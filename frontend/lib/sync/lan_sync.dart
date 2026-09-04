// Prototype — every device with the same share code, on the same network,
// holding the same documents and the same settings.
//
// WHAT IT IS
// ----------
// Type a code in Settings on two devices. They find each other with a UDP
// beacon, prove to each other that they know the code, compare what they have
// and fill in each other's gaps — and then stay connected, so a document saved
// on the iPad is on the laptop a second later without anybody pressing
// anything.
//
// WHAT IT IS NOT, and this is worth being exact about rather than vague:
//
//   * It is NOT a cloud. There is no server, no account and nothing leaves the
//     local network. Two devices that cannot see each other's broadcast — a
//     guest network, a VPN, two different subnets — will not pair, and the
//     status row says "looking" forever rather than pretending.
//   * It is NOT encrypted. The handshake is authenticated (a peer has to
//     answer a nonce it did not choose, with a key derived from the code), so
//     nothing pairs without the code; the file bytes then travel in the clear,
//     on the same footing as an unencrypted file share. The settings footer
//     says so.
//   * It NEVER DELETES. A file that exists on any device ends up on all of
//     them; a file deleted on one is restored from another. That is a
//     deliberate asymmetry — the failure mode of a delete that propagates
//     through a bug is losing work everywhere at once, and no amount of
//     testing makes that acceptable in the first version of a mirror.
//
// THE CONFLICT RULE is one line: the newest write wins, per file, by
// modification time. Two devices editing the same document at once is a case
// this cannot resolve honestly — there is no merge for a B-Rep feature tree —
// so it does the predictable thing rather than the clever one. The one
// protection that IS here: a document currently OPEN is not reloaded under the
// user's hands. The bytes land on disk, the in-memory model is left alone, and
// the next save from this device wins. The device you are working on is the
// one that keeps its work.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../log.dart';
import 'share_code.dart';
import 'sync_protocol.dart';

/// One file in the mirror, as both sides describe it.
@immutable
class SyncEntry {
  /// The path RELATIVE to the mirror root, always with forward slashes.
  ///
  /// Two roots, flattened into one namespace: documents are bare names
  /// (`Bracket.ptp`) and preferences are under `settings/`. A peer never
  /// learns anything about where the other device keeps its files, which is
  /// just as well — an iPad's container path means nothing on a PC.
  final String path;
  final int size;
  final int mtimeMs;
  final String sha;

  const SyncEntry(this.path, this.size, this.mtimeMs, this.sha);

  Map<String, Object?> toJson() =>
      {'p': path, 's': size, 'm': mtimeMs, 'h': sha};

  static SyncEntry? fromJson(Object? o) {
    if (o is! Map) return null;
    final p = o['p'];
    final h = o['h'];
    if (p is! String || p.isEmpty || h is! String) return null;
    return SyncEntry(p, (o['s'] as num?)?.toInt() ?? 0,
        (o['m'] as num?)?.toInt() ?? 0, h);
  }
}

/// A file that was DELETED, and when.
///
/// A delete has to travel as a fact of its own. The alternative — "I do not
/// have it, therefore delete yours" — cannot tell a deletion from a device
/// that has simply never seen the file, which on a first pair-up is every
/// document the other machine owns. A tombstone says who is missing what ON
/// PURPOSE, and carries the moment so it can lose to a later save.
@immutable
class SyncTomb {
  final String path;
  final int deletedAtMs;

  const SyncTomb(this.path, this.deletedAtMs);

  Map<String, Object?> toJson() => {'p': path, 'd': deletedAtMs};

  static SyncTomb? fromJson(Object? o) {
    if (o is! Map) return null;
    final p = o['p'];
    final d = (o['d'] as num?)?.toInt();
    if (p is! String || p.isEmpty || d == null) return null;
    return SyncTomb(p, d);
  }
}

/// A device this one can see.
@immutable
class SyncPeer {
  final String id;
  final String name;
  final String host;
  final int port;
  final DateTime seen;
  final bool connected;

  const SyncPeer({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.seen,
    this.connected = false,
  });

  SyncPeer withConnected(bool v) => SyncPeer(
      id: id, name: name, host: host, port: port, seen: seen, connected: v);
}

/// What the settings row shows.
enum SyncState {
  /// No code entered. Nothing is running.
  off,

  /// A code is set and the beacon is out, but nobody has answered.
  looking,

  /// At least one peer is connected.
  live,

  /// A code is set and something is wrong — no network, port taken.
  failed,
}

@immutable
class SyncStatus {
  final SyncState state;
  final int peers;
  final DateTime? lastChange;
  final String? detail;

  const SyncStatus(this.state, {this.peers = 0, this.lastChange, this.detail});
}

/// The mirror.
///
/// A singleton, like the other cross-cutting services in this app (Log, Perf,
/// NativeMenu): it owns sockets and a timer, there is exactly one network to
/// be on, and threading an instance through the widget tree would buy nothing.
class LanSync {
  LanSync._();
  static final LanSync instance = LanSync._();

  /// What the UI watches.
  final ValueNotifier<SyncStatus> status =
      ValueNotifier<SyncStatus>(const SyncStatus(SyncState.off));

  /// Called after a file has landed, so the app can pick it up: the gallery
  /// refreshes, the preferences are re-read. Set once, by AppState.
  void Function(Set<String> paths)? onApplied;

