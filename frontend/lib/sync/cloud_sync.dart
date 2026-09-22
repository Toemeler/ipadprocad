// Prototype — the same mirror, through a bucket instead of a socket.
//
// WHAT THIS IS FOR. `lan_sync.dart`'s header is blunt about the one thing it
// cannot do: "It is NOT a cloud. There is no server, no account and nothing
// leaves the local network. Two devices that cannot see each other's
// broadcast — a guest network, a VPN, two different subnets — will not pair,
// and the status row says 'looking' forever rather than pretending." M423
// softened that with a typed-in address over an overlay network, which works
// and still needs BOTH DEVICES SWITCHED ON AT ONCE. The iPad edited on a train
// and the desktop opened that evening never overlap, so they never sync.
//
// A bucket removes the "at once". One device leaves its files somewhere; the
// other picks them up whenever it next runs. That is the whole of what this
// adds.
//
// WHAT IT IS NOT: A SECOND SYNC DESIGN. Not one rule about what wins lives in
// this file. Every decision — take, skip, keep both, honour a delete, take a
// backup first — is made by `LanSync.verdictFor` and the members around it,
// reached through the nine forwarders M441 added to that class. A cloud that
// reasoned about conflicts on its own would be a second implementation of the
// hardest part of this app, and the two would disagree on the day it mattered.
// This file decides only WHAT TO MOVE AND IN WHICH ORDER.
//
// HOW ONE CYCLE GOES
//
//   1. Ask LanSync what this device holds and what it remembers deleting.
//   2. Pull every device's manifest from the Worker (one request).
//   3. Apply peers' tombstones, then fetch and apply the entries this device
//      wants — each through `mirrorApply`, so a fork still forks.
//   4. Upload anything of ours the bucket does not have yet.
//   5. Publish our own manifest.
//
// THE ORDER OF 4 AND 5 IS THE ONE INVARIANT THIS FILE OWNS, and it is worth
// stating on its own because everything else rests on it:
//
//   A MANIFEST ONLY EVER NAMES BLOBS THAT ARE ALREADY UPLOADED.
//
// Publish first and a peer reads an entry, asks for bytes that are not there
// and — worse than failing — could conclude from a 404 that the document is
// gone. Upload first and the failure mode is a blob nobody references yet,
// which costs a few kilobytes until the next cycle names it. One of those is
// a data-loss report and the other is litter.
//
// BLOBS ARE CONTENT-ADDRESSED, keyed by the sha256 `SyncEntry` already
// carries. That falls out of the mirror rather than being imposed on it:
// `verdictFor` decides everything by comparing shas, so a blob named after its
// own hash makes an upload idempotent, a rename free, and two documents
// holding the same imported STEP file one object instead of two. It also
// means NO DOCUMENT NAME EVER REACHES THE BUCKET — the manifest holds the
// path-to-sha map, and the bucket sees hex.
//
// WHAT IS NOT ENCRYPTED, said plainly rather than implied away. The bucket is
// private and TLS covers the wire, but the bytes sit on Backblaze's disks in
// the clear, so this is on the same footing as keeping documents in Dropbox or
// Drive: a company can read them. That is a real step down from the LAN
// mirror, where nothing left the house. Closing it means encrypting before the
// upload in [_upload] and decrypting after the download in [_download] — two
// places — and a cipher, which is a dependency this app does not have yet
// (`crypto` hashes, it does not encrypt). Until then `cloud/README.md` says
// so and so does this. DO NOT put anything here you would mind Backblaze
// holding.
//
// AND THE SHARE CODE IS STILL 60 BITS. `share_code.dart` is explicit that it
// is "not a password and is not treated as one — a rendezvous token whose
// exposure is bounded by being on one local network". This removes that bound.
// The Worker's group prefix is an HMAC under a salt only it holds, so a code
// cannot be turned into a bucket path off-device, and CLOUD_SYNC_SECRET keeps
// casual traffic off the endpoint — but neither turns the code into a
// password. Anyone who learns your code can read your gallery.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../log.dart';
import 'lan_sync.dart';
import 'share_code.dart';

/// The Worker's address, baked in at build time via
/// `--dart-define=CLOUD_SYNC_URL=...`. Empty means no cloud at all: nothing is
/// started, nothing is sent, and the app behaves exactly as it did before this
/// file existed. That is deliberately the default in every build config.
const String cloudSyncUrl = String.fromEnvironment('CLOUD_SYNC_URL');

