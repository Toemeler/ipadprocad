// M149 — the document tab bar, native.
//
// The old bar was a Flutter Row of hand-styled Containers: a flat #14171B
// strip, hard-edged rectangular tabs, a 2 px blue underline and a "✕"
// character standing in for a close button. It was a faithful port of the HTML
// mock and it looked like a port of an HTML mock.
//
// This is UIKit on the same Liquid Glass as the ribbon and the model browser,
// with the same dark trait environment (see GlassPanelView — a platform view
// inherits the host's light traits, which is what made the ribbon milky in
// M146). Tabs are `UIButton.Configuration` capsules with SF Symbols, the
// selected one is tinted rather than underlined, and close is a real
// `xmark.circle.fill` with its own hit target. Selection and close both fire
// haptics, because on iPadOS a document tab that closes silently feels broken.
//
// Dart owns WHICH tabs exist and what happens on tap; UIKit owns every pixel
// and every touch inside the bar. Same split as the browser, for the same
// reason: two gesture systems negotiating over one strip is how this project
// lost four milestones to the End of Part drag.
import Flutter
import UIKit

struct TabItem {
    let id: String
    let label: String
    /// SF Symbol name.
    let symbol: String
    let selected: Bool
    /// Home has no close button; documents do.
    let closable: Bool

    init?(_ m: [String: Any]) {
        guard let id = m["id"] as? String else { return nil }
        self.id = id
        label = m["label"] as? String ?? ""
        symbol = m["symbol"] as? String ?? "doc"
        selected = (m["selected"] as? NSNumber)?.boolValue ?? false
        closable = (m["closable"] as? NSNumber)?.boolValue ?? false
    }
}

@available(iOS 15.0, *)
final class GlassTabBarView: NSObject, FlutterPlatformView {
    private let container = UIView()
    private let scroll = UIScrollView()
    private let row = UIStackView()
    private let channel: FlutterMethodChannel

    /// Margin around the floating bar. Mirrors the ribbon's 28 pt sides so the
    /// three panels — ribbon, browser, tab bar — share one vertical rhythm.
    static let inset = UIEdgeInsets(top: 0, left: 28, bottom: 8, right: 28)
    static let radius: CGFloat = 18

    init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(
            name: "prototype/glass_tabbar/\(viewId)", binaryMessenger: messenger)
        super.init()
        container.frame = frame
        container.backgroundColor = .clear
        // Same reason as the ribbon and the browser: UIGlassEffect follows its
        // trait environment and Flutter's is light.
        container.overrideUserInterfaceStyle = .dark

        buildGlass()
        buildRow()

        channel.setMethodCallHandler { [weak self] call, result in
            guard let self else { return result(nil) }
            switch call.method {
            case "setTabs":
                let list = (call.arguments as? [[String: Any]]) ?? []
                self.apply(list.compactMap(TabItem.init))
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
            glass.isInteractive = false
            effect = glass
        } else {
            effect = UIBlurEffect(style: .systemMaterial)
        }
        let ev = UIVisualEffectView(effect: effect)
        ev.translatesAutoresizingMaskIntoConstraints = false
        ev.isUserInteractionEnabled = false
        ev.layer.cornerRadius = GlassTabBarView.radius
        ev.layer.cornerCurve = .continuous
        ev.clipsToBounds = true
        container.addSubview(ev)
        let i = GlassTabBarView.inset
        NSLayoutConstraint.activate([
            ev.leadingAnchor.constraint(
                equalTo: container.leadingAnchor, constant: i.left),
            ev.trailingAnchor.constraint(
                equalTo: container.trailingAnchor, constant: -i.right),
            ev.topAnchor.constraint(equalTo: container.topAnchor, constant: i.top),
            ev.bottomAnchor.constraint(
                equalTo: container.bottomAnchor, constant: -i.bottom),
        ])
    }

