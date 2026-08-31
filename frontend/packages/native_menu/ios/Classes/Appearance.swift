// M237 — one appearance for the whole app, Flutter side and UIKit side.
//
// THE BUG THIS EXISTS TO FIX: every native surface pinned
// `overrideUserInterfaceStyle = .dark` at construction. That was right while
// the app had exactly one (dark) scheme — M108's note is still true, a glass
// container left to its own devices resolves LIGHT and UIKit then picks dark
// label colours, which is the washed-out panel with near-black text. But with
// M236's two palettes it meant the ribbon, the model browser, the tab bar and
// every native menu stayed charcoal while the Flutter chrome went cream: one
// window, two appearances, and the screenshots showed exactly that.
//
// So the trait is still pinned — never left to resolve — but it is pinned to
// whatever palette Dart says is active, and it FOLLOWS a change. A UIKit view
// cannot observe a Dart ValueNotifier, so the notifier's value is pushed over
// the plugin channel (`setAppearance`) and applied here.
//
// WHY A WEAK TABLE and not NotificationCenter: the observer form of
// NotificationCenter hands back a token that has to be released, which means
// every glass class grows a stored property and a deinit for something that is
// one line of its job. `NSHashTable.weakObjects()` drops a view the moment it
// is deallocated, so binding is one call and there is nothing to unbind.
import UIKit

/// A view that PAINTS with the accent, and so has to redraw when it changes.
///
/// Distinct from merely being bound to the appearance: a trait change makes
/// UIKit re-resolve every dynamic colour by itself, but bug report #11 made
/// the accent a value the user sets WITHOUT the trait moving. Nothing tells a
/// button whose `baseForegroundColor` was resolved at build time that the
/// colour behind it now means something else, so the view is asked to rebuild.
protocol AccentFollowing: AnyObject {
    func accentDidChange()
}

/// The app-wide UIKit appearance, and the views that follow it.
final class AppearanceBinder {
    static let shared = AppearanceBinder()
    private init() {}

    /// Dark until Dart says otherwise. Matches the Flutter side's own default
    /// (Ember), so the first frame is never a mismatch.
    private(set) var style: UIUserInterfaceStyle = .dark

    private let bound = NSHashTable<UIView>.weakObjects()
    private let accented = NSHashTable<AnyObject>.weakObjects()

    // Bug report #11 — the accent is the user's choice, not a constant.
    //
    // TWO values, because UIKit resolves against the pinned trait exactly as
    // the Dart side picks a Palette, and a colour that reads on cream does not
    // read on charcoal. They start at M260's built-in teals so the frames
    // before Dart first speaks are the palette's own rather than a flash of
    // something else.
    private(set) var accentLight =
        UIColor(red: 0.059, green: 0.416, blue: 0.439, alpha: 1)
    private(set) var accentDark =
        UIColor(red: 0.184, green: 0.663, blue: 0.635, alpha: 1)

    /// The accent, as a DYNAMIC colour.
    ///
    /// A provider rather than a resolved colour, for the reason M260 gives at
    /// `GlassTabBarView.accentFill`: resolving once returns a static colour
    /// that is then the wrong palette for the rest of the session after an
    /// appearance switch. Built once and reused, so the identity is stable.
    let accent = UIColor { t in
        t.userInterfaceStyle == .light
            ? AppearanceBinder.shared.accentLight
            : AppearanceBinder.shared.accentDark
    }

    /// Keeps [view] redrawing when the accent changes. Weak, like [bind].
    func bindAccent(_ view: AccentFollowing) {
        accented.add(view)
    }

    /// Applies a new accent to every view that paints with one, now.
    ///
    /// Main thread only, for [set]'s reason: it touches UIKit views.
    func setAccent(light: UIColor, dark: UIColor) {
        assert(Thread.isMainThread, "the accent must be applied on the main thread")
        accentLight = light
        accentDark = dark
        for case let view as AccentFollowing in accented.allObjects {
            view.accentDidChange()
        }
    }

    /// Pins [view] to the current appearance and keeps it in step.
    ///
    /// Call INSTEAD of setting `overrideUserInterfaceStyle` directly — a view
    /// that sets the trait itself is the thing that broke.
    func bind(_ view: UIView) {
        view.overrideUserInterfaceStyle = style
        bound.add(view)
    }

    /// Applies a new appearance to every bound view, now.
    ///
    /// Main thread only: it touches UIKit views. The channel handler already
    /// runs there, and the guard makes that a stated requirement rather than
    /// an assumption.
    func set(dark: Bool) {
        assert(Thread.isMainThread, "appearance must be applied on the main thread")
        let next: UIUserInterfaceStyle = dark ? .dark : .light
        guard next != style else { return }
        style = next
        for view in bound.allObjects {
            view.overrideUserInterfaceStyle = next
        }
    }
}
