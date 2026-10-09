import Flutter
import UIKit
import WebKit

/// Uses the website's persistent cookie store, without exporting credentials
/// across the method channel or maintaining a second login implementation.
final class GrabCadBridge {
    private var login: GrabCadLoginController?
    private var download: GrabCadDownload?
    private var requests: [String: GrabCadMetadataRequest] = [:]
    private var csrfToken: String?
    private var events: [[String: Any]] = []
    private var droppedEvents = 0

    private func record(_ event: String, _ fields: [String: Any] = [:]) {
        if events.count == 300 { events.removeFirst(); droppedEvents += 1 }
        var entry = fields
        entry["event"] = event
        entry["time"] = ISO8601DateFormatter().string(from: Date())
        events.append(entry)
    }
    func diagnostics() -> [String: Any] {
        return ["schemaVersion": 1, "events": events, "droppedEvents": droppedEvents,
                "loginActive": login != nil, "downloadActive": download != nil,
                "metadataRequestsActive": requests.count]
    }

    func request(args: [String: Any], result: @escaping FlutterResult) {
        guard let id = args["id"] as? String, requests[id] == nil,
              let path = args["path"] as? String,
              path == "models" || path.hasPrefix("models/"),
              let url = URL(string: "https://grabcad.com/community/api/v1/" + path),
              url.scheme == "https", url.host == "grabcad.com",
              url.path.hasPrefix("/community/api/v1/models") else {
            result(FlutterError(code: "invalid_request", message: nil, details: nil)); return
        }
        let body = args["body"] as? String
        guard body == nil || (path == "models" && body!.utf8.count <= 65536) else {
            result(FlutterError(code: "invalid_request", message: nil, details: nil)); return
        }
        let started = Date()
        record("metadata.start", ["path": url.path, "method": body == nil ? "GET" : "POST"])
        let job = GrabCadMetadataRequest(url: url, body: body, csrfToken: csrfToken,
            diagnostic: { [weak self] event, fields in self?.record(event, fields) }) { [weak self] response in
            var fields: [String: Any] = ["path": url.path,
                "elapsedMs": Int(Date().timeIntervalSince(started) * 1000)]
            if let error = response as? FlutterError { fields["errorCode"] = error.code }
            if let value = response as? [String: Any] { fields["status"] = value["status"] }
            self?.record("metadata.finish", fields)
            self?.requests.removeValue(forKey: id)
            result(response)
        }
        requests[id] = job
        job.start()
    }

    func cancelRequests(_ ids: [String]) {
        for id in ids { requests[id]?.cancel() }
    }

    func signIn(args: [String: Any], result: @escaping FlutterResult,
                present: (UIViewController, @escaping () -> Void) -> Void) {
        guard login == nil else { result(false); return }
        record("login.present")
        let controller = GrabCadLoginController(args: args,
            diagnostic: { [weak self] event, fields in self?.record(event, fields) }) { [weak self] success, token in
            self?.record("login.finish", ["authenticated": success])
            self?.login = nil
            if success { self?.csrfToken = token }
            result(success)
        }
        login = controller
        let nav = UINavigationController(rootViewController: controller)
        nav.modalPresentationStyle = .formSheet
        nav.presentationController?.delegate = controller
        present(nav) { controller.finish(false) }
    }

    func startDownload(args: [String: Any], result: @escaping FlutterResult) {
        guard download == nil else {
            result(FlutterError(code: "busy", message: nil, details: nil)); return
        }
        guard let value = args["url"] as? String, let url = URL(string: value),
              url.scheme == "https", url.host == "grabcad.com",
              url.user == nil, url.password == nil,
              url.port == nil || url.port == 443,
              let name = args["name"] as? String, !name.isEmpty,
              name == (name as NSString).lastPathComponent,
              !name.contains("\\"), !name.contains("\0") else {
            result(FlutterError(code: "invalid_download", message: nil, details: nil)); return
        }
        let started = Date()
        record("download.start", ["path": url.path, "name": name])
        let job = GrabCadDownload(url: url, name: name,
            diagnostic: { [weak self] event, fields in self?.record(event, fields) }) { [weak self] value in
            var fields: [String: Any] = ["elapsedMs": Int(Date().timeIntervalSince(started) * 1000)]
            if let error = value as? FlutterError { fields["errorCode"] = error.code }
            fields["success"] = value is String
            self?.record("download.finish", fields)
            self?.download = nil
            result(value)
        }
        download = job
        job.start()
    }

    func cancelDownload() { download?.cancel() }
}

