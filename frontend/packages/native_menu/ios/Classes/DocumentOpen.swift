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
        // UIDocumentPickerViewController requires a NON-EMPTY array of
        // UNIQUE content types, and raises an Objective-C exception when it
        // does not get one. That exception cannot be caught from Swift: it
        // takes the whole app down, before any Dart code runs and therefore
        // with nothing in the app's own log to say why.
        //
        // Both preconditions are easy to break here, and this list broke both:
        //
        //   DUPLICATES. "step" and "stp" are two spellings of ONE format, so
        //   UTType(filenameExtension:) hands back the same type for each and
        //   the array holds it twice. Nothing about the call site suggests
        //   that; it looks like eight different kinds of file.
        //
        //   MIXING. An extension the system has no declared type for — 3mf is
        //   the one that matters, and stl and obj are not guaranteed either —
        //   resolves to nil and is dropped, which would leave that file greyed
        //   out in the picker with no explanation. Widening to plain data is
        //   the right answer, but it has to REPLACE the list rather than join
        //   it: public.data already contains every one of those types, so
        //   appending it adds nothing except a chance to break the rule above.
        //
        // Dart re-checks the extension on the way in (openActionFor) and says
        // so plainly when it is not one we handle, so a loose picker costs
        // nothing. What follows is always non-empty and always unique.
        var seenIds = Set<String>()
        var types: [UTType] = []
        var unresolved: [String] = []
        for ext in extensions {
            let t = UTType(filenameExtension: ext)
            // A DYNAMIC identifier is the trap, and it is not the same thing
            // as nil. For an extension nothing on the system declares, iOS
            // does not fail — it invents `dyn.ah62d4...`, a placeholder that
            // stands for "some file called .stl" and that matches no real
            // file. The app's own Info.plist says as much about ptp/pts
            // (M177): "without the declaration UTType(filenameExtension:)
            // only yields a dynamic identifier, which the open-in-place
            // picker will not match on."
            //
            // So `guard let` is not enough — it never fires — and a dynamic
            // type handed to UIDocumentPickerViewController is worse than
            // useless. M232 added stl, obj and 3mf, none of them declared,
            // and Open stopped surviving the tap.
            guard let t = t, !t.identifier.hasPrefix("dyn.") else {
                unresolved.append(ext)
                continue
            }
            if seenIds.insert(t.identifier).inserted { types.append(t) }
        }
        if !unresolved.isEmpty || types.isEmpty {
            types = [UTType.data]
        }
        // Console-only; the Dart log brackets this call from the other side.
        NSLog("[native_menu] open picker: asked %@, resolved %@, undeclared %@",
              extensions.joined(separator: ","),
              types.map { $0.identifier }.joined(separator: ","),
              unresolved.joined(separator: ","))

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
