// Prototype — the model browser as 100% native Apple UI (M107).
//
// A UICollectionView list on real Liquid Glass. Everything the browser does is
// UIKit here: rows, disclosure, the eye toggles, context menus and the End of
// Part drag. Dart pushes a flat row model and receives events back; it no
// longer draws or hit-tests anything in this panel.
//
// WHY NATIVE IS ACTUALLY BETTER HERE, not just prettier: every hard bug in
// this panel came from the Flutter/UIKit boundary. M48 — a platform view
// swallowed taps until it was wrapped in IgnorePointer. M102 — a
// UIContextMenuInteraction registered over the End of Part row cancelled the
// Flutter drag, and it took four milestones to find, because UIKit's
// long-press recogniser takes the touch away from Flutter at ~150 ms. Inside
// UIKit there is no such boundary: a cell's context-menu interaction and its
// pan recogniser negotiate in ONE gesture system, so the drag and the menu can
// finally coexist on the same row.
import Flutter
import UIKit

// ---------------------------------------------------------------------------
// Row model pushed from Dart
// ---------------------------------------------------------------------------

struct BrowserRow {
    let id: String
    let depth: Int
    let symbol: String      // SF Symbol name
    let label: String
    let title: String       // M243 — the NAME, even when the label is hidden
    let hasEye: Bool
    let eyeOn: Bool
    let dim: Bool           // rolled back / hidden -> drawn faded
    let expandable: Bool
    let expanded: Bool
    let selected: Bool
    let hovered: Bool       // M242 — pointer prehighlight
    let isEop: Bool
    let tint: String?       // "blue" | "red" | nil
    let menu: [[[String: Any]]]  // sections of items: {id,title,symbol,destructive}

    init?(_ m: [String: Any]) {
        guard let id = m["id"] as? String, let label = m["label"] as? String
        else { return nil }
        self.id = id
        self.label = label
        title = m["title"] as? String ?? label
        depth = (m["depth"] as? NSNumber)?.intValue ?? 0
        symbol = m["symbol"] as? String ?? "cube"
        hasEye = (m["hasEye"] as? NSNumber)?.boolValue ?? false
        eyeOn = (m["eyeOn"] as? NSNumber)?.boolValue ?? true
        dim = (m["dim"] as? NSNumber)?.boolValue ?? false
        expandable = (m["expandable"] as? NSNumber)?.boolValue ?? false
        expanded = (m["expanded"] as? NSNumber)?.boolValue ?? false
        selected = (m["selected"] as? NSNumber)?.boolValue ?? false
        hovered = (m["hovered"] as? NSNumber)?.boolValue ?? false
        isEop = (m["isEop"] as? NSNumber)?.boolValue ?? false
        tint = m["tint"] as? String
        menu = (m["menu"] as? [[[String: Any]]]) ?? []
    }
}

// ---------------------------------------------------------------------------
// The platform view
// ---------------------------------------------------------------------------