/// All metadata requests use the website cookie store, just like downloads.
/// No Cookie headers or account details are returned to Dart or logged.
private final class GrabCadMetadataRequest: NSObject, URLSessionTaskDelegate {
    private let url: URL
    private let body: String?
    private let csrfToken: String?
    private var completion: ((Any?) -> Void)?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var cancelled = false
    private let diagnostic: (String, [String: Any]) -> Void

    init(url: URL, body: String?, csrfToken: String?, diagnostic: @escaping (String, [String: Any]) -> Void, completion: @escaping (Any?) -> Void) {
        self.url = url; self.body = body; self.csrfToken = csrfToken; self.completion = completion
        self.diagnostic = diagnostic
    }
    func start() {
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self = self else { return }
            if self.cancelled { self.finish(error: "cancelled"); return }
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 20
            config.timeoutIntervalForResource = 30
            for cookie in cookies where cookie.domain == "grabcad.com" ||
                cookie.domain == ".grabcad.com" {
                config.httpCookieStorage?.setCookie(cookie)
            }
            var request = URLRequest(url: self.url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let token = self.csrfToken {
                request.setValue(token, forHTTPHeaderField: "X-CSRF-Token")
            }
            if let body = self.body {
                request.httpMethod = "POST"
                request.httpBody = body.data(using: .utf8)
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            let session = URLSession(configuration: config, delegate: self,
                                     delegateQueue: OperationQueue.main)
            self.session = session
            let task = session.dataTask(with: request) { [weak self] data, response, error in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if self.cancelled { self.finish(error: "cancelled"); return }
                    if let error = error as? URLError {
                        self.diagnostic("metadata.networkError", ["domain": NSURLErrorDomain, "code": error.errorCode])
                        self.finish(error: error.code == .timedOut ? "timeout" : "unavailable"); return
                    }
                    guard error == nil, let response = response as? HTTPURLResponse,
                          let data = data, data.count <= 8 * 1024 * 1024,
                          let text = String(data: data, encoding: .utf8) else {
                        self.finish(error: "unavailable"); return
                    }
                    self.finish(value: ["status": response.statusCode,
                                        "body": text,
                                        "contentType": response.mimeType ?? ""])
                }
            }
            self.task = task
            task.resume()
        }
    }
    func cancel() { cancelled = true; task?.cancel() }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme == "https" &&
            request.url?.host == "grabcad.com" ? request : nil)
    }
    private func finish(error: String) {
        finish(value: FlutterError(code: error, message: nil, details: nil))
    }
    private func finish(value: Any?) {
        guard let callback = completion else { return }
        completion = nil
        session?.invalidateAndCancel()
        session = nil
        callback(value)
    }
}