/// An abuse throttle the Worker checks, baked in via
/// `--dart-define=CLOUD_SYNC_SECRET=...`. NOT a credential — it ships inside
/// the app and is therefore public. See `relay/README.md` for why that
/// distinction holds for a throttle and would not for a token.
const String cloudSyncSecret = String.fromEnvironment('CLOUD_SYNC_SECRET');

/// Whether a cloud cycle will even be attempted.
bool get cloudSyncConfigured => cloudSyncUrl.isNotEmpty;

/// The manifest format's own version.
///
/// Bumped when a change would make an older app MISREAD a manifest rather than
/// merely miss a field — unknown keys are ignored on purpose, exactly as the
/// LAN protocol's headers are, so a newer device can add one without an older
/// one refusing the whole file.
const int kCloudManifestVersion = 1;

/// What one device published about itself.
@immutable
class CloudManifest {
  final String device;
  final String deviceName;
  final int atMs;
  final List<SyncEntry> entries;
  final List<SyncTomb> tombs;

  const CloudManifest({
    required this.device,
    required this.deviceName,
    required this.atMs,
    required this.entries,
    required this.tombs,
  });

  Map<String, Object?> toJson() => {
        'v': kCloudManifestVersion,
        'device': device,
        'name': deviceName,
        'at': atMs,
        'entries': [for (final e in entries) e.toJson()],
        'tombs': [for (final t in tombs) t.toJson()],
      };

  /// Null for anything that cannot be read as a manifest at all.
  ///
  /// A malformed entry inside an otherwise good manifest is DROPPED rather
  /// than failing the whole file: one unreadable record costs one document
  /// this cycle, and refusing the manifest costs every document that device
  /// holds. The same reasoning as [SyncEntry.fromJson] returning null per
  /// entry rather than throwing.
  static CloudManifest? fromJson(Object? o) {
    if (o is! Map) return null;
    final device = o['device'];
    if (device is! String || device.isEmpty) return null;
    final name = o['name'];
    final entries = <SyncEntry>[];
    final raw = o['entries'];
    if (raw is List) {
      for (final e in raw) {
        final parsed = SyncEntry.fromJson(e);
        if (parsed != null) entries.add(parsed);
      }
    }
    final tombs = <SyncTomb>[];
    final rawTombs = o['tombs'];
    if (rawTombs is List) {
      for (final t in rawTombs) {
        final parsed = SyncTomb.fromJson(t);
        if (parsed != null) tombs.add(parsed);
      }
    }
    return CloudManifest(
      device: device,
      deviceName: name is String && name.isNotEmpty ? name : 'another device',
      atMs: (o['at'] as num?)?.toInt() ?? 0,
      entries: entries,
      tombs: tombs,
    );
  }
}

/// Where a cycle got to, for the settings row and the log.
enum CloudState {
  /// No URL was built in, or no share code is set. Nothing runs.
  off,

  /// A cycle is in flight.
  working,

  /// The last cycle finished and the bucket matches this device.
  idle,

  /// The last cycle could not be completed. [CloudStatus.detail] says why.
  failed,
}

@immutable
class CloudStatus {
  final CloudState state;

  /// Devices other than this one that have published a manifest.
  final int devices;

  /// When the last cycle finished, or null if none has.
  final DateTime? lastRun;

  final String? detail;

  const CloudStatus(
    this.state, {
    this.devices = 0,
    this.lastRun,
    this.detail,
  });

  /// Value equality, and it earns its place for the reason [SyncStatus]'s
  /// does: this is a ValueNotifier published on every cycle, and without it
  /// every listener is woken to be told what it already knew.
  @override
  bool operator ==(Object other) =>
      other is CloudStatus &&
      other.state == state &&
      other.devices == devices &&
      other.lastRun == lastRun &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(state, devices, lastRun, detail);
}

/// The cloud half of the mirror.
///
/// A singleton for the same reason [LanSync] is one: it owns a timer and an
/// HTTP client, and there is one bucket to talk to.
class CloudSync {
  CloudSync._();

  static final CloudSync instance = CloudSync._();

  /// What the settings row watches.
  final ValueNotifier<CloudStatus> status =
      ValueNotifier<CloudStatus>(const CloudStatus(CloudState.off));

