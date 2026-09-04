// M373 — finding the other devices, on the platform that will not let a
// program shout.
//
// WHY BONJOUR AND NOT THE UDP BEACON the desktops use. Since iOS 14 a raw
// broadcast or multicast requires `com.apple.developer.networking.multicast`,
// an entitlement Apple grants by written application and reviews per app.
// Bonjour through NetService needs none of it: a service type in
// NSBonjourServices, the local-network usage string, and the one permission
// prompt the user answers. A desktop runs BOTH — its beacon for other
// desktops, its Bonjour record for this device — so the two halves meet.
//
// WHY NetService AND NOT NWBrowser. NWBrowser is the modern API and is nicer;
// NetService is available further back, needs no availability guard around the
// call sites, and this is thirty lines of it. The TXT dictionary is the same
// either way.
//
// WHAT IS IN THE TXT RECORD is exactly what the desktops put in their beacon:
// the protocol version, the device id and name, and the share code's
// FINGERPRINT. Not the code, and not the key — a Bonjour record is readable by
// anything on the network, and the fingerprint is derived under a different
// domain separator so that hearing it says nothing about the key the handshake
// uses.
import Foundation
import Flutter

final class SyncDiscovery: NSObject {
    static let shared = SyncDiscovery()

    private var service: NetService?
    private var browser: NetServiceBrowser?
    /// Resolving is asynchronous and the resolver must outlive the call, so
    /// every service being resolved is held here until it answers or fails.
    private var resolving: [NetService] = []
    private var sink: FlutterEventSink?

    private var myId = ""
    private var myFingerprint = ""

    // MARK: - Registration

    static func register(with registrar: FlutterPluginRegistrar) {
        let control = FlutterMethodChannel(
            name: "prototype/sync_discovery",
            binaryMessenger: registrar.messenger())
        let events = FlutterEventChannel(
            name: "prototype/sync_discovery/events",
            binaryMessenger: registrar.messenger())
        control.setMethodCallHandler { call, result in
            shared.handle(call, result: result)
        }
        events.setStreamHandler(shared)
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "start":
            let type = args["type"] as? String ?? "_prototypesync._tcp"
            let port = args["port"] as? Int ?? 0
            myId = args["id"] as? String ?? ""
            myFingerprint = args["fp"] as? String ?? ""
            start(type: type,
                  port: port,
                  name: args["n"] as? String ?? "device",
                  version: args["v"] as? Int ?? 1)
            result(nil)
        case "stop":
            stop()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Advertise and browse

    private func start(type: String, port: Int, name: String, version: Int) {
        stop()
        guard port > 0 else { return }

        // The SERVICE NAME is the device id rather than the device's name.
        // Bonjour makes names unique by appending " (2)" when two collide, and
        // two iPads called "iPad" is the normal case; the id is unique already
        // and the human-readable name travels in the TXT record where nothing
        // rewrites it.
        let s = NetService(domain: "local.", type: type, name: myId,
                           port: Int32(port))
        var txt: [String: Data] = [:]
        txt["id"] = myId.data(using: .utf8)
        txt["n"] = name.data(using: .utf8)
        txt["fp"] = myFingerprint.data(using: .utf8)
        txt["v"] = String(version).data(using: .utf8)
        s.setTXTRecordData(NetService.data(fromTXTRecord: txt))
        s.publish()
        service = s

        let b = NetServiceBrowser()
        b.delegate = self
        b.searchForServices(ofType: type, inDomain: "local.")
        browser = b
    }

    private func stop() {
        service?.stop()
        service = nil
        browser?.stop()
        browser = nil
        for r in resolving { r.stop() }
        resolving.removeAll()
    }

    // MARK: - Reporting

    private func report(_ service: NetService) {
        guard let sink = sink else { return }
        guard let data = service.txtRecordData() else { return }
        let txt = NetService.dictionary(fromTXTRecord: data)
        func str(_ k: String) -> String? {
            guard let d = txt[k] else { return nil }
            return String(data: d, encoding: .utf8)
        }
        guard let id = str("id"), !id.isEmpty, id != myId else { return }

        // THE FIRST IPv4 ADDRESS, and IPv4 on purpose: the mirror's TCP side
        // dials a host string, and a link-local IPv6 address needs a scope id
        // that would have to survive being turned into text and back. Every
        // network this feature is for has IPv4 on it.
        var host: String?
        for addr in service.addresses ?? [] {
            let resolved: String? = addr.withUnsafeBytes { raw -> String? in
                guard let base = raw.baseAddress else { return nil }
                let sa = base.assumingMemoryBound(to: sockaddr.self)
                guard sa.pointee.sa_family == sa_family_t(AF_INET) else {
                    return nil
                }
                var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                var sin = base.assumingMemoryBound(to: sockaddr_in.self).pointee
                guard inet_ntop(AF_INET, &sin.sin_addr, &buf,
                                socklen_t(INET_ADDRSTRLEN)) != nil else {
                    return nil
                }
                return String(cString: buf)
            }
            if let r = resolved { host = r; break }
        }
        guard let h = host, service.port > 0 else { return }

        sink([
            "id": id,
            "n": str("n") ?? "?",
            "host": h,
            "port": service.port,
            "fp": str("fp") ?? "",
            "v": Int(str("v") ?? "0") ?? 0,
        ])
    }
}

// MARK: - NetServiceBrowserDelegate

extension SyncDiscovery: NetServiceBrowserDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser,
                           didFind service: NetService,
                           moreComing: Bool) {
        // Our own record comes back from the browser like anyone else's; it is
        // dropped in report() by id rather than here by name, because the name
        // Bonjour publishes is not always the name that was asked for.
        service.delegate = self
        resolving.append(service)
        service.resolve(withTimeout: 5.0)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser,
                           didRemove service: NetService,
                           moreComing: Bool) {
        // Nothing to do: the mirror ages peers out on its own five-second
        // sweep, and a device that went away for one Wi-Fi hiccup should not
        // be forgotten faster than that.
        resolving.removeAll { $0 === service }
    }
}

// MARK: - NetServiceDelegate

extension SyncDiscovery: NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        report(sender)
        resolving.removeAll { $0 === sender }
    }

    func netService(_ sender: NetService,
                    didNotResolve errorDict: [String: NSNumber]) {
        resolving.removeAll { $0 === sender }
    }

    func netService(_ sender: NetService, didUpdateTXTRecord data: Data) {
        // A peer that changed its share code republishes with a new
        // fingerprint. Reporting the update is what lets the Dart side notice
        // that the group changed without waiting for the record to expire.
        report(sender)
    }
}

// MARK: - FlutterStreamHandler

extension SyncDiscovery: FlutterStreamHandler {
    func onListen(withArguments arguments: Any?,
                  eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        sink = nil
        return nil
    }
}
