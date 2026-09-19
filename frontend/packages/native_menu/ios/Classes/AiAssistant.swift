import Flutter
import UIKit
import Security
import ImageIO
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The native boundary for AI. Dart owns document/session history; each request
/// gets a fresh model session containing only the context Dart explicitly sends.
/// No prompt, response, attachment or API credential is written to a log here.
/// The plugin channel and request completions run on the main thread.
final class AiAssistant {
    private var requests: [String: Task<Void, Never>] = [:]
    private static let reservedResponseTokens = 1200
    private static let maxImageBytes = 20 * 1024 * 1024

    deinit {
        for task in requests.values { task.cancel() }
    }

    func handle(_ method: String, args: [String: Any], result: @escaping FlutterResult) {
        switch method {
        case "aiCapabilities": result(Self.capabilities())
        case "aiRespond": respond(args, result: result)
        case "aiCancel":
            guard let id = args["requestId"] as? String, let task = requests[id] else {
                result(false)
                return
            }
            // Keep the entry until completion, so a reused id cannot race its
            // predecessor's cleanup. Cancellation never switches providers.
            task.cancel()
            result(true)
        case "aiCredentialRead", "aiCredentialWrite", "aiCredentialDelete":
            Self.credential(method, args: args, result: result)
        case "aiClipboardImage": Self.clipboardImage(result: result)
        default: result(FlutterMethodNotImplemented)
        }
    }

    private static func unavailable(_ reason: String) -> [String: Any] {
        ["available": false, "route": "unavailable", "model": "Apple Intelligence",
         "supportsImages": false, "privateCloudComputeAvailable": false,
         "reason": reason, "contextTokens": 0, "maxInputBytes": 0]
    }

