// Prototype — every device with the same share code, on the same network,
// holding the same documents and the same settings.
//
// WHAT IT IS
// ----------
// Type a code in Settings on two devices. They find each other — with a UDP
// beacon between desktops and over Bonjour wherever an iPad is involved, since
// an iPad is not allowed to broadcast — prove to each other that they know the
// code, compare what they have and fill in each other's gaps. Then they stay
// connected, so a document saved on the iPad is on the laptop a moment later
// without anybody pressing anything.
//
// HOW "A MOMENT LATER" IS ACTUALLY ACHIEVED, since it is four separate things
// and each of them was once the slow one:
//
//   * The app SAYS SO. [LanSync.nudge] is called the instant a document is
//     written, renamed or deleted, rather than leaving the mirror to notice.
//   * Where nothing calls it — a preference written by one of the nine little
//     stores, say — a one-second poll notices instead, which is affordable
//     only because [LanSync._entryFor] caches a file's hash against its size
//     and time and so does no I/O at all over an unchanged gallery.
//   * A paired session WRITES SOMETHING every eight seconds whether or not it
//     has anything to say, because a half-open socket is silent and looks
//     exactly like a working one until somebody tries it.
//   * And [LanSync.resume] rebuilds the lot when the app comes back to the
//     foreground, which on iOS is the only moment at which the sockets the OS
//     closed underneath it can be noticed at all.
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
//   * It DOES delete, and that came after the rest of this on purpose. A
//     deletion travels as a tombstone — a fact with a time on it, kept for a
//     month so that a device which was switched off still learns of it — and
//     it loses to any save that is newer. The failure mode of a delete
//     propagating through a bug is losing work everywhere at once, so the rule
//     is the same one files use and nothing more: the later of the two wins.
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
import 'bonjour.dart';
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

  /// M417 — THE VERSION THAT WAS THROWN AWAY, when the deleting device knew
  /// it. This is what lets the other side answer "have I got anything to
  /// lose?" instead of "is my clock ahead?": a device holding exactly these
  /// bytes has nothing to lose and removes them, and a device holding
  /// anything else has an edit, which outlives a deletion.
  ///
  /// Null from a peer that predates this, and from a journal written by one.
  /// [LanSync._applyTomb] falls back to what it knew before in that case
  /// rather than refusing every delete it cannot prove is safe.
  final String? sha;

  const SyncTomb(this.path, this.deletedAtMs, [this.sha]);

  Map<String, Object?> toJson() => {
        'p': path,
        'd': deletedAtMs,
        if (sha != null) 'h': sha,
      };

  static SyncTomb? fromJson(Object? o) {
    if (o is! Map) return null;
    final p = o['p'];
    final d = (o['d'] as num?)?.toInt();
    if (p is! String || p.isEmpty || d == null) return null;
    final h = o['h'];
    return SyncTomb(p, d, h is String && h.isNotEmpty ? h : null);
  }
}

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

  SyncPeer withSeen(DateTime t) => SyncPeer(
      id: id, name: name, host: host, port: port, seen: t, connected: connected);
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

  /// Value equality, and it earns its place rather than being tidiness.
  ///
  /// [LanSync.status] is a ValueNotifier and [LanSync._publish] is called on
  /// every sweep — every two seconds, whether or not anything changed. A
  /// ValueNotifier only notifies when the new value differs from the old, so
  /// without this every listener is woken twice a second to be told exactly
  /// what it already knew, and the settings sheet redraws itself through a
  /// platform channel for nothing.
  @override
  bool operator ==(Object other) =>
      other is SyncStatus &&
      other.state == state &&
      other.peers == peers &&
      other.lastChange == lastChange &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(state, peers, lastChange, detail);
}

/// A document that was changed in two places at once, and what was done about
/// it: BOTH versions were kept, one under its own name and one under [copy].
///
/// M417 — there is no merge for a B-Rep feature tree, so the only honest
/// answers are "pick one" and "keep both", and only one of those can be given
/// without asking a question the person cannot answer. A beginner cannot say
/// whether they want "mine" or "theirs" from a filename and a time; they can
/// say it from two thumbnails they can open and look at. So the app keeps both
/// and says so, and deleting the one you do not want is the Delete you already
/// know.
@immutable
class SyncFork {
  /// The document that kept its name — the newer of the two.
  final String original;

  /// The copy the older version was kept under, e.g. `Bracket (iPad).ptp`.
  final String copy;

  /// The device the copied version was last saved on, which is what [copy] is
  /// named after.
  final String owner;

  const SyncFork(this.original, this.copy, this.owner);

  @override
  bool operator ==(Object other) =>
      other is SyncFork &&
      other.original == original &&
      other.copy == copy &&
      other.owner == owner;

  @override
  int get hashCode => Object.hash(original, copy, owner);
}

/// What should happen to a file a peer is offering.
enum SyncVerdict {
  /// Nothing: already the same, older than what is here, or deleted here.
  skip,

  /// Take it. Either this device does not have the file, or it has exactly
  /// the version the group last agreed on and the peer has moved on from it.
  take,

  /// BOTH sides changed it since they last agreed. Keep both.
  fork,
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

  /// When each peer was first seen, kept until it pairs or goes away. The
  /// escape hatch in [_maybeDial] is timed from this.
  final Map<String, DateTime> _firstSeen = <String, DateTime>{};

  /// Peers this device dialled against the id rule, so the reason is logged
  /// once rather than on every sweep that finds the same asymmetry.
  final Set<String> _reverseDialled = <String>{};

  /// Content hashes, by mirror path, trusted only while the file's size and
  /// modification time are what they were when it was hashed. See [_entryFor]
  /// — this is what makes a one-second poll cost a `stat` per document
  /// instead of a full read and a SHA-256 of the whole gallery.
  final Map<String, SyncEntry> _hashes = <String, SyncEntry>{};

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

