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

  /// M423 — THE SENDER'S OWN BASE VERSION for this path, when it is telling.
  ///
  /// Only ever set on an entry that is travelling: this device fills it in
  /// from [LanSync._base] on the way out and reads the peer's out of the
  /// wire. It is what lets the two sides notice that they do not even AGREE
  /// on what they last agreed on — see [LanSync.verdictFor], where a base
  /// that differs from ours is the difference between a divergence and a
  /// mirror that swaps two versions back and forth for ever.
  ///
  /// Null from a peer too old to send it, and on every entry this device
  /// merely holds. Both fall back to the rule as it was.
  final String? base;

  const SyncEntry(this.path, this.size, this.mtimeMs, this.sha, {this.base});

  /// The same entry as it goes out to a peer, carrying [b].
  SyncEntry withBase(String? b) => SyncEntry(path, size, mtimeMs, sha, base: b);

  Map<String, Object?> toJson() => {
        'p': path,
        's': size,
        'm': mtimeMs,
        'h': sha,
        if (base != null) 'b': base,
      };

  static SyncEntry? fromJson(Object? o) {
    if (o is! Map) return null;
    final p = o['p'];
    final h = o['h'];
    if (p is! String || p.isEmpty || h is! String) return null;
    final b = o['b'];
    return SyncEntry(p, (o['s'] as num?)?.toInt() ?? 0,
        (o['m'] as num?)?.toInt() ?? 0, h,
        base: b is String && b.isNotEmpty ? b : null);
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

/// A copy of a document taken before the mirror overwrote or removed it.
@immutable
class SyncBackup {
  /// The document's mirror path, e.g. `Bracket.ptp`.
  final String path;

  /// When the copy was taken.
  final DateTime at;

  /// Why: `replaced` (a peer's version arrived), `removed` (deleted on another
  /// device) or `discarded` (this device gave up its own changes).
  final String reason;

  /// The file holding the bytes.
  final File file;

  const SyncBackup(this.path, this.at, this.reason, this.file);

  /// `Bracket.ptp` -> `Bracket`, for anything that shows this to a person.
  String get documentName {
    final dot = path.lastIndexOf('.');
    return dot <= 0 ? path : path.substring(0, dot);
  }
}

/// How a "sync now" went, in the terms the person who pressed it thinks in.
enum SyncRefreshOutcome {
  /// Sharing is switched off on this device. Nothing was attempted.
  off,

  /// No other device answered.
  alone,

  /// Everything already matched.
  upToDate,

  /// Documents arrived or were replaced.
  updated,

  /// At least one document had been changed in two places and both copies
  /// were kept. Outranks [updated]: it is the thing worth reading.
  kept,

  /// The mirror could not be brought up at all.
  failed,
}

/// What a refresh did, for the one line the gallery shows afterwards.
///
/// M418 — A REFRESH THAT APPEARS TO DO NOTHING is why people press a button
/// five times, so this always carries enough to say something true and
/// specific. "Up to date" is a result; silence is not.
@immutable
class SyncRefreshResult {
  final SyncRefreshOutcome outcome;

  /// Documents that arrived or were replaced. Preferences are not counted —
  /// nobody presses refresh for a tick box.
  final int documents;

  /// Divergences resolved during this refresh, if any.
  final List<SyncFork> forks;

  /// Devices that answered.
  final int peers;

  final String? detail;

  const SyncRefreshResult(
    this.outcome, {
    this.documents = 0,
    this.forks = const <SyncFork>[],
    this.peers = 0,
    this.detail,
  });
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

  /// M423 — ONE PEER THIS DEVICE DIALS BY ADDRESS instead of finding.
  ///
  /// Discovery is a broadcast and an mDNS query, and both stop at the edge of
  /// the network: two devices that cannot hear each other never pair, however
  /// well they could talk if they were introduced. That is every pair on
  /// different networks — the iPad on a phone connection, the PC at home —
  /// and until now the answer was "it is a LAN mirror, that is not what it
  /// does".
  ///
  /// It is what it does now, and the whole of the change is this address: put
  /// both devices on one overlay network (Tailscale, ZeroTier, a VPN, a port
  /// forward if you must), type the other one's address here, and the mirror
  /// runs over that instead. Nothing else moves — the same handshake, the
  /// same frames, the same conflict rule. WHAT THE OVERLAY ADDS is the part
  /// [lan_sync.dart]'s header comment says this does not have: on Tailscale
  /// or any WireGuard tunnel the bytes are encrypted end to end, which is the
  /// difference between "use it on a network you trust" and "use it".
  ///
  /// Deliberately ONE address and not a list. The case is "my other device",
  /// and a list is a management screen for a feature whose whole job is to be
  /// a way in when discovery cannot find the one device you own.
  String? _manualPeer;

  /// The connection to [_manualPeer], live or still being made.
  _SyncSession? _manualSlot;

  /// The earliest moment the address may be dialled again.
  DateTime? _manualNext;

  /// False once a dial has failed, so an address that is simply not answering
  /// yet says so once rather than every quarter of a minute for an hour.
  bool _manualQuiet = false;

  /// Content hashes, by mirror path, trusted only while the file's size and
  /// modification time are what they were when it was hashed. See [_entryFor]
  /// — this is what makes a one-second poll cost a `stat` per document
  /// instead of a full read and a SHA-256 of the whole gallery.
  final Map<String, SyncEntry> _hashes = <String, SyncEntry>{};

  /// The manifest as of the last scan, so a change can be spotted by
  /// comparison on the platforms with no usable file watcher.
  Map<String, SyncEntry> _mine = <String, SyncEntry>{};

  /// What has been deleted, by path: the moment it happened AND the version
  /// that went.
  ///
  /// Kept in a small journal beside the preferences rather than in memory
  /// only: a device that is switched off while another one deletes something
  /// must still learn about it, and a device that deletes something and is
  /// then restarted must still be able to TELL anyone. Both of those are the
  /// normal case rather than an edge one.
  ///
  /// M425 — THE WHOLE TOMBSTONE, not just its timestamp, and that was issue
  /// #47. This used to be `Map<String, int>`: the sha M417 added — the version
  /// that was thrown away, the thing that lets a peer answer "have I got
  /// anything to lose?" — was carried on the wire, used once, and then dropped
  /// on the floor by whoever stored it. Every re-announcement after that went
  /// out bare, and a bare tombstone falls back to guesswork.
  Map<String, SyncTomb> _tombs = <String, SyncTomb>{};

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

  /// M423 — VERSIONS THIS DEVICE HAS ALREADY REPLACED, by path, with the
  /// moment it replaced them.
  ///
  /// The net under [verdictFor], and it catches the case the base version
  /// cannot: a peer too old to send its own base, or any other route into the
  /// same shape. Two devices that apply each other's version at the same
  /// moment end up HOLDING EACH OTHER'S — and from there the three-sha rule
  /// reads each side as "only they moved on", so they swap, and swap back,
  /// for as long as both are running. That is issue #45: the same two
  /// versions of one document, alternating every few seconds, with the person
  /// looking at whichever one lost the last round.
  ///
  /// A version this device has just thrown away is not news coming back. It
  /// is this device's own past, and taking it again is how the swap keeps its
  /// rhythm. Kept in memory only, briefly, and per path — long enough to
  /// break the loop, short enough that somebody deliberately restoring an old
  /// version an hour later is not argued with.
  final Map<String, Map<String, DateTime>> _superseded =
      <String, Map<String, DateTime>>{};

  /// Paths a crossing has already been reported for, so the log says it once
  /// per document rather than on every manifest that repeats it.
  final Set<String> _crossingLogged = <String>{};

  /// Divergences resolved since the app last cleared them, for the gallery to
  /// tell the user about. Newest last.
  final ValueNotifier<List<SyncFork>> recentForks =
      ValueNotifier<List<SyncFork>>(const <SyncFork>[]);

  /// Paths written by something other than a peer's file message — the second
  /// copy [_fork] keeps — waiting to be folded into the next [_applied] call
  /// so the gallery hears about them like anything else that landed.
  final Set<String> _extraApplied = <String>{};

  /// Non-null while [refresh] is running: what has landed since it started.
  Set<String>? _refreshApplied;

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
      _noticeResurrections(_mine);
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
      _manualNext = null;
      _dialManual();
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
    _manualSlot?.close('sharing off');
    _manualSlot = null;
    _manualNext = null;
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

  /// The address this device dials by hand, or null. See [_manualPeer].
  String? get manualPeer => _manualPeer;

  /// Sets (or clears) that address and acts on it now.
  Future<void> setManualPeer(String? address) async {
    final next =
        (address == null || address.trim().isEmpty) ? null : address.trim();
    if (next == _manualPeer) return;
    _manualPeer = next;
    _manualNext = null;
    _manualQuiet = false;
    final slot = _manualSlot;
    _manualSlot = null;
    slot?.close('the address changed');
    if (next != null) {
      Log.i('sync', 'dialling $next by address');
      _dialManual();
    }
    _publish();
  }

  /// Dials [_manualPeer] if it is time to. Called from every sweep.
  ///
  /// RETRIED FOR EVER, gently. The address names a device that may be asleep,
  /// off, or on a tunnel that has not come up yet, and the one thing this
  /// must not do is give up before the person does — "it worked yesterday" is
  /// the whole reason to type an address rather than rely on discovery.
  void _dialManual() {
    final address = _manualPeer;
    if (address == null || _code == null) return;
    final slot = _manualSlot;
    // Connected, or connecting and not yet written off.
    if (slot != null && (slot.live || !slot.stale)) return;
    final next = _manualNext;
    if (next != null && DateTime.now().isBefore(next)) return;
    _manualNext = DateTime.now().add(_manualRetry);
    final target = parseSyncAddress(address);
    if (target == null) {
      if (!_manualQuiet) {
        _manualQuiet = true;
        Log.w('sync', '"$address" is not an address this can dial');
      }
      return;
    }
    if (slot != null) {
      _manualSlot = null;
      slot.close('the handshake never finished');
    }
    unawaited(_dialAddress(target));
  }

  Future<void> _dialAddress(SyncAddress target) async {
    // The slot is claimed BEFORE the await for the same reason [_dial] claims
    // one: a sweep two seconds later must not start a second connection to a
    // machine that is simply slow to answer.
    final pending = _SyncSession.pending(null);
    _manualSlot = pending;
    try {
      final sock = await Socket.connect(target.host, target.port,
          timeout: _dialTimeout);
      if (!identical(_manualSlot, pending)) {
        sock.destroy(); // the address changed while this was connecting
        return;
      }
      final s = _SyncSession(this, sock, outgoing: true);
      _manualSlot = s;
      _manualQuiet = false;
      s.start();
    } catch (e) {
      if (identical(_manualSlot, pending)) _manualSlot = null;
      if (!_manualQuiet) {
        _manualQuiet = true;
        Log.w('sync', 'could not reach ${target.host}:${target.port}: $e');
      }
    }
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
    _dialManual();
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

  /// How often the hand-typed address is dialled again while it is not
  /// answering. Longer than a sweep: it is usually a machine on the other
  /// side of a tunnel, and there is no beacon to say when it wakes up.
  static const Duration _manualRetry = Duration(seconds: 15);

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
    if (identical(_manualSlot, s)) {
      // Whatever ended it — the peer hung up, the tunnel dropped, [_adopt]
      // kept the other side's connection instead — the address is free to be
      // dialled again, after a pause rather than on the next sweep.
      _manualSlot = null;
      _manualNext = DateTime.now().add(_manualRetry);
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
    // Coming back to the foreground is exactly when a tunnel has just come up
    // again, so the address gets its try now rather than at the next sweep.
    _manualNext = null;
    _dialManual();
    nudge();
    _publish();
  }

  /// SYNC NOW — everything [resume] does, plus asking every paired device for
  /// its list and waiting for the answer, and then saying what happened.
  ///
  /// M418 — the refresh button, and the drag-down on a touch screen. The
  /// mirror is continuous, so this is not what makes sync work; it is what
  /// makes it ANSWERABLE. "Did it sync?" had no way of being asked, and a
  /// person who cannot ask it does not trust the thing — which is most of what
  /// "the syncing is dangerous" was about.
  ///
  /// The manifest request is a header flag on the message both sides already
  /// exchange when they pair, not a new message type: a peer too old to
  /// understand it ignores an unknown key and the refresh degrades to what
  /// [resume] always did, rather than failing.
  Future<SyncRefreshResult> refresh(
      {Duration settle = const Duration(seconds: 3)}) async {
    if (_code == null) return const SyncRefreshResult(SyncRefreshOutcome.off);
    final forksBefore = recentForks.value.length;
    final landed = _refreshApplied = <String>{};
    try {
      if (_server == null || (_beacon == null && !_bonjour.running)) {
        Log.i('sync', 'refresh: the listener is not up — restarting it');
        final gen = ++_codeGen;
        await _stop();
        if (gen != _codeGen) {
          return const SyncRefreshResult(SyncRefreshOutcome.off);
        }
        await _start();
      }
      await _refreshInterfaces();
      _sendBeacon();
      await _startBonjour();
      for (final s in _sessions.values) {
        if (s.live) s.pingNow();
      }
      // Ours goes out first: a refresh is as much "take what I have" as it is
      // "give me what you have", and a peer that hears about our saves in the
      // same breath answers both in one round trip.
      _announceChanges();
      var asked = _requestManifests();
      if (asked == 0) {
        // Nobody paired YET. The beacon has just gone out, so give the
        // handshake the time it needs before concluding this device is alone.
        await Future<void>.delayed(const Duration(milliseconds: 900));
        asked = _requestManifests();
      }
      if (asked == 0) return const SyncRefreshResult(SyncRefreshOutcome.alone);
      // Wait for the exchange to go quiet rather than for a fixed time: a
      // first pair-up can be thirty documents and a routine check is none.
      final deadline = DateTime.now().add(settle);
      var seen = landed.length;
      var quiet = 0;
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
        if (landed.length != seen) {
          seen = landed.length;
          quiet = 0;
        } else if (++quiet >= 4) {
          break; // six hundred milliseconds with nothing arriving
        }
      }
      final forks = recentForks.value.length > forksBefore
          ? recentForks.value.sublist(forksBefore)
          : const <SyncFork>[];
      final docs =
          landed.where((p) => !p.startsWith(_prefsPrefix)).toSet().length;
      if (forks.isNotEmpty) {
        return SyncRefreshResult(SyncRefreshOutcome.kept,
            documents: docs, forks: forks, peers: asked);
      }
      if (docs > 0) {
        return SyncRefreshResult(SyncRefreshOutcome.updated,
            documents: docs, peers: asked);
      }
      return SyncRefreshResult(SyncRefreshOutcome.upToDate, peers: asked);
    } catch (e) {
      Log.w('sync', 'refresh failed: $e');
      return SyncRefreshResult(SyncRefreshOutcome.failed, detail: '$e');
    } finally {
      _refreshApplied = null;
      _publish();
    }
  }

  /// Documents this device has changed since it and the group last agreed —
  /// the ones "discard my changes" would actually undo.
  ///
  /// M420 — a document with no agreed version behind it is NOT in this list.
  /// It has never been anywhere else, so there is nothing to go back TO, and
  /// offering to discard it would be offering to delete it.
  List<String> get divergentDocuments {
    final out = <String>[];
    for (final e in _mine.entries) {
      if (e.key.startsWith(_prefsPrefix)) continue;
      final base = _base[e.key];
      if (base != null && base != e.value.sha) out.add(e.key);
    }
    out.sort();
    return out;
  }

  /// True when [path] is one of them.
  bool hasLocalChanges(String path) {
    final mine = _mine[path];
    if (mine == null || path.startsWith(_prefsPrefix)) return false;
    final base = _base[path];
    return base != null && base != mine.sha;
  }

  /// GIVE UP THIS DEVICE'S CHANGES to [paths] and take the group's versions.
  ///
  /// M420 — "I want a clear all changes button but also when I longpress a
  /// menu item a clear changes button only for this item" (#43).
  ///
  /// The recovery hatch, and the only destructive thing in the whole mirror
  /// that the user asks for on purpose. Three rules make it safe enough to put
  /// in front of a beginner:
  ///
  ///   * IT REFUSES WHEN THERE IS NOTHING TO GO BACK TO. No peer connected
  ///     means the replacement cannot be fetched, and deleting somebody's work
  ///     in exchange for nothing is the one outcome this must never have. The
  ///     caller shows "your other devices aren't reachable" and nothing
  ///     happens.
  ///   * The previous bytes are BACKED UP first (M421), so even the asked-for
  ///     destruction is undoable.
  ///   * It only ever touches a document with an agreed version behind it: one
  ///     that has never left this device has nothing to be discarded in favour
  ///     of, and dropping it would be a delete wearing another name.
  ///
  /// Returns the paths actually given up. The bytes arrive afterwards, through
  /// the ordinary manifest exchange: forgetting our version and asking is all
  /// this has to do, and doing it that way means the arrival path is the one
  /// that is already tested.
  Future<List<String>> discardLocalChanges(List<String> paths) async {
    if (_code == null && !_pretendLiveForTest) return const <String>[];
    if (!_pretendLiveForTest && !_sessions.values.any((s) => s.live)) {
      Log.w('sync', 'discard refused: no other device is reachable');
      return const <String>[];
    }
    final done = <String>[];
    for (final path in paths) {
      if (!hasLocalChanges(path)) continue;
      final f = _fileFor(path);
      if (f == null || !f.existsSync()) continue;
      if (!backup(path, 'discarded')) {
        Log.w('sync', 'discard skipped $path — it could not be backed up');
        continue;
      }
      // Forget that we hold anything at this path. The peer's version then
      // reads as "nothing here to lose" and arrives through the ordinary
      // route, rather than through a second write path nobody else exercises.
      try {
        f.deleteSync();
      } catch (e) {
        Log.w('sync', 'could not put $path back: $e');
        continue;
      }
      _mine.remove(path);
      _hashes.remove(path);
      _justApplied.remove(path);
      // NOT a deletion: no tombstone is written, and the base is dropped so
      // the copy coming back is taken rather than refused as one we threw
      // away on purpose.
      _base.remove(path);
      done.add(path);
    }
    if (done.isEmpty) return done;
    _saveBase();
    Log.i('sync', 'gave up local changes to ${done.join(", ")}');
    // Ask for them back. The manifest request is the same one the refresh
    // button sends.
    if (!_pretendLiveForTest) _requestManifests();
    _applied(done.toSet());
    return done;
  }

  /// Asks every paired device for its list. Returns how many were asked.
  int _requestManifests() {
    var n = 0;
    for (final s in _sessions.values) {
      if (!s.live) continue;
      s.requestManifest();
      n++;
    }
    return n;
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
    _noticeResurrections(now);
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

  /// M425 — A DOCUMENT THAT EXISTS AGAIN IS NOT A DELETED DOCUMENT.
  ///
  /// The other half of issue #47, and the half that starts it. A tombstone was
  /// only ever dropped when a file came back FROM A PEER ([_apply]); a file
  /// created here, at a path this device remembers deleting, left the record
  /// standing. So the device holding the new document went on telling the
  /// whole group, in every manifest, that the document at that path is
  /// deleted — and the group believed it, because a tombstone is a fact with
  /// a time on it and nothing about it says "this is about some other file
  /// that happened to have the same name".
  ///
  /// WHICH IS NOT AN EXOTIC CASE. New documents are named `Part1`, `Part2`,
  /// … by counting the ones that exist, so the name of a deleted document is
  /// the first one handed out again. Delete `Part1`, make a new document, and
  /// it is called `Part1` — carrying a month-old death certificate.
  void _noticeResurrections(Map<String, SyncEntry> now) {
    if (_tombs.isEmpty) return;
    var changed = false;
    for (final path in now.keys) {
      final was = _tombs.remove(path);
      if (was == null) continue;
      changed = true;
      Log.i('sync', '$path is here again — forgetting that it was deleted');
    }
    if (changed) _saveTombs();
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
      final was = _mine[path];
      // The version that went, kept for [verdictFor] and sent with the
      // tombstone so the other devices can answer the same question.
      if (was != null) _setBase(path, was.sha);
      final tomb = SyncTomb(path, at, was?.sha);
      _tombs[path] = tomb;
      out.add(tomb);
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
  /// M423 adds the two the rule above could not see either, because they are
  /// about B ITSELF rather than about L and R:
  ///
  ///   their B != my B         we never agreed on anything   -> fork
  ///   no their B, R is one I replaced minutes ago           -> fork
  ///
  /// Both are the same situation reached by two roads — two devices that have
  /// swapped versions rather than converged on one — and forking is what ends
  /// it. See m423_sync_crossing_test.dart for the report that named it.
  ///
  /// The fork cases are the ones the pre-M417 rule could not see. It compared
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
      // The version we deleted is exactly the one being offered back. The
      // tombstone's own sha answers that where there is one (M425); the base
      // is the fallback for a record written before the journal kept it.
      if ((tomb.sha ?? _base[remote.path]) == remote.sha) {
        return SyncVerdict.skip;
      }
      // Something else: it was edited elsewhere after the delete travelled,
      // and an edit outlives a deletion (see [_applyTomb]).
      return SyncVerdict.take;
    }
    if (mine == null) return SyncVerdict.take;
    // Identical bytes are an agreement whatever either side thinks it last
    // agreed on, and this line is what heals the disagreement below: the pair
    // that has just been forked holds the same winner a moment later, and
    // [_noteAgreement] then writes the same base on both devices.
    if (mine.sha == remote.sha) return SyncVerdict.skip;
    final base = _base[remote.path];
    // M423 — DO THE TWO DEVICES EVEN MEAN THE SAME THING BY "the version we
    // last agreed on"? Everything below this point assumes they do: the whole
    // three-sha rule is read against ONE base, and "only they moved on" is
    // only true if their B and mine are the same bytes.
    //
    // They come apart when both devices apply each other's version at the
    // same moment — a first pair-up where each side asks before either has
    // answered, which is precisely the shape of a manifest exchange. Each
    // ends up holding what the other had, and each writes THAT down as the
    // agreed version. From then on both read the other's offer as news, both
    // take it, and the same two versions cross the room every few seconds
    // until somebody closes the app. Nothing is corrupted and nothing is
    // ever settled; the person just sees the old one about half the time.
    //
    // Two bases that disagree are two devices that never agreed. That is the
    // definition of a divergence, and the mirror already knows what to do
    // with one — keep both, deterministically, so both sides land on the same
    // two files and it is OVER.
    final theirBase = remote.base;
    if (base != null && theirBase != null && theirBase != base) {
      _noteCrossing(remote.path, 'the base versions do not match');
      return SyncVerdict.fork;
    }
    // The same conclusion from this side alone, and ONLY for a peer too old
    // to say what its base is: bytes this device replaced minutes ago are not
    // an edit arriving, they are its own past coming back.
    //
    // Narrowed to that peer on purpose. Where the base IS on the wire the
    // rule above is exact, and this one is a guess that would be wrong in one
    // real case: somebody who undoes back to a version byte for byte and
    // saves it. A modern peer says "my base is still the newer one", which
    // reads correctly as an edit; only a peer that can say nothing needs to
    // be second-guessed.
    if (theirBase == null && _supersededRecently(remote.path, remote.sha)) {
      _noteCrossing(remote.path, 'this version was already replaced here');
      return SyncVerdict.fork;
    }
    if (base == null) return SyncVerdict.fork;
    if (mine.sha == base) return SyncVerdict.take;
    if (remote.sha == base) return SyncVerdict.skip;
    return SyncVerdict.fork;
  }

  /// M423 — remembers that [sha] was this device's copy of [path] until now.
  void _noteSuperseded(String path, String sha) {
    final seen = _superseded.putIfAbsent(path, () => <String, DateTime>{});
    seen[sha] = DateTime.now();
    while (seen.length > _supersededKeep) {
      var oldest = seen.entries.first;
      for (final e in seen.entries) {
        if (e.value.isBefore(oldest.value)) oldest = e;
      }
      seen.remove(oldest.key);
    }
  }

  /// Whether [sha] is a version of [path] this device threw away recently.
  bool _supersededRecently(String path, String sha) {
    final seen = _superseded[path];
    final at = seen?[sha];
    if (at == null) return false;
    if (DateTime.now().difference(at) > _supersededFor) {
      seen!.remove(sha);
      return false;
    }
    return true;
  }

  /// Says once, per document, that the two devices had come apart — the line
  /// a report like #45 needs in order to be diagnosed from the log alone.
  void _noteCrossing(String path, String why) {
    if (!_crossingLogged.add(path)) return;
    Log.i('sync', '$path changed on two devices at once ($why) — keeping both');
  }

  /// How long a replaced version stays remembered. Long enough to outlast the
  /// swap it is there to break, short enough not to argue with a person who
  /// puts an old version back on purpose.
  static const Duration _supersededFor = Duration(minutes: 5);

  /// How many replaced versions are remembered per document.
  static const int _supersededKeep = 4;

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
    // M421 — the version about to be replaced, kept for a month. This is the
    // case M417 reasons about correctly and can still be WRONG about: the
    // rules said this device was simply behind, and the rules do not know
    // that the person wanted what was here.
    backup(e.path, 'replaced');
    // M423 — what this device is about to stop holding. See [_superseded]:
    // the same bytes coming back later are its own past, not a peer's edit.
    final replaced = _mine[e.path];
    if (replaced != null) _noteSuperseded(e.path, replaced.sha);
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
      // The copy is a new document nobody asked for and everybody has to see:
      // the session only reports the path the peer NAMED, so this one has to
      // let itself be known.
      _extraApplied.add(copyPath);
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
    if (_extraApplied.isNotEmpty) {
      paths = <String>{...paths, ..._extraApplied};
      _extraApplied.clear();
    }
    if (paths.isEmpty) return;
    _refreshApplied?.addAll(paths);
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
    if (mine == null || mine.sha != remote.sha) return;
    _setBase(remote.path, remote.sha);
    // Whatever the two devices had come apart over, they are back together on
    // this document. A next time is news again.
    _crossingLogged.remove(remote.path);
  }

  /// M423 — an entry as it goes OUT, carrying this device's base version for
  /// it. See [SyncEntry.base] and [verdictFor].
  SyncEntry _outgoing(SyncEntry e) => e.withBase(_base[e.path]);

  /// This device's whole manifest, as it goes on the wire.
  List<Map<String, Object?>> _manifestJson() =>
      [for (final e in _scanLocal().values) _outgoing(e).toJson()];

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

  /// Reads the journal, in either shape it has ever had.
  ///
  /// A BARE NUMBER IS THE OLD SHAPE — `{"Bracket.ptp": 1757500000000}` — and
  /// it is read as a tombstone with no sha, which is exactly what it is: a
  /// record written before the journal kept one. It then heals itself, since
  /// [_applyTomb] fills the sha in from what it actually removed.
  void _loadTombs() {
    _tombs = <String, SyncTomb>{};
    final f = _tombPath;
    if (f == null || !f.existsSync()) return;
    try {
      final raw = jsonDecode(f.readAsStringSync());
      if (raw is! Map) return;
      for (final e in raw.entries) {
        final path = '${e.key}';
        final v = e.value;
        if (v is num) {
          _tombs[path] = SyncTomb(path, v.toInt());
          continue;
        }
        if (v is! Map) continue;
        final d = (v['d'] as num?)?.toInt();
        if (d == null) continue;
        final h = v['h'];
        _tombs[path] =
            SyncTomb(path, d, h is String && h.isNotEmpty ? h : null);
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
      tmp.writeAsStringSync(
          jsonEncode(<String, Object?>{
            for (final e in _tombs.entries)
              e.key: <String, Object?>{
                'd': e.value.deletedAtMs,
                if (e.value.sha != null) 'h': e.value.sha,
              }
          }),
          flush: true);
      tmp.renameSync(f.path);
    } catch (e) {
      Log.w('sync', 'could not write the delete journal: $e');
    }
  }

  void _expireTombs() {
    final cutoff =
        DateTime.now().subtract(_tombLife).millisecondsSinceEpoch;
    _tombs.removeWhere((_, t) => t.deletedAtMs < cutoff);
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
    if (known != null && known.deletedAtMs >= t.deletedAtMs) return false;
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
    // M425 — RECORDED WITH A SHA IF THERE IS ONE TO BE HAD, because this
    // record is what this device will announce to everyone else from now on.
    // A peer too old to send one still told us which file; what it threw away
    // is what we are about to throw away, so that is the version to write
    // down rather than passing the gap on.
    _tombs[t.path] =
        t.sha != null ? t : SyncTomb(t.path, t.deletedAtMs, mine?.sha);
    _saveTombs();
    final f = _fileFor(t.path);
    var removed = false;
    if (f != null && f.existsSync()) {
      try {
        // M421 — a delete is the one operation whose failure mode is losing
        // work everywhere at once, so the copy comes first.
        backup(t.path, 'removed');
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
  // Backups (M421)
  // -------------------------------------------------------------------------

  /// Where a copy is kept of everything the mirror was about to destroy.
  ///
  /// M421 — THE THING THAT MAKES THE REST SAFE TO OFFER. M417 stops the mirror
  /// losing work by accident; this is what covers the cases it cannot reason
  /// about — a delete that was correct by the rules and wrong by the user, a
  /// version taken from a peer that turned out to be the wrong one, and above
  /// all "discard my changes", which is destruction the person ASKED for and
  /// may still regret ten seconds later.
  ///
  /// Under the preferences directory rather than beside the documents: the
  /// gallery lists what is in the documents folder, and a drawer of old
  /// versions is not a drawer of documents. Never mirrored, for the same
  /// reason the journals are not — it is this device's undo history, not a
  /// shared fact.
  static const String _backupDir = 'sync-backup';

  /// Long enough to cover "I noticed on Monday", short enough not to grow
  /// without bound. The same month the tombstones get.
  static const Duration _backupLife = Duration(days: 30);

  Directory? get _backupRoot {
    final prefs = _prefs;
    return prefs == null ? null : Directory('${prefs.path}/$_backupDir');
  }

  /// Copies what is at [path] now into the backup drawer. True when there is
  /// a copy afterwards — including when there was nothing to copy, because a
  /// caller's question is "is it safe to go ahead", and it is.
  bool backup(String path, String reason) {
    final f = _fileFor(path);
    final dir = _backupRoot;
    if (f == null || dir == null) return false;
    if (!f.existsSync()) return true;
    try {
      dir.createSync(recursive: true);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final safe = path.replaceAll(RegExp(r'[^A-Za-z0-9._ ()-]'), '_');
      f.copySync('${dir.path}/$stamp-$reason-$safe');
      _expireBackups();
      return true;
    } catch (e) {
      Log.w('sync', 'could not keep a copy of $path: $e');
      return false;
    }
  }

  /// Everything in the drawer, newest first.
  List<SyncBackup> backups() {
    final dir = _backupRoot;
    if (dir == null || !dir.existsSync()) return const <SyncBackup>[];
    final out = <SyncBackup>[];
    try {
      for (final e in dir.listSync(followLinks: false)) {
        if (e is! File) continue;
        final name = e.uri.pathSegments.last;
        final dash = name.indexOf('-');
        if (dash <= 0) continue;
        final ms = int.tryParse(name.substring(0, dash));
        if (ms == null) continue;
        final rest = name.substring(dash + 1);
        final dash2 = rest.indexOf('-');
        if (dash2 <= 0) continue;
        out.add(SyncBackup(
            rest.substring(dash2 + 1),
            DateTime.fromMillisecondsSinceEpoch(ms),
            rest.substring(0, dash2),
            e));
      }
    } catch (e) {
      Log.w('sync', 'could not read the backup drawer: $e');
    }
    out.sort((a, b) => b.at.compareTo(a.at));
    return out;
  }

  /// Puts a backed-up version back, as a new save.
  ///
  /// M421 — AND IT IS A SAVE, not a rewind. The group still holds the version
  /// that replaced this one and would simply send it again; restoring has to
  /// mean "this is what the document is now", which is what publishing it as
  /// the newest version does. Anything else looks to the user like an undo
  /// that undid itself a second later.
  bool restore(SyncBackup b) {
    final target = _fileFor(b.path);
    if (target == null) return false;
    try {
      final bytes = b.file.readAsBytesSync();
      // The version being replaced goes into the drawer too: an undo that
      // cannot itself be undone is a trap.
      backup(b.path, 'replaced');
      if (!_writeAtomic(target, bytes)) return false;
      _rememberOnDisk(
          b.path, target, sha256.convert(bytes).toString());
      // No base and no tombstone: this is a local save like any other, and the
      // next announcement carries it to the other devices as the winner.
      _base.remove(b.path);
      _saveBase();
      if (_tombs.remove(b.path) != null) _saveTombs();
      _justApplied.remove(b.path);
      Log.i('sync', 'restored ${b.path} from ${b.at}');
      nudge();
      _applied(<String>{b.path});
      return true;
    } catch (e) {
      Log.w('sync', 'could not restore ${b.path}: $e');
      return false;
    }
  }

  void _expireBackups() {
    final dir = _backupRoot;
    if (dir == null || !dir.existsSync()) return;
    final cutoff = DateTime.now().subtract(_backupLife);
    try {
      for (final e in dir.listSync(followLinks: false)) {
        if (e is! File) continue;
        if (e.statSync().modified.isBefore(cutoff)) e.deleteSync();
      }
    } catch (e) {
      Log.w('sync', 'could not tidy the backup drawer: $e');
    }
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
    // M425 — WITHOUT A SHA, THE BASE ALONE PROVES NOTHING, and believing it
    // did is the second half of issue #47. "I hold exactly the group's
    // version" is the ordinary state of every file that arrived from a peer
    // and has not been touched since — it says nothing about whether THIS
    // tombstone is about THAT version. A month-old record of a deleted
    // `Part1.ptp`, re-announced bare, therefore read as permission to delete
    // a `Part1.ptp` created yesterday and synced an hour ago.
    //
    // So a sha-less tombstone has to clear both bars: the version here must be
    // the one the group agreed on AND older than the deletion it is being
    // measured against. A document saved after the delete keeps itself, which
    // is the rule the timestamp heuristic was always meant to express.
    final base = _base[t.path];
    if (base != null && mine.sha != base) return false;
    return mine.mtimeMs <= t.deletedAtMs + 1000;
  }

  /// The tombstones worth sending: everything still inside [_tombLife].
  ///
  /// M425 — SENT WHOLE. Rebuilding them here as `SyncTomb(path, time)` is
  /// what threw the sha away on every hop after the first, which left every
  /// device but the one that did the deleting announcing a fact nobody could
  /// check.
  List<SyncTomb> get _tombList {
    _expireTombs();
    return _tombs.values.toList(growable: false);
  }

  @visibleForTesting
  Map<String, SyncTomb> get tombsForTest => _tombs;

  /// What this device would ANNOUNCE — which is the thing #47 was about, and
  /// not the same list as the one [noticeDeletesForTest] returns.
  @visibleForTesting
  List<SyncTomb> tombListForTest() => _tombList;

  @visibleForTesting
  void noticeResurrectionsForTest() => _noticeResurrections(_scanLocal());

  @visibleForTesting
  bool applyTombForTest(SyncTomb t) => _applyTomb(t);

  @visibleForTesting
  List<SyncTomb> noticeDeletesForTest() => _noticeDeletes(_scanLocal());

  @visibleForTesting
  Map<String, SyncEntry> get localManifestForTest => _mine;

  @visibleForTesting
  Map<String, SyncEntry> scanForTest() => _scanLocal();

  @visibleForTesting
  List<Map<String, Object?>> manifestJsonForTest() => _manifestJson();

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
  Future<List<String>> discardForTest(List<String> paths,
      {required bool pretendPeer}) async {
    _pretendLiveForTest = pretendPeer;
    try {
      return await discardLocalChanges(paths);
    } finally {
      _pretendLiveForTest = false;
    }
  }

  /// Stands in for "a device is reachable" in a host test, where there are no
  /// sockets. Nothing else reads it.
  bool _pretendLiveForTest = false;

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
    _superseded.clear();
    _crossingLogged.clear();
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
      'files': _sync._manifestJson(),
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
    // Answer a REQUEST with our own list — and without the flag, or the two
    // devices would answer each other forever.
    if (f.header['reply'] == true) {
      _send(SyncFrame({
        't': SyncMsg.manifest,
        'files': _sync._manifestJson(),
        'tombs': [for (final t in _sync._tombList) t.toJson()],
      }));
    }
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

  /// "Here is my list — send me yours." The `reply` flag is what makes this a
  /// REQUEST rather than the announcement the same message usually is; a peer
  /// too old to know the key ignores it, which costs this device the answer
  /// and nothing else.
  void requestManifest() {
    _send(SyncFrame({
      't': SyncMsg.manifest,
      'files': _sync._manifestJson(),
      'tombs': [for (final t in _sync._tombList) t.toJson()],
      'reply': true,
    }));
  }

  void announce(List<SyncEntry> changed, [List<SyncTomb> gone = const []]) {
    _send(SyncFrame({
      't': SyncMsg.changed,
      'files': [for (final e in changed) _sync._outgoing(e).toJson()],
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
    // The BASE travels with the bytes as well as with the manifest: [_apply]
    // asks [verdictFor] a second time, at the moment of the write, and it has
    // to be able to reach the same answer it reached when the manifest
    // arrived. Without it that second look would see no crossing and take a
    // file the first look had decided to keep both of.
    _send(SyncFrame({
      't': SyncMsg.file,
      'e': _sync
          ._outgoing(
              SyncEntry(path, st.size, st.modified.millisecondsSinceEpoch, sha))
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

/// M423 — a host and a port, as typed by a person. See [LanSync.manualPeer].
@immutable
class SyncAddress {
  final String host;
  final int port;

  const SyncAddress(this.host, this.port);

  @override
  String toString() => host.contains(':') ? '[$host]:$port' : '$host:$port';
}

/// Reads an address a person typed, or null when it is not one.
///
/// Accepts `100.64.0.2`, `100.64.0.2:47821`, `laptop.local`, a Tailscale name
/// like `tom-pc.tail1234.ts.net`, and IPv6 in the brackets it is written in:
/// `[fd7a:115c::1]:47821`. The port is [kSyncFirstDataPort] when it is left
/// off, which is what the other device is listening on unless a second copy
/// of the app is running there.
///
/// A FREE FUNCTION because it is the part with the edge cases and none of the
/// I/O — and because the settings prompt validates with it, so a typo is
/// refused where it was made rather than becoming an address that is dialled
/// for ever and never answers.
SyncAddress? parseSyncAddress(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  // Anything with whitespace or a path in it is a URL or a sentence, not an
  // address, and guessing at one is worse than saying so.
  if (s.contains(RegExp(r'[\s/\\?#@]'))) return null;
  if (s.startsWith('[')) {
    final end = s.indexOf(']');
    if (end <= 1) return null;
    final host = s.substring(1, end);
    final rest = s.substring(end + 1);
    if (rest.isEmpty) return SyncAddress(host, kSyncFirstDataPort);
    if (!rest.startsWith(':')) return null;
    final port = int.tryParse(rest.substring(1));
    if (port == null || port < 1 || port > 65535) return null;
    return SyncAddress(host, port);
  }
  final colon = s.indexOf(':');
  if (colon >= 0) {
    // More than one colon and no brackets: a bare IPv6 address, which cannot
    // carry a port without them.
    if (s.indexOf(':', colon + 1) >= 0) {
      return SyncAddress(s, kSyncFirstDataPort);
    }
    if (colon == 0) return null;
    final port = int.tryParse(s.substring(colon + 1));
    if (port == null || port < 1 || port > 65535) return null;
    return SyncAddress(s.substring(0, colon), port);
  }
  return SyncAddress(s, kSyncFirstDataPort);
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
