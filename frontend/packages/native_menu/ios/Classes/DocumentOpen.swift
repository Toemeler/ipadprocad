// M177 — opening a document IN PLACE, and getting back to it next launch.
//
// WHY THIS EXISTS
// ---------------
// The standard Flutter file picker opens a UIDocumentPickerViewController in
// .import mode, which hands the app a COPY in NSTemporaryDirectory(). That is
// right for importing a STEP, and wrong for opening one of our own documents:
// the user picks Bracket.ptp from iCloud, edits it, saves — and the edits go
// into a temporary copy the system deletes. The file they opened never
// changes. A document app that does that cannot be trusted with anything.
//
// So Open uses .open mode (forOpeningContentTypes:), which grants access to
// the ORIGINAL file. Two consequences the caller has to live with:
//
//   * the grant is security-scoped. Every read and write has to happen between
//     startAccessingSecurityScopedResource() and its stop. We start on pick or
//     on resolve and hold it for the session, which is what a document that
//     stays open in a tab actually needs.
//   * the grant does not survive relaunch, and neither does the path — the
//     user can move or rename the file in Files between launches. A BOOKMARK
//     survives both. Dart stores it beside the document and hands it back on
//     the next launch to find the file again, wherever it went.
import Flutter
import UIKit
import UniformTypeIdentifiers

/// The open-in-place picker and its bookmarks.
///
/// Held by NativeMenuPlugin, which forwards the three method calls. Separate
/// from the plugin because it owns a picker delegate and a set of live
/// security scopes, and neither belongs in the context-menu code.
@available(iOS 14.0, *)
class DocumentOpener: NSObject, UIDocumentPickerDelegate {
    /// Security scopes we have started and not yet stopped, by path.
    private var scopes: [String: URL] = [:]
    private var pending: FlutterResult?
    /// Kept alive while presented — UIKit holds the delegate weakly.
    private var picker: UIDocumentPickerViewController?

    /// Supplied by the plugin, so the popover-anchor and key-window handling
    /// that the context menu and share sheet already rely on is used here too
    /// rather than written a second time. Returns false when there is nothing
    /// to present from.
    private let presenter: (UIViewController, CGRect?) -> Bool

    init(presenter: @escaping (UIViewController, CGRect?) -> Bool) {
        self.presenter = presenter
        super.init()
    }

    // MARK: - Picking

    /// Presents the system picker restricted to [extensions], in OPEN mode.
    func present(extensions: [String], anchor: CGRect?, result: @escaping FlutterResult) {
        // Only one picker at a time; a second tap must not orphan the first
        // call, which would leave Dart awaiting a Future that never completes.
        if pending != nil {
            result(nil)
            return
        }
        // M232 — an extension the system has no declared type for (3mf is the
        // one that matters, and .stl and .obj are not guaranteed either) yields
        // nil here. compactMap would quietly drop it, and the file would then
        // be greyed out in the picker with nothing to explain why. When any
        // requested extension fails to resolve, widen the filter to plain data
        // so the file can at least be chosen; Dart checks the extension again
        // on the way in (openActionFor) and says so plainly if it is not one we
        // handle. A loose picker beats an unopenable file.
        var types = extensions.compactMap { UTType(filenameExtension: $0) }
        if types.count < extensions.count { types.append(UTType.data) }
        if types.isEmpty { types = [UTType.data] }

        let vc = UIDocumentPickerViewController(forOpeningContentTypes: types,
                                                asCopy: false)
        vc.allowsMultipleSelection = false
        vc.delegate = self
        pending = result
        picker = vc
        if !presenter(vc, anchor) {
            pending = nil
            picker = nil
            result(nil)
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController,
                        didPickDocumentsAt urls: [URL]) {
        defer { picker = nil }
        guard let result = pending else { return }
        pending = nil
        guard let url = urls.first else {
            result(nil)
            return
        }
        result(adopt(url))
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        picker = nil
        let result = pending
        pending = nil
        result?(nil)
    }

    // MARK: - Bookmarks

    /// Starts access to [url] and returns {path, bookmark} for Dart.
    ///
    /// A bookmark that cannot be created is NOT a failure to open: the file is
    /// reachable right now, and one session of editing is better than none.
    /// Dart treats a missing bookmark as "this one will not come back after a
    /// relaunch", which is honest and still useful.
    private func adopt(_ url: URL) -> [String: Any]? {
        let started = url.startAccessingSecurityScopedResource()
        if started { scopes[url.path] = url }
        var out: [String: Any] = ["path": url.path]
        if let data = try? url.bookmarkData(options: .minimalBookmark,
                                            includingResourceValuesForKeys: nil,
                                            relativeTo: nil) {
            out["bookmark"] = data.base64EncodedString()
        }
        return out
    }

    /// Re-acquires access to a document remembered from an earlier launch.
    ///
    /// Returns its CURRENT path, which may differ from the one stored: that is
    /// the whole point of a bookmark. A stale bookmark is refreshed and handed
    /// back so the stored copy stops decaying.
    func resolve(bookmark: String) -> [String: Any]? {
        guard let data = Data(base64Encoded: bookmark) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data,
                                 options: [],
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else {
            return nil
        }
        let started = url.startAccessingSecurityScopedResource()
        if started { scopes[url.path] = url }
        var out: [String: Any] = ["path": url.path]
        if stale,
           let fresh = try? url.bookmarkData(options: .minimalBookmark,
                                             includingResourceValuesForKeys: nil,
                                             relativeTo: nil) {
            out["bookmark"] = fresh.base64EncodedString()
        }
        return out
    }

    /// Ends access to a document the app is done with.
    func release(path: String) {
        guard let url = scopes.removeValue(forKey: path) else { return }
        url.stopAccessingSecurityScopedResource()
    }

    /// Ends every live scope — for app teardown.
    func releaseAll() {
        for (_, url) in scopes { url.stopAccessingSecurityScopedResource() }
        scopes.removeAll()
    }
}
