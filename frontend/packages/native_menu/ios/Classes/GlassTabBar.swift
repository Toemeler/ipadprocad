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
//
// ── M260 — THE BAR IS THREE OBJECTS, AND IT GETS OUT OF THE WAY ────────────
//
// The report was "liquid glass is too much" — and the material was not the
// problem. One glass slab running the width of an iPad is too much; the same
// glass cut into three small objects is what iOS 26 actually ships. Reading
// what Apple settled on made that concrete:
//
//   * The tab bar stopped being a full-width strip. It is a floating capsule,
//     inset from the page, sized to its contents.
//   * Search LEFT the row and became its own circular island beside the bar.
//     Apple deliberately broke one strip into two objects.
//   * `tabViewBottomAccessory` made that official: a second capsule that rides
//     above the bar or in line with it.
//   * And the bar MINIMISES while a view scrolls, returning when it stops.
//     Chrome is expected to yield to the content it sits on top of.
//
// So the bar is now:
//
//     ( ⌂ )  ( cube Halter · cube Bracket ✕ · … )            ( ☰ )
//      home            documents                              all
//
// three separate glass groups, each rounded to its own height. Home is a
// button, not a list entry, and it never scrolls away. The documents ride in
// their own capsule, content-sized rather than stretched — a capsule stretched
// to the window is the slab again. The island on the right is the escape
// hatch: every open document in one menu, always reachable.
//
// The fourth point is the fold, and M265 turned it the right way up. M260 had
// the bar fold only while the model was under a finger — a CAD viewport never
// scrolls, so that is the gesture that means "get out of my way" — and open
// again the moment you let go. From the device: "it actually does but only
// when i actively do something", which is the miss exactly. A bar that is only
// out of the way while you are busy is in the way the rest of the time.
//
// Folded is the resting state now. The bar shows the document you are in and
// opens when you reach for it: a touch on it, a pointer over it, or arriving
// somewhere new. Three seconds later it folds back. Camera motion still folds
// it at once — Dart owns that latch (AppState.engageView) because Dart owns
// the gestures — but nothing Dart says can open it.
import Flutter
import UIKit

/// M260 — the app's two accents, as UIKit sees them. `T.accent` on the Dart
/// side: Ember's teal and Chalk's darker one.
private enum Accent {
    static let ember = UIColor(red: 0.184, green: 0.663, blue: 0.635, alpha: 1)
    static let chalk = UIColor(red: 0.059, green: 0.416, blue: 0.439, alpha: 1)
}

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

/// M260 — one glass object of the bar, rounded to its own height.
///
/// Same material and the same iOS 26 / iOS 15 split as before; what changed is
/// that there are three of these instead of one view spanning the whole strip.
/// The radius is taken in `layoutSubviews` rather than set once, because a
/// capsule whose radius was guessed at build time is wrong after the first
/// rotation or Dynamic Type change.
@available(iOS 15.0, *)
final class GlassGroup: UIVisualEffectView {
    init() {
        let effect: UIVisualEffect
        if #available(iOS 26.0, *) {
            let glass = UIGlassEffect()
            glass.isInteractive = false
            effect = glass
        } else {
            effect = UIBlurEffect(style: .systemMaterial)
        }
        super.init(effect: effect)
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerCurve = .continuous
        clipsToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }
}

/// M265 — a container that says when it is being touched.
///
/// The bar folds itself away when it is not in use, so it has to know when it
/// IS. `hitTest` rather than a gesture recogniser: every touch that lands
/// anywhere in the bar passes through here on its way to whatever it hit,
/// including the ones that belong to a tab button or to the scroll view, and a
/// recogniser would have to either compete with those or be attached to each
/// of them in turn.
///
/// A hit on the container ITSELF is a touch in the empty space between the
/// groups. That is not reaching for the bar, so it does not count — the hit is
/// still returned unchanged, because who gets that touch is a separate
/// question from whether the bar should open.
@available(iOS 15.0, *)
final class TouchAwareView: UIView {
    var onTouched: (() -> Void)?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        if let hit, hit !== self { onTouched?() }
        return hit
    }
}

