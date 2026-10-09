import Flutter
import Foundation
import Network
import WebKit

/// Full Python + build123d + OCP.wasm in a local WebKit worker. The loopback
/// listener serves ONLY signed bundle assets; it is not a modelling backend.
/// A random route and same-origin policy isolate it from other local clients.
final class LocalBuild123d: NSObject, FlutterPlugin, FlutterStreamHandler,
                           WKScriptMessageHandler, WKNavigationDelegate {
    private let registrar: FlutterPluginRegistrar
    private var sink: FlutterEventSink?
    private var webView: WKWebView?
    private var server: CadAssetServer?
    private var active: String?
    private var pending: (String, [String: Any], FlutterResult)?
    private var ready = false
    private var deadline: Timer?

    init(registrar: FlutterPluginRegistrar) { self.registrar = registrar }

    static func register(with registrar: FlutterPluginRegistrar) {
        let plugin = LocalBuild123d(registrar: registrar)
        let methods = FlutterMethodChannel(name: "prototype/build123d", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(plugin, channel: methods)
        let events = FlutterEventChannel(name: "prototype/build123d/events", binaryMessenger: registrar.messenger())
        events.setStreamHandler(plugin)
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events
        return nil
    }
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        if active != nil { cancel() }
        sink = nil
        return nil
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any], let id = args["id"] as? String else {
            result(FlutterError(code: "arguments", message: "Invalid local CAD request", details: nil)); return
        }
        if call.method == "cancel" {
            if id == active { cancel() }
            result(nil); return
        }
        guard call.method == "run", let job = args["job"] as? [String: Any] else {
            result(FlutterMethodNotImplemented); return
        }
        guard active == nil, sink != nil else {
            result(FlutterError(code: "busy", message: "Local CAD is busy or event channel is unavailable", details: nil)); return
        }
        guard let code = job["code"] as? String, !code.isEmpty, code.utf8.count <= 100000,
              JSONSerialization.isValidJSONObject(job),
              let data = try? JSONSerialization.data(withJSONObject: job), data.count <= 16 * 1024 * 1024 else {
            result(FlutterError(code: "size", message: "Invalid or oversized local CAD script", details: nil)); return
        }
        active = id
        pending = (id, job, result)
        deadline = Timer.scheduledTimer(withTimeInterval: 160, repeats: false) { [weak self] _ in
            self?.fail("Local CAD runtime timed out")
        }
        if ready { startPending(); return }
        if webView != nil { return }
        do {
            guard let root = assetRoot(), FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest.json").path) else {
                throw CadRuntimeError.missingBundle
            }
            let server = try CadAssetServer(root: root)
            self.server = server
            server.start { [weak self, weak server] url in
                DispatchQueue.main.async {
                    guard let self = self, let server = server, self.server === server else { return }
                    self.openRuntime(url)
                }
            }
        } catch { fail("Offline build123d bundle is missing. Rebuild the app with tools/modelling/bundle_runtime.py.") }
    }

    private func assetRoot() -> URL? {
        let key = registrar.lookupKey(forAsset: "assets/modelling/index.html")
        let roots = [Bundle.main.bundleURL,
                     Bundle.main.bundleURL.appendingPathComponent("Frameworks/App.framework")]
        for root in roots {
            let file = root.appendingPathComponent(key)
            if FileManager.default.fileExists(atPath: file.path) { return file.deletingLastPathComponent() }
        }
        return nil
    }

    private func openRuntime(_ url: URL) {
        guard active != nil else { return }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(self, name: "cadRuntime")
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = self
        webView = view
        view.load(URLRequest(url: url))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView else { return }
        ready = true
        startPending()
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard webView === self.webView else { return }
        fail("Local CAD page could not load")
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard webView === self.webView else { return }
        fail("Local CAD runtime could not start")
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === self.webView else { return }
        fail("Local CAD process ran out of memory or stopped; simplify the model and retry")
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, server?.owns(url) == true else {
            decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }

    private func startPending() {
        guard ready, let (id, job, result) = pending,
              let data = try? JSONSerialization.data(withJSONObject: [id, job]),
              let arguments = String(data: data, encoding: .utf8) else { return }
        pending = nil
        webView?.evaluateJavaScript("window.cadRun(...\(arguments))") { [weak self] _, error in
            guard self?.active == id else { result(nil); return }
            if let error = error {
                result(FlutterError(code: "runtime", message: "Could not start local CAD: \(error.localizedDescription)", details: nil))
                self?.fail("Could not start local CAD")
            } else { result(nil) }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let payload = message.body as? [String: Any],
              let id = payload["id"] as? String, id == active,
              let event = payload["event"] as? [String: Any], let type = event["type"] as? String,
              ["preview", "complete", "error"].contains(type),
              let data = try? JSONSerialization.data(withJSONObject: payload), data.count <= 17 * 1024 * 1024 else { return }
        sink?(payload)
        if type != "preview" {
            deadline?.invalidate(); deadline = nil
            active = nil
        }
    }

    private func fail(_ message: String) {
        if let id = active { sink?(["id": id, "event": ["type": "error", "error": message, "fatal": true]]) }
        if let (_, _, result) = pending {
            result(FlutterError(code: "runtime", message: message, details: nil))
        }
        pending = nil
        disposeRuntime()
    }
    private func cancel() {
        if let id = active { sink?(["id": id, "event": ["type": "error", "error": "Local CAD cancelled"]]) }
        if let (_, _, result) = pending { result(nil) }
        pending = nil
        // Destroying the WebView kills even a native WASM operation stuck in
        // OCCT, without blocking Flutter or leaving preview geometry behind.
        disposeRuntime()
    }
    private func disposeRuntime() {
        deadline?.invalidate(); deadline = nil
        active = nil; ready = false
        webView?.stopLoading()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "cadRuntime")
        webView = nil
        server?.stop(); server = nil
    }
}