private final class GrabCadLoginController: UIViewController,
    WKNavigationDelegate, UIAdaptivePresentationControllerDelegate {
    private let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    private let args: [String: Any]
    private var completion: ((Bool, String?) -> Void)?
    private var csrfToken: String?
    private var checking = false
    private let note = UILabel()
    private let diagnostic: (String, [String: Any]) -> Void

    init(args: [String: Any], diagnostic: @escaping (String, [String: Any]) -> Void, completion: @escaping (Bool, String?) -> Void) {
        self.args = args
        self.diagnostic = diagnostic
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = args["title"] as? String
        view.backgroundColor = .systemBackground
        note.text = args["help"] as? String
        note.textColor = .secondaryLabel
        note.numberOfLines = 0
        note.font = .preferredFont(forTextStyle: .footnote)
        note.translatesAutoresizingMaskIntoConstraints = false
        web.translatesAutoresizingMaskIntoConstraints = false
        web.navigationDelegate = self
        view.addSubview(note)
        view.addSubview(web)
        NSLayoutConstraint.activate([
            note.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            note.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            note.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            web.topAnchor.constraint(equalTo: note.bottomAnchor, constant: 12),
            web.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            web.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: args["cancel"] as? String, style: .plain,
            target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: args["done"] as? String, style: .done,
            target: self, action: #selector(checkLogin))
        web.load(URLRequest(url: URL(string: "https://grabcad.com/login")!))
    }

    @objc private func cancel() { finish(false) }

    @objc private func checkLogin() {
        guard !checking, web.url?.host == "grabcad.com" else { return }
        checking = true
        // Fetch runs in the website's origin, with its own cookies. Only the
        // authentication result and CSRF token stay native; the member payload
        // is not returned to Dart or logged.
        web.callAsyncJavaScript("""
            const r = await fetch('/community/api/v1/members/me', {credentials: 'same-origin'});
            if (!r.ok || r.status === 204) return {authenticated: false};
            const data = await r.json();
            return {
                authenticated: !!(data && (data.id || (data.member && data.member.id))),
                csrfToken: document.querySelector('meta[name="csrf-token"]')?.content || null
            };
            """, arguments: [:], in: nil, in: .page) { [weak self] result in
                guard let self = self else { return }
                self.checking = false
                if case .failure(let error) = result {
                    let native = error as NSError
                    self.diagnostic("login.sessionCheckError", ["domain": native.domain, "code": native.code])
                }
                if case .success(let value) = result,
                   let payload = value as? [String: Any],
                   payload["authenticated"] as? Bool == true {
                    self.csrfToken = payload["csrfToken"] as? String
                    self.finish(true)
                } else if case .success = result {
                    self.diagnostic("login.sessionUnauthenticated", [:])
                }
            }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Query strings and fragments may contain login tokens: exclude them.
        diagnostic("login.navigationFinished", ["host": webView.url?.host ?? "", "path": webView.url?.path ?? ""])
        checkLogin()
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navigationFailed(error)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationFailed(error)
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        diagnostic("login.webContentTerminated", [:])
    }
    private func navigationFailed(_ error: Error) {
        let native = error as NSError
        diagnostic("login.navigationError", ["domain": native.domain, "code": native.code])
    }
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        finish(false)
    }
    func finish(_ success: Bool) {
        guard let callback = completion else { return }
        completion = nil
        if let nav = navigationController, nav.presentingViewController != nil {
            nav.dismiss(animated: true) { callback(success, self.csrfToken) }
        } else { callback(success, csrfToken) }
    }
}

private final class GrabCadDownload: NSObject, URLSessionDownloadDelegate {
    private let url: URL
    private let name: String
    private var completion: ((Any?) -> Void)?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var failure: String?
    private var cancelled = false
    private let diagnostic: (String, [String: Any]) -> Void
    private let limit: Int64 = 250 * 1024 * 1024

    init(url: URL, name: String, diagnostic: @escaping (String, [String: Any]) -> Void, completion: @escaping (Any?) -> Void) {
        self.url = url; self.name = name; self.completion = completion
        self.diagnostic = diagnostic
    }
    func start() {
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self = self else { return }
            if self.cancelled { self.finish(error: "cancelled"); return }
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 30
            config.timeoutIntervalForResource = 300
            // Cookie storage enforces domain/path scoping on redirects. Never
            // put a Cookie header on a request that could redirect to a CDN.
            for cookie in cookies where cookie.domain == "grabcad.com" ||
                cookie.domain == ".grabcad.com" {
                config.httpCookieStorage?.setCookie(cookie)
            }
            let session = URLSession(configuration: config, delegate: self,
                                     delegateQueue: OperationQueue.main)
            self.session = session
            self.task = session.downloadTask(with: self.url)
            self.task?.resume()
        }
    }
    func cancel() { cancelled = true; task?.cancel() }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard request.url?.scheme == "https" else {
            failure = "invalid_download"; completionHandler(nil); return
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > limit || totalBytesExpectedToWrite > limit {
            failure = "too_large"; downloadTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard !cancelled else { finish(error: "cancelled"); return }
        guard let response = downloadTask.response as? HTTPURLResponse else {
            finish(error: "invalid_download"); return
        }
        diagnostic("download.response", ["status": response.statusCode, "contentType": response.mimeType ?? "", "expectedBytes": response.expectedContentLength])
        if response.statusCode == 401 || response.statusCode == 403 {
            finish(error: "sign_in_required"); return
        }
        let type = response.mimeType ?? ""
        guard response.statusCode == 200, !type.contains("text/html"),
              !type.contains("application/json") else {
            finish(error: "invalid_download"); return
        }
        let fm = FileManager.default
        var directory: URL?
        do {
            let size = try fm.attributesOfItem(atPath: location.path)[.size] as? NSNumber
            guard let count = size?.int64Value, count > 0, count <= limit else {
                finish(error: "invalid_download"); return
            }
            diagnostic("download.received", ["bytes": count])
            let folder = fm.temporaryDirectory.appendingPathComponent("grabcad_" + UUID().uuidString)
            directory = folder
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent(name)
            try fm.moveItem(at: location, to: file)
            finish(value: file.path)
        } catch {
            if let folder = directory { try? fm.removeItem(at: folder) }
            finish(error: "invalid_download")
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if completion != nil {
            if let error = error {
                let native = error as NSError
                diagnostic("download.networkError", ["domain": native.domain, "code": native.code])
            }
            finish(error: failure ?? (cancelled ? "cancelled" : "unavailable"))
        }
    }
    private func finish(error: String) {
        finish(value: FlutterError(code: error, message: nil, details: nil))
    }
    private func finish(value: Any?) {
        guard let callback = completion else { return }
        completion = nil
        session?.invalidateAndCancel()
        session = nil
        callback(value)
    }
}