    private func buildRow() {
        // Horizontal scrolling, because a CAD session ends up with more open
        // documents than fit and a tab that cannot be reached is a lost file.
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.backgroundColor = .clear
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = true
        scroll.clipsToBounds = true
        scroll.layer.cornerRadius = GlassTabBarView.radius
        scroll.layer.cornerCurve = .continuous
        container.addSubview(scroll)

        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(row)

        let i = GlassTabBarView.inset
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(
                equalTo: container.leadingAnchor, constant: i.left),
            scroll.trailingAnchor.constraint(
                equalTo: container.trailingAnchor, constant: -i.right),
            scroll.topAnchor.constraint(
                equalTo: container.topAnchor, constant: i.top),
            scroll.bottomAnchor.constraint(
                equalTo: container.bottomAnchor, constant: -i.bottom),
            row.leadingAnchor.constraint(
                equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 8),
            row.trailingAnchor.constraint(
                equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -8),
            row.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            row.bottomAnchor.constraint(
                equalTo: scroll.contentLayoutGuide.bottomAnchor),
            row.heightAnchor.constraint(
                equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
    }

    // MARK: - Model

    private func apply(_ tabs: [TabItem]) {
        row.arrangedSubviews.forEach {
            row.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for t in tabs { row.addArrangedSubview(makeTab(t)) }
    }

    private func makeTab(_ t: TabItem) -> UIView {
        var c = UIButton.Configuration.plain()
        c.image = UIImage(systemName: t.symbol)
        c.preferredSymbolConfigurationForImage =
            UIImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        if !t.label.isEmpty {
            var title = AttributedString(t.label)
            title.font = .systemFont(ofSize: 12.5, weight: t.selected ? .semibold : .regular)
            c.attributedTitle = title
            c.imagePadding = 5
        }
        // A capsule with a tint is how iPadOS shows a selected chip. The old
        // 2 px underline was a browser-tab idiom and read as web chrome.
        c.cornerStyle = .capsule
        c.contentInsets = NSDirectionalEdgeInsets(
            top: 4, leading: 10, bottom: 4, trailing: t.closable ? 2 : 10)
        c.baseForegroundColor = t.selected ? .label : .secondaryLabel
        c.background.backgroundColor = t.selected
            ? UIColor.systemBlue.withAlphaComponent(0.30)
            : .clear

        let b = UIButton(configuration: c)
        b.addAction(UIAction { [weak self] _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            self?.channel.invokeMethod("tap", arguments: ["id": t.id])
        }, for: .touchUpInside)
        // Pointer effects on iPadOS: a tab that does not respond to a trackpad
        // hover is the giveaway that a control is not really native.
        b.isPointerInteractionEnabled = true

        guard t.closable else { return b }

        var xc = UIButton.Configuration.plain()
        xc.image = UIImage(systemName: "xmark.circle.fill")
        xc.preferredSymbolConfigurationForImage =
            UIImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        xc.contentInsets = NSDirectionalEdgeInsets(
            top: 4, leading: 2, bottom: 4, trailing: 8)
        xc.baseForegroundColor = t.selected ? .secondaryLabel : .tertiaryLabel

        let x = UIButton(configuration: xc)
        x.isPointerInteractionEnabled = true
        x.addAction(UIAction { [weak self] _ in
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            self?.channel.invokeMethod("close", arguments: ["id": t.id])
        }, for: .touchUpInside)

        // The capsule belongs to the PAIR, so the close button sits inside the
        // selected tint rather than floating next to it.
        let wrap = UIView()
        wrap.backgroundColor = t.selected
            ? UIColor.systemBlue.withAlphaComponent(0.30) : .clear
        wrap.layer.cornerCurve = .continuous
        b.configuration?.background.backgroundColor = .clear

        let pair = UIStackView(arrangedSubviews: [b, x])
        pair.axis = .horizontal
        pair.alignment = .center
        pair.spacing = 0
        pair.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(pair)
        NSLayoutConstraint.activate([
            pair.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            pair.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            pair.topAnchor.constraint(equalTo: wrap.topAnchor),
            pair.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
        ])
        // Capsule radius has to follow the laid-out height, not a guess.
        wrap.layoutIfNeeded()
        wrap.layer.cornerRadius = wrap.bounds.height / 2
        wrap.autoresizingMask = []
        return CapsuleWrap(wrap)
    }

    /// Keeps the capsule radius correct across rotation and Dynamic Type.
    final class CapsuleWrap: UIView {
        init(_ inner: UIView) {
            super.init(frame: .zero)
            addSubview(inner)
            inner.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                inner.leadingAnchor.constraint(equalTo: leadingAnchor),
                inner.trailingAnchor.constraint(equalTo: trailingAnchor),
                inner.topAnchor.constraint(equalTo: topAnchor),
                inner.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        required init?(coder: NSCoder) { fatalError("not used") }
        override func layoutSubviews() {
            super.layoutSubviews()
            subviews.first?.layer.cornerRadius = bounds.height / 2
        }
    }
}

@available(iOS 15.0, *)
final class GlassTabBarFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger
    init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }

    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64,
                arguments args: Any?) -> FlutterPlatformView {
        GlassTabBarView(frame: frame, viewId: viewId, messenger: messenger)
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }
}
