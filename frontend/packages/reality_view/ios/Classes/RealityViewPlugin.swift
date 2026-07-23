// iPadProCAD — RealityKit viewport plugin: registration + platform-view factory.
//
// Registers a FlutterPlatformViewFactory under the view type
// "ipadprocad/reality_view". Each embedded view gets its OWN method channel
// "ipadprocad/reality_view/<id>" (the id Flutter assigns the platform view),
// so several viewports could coexist without cross-talk — though the app only
// ever shows one at a time.
import Flutter
import UIKit

public class RealityViewPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let factory = RealityPartViewFactory(messenger: registrar.messenger())
        registrar.register(factory, withId: "ipadprocad/reality_view")
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
            name: "ipadprocad/reality_view/\(viewId)",
            binaryMessenger: messenger)
        return RealityPartView(frame: frame, channel: channel)
    }
}
