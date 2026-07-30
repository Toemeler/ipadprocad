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
    let hasEye: Bool
    let eyeOn: Bool
    let dim: Bool           // rolled back / hidden -> drawn faded
    let expandable: Bool
    let expanded: Bool
    let selected: Bool
    let isEop: Bool
    let tint: String?       // "blue" | "red" | nil
    let menu: [[[String: Any]]]  // sections of items: {id,title,symbol,destructive}

    init?(_ m: [String: Any]) {
        guard let id = m["id"] as? String, let label = m["label"] as? String
        else { return nil }
        self.id = id
        self.label = label
        depth = (m["depth"] as? NSNumber)?.intValue ?? 0
        symbol = m["symbol"] as? String ?? "cube"
        hasEye = (m["hasEye"] as? NSNumber)?.boolValue ?? false
        eyeOn = (m["eyeOn"] as? NSNumber)?.boolValue ?? true
        dim = (m["dim"] as? NSNumber)?.boolValue ?? false
        expandable = (m["expandable"] as? NSNumber)?.boolValue ?? false
        expanded = (m["expanded"] as? NSNumber)?.boolValue ?? false
        selected = (m["selected"] as? NSNumber)?.boolValue ?? false
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

    /// M129 — is [r] the last child at its own depth? Read off the FLATTENED
    /// row order: scanning forward, the first row that is not deeper ends this
    /// row's sibling run. Derived here rather than shipped from Dart so the
    /// payload and its decoder stay untouched — the flattened order already
    /// carries the whole tree shape.
    private func isLastChild(_ r: BrowserRow) -> Bool {
        guard let i = rows.firstIndex(where: { $0.id == r.id }) else { return true }
        var j = i + 1
        while j < rows.count {
            if rows[j].depth <= r.depth { return rows[j].depth < r.depth }
            j += 1
        }
        return true
    }
    private var byId: [String: BrowserRow] = [:]

    /// Live End of Part drag: the row the finger started on and how far it has
    /// travelled, in whole rows.
    private var eopStartY: CGFloat?
    private var eopStartIndex: Int?

    init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(
            name: "prototype/glass_browser/\(viewId)", binaryMessenger: messenger)
        super.init()
        container.frame = frame
        container.backgroundColor = .clear
        // M108 — the app is a dark tool UI. Left to its own devices the glass
        // resolves light and UIKit then picks DARK label colours, which is the
        // washed-out grey panel with near-black text in the device shot.
        // Pinning the trait makes the material render dark and .label become
        // light, which is the same decision every dark-chrome Apple app makes.
        container.overrideUserInterfaceStyle = .dark
        buildGlass()
        buildCollection()
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self else { return result(nil) }
            switch call.method {
            case "setRows":
                let list = (call.arguments as? [[String: Any]]) ?? []
                self.apply(list.compactMap(BrowserRow.init))
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
    static let inset = UIEdgeInsets(top: 12, left: 28, bottom: 12, right: 0)

    // M129 — feature-tree palette, matched to the reference screenshots.
    /// Warm amber of a filled container folder.
    static let folderAmber = UIColor(red: 0.88, green: 0.76, blue: 0.44, alpha: 1)
    /// The dotted tree rules. Faint on purpose: they are a reading aid, and at
    /// full contrast a deep tree turns into a ladder that outshouts the labels.
    static let treeRule = UIColor(white: 1.0, alpha: 0.26)
    /// One indent step. Must match `indentationWidth` below or the dots drift
    /// away from the glyph column they are supposed to line up with.
    static let indentStep: CGFloat = 11

    /// A cell that draws the dotted ancestry rules behind its content.
    /// UIKit list cells have no notion of tree rules, so the guides are drawn
    /// per row: one dotted vertical per ancestor level, plus the elbow into
    /// this row's own glyph. Rows carry their depth already, which is all the
    /// geometry this needs — no second tree model to keep in sync.
    final class TreeRuleView: UIView {
        var depth: Int = 0 { didSet { setNeedsDisplay() } }
        var isLast: Bool = false { didSet { setNeedsDisplay() } }

        override func draw(_ rect: CGRect) {
            guard depth > 0, let ctx = UIGraphicsGetCurrentContext() else { return }
            ctx.setStrokeColor(GlassBrowserView.treeRule.cgColor)
            ctx.setLineWidth(1)
            ctx.setLineDash(phase: 0, lengths: [1, 2])
            let step = GlassBrowserView.indentStep
            let mid = rect.height / 2
            // One vertical rule per ANCESTOR level, full height of the row.
            for level in 1..<depth {
                let x = (CGFloat(level) * step) + 4.5
                ctx.move(to: CGPoint(x: x, y: 0))
                ctx.addLine(to: CGPoint(x: x, y: rect.height))
            }
            // This row's own rule stops at the elbow when it is the last child.
            let x = (CGFloat(depth) * step) + 4.5
            ctx.move(to: CGPoint(x: x, y: 0))
            ctx.addLine(to: CGPoint(x: x, y: isLast ? mid : rect.height))
            // Elbow out to the glyph.
            ctx.move(to: CGPoint(x: x, y: mid))
            ctx.addLine(to: CGPoint(x: x + step - 2, y: mid))
            ctx.strokePath()
        }
    }

    private func buildCollection() {
        var config = UICollectionLayoutListConfiguration(appearance: .plain)
        // M108 — a CAD tree wants density, not Settings-app spacing; the row
        // metrics are tightened per-cell below (contentConfiguration margins).
        // Let the glass through: no opaque list background of our own.
        config.backgroundColor = .clear
        config.showsSeparators = false
        config.trailingSwipeActionsConfigurationProvider = nil
        let layout = UICollectionViewCompositionalLayout.list(using: config)

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
                top: 3, leading: 4, bottom: 3, trailing: 4)
            // M118 — with no label the row is icon-only (the retracted
            // panel); centring it keeps the column of glyphs straight instead
            // of hugging the left edge where the text used to start.
            c.imageToTextPadding = r.label.isEmpty ? 0 : 6
            if r.label.isEmpty {
                // M121 — retracted rows: a slim, symmetric margin so the glyph
                // column is centred and never clipped against the panel edge.
                // 12 pt of leading on a ~50 pt wide content area pushed the
                // 16 pt symbol into the trailing edge.
                c.directionalLayoutMargins = NSDirectionalEdgeInsets(
                    top: 5, leading: 4, bottom: 5, trailing: 4)
                c.imageProperties.reservedLayoutSize =
                    CGSize(width: 20, height: 20)
                c.imageProperties.maximumSize = CGSize(width: 18, height: 18)
            }
            // Dark trait is pinned on the container, so .label is the light
            // text the rest of the app uses; dim rows drop to secondary rather
            // than tertiary, which was too faint to read on glass.
            c.textProperties.color = r.dim ? .secondaryLabel : .label
            c.image = UIImage(systemName: r.symbol)
            c.imageProperties.preferredSymbolConfiguration =
                UIImage.SymbolConfiguration(pointSize: 11, weight: .regular)
            c.imageProperties.reservedLayoutSize = CGSize(width: 16, height: 16)
            c.imageProperties.maximumSize = CGSize(width: 16, height: 16)
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
            cell.indentationWidth = 11
            cell.contentConfiguration = c

            var bg = UIBackgroundConfiguration.listPlainCell()
            bg.backgroundColor = r.selected
                ? UIColor.systemBlue.withAlphaComponent(0.28)
                : .clear
            // M129 — the dotted ancestry rules ride in the background view, so
            // they sit BEHIND the selection tint and never fight the label.
            // Reused across dequeues: a fresh view per bind would churn a layer
            // on every scroll tick.
            let rule = (bg.customView as? TreeRuleView) ?? TreeRuleView()
            rule.backgroundColor = .clear
            rule.isOpaque = false
            rule.depth = r.depth
            rule.isLast = self.isLastChild(r)
            bg.customView = rule
            cell.backgroundConfiguration = bg

            var accessories: [UICellAccessory] = []
            if r.expandable {
                // M129 — a boxed +/- at the LEADING edge, the way a feature
                // tree has always drawn it, instead of UIKit's rotating
                // chevron. outlineDisclosure also animates a rotation on every
                // toggle, which reads as a list control rather than a tree.
                let b = UIButton(type: .system)
                b.setImage(UIImage(systemName: r.expanded
                                   ? "minus.square" : "plus.square"),
                           for: .normal)
                b.setPreferredSymbolConfiguration(
                    UIImage.SymbolConfiguration(pointSize: 10, weight: .regular),
                    forImageIn: .normal)
                b.frame = CGRect(x: 0, y: 0, width: 16, height: 16)
                b.tintColor = .secondaryLabel
                b.addAction(UIAction { [weak self] _ in
                    self?.channel.invokeMethod(
                        "expand", arguments: ["id": r.id, "on": !r.expanded])
                }, for: .touchUpInside)
                accessories.append(.customView(configuration: .init(
                    customView: b, placement: .leading(displayed: .always),
                    reservedLayoutWidth: .custom(16))))
            }
            if r.hasEye {
                let b = UIButton(type: .system)
                b.setImage(UIImage(systemName: r.eyeOn ? "eye" : "eye.slash"),
                           for: .normal)
                b.setPreferredSymbolConfiguration(
                    UIImage.SymbolConfiguration(pointSize: 11), forImageIn: .normal)
                b.frame = CGRect(x: 0, y: 0, width: 22, height: 22)
                b.tintColor = r.eyeOn ? .secondaryLabel : .tertiaryLabel
                b.addAction(UIAction { [weak self] _ in
                    self?.channel.invokeMethod("eye", arguments: ["id": r.id])
                }, for: .touchUpInside)
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
    }

    private func apply(_ list: [BrowserRow]) {
        rows = list
        byId = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
        var snap = NSDiffableDataSourceSnapshot<Int, String>()
        snap.appendSections([0])
        snap.appendItems(list.map(\.id))
        dataSource.applySnapshotUsingReloadData(snap)
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
            return UIMenu(title: r.label, children: sections)
        }
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
