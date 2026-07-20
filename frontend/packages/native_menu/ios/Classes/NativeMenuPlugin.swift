// iPadProCAD — real UIKit context menus for Flutter content.
//
// HOW THIS WORKS (and why it is not a platform view)
// --------------------------------------------------
// Flutter draws everything into ONE UIView. Wrapping each gallery card in a
// UiKitView would cost a platform view per card and still leave the preview
// blank (the card pixels belong to Flutter, not to the native view).
//
// Instead a single UIContextMenuInteraction is attached to the FlutterView
// itself. Dart continuously publishes the hit rectangles of the cards that
// currently want a menu; when UIKit asks for a configuration at a point we
// look the point up in that list and hand back a real UIMenu. If the point
// misses every rect we return nil and UIKit forwards the touch to Flutter
// untouched — so nothing outside the gallery changes behaviour.
//
// The interaction is only ATTACHED while there is at least one target. Leaving
// the Home tab pushes an empty list, which removes it entirely: the CAD
// viewport's own long-press/drag handling can never be shadowed by this.
//
// The lifted preview is the sketch's existing 380x240 preview PNG (the same
// file the Flutter card renders), so no snapshotting of the Metal layer is
// required — that is unreliable under Impeller.
import Flutter
import UIKit

public class NativeMenuPlugin: NSObject, FlutterPlugin {
    private struct Item {
        let id: String
        let title: String
        let symbol: String?
        let destructive: Bool
    }

    private struct Target {
        let id: String
        let title: String
        /// Whole card: the region that reacts to a long press.
        let rect: CGRect
        /// Just the thumbnail: the region that visually lifts.
        let previewRect: CGRect
        let cornerRadius: CGFloat
        let previewImagePath: String?
        let groups: [[Item]]
    }

    private let channel: FlutterMethodChannel
    private var targets: [Target] = []
    private var interaction: UIContextMenuInteraction?
    private weak var attachedView: UIView?
    // M53 — Apple Pencil hardware gestures (double-tap, Pro squeeze)
    private var pencil: UIPencilInteraction?
    private weak var pencilView: UIView?