    static func capabilities() -> [String: Any] {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            // Xcode 27 ships Swift 6.4. The compiler gate also keeps these SDK
            // symbols out of builds made with the production Xcode 26 SDK.
            #if compiler(>=6.4)
            if #available(iOS 27.0, *) {
                let cloud = PrivateCloudComputeLanguageModel()
                if cloud.isAvailable && !cloud.quotaUsage.isLimitReached {
                    return capability(route: "privateCloudCompute",
                        model: "Apple Intelligence · Private Cloud Compute",
                        images: true, context: cloud.contextSize, cloud: true)
                }
            }
            #endif
            let model = SystemLanguageModel.default
            guard model.isAvailable else { return unavailable(localUnavailableReason()) }
            var images = false
            var context = 4096
            #if compiler(>=6.4)
            if #available(iOS 27.0, *) {
                images = true
                context = model.contextSize
            }
            #endif
            return capability(route: "onDevice", model: "Apple Intelligence · On device",
                              images: images, context: context, cloud: false)
        }
        #endif
        return unavailable("Apple Intelligence requires iPadOS 26 or later and a compatible device. You can also add an API key in AI settings.")
    }

    private static func inputByteLimit(_ context: Int) -> Int {
        // A conservative transport budget, NOT a token counter. The framework
        // still enforces its actual token limit; never silently trim a request.
        max(1024, min(96000, (context - reservedResponseTokens) * 2))
    }

    private static func capability(route: String, model: String, images: Bool,
                                   context: Int, cloud: Bool) -> [String: Any] {
        ["available": true, "route": route, "model": model,
         "supportsImages": images, "privateCloudComputeAvailable": cloud,
         "reason": "", "contextTokens": context, "maxInputBytes": inputByteLimit(context)]
    }

    private func respond(_ args: [String: Any], result: @escaping FlutterResult) {
        guard let id = args["requestId"] as? String, !id.isEmpty, id.count <= 128,
              let prompt = args["prompt"] as? String,
              !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            result(Self.error("ai_invalid_request", "A request identifier and a message are required."))
            return
        }
        guard requests.isEmpty else {
            result(Self.error("ai_busy", "Apple Intelligence is answering another request. Wait for it to finish or cancel it."))
            return
        }
        let instructions = args["instructions"] as? String ?? ""
        if args["imagePaths"] != nil && !(args["imagePaths"] is [String]) {
            result(Self.error("ai_invalid_request", "Image attachments must be local file paths."))
            return
        }
        let imagePaths = args["imagePaths"] as? [String] ?? []
        guard imagePaths.count <= 4, prompt.utf8.count + instructions.utf8.count <= 96000 else {
            result(Self.error("ai_request_too_large", "Use a shorter message and at most four images."))
            return
        }
        let capabilities = Self.capabilities()
        guard capabilities["available"] as? Bool == true else {
            result(Self.error("ai_unavailable", capabilities["reason"] as? String ?? "Apple Intelligence is unavailable."))
            return
        }
        guard imagePaths.isEmpty || capabilities["supportsImages"] as? Bool == true else {
            result(Self.error("ai_images_unsupported", "This Apple Intelligence build supports text only. Use an image-capable API provider, or a build with iPadOS 27 image support."))
            return
        }
        guard prompt.utf8.count + instructions.utf8.count <= (capabilities["maxInputBytes"] as? Int ?? 0) else {
            result(Self.error("ai_context_too_large", "This message and its session context are too large for the available Apple model. Start a shorter session or use an API provider with a larger context window."))
            return
        }
        do { try Self.validateImages(imagePaths) }
        catch let failure as Failure { result(Self.error(failure.code, failure.message)); return }
        catch { result(Self.error("ai_invalid_image", "An attached image could not be read.")); return }

        requests[id] = Task { @MainActor [weak self] in
            defer { self?.requests.removeValue(forKey: id) }
            do {
                try Task.checkCancellation()
                let response = try await Self.generate(instructions: instructions, prompt: prompt,
                                                       imagePaths: imagePaths)
                try Task.checkCancellation()
                result(response)
            } catch is CancellationError {
                result(Self.error("ai_cancelled", "The request was cancelled."))
            } catch let failure as Failure {
                result(Self.error(failure.code, failure.message))
            } catch {
                if Task.isCancelled {
                    result(Self.error("ai_cancelled", "The request was cancelled."))
                } else {
                    result(Self.modelError(error))
                }
            }
        }
    }

    private struct Failure: Error {
        let code: String
        let message: String
    }

    private static func error(_ code: String, _ message: String) -> FlutterError {
        FlutterError(code: code, message: message, details: nil)
    }

    private static func validateImages(_ paths: [String]) throws {
        var total = 0
        for path in paths {
            let url = URL(fileURLWithPath: path)
            let info = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard info.isRegularFile == true, let size = info.fileSize, size > 0,
                  size <= maxImageBytes, total <= maxImageBytes - size else {
                throw Failure(code: "ai_image_too_large", message: "Attached images must total no more than 20 MB.")
            }
            total += size
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  CGImageSourceGetCount(source) > 0,
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                  let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
                  width.doubleValue > 0, height.doubleValue > 0,
                  width.doubleValue * height.doubleValue <= 64_000_000 else {
                throw Failure(code: "ai_invalid_image", message: "Use a valid image with no more than 64 megapixels.")
            }
        }
    }

    private static func generate(instructions: String, prompt: String,
                                 imagePaths: [String]) async throws -> [String: Any] {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            #if compiler(>=6.4)
            if #available(iOS 27.0, *) {
                return try await generateModern(instructions: instructions, prompt: prompt, imagePaths: imagePaths)
            }
            #endif
            guard SystemLanguageModel.default.isAvailable else {
                throw Failure(code: "ai_unavailable", message: localUnavailableReason())
            }
            let session = LanguageModelSession(instructions: instructions)
            // A hard maximumResponseTokens silently truncates without an error.
            // Let the framework finish naturally or report context exhaustion.
            let reply = try await session.respond(to: prompt)
            return ["text": reply.content, "route": "onDevice", "model": "Apple Intelligence · On device"]
        }
        #endif
        throw Failure(code: "ai_unavailable", message: "Apple Intelligence is unavailable on this device.")
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func localUnavailableReason() -> String {
        switch SystemLanguageModel.default.availability {
        case .available: return ""
        case .unavailable(.deviceNotEligible):
            return "This device does not support Apple Intelligence. Add an API key to use AI here."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in the device Settings, or add an API key."
        case .unavailable(.modelNotReady):
            return "The Apple Intelligence model is not ready yet. Let its download finish, then try again."
        case .unavailable:
            return "Apple Intelligence is currently unavailable. Check its settings and try again, or add an API key."
        @unknown default:
            return "Apple Intelligence is currently unavailable."
        }
    }

    #if compiler(>=6.4)
    @available(iOS 27.0, *)
    private static func generateModern(instructions: String, prompt: String,
                                       imagePaths: [String]) async throws -> [String: Any] {
        let input = Prompt {
            prompt
            for (index, path) in imagePaths.enumerated() {
                Attachment(imageURL: URL(fileURLWithPath: path)).label("reference-\(index + 1)")
            }
        }
        let options = GenerationOptions()
        let cloud = PrivateCloudComputeLanguageModel()
        var fallback = false
        // The framework enforces the managed PCC entitlement, region/device
        // eligibility, account state and quota. This plugin adds no entitlement.
        // There is no public API that forces the Cloud Pro model variant.
        if cloud.isAvailable && !cloud.quotaUsage.isLimitReached {
            do {
                let session = LanguageModelSession(model: cloud,
                    dynamicInstructions: Instructions(instructions))
                let reply = try await session.respond(to: input, options: options,
                    contextOptions: ContextOptions(reasoningLevel: .moderate))
                return ["text": reply.content, "route": "privateCloudCompute",
                        "model": "Apple Intelligence · Private Cloud Compute"]
            } catch {
                try Task.checkCancellation()
                // Only an available local model can be a fallback. A fresh
                // session receives the same complete request; nothing is cut.
                guard isCloudInfrastructureFailure(error),
                      SystemLanguageModel.default.isAvailable else { throw error }
                fallback = true
            }
        }
        let local = SystemLanguageModel.default
        guard local.isAvailable else {
            throw Failure(code: "ai_unavailable", message: localUnavailableReason())
        }
        guard prompt.utf8.count + instructions.utf8.count <= inputByteLimit(local.contextSize) else {
            throw Failure(code: "ai_context_too_large", message: "Private Cloud Compute is unavailable and this request is too large for the on-device model. Shorten the session or use an API provider.")
        }
        let session = LanguageModelSession(model: local, instructions: instructions)
        let reply = try await session.respond(to: input, options: options)
        var response: [String: Any] = ["text": reply.content, "route": "onDevice",
                                      "model": "Apple Intelligence · On device"]
        if fallback { response["fallbackReason"] = "Private Cloud Compute could not complete this request; the on-device model answered." }
        return response
    }

    @available(iOS 27.0, *)
    private static func isCloudInfrastructureFailure(_ error: Error) -> Bool {
        guard let error = error as? PrivateCloudComputeLanguageModel.Error else { return false }
        switch error {
        case .quotaLimitReached, .networkFailure, .serviceUnavailable: return true
        @unknown default: return false
        }
    }
    #endif
    #endif

    private static func modelError(_ error: Error) -> FlutterError {
        #if canImport(FoundationModels)
        #if compiler(>=6.4)
        if #available(iOS 27.0, *), let modern = error as? LanguageModelError {
            switch modern {
            case .contextSizeExceeded:
                return self.error("ai_context_too_large", "The Apple model's context window is full. Shorten the message or session, or use an API provider with a larger context window.")
            case .guardrailViolation, .refusal:
                return self.error("ai_refused", "Apple Intelligence could not answer this request. Try rephrasing it.")
            case .unsupportedLanguageOrLocale:
                return self.error("ai_language_unsupported", "Apple Intelligence does not support this language or region on this device.")
            case .unsupportedCapability, .unsupportedTranscriptContent:
                return self.error("ai_content_unsupported", "The available Apple model cannot read this attachment or perform this request.")
            case .rateLimited:
                return self.error("ai_rate_limited", "Apple Intelligence is busy. Wait a moment, then try again.")
            case .timeout:
                return self.error("ai_timeout", "Apple Intelligence took too long to answer. Try again with a shorter request.")
            default: break
            }
        }
        #endif
        if #available(iOS 26.0, *), let error = error as? LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize:
                return self.error("ai_context_too_large", "The Apple model's context window is full. Shorten the message or session, or use an API provider with a larger context window.")
            case .guardrailViolation, .refusal:
                return self.error("ai_refused", "Apple Intelligence could not answer this request. Try rephrasing it.")
            case .unsupportedLanguageOrLocale:
                return self.error("ai_language_unsupported", "Apple Intelligence does not support this language or region on this device.")
            case .rateLimited, .concurrentRequests:
                return self.error("ai_rate_limited", "Apple Intelligence is busy. Wait a moment, then try again.")
            case .assetsUnavailable:
                return self.error("ai_unavailable", "The Apple Intelligence model is currently unavailable. Check its settings and try again.")
            default: break
            }
        }
        #endif
        // Do not serialize framework debug descriptions: they can contain
        // excerpts of the private conversation or the attached document.
        return self.error("ai_generation_failed", "Apple Intelligence could not complete the request. Try again with a shorter message, or use an API provider.")
    }

    private static func credential(_ method: String, args: [String: Any], result: FlutterResult) {
        guard let provider = args["provider"] as? String,
              provider.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$", options: .regularExpression) != nil else {
            result(error("ai_invalid_provider", "Choose a valid AI provider."))
            return
        }
        let service = (Bundle.main.bundleIdentifier ?? "prototype") + ".ai.credentials"
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: provider]
        if method == "aiCredentialRead" {
            var lookup = query
            lookup[kSecReturnData as String] = true
            lookup[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            let status = SecItemCopyMatching(lookup as CFDictionary, &item)
            if status == errSecItemNotFound { result(nil); return }
            guard status == errSecSuccess, let data = item as? Data,
                  let key = String(data: data, encoding: .utf8) else {
                result(error("ai_keychain_unavailable", "The API key could not be read from the secure storage. Unlock this device and try again."))
                return
            }
            result(key)
        } else if method == "aiCredentialDelete" {
            let status = SecItemDelete(query as CFDictionary)
            if status == errSecSuccess || status == errSecItemNotFound { result(true) }
            else { result(error("ai_keychain_unavailable", "The API key could not be removed from secure storage.")) }
        } else {
            guard let raw = args["key"] as? String else {
                result(error("ai_invalid_key", "Enter an API key.")); return
            }
            let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, key.utf8.count <= 16384 else {
                result(error("ai_invalid_key", "Enter a valid API key.")); return
            }
            let attributes: [String: Any] = [kSecValueData as String: Data(key.utf8),
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
            var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if status == errSecItemNotFound {
                var item = query
                attributes.forEach { item[$0.key] = $0.value }
                status = SecItemAdd(item as CFDictionary, nil)
            }
            if status == errSecSuccess { result(true) }
            else { result(error("ai_keychain_unavailable", "The API key could not be saved securely. Unlock this device and try again.")) }
        }
    }

    private static func clipboardImage(result: FlutterResult) {
        // Called only after a user explicitly invokes Paste. Never poll the
        // clipboard while opening a session or checking provider capabilities.
        guard let image = UIPasteboard.general.image else { result(nil); return }
        let pixels = image.size.width * image.scale * image.size.height * image.scale
        guard pixels > 0, pixels <= 64_000_000 else {
            result(error("ai_image_too_large", "Paste an image smaller than 20 MB and 64 megapixels."))
            return
        }
        // UIImage can carry a display orientation separately from its pixels.
        // Normalize it before PNG export so the provider sees the same image
        // the person pasted, including photos with EXIF rotation or mirroring.
        let normalized: UIImage
        if image.imageOrientation == .up { normalized = image }
        else {
            let format = UIGraphicsImageRendererFormat()
            format.scale = image.scale
            normalized = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: image.size))
            }
        }
        guard let data = normalized.pngData(), data.count <= maxImageBytes else {
            result(error("ai_image_too_large", "Paste an image smaller than 20 MB."))
            return
        }
        result(["bytes": FlutterStandardTypedData(bytes: data),
                "mimeType": "image/png", "name": "Pasted image.png"])
    }
}
