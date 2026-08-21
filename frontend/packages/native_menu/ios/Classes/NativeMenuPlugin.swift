// Prototype — real UIKit context menus for Flutter content.
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
        /// M90 — false for targets whose pixels UIKit cannot obtain (Flutter
        /// rows). Lifting those produced a blank slab; see buildPreview.
        let lift: Bool
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
            name: "prototype/native_menu",
            binaryMessenger: registrar.messenger())
        let instance = NativeMenuPlugin(channel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
        // M178 — iPadOS floats its keyboard shortcuts bar over the bottom of
        // the screen the moment any field takes focus, on top of the app's own
        // tab bar. Suppressed once, for every text field in the app.
        KeyboardBar.install()
        // M106 — real Apple Liquid Glass surface for the model browser.
        if #available(iOS 15.0, *) {
            registrar.register(GlassPanelFactory(),
                               withId: "prototype/glass_panel")
            // M107 — the whole browser, native.
            registrar.register(
                GlassBrowserFactory(messenger: registrar.messenger()),
                withId: "prototype/glass_browser")
            // M149 — the document tab bar, native.
            registrar.register(
                GlassTabBarFactory(messenger: registrar.messenger()),
                withId: "prototype/glass_tabbar")
            // M192 — the vertical quick-tool bar on the right edge.
            registrar.register(
                GlassToolBarFactory(messenger: registrar.messenger()),
                withId: "prototype/glass_toolbar")
        }
    }

    // MARK: - Method channel

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "isSupported":
            result(true)

        // M237 — the Flutter palette, pushed into UIKit. Every glass surface
        // bound through AppearanceBinder switches with it, so the material and
        // the Flutter text on top of it always come from the same scheme.
        case "setAppearance":
            AppearanceBinder.shared.set(dark: args["dark"] as? Bool ?? true)
            result(nil)

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

        case "menu":
            // A tap-to-choose action sheet (the gallery "+"). On iPad this is a
            // popover, so it REQUIRES a source rect — the same trap as
            // share/export; present(_:anchor:) supplies it. Returns the chosen
            // item id, or nil when cancelled / nothing to present from.
            let items = args["items"] as? [[String: Any]] ?? []
            let sheet = UIAlertController(
                title: (args["title"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                message: nil,
                preferredStyle: .actionSheet)
            var answered = false
            let reply: (String?) -> Void = { value in
                if answered { return }
                answered = true
                result(value)
            }
            for raw in items {
                guard let id = raw["id"] as? String,
                      let label = raw["title"] as? String else { continue }
                let destructive = (raw["destructive"] as? NSNumber)?.boolValue ?? false
                let action = UIAlertAction(
                    title: label,
                    style: destructive ? .destructive : .default) { _ in reply(id) }
                if let symbol = raw["symbol"] as? String,
                   let image = UIImage(systemName: symbol) {
                    // Private but stable key UIKit reads for a leading glyph.
                    action.setValue(image, forKey: "image")
                }
                sheet.addAction(action)
            }
            sheet.addAction(UIAlertAction(
                title: args["cancelLabel"] as? String ?? "Cancel",
                style: .cancel) { _ in reply(nil) })
            if !present(sheet, anchor: NativeMenuPlugin.parseRect(args["anchor"])) {
                reply(nil)
            }

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

        // M177 — Open, in place. See DocumentOpen.swift for why this cannot
        // be the ordinary file picker: that one hands over a COPY in tmp, so
        // saving a document you opened from Files would never reach the file.
        case "openInPlace":
            guard #available(iOS 14.0, *) else {
                result(nil)
                return
            }
            documentOpener().present(
                extensions: args["extensions"] as? [String] ?? [],
                anchor: NativeMenuPlugin.parseRect(args["anchor"]),
                result: result)

        case "resolveBookmark":
            guard #available(iOS 14.0, *),
                  let bm = args["bookmark"] as? String else {
                result(nil)
                return
            }
            result(documentOpener().resolve(bookmark: bm))

        case "releaseDocument":
            if #available(iOS 14.0, *), let path = args["path"] as? String {
                documentOpener().release(path: path)
            }
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

    // MARK: - Open in place (M177)

    private var opener: AnyObject?

    @available(iOS 14.0, *)
    private func documentOpener() -> DocumentOpener {
        if let existing = opener as? DocumentOpener { return existing }
        let made = DocumentOpener { [weak self] vc, anchor in
            self?.present(vc, anchor: anchor) ?? false
        }
        opener = made
        return made
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
    /// raises NSGenericException and kills the app. Returns false when there is
    /// no view controller to present from (so a caller whose FlutterResult fires
    /// from the sheet's actions can reply instead of leaking it).
    @discardableResult
    private func present(_ vc: UIViewController, anchor: CGRect?) -> Bool {
        guard let host = NativeMenuPlugin.flutterHostView(),
              var top = NativeMenuPlugin.keyRootViewController() else { return false }
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
        return true
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

    /// Not private: KeyboardBar.swift sweeps the same hierarchy.
    static func flutterHostView() -> UIView? {
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
            lift: (m["lift"] as? NSNumber)?.boolValue ?? true,
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
    ///
    /// M90 — THE BLANK SLAB. This used to fill the container with the viewport
    /// colour and only then draw the image, so a target WITHOUT an image (the
    /// model browser rows added in M84) lifted an empty rounded rectangle the
    /// size of the row: a grey slab sitting over the tree with nothing in it.
    /// The row's real pixels are unobtainable — they live in Flutter's Metal
    /// layer, which is exactly why the gallery hands over a PNG instead.
    ///
    /// So such targets now opt out of lifting entirely (`lift: false`). We
    /// still return a preview rather than nil, because nil makes UIKit
    /// snapshot the Flutter view itself and produce the same unreliable
    /// result: an INVISIBLE one, with no background, no shadow and an empty
    /// visible path. The row stays put and only the menu animates in, which is
    /// how iOS list menus behave when a preview cannot be supplied.
    private func buildPreview(for configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        guard let t = target(for: configuration), let host = attachedView else { return nil }
        let r = t.previewRect
        guard r.width > 1, r.height > 1 else { return nil }

        let container = UIView(frame: CGRect(origin: .zero, size: r.size))
        let params = UIPreviewParameters()
        params.backgroundColor = .clear

        if t.lift, let path = t.previewImagePath,
           let image = UIImage(contentsOfFile: path) {
            container.backgroundColor = UIColor(
                red: 0x21 / 255.0, green: 0x28 / 255.0, blue: 0x30 / 255.0, alpha: 1)
            container.layer.cornerRadius = t.cornerRadius
            container.layer.cornerCurve = .continuous
            container.clipsToBounds = true
            let iv = UIImageView(image: image)
            iv.frame = container.bounds
            iv.contentMode = .scaleAspectFill
            iv.clipsToBounds = true
            container.addSubview(iv)
            params.visiblePath = UIBezierPath(
                roundedRect: container.bounds, cornerRadius: t.cornerRadius)
        } else {
            // Nothing to lift. An empty visible path draws no platter, and an
            // empty shadow path suppresses the drop shadow UIKit would
            // otherwise cast around it.
            container.backgroundColor = .clear
            params.visiblePath = UIBezierPath()
            params.shadowPath = UIBezierPath()
        }

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

// ===========================================================================
// M106 — REAL Apple Liquid Glass for the model browser panel.
// ===========================================================================
//
// A genuine UIVisualEffectView driven by UIGlassEffect (iOS 26), not a blur
// painted in Flutter. UIGlassEffect is the actual system material, so it picks
// up the system's refraction, specular edge and interactive response — none of
// which can be reproduced client-side.
//
// It is a BACKGROUND surface: Flutter keeps drawing the tree rows on top with
// a transparent background. That is deliberate, not a shortcut. The browser is
// the most interaction-dense part of the app — EOP dragging, body picking,
// hover highlight, context menus — and every one of those has already cost
// this project debugging time at the Flutter/UIKit boundary (M48: a platform
// view swallowed taps and had to be wrapped in IgnorePointer; M102: a
// UIContextMenuInteraction cancelled the EOP drag for four milestones).
// Moving the CONTENT native would mean re-solving all of it in Swift. The
// glass is what you see; the rows keep working.
@available(iOS 15.0, *)
final class GlassPanelView: NSObject, FlutterPlatformView {
    private let container = UIView()

    init(frame: CGRect, cornerRadius: CGFloat) {
        super.init()
        container.frame = frame
        container.backgroundColor = .clear
        // The glass must never take touches: Flutter's rows sit above it and
        // own every gesture in this panel.
        container.isUserInteractionEnabled = false
        // M237 — the trait is still pinned explicitly, but to the ACTIVE
        // palette rather than to dark.
        //
        // M108's reason stands: left to resolve on its own, UIGlassEffect
        // follows the host's trait environment (Flutter's is light), the
        // material comes out milky and UIKit then picks near-black labels.
        // Pinning it to .dark fixed that and created the next problem — the
        // glass stayed charcoal under M236's cream chrome, so one window
        // rendered in two schemes. AppearanceBinder does both jobs: always
        // explicit, and it follows a scheme change.
        AppearanceBinder.shared.bind(container)

        let effect: UIVisualEffect
        if #available(iOS 26.0, *) {
            let glass = UIGlassEffect()
            glass.isInteractive = false // a background surface, not a control
            effect = glass
        } else {
            // Pre-26 devices get the closest system material rather than
            // nothing, so the panel is still legible.
            effect = UIBlurEffect(style: .systemMaterial)
        }
        let ev = UIVisualEffectView(effect: effect)
        ev.frame = container.bounds
        ev.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        ev.isUserInteractionEnabled = false
        // M146 — a floating card needs its own corners; a full-bleed surface
        // must keep 0 so the existing model-browser fallback is untouched.
        if cornerRadius > 0 {
            ev.layer.cornerRadius = cornerRadius
            ev.layer.cornerCurve = .continuous
            ev.clipsToBounds = true
        }
        container.addSubview(ev)
    }

    func view() -> UIView { container }
}

@available(iOS 15.0, *)
final class GlassPanelFactory: NSObject, FlutterPlatformViewFactory {
    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64,
                arguments args: Any?) -> FlutterPlatformView {
        let m = args as? [String: Any]
        let r = (m?["cornerRadius"] as? NSNumber)?.doubleValue ?? 0
        return GlassPanelView(frame: frame, cornerRadius: CGFloat(r))
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }
}