    private init(channel: FlutterMethodChannel) {
        self.channel = channel
        super.init()
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "ipadprocad/native_menu",
            binaryMessenger: registrar.messenger())
        let instance = NativeMenuPlugin(channel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    // MARK: - Method channel

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "isSupported":
            result(true)

        case "setTargets":
            let raw = args["targets"] as? [[String: Any]] ?? []
            targets = raw.compactMap { NativeMenuPlugin.parseTarget($0) }
            syncInteraction()
            result(true)

        case "pencilInterest":
            setPencilInterest(args["on"] as? Bool ?? false)
            result(true)

        case "prompt":
            // .alert style is modal on every device — unlike an action sheet it
            // needs NO popover anchor.
            let alert = UIAlertController(
                title: args["title"] as? String ?? "",
                message: args["message"] as? String,
                preferredStyle: .alert)
            alert.addTextField { field in
                field.text = args["initialValue"] as? String ?? ""
                field.placeholder = args["placeholder"] as? String ?? ""
                field.clearButtonMode = .whileEditing
                field.autocapitalizationType = .words
                field.autocorrectionType = .no
                field.returnKeyType = .done
            }
            // A FlutterResult must fire exactly once; two taps or a failed
            // presentation would otherwise either leak or crash the engine.
            var answered = false
            let reply: (Any?) -> Void = { value in
                if answered { return }
                answered = true
                result(value)
            }
            alert.addAction(UIAlertAction(
                title: args["cancelLabel"] as? String ?? "Cancel",
                style: .cancel) { _ in reply(nil) })
            alert.addAction(UIAlertAction(
                title: args["confirmLabel"] as? String ?? "OK",
                style: .default) { [weak alert] _ in
                    reply(alert?.textFields?.first?.text ?? "")
                })
            if !presentModal(alert) { reply(nil) }

        case "confirm":
            let alert = UIAlertController(
                title: args["title"] as? String ?? "",
                message: args["message"] as? String,
                preferredStyle: .alert)
            var answered = false
            let reply: (Bool) -> Void = { value in
                if answered { return }
                answered = true
                result(value)
            }
            let destructive = (args["destructive"] as? NSNumber)?.boolValue ?? true
            alert.addAction(UIAlertAction(
                title: args["cancelLabel"] as? String ?? "Cancel",
                style: .cancel) { _ in reply(false) })
            alert.addAction(UIAlertAction(
                title: args["confirmLabel"] as? String ?? "OK",
                style: destructive ? .destructive : .default) { _ in reply(true) })
            if !presentModal(alert) { reply(false) }

        case "share":
            guard let path = args["path"] as? String,
                  FileManager.default.fileExists(atPath: path) else {
                result(false)
                return
            }
            let url = URL(fileURLWithPath: path)
            let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            present(vc, anchor: NativeMenuPlugin.parseRect(args["anchor"]))
            result(true)

        case "export":
            guard let path = args["path"] as? String,
                  FileManager.default.fileExists(atPath: path) else {
                result(false)
                return
            }
            let url = URL(fileURLWithPath: path)
            // asCopy: true — the app keeps its own file; the picker exports a
            // duplicate. asCopy: false would MOVE the sketch out of Documents.
            let vc = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
            present(vc, anchor: NativeMenuPlugin.parseRect(args["anchor"]))
            result(true)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Interaction lifecycle

    /// Attach only while targets exist; detach the moment the list goes empty.
    /// This keeps the interaction completely out of the CAD viewport.
    private func syncInteraction() {
        if targets.isEmpty {
            detach()
            return
        }
        guard let host = NativeMenuPlugin.flutterHostView() else { return }
        if attachedView !== host || interaction == nil {
            detach()
            let i = UIContextMenuInteraction(delegate: self)
            host.addInteraction(i)
            interaction = i
            attachedView = host
        }
    }

    private func detach() {
        if let view = attachedView, let i = interaction {
            view.removeInteraction(i)
        }
        interaction = nil
        attachedView = nil
    }

    private func target(at point: CGPoint) -> Target? {
        // Last match wins: later entries paint on top in the Flutter tree.
        var found: Target?
        for t in targets where t.rect.contains(point) {
            found = t
        }
        return found
    }

    private func target(for configuration: UIContextMenuConfiguration) -> Target? {
        guard let ns = configuration.identifier as? NSString else { return nil }
        let id = ns as String
        return targets.first { $0.id == id }
    }

    // MARK: - Presentation helpers

    /// iPad REQUIRES a popover anchor for these sheets — presenting without one
    /// raises NSGenericException and kills the app.
    private func present(_ vc: UIViewController, anchor: CGRect?) {
        guard let host = NativeMenuPlugin.flutterHostView(),
              var top = NativeMenuPlugin.keyRootViewController() else { return }
        if let pop = vc.popoverPresentationController {
            pop.sourceView = host
            pop.sourceRect = anchor ?? CGRect(
                x: host.bounds.midX, y: host.bounds.midY, width: 1, height: 1)
            pop.permittedArrowDirections = [.up, .down]
        }
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        top.present(vc, animated: true, completion: nil)
    }

    /// Presents something that does NOT need a popover anchor (alerts).
    /// Returns false when there is nothing to present from.
    @discardableResult
    private func presentModal(_ vc: UIViewController) -> Bool {
        guard var top = NativeMenuPlugin.keyRootViewController() else { return false }
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        top.present(vc, animated: true, completion: nil)
        return true
    }

    private static func keyRootViewController() -> UIViewController? {
        var window: UIWindow?
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            if let key = ws.windows.first(where: { $0.isKeyWindow }) {
                window = key
                break
            }
            if window == nil { window = ws.windows.first }
        }
        if window == nil {
            window = UIApplication.shared.delegate?.window ?? nil
        }
        return window?.rootViewController
    }

    private static func flutterHostView() -> UIView? {
        guard let root = keyRootViewController() else { return nil }
        if let flutter = findFlutterViewController(root) { return flutter.view }
        return root.view
    }

    private static func findFlutterViewController(_ vc: UIViewController) -> UIViewController? {
        if vc is FlutterViewController { return vc }
        for child in vc.children {
            if let found = findFlutterViewController(child) { return found }
        }
        return nil
    }

    // MARK: - Argument parsing

    private static func parseRect(_ raw: Any?) -> CGRect? {
        guard let m = raw as? [String: Any],
              let l = m["left"] as? NSNumber,
              let t = m["top"] as? NSNumber,
              let w = m["width"] as? NSNumber,
              let h = m["height"] as? NSNumber else { return nil }
        return CGRect(x: CGFloat(l.doubleValue), y: CGFloat(t.doubleValue),
                      width: CGFloat(w.doubleValue), height: CGFloat(h.doubleValue))
    }

    private static func parseTarget(_ m: [String: Any]) -> Target? {
        guard let id = m["id"] as? String, let rect = parseRect(m["rect"]) else { return nil }
        let groups: [[Item]] = (m["groups"] as? [[[String: Any]]] ?? []).map { group in
            group.compactMap { raw in
                guard let iid = raw["id"] as? String,
                      let title = raw["title"] as? String else { return nil }
                return Item(
                    id: iid,
                    title: title,
                    symbol: raw["symbol"] as? String,
                    destructive: (raw["destructive"] as? NSNumber)?.boolValue ?? false)
            }
        }
        return Target(
            id: id,
            title: m["title"] as? String ?? "",
            rect: rect,
            previewRect: parseRect(m["previewRect"]) ?? rect,
            cornerRadius: CGFloat((m["cornerRadius"] as? NSNumber)?.doubleValue ?? 0),
            previewImagePath: m["previewImagePath"] as? String,
            groups: groups)
    }
}

