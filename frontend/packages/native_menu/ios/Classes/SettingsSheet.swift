// M261 — the app's Settings, as a real UIKit form sheet.
//
// WHY NATIVE AND NOT FLUTTER. Settings is the one screen in this app that is
// not about drawing, and it is the screen a user arrives at with the strongest
// expectations: they have opened iOS Settings a thousand times and they know
// exactly what a grouped table with checkmarks does. Drawing a lookalike in
// Flutter would mean re-deriving row heights, separator insets, the selection
// flash, the grabber, Dynamic Type and VoiceOver — and being subtly wrong at
// all of them. UITableView is already right, and it is right in the next iOS
// version too.
//
// WHAT IS NATIVE HERE AND WHAT IS NOT. The chrome, the layout and every
// behaviour are UIKit's. The CONTENT is Dart's: sections and rows arrive as a
// spec so that every string comes from the ARB (this app is written in German
// and translated to English, never the other way round) and so the sheet has
// no opinion about what a setting means. It renders what it is given and
// reports what was tapped.
//
// THE ONE THING THAT MAKES IT FEEL LIVE. Tapping a row does not close the
// sheet. Dart applies the change and pushes a fresh spec, so the checkmark
// moves, and — when the language changed — every label in the sheet changes
// under your finger. That is the strongest confirmation a preference screen
// can give, and it costs one reload.
import Flutter
import UIKit

/// One row. `kind` decides what UIKit builds:
///   check  — single-select within its section; the selected one has a tick
///   action — a tappable command (Report a Problem, Share the Log)
///   value  — read-only, with a right-aligned detail (the About rows)
struct SettingsRow {
    let id: String
    let title: String
    let detail: String?
    let symbol: String?
    let kind: String
    let selected: Bool
    let destructive: Bool
}

struct SettingsSection {
    let id: String
    let header: String?
    let footer: String?
    let rows: [SettingsRow]
}

/// The grouped table itself.
///
/// `.insetGrouped`, which is what the Settings app and every modern iOS
/// preference screen uses; `.grouped` is the pre-iOS-13 look and reads as old
/// on an iPad running 26.
final class SettingsSheetController: UITableViewController {
    private var sections: [SettingsSection] = []
    private let onSelect: (String, String) -> Void
    private let onClose: () -> Void
    private var title_: String
    private var doneLabel: String

    init(title: String,
         doneLabel: String,
         sections: [SettingsSection],
         onSelect: @escaping (String, String) -> Void,
         onClose: @escaping () -> Void) {
        self.title_ = title
        self.doneLabel = doneLabel
        self.sections = sections
        self.onSelect = onSelect
        self.onClose = onClose
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = title_
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: doneLabel, style: .done, target: self, action: #selector(done))
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "row")
    }

    @objc private func done() {
        dismiss(animated: true) { [weak self] in self?.onClose() }
    }

    /// Replace the whole spec and redraw. Called after every tap, because Dart
    /// owns the state and this view owns none of it.
    func apply(title: String, doneLabel: String, sections: [SettingsSection]) {
        self.title_ = title
        self.doneLabel = doneLabel
        self.sections = sections
        self.title = title
        navigationItem.rightBarButtonItem?.title = doneLabel
        tableView.reloadData()
    }

    // MARK: - table

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(_ t: UITableView, numberOfRowsInSection s: Int) -> Int {
        sections[s].rows.count
    }

    override func tableView(_ t: UITableView, titleForHeaderInSection s: Int) -> String? {
        sections[s].header
    }

    override func tableView(_ t: UITableView, titleForFooterInSection s: Int) -> String? {
        sections[s].footer
    }

    override func tableView(_ t: UITableView,
                            cellForRowAt ip: IndexPath) -> UITableViewCell {
        let row = sections[ip.section].rows[ip.row]
        // A `value` row needs the .value1 style for its right-aligned detail,
        // and the recycler cannot change a cell's style after the fact — so
        // those get their own reuse identifier rather than a reused .default
        // cell that would silently drop the detail label.
        let cell: UITableViewCell
        if row.kind == "value" {
            cell = t.dequeueReusableCell(withIdentifier: "value")
                ?? UITableViewCell(style: .value1, reuseIdentifier: "value")
        } else {
            cell = t.dequeueReusableCell(withIdentifier: "row")
                ?? UITableViewCell(style: .default, reuseIdentifier: "row")
        }

        var content = cell.defaultContentConfiguration()
        content.text = row.title
        if row.kind == "value" { content.secondaryText = row.detail }
        if let symbol = row.symbol, let image = UIImage(systemName: symbol) {
            content.image = image
        }
        if row.destructive {
            content.textProperties.color = .systemRed
        } else if row.kind == "action" {
            content.textProperties.color = cell.tintColor
        }
        cell.contentConfiguration = content

        switch row.kind {
        case "check":
            cell.accessoryType = row.selected ? .checkmark : .none
            cell.selectionStyle = .default
        case "value":
            cell.accessoryType = .none
            // Not selectable: a row that flashes but does nothing reads as
            // broken, and these are facts, not controls.
            cell.selectionStyle = .none
        default:
            cell.accessoryType = .none
            cell.selectionStyle = .default
        }
        // VoiceOver: a checkmark is a visual affordance and says nothing on
        // its own, so the state is spelled out.
        cell.accessibilityTraits = row.kind == "value" ? .staticText : .button
        if row.kind == "check" && row.selected {
            cell.accessibilityTraits.insert(.selected)
        }
        return cell
    }

    override func tableView(_ t: UITableView, willSelectRowAt ip: IndexPath) -> IndexPath? {
        sections[ip.section].rows[ip.row].kind == "value" ? nil : ip
    }

    override func tableView(_ t: UITableView, didSelectRowAt ip: IndexPath) {
        t.deselectRow(at: ip, animated: true)
        let section = sections[ip.section]
        let row = section.rows[ip.row]
        if row.kind == "value" { return }
        onSelect(section.id, row.id)
    }
}