  /// THE VERSION THIS DEVICE AND THE GROUP LAST AGREED ON, by path: the sha of
  /// the bytes that were either taken from a peer or handed to one.
  ///
  /// M417 — THE PIECE THAT WAS MISSING, and the whole of why this used to lose
  /// work. Without it the only question that can be asked about an incoming
  /// file is "is it newer than mine", and that question cannot tell these two
  /// apart:
  ///
  ///   * I have an old version and they saved a new one — they should win;
  ///   * I edited mine and they edited theirs — NOBODY should win.
  ///
  /// Both look like "their timestamp is larger", so the second silently
  /// destroyed one side's afternoon, and which side depended on two clocks
  /// that were never synchronised. With a base version the two are different
  /// questions with different answers (see [verdictFor]) and no clock is
  /// consulted at all.
  ///
  /// Kept beside the delete journal, in the same shape and for the same
  /// reason: it has to survive a restart, and it is about THIS device's
  /// relationship with the group, so it is never mirrored.
  Map<String, String> _base = <String, String>{};

  /// Divergences resolved since the app last cleared them, for the gallery to
  /// tell the user about. Newest last.
  final ValueNotifier<List<SyncFork>> recentForks =
      ValueNotifier<List<SyncFork>>(const <SyncFork>[]);

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
    _loadBase();
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

  /// Every code change gets a number, and a change that has been overtaken
  /// stands down instead of finishing on top of the newer one.
  ///
  /// THE BUG THIS IS FOR. Turning the mirror on or off stops one and starts
  /// another, and both halves await sockets — so two changes that overlap
  /// interleave, and the one that STARTED first can finish last and assign its
  /// own `_code` over the newer one's. What that looks like is a share code on
  /// screen, a listener up, and a status row saying "off". Typing a code and
  /// changing your mind is enough to produce it, and so is a [resume] landing
  /// on a code change — a likelier collision than it sounds, since both happen
  /// when somebody picks the device up.
  ///
  /// A COUNTER RATHER THAN A QUEUE, and the queue was tried first. Chaining
  /// each change onto the last is the obvious answer and it has a failure this
  /// does not: the chain's continuation is registered in whatever zone the
  /// first caller happened to be in, and if that zone stops running — a widget
  /// test's, most sharply, but any zone can be torn down — every later change
  /// waits behind a callback that will never fire, and sharing can no longer
  /// be switched off for the rest of the process. Nothing recovers from that,
  /// not even a timeout, because the timeout is scheduled in the dead zone
  /// too.
  ///
  /// A counter has no such thread to break. Each change checks, after every
  /// await, whether it is still the one that matters, and quietly stops if it
  /// is not.
  int _codeGen = 0;

  /// What has been ASKED for, which is not the same as what is running.
  ///
  /// A change is several awaits long, so for most of one `_code` still holds
  /// the previous value — and a second change arriving in the middle has to
  /// compare itself against the intention rather than against how far the
  /// first one has got. Comparing against `_code` made a genuine change look
  /// like a repeat and drop it: ask for a code and immediately switch sharing
  /// off, and the "off" saw `_code` still null, decided there was nothing to
  /// do, and returned — leaving the first change to finish and turn sharing
  /// ON. Its own test caught it.
  String? _wanted;

  /// Turns the mirror on with [canonical], or off with null.
  ///
  /// Idempotent, and safe to call before [attach] — it simply records the code
  /// and does nothing until there is somewhere to mirror.
  Future<void> setCode(String? canonical) async {
    if (canonical == _wanted) return;
    _wanted = canonical;
    final gen = ++_codeGen;
    await _stop();
    if (gen != _codeGen) return; // overtaken while stopping
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
    if (gen != _codeGen) {
      // A newer change arrived while this one was binding its sockets. It has
      // its own _stop() to run and will; standing down here only avoids
      // reporting a state that is already gone.
      return;
    }
  }

