// Prototype — discovery on the platform that will not let a program shout.
//
// WHY THIS EXISTS AT ALL, given that the UDP beacon in lan_sync.dart already
// works: since iOS 14 a raw broadcast or multicast needs
// `com.apple.developer.networking.multicast`, an entitlement Apple grants by
// written application and reviews per app. Bonjour through the system's own
// API needs none of that — a service type in `NSBonjourServices`, the
// local-network usage string, and the one permission prompt the user answers.
//
// So iOS advertises and browses `_prototypesync._tcp` while the desktops
// broadcast, and the two meet because a DESKTOP RUNS BOTH: it answers the
// beacon for other desktops and publishes a Bonjour record for the iPad. The
// iPad only ever needs the half it is allowed to have.
//
// WHAT TRAVELS IN THE TXT RECORD is exactly what travels in the beacon — the
// protocol version, the device id and name, and the share code's FINGERPRINT.
// Not the code and not the key: a Bonjour record is readable by anything on
// the network, and the fingerprint is derived under a different domain
// separator precisely so that hearing it tells you nothing about the key the
// handshake uses (see share_code.dart).
//
// A PLATFORM WITHOUT THE PLUGIN falls back to [MdnsFallback] (mdns.dart): a
// pure-Dart mDNS/DNS-SD advertiser and browser, speaking the same wire
// protocol Apple's own Bonjour stack does, for exactly the two platforms —
// Linux and Windows — this channel has no native implementation behind. See
// mdns.dart's header for why this is not optional on Windows: it is the only
// thing that makes an iPad able to see one at all.
import 'dart:async';

import 'package:flutter/services.dart';

import '../log.dart';
import 'mdns.dart' show MdnsFallback;

/// One device, as Bonjour describes it.
class SyncSighting {
  final String id;
  final String name;
  final String host;
  final int port;
  final String fingerprint;
  final int version;

  const SyncSighting({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.fingerprint,
    required this.version,
  });

  static SyncSighting? fromMap(Object? o) {
    if (o is! Map) return null;
    final id = o['id'];
    final host = o['host'];
    final port = (o['port'] as num?)?.toInt();
    if (id is! String || id.isEmpty || host is! String || port == null) {
      return null;
    }
    return SyncSighting(
      id: id,
      name: o['n'] is String ? o['n'] as String : '?',
      host: host,
      port: port,
      fingerprint: o['fp'] is String ? o['fp'] as String : '',
      version: (o['v'] as num?)?.toInt() ?? 0,
    );
  }
}

/// The service type, which must match `NSBonjourServices` in Info.plist
/// exactly — iOS silently browses nothing if it does not.
const String kBonjourServiceType = '_prototypesync._tcp';

/// Advertises this device and reports the others.
class Bonjour {
  static const MethodChannel _control =
      MethodChannel('prototype/sync_discovery');
  static const EventChannel _events =
      EventChannel('prototype/sync_discovery/events');

  StreamSubscription<dynamic>? _sub;
  bool _running = false;

  /// The pure-Dart stand-in, used only where [_control] has nothing behind
  /// it. Never both at once: [start] picks exactly one per call.
  final MdnsFallback _fallback = MdnsFallback();

  /// True when Bonjour is actually running — the platform channel, or (on a
  /// platform with none) the pure-Dart fallback in its place.
  bool get running => _running || _fallback.running;

  Future<void> start({
    required String fingerprint,
    required String deviceId,
    required String deviceName,
    required int port,
    required void Function(SyncSighting) onSighting,
  }) async {
    await stop();
    try {
      await _control.invokeMethod<void>('start', <String, Object?>{
        'type': kBonjourServiceType,
        'id': deviceId,
        'n': deviceName,
        'port': port,
        'fp': fingerprint,
        'v': 1,
      });
    } on MissingPluginException {
      // Windows and Linux. Not a warning: this is the expected shape there,
      // answered by falling back to mdns.dart rather than going without.
      Log.i('sync', 'no native Bonjour on this platform — using the '
          'pure-Dart fallback');
      await _fallback.start(
        fingerprint: fingerprint,
        deviceId: deviceId,
        deviceName: deviceName,
        port: port,
        onSighting: onSighting,
      );
      return;
    } catch (e) {
      Log.w('sync', 'Bonjour would not start: $e');
      return;
    }
    _running = true;
    _sub = _events.receiveBroadcastStream().listen(
      (dynamic e) {
        final s = SyncSighting.fromMap(e);
        if (s != null) onSighting(s);
      },
      onError: (Object e) => Log.w('sync', 'Bonjour stopped reporting: $e'),
    );
    Log.i('sync', 'Bonjour up: $kBonjourServiceType on $port');
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    await _fallback.stop();
    if (!_running) return;
    _running = false;
    try {
      await _control.invokeMethod<void>('stop');
    } catch (e) {
      Log.w('sync', 'Bonjour would not stop cleanly: $e');
    }
  }
}
