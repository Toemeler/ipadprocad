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
// occt_mesh_progress(), a three-int snapshot of the running conversion:
// which stage, how far into it, and out of how much. See occt_capi.h. Nothing
// here estimates, weights or extrapolates anything:
//
//   * total > 0  — a real count of real work units (triangles resolved into
//                  surfaces, faces built). The bar fills to done/total and the
//                  label says so.
//   * total == 0 — the stage is one opaque call the kernel gives no windows
//                  into (sewing a shell, merging coplanar faces). The bar
//                  SWEEPS. A sweep is the honest picture of "working, position
//                  unknown"; a bar creeping forward on a guessed rate is a lie
//                  that gets caught by the first model that does not match it.
//   * total > 0 but nothing finished yet — also a SWEEP, until the first unit
//                  lands. Every stage begins with setup that retires nothing:
//                  measured on the whale, the freeform stage knows its total
//                  1.2 s before it covers its first triangle. A determinate
//                  bar pinned at 0% for over a second is indistinguishable
//                  from a hang, and a sweep says the same true thing without
//                  looking stuck.
//
// Deliberately NOT one bar across the whole conversion. That would need a
// weight per stage, and those weights depend on the model: on a whale the
// fitting is three quarters of the time and on a prismatic bracket it is a
// tenth. Per-stage is what is actually known.
//
// The symbol is resolved with dlsym rather than linked. A build of this plugin
// that is not sitting next to the kernel then still shows an honest sweeping
// card instead of failing to link, and the "is there a converter here?"
// question is answered once at runtime instead of at every call site.
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
    private var lastFrac = -1.0
    private var sweeping = true

    /// The last percentage put on screen, so the label is only rewritten when
    /// the number a reader would see has actually changed. At 30 Hz over half
    /// a minute that is a few hundred string builds instead of a thousand.
    private var lastShownPercent = -1

    private init() {}

    /// Whether this binary actually has the converter's progress counters in
    /// it. Reported back through busyShow so it lands in the milestone log and
    /// therefore in a bug report: "the bar swept the whole way" then has an
    /// answer in the bundle instead of needing a device to reproduce on.
    var hasRealProgress: Bool { BusyOverlay.progressFn != nil }

    // MARK: - The kernel's progress counters

    private typealias ProgressFn =
        @convention(c) (UnsafeMutablePointer<Int32>?,
                        UnsafeMutablePointer<Int32>?,
                        UnsafeMutablePointer<Int32>?) -> Void
    private typealias StageNameFn =
        @convention(c) (Int32) -> UnsafePointer<CChar>?

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
    func show(title: String, detail: String) {
        assert(Thread.isMainThread)
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

        let stack = UIStackView(arrangedSubviews: [title1, detail1, track1, footer])
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
        started = CACurrentMediaTime()
        lastStage = -1
        lastFrac = -1
        lastShownPercent = -1
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
    private func setFraction(_ f: Double) {
        guard let t = track, let b = bar else { return }
        if sweeping {
            sweeping = false
            b.layer.removeAnimation(forKey: "sweep")
        }
        let w = max(t.bounds.width, 1)
        let clamped = min(max(f, 0), 1)
        // Never let it go backwards WITHIN a stage. The counters do not, but a
        // stage change resets them, and a bar that jumps back reads as work
        // being undone. lastFrac is reset by the caller when the stage changes.
        let shown = max(clamped, lastFrac < 0 ? 0 : lastFrac)
        lastFrac = shown
        // A short animation rather than a jump: the ticks arrive in bursts (a
        // whole surface's triangles retire at once) and an instant step of ten
        // per cent looks like a glitch where a 120 ms slide looks like work.
        UIView.animate(withDuration: 0.12, delay: 0,
                       options: [.curveEaseOut, .beginFromCurrentState]) {
            b.frame = CGRect(x: 0, y: 0, width: w * CGFloat(shown), height: 6)
        }
    }

    @objc private func tick() {
        let seconds = CACurrentMediaTime() - started
        elapsedLabel?.text = String(format: "%.1f s", seconds)

        guard let p = BusyOverlay.poll() else { return } // no converter here
        // Stage 0 is idle: either the call has not started yet or it has
        // finished and the card is about to come down. Keep sweeping rather
        // than snapping the bar to empty.
        if p.stage <= 0 {
            if lastStage != 0 {
                lastStage = 0
                lastFrac = -1
                lastShownPercent = -1
                stageLabel?.text = ""
                sweeping = false
                beginSweep()
            }
            return
        }
        if p.stage != lastStage {
            lastStage = p.stage
            lastFrac = -1
            lastShownPercent = -1
            stageLabel?.text = BusyOverlay.stageName(p.stage)
            // Every stage starts as a sweep. It becomes a bar below, the
            // moment there is something real to draw with.
            sweeping = false
            beginSweep()
        }
        // `lastFrac >= 0` means this stage already went determinate, so it
        // stays that way: a counter that pauses must not throw the bar away
        // and start sweeping again from wherever it had got to.
        guard p.total > 0, p.done > 0 || lastFrac >= 0 else {
            if !sweeping { beginSweep() }
            return
        }
        setFraction(Double(p.done) / Double(p.total))
        // A PERCENTAGE, not the raw counts: the unit changes from stage to
        // stage — triangles resolved here, faces built there — and a bare
        // "69 / 110" under "Building the faces" invites reading it as
        // something it is not. A percentage of a stage is unambiguous.
        let pct = Int((lastFrac * 100).rounded())
        if pct != lastShownPercent {
            lastShownPercent = pct
            stageLabel?.text = "\(BusyOverlay.stageName(p.stage))  \(pct)%"
        }
    }

    func hide() {
        assert(Thread.isMainThread)
        ticker?.invalidate()
        ticker = nil
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
        lastFrac = -1
        lastShownPercent = -1
        sweeping = false
        UIView.animate(withDuration: 0.18, animations: { dim.alpha = 0 }) { _ in
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