  /// How often a cycle runs on its own.
  ///
  /// TWO MINUTES, AND THE NUMBER IS NOT ARBITRARY. Backblaze gives 2,500 free
  /// Class B transactions a day; a pull is one. Three devices at this interval
  /// spend about 2,160 of them and stay inside it, where the same three at
  /// thirty seconds would spend 8,640 and start costing money — pennies, but
  /// pennies nobody agreed to. The mirror on a LAN is what makes "instant"
  /// feel instant; this is the net under it.
  static const Duration _cycleEvery = Duration(minutes: 2);

  /// How long any one request may take before it is abandoned.
  ///
  /// A phone that has walked out of range does not refuse a connection, it
  /// simply never answers — and a cycle without this sits holding a timer that
  /// will not fire again until it returns.
  static const Duration _timeout = Duration(seconds: 30);

  final http.Client _http = http.Client();

  String? _code;
  Timer? _timer;

  /// Non-null while a cycle is running, so two never overlap.
  ///
  /// They would otherwise: the timer fires every two minutes and a cycle over
  /// a slow connection can outlast that, which would have two of them
  /// uploading the same blobs and publishing two manifests over each other.
  Future<CloudResult>? _running;

  bool get enabled => cloudSyncConfigured && _code != null;

  /// Turns the cloud on with [canonical], or off with null.
  ///
  /// Safe to call when no URL was built in: it records the code and does
  /// nothing, so callers never have to ask whether the cloud exists.
  Future<void> setCode(String? canonical) async {
    if (canonical == _code) return;
    _code = canonical;
    _timer?.cancel();
    _timer = null;
    if (!cloudSyncConfigured) return;
    if (canonical == null) {
      _publish(const CloudStatus(CloudState.off));
      Log.i('cloud', 'cloud mirror off');
      return;
    }
    Log.i('cloud', 'cloud mirror on, group ${shareCodeFingerprint(canonical)}');
    _timer = Timer.periodic(_cycleEvery, (_) => unawaited(_tick()));
    unawaited(_tick());
  }

  /// Runs a cycle now, joining one already in flight rather than starting a
  /// second. This is what a "sync now" button calls.
  Future<CloudResult> syncNow() => _tick();

