import Flutter
import UIKit
import WebKit

/// Uses the website's persistent cookie store, without exporting credentials
/// across the method channel or maintaining a second login implementation.
final class GrabCadBridge {
    private var login: GrabCadLoginController?
    private var download: GrabCadDownload?

    func signIn(args: [String: Any], result: @escaping FlutterResult,
                present: (UIViewController, @escaping () -> Void) -> Void) {
        guard login == nil else { result(false); return }
        let controller = GrabCadLoginController(args: args) { [weak self] success in
            self?.login = nil
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
        let job = GrabCadDownload(url: url, name: name) { [weak self] value in
            self?.download = nil
            result(value)
        }
        download = job
        job.start()
    }

    func cancelDownload() { download?.cancel() }
}

private final class GrabCadLoginController: UIViewController,
    WKNavigationDelegate, UIAdaptivePresentationControllerDelegate {
    private let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    private let args: [String: Any]
    private var completion: ((Bool) -> Void)?
    private var checking = false
    private let note = UILabel()

    init(args: [String: Any], completion: @escaping (Bool) -> Void) {
        self.args = args
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
        // boolean result leaves WebKit; do not log or read the member payload.
        web.callAsyncJavaScript("""
            const r = await fetch('/community/api/v1/members/me', {credentials: 'same-origin'});
            if (!r.ok) return false;
            const data = await r.json();
            return !!(data && (data.id || (data.member && data.member.id)));
            """, arguments: [:], in: nil, in: .page) { [weak self] result in
                guard let self = self else { return }
                self.checking = false
                if case .success(let value) = result, value as? Bool == true {
                    self.finish(true)
                }
            }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { checkLogin() }
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        finish(false)
    }
    func finish(_ success: Bool) {
        guard let callback = completion else { return }
        completion = nil
        if let nav = navigationController, nav.presentingViewController != nil {
            nav.dismiss(animated: true) { callback(success) }
        } else { callback(success) }
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
    private let limit: Int64 = 250 * 1024 * 1024

    init(url: URL, name: String, completion: @escaping (Any?) -> Void) {
        self.url = url; self.name = name; self.completion = completion
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
