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
// A PLATFORM WITHOUT THE PLUGIN IS A SUPPORTED STATE. Linux and Windows have
// no implementation behind this channel and are not supposed to: the call
// throws MissingPluginException, which is caught, logged once, and forgotten.
// The beacon is the whole of discovery there.
import 'dart:async';

import 'package:flutter/services.dart';

import '../log.dart';

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

  /// True when the platform answered — i.e. Bonjour is actually running.
  bool get running => _running;

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
      // Every desktop. Not a warning: the beacon is discovery there, and a
      // warning per launch would train the reader to skim the warnings.
      Log.i('sync', 'no Bonjour on this platform — the UDP beacon is it');
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
    if (!_running) return;
    _running = false;
    try {
      await _control.invokeMethod<void>('stop');
    } catch (e) {
      Log.w('sync', 'Bonjour would not stop cleanly: $e');
    }
  }
}