private enum CadRuntimeError: Error { case missingBundle }

/// Static files under one signed asset directory; no arbitrary files, methods,
/// model inputs or paths. A Web Worker needs HTTP origin semantics in WKWebView.
private final class CadAssetServer {
    private let root: URL
    private let route = UUID().uuidString + "/"
    private let listener: NWListener
    private let queue = DispatchQueue(label: "prototype.cad.assets")
    private var base: URL?

    init(root: URL) throws {
        self.root = root
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: params)
    }
    func owns(_ url: URL) -> Bool {
        guard let base = base else { return false }
        return url.scheme == base.scheme && url.host == base.host && url.port == base.port &&
            url.path.hasPrefix(base.path)
    }
    func start(_ ready: @escaping (URL) -> Void) {
        listener.stateUpdateHandler = { [weak self] state in
            guard let self = self, case .ready = state, let port = self.listener.port else { return }
            let base = URL(string: "http://127.0.0.1:\(port.rawValue)/\(self.route)")!
            self.base = base
            ready(base.appendingPathComponent("index.html"))
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self = self else { connection.cancel(); return }
            connection.start(queue: self.queue)
            self.read(connection, buffered: Data())
        }
        listener.start(queue: queue)
    }
    func stop() { listener.cancel() }
    private func read(_ connection: NWConnection, buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
            guard let self = self, error == nil else { connection.cancel(); return }
            var buffer = buffered
            if let data = data { buffer.append(data) }
            if buffer.count > 8192 { connection.cancel(); return }
            if let text = String(data: buffer, encoding: .utf8), text.contains("\r\n\r\n") {
                self.respond(connection, request: text)
            } else if !complete { self.read(connection, buffered: buffer) }
            else { connection.cancel() }
        }
    }
    private func respond(_ connection: NWConnection, request: String) {
        let fields = (request.components(separatedBy: "\r\n").first ?? "").split(separator: " ")
        guard fields.count == 3, fields[0] == "GET", fields[1].hasPrefix("/" + route) else {
            connection.cancel(); return
        }
        let name = String(fields[1].dropFirst(route.count + 1))
        guard !name.isEmpty, !name.contains("/"), !name.contains("\\"), !name.contains("%"),
              !name.contains(".."), !name.contains("?"),
              let data = try? Data(contentsOf: root.appendingPathComponent(name), options: .mappedIfSafe) else {
            let response = Data("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
            connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() }); return
        }
        let ext = (name as NSString).pathExtension
        let mime = ["html":"text/html", "js":"application/javascript", "wasm":"application/wasm",
                    "json":"application/json", "py":"text/plain" ][ext] ?? "application/octet-stream"
        let csp = "default-src 'none'; script-src 'self' 'unsafe-eval' 'wasm-unsafe-eval'; worker-src 'self'; connect-src 'self'; style-src 'none'; img-src 'none'"
        let headers = "HTTP/1.1 200 OK\r\nContent-Type: \(mime)\r\nContent-Length: \(data.count)\r\nConnection: close\r\nCache-Control: private, max-age=31536000, immutable\r\nContent-Security-Policy: \(csp)\r\nCross-Origin-Resource-Policy: same-origin\r\nX-Content-Type-Options: nosniff\r\n\r\n"
        connection.send(content: Data(headers.utf8), completion: .contentProcessed { error in
            guard error == nil else { connection.cancel(); return }
            connection.send(content: data, completion: .contentProcessed { _ in connection.cancel() })
        })
    }
}