  Future<void> _start() async {
    if (_docs == null || _prefs == null) return;
    try {
      _loadTombs();
      _mine = _scanLocal();
      _pruneBase();
      await _startServer();
      await _startBeacon();
      await _startBonjour();
      _watchLocal();
      unawaited(_refreshInterfaces());
      _interfaces = Timer.periodic(
          const Duration(seconds: 30), (_) => unawaited(_refreshInterfaces()));
      _announce =
          Timer.periodic(const Duration(seconds: 2), (_) => _sendBeacon());
      _scan = Timer.periodic(_sweepEvery, (_) => _sweep());
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
    _firstSeen.clear();
    _reverseDialled.clear();
    _beacon?.close();
    _beacon = null;
    await _bonjour.stop();
    await _server?.close();
    _server = null;
  }

  // -------------------------------------------------------------------------
  // Discovery
  // -------------------------------------------------------------------------

  /// The UDP beacon, which is how every desktop finds every other desktop.
  ///
  /// NOT FATAL WHEN IT FAILS, and that is the point of the try. iOS refuses a
  /// broadcast outright without an entitlement Apple grants case by case, so
  /// on a phone or a tablet this is expected to fail and Bonjour — started
  /// beside it — is the whole of discovery. A mirror that refused to start
  /// because one of its two ways of finding peers was unavailable would be a
  /// mirror that never ran on an iPad.
  Future<void> _startBeacon() async {
    try {
      // reusePort so two copies on ONE machine can both listen — which is not
      // a user's arrangement, it is how this gets tested, and a feature that
      // can only be tested by owning two devices does not get tested. Not
      // every platform honours it; the failure is one instance seeing the
      // other but not the reverse, which the dial rule below survives.
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
      }, onError: (Object e) {
        // A NETWORK THAT REFUSES A BROADCAST SAYS SO HERE, not from send().
        //
        //     SocketException: Send failed (OS Error: No route to host,
        //     errno = 65), address = 0.0.0.0, port = 47820
        //
        // `send` returns the byte count and reports the failure on the
        // socket's stream a moment later, so the try/catch around the send
        // never sees it — and a stream with no onError turns it into an
        // unhandled asynchronous error with nobody underneath to catch it.
        // A macOS CI runner produced exactly that; a guest network, a VPN
        // that swallows broadcast, or an interface going down mid-send are
        // the same shape on somebody's actual machine.
        //
        // Info rather than warning, and the mirror carries on: the beacon is
        // one of two ways of finding peers, and the one an iPad cannot use
        // anyway. Bonjour and mDNS are unaffected.
        Log.i('sync', 'the beacon socket gave up ($e) — Bonjour only');
      });
      _beacon = s;
    } catch (e) {
      Log.i('sync', 'no UDP beacon here ($e) — Bonjour only');
    }
  }

  /// Bonjour, which is how iOS is ALLOWED to find anything.
  ///
  /// Since iOS 14 a raw broadcast or multicast needs
  /// `com.apple.developer.networking.multicast`, an entitlement Apple grants
  /// by application; Bonjour through the system's own API needs only the
  /// local-network permission and a service type in Info.plist. So the phone
  /// advertises and browses `_prototypesync._tcp` and the desktops answer the
  /// beacon — and the two meet, because a desktop runs BOTH.
  final Bonjour _bonjour = Bonjour();

  Future<void> _startBonjour() async {
    final port = _server?.port;
    final fp = _fp;
    if (port == null || fp == null) return;
    await _bonjour.start(
      fingerprint: fp,
      deviceId: _deviceId,
      deviceName: _deviceName,
      port: port,
      onSighting: (s) {
        if (s.fingerprint != fp) return; // a different group
        if (s.id == _deviceId) return; // our own record, come back
        if (s.version != kSyncProtocolVersion) {
          Log.w('sync', 'peer ${s.id} speaks version ${s.version}, this one '
              'speaks $kSyncProtocolVersion — not pairing');
          return;
        }
        _sighted(id: s.id, name: s.name, host: s.host, port: s.port);
      },
    );
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
    _sighted(
        id: id, name: '${m['n']}', host: dg.address.address, port: port);
  }

  /// One device seen, however it was seen.
  ///
  /// The two discoveries end here rather than each keeping their own list: a
  /// desktop that hears a Mac's beacon AND resolves its Bonjour record has
  /// seen one device twice, and the peer map is keyed by device id precisely
  /// so that the second sighting refreshes the first instead of doubling it.
  void _sighted({
    required String id,
    required String name,
    required String host,
    required int port,
  }) {
    final known = _peers[id];
    _firstSeen.putIfAbsent(id, DateTime.now);
    _peers[id] = SyncPeer(
      id: id,
      name: name,
      host: host,
      port: port,
      seen: DateTime.now(),
      connected: known?.connected ?? false,
    );
    if (known == null) Log.i('sync', 'saw $name ($id) at $host:$port');
    _maybeDial(id);
    _publish();
  }

  /// ONE session per pair, and the lower id dials — until that stops working.
  ///
  /// Both devices are listening and both can see each other, so without a rule
  /// they each open a connection and every file crosses twice. Comparing the
  /// ids is the cheapest rule that both sides evaluate the same way with no
  /// extra round trip.
  ///
  /// IT ASSUMES BOTH SIDES CAN SEE EACH OTHER, and the iPad/Windows pair is
  /// exactly where that assumption breaks. An iPad can neither send nor hear
  /// the UDP beacon without an entitlement Apple grants case by case, and a
  /// Windows machine cannot always answer on port 5353 — something else may
  /// already hold it. Either leaves ONE device seeing a peer that is blind to
  /// it, and if the sighted one happens to hold the higher id then nobody ever
  /// dials: two machines a metre apart, both saying "looking", for ever.
  ///
  /// So after [dialGrace] the id rule is simply dropped and whoever can see
  /// dials. Late enough that the ordinary symmetric case has always paired
  /// long before, and a double dial was already survivable — [_adopt] keeps
  /// one of the two and hangs up the other.
  void _maybeDial(String id) {
    if (_sessions.containsKey(id)) return;
    final peer = _peers[id];
    if (peer == null) return;
    final since = _firstSeen[id];
    if (!shouldDial(
        myId: _deviceId,
        peerId: id,
        seenFor: since == null
            ? Duration.zero
            : DateTime.now().difference(since))) {
      return;
    }
    if (_deviceId.compareTo(id) >= 0) {
      if (_reverseDialled.add(id)) {
        Log.i(
            'sync',
            '${peer.name} can evidently not see this device — dialling it '
                'rather than waiting to be dialled');
      }
    }
    unawaited(_dial(peer));
  }

  Future<void> _dial(SyncPeer peer) async {
    if (_sessions.containsKey(peer.id)) return;
    // Claim the slot BEFORE the await, or two beacons a millisecond apart
    // start two connections to the same peer.
    final slot = _SyncSession.pending(peer.id);
    _sessions[peer.id] = slot;
    try {
      final sock = await Socket.connect(peer.host, peer.port,
          timeout: _dialTimeout);
      final s = _SyncSession(this, sock, outgoing: true, peerId: peer.id);
      _sessions[peer.id] = s;
      s.start();
    } catch (e) {
      // Only if the slot is still OURS. A sweep may have reaped this attempt
      // as stale and started another one, and removing the entry blind would
      // take that live session's place in the map with it.
      if (identical(_sessions[peer.id], slot)) _sessions.remove(peer.id);
      Log.w('sync', 'could not reach ${peer.name}: $e');
    }
  }

  /// Drops peers that have stopped announcing, and retries the ones that are
  /// there but not connected.
  void _sweep() {
    final now = DateTime.now();
    for (final id in _peers.keys.toList()) {
      final p = _peers[id]!;
      final s = _sessions[id];
      if (s != null && s.live) {
        // A CONNECTION IS BETTER EVIDENCE THAN AN ANNOUNCEMENT. Discovery is
        // UDP: a beacon or an mDNS answer can be lost several rounds running
        // on a busy network, and the old rule then dropped the peer and hung
        // up a session that was working perfectly — which the other side saw
        // as a disconnect, and which it then had to rebuild. That churn is
        // most of what "the sync keeps dropping" is. A live session refreshes
        // the sighting instead.
        _peers[id] = p.withSeen(now);
        continue;
      }
      if (now.difference(p.seen) > _peerLife) {
        _peers.remove(id);
        _firstSeen.remove(id);
        _reverseDialled.remove(id);
        _sessions.remove(id)?.close('gone');
        Log.i('sync', '${p.name} went away');
      } else if (s == null) {
        _maybeDial(id);
      } else if (s.stale) {
        // A slot held by a connection that never finished its handshake: a
        // TCP connect to a machine that has gone away can sit unanswered for
        // minutes, and for all of them this entry made every retry above look
        // unnecessary.
        _sessions.remove(id);
        s.close('handshake never finished');
        _maybeDial(id);
      }
    }
    _publish();
  }

  /// How long a peer survives on the strength of its last sighting alone.
  ///
  /// Six beacons or two mDNS query rounds. Long enough to ride out a handful
  /// of lost datagrams, short enough that a device that has actually gone
  /// leaves the settings row within a sweep or two.
  static const Duration _peerLife = Duration(seconds: 12);

  /// How often peers are aged and un-paired ones retried.
  static const Duration _sweepEvery = Duration(seconds: 2);

  /// How long the lower-id-dials rule is given before it is dropped. See
  /// [_maybeDial] and [shouldDial].
  static const Duration dialGrace = Duration(seconds: 4);

  /// How long to wait for a TCP connection to a peer that has just announced
  /// itself. It is one hop away; a machine that has not answered in four
  /// seconds is asleep, firewalled, or gone, and the sweep will try again.
  static const Duration _dialTimeout = Duration(seconds: 4);

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
    }, onError: (Object e) {
      // Same reasoning as the beacon's: an accept that fails reports on the
      // stream, and unhandled there it is an asynchronous error nothing
      // catches. This one IS worth a warning — a listener that has stopped
      // accepting means no peer can dial this device again.
      Log.w('sync', 'the listener stopped accepting: $e');
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

  /// The app came back to the foreground, or the network changed under it.
  ///
  /// Both leave the same wreckage and neither announces itself. iOS closes a
  /// suspended app's sockets, so an iPad that has been in a pocket comes back
  /// with a mirror whose beacon, listener and Bonjour registration are all
  /// gone — and nothing inside the app has any reason to think so. A Wi-Fi
  /// change or a laptop lid leaves TCP connections HALF OPEN instead:
  /// established on one side, gone on the other, silent until something is
  /// written to them.
  ///
  /// So this re-announces on every channel, asks every live session to prove
  /// it is alive, re-examines the local side — and rebuilds the whole mirror
  /// when the listener itself did not survive, which is the iPad case.
  Future<void> resume() async {
    if (_code == null) return;
    if (_server == null || (_beacon == null && !_bonjour.running)) {
      Log.i('sync', 'resuming: the listener did not survive — restarting');
      final gen = ++_codeGen;
      await _stop();
      if (gen != _codeGen) return; // the code changed under the resume
      await _start();
      return;
    }
    await _refreshInterfaces();
    _sendBeacon();
    await _startBonjour();
    for (final s in _sessions.values) {
      if (s.live) s.pingNow();
    }
    nudge();
    _publish();
  }

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
    // The hash cache follows the mirror rather than growing with it: a file
    // that is no longer there must not keep an entry alive, or a document
    // deleted and later restored to the same length at the same second would
    // be read as unchanged.
    if (_hashes.length > out.length) {
      _hashes.removeWhere((k, _) => !out.containsKey(k));
    }
    return out;
  }

  /// How long a file has to have been still before its hash is cached.
  ///
  /// A cache keyed on size and modification time cannot see a file rewritten
  /// to the SAME length inside one clock tick — and `settings.json` with a
  /// boolean toggled off and on again is exactly that shape, on filesystems
  /// whose timestamps have one-second granularity. Two seconds of distrust
  /// costs one re-read of one file, immediately after it was written, and
  /// nothing at all thereafter.
  static const int _settleMs = 2000;

  SyncEntry? _entryFor(String path, File f) {
    try {
      final st = f.statSync();
      final mtime = st.modified.millisecondsSinceEpoch;
      // Hashed rather than compared by size and time alone: two devices that
      // saved the same document a second apart have different times and
      // identical bytes, and copying it back and forth forever is what a mirror
      // that trusts timestamps does.
      //
      // But hashed ONCE. This used to read and SHA-256 every document in the
      // gallery on every scan, and a scan happens on every poll, on every
      // pair-up and on every manifest a peer sends — tens of megabytes of I/O
      // a few seconds apart, on the UI isolate, for an answer that had not
      // changed. Now a file whose size and time are what they were the last
      // time it was hashed keeps that hash, and the poll that pays for
      // instant sync costs a `stat` per document.
      final cached = _hashes[path];
      if (cached != null &&
          cached.size == st.size &&
          cached.mtimeMs == mtime &&
          DateTime.now().millisecondsSinceEpoch - mtime > _settleMs) {
        return cached;
      }
      final sha = sha256.convert(f.readAsBytesSync()).toString();
      final e = SyncEntry(path, st.size, mtime, sha);
      _hashes[path] = e;
      return e;
    } catch (e) {
      Log.w('sync', 'could not read $path: $e');
      return null;
    }
  }

  /// Records a file this device now holds, in both the manifest and the hash
  /// cache. Together, because a hash cache that disagrees with the manifest
  /// is worse than no hash cache at all.
  void _remember(SyncEntry e) {
    _mine[e.path] = e;
    _hashes[e.path] = e;
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

  /// How often the local side is re-examined where there is NO file watcher.
  ///
  /// `Directory.watch` throws on iOS, so on the one platform this app is
  /// primarily for, the poll is not a fallback — it is the only thing that
  /// ever notices a save, and its period is therefore the whole of the delay
  /// before another device hears about one. It used to be five seconds, on
  /// the reasoning that five seconds is indistinguishable from instant to
  /// somebody walking between two devices. It is not: you save on the iPad,
  /// you look at the laptop, and nothing happens for what feels like a long
  /// time. It is a second now, and [_entryFor]'s cache is what makes that
  /// affordable — a poll over an unchanged gallery is one `stat` per document
  /// and no reads at all.
  static const Duration _pollBare = Duration(seconds: 1);

  /// And with a watcher, where the poll is only the safety net for the events
  /// no platform delivers reliably — a file replaced by rename, a network
  /// volume, a sandbox that coalesces — so it can afford to be lazy.
  static const Duration _pollWatched = Duration(seconds: 4);

  /// Watches for local saves.
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
    _startPoll();
  }

  /// (Re)starts the poll at the cadence the current arrangement deserves.
  ///
  /// A separate method because [_fallBackToPolling] runs LATER — a watcher
  /// that fails does so on its stream, after this has already picked a
  /// period — and a device that has just discovered it has no watcher must
  /// not keep the lazy one.
  void _startPoll() {
    _poll?.cancel();
    final watching = _watchDocs != null || _watchPrefs != null;
    _poll = Timer.periodic(
        watching ? _pollWatched : _pollBare, (_) => _onLocalChange());
  }

  void _fallBackToPolling(Object e) {
    if (_watchDocs == null && _watchPrefs == null) return;
    Log.i('sync', 'no file watcher here ($e) — polling instead');
    _watchDocs?.cancel();
    _watchPrefs?.cancel();
    _watchDocs = _watchPrefs = null;
    _startPoll();
  }

  Timer? _debounce;

  void _onLocalChange() {
    // A save is several writes; announcing each one would send the document
    // three times. Half a second after the last of them is still immediate to
    // a person and is one transfer.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _announceChanges);
  }

  /// "The app has just finished writing something." Called by the app itself.
  ///
  /// The poll above notices a save within a second and a watcher within
  /// milliseconds, and neither is the point: the APP knows the exact moment a
  /// document is on disk, and saying so is the difference between a mirror
  /// that reacts and a mirror that checks. It is also the only signal that
  /// does not have to wait for a clock — a save and its announcement are one
  /// sequence rather than two that happen to meet.
  ///
  /// Shorter than the watcher's debounce because there is nothing left to
  /// wait for: the caller writes, then says so. Idempotent and cheap — it
  /// restarts a timer — so no caller ever has to work out whether this is the
  /// save that needs it.
  void nudge() {
    if (_code == null) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), _announceChanges);
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
      final was = _mine[path];
      // The version that went, kept for [verdictFor] and sent with the
      // tombstone so the other devices can answer the same question.
      if (was != null) _setBase(path, was.sha);
      out.add(SyncTomb(path, at, was?.sha));
    }
    if (out.isNotEmpty) _saveTombs();
    return out;
  }

  // -------------------------------------------------------------------------
  // Applying what a peer sent
  // -------------------------------------------------------------------------

  /// What should happen to [remote]: nothing, take it, or keep both.
  ///
  /// M417 — THE CONFLICT RULE, and it reads off three shas rather than two
  /// clocks. L is what this device holds, R is what the peer is offering, B is
  /// the version the two last agreed on ([_base]).
  ///
  ///   L == R                  they already agree            -> skip
  ///   L absent                nothing here to lose          -> take
  ///   L == B, R != B          only THEY moved on            -> take
  ///   R == B, L != B          only I moved on               -> skip (I push)
  ///   L != B, R != B, L != R  BOTH moved on                 -> fork
  ///   B absent, L != R        both invented the same name   -> fork
  ///
  /// The last two are the cases the old rule could not see. It compared
  /// modification times and let the larger one win, so two people editing the
  /// same document meant one of them lost, silently, decided by whichever
  /// machine's clock happened to run ahead. Nothing here consults a clock.
  SyncVerdict verdictFor(SyncEntry remote) {
    // PREFERENCES ARE NOT DOCUMENTS. `settings.json` is MERGED rather than
    // replaced (see [_applySettings]), so there is nothing here to lose and
    // nothing to keep two copies of — a preference that loses is a tick box in
    // the wrong position, not an afternoon's modelling. It keeps the rule it
    // has always had, which also keeps two devices from handing merged files
    // back to each other forever.
    if (remote.path.startsWith(_prefsPrefix)) {
      final mine = _mine[remote.path];
      if (mine == null) return SyncVerdict.take;
      if (mine.sha == remote.sha) return SyncVerdict.skip;
      return remote.mtimeMs > mine.mtimeMs + 1000
          ? SyncVerdict.take
          : SyncVerdict.skip;
    }
    // Deleted here, and the file on offer is the copy that was thrown away
    // coming back from a device that has not heard yet. Refusing it is what
    // makes a delete stick. A file SAVED again since the deletion is a
    // different thing and is caught below, by its sha differing from the one
    // the tombstone was written for.
    final tomb = _tombs[remote.path];
    final mine = _mine[remote.path];
    if (tomb != null && mine == null) {
      // The version we deleted is exactly the one being offered back.
      if (_base[remote.path] == remote.sha) return SyncVerdict.skip;
      // Something else: it was edited elsewhere after the delete travelled,
      // and an edit outlives a deletion (see [_applyTomb]).
      return SyncVerdict.take;
    }
    if (mine == null) return SyncVerdict.take;
    if (mine.sha == remote.sha) return SyncVerdict.skip;
    final base = _base[remote.path];
    if (base == null) return SyncVerdict.fork;
    if (mine.sha == base) return SyncVerdict.take;
    if (remote.sha == base) return SyncVerdict.skip;
    return SyncVerdict.fork;
  }

  /// The paths worth asking a peer for: everything we would either take or
  /// keep a second copy of. Both need the bytes.
  bool _wants(SyncEntry remote) =>
      verdictFor(remote) != SyncVerdict.skip;

  /// Writes a file a peer sent, atomically, and remembers it.
  ///
  /// [peerName] names the device it came from, which is what a kept-both copy
  /// is named after when this turns out to be a divergence.
  bool _apply(SyncEntry e, Uint8List bytes, {String peerName = 'another device'}) {
    final f = _fileFor(e.path);
    if (f == null) return false;
    final actual = sha256.convert(bytes).toString();
    if (actual != e.sha) {
      Log.w('sync', '${e.path} arrived corrupt — dropped');
      return false;
    }
    // The preference merge decides for itself what it keeps, key by key, and
    // is asked before the verdict for that reason.
    if (e.path == '${_prefsPrefix}settings.json') {
      try {
        return _applySettings(e, bytes);
      } catch (err) {
        Log.w('sync', 'could not merge ${e.path}: $err');
        return false;
      }
    }
    // M417 — asked AGAIN here, not just when the manifest arrived. The bytes
    // travel asynchronously and this device may have saved the document in
    // between; deciding on the state at the moment of the write is what makes
    // that save count rather than be overwritten by a decision taken before
    // it happened.
    final verdict = verdictFor(e);
    if (verdict == SyncVerdict.skip) return false;
    if (verdict == SyncVerdict.fork) return _fork(e, bytes, peerName);
    try {
      f.parent.createSync(recursive: true);
      // Written beside and renamed: a mirror that truncates a document and
      // then dies has destroyed it, and this app's documents are single files
      // with no journal behind them.
      final tmp = File('${f.path}.sync-part');
      tmp.writeAsBytesSync(bytes, flush: true);
      tmp.renameSync(f.path);
      final st = f.statSync();
      _remember(SyncEntry(
          e.path, st.size, st.modified.millisecondsSinceEpoch, e.sha));
      _justApplied[e.path] = st.modified.millisecondsSinceEpoch;
      // M417 — we now hold exactly what the group holds. That is the whole
      // definition of the base version, and recording it here is what lets
      // the NEXT change be told apart from a divergence.
      _setBase(e.path, e.sha);
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

  /// KEEPS BOTH VERSIONS. Returns true when something landed.
  ///
  /// M417 — the answer to "we both changed it". The newer of the two keeps the
  /// document's name and the older is kept beside it as
  /// `Bracket (Tom's iPad).ptp`, named after the device it was last saved on.
  /// Nothing is overwritten without its previous contents being written down
  /// first, so the worst this can cost is a card to tidy up.
  ///
  /// BOTH DEVICES RUN THIS, on the same pair of versions, and they have to
  /// reach the same two filenames holding the same two documents or the
  /// mirror would never settle. That is why the winner is chosen by
  /// modification time with the SHA as the tie-break rather than by "mine
  /// versus theirs": every device comparing the same L and R gets the same
  /// answer, whereas "mine wins" gets a different answer on each of them and
  /// the two would copy back and forth forever.
  bool _fork(SyncEntry remote, Uint8List remoteBytes, String peerName) {
    final mine = _mine[remote.path];
    if (mine == null) return false;
    final target = _fileFor(remote.path);
    if (target == null) return false;
    Uint8List myBytes;
    try {
      myBytes = target.readAsBytesSync();
    } catch (err) {
      Log.w('sync', 'could not read ${remote.path} to keep both: $err');
      return false;
    }
    // Deterministic, and identical on both devices: newer keeps the name; if
    // the two clocks say the same millisecond, the smaller SHA does.
    final theirsWins = remote.mtimeMs != mine.mtimeMs
        ? remote.mtimeMs > mine.mtimeMs
        : remote.sha.compareTo(mine.sha) < 0;
    final loserSha = theirsWins ? mine.sha : remote.sha;
    final loserBytes = theirsWins ? myBytes : remoteBytes;
    final loserOwner = theirsWins ? _deviceName : peerName;
    final copyPath = _freeCopyPath(remote.path, loserOwner, loserSha);
    if (copyPath == null) return false;
    final copyFile = _fileFor(copyPath);
    if (copyFile == null) return false;
    try {
      // The LOSER is written first, always. If anything fails after this the
      // worst outcome is a duplicate, never a missing version.
      if (!_writeAtomic(copyFile, loserBytes)) return false;
      _rememberOnDisk(copyPath, copyFile, loserSha);
      _setBase(copyPath, loserSha);
      if (theirsWins) {
        if (!_writeAtomic(target, remoteBytes)) return false;
        _rememberOnDisk(remote.path, target, remote.sha);
        _justApplied[remote.path] = target.statSync().modified
            .millisecondsSinceEpoch;
      }
      // THE REMOTE SHA, whichever version won, and the distinction matters:
      // the base has to say "this device has SEEN AND DEALT WITH that
      // version", not merely "this is what I hold". Recording my own sha when
      // mine won would leave `mine == base` true, which reads as "only they
      // moved on" — and the very next announcement of the version we just
      // decided against would overwrite the winner with the loser, forever.
      _setBase(remote.path, remote.sha);
      // A tombstone cannot outlive a document that is demonstrably still
      // being worked on, on two devices at once.
      if (_tombs.remove(remote.path) != null) _saveTombs();
      _lastApplied = DateTime.now();
      final fork = SyncFork(remote.path, copyPath, loserOwner);
      recentForks.value = <SyncFork>[...recentForks.value, fork];
      Log.i(
          'sync',
          '${remote.path} was changed here and on $peerName — '
          'both kept, the older one as $copyPath');
      return true;
    } catch (err) {
      Log.w('sync', 'could not keep both versions of ${remote.path}: $err');
      return false;
    }
  }

  /// `Bracket.ptp` + `Tom's iPad` -> `Bracket (Tom's iPad).ptp`, or the next
  /// free numbering of it. Null when the name cannot be formed.
  ///
  /// A target that ALREADY holds the bytes we were going to write is reused
  /// rather than numbered around: the two devices resolve the same divergence
  /// independently and a moment apart, and without this the second one to
  /// arrive would make `Bracket (iPad) 2.ptp` out of a file that is already
  /// there and identical.
  String? _freeCopyPath(String path, String owner, String sha) {
    final dot = path.lastIndexOf('.');
    if (dot <= 0) return null;
    final stem = path.substring(0, dot), ext = path.substring(dot);
    final tag = _safeName(owner);
    for (var n = 1; n <= 50; n++) {
      final candidate = n == 1 ? '$stem ($tag)$ext' : '$stem ($tag) $n$ext';
      if (_fileFor(candidate) == null) return null;
      final held = _mine[candidate];
      if (held == null) return candidate;
      if (held.sha == sha) return candidate; // already exactly this
    }
    return null;
  }

  /// A device name reduced to something every filesystem this app runs on
  /// will accept, and short enough to leave the document's own name readable.
  static String _safeName(String raw) {
    final cleaned = raw
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ')
        .replaceAll(RegExp(r'[\x00-\x1f]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return 'another device';
    return cleaned.length <= 40 ? cleaned : cleaned.substring(0, 40).trim();
  }

  /// Beside-and-rename, the same way [_apply] writes: a mirror that truncates
  /// a document and then dies has destroyed it.
  bool _writeAtomic(File f, Uint8List bytes) {
    try {
      f.parent.createSync(recursive: true);
      final tmp = File('${f.path}.sync-part');
      tmp.writeAsBytesSync(bytes, flush: true);
      tmp.renameSync(f.path);
      return true;
    } catch (e) {
      Log.w('sync', 'could not write ${f.path}: $e');
      return false;
    }
  }

  void _rememberOnDisk(String path, File f, String sha) {
    final st = f.statSync();
    _remember(
        SyncEntry(path, st.size, st.modified.millisecondsSinceEpoch, sha));
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
      _remember(SyncEntry(e.path, st.size, st.modified.millisecondsSinceEpoch,
          sha256.convert(out).toString()));
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

  /// A peer holds exactly what this device holds: that is an agreement, and
  /// it is worth writing down even though nothing moved.
  void _noteAgreement(SyncEntry remote) {
    final mine = _mine[remote.path];
    if (mine != null && mine.sha == remote.sha) _setBase(remote.path, remote.sha);
  }

  /// This device has just handed [path] to a peer.
  void _noteHandedOver(String path, String sha) {
    final mine = _mine[path];
    if (mine != null && mine.sha == sha) _setBase(path, sha);
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
  /// M417 — A DELETE NEVER BEATS AN EDIT, and that is the whole rule now.
  /// This used to be "the later of the two wins", decided by comparing a
  /// tombstone's timestamp against a file's modification time — two clocks on
  /// two machines — so whether your afternoon survived somebody else's tidying
  /// up came down to which device was running fast. It is a question about
  /// versions, not times: if this device holds exactly the version that was
  /// thrown away it has nothing to lose and the delete applies; if it holds
  /// anything else, somebody changed it here since, and the edit stays.
  ///
  /// The failure mode this protects against is the worst one the mirror has —
  /// a deletion propagating through a bug loses work everywhere at once — so
  /// it errs, deliberately, towards keeping a file nobody wanted rather than
  /// removing one somebody did.
  bool _applyTomb(SyncTomb t) {
    if (!_deletable(t.path)) return false;
    final known = _tombs[t.path];
    if (known != null && known >= t.deletedAtMs) return false;
    final mine = _mine[t.path];
    if (mine != null && !_deleteIsSafe(t, mine)) {
      // Changed here since this device and the group last agreed. Keep it;
      // the next announcement carries it back to whoever deleted it.
      Log.i(
          'sync',
          'kept ${t.path} — deleted elsewhere, but it has been changed here '
          'since the two devices last agreed');
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
    _hashes.remove(t.path);
    _justApplied.remove(t.path);
    // NOT dropped: the sha of the version that went is exactly what lets
    // [verdictFor] recognise the copy a peer who has not heard yet offers
    // back, and refuse it. Dropping it is how a delete fails to stick.
    if (mine != null) _setBase(t.path, mine.sha);
    if (removed) _lastApplied = DateTime.now();
    return removed;
  }

  // -------------------------------------------------------------------------
  // The base version (M417)
  // -------------------------------------------------------------------------

  /// Where the agreed-version journal lives. Beside the delete journal, and
  /// like it never mirrored as a FILE: it describes this device's
  /// relationship with the group, and two devices overwriting each other's
  /// copies would destroy the very records that keep them apart.
  static const String _baseFile = 'sync-base.json';

  File? get _basePath {
    final prefs = _prefs;
    return prefs == null ? null : File('${prefs.path}/$_baseFile');
  }

  void _loadBase() {
    _base = <String, String>{};
    final f = _basePath;
    if (f == null || !f.existsSync()) return;
    try {
      final raw = jsonDecode(f.readAsStringSync());
      if (raw is! Map) return;
      for (final e in raw.entries) {
        final v = e.value;
        if (v is String && v.isNotEmpty) _base['${e.key}'] = v;
      }
    } catch (e) {
      Log.w('sync', 'could not read the agreed-version journal: $e');
    }
  }

  void _saveBase() {
    final f = _basePath;
    if (f == null) return;
    try {
      f.parent.createSync(recursive: true);
      final tmp = File('${f.path}.sync-part');
      tmp.writeAsStringSync(jsonEncode(_base), flush: true);
      tmp.renameSync(f.path);
    } catch (e) {
      Log.w('sync', 'could not write the agreed-version journal: $e');
    }
  }

  void _setBase(String path, String sha) {
    if (_base[path] == sha) return;
    _base[path] = sha;
    _saveBase();
  }

  /// Forgets the agreed version of everything this device neither holds nor
  /// remembers deleting, so the journal follows the gallery instead of growing
  /// with everything that ever passed through it.
  void _pruneBase() {
    final before = _base.length;
    _base.removeWhere((p, _) => !_mine.containsKey(p) && !_tombs.containsKey(p));
    if (_base.length != before) _saveBase();
  }

  @visibleForTesting
  Map<String, String> get baseForTest => _base;

  @visibleForTesting
  void setBaseForTest(String path, String sha) => _setBase(path, sha);

  /// Is removing [mine] safe — i.e. does this device hold exactly the version
  /// that was thrown away, with nothing of its own on top?
  ///
  /// Three sources of truth, best first. The tombstone's own sha is the good
  /// one and needs nothing else. The base version answers it for a peer too
  /// old to send one. With neither — an old journal, an old peer, a file this
  /// device has never exchanged — there is nothing to compare and the old
  /// timestamp heuristic is kept rather than refusing every delete that cannot
  /// be proved safe, which would leave documents undeletable across an
  /// upgrade.
  bool _deleteIsSafe(SyncTomb t, SyncEntry mine) {
    final theirs = t.sha;
    if (theirs != null) return mine.sha == theirs;
    final base = _base[t.path];
    if (base != null) return mine.sha == base;
    return mine.mtimeMs <= t.deletedAtMs + 1000;
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
  bool applyForTest(SyncEntry e, Uint8List bytes,
          {String peerName = 'another device'}) =>
      _apply(e, bytes, peerName: peerName);

  @visibleForTesting
  void noteAgreementForTest(SyncEntry e) => _noteAgreement(e);

  @visibleForTesting
  void noteHandedOverForTest(String path, String sha) =>
      _noteHandedOver(path, sha);

  @visibleForTesting
  void pruneBaseForTest() => _pruneBase();

  @visibleForTesting
  void attachForTest(
      {required Directory documents,
      required Directory preferences,
      String deviceName = 'device'}) {
    _docs = documents;
    _prefs = preferences;
    _deviceName = deviceName;
    _loadTombs();
    // M417 — and the agreed-version journal, for the same reason the delete
    // journal is loaded here: this is a singleton, so a test that inherited
    // the previous test's idea of what the group had agreed would be reading
    // state nothing in it put there.
    _loadBase();
    _hashes.clear();
    recentForks.value = const <SyncFork>[];
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

  /// How often a paired session writes something, whether or not it has
  /// anything to say. See [SyncMsg.ping].
  static const Duration _beatEvery = Duration(seconds: 8);

  /// How long a peer that ANSWERS pings may go silent before it is given up
  /// on. Five missed beats: enough that a machine busy writing a large
  /// document is never mistaken for a dead one.
  static const Duration _beatDeadline = Duration(seconds: 45);

  /// How long a connection may take to finish its handshake. It is four
  /// frames over one LAN hop; anything slower has failed in a way TCP has not
  /// noticed yet.
  static const Duration _handshakeDeadline = Duration(seconds: 10);

  /// When this session was created, so a sweep can tell a connection that is
  /// still being made from one that will never finish.
  final DateTime _born = DateTime.now();

  /// The last time ANYTHING arrived on this socket.
  DateTime _heard = DateTime.now();

  /// Whether this peer has ever answered a ping. Until it has, silence from
  /// it means nothing: an older build ignores an unknown frame type, and
  /// hanging up on one every forty-five seconds would be a reconnect loop
  /// wearing a health check's clothes.
  bool _peerAnswers = false;

  Timer? _beat;
  Timer? _deadline;

  bool get live => _authed && _socket != null;

  /// True for a slot that has been sitting unpaired long enough to be
  /// written off — a pending dial to a machine that has gone away, or a
  /// connection whose handshake stalled. [LanSync._sweep] clears these,
  /// because until it does they make every retry look unnecessary.
  bool get stale =>
      !_authed && DateTime.now().difference(_born) > _handshakeDeadline;

  void start() {
    final sock = _socket;
    if (sock == null) return;
    sock.setOption(SocketOption.tcpNoDelay, true);
    _deadline = Timer(_handshakeDeadline, () {
      if (!_authed) close('the handshake did not finish');
    });
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
    _heard = DateTime.now();
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
        if (_sync._apply(e, body, peerName: peerName)) {
          _applied.add(e.path);
          // One notification for a burst, not one per file: a first pair-up
          // can be thirty documents and the gallery should rebuild once.
          _settle?.cancel();
          _settle = Timer(const Duration(milliseconds: 400), () {
            _sync._applied(Set<String>.of(_applied));
            _applied.clear();
          });
        }
      case SyncMsg.ping:
        _send(SyncFrame({'t': SyncMsg.pong}));
      case SyncMsg.pong:
        _peerAnswers = true;
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
    _deadline?.cancel();
    _deadline = null;
    _heard = DateTime.now();
    _beat = Timer.periodic(_beatEvery, (_) => _tick());
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
      // M417 — TWO DEVICES THAT ALREADY HOLD THE SAME BYTES HAVE AGREED, and
      // saying so is what gives an install that predates the journal a base to
      // reason from. Without it the first edit after an upgrade would look
      // like a divergence and be kept twice.
      _sync._noteAgreement(e);
      if (_sync._wants(e)) want.add(e.path);
    }
    if (removed.isNotEmpty) _sync._applied(removed);
    if (want.isEmpty) return;
    Log.i('sync', 'asking $peerName for ${want.join(", ")}');
    _send(SyncFrame({'t': SyncMsg.want, 'paths': want}));
  }

  /// One beat: give up on a peer that has stopped answering, and write
  /// something either way.
  ///
  /// THE WRITE IS THE TEST. A half-open socket — the shape a Wi-Fi change, a
  /// sleep or a dropped NAT entry leaves behind — is indistinguishable from a
  /// quiet one until something is sent down it, and this app can go minutes
  /// without a document to send. Eight seconds of a twelve-byte frame is what
  /// turns "connected" back into a fact.
  void _tick() {
    if (!live) return;
    if (_peerAnswers && DateTime.now().difference(_heard) > _beatDeadline) {
      close('silent for ${_beatDeadline.inSeconds}s');
      return;
    }
    _send(SyncFrame({'t': SyncMsg.ping}));
  }

  /// Ask now rather than at the next beat — used on resume, where the whole
  /// question is whether the connections survived being suspended.
  void pingNow() {
    if (live) _send(SyncFrame({'t': SyncMsg.ping}));
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
    final sha = sha256.convert(bytes).toString();
    _send(SyncFrame({
      't': SyncMsg.file,
      'e': SyncEntry(path, st.size, st.modified.millisecondsSinceEpoch, sha)
          .toJson(),
    }, bytes));
    // M417 — HANDING IT OVER IS AGREEING ON IT. The other half of the base
    // version: a file this device has published is one the group holds, so the
    // NEXT edit here is a change on top of a known version rather than an
    // unexplained difference that would be kept twice.
    _sync._noteHandedOver(path, sha);
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
    _beat?.cancel();
    _deadline?.cancel();
    _beat = _deadline = null;
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

/// Whether this device should open the connection to [peerId].
///
/// The lower id dials, so that two devices which can both see each other open
/// one connection rather than two — and after [grace] the rule is dropped, so
/// that two devices where only ONE can see the other still pair. See
/// [LanSync._maybeDial] for why that second case is the normal one between an
/// iPad and a PC rather than an exotic one.
///
/// A free function because it is pure — two ids and a duration in, a decision
/// out — and because the decision is the part that was wrong.
bool shouldDial({
  required String myId,
  required String peerId,
  required Duration seenFor,
  Duration grace = LanSync.dialGrace,
}) {
  if (myId.compareTo(peerId) < 0) return true;
  if (myId == peerId) return false; // ourselves, heard through a mirror
  return seenFor >= grace;
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
