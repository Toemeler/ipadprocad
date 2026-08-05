// M205 — a button that still counts a press UIKit took away from it.
//
// THE REPORT
// ----------
// "A few times clicks on native swift liquidglass elements like the debug
// button didn't work by clicking on the trackpad." — "the buttons seem to get
// bigger when i click but somehow it doesnt count as a click." — "try to find
// a double proof fix so that a click on a native element will surely work also
// when apple bugs. i use iOS 27 beta 4 so maybe that's because of that."
//
// "Bigger, but not a click" names the mechanism exactly. A UIControl highlights
// on `touchesBegan` and fires `.touchUpInside` on `touchesEnded` inside its
// bounds. A control that lights up and then goes quiet was sent
// `touchesCancelled` in between: the press was delivered, and then taken back.
//
// The FIRST guard against that is on the Flutter side — the platform view now
// claims its touch sequences eagerly, so the engine never has cause to cancel
// them (see `native_touches.dart`). This is the second one, and it is
// deliberately independent: it assumes the cancel arrives anyway, and asks
// whether the gesture was a press regardless.
//
// WHEN A CANCEL IS STILL A TAP
// ----------------------------
// Three conditions, all required, all cheap:
//
//  * The touch ended INSIDE the button (with the usual slop — a finger rolls).
//  * It never travelled more than [moveSlop]. This is what keeps the recovery
//    off scrolling: the tab bar's row and the browser's tree both live in
//    scroll views, and a scroll cancels the touches of whatever was under the
//    finger. A scroll has to move past the scroll view's own slop first, so a
//    cancelled touch that never moved was not a scroll.
//  * No scroll view above it is actually dragging. Belt and braces for the
//    same case, from the other side.
//
// A press is recovered at most once per touch sequence, so a cancel that
// arrives after a normal `.touchUpInside` fires nothing.
import UIKit

/// A UIButton whose action survives a cancelled touch. Set [onTap] instead of
/// adding a `.touchUpInside` action — it is called for both paths.
@available(iOS 15.0, *)
final class GlassButton: UIButton {
    /// What the press means. Called exactly once per press, from the normal
    /// path or from the recovery.
    var onTap: (() -> Void)?

    /// Furthest a touch may travel and still be treated as a press. Under a
    /// scroll view's own pan threshold, so a scroll can never be recovered as
    /// a click even before the scroll-view guard below gets a say.
    private static let moveSlop: CGFloat = 8

    /// How far outside its own bounds a touch may end. A fingertip is wide and
    /// the report is specifically about presses that were hard to land.
    private static let boundsSlop: CGFloat = 12

    /// Longest a press may last and still be recovered. A cancel arriving long
    /// after the touch began is an interruption, not a click.
    private static let recoveryWindow: CFTimeInterval = 1.5

    private var beganAt: CFTimeInterval?
    private var beganWhere: CGPoint?
    private var fired = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        addTarget(self, action: #selector(handleUpInside), for: .touchUpInside)
    }

    // Both of UIButton's designated initialisers are overridden here, so its
    // convenience ones — `GlassButton(configuration:)` above all — are
    // inherited unchanged.
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        addTarget(self, action: #selector(handleUpInside), for: .touchUpInside)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        beganAt = CACurrentMediaTime()
        beganWhere = touches.first?.location(in: self)
        fired = false
        super.touchesBegan(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        beganAt = nil
        beganWhere = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        let began = beganAt
        let from = beganWhere
        let ended = touches.first?.location(in: self)
        super.touchesCancelled(touches, with: event)
        beganAt = nil
        beganWhere = nil
        guard let began, let from, let ended else { return }
        guard CACurrentMediaTime() - began <= Self.recoveryWindow else { return }
        guard hypot(ended.x - from.x, ended.y - from.y) <= Self.moveSlop else { return }
        guard bounds.insetBy(dx: -Self.boundsSlop, dy: -Self.boundsSlop)
                .contains(ended) else { return }
        guard !enclosingScrollViewIsMoving else { return }
        fire()
    }

    @objc private func handleUpInside() { fire() }

    private func fire() {
        guard isEnabled, !fired else { return }
        fired = true
        onTap?()
    }

    private var enclosingScrollViewIsMoving: Bool {
        var v: UIView? = superview
        while let cur = v {
            if let s = cur as? UIScrollView, s.isDragging || s.isDecelerating {
                return true
            }
            v = cur.superview
        }
        return false
    }
}
