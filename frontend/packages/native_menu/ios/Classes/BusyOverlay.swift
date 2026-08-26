// A progress card that keeps moving while Dart is not.
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
// therefore animates normally: the bar sweeps, the seconds count up, and the
// app reads as busy rather than dead. That is the entire reason this is Swift.
//
// The bar is deliberately INDETERMINATE. The converter reports nothing while
// it runs, and a bar that fills at a rate someone guessed is a lie that gets
// caught every time a big model takes longer than the guess. A sweep plus an
// honest elapsed-seconds readout says what is actually known.
import Flutter
import UIKit

final class BusyOverlay {
    static let shared = BusyOverlay()

    private var host: UIView?
    private var card: UIVisualEffectView?
    private var titleLabel: UILabel?
    private var detailLabel: UILabel?
    private var elapsedLabel: UILabel?
    private var sweep: UIView?
    private var started: CFTimeInterval = 0
    private var ticker: CADisplayLink?

    private init() {}

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

        let track = UIView()
        track.backgroundColor = UIColor.label.withAlphaComponent(0.12)
        track.layer.cornerRadius = 3
        track.clipsToBounds = true
        track.translatesAutoresizingMaskIntoConstraints = false

        let bar = UIView()
        bar.backgroundColor = .tintColor
        bar.layer.cornerRadius = 3
        track.addSubview(bar)

        let elapsed = UILabel()
        elapsed.text = "0.0 s"
        elapsed.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        elapsed.textColor = .tertiaryLabel
        elapsed.textAlignment = .center
        elapsed.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [title1, detail1, track, elapsed])
        stack.axis = .vertical
        stack.spacing = 10
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
            track.heightAnchor.constraint(equalToConstant: 6),
        ])
        dim.layoutIfNeeded()

        // The sweep is a CAAnimation, not a timer-driven frame loop: Core
        // Animation runs it on the render server, so it keeps moving even if
        // the platform thread is momentarily busy too.
        let w = track.bounds.width
        bar.frame = CGRect(x: -w * 0.35, y: 0, width: w * 0.35, height: 6)
        let slide = CABasicAnimation(keyPath: "position.x")
        slide.fromValue = -w * 0.175
        slide.toValue = w * 1.175
        slide.duration = 1.1
        slide.repeatCount = .infinity
        slide.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        bar.layer.add(slide, forKey: "sweep")

        dim.alpha = 0
        UIView.animate(withDuration: 0.15) { dim.alpha = 1 }

        host = dim
        card = blur
        titleLabel = title1
        detailLabel = detail1
        elapsedLabel = elapsed
        sweep = bar
        started = CACurrentMediaTime()

        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        ticker = link
    }

    @objc private func tick() {
        guard let l = elapsedLabel else { return }
        l.text = String(format: "%.1f s", CACurrentMediaTime() - started)
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
        elapsedLabel = nil
        sweep = nil
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
