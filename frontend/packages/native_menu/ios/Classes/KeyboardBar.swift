// Prototype — M178: iPadOS's keyboard shortcuts bar, off.
//
// WHAT WENT WRONG
// ---------------
// With a hardware keyboard attached, focusing ANY text field makes iPadOS float
// its shortcuts bar across the bottom of the screen: the input-language chip
// ("DE EN"), the undo/redo/paste group and the dismiss chevron. It is a system
// overlay owned by the keyboard, so it lands ON TOP of the app's own floating
// tab bar and the perf readout — which is exactly what the device screenshot
// showed while the work plane's offset field was open. The app hides the status
// bar and the home indicator for the same reason; this was the one piece of
// system chrome still painting over the document.
//
// WHY IT CANNOT BE FIXED IN DART
// ------------------------------
// The bar is not ours to move, and Flutter exposes nothing that reaches it.
// `inputAssistantItem` belongs to the UIResponder that is first responder, and
// in a Flutter app that responder is the engine's own FlutterTextInputView, not
// any view we create. UIKit hides the bar when BOTH of its button groups are
// empty, so emptying them on that view is the whole fix.
//
// WHY TWO LAYERS
// --------------
// The groups have to be empty BEFORE the view becomes first responder. Clear
// them afterwards and the bar has already been built and measured — it flashes
// in, and the keyboard frame it reported was the wrong one.
//
//   1. `becomeFirstResponder` on FlutterTextInputView is hooked so the item is
//      cleared first. Deterministic, and the only layer that catches the very
//      first focus after launch.
//   2. A sweep on the keyboard notifications, as a backstop for the day the
//      engine renames that class: NSClassFromString then returns nil, layer 1
//      quietly does nothing, and the bar would otherwise be back for good. The
//      sweep still catches it, one focus late, because the engine REUSES its
//      text input views.
//
// Deliberately scoped to the Flutter view hierarchy. The rename/prompt dialogs
// are real UIAlertControllers in their own window, and their text fields keep
// the shortcuts bar they should have.
import UIKit

enum KeyboardBar {
    private static var installed = false

    /// Idempotent: plugin registration may run more than once per process
    /// (add-to-app, engine restarts), and hooking the method twice would put
    /// the original implementation back.
    static func install() {
        guard !installed else { return }
        installed = true
        hookBecomeFirstResponder()
        observeKeyboard()
    }

    /// Empties the responder's assistant item. UIKit hides the shortcuts bar
    /// entirely once both groups are empty; there is no separate "hidden" flag.
    static func silence(_ responder: UIResponder) {
        let item = responder.inputAssistantItem
        if !item.leadingBarButtonGroups.isEmpty {
            item.leadingBarButtonGroups = []
        }
        if !item.trailingBarButtonGroups.isEmpty {
            item.trailingBarButtonGroups = []
        }
    }

    // MARK: - Layer 1: before the view becomes first responder

    private static func hookBecomeFirstResponder() {
        guard let cls = NSClassFromString("FlutterTextInputView") else { return }
        let sel = #selector(UIResponder.becomeFirstResponder)
        guard let method = class_getInstanceMethod(cls, sel) else { return }

        // Captured, not re-looked-up: `method` may belong to a SUPERCLASS
        // (UIView) when the engine does not override becomeFirstResponder
        // itself. Exchanging implementations there would hook every view in the
        // process; adding an override on the engine's class instead keeps this
        // to the one class we mean, and the captured pointer is what "call the
        // original" then means.
        typealias Impl = @convention(c) (AnyObject, Selector) -> Bool
        let original = unsafeBitCast(method_getImplementation(method), to: Impl.self)

        let replacement: @convention(block) (AnyObject) -> Bool = { me in
            if let responder = me as? UIResponder { silence(responder) }
            return original(me, sel)
        }
        let imp = imp_implementationWithBlock(replacement)
        if !class_addMethod(cls, sel, imp, method_getTypeEncoding(method)) {
            // The class implements it itself, so there is nothing to add and
            // `method` is its own — swap the implementation in place. `original`
            // still points at the code we are replacing, so the call above is
            // the real one and not a loop.
            method_setImplementation(method, imp)
        }
    }

    // MARK: - Layer 2: backstop

    private static func observeKeyboard() {
        let names: [Notification.Name] = [
            UIResponder.keyboardWillShowNotification,
            UIResponder.keyboardWillChangeFrameNotification,
            UIResponder.keyboardDidShowNotification,
        ]
        for name in names {
            // queue: nil — run on the posting thread, synchronously. Handing
            // this to OperationQueue.main would defer it by a runloop turn,
            // which is the one thing a backstop against a visible flash cannot
            // afford.
            NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: nil
            ) { _ in
                sweep()
            }
        }
    }

    /// Clears every text-input responder currently living under the Flutter
    /// view. Matching on UITextInput rather than on a class name keeps this
    /// working across engine versions — that protocol is what makes a view a
    /// keyboard client in the first place.
    private static func sweep() {
        guard let host = NativeMenuPlugin.flutterHostView() else { return }
        clear(host)
    }

    private static func clear(_ view: UIView) {
        if view is UITextInput { silence(view) }
        for sub in view.subviews { clear(sub) }
    }
}
