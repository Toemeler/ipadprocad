// A progress card that keeps moving while Dart is not, showing what the
// converter is ACTUALLY doing.
//
// WHY THIS IS NATIVE AND NOT A FLUTTER WIDGET
// -------------------------------------------
// The mesh converter is a native call the Dart isolate makes and waits inside.
// While it waits, the UI thread produces no frames — so a Flutter progress bar
// is a still picture of a progress bar, which is worse than nothing: it tells
// the user the app is running when it is exactly as frozen as it looks.
//
// Flutter's platform thread is a DIFFERENT thread from the Dart UI thread, and
// it is idle for the whole conversion. A UIKit view on top of the FlutterView
// therefore animates normally, and — the point of M333 — it can READ the
// converter's progress counters while the isolate is stuck inside the call
// that is advancing them. Dart cannot; this thread can. That is the entire
// reason this is Swift.
//
// WHERE THE NUMBERS COME FROM
// ---------------------------
// occt_mesh_overall(), two ints describing one bar over the WHOLE conversion.
// See occt_capi.h. `permille` is where the work has actually got to and never
// goes backwards; `ceiling` is the furthest the current stage could take it.
//
//   * they move together — the stage counts itself (triangles resolved into
//     surfaces, faces built, OCCT's own progress through the sewing), and the
//     bar is simply the truth.
//   * ceiling is ahead — the stage is one opaque call OCCT gives no way into,
//     and merging coplanar faces is a THIRD of a 1:1 conversion. The bar eases
//     towards the ceiling on elapsed time and never reaches it, so the guess
//     lives here, in the drawing, where being wrong costs a bar that moves at
//     the wrong speed. In the numbers it would be a lie about the work.
//
// One bar and not one per stage. A bar that empties and refills four times
// cannot be read: nobody can tell the fourth 20% from the first. The stage
// spans behind `permille` were measured across four models spanning 1,138 to
// 83,178 triangles — see SpanOf in mesh_recon.cpp.
//
// CANCELLING
// ----------
// The conversion blocks the Dart isolate, so without a button here the user's
// only control over a long import is to force quit. The button calls
// occt_mesh_cancel(), which the converter answers within 5 ms while fitting
// and 127 ms while building — the one exception being OCCT's coplanar-face
// merge, which cannot be interrupted at all, so the card says "Cancelling…"
// and means it rather than pretending the tap did nothing.
//
// The symbols are resolved with dlsym rather than linked. A build of this
// plugin that is not sitting next to the kernel then still shows an honest
// sweeping card with no Cancel button, instead of failing to link.
import Darwin   // dlsym
import Flutter
import UIKit

final class BusyOverlay {
    static let shared = BusyOverlay()

    private var host: UIView?
    private var card: UIVisualEffectView?
    private var titleLabel: UILabel?
    private var detailLabel: UILabel?
    private var stageLabel: UILabel?
    private var elapsedLabel: UILabel?
    private var track: UIView?
    private var bar: UIView?
    private var started: CFTimeInterval = 0
    private var ticker: CADisplayLink?

    /// What the last poll said, so the card only relayouts when it changed.
    private var lastStage = -1
    private var sweeping = true

    /// The last percentage put on screen, so the label is only rewritten when
    /// the number a reader would see has actually changed. At 30 Hz over half
    /// a minute that is a few hundred string builds instead of a thousand.
    private var lastShownPercent = -1

    /// Where the bar is drawn, which is at or ahead of what the converter has
    /// actually finished — see the note on `ceiling` above. Only ever rises.
    private var shown = 0.0

    /// When the current stage began, for easing across an opaque one.
    private var stageStarted: CFTimeInterval = 0

    private var cancelButton: UIButton?
    private var cancelling = false
    private var cancelTitle = ""
    private var cancellingTitle = ""

    /// Stage names in the user's language, indexed by stage number; empty when
    /// the caller sent none, in which case the kernel's own English is used.
    private var stageNames: [String] = []

    private init() {}