// MARK: - UIContextMenuInteractionDelegate

extension NativeMenuPlugin: UIContextMenuInteractionDelegate {
    public func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        // nil == "nothing here": UIKit leaves the touch to Flutter.
        guard let t = target(at: location) else { return nil }
        return UIContextMenuConfiguration(
            identifier: t.id as NSString,
            previewProvider: nil
        ) { [weak self] _ in
            self?.buildMenu(for: t) ?? UIMenu(title: "", children: [])
        }
    }

    public func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration
    ) -> UITargetedPreview? {
        return buildPreview(for: configuration)
    }

    public func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration
    ) -> UITargetedPreview? {
        return buildPreview(for: configuration)
    }

    private func buildMenu(for t: Target) -> UIMenu {
        var children: [UIMenuElement] = []
        for group in t.groups {
            let actions: [UIAction] = group.map { item in
                var attributes: UIMenuElement.Attributes = []
                if item.destructive { attributes.insert(.destructive) }
                let image = item.symbol.flatMap { UIImage(systemName: $0) }
                return UIAction(title: item.title, image: image, attributes: attributes) {
                    [weak self] _ in
                    self?.channel.invokeMethod(
                        "selected", arguments: ["target": t.id, "item": item.id])
                }
            }
            if actions.isEmpty { continue }
            // A nested .displayInline menu is how UIKit renders a separated
            // section — that is what puts Delete in its own block, like Files.
            if t.groups.count > 1 {
                children.append(UIMenu(title: "", options: .displayInline, children: actions))
            } else {
                children.append(contentsOf: actions)
            }
        }
        return UIMenu(title: t.title, children: children)
    }

    /// The card thumbnail lifts out of the page. Built from the sketch's own
    /// preview PNG rather than a snapshot of the Flutter view, because
    /// snapshotting a Metal-backed layer is unreliable.
    private func buildPreview(for configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        guard let t = target(for: configuration), let host = attachedView else { return nil }
        let r = t.previewRect
        guard r.width > 1, r.height > 1 else { return nil }

        let container = UIView(frame: CGRect(origin: .zero, size: r.size))
        container.backgroundColor = UIColor(
            red: 0x21 / 255.0, green: 0x28 / 255.0, blue: 0x30 / 255.0, alpha: 1)
        container.layer.cornerRadius = t.cornerRadius
        container.layer.cornerCurve = .continuous
        container.clipsToBounds = true

        if let path = t.previewImagePath, let image = UIImage(contentsOfFile: path) {
            let iv = UIImageView(image: image)
            iv.frame = container.bounds
            iv.contentMode = .scaleAspectFill
            iv.clipsToBounds = true
            container.addSubview(iv)
        }

        let params = UIPreviewParameters()
        params.backgroundColor = .clear
        params.visiblePath = UIBezierPath(
            roundedRect: container.bounds, cornerRadius: t.cornerRadius)

        let previewTarget = UIPreviewTarget(
            container: host, center: CGPoint(x: r.midX, y: r.midY))
        return UITargetedPreview(view: container, parameters: params, target: previewTarget)
    }
}


// MARK: - M53: Apple Pencil hardware gestures

extension NativeMenuPlugin: UIPencilInteractionDelegate {
    private func pencilHostView() -> UIView? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow }
            ?? scenes.first?.windows.first
        return window?.rootViewController?.view
    }

    func setPencilInterest(_ on: Bool) {
        if !on {
            if let p = pencil { pencilView?.removeInteraction(p) }
            pencil = nil
            pencilView = nil
            return
        }
        guard pencil == nil, let host = pencilHostView() else { return }
        let p = UIPencilInteraction()
        p.delegate = self
        host.addInteraction(p)
        pencil = p
        pencilView = host
    }

    /// Double-tap (Pencil 2 / Pro). Forwarded only when the user's system
    /// setting allows apps to act on it — Apple's HIG contract.
    public func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        guard UIPencilInteraction.preferredTapAction != .ignore else { return }
        channel.invokeMethod("pencil", arguments: ["event": "tap"])
    }

    /// Squeeze (Pencil Pro, iOS 17.5+): Apple's own apps open a tool palette
    /// at the tip; the hover pose (when present) is the anchor for ours.
    @available(iOS 17.5, *)
    public func pencilInteraction(
        _ interaction: UIPencilInteraction,
        didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze
    ) {
        guard UIPencilInteraction.preferredSqueezeAction != .ignore else { return }
        guard squeeze.phase == .ended else { return }
        var args: [String: Any] = ["event": "squeeze"]
        if let pose = squeeze.hoverPose, let view = pencilView {
            let loc = pose.location
            let inWindow = view.convert(loc, to: nil)
            args["x"] = Double(inWindow.x)
            args["y"] = Double(inWindow.y)
        }
        channel.invokeMethod("pencil", arguments: args)
    }
}
