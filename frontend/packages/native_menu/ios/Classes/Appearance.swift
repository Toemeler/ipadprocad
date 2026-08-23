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

/// The app-wide UIKit appearance, and the views that follow it.
final class AppearanceBinder {
    static let shared = AppearanceBinder()
    private init() {}

    /// Dark until Dart says otherwise. Matches the Flutter side's own default
    /// (Ember), so the first frame is never a mismatch.
    private(set) var style: UIUserInterfaceStyle = .dark

    private let bound = NSHashTable<UIView>.weakObjects()

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
