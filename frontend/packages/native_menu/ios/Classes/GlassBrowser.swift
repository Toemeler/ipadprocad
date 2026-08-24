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
                self.glassView?.isHidden = !on
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
            ev.trailingAnchor.constraint(
                equalTo: container.trailingAnchor, constant: -i.right),
            ev.topAnchor.constraint(equalTo: container.topAnchor, constant: i.top),
            ev.bottomAnchor.constraint(
                equalTo: container.bottomAnchor, constant: -i.bottom),
        ])
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
            collection.trailingAnchor.constraint(
                equalTo: container.trailingAnchor, constant: -ci.right),
            collection.topAnchor.constraint(
                equalTo: container.topAnchor, constant: ci.top),
            collection.bottomAnchor.constraint(
                equalTo: container.bottomAnchor, constant: -ci.bottom),
        ])
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
            cell.accessories = accessories
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
        rows = list
        byId = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
        var snap = NSDiffableDataSourceSnapshot<Int, String>()
        snap.appendSections([0])
        snap.appendItems(list.map(\.id))
        dataSource.applySnapshotUsingReloadData(snap)
        pushMetrics()
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