@available(iOS 15.0, *)
final class GlassBrowserView: NSObject, FlutterPlatformView,
                              UICollectionViewDelegate {
    private let container = UIView()
    private var collection: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, String>!
    private let channel: FlutterMethodChannel

    private var rows: [BrowserRow] = []

    private var byId: [String: BrowserRow] = [:]

    /// Live End of Part drag: the row the finger started on and how far it has
    /// travelled, in whole rows.
    private var eopStartY: CGFloat?
    private var eopStartIndex: Int?

    /// M199 — the glass slab itself, kept so it can be taken away. Retracted,
    /// the panel is a column of icons over the model and a frosted plate
    /// behind them is just something else covering the drawing.
    private var glassView: UIVisualEffectView?

    // ---- M262: THE MORPH ---------------------------------------------------
    //
    // M204 took the retract animation away, and it was right to: the card is a
    // UiKitView, resizing one is an ASYNC round trip to the platform-view
    // controller, and animating its width fires that trip on every frame of
    // the curve. A dozen resizes in flight, the last to land wins whether or
    // not it was the last sent, and Flutter goes on painting the texture at
    // the widget's size — so you saw icons where the touch interceptor no
    // longer was. "when its retracted i cant use the icons."
    //
    // The animation comes back on the other side of that boundary. Dart still
    // resizes the platform view EXACTLY ONCE per toggle — it holds the card at
    // its wide size for the length of the morph and settles afterwards, so the
    // resize always lands on a still panel with nothing in flight. What moves
    // is everything INSIDE these bounds, which is UIKit's own layer and costs
    // no round trip at all: the glass plate and the list contract to the glyph
    // column while the wide rows dissolve into the narrow ones.
    //
    // Collapsing, the bounds are still wide while the content shrinks, and the
    // shrink to 56 pt afterwards is invisible because nothing is drawn out
    // there any more. Expanding, the bounds are wide from the first frame and
    // the content grows into them. Either way the seam falls where there is
    // nothing to see.

    /// One toggle, one curve. Dart's settle timer waits on this, so the two
    /// numbers have to agree — see `_kMorph` in native_browser_host.dart.
    ///
    /// M263 — and it is an EASE, not a spring. The first cut of this used
    /// `usingSpringWithDamping: 0.9` on the panel's width, which overshoots by
    /// a couple of percent: retracting, the glass edge dipped past the glyph
    /// column and came back. On a bouncing button that reads as life; on the
    /// straight edge of a panel it reads as a mis-set constraint. Apple's
    /// guidance for this is "quick, precise animations that combine brevity
    /// and precision" — a spring is for something you are dragging, and a
    /// chevron tap is not direct manipulation.
    static let morph: TimeInterval = 0.28

    /// Every animation in the morph runs on these, so the panel moves as one
    /// object rather than as three properties that happen to start together.
    static let morphCurve: UIView.AnimationOptions =
        [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction]

    /// The card's width, ABSOLUTE, and told to us rather than taken from the
    /// container.
    ///
    /// This is the part that has to be got right. The container is the
    /// platform view, and its bounds change on Flutter's schedule: an async
    /// round trip that lands a frame or two after the toggle, and — opening —
    /// AFTER this animation has already started. Pinning the content to the
    /// container's trailing edge would therefore animate toward the OLD width
    /// and then be snapped to the new one by the layout pass that follows the
    /// resize, which is a jump wearing an animation's clothes.
    ///
    /// So Dart sends the number. It owns `_kWide` and `_kNarrow` already, the
    /// value arrives in the same turn as the rows it belongs with, and neither
    /// side keeps a copy of the other's geometry.
    private var glassWidth: NSLayoutConstraint!
    private var listWidth: NSLayoutConstraint!

    /// Wide, until Dart says otherwise on the first push — `_kWide` less this
    /// view's own insets. Only ever seen if a card is built and never told its
    /// width, which the force-push on create rules out.
    static let defaultContentWidth: CGFloat = 250

    /// True while the rows are the glyph-only set.
    private var retracted = false
    /// What the last `setGlass` asked for, so a completion block cannot hide a
    /// plate that a second toggle has already brought back.
    private var glassOn = true

    // The FIRST value on each channel is the panel's starting state, not a
    // change to it, and it is applied without animation. Dart force-pushes all
    // three when the view is created; without these the card would open on
    // screen by playing its retract animation at whoever just launched the
    // app. One flag per channel rather than one shared: they arrive as three
    // separate calls, so a single flag set by the first would only un-prime
    // the other two.
    private var sawRows = false
    private var sawGlass = false
    private var sawCard = false

    init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(
            name: "prototype/glass_browser/\(viewId)", binaryMessenger: messenger)
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
        buildCollection()
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self else { return result(nil) }
            switch call.method {
            case "setRows":
                let list = (call.arguments as? [[String: Any]]) ?? []
                self.apply(list.compactMap(BrowserRow.init))
                result(nil)
            case "setGlass":
                let on = (call.arguments as? NSNumber)?.boolValue ?? true
                self.setGlass(on)
                result(nil)
            case "setCard":
                let w = (call.arguments as? NSNumber)?.doubleValue ?? 0
                self.setCard(CGFloat(w))
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    func view() -> UIView { container }

    // -- glass ---------------------------------------------------------------

    private func buildGlass() {
        let effect: UIVisualEffect
        if #available(iOS 26.0, *) {
            // The container effect is what lets several glass elements merge
            // and morph; the panel is one surface, so a plain glass effect
            // inside a container keeps the door open for floating controls
            // later without re-plumbing.
            let glass = UIGlassEffect()
            glass.isInteractive = false
            effect = glass
        } else {
            effect = UIBlurEffect(style: .systemMaterial)
        }
        let ev = UIVisualEffectView(effect: effect)
        // M108 — FLOATING: inset from the edges with rounded corners, so it
        // reads as a panel resting over the model rather than a wall glued to
        // the side. The viewport runs underneath it (see main.dart).
        //
        // M120 — AUTO LAYOUT, not frame + autoresizing. The frame was insetted
        // once at init, when `container.bounds` is still whatever Flutter
        // passed (often zero), and `flexibleWidth/Height` then SCALES that
        // frame instead of preserving the margin — so the card ended up flush
        // against the iPad's edge with no left padding at all. Constraints
        // keep the inset whatever the panel is resized to.
        ev.translatesAutoresizingMaskIntoConstraints = false
        ev.isUserInteractionEnabled = false
        ev.layer.cornerRadius = 18
        ev.layer.cornerCurve = .continuous
        ev.clipsToBounds = true
        container.addSubview(ev)
        glassView = ev
        let i = GlassBrowserView.inset
        NSLayoutConstraint.activate([
            ev.leadingAnchor.constraint(
                equalTo: container.leadingAnchor, constant: i.left),
            ev.topAnchor.constraint(equalTo: container.topAnchor, constant: i.top),
            ev.bottomAnchor.constraint(
                equalTo: container.bottomAnchor, constant: -i.bottom),
        ])
        // M262 — the plate's trailing edge is the thing that morphs.
        glassWidth = ev.widthAnchor.constraint(
            equalToConstant: GlassBrowserView.defaultContentWidth)
        glassWidth.isActive = true
    }

    /// M199's switch, M262's animation: the plate fades as it contracts, so it
    /// dissolves INTO the glyph column rather than blinking out from behind
    /// it.
    private func setGlass(_ on: Bool) {
        guard let ev = glassView else { return }
        glassOn = on
        if on { ev.isHidden = false }
        guard sawGlass else {
            sawGlass = true
            ev.alpha = on ? 1 : 0
            ev.isHidden = !on
            return
        }
        // M263 — THE PLATE MORPHS, IT DOES NOT DISSOLVE.
        //
        // "The glass does not just fade — it physically morphs from one shape
        // to another, MAINTAINING THE TRANSLUCENT MATERIAL throughout the
        // animation." The first cut faded alpha over the same 280 ms the plate
        // was contracting in, so the material was three-quarters gone before
        // the shape had arrived: what you saw was a panel evaporating, not one
        // changing shape.
        //
        // The fade is pushed to the ends instead, and the shape change owns
        // the middle. Retracting, the plate contracts at full strength and
        // only lets go once it has reached the glyph column (M199 — retracted,
        // there is no plate). Opening, it arrives first and grows with the
        // panel, so the material is under the rows the whole way out.
        let d = GlassBrowserView.morph
        UIView.animate(
            withDuration: d * 0.45, delay: on ? 0 : d * 0.55,
            options: GlassBrowserView.morphCurve,
            animations: { ev.alpha = on ? 1 : 0 },
            completion: { _ in
                // Only if nothing has changed its mind in the meantime: a
                // second toggle inside 280 ms would otherwise be undone by
                // the first one's completion.
                if self.glassOn == on { ev.isHidden = !on }
            })
    }

    /// M262 — the panel's width, animated. [w] is the CARD's width as Dart
    /// draws it; the insets are ours, so we take them off here rather than
    /// making Dart keep a copy of them.
    ///
    /// Spring rather than a plain ease: the panel is an object being pushed
    /// aside and pulled back, and a linear contraction reads as a window being
    /// resized by a script.
    private func setCard(_ w: CGFloat) {
        let i = GlassBrowserView.inset
        let inner = max(0, w - i.left - i.right)
        let first = !sawCard
        sawCard = true
        guard inner != listWidth.constant else { return }
        glassWidth.constant = inner
        listWidth.constant = inner
        guard !first else { return container.layoutIfNeeded() }
        UIView.animate(
            withDuration: GlassBrowserView.morph, delay: 0,
            options: GlassBrowserView.morphCurve,
            animations: { self.container.layoutIfNeeded() })
    }

    // -- list ----------------------------------------------------------------

    /// Margin around the floating panel. M116 — a little more on the left,
    /// top and bottom now that it is a card rather than a wall, and less on
    /// the right so the tree keeps its width.
    /// M118 — more on the LEFT so the card never sits on the iPad's edge, and
    /// room on the right for the retract chevron Flutter draws over the panel.
    /// M150 — left 28 -> 14, matching the ribbon and the tab bar. At 28 the
    /// card stood noticeably further in than the ribbon above it, which read
    /// as a misalignment rather than a margin.
    static let inset = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 0)

    // M129 — feature-tree palette, matched to the reference screenshots.
    /// Warm amber of a filled container folder.
    static let folderAmber = UIColor(red: 0.88, green: 0.76, blue: 0.44, alpha: 1)
    /// One indent step, used by the cell's `indentationWidth`.
    static let indentStep: CGFloat = 11

    /// M244 — the trailing edge of the RETRACTED glyph column, in the view's
    /// own coordinates: the card's inset, the cell's leading margin and the
    /// reserved image box, which is all a 56 pt card holds. Flutter draws the
    /// retract chevron and has no way to know any of those three, so the
    /// number is sent rather than guessed at on the other side.
    static var glyphTrailing: CGFloat { inset.left + 4 + 20 }

    /// M148 — EXPLICIT row height.
    ///
    /// The content configuration has asked for 3 pt margins around an 11.5 pt
    /// label since M108, and the rows still came out at UIKit's ~44 pt on the
    /// device: a list section's group is `.estimated(44)` and the list cell
    /// will not self-size below its own standard metric, so tightening the
    /// margins alone did nothing measurable. A feature tree with fifteen
    /// bodies in it wants to SHOW fifteen bodies, so the height is now stated
    /// rather than negotiated.
    static let rowHeight: CGFloat = 26

    /// A cell that draws the dotted ancestry rules behind its content.
    /// UIKit list cells have no notion of tree rules, so the guides are drawn
    /// per row: one dotted vertical per ancestor level, plus the elbow into
    /// this row's own glyph. Rows carry their depth already, which is all the
    /// geometry this needs — no second tree model to keep in sync.
    // M200 — the dotted ancestry rules are GONE.
    //
    // "the point line in the Modell browser is buggy. it goes over the layer 1
    // currently", with a photo that shows exactly that: a dotted vertical line
    // running through the labels, its elbow poking out to the right of each
    // one as a stray "- -".
    //
    // They were drawn into the background configuration's custom view (M129),
    // whose coordinate space is not the cell's leading edge — so `depth * 11 +
    // 4.5` landed in the middle of the text instead of in the margin. Since
    // the panel is a platform view it is ABSENT from every bug-report
    // screenshot, which is why this survived so long and why a corrected
    // placement cannot be verified from here either.
    //
    // So the decoration goes rather than being guessed at again. The tree is
    // two or three levels deep and UIKit already indents it; the rules were
    // never carrying the hierarchy, only decorating it. If they come back they
    // belong in a view whose geometry is known — drawn in contentView
    // coordinates — and checked on the device.

    private func buildCollection() {
        // M148 — a plain section with an ABSOLUTE item height instead of
        // `.list(using:)`. Nothing the list configuration provided is actually
        // in use here: separators are off, swipe actions are nil, and the
        // background is cleared so the glass shows through. What it did
        // provide was a 44 pt estimated group height that no amount of margin
        // tightening could get under. Indentation and accessories belong to
        // UICollectionViewListCell, not to the section, so the cells are
        // unaffected by the change.
        let layout = UICollectionViewCompositionalLayout { _, _ in
            let size = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .absolute(GlassBrowserView.rowHeight))
            let item = NSCollectionLayoutItem(layoutSize: size)
            let group = NSCollectionLayoutGroup.vertical(
                layoutSize: size, subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 0
            return section
        }

        collection = UICollectionView(frame: .zero,
                                      collectionViewLayout: layout)
        // M120 — same reason as the glass: constraints, not autoresizing.
        collection.translatesAutoresizingMaskIntoConstraints = false
        collection.backgroundColor = .clear
        // Match the glass corners so rows cannot spill past the panel edge.
        collection.layer.cornerRadius = 18
        collection.layer.cornerCurve = .continuous
        collection.clipsToBounds = true
        collection.contentInset = UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        // M121 — dark panel: the default scroll indicator is black on glass.
        collection.indicatorStyle = .white
        container.addSubview(collection)
        let ci = GlassBrowserView.inset
        NSLayoutConstraint.activate([
            collection.leadingAnchor.constraint(
                equalTo: container.leadingAnchor, constant: ci.left),
            collection.topAnchor.constraint(
                equalTo: container.topAnchor, constant: ci.top),
            collection.bottomAnchor.constraint(
                equalTo: container.bottomAnchor, constant: -ci.bottom),
        ])
        // M262 — the list contracts with the plate, and it has to: a retracted
        // row's selection highlight is a CHIP inset 6 pt from either edge
        // (M243), so laid out in a still-wide cell it is a bar across the
        // card — the exact "invisible background bar" M243 exists to have got
        // rid of. Narrowing the list is what keeps the chip a chip for the
        // 280 ms the container is still wide.
        listWidth = collection.widthAnchor.constraint(
            equalToConstant: GlassBrowserView.defaultContentWidth)
        listWidth.isActive = true
        collection.delegate = self
        collection.allowsSelection = true

        let cell = UICollectionView.CellRegistration<UICollectionViewListCell, String> {
            [weak self] cell, _, id in
            guard let self, let r = self.byId[id] else { return }
            var c = cell.defaultContentConfiguration()
            c.text = r.label
            c.textProperties.font = .systemFont(ofSize: 11.5)
            // Pull the row in tight: the default list metrics are sized for
            // touch lists, and a feature tree needs to show a lot of rows.
            c.directionalLayoutMargins = NSDirectionalEdgeInsets(
                top: 2, leading: 4, bottom: 2, trailing: 4)
            // M118 — with no label the row is icon-only (the retracted
            // panel); centring it keeps the column of glyphs straight instead
            // of hugging the left edge where the text used to start.
            c.imageToTextPadding = r.label.isEmpty ? 0 : 6
            // Dark trait is pinned on the container, so .label is the light
            // text the rest of the app uses; dim rows drop to secondary rather
            // than tertiary, which was too faint to read on glass.
            c.textProperties.color = r.dim ? .secondaryLabel : .label
            c.image = UIImage(systemName: r.symbol)
            c.imageProperties.preferredSymbolConfiguration =
                UIImage.SymbolConfiguration(pointSize: 11, weight: .regular)
            c.imageProperties.reservedLayoutSize = CGSize(width: 16, height: 16)
            c.imageProperties.maximumSize = CGSize(width: 16, height: 16)
            // M204 — the retracted metrics come AFTER the shared ones.
            //
            // M121 wrote them first and the two unconditional lines above then
            // overwrote reservedLayoutSize and maximumSize, so the retracted
            // sizing has never once taken effect. Same values it always meant
            // to set, in the order that makes them stick.
            if r.label.isEmpty {
                // Retracted rows: a slim, symmetric margin so the glyph column
                // is centred and never clipped against the panel edge. 12 pt of
                // leading on a ~34 pt wide content area pushed the 16 pt symbol
                // into the trailing edge.
                c.directionalLayoutMargins = NSDirectionalEdgeInsets(
                    top: 5, leading: 4, bottom: 5, trailing: 4)
                // M243 — THE GLYPH UNDER THE POINTER GROWS.
                //
                // Retracted there is no label to highlight and no room for
                // one, so the row answers the pointer the way a dock icon
                // does: it gets bigger. The reserved size grows with it, or
                // the larger symbol would be clipped to the old box and
                // nothing visible would happen.
                let big = r.hovered
                c.imageProperties.reservedLayoutSize =
                    CGSize(width: big ? 26 : 20, height: big ? 26 : 20)
                c.imageProperties.maximumSize =
                    CGSize(width: big ? 24 : 18, height: big ? 24 : 18)
                c.imageProperties.preferredSymbolConfiguration =
                    UIImage.SymbolConfiguration(
                        pointSize: big ? 15 : 11, weight: .regular)
            }
            switch r.tint {
            case "blue": c.imageProperties.tintColor = .systemBlue
            case "red": c.imageProperties.tintColor = .systemRed
            // M129 — Inventor's container folders: a warm filled amber that
            // reads as a FOLDER at 11 pt, where a grey outline just read as
            // another feature glyph.
            case "folder": c.imageProperties.tintColor = GlassBrowserView.folderAmber
            default: c.imageProperties.tintColor = r.dim ? .tertiaryLabel : .secondaryLabel
            }
            // Indentation is the tree: UIKit owns it, no manual padding.
            cell.indentationLevel = r.depth
            cell.indentationWidth = GlassBrowserView.indentStep
            cell.contentConfiguration = c

            var bg = UIBackgroundConfiguration.listPlainCell()
            // M242 — selection, then the pointer prehighlight at half its
            // strength. Selected WINS on a row that is both: two washes would
            // compound into a third colour that means nothing.
            bg.backgroundColor = r.selected
                ? UIColor.systemBlue.withAlphaComponent(0.28)
                : (r.hovered
                   ? UIColor.systemBlue.withAlphaComponent(0.14)
                   : .clear)
            // M243 — retracted, that highlight is a CHIP around the glyph, not
            // a bar across the card. "It looks as if there was an invisible
            // background bar": a full-width wash on a 56 pt column of icons is
            // exactly that, and it is why the icons did not read as separate
            // items. Inset to the glyph and rounded, each row is its own
            // object again.
            if r.label.isEmpty {
                bg.backgroundInsets = NSDirectionalEdgeInsets(
                    top: 1, leading: 6, bottom: 1, trailing: 6)
                bg.cornerRadius = 9
            }
            cell.backgroundConfiguration = bg

            var accessories: [UICellAccessory] = []
            if r.expandable {
                // M129 — a boxed +/- at the LEADING edge, the way a feature
                // tree has always drawn it, instead of UIKit's rotating
                // chevron. outlineDisclosure also animates a rotation on every
                // toggle, which reads as a list control rather than a tree.
                // M205 — GlassButton: a 16-pt target inside a scrolling
                // tree is the hardest press in the app, and a cancelled one
                // used to be lost outright. The recovery ignores anything the
                // finger dragged, so scrolling the tree still just scrolls.
                let b = GlassButton(frame: .zero)
                b.setImage(UIImage(systemName: r.expanded
                                   ? "minus.square" : "plus.square"),
                           for: .normal)
                b.setPreferredSymbolConfiguration(
                    UIImage.SymbolConfiguration(pointSize: 10, weight: .regular),
                    forImageIn: .normal)
                b.frame = CGRect(x: 0, y: 0, width: 16, height: 16)
                b.tintColor = .secondaryLabel
                b.onTap = { [weak self] in
                    self?.channel.invokeMethod(
                        "expand", arguments: ["id": r.id, "on": !r.expanded])
                }
                accessories.append(.customView(configuration: .init(
                    customView: b, placement: .leading(displayed: .always),
                    reservedLayoutWidth: .custom(16))))
            }
            if r.hasEye {
                let b = GlassButton(frame: .zero)
                b.setImage(UIImage(systemName: r.eyeOn ? "eye" : "eye.slash"),
                           for: .normal)
                b.setPreferredSymbolConfiguration(
                    UIImage.SymbolConfiguration(pointSize: 11), forImageIn: .normal)
                b.frame = CGRect(x: 0, y: 0, width: 22, height: 22)
                b.tintColor = r.eyeOn ? .secondaryLabel : .tertiaryLabel
                b.onTap = { [weak self] in
                    self?.channel.invokeMethod("eye", arguments: ["id": r.id])
                }
                accessories.append(.customView(configuration: .init(
                    customView: b, placement: .trailing(displayed: .always))))
            }
            // M264 — THE BOXES FLEW UP ON EVERY TAB SWITCH.
            //
            // "the boxes of the elements seem to fly up every time i switch
            // tab". The boxes are these: the +/- accessory M129 puts at the
            // leading edge, and the eye at the trailing one.
            //
            // UICollectionViewListCell ANIMATES an accessory change on a cell
            // that is already configured, and a reloaded list does not hand
            // out fresh cells — it hands out cells from the reuse pool, still
            // carrying the last document's accessories. So switching tabs is
            // an accessory swap on a live cell, which UIKit obligingly
            // animates in from nothing, one per row. It has been doing that
            // since M129; it takes a second document to notice.
            //
            // The content configuration above is deliberately NOT wrapped:
            // during a retract (M263) that IS the animation — the glyph moving
            // from its indentation to the column. Only the accessories are
            // silenced, and they are the right thing to silence, because they
            // exist in one state and not the other and have nowhere to move
            // from.
            UIView.performWithoutAnimation { cell.accessories = accessories }
        }

        dataSource = UICollectionViewDiffableDataSource<Int, String>(
            collectionView: collection
        ) { cv, indexPath, id in
            cv.dequeueConfiguredReusableCell(using: cell, for: indexPath, item: id)
        }

        // End of Part drag — a plain pan recogniser. Inside UIKit this
        // negotiates with the list's own scroll and with the cell's context
        // menu in ONE gesture system, which is exactly what could not be made
        // to work across the Flutter boundary (see the file header).
        let pan = UIPanGestureRecognizer(target: self, action: #selector(onPan(_:)))
        pan.delegate = self
        collection.addGestureRecognizer(pan)
        // M121 — THE EOP DRAG, AGAIN, AND FINALLY THE RIGHT LAYER.
        //
        // Adding a pan to a collection view is not enough: the list has its own
        // `panGestureRecognizer`, it was installed first, and a scroll view's
        // pan is greedy — it claimed the touch and the marker never moved,
        // exactly as before, just one layer further down. Making the scroll
        // pan REQUIRE ours to fail hands the touch over when the drag starts on
        // the End of Part row.
        //
        // This does not cost scrolling anywhere else: gestureRecognizerShouldBegin
        // rejects immediately for any other row, so the scroll pan is released
        // in the same event.
        collection.panGestureRecognizer.require(toFail: pan)

        // M242 — POINTER HOVER (trackpad, or Apple Pencil on a hover-capable
        // iPad). The row under the pointer is published to Dart, which lights
        // the matching solid in 3D as well; touch input never fires this, so a
        // finger-only session behaves exactly as before.
        let hover = UIHoverGestureRecognizer(
            target: self, action: #selector(onHover(_:)))
        collection.addGestureRecognizer(hover)
    }

    /// The row the pointer last reported, so a move WITHIN one row costs
    /// nothing: a hover push reloads the tree's snapshot on the Dart side.
    private var hoveredId = ""

    @objc private func onHover(_ g: UIHoverGestureRecognizer) {
        var id = ""
        var y = 0.0
        if g.state == .began || g.state == .changed {
            let pt = g.location(in: collection)
            if let ip = collection.indexPathForItem(at: pt),
               ip.item < rows.count {
                id = rows[ip.item].id
                // M243 — the row's CENTRE, in the platform view's own
                // coordinates: Dart parks the tooltip beside it, and only this
                // side knows where a row ended up once the list has scrolled.
                if let f = collection.layoutAttributesForItem(at: ip)?.frame {
                    y = Double(collection.convert(f, to: container).midY)
                }
            }
        }
        // "" is "the pointer is over no row", including .ended: an empty string
        // rather than a nil keeps the argument map free of NSNull.
        if id == hoveredId { return }
        hoveredId = id
        channel.invokeMethod("hover", arguments: ["id": id, "y": y])
    }

    private func apply(_ list: [BrowserRow]) {
        // M262 — is this the retract, or just a model change?
        //
        // Read off the payload rather than asked for over a third channel
        // call: Dart sends the glyph-only row set when the card retracts and
        // the labelled one when it opens, so the answer is already here and
        // cannot arrive out of step with the rows it describes. Every row, not
        // the first: a single unlabelled row in a labelled tree is a row with
        // no name, not a retracted panel.
        let empty = list.isEmpty
        let nowRetracted = !empty && list.allSatisfy { $0.label.isEmpty }
        let morphing = sawRows && !empty && nowRetracted != retracted
        if !empty {
            retracted = nowRetracted
            sawRows = true
        }

        // M263 — the rows are the SAME ROWS, so they have to stay the same
        // rows. See morphRows below.
        let sameItems = rows.map(\.id) == list.map(\.id)
        self.rows = list
        byId = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })

        if morphing && sameItems {
            morphRows()
        } else {
            var snap = NSDiffableDataSourceSnapshot<Int, String>()
            snap.appendSections([0])
            snap.appendItems(list.map(\.id))
            dataSource.applySnapshotUsingReloadData(snap)
        }
        pushMetrics()
    }

    /// M263 — RECONFIGURE, DO NOT RELOAD.
    ///
    /// The first cut of the morph lifted the old rows off as a snapshot view
    /// and cross-faded them against the new ones. That is a dissolve, and a
    /// dissolve is the opposite of a morph: for 280 ms there were TWO copies
    /// of every glyph on screen, at two different x, both half-transparent,
    /// sliding apart. Which is exactly what "looks weird" looks like.
    ///
    /// The mistake was reaching for a transition at all. Retracting does not
    /// replace the tree, it restates it — same rows, same ids, same glyphs,
    /// minus the labels and the indentation. A morph is continuity of
    /// identity: the thing that exists in both states MOVES, and only what is
    /// unique to one state fades. Here that means one glyph per row travelling
    /// from its indented position to the column, and nothing else.
    ///
    /// `reconfigureItems` is what buys that. It re-runs the cell registration
    /// against the EXISTING cell rather than dequeuing a new one — "choose to
    /// reconfigure items instead of reloading items unless you have an
    /// explicit need to replace the existing cell" — so the views that draw
    /// the row are the same objects before and after. Whatever else happens,
    /// there is only ever one copy of each glyph on screen, which is the fault
    /// being fixed.
    ///
    /// `animatingDifferences: true`, and NOT wrapped in a `UIView.animate`
    /// block: passing false makes the data source apply the update inside
    /// `performWithoutAnimation`, which would cancel the very block it was
    /// nested in. UIKit's own batch update is the animation here.
    ///
    /// Only when the row SET is unchanged. A morph that coincides with a
    /// feature being added has rows to insert, and an insertion animation has
    /// nothing to gain from this one.
    private func morphRows() {
        var snap = dataSource.snapshot()
        snap.reconfigureItems(snap.itemIdentifiers)
        dataSource.apply(snap, animatingDifferences: true)
    }

    /// M244 — where the rows actually are, so the retract handle can stand
    /// beside them instead of in the middle of an empty panel.
    ///
    /// Arithmetic over this file's own metrics rather than a question for the
    /// layout: the rows are a uniform height, the two insets are constants,
    /// and asking `layoutAttributesForItem` would tie the answer to whether a
    /// layout pass had run yet — which, straight after a snapshot, it has not.
    /// Scrolling is deliberately not tracked: a handle that slid up and down
    /// with the list would be harder to find than one that stays put.
    private func pushMetrics() {
        let top = GlassBrowserView.inset.top + 6 // + the collection's own inset
        let bottom = top + CGFloat(rows.count) * GlassBrowserView.rowHeight
        channel.invokeMethod("metrics", arguments: [
            "top": Double(top),
            "bottom": Double(bottom),
            "x": Double(GlassBrowserView.glyphTrailing),
        ])
    }

    // -- interaction ---------------------------------------------------------

    func collectionView(_ cv: UICollectionView,
                        didSelectItemAt indexPath: IndexPath) {
        cv.deselectItem(at: indexPath, animated: false)
        guard indexPath.item < rows.count else { return }
        channel.invokeMethod("tap", arguments: ["id": rows[indexPath.item].id])
    }

    /// Native context menu, straight off the cell — no rect registration, no
    /// interaction competing with Flutter for the touch.
    func collectionView(
        _ cv: UICollectionView,
        contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let ip = indexPaths.first, ip.item < rows.count else { return nil }
        let r = rows[ip.item]
        if r.menu.isEmpty { return nil }
        return UIContextMenuConfiguration(identifier: r.id as NSString,
                                          previewProvider: nil) { _ in
            let sections: [UIMenuElement] = r.menu.compactMap { group in
                let items: [UIAction] = group.compactMap { m in
                    guard let id = m["id"] as? String,
                          let title = m["title"] as? String else { return nil }
                    let destructive = (m["destructive"] as? NSNumber)?.boolValue ?? false
                    return UIAction(
                        title: title,
                        image: (m["symbol"] as? String).flatMap {
                            UIImage(systemName: $0)
                        },
                        attributes: destructive ? .destructive : []
                    ) { [weak self] _ in
                        self?.channel.invokeMethod(
                            "menu", arguments: ["id": r.id, "item": id])
                    }
                }
                if items.isEmpty { return nil }
                return UIMenu(title: "", options: .displayInline, children: items)
            }
            return UIMenu(title: r.title, children: sections)
        }
    }

    /// M243 — WHAT A LONG PRESS LIFTS.
    ///
    /// With no preview of our own UIKit lifts the whole cell, and a cell here
    /// is the full width of the card with a transparent background: the press
    /// produced a wide, empty slab with a glyph somewhere inside it — "it
    /// looks as if there was an invisible background bar". The preview is
    /// clipped to what the row actually DRAWS instead: the icon chip when the
    /// panel is retracted, the row itself when it is not.
    private func liftPreview(_ configuration: UIContextMenuConfiguration)
        -> UITargetedPreview? {
        guard let ns = configuration.identifier as? NSString else { return nil }
        let id = ns as String
        guard let i = rows.firstIndex(where: { $0.id == id }),
              let cell = collection.cellForItem(at: IndexPath(item: i, section: 0))
        else { return nil }
        let b = cell.bounds
        // Matches the background chip above, so what lifts is what was lit.
        let rect = rows[i].label.isEmpty
            ? b.insetBy(dx: max(0, (b.width - 34) / 2), dy: 1)
            : b.insetBy(dx: 2, dy: 1)
        let p = UIPreviewParameters()
        p.backgroundColor = .clear
        p.visiblePath = UIBezierPath(roundedRect: rect, cornerRadius: 9)
        return UITargetedPreview(view: cell, parameters: p)
    }

    func collectionView(
        _ cv: UICollectionView,
        previewForHighlightingContextMenuWithConfiguration
            configuration: UIContextMenuConfiguration
    ) -> UITargetedPreview? {
        liftPreview(configuration)
    }

    func collectionView(
        _ cv: UICollectionView,
        previewForDismissingContextMenuWithConfiguration
            configuration: UIContextMenuConfiguration
    ) -> UITargetedPreview? {
        liftPreview(configuration)
    }

    /// M122 — the End of Part row under [pt], with a little slack.
    ///
    /// The drag was hit and miss because `indexPathForItem(at:)` returns nil in
    /// the hairline BETWEEN cells and just outside a cell's bounds — start
    /// there and the gesture failed, so the list scrolled instead and the
    /// marker did not move. Probing a few points around the touch turns "grab
    /// the marker" into something you can actually hit.
    private func eopIndex(at pt: CGPoint) -> Int? {
        for dy in [CGFloat(0), -6, 6, -12, 12] {
            let probe = CGPoint(x: pt.x, y: pt.y + dy)
            guard let ip = collection.indexPathForItem(at: probe),
                  ip.item < rows.count else { continue }
            if rows[ip.item].isEop { return ip.item }
        }
        return nil
    }

    @objc private func onPan(_ g: UIPanGestureRecognizer) {
        let pt = g.location(in: collection)
        switch g.state {
        case .began:
            guard let i = eopIndex(at: pt) else {
                g.state = .failed // not the marker: let the list scroll
                return
            }
            eopStartY = pt.y
            eopStartIndex = i
            // Nothing should slide under the finger while the marker moves.
            collection.isScrollEnabled = false
        case .changed:
            guard let y0 = eopStartY, let i0 = eopStartIndex else { return }
            // Rows are uniform height in a plain list; ask the layout rather
            // than assuming a constant, which is what got the Flutter version
            // wrong twice.
            let h = collection.layoutAttributesForItem(
                at: IndexPath(item: i0, section: 0))?.frame.height ?? 44
            let steps = Int(((pt.y - y0) / h).rounded())
            channel.invokeMethod("eopDrag", arguments: ["steps": steps])
        case .ended, .cancelled, .failed:
            collection.isScrollEnabled = true
            if eopStartIndex != nil {
                channel.invokeMethod("eopEnd", arguments: nil)
            }
            eopStartY = nil
            eopStartIndex = nil
        default:
            break
        }
    }
}

@available(iOS 15.0, *)
extension GlassBrowserView: UIGestureRecognizerDelegate {
    /// The pan only claims the touch when it starts ON the End of Part row;
    /// everywhere else the list keeps its scrolling.
    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        eopIndex(at: g.location(in: collection)) != nil
    }
}

@available(iOS 15.0, *)
final class GlassBrowserFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger
    init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }

    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64,
                arguments args: Any?) -> FlutterPlatformView {
        GlassBrowserView(frame: frame, viewId: viewId, messenger: messenger)
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }
}