  /// Where documents live, and where `settings.json` lives.
  Directory? _docs;
  Directory? _prefs;

  String? _code;
  Uint8List? _key;
  String? _fp;

  /// This device, as the beacon and the handshake name it. Stable for the
  /// process; a restart is a new id, which is harmless — an id only decides
  /// who dials whom.
  final String _deviceId = newNonce().substring(0, 12);
  String _deviceName = 'device';

  RawDatagramSocket? _beacon;
  ServerSocket? _server;
  Timer? _announce;
  Timer? _scan;
  Timer? _interfaces;
  StreamSubscription<FileSystemEvent>? _watchDocs;
  StreamSubscription<FileSystemEvent>? _watchPrefs;
  Timer? _poll;

  final Map<String, SyncPeer> _peers = <String, SyncPeer>{};
  final Map<String, _SyncSession> _sessions = <String, _SyncSession>{};

  /// The manifest as of the last scan, so a change can be spotted by
  /// comparison on the platforms with no usable file watcher.
  Map<String, SyncEntry> _mine = <String, SyncEntry>{};

  /// What has been deleted, by path, with the moment it happened.
  ///
  /// Kept in a small journal beside the preferences rather than in memory
  /// only: a device that is switched off while another one deletes something
  /// must still learn about it, and a device that deletes something and is
  /// then restarted must still be able to TELL anyone. Both of those are the
  /// normal case rather than an edge one.
  Map<String, int> _tombs = <String, int>{};

  /// Paths this device has just WRITTEN because a peer sent them. Suppresses
  /// the echo: without it, applying a peer's file fires the watcher, which
  /// announces the change, which the peer applies, which fires its watcher.
  final Map<String, int> _justApplied = <String, int>{};

  bool get enabled => _code != null;
  String? get code => _code;
  List<SyncPeer> get peers => _peers.values.toList(growable: false);

  /// Documents, by extension. The three the app owns and nothing else — a
  /// mirror that copied whatever it found would copy the log, the thumbnail
  /// cache and the crash reports too.
  static const Set<String> _docExtensions = {'.ptp', '.pts', '.pas'};

  /// The prefix under which preferences travel.
  static const String _prefsPrefix = 'settings/';

  /// The preference file, and the picture the gallery backdrop may point at.
  static const List<String> _prefFiles = [
    'settings.json',
    'backdrop.png',
    'backdrop.jpg',
  ];

  /// Keys in settings.json that are about THIS DEVICE and must not travel.
  ///
  ///   sync              the code itself, and whether this device is sharing.
  ///                     Syncing it would mean one device could switch another
  ///                     one's sharing off, which is not a preference, it is a
  ///                     remote control.
  ///   previewFormat     cache bookkeeping. Wrong values cost a redundant
  ///   previewsRepaired  redraw, and a shared value would cost one per device.
  static const Set<String> _localOnlyPrefs = {
    'sync',
    'previewFormat',
    'previewsRepaired',
  };

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  /// Points the mirror at this install's two directories. Called once, from
  /// AppState.init, before [setCode].
  void attach({
    required Directory documents,
    required Directory preferences,
    String? deviceName,
  }) {
    _docs = documents;
    _prefs = preferences;
    _deviceName = deviceName ?? _defaultDeviceName();
    _loadTombs();
  }

  static String _defaultDeviceName() {
    try {
      final h = Platform.localHostname;
      if (h.isNotEmpty) return h;
    } catch (_) {
      // Some sandboxes refuse the hostname. It is a label, not a key.
    }
    return Platform.operatingSystem;
  }

  /// Turns the mirror on with [canonical], or off with null.
  ///
  /// Idempotent, and safe to call before [attach] — it simply records the code
  /// and does nothing until there is somewhere to mirror.
  Future<void> setCode(String? canonical) async {
    if (canonical == _code) return;
    await _stop();
    _code = canonical;
    if (canonical == null) {
      _key = null;
      _fp = null;
      status.value = const SyncStatus(SyncState.off);
      Log.i('sync', 'sharing off');
      return;
    }
    _key = shareCodeKey(canonical);
    _fp = shareCodeFingerprint(canonical);
    Log.i('sync', 'sharing on, group $_fp, as $_deviceName/$_deviceId');
    await _start();
  }

  Future<void> _start() async {
    if (_docs == null || _prefs == null) return;
    try {
      _loadTombs();
      _mine = _scanLocal();
      await _startServer();
      await _startBeacon();
      _watchLocal();
      unawaited(_refreshInterfaces());
      _interfaces = Timer.periodic(
          const Duration(seconds: 30), (_) => unawaited(_refreshInterfaces()));
      _announce = Timer.periodic(const Duration(seconds: 2), (_) => _sendBeacon());
      _scan = Timer.periodic(const Duration(seconds: 5), (_) => _sweep());
      _sendBeacon();
      _publish();
    } catch (e) {
      Log.w('sync', 'could not start: $e');
      status.value = SyncStatus(SyncState.failed, detail: '$e');
    }
  }

  Future<void> _stop() async {
    _announce?.cancel();
    _scan?.cancel();
    _interfaces?.cancel();
    _poll?.cancel();
    _announce = _scan = _interfaces = _poll = null;
    await _watchDocs?.cancel();
    await _watchPrefs?.cancel();
    _watchDocs = _watchPrefs = null;
    for (final s in _sessions.values.toList()) {
      s.close('sharing off');
    }
    _sessions.clear();
    _peers.clear();
    _beacon?.close();
    _beacon = null;
    await _server?.close();
    _server = null;
  }