@available(iOS 15.0, *)
final class GlassTabBarView: NSObject, FlutterPlatformView {
    private let container = TouchAwareView()

    private let home = GlassGroup()
    private let docs = GlassGroup()
    private let island = GlassGroup()

    private let scroll = UIScrollView()
    private let row = UIStackView()
    private let channel: FlutterMethodChannel

    /// Margin around the floating bar. Mirrors the ribbon's sides so the three
    /// panels — ribbon, browser, tab bar — float on one shared edge (M150:
    /// 28 -> 14).
    static let inset = UIEdgeInsets(top: 0, left: 14, bottom: 8, right: 14)

    /// Height of every group, and so the diameter of the two circles. 44 pt is
    /// Apple's touch minimum and the bar's own 52 pt height less the 8 pt it
    /// floats above the screen edge.
    static let groupH: CGFloat = 44
    /// Between groups. Half the outer inset, so the split reads as one object
    /// broken up rather than three unrelated ones.
    static let gap: CGFloat = 8
    /// Inside the documents capsule, around the row of chips.
    static let rowPad: CGFloat = 5

    /// M260 — the app's accent, the same teal the planes and the selected
    /// edges use. Was `systemBlue`, which belonged to no palette in this app
    /// and said nothing: the accent means "this is the thing you are working
    /// on" everywhere else, and now it means that here too.
    ///
    /// Dynamic rather than one constant because M236 gave the app two
    /// palettes; AppearanceBinder pins the trait, so this resolves to the one
    /// Dart says is active.
    static let accent = UIColor { t in
        t.userInterfaceStyle == .light ? Accent.chalk : Accent.ember
    }

    /// The same accent as a chip fill.
    ///
    /// Built inside the provider, not as `accent.withAlphaComponent(_:)`:
    /// asking a dynamic colour for a new alpha RESOLVES it against whatever
    /// trait is current at the call and returns a static colour, which would
    /// then be the wrong palette for the rest of the session after a scheme
    /// switch. M237 exists because that class of staleness is hard to see.
    static let accentFill = UIColor { t in
        (t.userInterfaceStyle == .light ? Accent.chalk : Accent.ember)
            .withAlphaComponent(0.30)
    }

    /// Trailing cap on the documents capsule. Exactly one is active: the bar
    /// stops at the island when there is one, at the screen inset when there
    /// is not.
    private var capToIsland: NSLayoutConstraint!
    private var capToEdge: NSLayoutConstraint!

    private var items: [TabItem] = []
    /// The document chips, in row order, paired with whether each is current.
    private var docViews: [(view: UIView, selected: Bool)] = []

    // ---- M265: FOLDED IS THE RESTING STATE ---------------------------------
    //
    // M260 folded the bar while the model was under a finger and opened it
    // again the moment you let go. From the device: "it actually does but only
    // when i actively do something" — which is the whole of the miss. A bar
    // that is only out of the way while you are busy is in the way the rest of
    // the time, and the rest of the time is most of the time.
    //
    // So it is inverted. The bar is folded to the document you are in, and it
    // opens when you reach for it: a touch anywhere on it, a pointer hovering
    // it, or landing in a different document (worth seeing once, then gone).
    // Three seconds after the last of those it folds back.
    //
    // Which makes the island load-bearing rather than a nicety — folded, it is
    // how you reach a document that is not the current one, and it does not
    // care whether the row scrolled off the end either.

    /// How long the bar stays open after the last thing you did to it.
    static let idleFold: TimeInterval = 3

    /// Open because someone reached for it. Otherwise folded.
    private var awake = false
    private var idle: Timer?
    /// The document that was current last time the tabs were pushed, so
    /// arriving somewhere new can be told apart from a tree change.
    private var selectedDocId: String?

    init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(
            name: "prototype/glass_tabbar/\(viewId)", binaryMessenger: messenger)
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