    /// Whether this binary actually has the converter's progress counters in
    /// it. Reported back through busyShow so it lands in the milestone log and
    /// therefore in a bug report: "the bar swept the whole way" then has an
    /// answer in the bundle instead of needing a device to reproduce on.
    var hasRealProgress: Bool { BusyOverlay.overallFn != nil }

    /// Whether this binary can be asked to stop. Without it there is no
    /// Cancel button, because a button that does nothing is worse than none.
    var canCancel: Bool { BusyOverlay.cancelFn != nil }

    // MARK: - The kernel's progress counters

    private typealias ProgressFn =
        @convention(c) (UnsafeMutablePointer<Int32>?,
                        UnsafeMutablePointer<Int32>?,
                        UnsafeMutablePointer<Int32>?) -> Void
    private typealias StageNameFn =
        @convention(c) (Int32) -> UnsafePointer<CChar>?
    private typealias OverallFn =
        @convention(c) (UnsafeMutablePointer<Int32>?,
                        UnsafeMutablePointer<Int32>?) -> Void
    private typealias CancelFn = @convention(c) () -> Void

    /// RTLD_DEFAULT. A C macro — `((void *) -2)` — so it does not come across
    /// into Swift and has to be spelled out. It searches the main executable
    /// first, which is where the kernel is: CI force-loads libocct_capi.a into
    /// the Runner target and keeps `_occt_*` through the strip with an
    /// exported symbols list, which is the same mechanism Dart's
    /// DynamicLibrary.process() already relies on for every other occt call.
    private static let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)

    /// Resolved once, on first use. A build without the kernel leaves these
    /// nil for good and the card stays indeterminate, which is exactly what it
    /// was before M333 — a missing symbol must cost the bar, never the import.
    private static let progressFn: ProgressFn? = {
        guard let sym = dlsym(rtldDefault, "occt_mesh_progress") else {
            return nil
        }
        return unsafeBitCast(sym, to: ProgressFn.self)
    }()
    private static let stageNameFn: StageNameFn? = {
        guard let sym = dlsym(rtldDefault, "occt_mesh_stage_name") else {
            return nil
        }
        return unsafeBitCast(sym, to: StageNameFn.self)
    }()
    private static let overallFn: OverallFn? = {
        guard let sym = dlsym(rtldDefault, "occt_mesh_overall") else { return nil }
        return unsafeBitCast(sym, to: OverallFn.self)
    }()
    private static let cancelFn: CancelFn? = {
        guard let sym = dlsym(rtldDefault, "occt_mesh_cancel") else { return nil }
        return unsafeBitCast(sym, to: CancelFn.self)
    }()

    /// The whole-conversion bar: where it is, and how far this stage could
    /// take it. Nil when this binary has no converter in it.
    private static func overall() -> (at: Double, ceiling: Double)? {
        guard let fn = overallFn else { return nil }
        var p: Int32 = 0, c: Int32 = 0
        fn(&p, &c)
        return (Double(p) / 1000.0, Double(c) / 1000.0)
    }

    /// One snapshot, or nil when there is no converter in this binary.
    private static func poll() -> (stage: Int, done: Int, total: Int)? {
        guard let fn = progressFn else { return nil }
        var s: Int32 = 0, d: Int32 = 0, t: Int32 = 0
        fn(&s, &d, &t)
        return (Int(s), Int(d), Int(t))
    }

    private static func stageName(_ stage: Int) -> String {
        guard let fn = stageNameFn, let p = fn(Int32(stage)) else { return "" }
        return String(cString: p)
    }

    // MARK: - Presentation

    /// Puts the card up. Safe to call twice — the second call re-labels.
    func show(title: String, detail: String, stages: [String] = [],
              cancelTitle: String = "", cancellingTitle: String = "") {
        assert(Thread.isMainThread)
        stageNames = stages
        self.cancelTitle = cancelTitle
        self.cancellingTitle = cancellingTitle
        if let t = titleLabel, let d = detailLabel, host != nil {
            t.text = title
            d.text = detail
            return
        }
        guard let window = BusyOverlay.keyWindow() else { return }

        let dim = UIView(frame: window.bounds)
        dim.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dim.backgroundColor = UIColor.black.withAlphaComponent(0.28)
        // The point of the card is to say "wait", so it must also STOP the
        // taps that would otherwise queue up against a frozen UI thread and
        // all arrive at once when it thaws.
        dim.isUserInteractionEnabled = true
        window.addSubview(dim)

        let blur = UIVisualEffectView(
            effect: UIBlurEffect(style: .systemThickMaterial))
        blur.layer.cornerRadius = 18
        blur.layer.cornerCurve = .continuous
        blur.clipsToBounds = true
        blur.translatesAutoresizingMaskIntoConstraints = false
        dim.addSubview(blur)

        let title1 = UILabel()
        title1.text = title
        title1.font = .preferredFont(forTextStyle: .headline)
        title1.textAlignment = .center
        title1.translatesAutoresizingMaskIntoConstraints = false

        let detail1 = UILabel()
        detail1.text = detail
        detail1.font = .preferredFont(forTextStyle: .subheadline)
        detail1.textColor = .secondaryLabel
        detail1.textAlignment = .center
        detail1.numberOfLines = 2
        detail1.translatesAutoresizingMaskIntoConstraints = false

        let track1 = UIView()
        track1.backgroundColor = UIColor.label.withAlphaComponent(0.12)
        track1.layer.cornerRadius = 3
        track1.clipsToBounds = true
        track1.translatesAutoresizingMaskIntoConstraints = false

        let bar1 = UIView()
        bar1.backgroundColor = .tintColor
        bar1.layer.cornerRadius = 3
        track1.addSubview(bar1)

        // The stage line and the seconds share a row: what it is doing on the
        // left, how long it has been doing it on the right. Two centred lines
        // stacked would push the card taller for no more information.
        let stage1 = UILabel()
        stage1.text = ""
        stage1.font = .preferredFont(forTextStyle: .caption1)
        stage1.textColor = .tertiaryLabel
        stage1.textAlignment = .left
        stage1.adjustsFontSizeToFitWidth = true
        stage1.minimumScaleFactor = 0.8
        stage1.translatesAutoresizingMaskIntoConstraints = false
        stage1.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let elapsed = UILabel()
        elapsed.text = "0.0 s"
        elapsed.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        elapsed.textColor = .tertiaryLabel
        elapsed.textAlignment = .right
        elapsed.translatesAutoresizingMaskIntoConstraints = false
        elapsed.setContentHuggingPriority(.required, for: .horizontal)
        elapsed.setContentCompressionResistancePriority(.required,
                                                        for: .horizontal)

        let footer = UIStackView(arrangedSubviews: [stage1, elapsed])
        footer.axis = .horizontal
        footer.spacing = 8
        footer.alignment = .firstBaseline
        footer.translatesAutoresizingMaskIntoConstraints = false

        /* The way out. Only built when the kernel in this binary can actually
         * be asked to stop — a Cancel that does nothing is worse than none. */
        var rows: [UIView] = [title1, detail1, track1, footer]
        var button: UIButton?
        if canCancel && !cancelTitle.isEmpty {
            let b = UIButton(type: .system)
            b.setTitle(cancelTitle, for: .normal)
            b.titleLabel?.font = .preferredFont(forTextStyle: .body)
            b.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
            b.translatesAutoresizingMaskIntoConstraints = false
            b.heightAnchor.constraint(equalToConstant: 34).isActive = true
            let rule = UIView()
            rule.backgroundColor = UIColor.label.withAlphaComponent(0.12)
            rule.translatesAutoresizingMaskIntoConstraints = false
            rule.heightAnchor.constraint(equalToConstant: 1).isActive = true
            rows.append(rule)
            rows.append(b)
            button = b
        }

        let stack = UIStackView(arrangedSubviews: rows)
        stack.axis = .vertical
        stack.spacing = 8
        stack.setCustomSpacing(16, after: detail1)
        stack.translatesAutoresizingMaskIntoConstraints = false
        blur.contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            blur.centerXAnchor.constraint(equalTo: dim.centerXAnchor),
            blur.centerYAnchor.constraint(equalTo: dim.centerYAnchor),
            blur.widthAnchor.constraint(equalToConstant: 320),
            stack.topAnchor.constraint(equalTo: blur.contentView.topAnchor,
                                       constant: 22),
            stack.bottomAnchor.constraint(equalTo: blur.contentView.bottomAnchor,
                                          constant: -22),
            stack.leadingAnchor.constraint(equalTo: blur.contentView.leadingAnchor,
                                           constant: 24),
            stack.trailingAnchor.constraint(equalTo: blur.contentView.trailingAnchor,
                                            constant: -24),
            track1.heightAnchor.constraint(equalToConstant: 6),
        ])
        dim.layoutIfNeeded()

        dim.alpha = 0
        UIView.animate(withDuration: 0.15) { dim.alpha = 1 }

        host = dim
        card = blur
        titleLabel = title1
        detailLabel = detail1
        stageLabel = stage1
        elapsedLabel = elapsed
        track = track1
        bar = bar1
        cancelButton = button
        started = CACurrentMediaTime()
        stageStarted = started
        lastStage = -1
        lastShownPercent = -1
        shown = 0
        cancelling = false
        sweeping = false
        beginSweep() // until the first poll says otherwise

        // 30 Hz, not 60: this reads three relaxed atomics and formats a string,
        // and doing it on every frame of a ProMotion display is 120 times a
        // second for a number that changes at human speed.
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFramesPerSecond = 30
        link.add(to: .main, forMode: .common)
        ticker = link
    }

    // MARK: - The two bar modes

    /// Indeterminate: a stripe sliding across the track, driven by Core
    /// Animation on the render server so it keeps moving even when the
    /// platform thread is momentarily busy too.
    private func beginSweep() {
        guard !sweeping, let t = track, let b = bar else { return }
        sweeping = true
        let w = max(t.bounds.width, 1)
        b.layer.removeAnimation(forKey: "sweep")
        b.frame = CGRect(x: -w * 0.35, y: 0, width: w * 0.35, height: 6)
        let slide = CABasicAnimation(keyPath: "position.x")
        slide.fromValue = -w * 0.175
        slide.toValue = w * 1.175
        slide.duration = 1.1
        slide.repeatCount = .infinity
        slide.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        b.layer.add(slide, forKey: "sweep")
    }

    /// Determinate: the bar is the fraction, filled from the left.
    ///
    /// Monotonicity is the caller's business — `shown` in tick() only rises —
    /// so this draws exactly what it is given.
    private func setFraction(_ f: Double) {
        guard let t = track, let b = bar else { return }
        if sweeping {
            sweeping = false
            b.layer.removeAnimation(forKey: "sweep")
        }
        let w = max(t.bounds.width, 1)
        let v = min(max(f, 0), 1)
        // A short animation rather than a jump: the ticks arrive in bursts (a
        // whole surface's triangles retire at once) and an instant step of ten
        // per cent looks like a glitch where a 120 ms slide looks like work.
        UIView.animate(withDuration: 0.12, delay: 0,
                       options: [.curveEaseOut, .beginFromCurrentState]) {
            b.frame = CGRect(x: 0, y: 0, width: w * CGFloat(v), height: 6)
        }
    }

    @objc private func cancelTapped() {
        guard !cancelling, let fn = BusyOverlay.cancelFn else { return }
        cancelling = true
        fn()
        /* The button stays on screen and stops responding, relabelled. The
         * converter answers within milliseconds almost everywhere, but OCCT's
         * coplanar-face merge cannot be interrupted at all, and up to four
         * seconds of "nothing happened" after a tap is what makes an app feel
         * broken. Saying "Cancelling…" is the difference between waiting and
         * wondering. */
        cancelButton?.isEnabled = false
        if !cancellingTitle.isEmpty {
            cancelButton?.setTitle(cancellingTitle, for: .normal)
        }
    }

    /// The stage's name in the user's language, or the kernel's English when
    /// the caller sent no catalogue.
    private func nameOf(_ stage: Int) -> String {
        if stage >= 0 && stage < stageNames.count && !stageNames[stage].isEmpty {
            return stageNames[stage]
        }
        return BusyOverlay.stageName(stage)
    }

    @objc private func tick() {
        let now = CACurrentMediaTime()
        elapsedLabel?.text = String(format: "%.1f s", now - started)

        guard let p = BusyOverlay.poll(), let o = BusyOverlay.overall() else {
            return // no converter in this binary: the sweep stands
        }

        // Idle: the call has not started yet, or it has finished and the card
        // is about to come down. Keep sweeping rather than snapping to empty.
        if p.stage <= 0 {
            if lastStage != 0 {
                lastStage = 0
                lastShownPercent = -1
                stageLabel?.text = ""
                sweeping = false
                beginSweep()
            }
            return
        }
        if p.stage != lastStage {
            lastStage = p.stage
            stageStarted = now
            stageLabel?.text = nameOf(p.stage)
        }

        // Where the work has really got to — and, for a stage that cannot
        // count itself, an eased guess at where it is inside that stage.
        //
        // `total == 0` is the test, NOT `ceiling > at`: a counted stage also
        // has room left in its span until it finishes, and easing there put
        // the bar ahead of work that was reporting itself perfectly well.
        // Measured on the 1:1 path, where the first 45% is counted per
        // triangle: the bar sat a fifth of the model ahead of the truth for
        // five seconds.
        //
        // 2.5 s is the time constant, near the measured length of the two
        // stages this applies to on a large model (1.7 s sewing, 4.5 s
        // merging). Being wrong costs a bar that approaches the top of the
        // stage too fast or too slowly, never one that arrives before the work.
        var want = o.at
        if p.total <= 0 && o.ceiling > o.at {
            let t = now - stageStarted
            want = o.at + (o.ceiling - o.at) * (1.0 - exp(-t / 2.5))
        }
        // Only ever forward. The converter's own number never retreats, and
        // the eased part must not either when a stage finally reports.
        if want > shown { shown = min(want, 0.999) }
        setFraction(shown)

        let pct = Int((shown * 100).rounded())
        if pct != lastShownPercent {
            lastShownPercent = pct
            stageLabel?.text = "\(nameOf(p.stage))  \(pct)%"
        }
    }

    func hide() {
        assert(Thread.isMainThread)
        ticker?.invalidate()
        ticker = nil
        // Finish the bar before taking it away.
        //
        // The work is done by the time this is called, so whatever the bar was
        // showing is now behind. A card that vanishes at 84% leaves the last
        // impression of the import being that it did not finish — and the two
        // stages OCCT gives no way into are exactly the ones that end early.
        // Filling it costs the length of one fade.
        if host != nil && !sweeping {
            shown = 1.0
            setFraction(1.0)
            stageLabel?.text = lastStage > 0 ? nameOf(lastStage) : ""
        }
        cancelButton = nil
        cancelling = false
        stageNames = []
        guard let dim = host else { return }
        host = nil
        card = nil
        titleLabel = nil
        detailLabel = nil
        stageLabel = nil
        elapsedLabel = nil
        track = nil
        bar = nil
        lastStage = -1
        lastShownPercent = -1
        shown = 0
        sweeping = false
        UIView.animate(withDuration: 0.18, delay: 0.10, options: [],
                       animations: { dim.alpha = 0 }) { _ in
            dim.removeFromSuperview()
        }
    }

    private static func keyWindow() -> UIWindow? {
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            if let w = ws.windows.first(where: { $0.isKeyWindow }) { return w }
            if let w = ws.windows.first { return w }
        }
        return nil
    }
}
