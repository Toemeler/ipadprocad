// Prototype — RealityKit viewport plugin: registration + platform-view factory.
//
// Registers a FlutterPlatformViewFactory under the view type
// "prototype/reality_view". Each embedded view gets its OWN method channel
// "prototype/reality_view/<id>" (the id Flutter assigns the platform view),
// so several viewports could coexist without cross-talk — though the app only
// ever shows one at a time.
import Flutter
import UIKit

public class RealityViewPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let factory = RealityPartViewFactory(messenger: registrar.messenger())
        registrar.register(factory, withId: "prototype/reality_view")
        // M64: plugin-level channel for off-screen stills (gallery thumbnails),
        // independent of whether a viewport platform view currently exists.
        registerThumbChannel(with: registrar)
    }
}

final class RealityPartViewFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    // Params arrive with the StandardMessageCodec (matches the Dart side).
    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        let channel = FlutterMethodChannel(
            name: "prototype/reality_view/\(viewId)",
            binaryMessenger: messenger)
        return RealityPartView(frame: frame, channel: channel)
    }
}

// ===========================================================================
// Off-screen still renderer (M64) — "prototype/reality_view/thumb".
// ===========================================================================
//
// WHY: the gallery/context-menu thumbnail was drawn by the Dart CPU painter
// while the live viewport is RealityKit. Same body, two engines, two looks.
// This renders the still with the SAME PartRenderer the viewport uses, so the
// card and the viewport agree by construction.
//
// WHY IT IS ATTACHED TO A WINDOW: `ARView.snapshot` drives the real render
// loop; a view with no window never gets a frame and the snapshot comes back
// nil. The renderer is therefore parked in the key window at zero alpha,
// BEHIND everything, for the handful of frames it takes to draw, then removed.
// It is never interactive and never visible.
final class RealityThumbRenderer: NSObject {
    static let shared = RealityThumbRenderer()

    /// Frames to let RealityKit settle before grabbing the picture. One is not
    /// enough: mesh resources uploaded in `setScene` are picked up on the
    /// FOLLOWING frame, so a single-frame snapshot yields the empty viewport
    /// colour. Two rendered frames plus the snapshot's own is the cheapest
    /// value that reliably contains the geometry.
    private static let warmupFrames = 2

    func render(
        scene: [String: Any],
        camera: [String: Any],
        size: CGSize,
        completion: @escaping (Data?) -> Void
    ) {
        guard #available(iOS 15.0, *) else { return completion(nil) }
        guard let window = RealityThumbRenderer.hostWindow() else {
            // No window (app backgrounded / launching): the caller keeps its
            // CPU fallback rather than getting a blank card.
            return completion(nil)
        }
        let px = CGRect(origin: .zero, size: size)
        let renderer = PartRenderer(frame: px)
        let host = renderer.view
        host.frame = px
        host.alpha = 0.0
        host.isUserInteractionEnabled = false
        window.insertSubview(host, at: 0)

        renderer.setScene(scene)
        renderer.setCamera(camera)

        RealityThumbRenderer.afterFrames(RealityThumbRenderer.warmupFrames) {
            renderer.snapshot { image in
                host.removeFromSuperview()
                completion(image?.pngData())
            }
        }
    }

    private static func hostWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        return scenes.first(where: { $0.activationState == .foregroundActive })?
            .windows.first(where: { $0.isKeyWindow })
            ?? scenes.flatMap { $0.windows }.first
    }

    /// Runs [body] after [n] display frames on the main thread.
    private static func afterFrames(_ n: Int, _ body: @escaping () -> Void) {
        guard n > 0 else { return body() }
        let link = CADisplayLink(target: FrameWaiter(n, body),
                                 selector: #selector(FrameWaiter.tick))
        link.add(to: .main, forMode: .common)
    }

    private final class FrameWaiter: NSObject {
        private var left: Int
        private let body: () -> Void
        private var link: CADisplayLink?
        init(_ n: Int, _ body: @escaping () -> Void) {
            self.left = n
            self.body = body
        }
        @objc func tick(_ link: CADisplayLink) {
            self.link = link
            left -= 1
            if left <= 0 {
                link.invalidate()
                body()
            }
        }
    }
}

extension RealityViewPlugin {
    /// Registers the plugin-level thumbnail channel. Called from `register`.
    static func registerThumbChannel(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "prototype/reality_view/thumb",
            binaryMessenger: registrar.messenger())
        channel.setMethodCallHandler { call, result in
            guard call.method == "render" else {
                return result(FlutterMethodNotImplemented)
            }
            guard
                let a = call.arguments as? [String: Any],
                let scene = a["scene"] as? [String: Any],
                let camera = a["camera"] as? [String: Any],
                let w = a["w"] as? NSNumber, let h = a["h"] as? NSNumber,
                w.intValue > 0, h.intValue > 0
            else {
                return result(FlutterError(
                    code: "bad_args",
                    message: "render needs scene, camera, w>0, h>0",
                    details: nil))
            }
            let size = CGSize(width: w.doubleValue, height: h.doubleValue)
            RealityThumbRenderer.shared.render(
                scene: scene, camera: camera, size: size
            ) { data in
                // A nil here is NOT an error: it means "no picture this time"
                // and the Dart side falls back to the CPU painter.
                result(data.map { FlutterStandardTypedData(bytes: $0) })
            }
        }
    }
}