  // -------------------------------------------------------------------------
  // Discovery
  // -------------------------------------------------------------------------

  Future<void> _startBeacon() async {
    // reusePort so two copies on ONE machine can both listen — which is not a
    // user's arrangement, it is how this gets tested, and a feature that can
    // only be tested by owning two devices does not get tested. Not every
    // platform honours it; the failure is one instance seeing the other but
    // not the reverse, which the dial rule below survives.
    final s = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      kSyncBeaconPort,
      reuseAddress: true,
      reusePort: !Platform.isWindows,
    );
    s.broadcastEnabled = true;
    s.listen((event) {
      if (event != RawSocketEvent.read) return;
      final dg = s.receive();
      if (dg == null) return;
      _onBeacon(dg);
    });
    _beacon = s;
  }

  void _sendBeacon() {
    final s = _beacon;
    final port = _server?.port;
    if (s == null || port == null || _fp == null) return;
    final msg = utf8.encode(jsonEncode({
      'p': 'prototype-sync',
      'v': kSyncProtocolVersion,
      'id': _deviceId,
      'n': _deviceName,
      'port': port,
      'fp': _fp,
    }));
    // Both the directed broadcast and the local one: some stacks drop
    // 255.255.255.255 and some drop the subnet address, and sending twice
    // costs a hundred bytes every two seconds.
    for (final addr in _broadcastAddresses()) {
      try {
        s.send(msg, addr, kSyncBeaconPort);
      } catch (_) {
        // A down interface is not an error worth a log line every two seconds.
      }
    }
  }

  /// 255.255.255.255 plus one directed broadcast per interface.
  ///
  /// The limited broadcast alone is not enough on a machine with more than one
  /// interface — a socket bound to 0.0.0.0 sends it out the DEFAULT route and
  /// nowhere else, so a laptop on Wi-Fi with a docking Ethernet, or any
  /// Windows box with Hyper-V's virtual adapters, announces itself on one
  /// network and is silent on the other. A directed broadcast goes out the
  /// interface that owns the subnet.
  ///
  /// THE /24 IS AN ASSUMPTION and it is stated rather than hidden: Dart's
  /// NetworkInterface gives addresses and no netmasks, so there is nothing to
  /// derive the real prefix from. It is right for essentially every home and
  /// office network, wrong for the rare /16, and the cost of being wrong is
  /// one datagram that nothing answers — the limited broadcast is still sent,
  /// and a peer that hears either one pairs.
  List<InternetAddress> _broadcastAddresses() =>
      broadcastAddressesFor(_localV4);

  /// The IPv4 addresses of this machine, refreshed on a slow timer.
  ///
  /// Cached because NetworkInterface.list() is asynchronous and the beacon is
  /// not, and because enumerating interfaces every two seconds to learn
  /// something that changes when a cable is plugged in is work for nothing.
  List<String> _localV4 = const <String>[];

  Future<void> _refreshInterfaces() async {
    try {
      final ifs = await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLoopback: false);
      _localV4 = <String>[
        for (final i in ifs)
          for (final a in i.addresses) a.address,
      ];
    } catch (e) {
      Log.w('sync', 'could not list the interfaces: $e');
    }
  }

  void _onBeacon(Datagram dg) {
    if (_fp == null) return;
    Map<String, Object?> m;
    try {
      final raw = jsonDecode(utf8.decode(dg.data));
      if (raw is! Map) return;
      m = <String, Object?>{for (final e in raw.entries) '${e.key}': e.value};
    } catch (_) {
      return; // something else on the port
    }
    if (m['p'] != 'prototype-sync') return;
    if (m['fp'] != _fp) return; // a different group, or none
    final id = '${m['id']}';
    if (id == _deviceId) return; // our own broadcast, come back
    final port = (m['port'] as num?)?.toInt();
    if (port == null) return;
    if ((m['v'] as num?)?.toInt() != kSyncProtocolVersion) {
      Log.w('sync', 'peer $id speaks version ${m['v']}, this one speaks '
          '$kSyncProtocolVersion — not pairing');
      return;
    }
    final known = _peers[id];
    _peers[id] = SyncPeer(
      id: id,
      name: '${m['n']}',
      host: dg.address.address,
      port: port,
      seen: DateTime.now(),
      connected: known?.connected ?? false,
    );
    if (known == null) {
      Log.i('sync', 'saw ${m['n']} ($id) at ${dg.address.address}:$port');
    }
    _maybeDial(id);
    _publish();
  }

  /// ONE session per pair, and the lower id dials.
  ///
  /// Both devices are listening and both can see each other, so without a rule
  /// they each open a connection and every file crosses twice. Comparing the
  /// ids is the cheapest rule that both sides evaluate the same way with no
  /// extra round trip.
  void _maybeDial(String id) {
    if (_sessions.containsKey(id)) return;
    if (_deviceId.compareTo(id) >= 0) return;
    final peer = _peers[id];
    if (peer == null) return;
    unawaited(_dial(peer));
  }

  Future<void> _dial(SyncPeer peer) async {
    if (_sessions.containsKey(peer.id)) return;
    // Claim the slot BEFORE the await, or two beacons a millisecond apart
    // start two connections to the same peer.
    _sessions[peer.id] = _SyncSession.pending(peer.id);
    try {
      final sock = await Socket.connect(peer.host, peer.port,
          timeout: const Duration(seconds: 5));
      final s = _SyncSession(this, sock, outgoing: true, peerId: peer.id);
      _sessions[peer.id] = s;
      s.start();
    } catch (e) {
      _sessions.remove(peer.id);
      Log.w('sync', 'could not reach ${peer.name}: $e');
    }
  }

  /// Drops peers that have stopped announcing, and retries the ones that are
  /// there but not connected.
  void _sweep() {
    final now = DateTime.now();
    for (final id in _peers.keys.toList()) {
      final p = _peers[id]!;
      if (now.difference(p.seen) > const Duration(seconds: 12)) {
        _peers.remove(id);
        _sessions.remove(id)?.close('gone');
        Log.i('sync', '${p.name} went away');
      } else if (!_sessions.containsKey(id)) {
        _maybeDial(id);
      }
    }
    _publish();
  }

  // -------------------------------------------------------------------------
  // The listener
  // -------------------------------------------------------------------------

  Future<void> _startServer() async {
    for (var port = kSyncFirstDataPort; port < kSyncFirstDataPort + 20; port++) {
      try {
        _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
        break;
      } on SocketException {
        continue; // another copy of the app, or something else
      }
    }
    final s = _server;
    if (s == null) throw const SocketException('no free port to listen on');
    s.listen((sock) {
      final session = _SyncSession(this, sock, outgoing: false);
      session.start();
    });
    Log.i('sync', 'listening on ${s.port}');
  }

  void _adopt(_SyncSession s, String peerId) {
    final existing = _sessions[peerId];
    if (existing != null && existing != s && existing.live) {
      // Both sides dialled — possible when one of them could not see the
      // other's beacon and so did not apply the id rule. Keep one.
      s.close('already connected');
      return;
    }
    _sessions[peerId] = s;
    final p = _peers[peerId];
    if (p != null) _peers[peerId] = p.withConnected(true);
    _publish();
  }

  void _forget(_SyncSession s) {
    final id = s.peerId;
    if (id != null && identical(_sessions[id], s)) {
      _sessions.remove(id);
      final p = _peers[id];
      if (p != null) _peers[id] = p.withConnected(false);
    }
    _publish();
  }

  void _publish() {
    if (_code == null) {
      status.value = const SyncStatus(SyncState.off);
      return;
    }
    final live = _sessions.values.where((s) => s.live).length;
    status.value = SyncStatus(
      live > 0 ? SyncState.live : SyncState.looking,
      peers: live,
      lastChange: _lastApplied,
    );
  }

  DateTime? _lastApplied;

  // -------------------------------------------------------------------------
  // The local side
  // -------------------------------------------------------------------------

  /// Everything this device is offering, by mirror path.
  Map<String, SyncEntry> _scanLocal() {
    final out = <String, SyncEntry>{};
    final docs = _docs, prefs = _prefs;
    if (docs != null && docs.existsSync()) {
      for (final e in docs.listSync(followLinks: false)) {
        if (e is! File) continue;
        final name = e.uri.pathSegments.last;
        final dot = name.lastIndexOf('.');
        if (dot < 0) continue;
        if (!_docExtensions.contains(name.substring(dot).toLowerCase())) {
          continue;
        }
        final entry = _entryFor(name, e);
        if (entry != null) out[name] = entry;
      }
    }
    if (prefs != null && prefs.existsSync()) {
      for (final name in _prefFiles) {
        final f = File('${prefs.path}/$name');
        if (!f.existsSync()) continue;
        final entry = _entryFor('$_prefsPrefix$name', f);
        if (entry != null) out['$_prefsPrefix$name'] = entry;
      }
    }
    return out;
  }

  SyncEntry? _entryFor(String path, File f) {
    try {
      final st = f.statSync();
      // Hashed rather than compared by size and time alone: two devices that
      // saved the same document a second apart have different times and
      // identical bytes, and copying it back and forth forever is what a mirror
      // that trusts timestamps does. A document is a few megabytes and this
      // runs on a change, not on a frame.
      final sha = sha256.convert(f.readAsBytesSync()).toString();
      return SyncEntry(path, st.size, st.modified.millisecondsSinceEpoch, sha);
    } catch (e) {
      Log.w('sync', 'could not read $path: $e');
      return null;
    }
  }

  File? _fileFor(String path) {
    if (path.contains('..') || path.startsWith('/') || path.contains('\\')) {
      // A peer names files in OUR namespace; anything that could escape it is
      // a peer that should not be trusted with a write.
      Log.w('sync', 'refusing a path from a peer: $path');
      return null;
    }
    if (path.startsWith(_prefsPrefix)) {
      final name = path.substring(_prefsPrefix.length);
      if (!_prefFiles.contains(name)) return null;
      final prefs = _prefs;
      return prefs == null ? null : File('${prefs.path}/$name');
    }
    final dot = path.lastIndexOf('.');
    if (dot < 0) return null;
    if (!_docExtensions.contains(path.substring(dot).toLowerCase())) return null;
    if (path.contains('/')) return null;
    final docs = _docs;
    return docs == null ? null : File('${docs.path}/$path');
  }

  /// Watches for local saves.
  ///
  /// `Directory.watch` is not available on every platform this app runs on —
  /// on iOS it throws — so the poll is not a fallback for a broken watcher, it
  /// is the implementation there. Five seconds: a mirror that notices a save
  /// within five seconds is indistinguishable from an instant one to someone
  /// walking between two devices, and a tighter loop would hash every document
  /// every second for nothing.
  void _watchLocal() {
    final docs = _docs, prefs = _prefs;
    try {
      if (docs != null) {
        _watchDocs = docs.watch(events: FileSystemEvent.all).listen(
            (_) => _onLocalChange(),
            onError: (Object e) => _fallBackToPolling(e));
      }
      if (prefs != null) {
        _watchPrefs = prefs.watch(events: FileSystemEvent.all).listen(
            (_) => _onLocalChange(),
            onError: (Object e) => _fallBackToPolling(e));
      }
    } catch (e) {
      _fallBackToPolling(e);
    }
    // Even with a watcher: a poll every five seconds is the safety net for the
    // events no platform delivers reliably (a file replaced by rename, a
    // network volume, a sandbox that coalesces).
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _onLocalChange());
  }

  void _fallBackToPolling(Object e) {
    Log.i('sync', 'no file watcher here ($e) — polling instead');
    _watchDocs?.cancel();
    _watchPrefs?.cancel();
    _watchDocs = _watchPrefs = null;
  }

  Timer? _debounce;

  void _onLocalChange() {
    // A save is several writes; announcing each one would send the document
    // three times. Half a second after the last of them is still immediate to
    // a person and is one transfer.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _announceChanges);
  }

  void _announceChanges() {
    if (_code == null) return;
    final now = _scanLocal();
    final gone = _noticeDeletes(now);
    final changed = <SyncEntry>[];
    for (final e in now.entries) {
      final was = _mine[e.key];
      if (was == null || was.sha != e.value.sha) {
        // Not the echo of something a peer just sent us.
        final applied = _justApplied[e.key];
        if (applied != null && applied == e.value.mtimeMs) continue;
        changed.add(e.value);
      }
    }
    _mine = now;
    if (changed.isEmpty && gone.isEmpty) return;
    if (changed.isNotEmpty) {
      Log.i('sync', 'offering ${changed.map((c) => c.path).join(", ")}');
    }
    if (gone.isNotEmpty) {
      Log.i('sync', 'deleted here: ${gone.map((t) => t.path).join(", ")}');
    }
    for (final s in _sessions.values) {
      if (s.live) s.announce(changed, gone);
    }
  }

  /// Turns "it was in the last scan and is not in this one" into tombstones.
  ///
  /// The EXISTENCE CHECK is not redundant with the scan. [_scanLocal] drops a
  /// file it cannot read — a lock, a permission, a half-written save — and
  /// treating that as a deletion would delete a perfectly good document on
  /// every other device the moment one machine hiccuped. A tombstone is only
  /// written for a file that is genuinely not there any more.
  List<SyncTomb> _noticeDeletes(Map<String, SyncEntry> now) {
    final out = <SyncTomb>[];
    final at = DateTime.now().millisecondsSinceEpoch;
    for (final path in _mine.keys) {
      if (now.containsKey(path)) continue;
      if (!_deletable(path)) continue;
      final f = _fileFor(path);
      if (f == null || f.existsSync()) continue;
      _tombs[path] = at;
      out.add(SyncTomb(path, at));
    }
    if (out.isNotEmpty) _saveTombs();
    return out;
  }

  // -------------------------------------------------------------------------
  // Applying what a peer sent
  // -------------------------------------------------------------------------

  /// True when [remote] should replace what is here.
  bool _wants(SyncEntry remote) {
    // Deleted here, and the file on offer is older than the deletion: this is
    // the copy that was thrown away, coming back from a device that has not
    // heard yet. Refusing it is what makes a delete stick — otherwise every
    // device that still has the file would hand it straight back.
    final tomb = _tombs[remote.path];
    if (tomb != null && tomb > remote.mtimeMs + 1000) return false;
    final mine = _mine[remote.path];
    if (mine == null) return true;
    if (mine.sha == remote.sha) return false;
    // A second of slack, because two devices' clocks are never equal and a
    // difference of milliseconds is not a decision anybody made.
    return remote.mtimeMs > mine.mtimeMs + 1000;
  }

  /// Writes a file a peer sent, atomically, and remembers it.
  bool _apply(SyncEntry e, Uint8List bytes) {
    final f = _fileFor(e.path);
    if (f == null) return false;
    final actual = sha256.convert(bytes).toString();
    if (actual != e.sha) {
      Log.w('sync', '${e.path} arrived corrupt — dropped');
      return false;
    }
    try {
      if (e.path == '${_prefsPrefix}settings.json') {
        return _applySettings(e, bytes);
      }
      f.parent.createSync(recursive: true);
      // Written beside and renamed: a mirror that truncates a document and
      // then dies has destroyed it, and this app's documents are single files
      // with no journal behind them.
      final tmp = File('${f.path}.sync-part');
      tmp.writeAsBytesSync(bytes, flush: true);
      tmp.renameSync(f.path);
      final st = f.statSync();
      _mine[e.path] = SyncEntry(e.path, st.size, st.modified.millisecondsSinceEpoch, e.sha);
      _justApplied[e.path] = st.modified.millisecondsSinceEpoch;
      _lastApplied = DateTime.now();
      // It got past _wants, so it is newer than any tombstone we hold: the
      // document is back, and the record of its deletion has to go with it or
      // the next scan would delete it again.
      if (_tombs.remove(e.path) != null) _saveTombs();
      Log.i('sync', 'took ${e.path} (${bytes.length} bytes)');
      return true;
    } catch (err) {
      Log.w('sync', 'could not write ${e.path}: $err');
      return false;
    }
  }

  /// settings.json is MERGED, not replaced.
  ///
  /// The file is one object several preferences share, and three of its keys
  /// are about this device rather than about the app — the share code above
  /// all. Overwriting the file whole would mean a device could turn another
  /// one's sharing off by saving a preference, which is not what "settings are
  /// synced" means to anyone.
  bool _applySettings(SyncEntry e, Uint8List bytes) {
    final f = _fileFor(e.path);
    if (f == null) return false;
    try {
      final incoming = jsonDecode(utf8.decode(bytes));
      if (incoming is! Map) return false;
      Map<String, Object?> merged = <String, Object?>{};
      if (f.existsSync()) {
        final mineRaw = jsonDecode(f.readAsStringSync());
        if (mineRaw is Map) {
          merged = <String, Object?>{
            for (final en in mineRaw.entries) '${en.key}': en.value
          };
        }
      }
      final local = <String, Object?>{
        for (final k in _localOnlyPrefs)
          if (merged.containsKey(k)) k: merged[k]
      };
      for (final en in incoming.entries) {
        final k = '${en.key}';
        if (_localOnlyPrefs.contains(k)) continue;
        merged[k] = en.value;
      }
      merged.addAll(local);
      final out = utf8.encode(jsonEncode(merged));
      final tmp = File('${f.path}.sync-part');
      tmp.writeAsBytesSync(out, flush: true);
      tmp.renameSync(f.path);
      final st = f.statSync();
      // The merged file is NOT what the peer sent, so its hash is this
      // device's own — recorded so the next scan does not read the difference
      // as a local edit and send it straight back.
      _mine[e.path] = SyncEntry(e.path, st.size,
          st.modified.millisecondsSinceEpoch, sha256.convert(out).toString());
      _justApplied[e.path] = st.modified.millisecondsSinceEpoch;
      _lastApplied = DateTime.now();
      Log.i('sync', 'merged settings from a peer');
      return true;
    } catch (err) {
      Log.w('sync', 'could not merge settings: $err');
      return false;
    }
  }

  void _applied(Set<String> paths) {
    if (paths.isEmpty) return;
    _publish();
    try {
      onApplied?.call(paths);
    } catch (e) {
      Log.w('sync', 'the app could not take what arrived: $e');
    }
  }

  /// Reads a file for a peer that asked for it.
  Uint8List? _read(String path) {
    final f = _fileFor(path);
    if (f == null || !f.existsSync()) return null;
    try {
      return f.readAsBytesSync();
    } catch (e) {
      Log.w('sync', 'could not read $path for a peer: $e');
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // Deletes
  // -------------------------------------------------------------------------

  /// Where the tombstones live. Not in [_prefFiles], so the journal itself is
  /// never mirrored as a FILE — it travels as facts inside the manifest, and
  /// two devices that overwrote each other's journals would lose the very
  /// records they were exchanging.
  static const String _tombFile = 'sync-deleted.json';

  /// How long a tombstone is worth keeping.
  ///
  /// It has to outlive a device being away — a laptop shut in a bag for a
  /// fortnight has to learn on its return that a document went — and it must
  /// not grow without bound. A month is comfortably past the first and
  /// nowhere near the second: a tombstone is about sixty bytes.
  static const Duration _tombLife = Duration(days: 30);

  File? get _tombPath {
    final prefs = _prefs;
    return prefs == null ? null : File('${prefs.path}/$_tombFile');
  }

  void _loadTombs() {
    _tombs = <String, int>{};
    final f = _tombPath;
    if (f == null || !f.existsSync()) return;
    try {
      final raw = jsonDecode(f.readAsStringSync());
      if (raw is! Map) return;
      for (final e in raw.entries) {
        final d = (e.value as num?)?.toInt();
        if (d != null) _tombs['${e.key}'] = d;
      }
      _expireTombs();
    } catch (e) {
      Log.w('sync', 'could not read the delete journal: $e');
    }
  }

  void _saveTombs() {
    final f = _tombPath;
    if (f == null) return;
    try {
      f.parent.createSync(recursive: true);
      final tmp = File('${f.path}.sync-part');
      tmp.writeAsStringSync(jsonEncode(_tombs), flush: true);
      tmp.renameSync(f.path);
    } catch (e) {
      Log.w('sync', 'could not write the delete journal: $e');
    }
  }

  void _expireTombs() {
    final cutoff =
        DateTime.now().subtract(_tombLife).millisecondsSinceEpoch;
    _tombs.removeWhere((_, d) => d < cutoff);
  }

  /// True when [path] may carry a tombstone at all.
  ///
  /// Documents only. Deleting `settings.json` is not something anyone does on
  /// purpose, and a tombstone for it would be a way to wipe another device's
  /// preferences from this one.
  bool _deletable(String path) =>
      !path.startsWith(_prefsPrefix) && _fileFor(path) != null;

  /// Applies a peer's tombstone. Returns true when a file actually went.
  ///
  /// THE RULE IS THE SAME ONE FILES USE — the later of the two wins — so a
  /// document deleted on one device and then saved again on another comes
  /// back, and a document saved and then deleted stays gone. The one second of
  /// slack is [_wants]'s, for [_wants]'s reason: two clocks are never equal.
  bool _applyTomb(SyncTomb t) {
    if (!_deletable(t.path)) return false;
    final known = _tombs[t.path];
    if (known != null && known >= t.deletedAtMs) return false;
    final mine = _mine[t.path];
    if (mine != null && mine.mtimeMs > t.deletedAtMs + 1000) {
      // Saved again here AFTER it was deleted there. The save wins; the next
      // announcement carries it back.
      return false;
    }
    _tombs[t.path] = t.deletedAtMs;
    _saveTombs();
    final f = _fileFor(t.path);
    var removed = false;
    if (f != null && f.existsSync()) {
      try {
        f.deleteSync();
        removed = true;
        Log.i('sync', 'removed ${t.path} — deleted on another device');
      } catch (e) {
        Log.w('sync', 'could not remove ${t.path}: $e');
      }
    }
    // Forgotten from the manifest either way: this device now agrees the file
    // is gone, and leaving a stale entry would make the next scan read the
    // absence as a NEW deletion and stamp it with a new time.
    _mine.remove(t.path);
    _justApplied.remove(t.path);
    if (removed) _lastApplied = DateTime.now();
    return removed;
  }

  /// The tombstones worth sending: everything still inside [_tombLife].
  List<SyncTomb> get _tombList {
    _expireTombs();
    return <SyncTomb>[
      for (final e in _tombs.entries) SyncTomb(e.key, e.value)
    ];
  }

  @visibleForTesting
  Map<String, int> get tombsForTest => _tombs;

  @visibleForTesting
  bool applyTombForTest(SyncTomb t) => _applyTomb(t);

  @visibleForTesting
  List<SyncTomb> noticeDeletesForTest() => _noticeDeletes(_scanLocal());

  @visibleForTesting
  Map<String, SyncEntry> get localManifestForTest => _mine;

  @visibleForTesting
  Map<String, SyncEntry> scanForTest() => _scanLocal();

  @visibleForTesting
  bool wantsForTest(SyncEntry e) => _wants(e);

  @visibleForTesting
  bool applyForTest(SyncEntry e, Uint8List bytes) => _apply(e, bytes);

  @visibleForTesting
  void attachForTest({required Directory documents, required Directory preferences}) {
    _docs = documents;
    _prefs = preferences;
    _loadTombs();
    _mine = _scanLocal();
  }
}

/// One connection to one peer.
class _SyncSession {
  _SyncSession(this._sync, this._socket, {required this.outgoing, this.peerId});

  /// A slot-holder, so two beacons cannot start two connections.
  _SyncSession.pending(this.peerId)
      : _sync = LanSync.instance,
        _socket = null,
        outgoing = true;

  final LanSync _sync;
  final Socket? _socket;
  final bool outgoing;
  String? peerId;
  String peerName = '?';

  final SyncFrameReader _reader = SyncFrameReader();
  bool _authed = false;
  String? _myNonce;
  final Set<String> _applied = <String>{};
  Timer? _settle;

  bool get live => _authed && _socket != null;

  void start() {
    final sock = _socket;
    if (sock == null) return;
    sock.setOption(SocketOption.tcpNoDelay, true);
    sock.listen(
      _onData,
      onError: (Object e) => close('$e'),
      onDone: () => close('closed'),
      cancelOnError: true,
    );
    // The LISTENER speaks first: it is the one holding the nonce, so an
    // attacker who merely connects learns nothing and has to answer something.
    if (!outgoing) {
      _myNonce = newNonce();
      _send(SyncFrame({
        't': SyncMsg.hello,
        'v': kSyncProtocolVersion,
        'id': _sync._deviceId,
        'n': _sync._deviceName,
        'nonce': _myNonce,
      }));
    }
  }

  void _onData(Uint8List data) {
    List<SyncFrame> frames;
    try {
      frames = _reader.add(data);
    } catch (e) {
      close('bad frame: $e');
      return;
    }
    for (final f in frames) {
      try {
        _onFrame(f);
      } catch (e) {
        close('bad message: $e');
        return;
      }
    }
  }

  void _onFrame(SyncFrame f) {
    final key = _sync._key;
    if (key == null) {
      close('sharing off');
      return;
    }
    switch (f.type) {
      case SyncMsg.hello:
        if ((f.header['v'] as num?)?.toInt() != kSyncProtocolVersion) {
          _refuse('version');
          return;
        }
        peerId = '${f.header['id']}';
        peerName = '${f.header['n']}';
        _myNonce = newNonce();
        _send(SyncFrame({
          't': SyncMsg.auth,
          'v': kSyncProtocolVersion,
          'id': _sync._deviceId,
          'n': _sync._deviceName,
          'proof': shareCodeProof(key, '${f.header['nonce']}'),
          'nonce': _myNonce,
        }));
      case SyncMsg.auth:
        final mine = _myNonce;
        if (mine == null ||
            !secureEquals('${f.header['proof']}', shareCodeProof(key, mine))) {
          _refuse('the code does not match');
          return;
        }
        peerId = '${f.header['id']}';
        peerName = '${f.header['n']}';
        _send(SyncFrame({
          't': SyncMsg.ready,
          'proof': shareCodeProof(key, '${f.header['nonce']}'),
        }));
        _live();
      case SyncMsg.ready:
        final mine = _myNonce;
        if (mine == null ||
            !secureEquals('${f.header['proof']}', shareCodeProof(key, mine))) {
          _refuse('the code does not match');
          return;
        }
        _live();
      case SyncMsg.manifest:
        _requireAuth();
        _onManifest(f);
      case SyncMsg.changed:
        _requireAuth();
        _onManifest(f);
      case SyncMsg.want:
        _requireAuth();
        for (final p in (f.header['paths'] as List? ?? const [])) {
          _sendFile('$p');
        }
      case SyncMsg.file:
        _requireAuth();
        final e = SyncEntry.fromJson(f.header['e']);
        final body = f.payload;
        if (e == null || body == null) return;
        if (_sync._apply(e, body)) {
          _applied.add(e.path);
          // One notification for a burst, not one per file: a first pair-up
          // can be thirty documents and the gallery should rebuild once.
          _settle?.cancel();
          _settle = Timer(const Duration(milliseconds: 400), () {
            _sync._applied(Set<String>.of(_applied));
            _applied.clear();
          });
        }
      case SyncMsg.bye:
        close('peer said: ${f.header['why']}');
      default:
        // An unknown type from a newer peer is not a reason to hang up.
        break;
    }
  }

  void _requireAuth() {
    if (!_authed) throw StateError('before the handshake');
  }

  void _live() {
    _authed = true;
    final id = peerId;
    if (id == null) {
      close('no id');
      return;
    }
    Log.i('sync', 'paired with $peerName ($id)');
    _sync._adopt(this, id);
    // Both sides send their whole manifest as soon as they are satisfied. It
    // is a few hundred bytes per document and it makes the first exchange one
    // round trip instead of a negotiation.
    _send(SyncFrame({
      't': SyncMsg.manifest,
      'files': [for (final e in _sync._scanLocal().values) e.toJson()],
      'tombs': [for (final t in _sync._tombList) t.toJson()],
    }));
  }

  void _onManifest(SyncFrame f) {
    // TOMBSTONES FIRST, and the order is the whole point: a peer that both
    // deleted A and saved B sends one manifest, and applying the delete before
    // deciding what to ask for is what stops this device asking for A back
    // from the same message that says A is gone.
    final removed = <String>{};
    for (final raw in (f.header['tombs'] as List? ?? const [])) {
      final t = SyncTomb.fromJson(raw);
      if (t == null) continue;
      if (_sync._applyTomb(t)) removed.add(t.path);
    }
    final want = <String>[];
    for (final raw in (f.header['files'] as List? ?? const [])) {
      final e = SyncEntry.fromJson(raw);
      if (e == null) continue;
      if (_sync._fileFor(e.path) == null) continue;
      if (_sync._wants(e)) want.add(e.path);
    }
    if (removed.isNotEmpty) _sync._applied(removed);
    if (want.isEmpty) return;
    Log.i('sync', 'asking $peerName for ${want.join(", ")}');
    _send(SyncFrame({'t': SyncMsg.want, 'paths': want}));
  }

  void announce(List<SyncEntry> changed, [List<SyncTomb> gone = const []]) {
    _send(SyncFrame({
      't': SyncMsg.changed,
      'files': [for (final e in changed) e.toJson()],
      'tombs': [for (final t in gone) t.toJson()],
    }));
  }

  void _sendFile(String path) {
    final bytes = _sync._read(path);
    if (bytes == null) return;
    final f = _sync._fileFor(path);
    if (f == null) return;
    final st = f.statSync();
    _send(SyncFrame({
      't': SyncMsg.file,
      'e': SyncEntry(path, st.size, st.modified.millisecondsSinceEpoch,
              sha256.convert(bytes).toString())
          .toJson(),
    }, bytes));
  }

  void _send(SyncFrame f) {
    try {
      _socket?.add(f.encode());
    } catch (e) {
      close('$e');
    }
  }

  void _refuse(String why) {
    Log.w('sync', 'refusing $peerName: $why');
    _send(SyncFrame({'t': SyncMsg.bye, 'why': why}));
    close(why);
  }

  void close(String why) {
    _settle?.cancel();
    if (_authed) Log.i('sync', 'disconnected from $peerName ($why)');
    _authed = false;
    try {
      _socket?.destroy();
    } catch (_) {
      // Already gone.
    }
    _sync._forget(this);
  }
}

/// The addresses a beacon goes to, given this machine's IPv4 addresses.
///
/// A free function rather than a method because it is the one part of the
/// beacon that is pure — a list of strings in, a list of addresses out — and
/// therefore the one part that can be tested without a network.
List<InternetAddress> broadcastAddressesFor(List<String> localV4) {
  final out = <InternetAddress>[InternetAddress('255.255.255.255')];
  final seen = <String>{};
  for (final a in localV4) {
    final dot = a.lastIndexOf('.');
    if (dot <= 0) continue;
    final directed = '${a.substring(0, dot)}.255';
    if (directed == '255.255.255.255' || !seen.add(directed)) continue;
    try {
      out.add(InternetAddress(directed));
    } catch (_) {
      // Not an address after all; the limited broadcast still goes.
    }
  }
  return out;
}