        container.onTouched = { [weak self] in self?.wake() }
        // Pointer, for the trackpad: on iPadOS reaching for the bar can happen
        // without ever touching the glass.
        container.addGestureRecognizer(
            UIHoverGestureRecognizer(target: self, action: #selector(onHover)))

        buildGroups()
        buildRow()
        buildIsland()

        channel.setMethodCallHandler { [weak self] call, result in
            guard let self else { return result(nil) }
            switch call.method {
            case "setTabs":
                let list = (call.arguments as? [[String: Any]]) ?? []
                self.apply(list.compactMap(TabItem.init))
                result(nil)
            case "setEngaged":
                let a = (call.arguments as? [String: Any]) ?? [:]
                self.setEngaged((a["engaged"] as? NSNumber)?.boolValue ?? false)
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    func view() -> UIView { container }

    // MARK: - Chrome

    private func buildGroups() {
        container.addSubview(home)
        container.addSubview(docs)
        container.addSubview(island)

        let i = GlassTabBarView.inset
        let h = GlassTabBarView.groupH
        let gap = GlassTabBarView.gap
        NSLayoutConstraint.activate([
            home.leadingAnchor.constraint(
                equalTo: container.leadingAnchor, constant: i.left),
            home.bottomAnchor.constraint(
                equalTo: container.bottomAnchor, constant: -i.bottom),
            home.widthAnchor.constraint(equalToConstant: h),
            home.heightAnchor.constraint(equalToConstant: h),

            docs.leadingAnchor.constraint(
                equalTo: home.trailingAnchor, constant: gap),
            docs.bottomAnchor.constraint(
                equalTo: container.bottomAnchor, constant: -i.bottom),
            docs.heightAnchor.constraint(equalToConstant: h),

            island.trailingAnchor.constraint(
                equalTo: container.trailingAnchor, constant: -i.right),
            island.bottomAnchor.constraint(
                equalTo: container.bottomAnchor, constant: -i.bottom),
            island.widthAnchor.constraint(equalToConstant: h),
            island.heightAnchor.constraint(equalToConstant: h),
        ])

        capToIsland = docs.trailingAnchor.constraint(
            lessThanOrEqualTo: island.leadingAnchor, constant: -gap)
        capToEdge = docs.trailingAnchor.constraint(
            lessThanOrEqualTo: container.trailingAnchor, constant: -i.right)
        capToIsland.isActive = true
    }

    private func buildRow() {
        // Horizontal scrolling, because a CAD session ends up with more open
        // documents than fit and a tab that cannot be reached is a lost file.
        // The island is the other half of that promise: what scrolls out of
        // sight is still one tap away.
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.backgroundColor = .clear
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = true
        scroll.clipsToBounds = true
        docs.contentView.addSubview(scroll)

        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 4
        row.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(row)

        let pad = GlassTabBarView.rowPad
        // The capsule takes its width FROM the row, up to the cap set in
        // buildGroups. Near-required, so the only thing that can beat it is
        // running out of screen — a scroll view has no intrinsic width of its
        // own and the group would otherwise be ambiguous.
        let fit = docs.widthAnchor.constraint(
            equalTo: row.widthAnchor, constant: 2 * pad)
        fit.priority = UILayoutPriority(999)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: docs.contentView.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: docs.contentView.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: docs.contentView.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: docs.contentView.bottomAnchor),
            row.leadingAnchor.constraint(
                equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: pad),
            row.trailingAnchor.constraint(
                equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -pad),
            row.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            row.bottomAnchor.constraint(
                equalTo: scroll.contentLayoutGuide.bottomAnchor),
            row.heightAnchor.constraint(
                equalTo: scroll.frameLayoutGuide.heightAnchor),
            fit,
        ])
    }

    private func buildIsland() {
        var c = UIButton.Configuration.plain()
        c.image = UIImage(systemName: "list.bullet")
        c.preferredSymbolConfigurationForImage =
            UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        c.baseForegroundColor = .secondaryLabel
        c.contentInsets = .zero

        // Deliberately NOT a GlassButton. M205's recovery fires an action for
        // a press UIKit cancelled, and a menu button has no action to fire —
        // `showsMenuAsPrimaryAction` presents on touch-DOWN, so the cancel
        // that recovery exists to catch cannot happen here.
        let b = UIButton(type: .system)
        b.configuration = c
        b.showsMenuAsPrimaryAction = true
        b.isPointerInteractionEnabled = true
        b.translatesAutoresizingMaskIntoConstraints = false
        // Built when it opens, not when the tabs change: the menu has to show
        // the documents as they are at the moment of the press.
        let deferred: [UIMenuElement] = [
            UIDeferredMenuElement.uncached { [weak self] done in
                done(self?.documentActions() ?? [])
            }
        ]
        b.menu = UIMenu(title: "", children: deferred)
        island.contentView.addSubview(b)
        NSLayoutConstraint.activate([
            b.leadingAnchor.constraint(equalTo: island.contentView.leadingAnchor),
            b.trailingAnchor.constraint(equalTo: island.contentView.trailingAnchor),
            b.topAnchor.constraint(equalTo: island.contentView.topAnchor),
            b.bottomAnchor.constraint(equalTo: island.contentView.bottomAnchor),
        ])
    }

    /// Every open document, current one checked. This is what makes the fold
    /// safe: with the row collapsed to one chip, this menu is how you reach
    /// the rest, and it does not care whether they scrolled off the end.
    private func documentActions() -> [UIMenuElement] {
        let actions: [UIAction] = items.filter { $0.closable }.map { t in
            UIAction(
                title: t.label,
                image: UIImage(systemName: t.symbol),
                state: t.selected ? .on : .off
            ) { [weak self] _ in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                self?.channel.invokeMethod("tap", arguments: ["id": t.id])
            }
        }
        return actions
    }

    // MARK: - Model

    private func apply(_ tabs: [TabItem]) {
        items = tabs

        home.contentView.subviews.forEach { $0.removeFromSuperview() }
        if let h = tabs.first(where: { !$0.closable }) {
            let b = makeHome(h)
            home.contentView.addSubview(b)
            NSLayoutConstraint.activate([
                b.leadingAnchor.constraint(equalTo: home.contentView.leadingAnchor),
                b.trailingAnchor.constraint(equalTo: home.contentView.trailingAnchor),
                b.topAnchor.constraint(equalTo: home.contentView.topAnchor),
                b.bottomAnchor.constraint(equalTo: home.contentView.bottomAnchor),
            ])
        }
        home.isHidden = !tabs.contains(where: { !$0.closable })

        row.arrangedSubviews.forEach {
            row.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        docViews = []
        for t in tabs where t.closable {
            let v = makeTab(t)
            row.addArrangedSubview(v)
            docViews.append((v, t.selected))
        }

        // No documents open: no capsule and no island to list them in. The
        // Home circle alone is the whole bar, which is the truth of that
        // state and much quieter than an empty pill.
        let empty = docViews.isEmpty
        docs.isHidden = empty
        island.isHidden = empty
        capToIsland.isActive = !empty
        capToEdge.isActive = empty

        let wasIn = selectedDocId
        selectedDocId = tabs.first(where: { $0.closable && $0.selected })?.id

        // Without animation first: these are new views and they need the
        // current fold state applied to them, not a transition into it.
        applyFold(animated: false)
        // Landing somewhere new — from Home, from the island, from a file the
        // ribbon opened — is worth seeing once. It folds itself back.
        if selectedDocId != nil && selectedDocId != wasIn { wake() }
    }

    /// Home is a button, not a row entry — so it keeps its circle whatever
    /// happens to the documents, and it carries the accent when it is the
    /// place you are. A tinted glyph rather than a tinted circle: the group
    /// is already a shape, and tinting both would be saying it twice.
    private func makeHome(_ t: TabItem) -> UIButton {
        var c = UIButton.Configuration.plain()
        c.image = UIImage(systemName: t.symbol)
        c.preferredSymbolConfigurationForImage =
            UIImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        c.contentInsets = .zero
        c.baseForegroundColor = t.selected
            ? GlassTabBarView.accent : .secondaryLabel

        let b = GlassButton(configuration: c)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.isPointerInteractionEnabled = true
        b.onTap = { [weak self] in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            self?.channel.invokeMethod("tap", arguments: ["id": t.id])
        }
        return b
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
            ? GlassTabBarView.accentFill
            : .clear

        // M205 — GlassButton recovers a press that the scroll view or the
        // engine cancelled without it ever having moved. See GlassButton.swift.
        let b = GlassButton(configuration: c)
        b.onTap = { [weak self] in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            self?.channel.invokeMethod("tap", arguments: ["id": t.id])
        }
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

        let x = GlassButton(configuration: xc)
        x.isPointerInteractionEnabled = true
        x.onTap = { [weak self] in
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            self?.channel.invokeMethod("close", arguments: ["id": t.id])
        }

        // The capsule belongs to the PAIR, so the close button sits inside the
        // selected tint rather than floating next to it.
        let wrap = UIView()
        wrap.backgroundColor = t.selected ? GlassTabBarView.accentFill : .clear
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

    // MARK: - Fold

    /// M260 — the model is under a finger.
    ///
    /// M265 — and only the FOLD half of that is Dart's to drive now. A camera
    /// that has stopped moving is not a reason to open the bar; reaching for
    /// the bar is the only reason to open the bar.
    private func setEngaged(_ on: Bool) {
        guard on else { return }
        rest()
    }

    @objc private func onHover(_ g: UIHoverGestureRecognizer) {
        if g.state == .began || g.state == .changed { wake() }
    }

    /// Someone reached for the bar. Open it, and start counting again.
    private func wake() {
        idle?.invalidate()
        idle = Timer.scheduledTimer(
            withTimeInterval: GlassTabBarView.idleFold, repeats: false
        ) { [weak self] _ in self?.rest() }
        guard !awake else { return }
        awake = true
        applyFold(animated: true)
    }

    /// Back to the document you are in.
    ///
    /// Named `rest` rather than `sleep` so it cannot be read as — or resolved
    /// against — Darwin's `sleep(_:)`. Arity separates them and the compiler is
    /// never confused; a person reading `sleep()` in a UIKit file might be.
    private func rest() {
        idle?.invalidate()
        idle = nil
        guard awake else { return }
        awake = false
        applyFold(animated: true)
    }

    deinit { idle?.invalidate() }

    /// Hides every document chip but the current one while the bar is folded.
    ///
    /// `isHidden` on an arranged subview rather than rebuilding the row: the
    /// stack view animates the collapse for free, the scroll offset survives,
    /// and the chips that come back are the same objects with the same
    /// gesture state. Rebuilding twice per orbit would be the M149 mistake
    /// again, one layer down.
    ///
    /// Nothing folds unless a document is actually current — otherwise the
    /// capsule would collapse to nothing and reappear as a stub, which reads
    /// as a glitch rather than as chrome getting out of the way.
    private func applyFold(animated: Bool) {
        let fold = !awake && docViews.contains(where: { $0.selected })
        let step = {
            for d in self.docViews {
                let hide = fold && !d.selected
                if d.view.isHidden != hide { d.view.isHidden = hide }
                d.view.alpha = hide ? 0 : 1
            }
            self.container.layoutIfNeeded()
        }
        guard animated else { return step() }
        // M265 — an ease, not a spring, for M263's reason: the capsule's edge
        // is a straight edge, and a straight edge that overshoots its target
        // and comes back reads as a mis-set constraint rather than as life.
        UIView.animate(
            withDuration: 0.26, delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState,
                      .allowUserInteraction],
            animations: step)
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