  /// M441 — a save just happened, so do not wait out the two minutes.
  ///
  /// Debounced rather than immediate: a save writes the document and its
  /// preview and may rewrite a sidecar, and a cycle per write would upload the
  /// same document three times. Five seconds is past the end of any one save
  /// and far short of anything a person would notice.
  void nudge() {
    if (!enabled) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 5), () => unawaited(_tick()));
  }

  Timer? _debounce;

  Future<CloudResult> _tick() {
    final running = _running;
    if (running != null) return running;
    final started = _cycle();
    _running = started;
    return started.whenComplete(() {
      if (identical(_running, started)) _running = null;
    });
  }

  // -------------------------------------------------------------------------
  // One cycle
  // -------------------------------------------------------------------------

  Future<CloudResult> _cycle() async {
    final code = _code;
    if (!cloudSyncConfigured || code == null) {
      return const CloudResult(CloudOutcome.off);
    }
    final mirror = LanSync.instance;
    final fingerprint = shareCodeFingerprint(code);

    _publish(CloudStatus(CloudState.working, lastRun: _lastRun));
    try {
      // 1. Notice what has changed HERE since the last cycle — a document
      //    saved, a document deleted — so this device's tombstones are current
      //    before anything is compared against them. Called for that effect;
      //    the entries are read again at step 4, because steps 2 and 3 change
      //    them. See [LanSync.mirrorState] for why the order inside it
      //    matters.
      mirror.mirrorState();

      // 2. Everyone's manifest, including our own last one.
      final manifests = await _pull(fingerprint);
      final mine = manifests.where((m) => m.device == mirror.deviceId).toList();
      final theirs =
          manifests.where((m) => m.device != mirror.deviceId).toList();

      // Every sha the bucket is known to hold. The invariant at the top of
      // this file is what makes reading it off the manifests sound: nothing is
      // named by a manifest until its bytes are up.
      final uploaded = <String>{
        for (final m in manifests)
          for (final e in m.entries) e.sha,
      };

      // 3. Take what the others have.
      final landed = <String>{};
      var forks = 0;
      for (final m in theirs) {
        for (final t in m.tombs) {
          if (mirror.mirrorApplyTomb(t)) landed.add(t.path);
        }
      }
      for (final m in theirs) {
        for (final entry in m.entries) {
          if (!mirror.mirrorWants(entry)) {
            // Not wanted means one of two very different things, and only one
            // of them is worth writing down: we already hold exactly this, in
            // which case the group agrees and the journal should say so.
            mirror.mirrorNoteAgreement(entry);
            continue;
          }
          final before = mirror.recentForks.value.length;
          final bytes = await _download(fingerprint, entry);
          if (bytes == null) continue;
          if (mirror.mirrorApply(entry, bytes, peerName: m.deviceName)) {
            landed.add(entry.path);
            if (mirror.recentForks.value.length > before) forks++;
          }
        }
      }

      // 4. Give the bucket what it is missing, BEFORE naming any of it.
      //
      // Re-scanned rather than reusing step 1's answer: step 3 has just
      // written documents to disk, and offering the versions this device held
      // before they landed would upload a file it no longer has.
      final after = mirror.mirrorState();
      final published = <SyncEntry>[];
      for (final entry in after.entries) {
        if (uploaded.contains(entry.sha)) {
          published.add(entry);
          continue;
        }
        if (await _upload(fingerprint, entry)) {
          published.add(entry);
          // The group has it now, so this version is what we agree on.
          mirror.mirrorNoteHandedOver(entry.path, entry.sha);
        }
        // An entry whose upload failed is deliberately left OUT of the
        // manifest. It goes up on the next cycle; naming it now would break
        // the one invariant this file owns.
      }

      // 5. Say what we hold.
      await _push(
        fingerprint,
        CloudManifest(
          device: mirror.deviceId,
          deviceName: mirror.deviceName,
          atMs: DateTime.now().millisecondsSinceEpoch,
          entries: published,
          tombs: after.tombs,
        ),
      );

      if (landed.isNotEmpty) mirror.mirrorApplied(landed);

      _lastRun = DateTime.now();
      _publish(CloudStatus(CloudState.idle,
          devices: theirs.length, lastRun: _lastRun));
      final documents = landed.where((p) => !p.startsWith('settings/')).length;
      if (documents > 0 || forks > 0) {
        Log.i('cloud',
            'cycle done: $documents document(s), $forks kept-both, ${theirs.length} device(s)');
      }
      // `mine` is read only to know whether this device had published before;
      // a first cycle is worth one line in the log and nothing else.
      if (mine.isEmpty) Log.i('cloud', 'first publish from this device');
      return CloudResult(
        forks > 0
            ? CloudOutcome.kept
            : documents > 0
                ? CloudOutcome.updated
                : CloudOutcome.upToDate,
        documents: documents,
        forks: forks,
        devices: theirs.length,
      );
    } catch (e) {
      Log.w('cloud', 'cycle failed: $e');
      _publish(CloudStatus(CloudState.failed,
          lastRun: _lastRun, detail: '$e'));
      return CloudResult(CloudOutcome.failed, detail: '$e');
    }
  }

  DateTime? _lastRun;

  void _publish(CloudStatus next) => status.value = next;

  // -------------------------------------------------------------------------
  // The wire
  // -------------------------------------------------------------------------

  Map<String, String> _headers(String fingerprint) => {
        'x-cloud-group': fingerprint,
        'x-cloud-device': LanSync.instance.deviceId,
        if (cloudSyncSecret.isNotEmpty) 'x-cloud-secret': cloudSyncSecret,
      };

  Uri _endpoint(String path) {
    final base = cloudSyncUrl.endsWith('/')
        ? cloudSyncUrl.substring(0, cloudSyncUrl.length - 1)
        : cloudSyncUrl;
    return Uri.parse('$base$path');
  }

  Future<List<CloudManifest>> _pull(String fingerprint) async {
    final res = await _http
        .post(_endpoint('/v1/pull'), headers: _headers(fingerprint))
        .timeout(_timeout);
    if (res.statusCode != 200) {
      throw StateError('pull: ${res.statusCode} ${res.body}');
    }
    final body = jsonDecode(res.body);
    if (body is! Map) throw const FormatException('pull: not an object');
    final raw = body['manifests'];
    if (raw is! List) return const <CloudManifest>[];
    final out = <CloudManifest>[];
    for (final m in raw) {
      final parsed = CloudManifest.fromJson(m);
      if (parsed != null) out.add(parsed);
    }
    return out;
  }

  Future<void> _push(String fingerprint, CloudManifest manifest) async {
    final res = await _http
        .post(
          _endpoint('/v1/push'),
          headers: {
            ..._headers(fingerprint),
            'content-type': 'application/json',
          },
          body: jsonEncode(manifest.toJson()),
        )
        .timeout(_timeout);
    if (res.statusCode != 200) {
      throw StateError('push: ${res.statusCode} ${res.body}');
    }
  }

  /// A presigned URL for one blob, or null if the Worker would not give one.
  Future<Uri?> _blobUrl(String fingerprint, String sha, String op) async {
    final res = await _http
        .post(
          _endpoint('/v1/blob'),
          headers: {
            ..._headers(fingerprint),
            'content-type': 'application/json',
          },
          body: jsonEncode({'op': op, 'sha': sha}),
        )
        .timeout(_timeout);
    if (res.statusCode != 200) {
      Log.w('cloud', 'no $op url for $sha: ${res.statusCode} ${res.body}');
      return null;
    }
    final body = jsonDecode(res.body);
    if (body is! Map) return null;
    final url = body['url'];
    return url is String && url.isNotEmpty ? Uri.parse(url) : null;
  }

  /// Fetches one document's bytes. Null on any failure, ALWAYS logged.
  ///
  /// Returning null rather than throwing on purpose: one document that cannot
  /// be fetched — a blob a peer named but never finished uploading, a URL that
  /// expired mid-cycle — must not cost the other nine their turn.
  Future<Uint8List?> _download(String fingerprint, SyncEntry entry) async {
    try {
      final url = await _blobUrl(fingerprint, entry.sha, 'get');
      if (url == null) return null;
      final res = await _http.get(url).timeout(_timeout);
      if (res.statusCode != 200) {
        Log.w('cloud', 'could not fetch ${entry.path}: ${res.statusCode}');
        return null;
      }
      // NOT verified here. `mirrorApply` re-hashes the bytes and drops
      // anything whose sha does not match the entry, which is the same check
      // a peer's bytes get and the only one that counts.
      return Uint8List.fromList(res.bodyBytes);
    } catch (e) {
      Log.w('cloud', 'could not fetch ${entry.path}: $e');
      return null;
    }
  }

  /// Puts one document's bytes in the bucket. False on any failure.
  Future<bool> _upload(String fingerprint, SyncEntry entry) async {
    try {
      final bytes = LanSync.instance.bytesFor(entry.path);
      if (bytes == null) {
        // Deleted or renamed between the scan and here. The next cycle scans
        // again and will not offer it.
        return false;
      }
      final url = await _blobUrl(fingerprint, entry.sha, 'put');
      if (url == null) return false;
      final res = await _http
          .put(url,
              headers: {'content-type': 'application/octet-stream'},
              body: bytes)
          .timeout(_timeout);
      if (res.statusCode != 200 && res.statusCode != 201) {
        Log.w('cloud', 'could not upload ${entry.path}: ${res.statusCode}');
        return false;
      }
      return true;
    } catch (e) {
      Log.w('cloud', 'could not upload ${entry.path}: $e');
      return false;
    }
  }

  @visibleForTesting
  void resetForTest() {
    _timer?.cancel();
    _timer = null;
    _debounce?.cancel();
    _debounce = null;
    _code = null;
    _running = null;
    _lastRun = null;
    status.value = const CloudStatus(CloudState.off);
  }
}

/// How a cycle went, in the terms the person who pressed "sync" thinks in.
///
/// Deliberately the same shape as [SyncRefreshOutcome] rather than reusing it:
/// the two mirrors fail differently — "nobody answered" is a real answer on a
/// LAN and meaningless against a bucket — and one enum covering both would
/// have members that are impossible on each side.
enum CloudOutcome {
  /// No URL built in, or no share code. Nothing was attempted.
  off,

  /// The bucket already matched this device.
  upToDate,

  /// Documents arrived or were replaced.
  updated,

  /// At least one document had been changed in two places and both copies were
  /// kept. Outranks [updated]: it is the thing worth reading.
  kept,

  /// The cycle could not be completed.
  failed,
}

@immutable
class CloudResult {
  final CloudOutcome outcome;
  final int documents;
  final int forks;
  final int devices;
  final String? detail;

  const CloudResult(
    this.outcome, {
    this.documents = 0,
    this.forks = 0,
    this.devices = 0,
    this.detail,
  });
}
