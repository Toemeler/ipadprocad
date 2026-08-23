// M192 — the quick-tool bar, native, vertical, on the right edge.
//
// WHAT IT REPLACES
// ----------------
// Nothing is removed: the M53 quick menu (long press / Pencil squeeze) stays
// exactly where it is. What changes is that its contents stop being SECRET.
// Enter (OK) and Escape (Cancel) had no on-screen affordance at all — with a
// finger or a Pencil the only way to finish a spline or abort a half-drawn
// line was to guess that a 600 ms press opens a menu. That is a keyboard app
// wearing a tablet's clothes.
//
// WHY UIKIT
// ---------
// Same split as the ribbon, the model browser and the tab bar: Dart owns WHICH
// buttons exist and what they do, UIKit owns every pixel and every touch inside
// the bar. A Flutter column of hand-painted containers over a Liquid Glass app
// reads as a foreign object — and, more practically, a second gesture system
// negotiating with the viewport's raw pointer stream is how this project lost
// milestones before.
//
// The dark trait override is not cosmetic: `UIGlassEffect` follows its trait
// environment, a Flutter platform view inherits the host's, and the host is
// light. Without it the bar comes out milky white (M146).
import Flutter
import UIKit

struct ToolBarItem {
    let id: String
    /// SF Symbol name. A separator carries none.
    let symbol: String
    /// Older SF Symbol to use when [symbol] does not exist on this OS. An
    /// unknown name resolves to nil, and a button with no glyph is an INVISIBLE
    /// button — the one failure mode of an icons-only bar.
    let fallback: String
    /// VoiceOver / pointer label. Never drawn — the bar is icons only.
    let label: String
    let enabled: Bool
    /// Armed tool: drawn as a tinted capsule, the way iPadOS shows a selected
    /// chip.
    let selected: Bool
    /// Cancel and friends: red glyph, UIKit's own destructive tone.
    let destructive: Bool
    /// A hairline rule instead of a button.
    let separator: Bool

    init?(_ m: [String: Any]) {
        guard let id = m["id"] as? String else { return nil }
        self.id = id
        symbol = m["symbol"] as? String ?? ""
        fallback = m["fallback"] as? String ?? ""
        label = m["label"] as? String ?? ""
        enabled = (m["enabled"] as? NSNumber)?.boolValue ?? true
        selected = (m["selected"] as? NSNumber)?.boolValue ?? false
        destructive = (m["destructive"] as? NSNumber)?.boolValue ?? false
        separator = (m["separator"] as? NSNumber)?.boolValue ?? false
    }
}

@available(iOS 15.0, *)
final class GlassToolBarView: NSObject, FlutterPlatformView {
    private let container = UIView()
    private let column = UIStackView()
    private let channel: FlutterMethodChannel

    /// Geometry. These four numbers are DUPLICATED in Dart
    /// (`GlassToolBar.buttonSize` and friends) because Dart has to size the
    /// platform view before UIKit ever sees it. Change one, change both — the
    /// Dart test pins the arithmetic.
    static let button: CGFloat = 44
    static let spacing: CGFloat = 2
    static let separatorSlot: CGFloat = 11
    static let padding: CGFloat = 5
    static let radius: CGFloat = 16

    init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(
            name: "prototype/glass_toolbar/\(viewId)", binaryMessenger: messenger)
        super.init()
        container.frame = frame
        container.backgroundColor = .clear
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

        buildGlass()
        buildColumn()