/// Owns the presented sheet, so `update` and `dismiss` have something to talk
/// to and a second `show` cannot stack two of them.
final class SettingsSheet {
    static let shared = SettingsSheet()

    private weak var controller: SettingsSheetController?
    private weak var nav: UINavigationController?

    var isPresented: Bool { controller != nil }

    /// Builds the spec from the channel arguments. Anything malformed is
    /// dropped rather than crashing the engine — the same rule the rest of
    /// this plugin follows for Dart-supplied maps.
    static func parse(_ raw: Any?) -> [SettingsSection] {
        guard let list = raw as? [[String: Any]] else { return [] }
        return list.compactMap { s in
            guard let id = s["id"] as? String else { return nil }
            let rows = (s["rows"] as? [[String: Any]] ?? []).compactMap { r -> SettingsRow? in
                guard let rid = r["id"] as? String,
                      let title = r["title"] as? String else { return nil }
                return SettingsRow(
                    id: rid,
                    title: title,
                    detail: r["detail"] as? String,
                    symbol: r["symbol"] as? String,
                    kind: r["kind"] as? String ?? "action",
                    selected: (r["selected"] as? NSNumber)?.boolValue ?? false,
                    destructive: (r["destructive"] as? NSNumber)?.boolValue ?? false)
            }
            return SettingsSection(
                id: id,
                header: (s["header"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                footer: (s["footer"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                rows: rows)
        }
    }

    /// Presents the sheet. Returns false when there is nothing to present
    /// from, so Dart can fall back rather than believing it opened.
    @discardableResult
    func show(title: String,
              doneLabel: String,
              sections: [SettingsSection],
              present: (UIViewController) -> Bool,
              onSelect: @escaping (String, String) -> Void,
              onClose: @escaping () -> Void) -> Bool {
        // Already up: re-use it rather than stacking a second sheet on top of
        // the first, which is what a double tap on the gear would otherwise do.
        if let existing = controller {
            existing.apply(title: title, doneLabel: doneLabel, sections: sections)
            return true
        }
        let vc = SettingsSheetController(
            title: title,
            doneLabel: doneLabel,
            sections: sections,
            onSelect: onSelect,
            onClose: { [weak self] in
                self?.controller = nil
                self?.nav = nil
                onClose()
            })
        let nav = UINavigationController(rootViewController: vc)
        // .formSheet is the iPad shape for a preference screen: a centred
        // card over a dimmed app, dismissible by the grabber or by tapping
        // outside. A full screen would hide the document the settings are
        // about, and a popover would put a preference screen on a stalk.
        nav.modalPresentationStyle = .formSheet
        nav.preferredContentSize = CGSize(width: 420, height: 560)
        if let sheet = nav.sheetPresentationController {
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 20
        }
        guard present(nav) else { return false }
        controller = vc
        self.nav = nav
        // A swipe-down dismissal never reaches the Done button, so the close
        // callback has to come from the delegate too or Dart would keep
        // believing the sheet is open.
        //
        // AFTER present, not before: `presentationController` is created
        // lazily for the current modalPresentationStyle, and reading it early
        // is the kind of thing that works until UIKit decides to hand out a
        // different one at presentation time. Once presented there is exactly
        // one and it is the one that will report the dismissal.
        DismissRelay.shared.onDismiss = { [weak self] in
            self?.controller = nil
            self?.nav = nil
            onClose()
        }
        nav.presentationController?.delegate = DismissRelay.shared
        return true
    }

    func update(title: String, doneLabel: String, sections: [SettingsSection]) {
        controller?.apply(title: title, doneLabel: doneLabel, sections: sections)
    }

    func dismiss() {
        guard let nav = nav else { return }
        controller = nil
        self.nav = nil
        nav.dismiss(animated: true, completion: nil)
    }
}

/// UIKit reports an interactive (swipe-down) dismissal through the
/// presentation controller's delegate, which has to be an object. One shared
/// relay rather than making SettingsSheet an NSObject subclass for it.
final class DismissRelay: NSObject, UIAdaptivePresentationControllerDelegate {
    static let shared = DismissRelay()
    var onDismiss: (() -> Void)?

    func presentationControllerDidDismiss(_ controller: UIPresentationController) {
        let cb = onDismiss
        onDismiss = nil
        cb?()
    }
}