        channel.setMethodCallHandler { [weak self] call, result in
            guard let self else { return result(nil) }
            switch call.method {
            case "setItems":
                let list = (call.arguments as? [[String: Any]]) ?? []
                self.apply(list.compactMap(ToolBarItem.init))
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    func view() -> UIView { container }

    // MARK: - Chrome

    private func buildGlass() {
        let effect: UIVisualEffect
        if #available(iOS 26.0, *) {
            let glass = UIGlassEffect()
            // The buttons live OUTSIDE the effect view (siblings above it), so
            // an interactive glass would highlight for touches it never sees.
            glass.isInteractive = false
            effect = glass
        } else {
            effect = UIBlurEffect(style: .systemMaterial)
        }
        let ev = UIVisualEffectView(effect: effect)
        ev.translatesAutoresizingMaskIntoConstraints = false
        ev.isUserInteractionEnabled = false
        ev.layer.cornerRadius = GlassToolBarView.radius
        ev.layer.cornerCurve = .continuous
        ev.clipsToBounds = true
        container.addSubview(ev)
        NSLayoutConstraint.activate([
            ev.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            ev.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ev.topAnchor.constraint(equalTo: container.topAnchor),
            ev.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    private func buildColumn() {
        column.axis = .vertical
        column.alignment = .center
        column.spacing = GlassToolBarView.spacing
        column.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(column)
        let p = GlassToolBarView.padding
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(
                equalTo: container.leadingAnchor, constant: p),
            column.trailingAnchor.constraint(
                equalTo: container.trailingAnchor, constant: -p),
            column.topAnchor.constraint(equalTo: container.topAnchor, constant: p),
        ])
    }

    // MARK: - Model

    private func apply(_ items: [ToolBarItem]) {
        column.arrangedSubviews.forEach {
            column.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for i in items {
            column.addArrangedSubview(i.separator ? makeRule() : makeButton(i))
        }
    }

    private func makeRule() -> UIView {
        let slot = UIView()
        slot.backgroundColor = .clear
        slot.translatesAutoresizingMaskIntoConstraints = false
        let line = UIView()
        line.backgroundColor = UIColor.separator
        line.translatesAutoresizingMaskIntoConstraints = false
        slot.addSubview(line)
        NSLayoutConstraint.activate([
            slot.heightAnchor.constraint(
                equalToConstant: GlassToolBarView.separatorSlot),
            slot.widthAnchor.constraint(
                equalToConstant: GlassToolBarView.button),
            line.centerYAnchor.constraint(equalTo: slot.centerYAnchor),
            line.leadingAnchor.constraint(
                equalTo: slot.leadingAnchor, constant: 8),
            line.trailingAnchor.constraint(
                equalTo: slot.trailingAnchor, constant: -8),
            line.heightAnchor.constraint(equalToConstant: 1),
        ])
        return slot
    }

    private func makeButton(_ i: ToolBarItem) -> UIView {
        var icon = UIImage(systemName: i.symbol)
        if icon == nil, !i.fallback.isEmpty {
            icon = UIImage(systemName: i.fallback)
        }
        var c = UIButton.Configuration.plain()
        c.image = icon
        c.preferredSymbolConfigurationForImage =
            UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        c.cornerStyle = .capsule
        c.contentInsets = .zero
        c.baseForegroundColor = i.destructive ? .systemRed : .label
        c.background.backgroundColor = i.selected
            ? UIColor.systemBlue.withAlphaComponent(0.30)
            : .clear

        // M205 — GlassButton, not UIButton: this bar is the one the report
        // named ("the debug button"), and its presses were being highlighted
        // and then cancelled. GlassButton counts a cancelled press that never
        // moved and ended inside the button as the click it was.
        let b = GlassButton(configuration: c)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.isEnabled = i.enabled
        b.accessibilityLabel = i.label.isEmpty ? i.id : i.label
        // A control that does not react to a trackpad hover is the giveaway
        // that it is not really native.
        b.isPointerInteractionEnabled = true
        // 44 pt square: Apple's HIG floor for a touch target, which is the
        // whole point of this bar existing.
        NSLayoutConstraint.activate([
            b.widthAnchor.constraint(equalToConstant: GlassToolBarView.button),
            b.heightAnchor.constraint(equalToConstant: GlassToolBarView.button),
        ])
        // Disabled must still LOOK disabled on a glass surface, where a plain
        // alpha drop reads as "the blur moved".
        b.configurationUpdateHandler = { btn in
            btn.alpha = btn.isEnabled ? 1.0 : 0.32
        }
        let id = i.id
        let destructive = i.destructive
        b.onTap = { [weak self] in
            UIImpactFeedbackGenerator(style: destructive ? .rigid : .light)
                .impactOccurred()
            self?.channel.invokeMethod("tap", arguments: ["id": id])
        }
        return b
    }
}

@available(iOS 15.0, *)
final class GlassToolBarFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger
    init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }

    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64,
                arguments args: Any?) -> FlutterPlatformView {
        GlassToolBarView(frame: frame, viewId: viewId, messenger: messenger)
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }
}
