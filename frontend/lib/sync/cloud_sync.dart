// Prototype — the same mirror, through a bucket instead of a socket.
//
// WHAT THIS IS FOR. `lan_sync.dart`'s header is blunt about the one thing it
// cannot do: "It is NOT a cloud. There is no server, no account and nothing
// leaves the local network." M423 softened that with a typed-in address over
// an overlay network, which works and still needs BOTH DEVICES SWITCHED ON AT
// ONCE. The iPad edited on a train and the desktop opened that evening never
// overlap, so they never sync.
//
// A bucket removes the "at once". THE LAN MIRROR IS STILL THE FAST PATH and
// is not going anywhere: when two devices can see each other a save is on the
// other machine in about a second, over a socket, with no bucket involved.
// This is what happens when they cannot.
//
// WHAT IT IS NOT: A SECOND SYNC DESIGN. Not one rule about what wins lives in
// this file. Every decision — take, skip, keep both, honour a delete, take a
// backup first — is made by `LanSync.verdictFor` and the members around it,
// reached through the forwarders M441 added to that class. A cloud that
// reasoned about conflicts on its own would be a second implementation of the
// hardest part of this app, and the two would disagree on the day it
// mattered. This file decides only WHAT TO MOVE AND IN WHICH ORDER.
//
// M442 — NO SERVER IN BETWEEN. M441 put the B2 credential in a Cloudflare
// Worker and asked it for presigned URLs. That is still the right answer when
// the credential must not be on the device (see `cloud/README.md`), and it
// costs a terminal, a Cloudflare account and a deploy. The app now signs its
// own requests instead (`b2_signer.dart`), so the whole setup is a key pasted
// into Settings. What that trades is written down in `cloud_account.dart`.
//
// HOW ONE CYCLE GOES
//
//   1. Ask LanSync what this device holds and what it remembers deleting.
//   2. LIST the manifests. Fetch only the ones whose ETag moved.
//   3. Apply peers' tombstones, then fetch and apply the entries this device
//      wants — each through `mirrorApply`, so a fork still forks.
//   4. Upload anything of ours the bucket does not have yet.
//   5. Publish our own manifest.
//
// THE ORDER OF 4 AND 5 IS THE ONE INVARIANT THIS FILE OWNS:
//
//   A MANIFEST ONLY EVER NAMES BLOBS THAT ARE ALREADY UPLOADED.
//
// Publish first and a peer reads an entry, asks for bytes that are not there
// and — worse than failing — could conclude from a 404 that the document is
// gone. Upload first and the failure mode is a blob nobody references yet,
// which costs a few kilobytes until the collector takes it. One of those is a
// data-loss report and the other is litter.
//
// WHAT MAKES IT FAST, since "it is the slow path" is not a reason to be slow:
//
//   * AN IDLE CYCLE IS ONE REQUEST. A LIST returns every manifest's ETag, and
//     an ETag that has not moved is a device that has nothing to say. Only
//     changed manifests are fetched. Three idle devices cost one LIST each,
//     not one LIST and three GETs each.
//   * THE INTERVAL FOLLOWS THE WORK. Five seconds while anything is
//     happening, doubling up to two minutes when nothing is. Somebody moving
//     between two devices is inside the fast band the whole time; a laptop
//     left open overnight settles at the slow one.
//   * A SAVE DOES NOT WAIT FOR THE INTERVAL AT ALL. [nudge] is called the
//     moment bytes are on disk and runs a cycle a second later.
//   * TRANSFERS RUN TOGETHER. Ten documents that changed are ten round trips,
//     and done one after another on a phone connection that is most of a
//     minute. Bounded, because a hundred at once is how a mobile connection
//     is made to fail rather than to go faster.
//
// Which lands, in the ordinary case of two devices and a save, at about a
// second on the LAN and about two seconds through the bucket.
//
// WHAT IS NOT ENCRYPTED, said plainly rather than implied away. The bucket is
// private and TLS covers the wire, but the bytes sit on Backblaze's disks in
// the clear, so this is on the same footing as keeping documents in Dropbox
// or Drive: a company can read them. Closing it means encrypting in [_upload]
// and decrypting in [_download] — two places — plus a cipher, which this app
// does not have (`crypto` hashes, it does not encrypt).
import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../log.dart';
import 'b2_signer.dart';
import 'lan_sync.dart';

/// The manifest format's own version.
///
/// Bumped when a change would make an older app MISREAD a manifest rather
/// than merely miss a field — unknown keys are ignored on purpose, exactly as
/// the LAN protocol's headers are, so a newer device can add one without an
/// older one refusing the file.
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

/// One object as a listing describes it.
@immutable
class B2Object {
  final String key;
  final String etag;
  final int sizeBytes;
  final int lastModifiedMs;

  const B2Object(this.key, this.etag, this.sizeBytes, this.lastModifiedMs);

  /// The last path segment — a manifest's device id, or a blob's sha.
  String get name => key.substring(key.lastIndexOf('/') + 1);
}

/// Where a cycle got to, for the settings row and the log.
enum CloudState {
  /// No account. Nothing runs.
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

  const CloudStatus(this.state, {this.devices = 0, this.lastRun, this.detail});

  /// Value equality, and it earns its place for the reason [SyncStatus]'s
  /// does: this is published on every cycle, and without it every listener is
  /// woken to be told what it already knew.
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
class CloudSync {
  CloudSync._();

  static final CloudSync instance = CloudSync._();

  /// What the settings row watches.
  final ValueNotifier<CloudStatus> status =
      ValueNotifier<CloudStatus>(const CloudStatus(CloudState.off));

  /// The interval while anything is happening.
  ///
  /// Five seconds, not one: a cycle is a LIST and usually nothing else, but
  /// somebody who is merely SCROLLING the gallery should not be generating a
  /// request every second for a bucket nobody is writing to. A save does not
  /// wait for this at all — see [nudge].
  static const Duration fastCycle = Duration(seconds: 5);

  /// The interval once nothing has happened for a while.
  ///
  /// TWO MINUTES, AND THE NUMBER IS PICKED AGAINST A LIMIT. Backblaze gives
  /// 2,500 free Class B transactions a day and an idle cycle spends one.
  /// Three devices at two minutes spend about 2,160 of them and stay inside
  /// it. The fast band above costs more, and costs it only while somebody is
  /// actually working — which is the trade this whole schedule exists to
  /// make.
  static const Duration slowCycle = Duration(minutes: 2);

  /// How long any one request may take before it is abandoned.
  ///
  /// A phone that has walked out of range does not refuse a connection, it
  /// simply never answers — and a cycle without this holds the next one up
  /// for ever.
  static const Duration _timeout = Duration(seconds: 30);

  /// The largest document this will fetch or send.
  ///
  /// THE SAME BOUND THE LAN MIRROR HAS (`SyncFrameReader.maxPayload`), and it
  /// is here for a sharper reason: `http.get` buffers the whole body in memory
  /// before anything can look at it, so a manifest entry claiming a gigabyte
  /// is an out-of-memory crash on an iPad — and a manifest is the one thing
  /// here that another device writes. The size is checked from the ENTRY,
  /// before the request goes out, and again against what actually arrived.
  static const int maxDocumentBytes = 256 << 20;

  /// How many transfers run at once.
  ///
  /// Four, because the point is to stop paying full latency per document and
  /// not to saturate a mobile connection: past about this many, a phone
  /// starts timing requests out rather than finishing them sooner.
  static const int _concurrency = 4;

  final http.Client _http = http.Client();

  B2Credentials? _account;
  Timer? _timer;
  Timer? _debounce;
  Duration _interval = fastCycle;
  DateTime? _lastRun;

  /// The ETag each device's manifest had when it was last read, and what it
  /// held. This is what makes an idle cycle one request: a manifest whose
  /// ETag has not moved is a device with nothing to say, and is not fetched.
  final Map<String, String> _manifestEtags = <String, String>{};
  final Map<String, CloudManifest> _manifestCache = <String, CloudManifest>{};

  /// Non-null while a cycle is running, so two never overlap. They would
  /// otherwise: a cycle over a slow connection can outlast the interval, and
  /// two of them would upload the same blobs and publish two manifests over
  /// each other.
  Future<CloudResult>? _running;

  bool get enabled => _account != null;
  B2Credentials? get account => _account;

  /// Turns the cloud on with [credentials], or off with null.
  Future<void> setAccount(B2Credentials? credentials) async {
    final next =
        (credentials != null && credentials.isComplete) ? credentials : null;
    if (next == _account) return;
    _account = next;
    _timer?.cancel();
    _timer = null;
    _manifestEtags.clear();
    _manifestCache.clear();
    if (next == null) {
      _publish(const CloudStatus(CloudState.off));
      Log.i('cloud', 'cloud mirror off');
      return;
    }
    Log.i('cloud', 'cloud mirror on, bucket ${next.bucket}');
    _interval = fastCycle;
    unawaited(_tick());
  }

  /// Runs a cycle now, joining one already in flight rather than starting a
  /// second. This is what a "sync now" button calls.
  Future<CloudResult> syncNow() {
    _interval = fastCycle;
    return _tick();
  }

  /// A save just happened, so do not wait out the interval.
  ///
  /// ONE SECOND, debounced rather than immediate: a save writes the document
  /// and its preview and may rewrite a sidecar, and a cycle per write would
  /// upload the same document three times. One second is past the end of any
  /// one save and short enough that nobody notices it.
  void nudge() {
    if (!enabled) return;
    _interval = fastCycle;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 1), () => unawaited(_tick()));
  }

  Future<CloudResult> _tick() {
    final running = _running;
    if (running != null) return running;
    final started = _cycle();
    _running = started;
    return started.whenComplete(() {
      if (identical(_running, started)) _running = null;
      _reschedule();
    });
  }

  /// Sets the next cycle, at whatever the interval has become.
  ///
  /// A single-shot timer rebuilt each time rather than `Timer.periodic`: the
  /// interval changes, and a periodic timer cannot be asked to change its
  /// mind.
  void _reschedule() {
    _timer?.cancel();
    if (!enabled) return;
    _timer = Timer(_interval, () => unawaited(_tick()));
  }

  /// Something happened, so stay in the fast band.
  void _sawWork() => _interval = fastCycle;

  /// Nothing happened, so back off — doubling, up to [slowCycle].
  void _sawNothing() {
    final next = _interval * 2;
    _interval = next > slowCycle ? slowCycle : next;
  }

  // -------------------------------------------------------------------------
  // One cycle
  // -------------------------------------------------------------------------

  Future<CloudResult> _cycle() async {
    final account = _account;
    if (account == null) return const CloudResult(CloudOutcome.off);
    final mirror = LanSync.instance;
    final group = _groupFor(account);

    _publish(CloudStatus(CloudState.working, lastRun: _lastRun));
    try {
      // 1. Notice what has changed HERE since the last cycle — a document
      //    saved, a document deleted — so this device's tombstones are
      //    current before anything is compared against them. Called for that
      //    effect; the entries are read again at step 4, because steps 2 and
      //    3 change them.
      mirror.mirrorState();

      // 2. One LIST, and a GET only for what moved.
      final manifests = await _pullManifests(account, group);
      final theirs =
          manifests.where((m) => m.device != mirror.deviceId).toList();

      // Every sha the bucket is known to hold. The invariant at the top of
      // this file is what makes reading it off the manifests sound.
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

      // Decided first, fetched together. Asking `mirrorWants` up front costs
      // nothing and means the transfers below are all work that is wanted.
      final wanted = <({SyncEntry entry, String from})>[];
      final seen = <String>{};
      for (final m in theirs) {
        for (final entry in m.entries) {
          if (!mirror.mirrorWants(entry)) {
            // Not wanted means one of two very different things, and only one
            // is worth writing down: we hold exactly this, so the group
            // agrees and the journal should say so.
            mirror.mirrorNoteAgreement(entry);
            continue;
          }
          // Two devices offering the same version of the same path is one
          // download, not two.
          if (!seen.add('${entry.path}\u0000${entry.sha}')) continue;
          wanted.add((entry: entry, from: m.deviceName));
        }
      }

      final fetched = await _inBatches(
        wanted,
        (w) async => (w, await _download(account, group, w.entry)),
      );
      for (final (w, bytes) in fetched) {
        if (bytes == null) continue;
        final before = mirror.recentForks.value.length;
        if (mirror.mirrorApply(w.entry, bytes, peerName: w.from)) {
          landed.add(w.entry.path);
          if (mirror.recentForks.value.length > before) forks++;
        }
      }

      // 4. Give the bucket what it is missing, BEFORE naming any of it.
      //
      // Re-scanned rather than reusing step 1's answer: step 3 has just
      // written documents to disk, and offering the versions this device held
      // before they landed would upload a file it no longer has.
      final after = mirror.mirrorState();
      final owed = [
        for (final e in after.entries)
          if (!uploaded.contains(e.sha)) e,
      ];
      final sent = await _inBatches(
        owed,
        (e) async => (e, await _upload(account, group, e)),
      );
      final failed = <String>{
        for (final (entry, ok) in sent)
          if (!ok) entry.path,
      };
      for (final (entry, ok) in sent) {
        if (ok) mirror.mirrorNoteHandedOver(entry.path, entry.sha);
      }
      // An entry whose upload failed is deliberately left OUT of the
      // manifest. It goes up on the next cycle; naming it now would break the
      // one invariant this file owns.
      final published = [
        for (final e in after.entries)
          if (!failed.contains(e.path)) e,
      ];

      // 5. Say what we hold — but only if it differs from what we last said.
      //    A manifest rewritten every cycle would change its ETag every cycle,
      //    and every other device would fetch it to learn nothing.
      final mineNow = CloudManifest(
        device: mirror.deviceId,
        deviceName: mirror.deviceName,
        atMs: DateTime.now().millisecondsSinceEpoch,
        entries: published,
        tombs: after.tombs,
      );
      final changedOurs = _differs(_manifestCache[mirror.deviceId], mineNow);
      if (changedOurs) {
        await _push(account, group, mineNow);
        _manifestCache[mirror.deviceId] = mineNow;
        // Our own ETag is now unknown; the next LIST will tell us. Dropping
        // it is what stops us reading our own write back as a peer's change.
        _manifestEtags.remove(mirror.deviceId);
      }

      if (landed.isNotEmpty) mirror.mirrorApplied(landed);

      _lastRun = DateTime.now();
      _publish(CloudStatus(CloudState.idle,
          devices: theirs.length, lastRun: _lastRun));

      final documents = landed.where((p) => !p.startsWith('settings/')).length;
      if (documents > 0 || forks > 0 || changedOurs) {
        _sawWork();
        Log.i(
            'cloud',
            'cycle: $documents in, ${published.length} held, $forks kept-both, '
            '${theirs.length} device(s)');
      } else {
        _sawNothing();
      }
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
      Log.w('cloud', 'cycle failed: ${redactUrls(e)}');
      _publish(
          CloudStatus(CloudState.failed, lastRun: _lastRun, detail: _explain(e)));
      // A failure backs off like a quiet cycle rather than hammering a bucket
      // that is refusing us — a wrong key would otherwise be 720 rejected
      // requests an hour.
      _sawNothing();
      return CloudResult(CloudOutcome.failed, detail: _explain(e));
    }
  }

  /// Whether the manifest we are about to publish says anything new.
  static bool _differs(CloudManifest? was, CloudManifest now) {
    if (was == null) return true;
    if (was.entries.length != now.entries.length) return true;
    if (was.tombs.length != now.tombs.length) return true;
    // `atMs` is deliberately NOT compared: it moves every cycle and comparing
    // it would make every cycle a write.
    final a = {for (final e in was.entries) e.path: e.sha};
    for (final e in now.entries) {
      if (a[e.path] != e.sha) return true;
    }
    final t = {for (final e in was.tombs) e.path: e.deletedAtMs};
    for (final e in now.tombs) {
      if (t[e.path] != e.deletedAtMs) return true;
    }
    return false;
  }

  /// Runs [work] over [items], [_concurrency] at a time, in order.
  static Future<List<R>> _inBatches<T, R>(
      List<T> items, Future<R> Function(T) work) async {
    final out = <R>[];
    for (var i = 0; i < items.length; i += _concurrency) {
      final end =
          (i + _concurrency < items.length) ? i + _concurrency : items.length;
      out.addAll(await Future.wait(items.sublist(i, end).map(work)));
    }
    return out;
  }

  void _publish(CloudStatus next) => status.value = next;

  // -------------------------------------------------------------------------
  // The bucket
  // -------------------------------------------------------------------------

  /// The folder in the bucket this account's devices share.
  ///
  /// Derived rather than fixed, so one bucket can hold more than one group
  /// without them ever seeing each other's manifests — and so the folder name
  /// says nothing about the key it came from.
  static String _groupFor(B2Credentials c) => sha256Hex(
      'prototype-cloud\x00${c.appKey}\x00${c.bucket}');

  Future<List<CloudManifest>> _pullManifests(
      B2Credentials account, String group) async {
    final listed = await _list(account, 'g/$group/m/');
    final out = <CloudManifest>[];
    final live = <String>{};

    final stale = <B2Object>[];
    for (final o in listed) {
      if (!o.name.endsWith('.json')) continue;
      final device = o.name.substring(0, o.name.length - 5);
      live.add(device);
      // THE WHOLE POINT OF THE LISTING. An ETag that has not moved is a
      // device that has published nothing since we last looked, so there is
      // no reason to spend a request on it.
      if (_manifestEtags[device] == o.etag &&
          _manifestCache.containsKey(device)) {
        out.add(_manifestCache[device]!);
        continue;
      }
      stale.add(o);
    }

    final fetched = await _inBatches(
        stale, (o) async => (o, await _getString(account, o.key)));
    for (final (o, body) in fetched) {
      if (body == null) continue;
      final device = o.name.substring(0, o.name.length - 5);
      try {
        final m = CloudManifest.fromJson(jsonDecode(body));
        if (m == null) continue;
        _manifestEtags[device] = o.etag;
        _manifestCache[device] = m;
        out.add(m);
      } catch (e) {
        // One device's unreadable manifest costs that device's updates this
        // cycle. Failing the pull would cost every device's.
        Log.w('cloud', 'could not read a manifest: ${redactUrls(e)}');
      }
    }

    // A device whose manifest is gone has left. Forgetting it keeps the
    // caches from growing with every device that ever paired.
    _manifestEtags.removeWhere((k, _) => !live.contains(k));
    _manifestCache.removeWhere((k, _) => !live.contains(k));
    return out;
  }

  Future<void> _push(
      B2Credentials account, String group, CloudManifest manifest) async {
    final url = B2Signer.sign(
      credentials: account,
      method: 'PUT',
      key: 'g/$group/m/${manifest.device}.json',
    );
    final res = await _http
        .put(url,
            headers: const {'content-type': 'application/json'},
            body: utf8.encode(jsonEncode(manifest.toJson())))
        .timeout(_timeout);
    if (res.statusCode != 200) {
      throw StateError('push: ${res.statusCode}');
    }
  }

  /// Every object under [prefix], following the listing's continuation.
  ///
  /// B2 caps a listing at 1,000 and says so with `IsTruncated`. Reading only
  /// the first page would silently hide devices once a bucket grew.
  Future<List<B2Object>> _list(B2Credentials account, String prefix) async {
    final out = <B2Object>[];
    String? token;
    // Bounded rather than `while (true)`: a server that kept handing back the
    // same token would otherwise spin for ever.
    for (var page = 0; page < 64; page++) {
      final url = B2Signer.sign(
        credentials: account,
        method: 'GET',
        key: '',
        query: {
          'list-type': '2',
          'prefix': prefix,
          'max-keys': '1000',
          if (token != null) 'continuation-token': token,
        },
      );
      final res = await _http.get(url).timeout(_timeout);
      if (res.statusCode != 200) {
        throw StateError('list: ${res.statusCode}');
      }
      final xml = utf8.decode(res.bodyBytes);
      out.addAll(parseListing(xml));
      token = parseContinuation(xml);
      if (token == null) break;
    }
    return out;
  }

  Future<String?> _getString(B2Credentials account, String key) async {
    try {
      final res = await _http
          .get(B2Signer.sign(credentials: account, method: 'GET', key: key))
          .timeout(_timeout);
      if (res.statusCode != 200) return null;
      return utf8.decode(res.bodyBytes);
    } catch (e) {
      Log.w('cloud', 'could not read $key: ${redactUrls(e)}');
      return null;
    }
  }

  /// Fetches one document's bytes. Null on any failure, ALWAYS logged.
  ///
  /// Returning null rather than throwing on purpose: one document that cannot
  /// be fetched — a blob a peer named but never finished uploading — must not
  /// cost the other nine their turn.
  Future<Uint8List?> _download(
      B2Credentials account, String group, SyncEntry entry) async {
    // BEFORE THE REQUEST, from the size the MANIFEST claims. `http.get`
    // buffers the whole body before anything can inspect it, so by the time a
    // response could be measured the memory is already gone — and a manifest
    // is written by another device, which makes this the one number here that
    // is not ours.
    if (entry.size < 0 || entry.size > maxDocumentBytes) {
      Log.w('cloud',
          'refusing ${entry.path}: it claims ${entry.size} bytes');
      return null;
    }
    try {
      final res = await _http
          .get(B2Signer.sign(
              credentials: account,
              method: 'GET',
              key: 'g/$group/b/${entry.sha}'))
          .timeout(_timeout);
      if (res.statusCode != 200) {
        Log.w('cloud', 'could not fetch ${entry.path}: ${res.statusCode}');
        return null;
      }
      // NOT verified here. `mirrorApply` re-hashes the bytes and drops
      // anything whose sha does not match, which is the same check a peer's
      // bytes get and the only one that counts.
      return Uint8List.fromList(res.bodyBytes);
    } catch (e) {
      Log.w('cloud', 'could not fetch ${entry.path}: ${redactUrls(e)}');
      return null;
    }
  }

  /// Puts one document's bytes in the bucket. False on any failure.
  Future<bool> _upload(
      B2Credentials account, String group, SyncEntry entry) async {
    try {
      final bytes = LanSync.instance.bytesFor(entry.path);
      if (bytes == null) {
        // Deleted or renamed between the scan and here. The next cycle scans
        // again and will not offer it.
        return false;
      }
      final res = await _http
          .put(
              B2Signer.sign(
                  credentials: account,
                  method: 'PUT',
                  key: 'g/$group/b/${entry.sha}'),
              headers: const {'content-type': 'application/octet-stream'},
              body: bytes)
          .timeout(_timeout);
      if (res.statusCode != 200 && res.statusCode != 201) {
        Log.w('cloud', 'could not upload ${entry.path}: ${res.statusCode}');
        return false;
      }
      return true;
    } catch (e) {
      Log.w('cloud', 'could not upload ${entry.path}: ${redactUrls(e)}');
      return false;
    }
  }

  @visibleForTesting
  void resetForTest() {
    _timer?.cancel();
    _timer = null;
    _debounce?.cancel();
    _debounce = null;
    _account = null;
    _running = null;
    _lastRun = null;
    _interval = fastCycle;
    _manifestEtags.clear();
    _manifestCache.clear();
    status.value = const CloudStatus(CloudState.off);
  }

  @visibleForTesting
  Duration get intervalForTest => _interval;

  @visibleForTesting
  void sawNothingForTest() => _sawNothing();

  @visibleForTesting
  void sawWorkForTest() => _sawWork();

  @visibleForTesting
  static String groupForTest(B2Credentials c) => _groupFor(c);

  @visibleForTesting
  static bool differsForTest(CloudManifest? was, CloudManifest now) =>
      _differs(was, now);
}

/// One line of a log or a status row, with any signed URL taken out of it.
///
/// THE LEAK THIS CLOSES. `package:http` throws `ClientException`, whose
/// `toString()` is `'ClientException: <message>, uri=<uri>'` — so logging an
/// error with string interpolation on any network failure would write the whole
/// presigned URL into the log. That URL carries `X-Amz-Credential` (the key
/// ID) and `X-Amz-Signature`, which is a bearer token for that object until it
/// expires; and `bug_capture.dart` puts the log tail into a bundle that the
/// relay commits to a GitHub issue. A dropped connection would have published
/// a working credential.
///
/// Everything from the first `?` of a URL is replaced, rather than only the
/// parameters we know about: a signer that gains a parameter must not quietly
/// gain a way out of this.
/// `replaceAllMapped`, NOT `replaceAll`: Dart's `replaceAll` treats `$1` in
/// the replacement as two literal characters rather than the captured group,
/// so the naive version blanked the path as well and every log line read
/// `uri=$1?<signed>`. It still redacted — it also threw away the one part of
/// the URL that says which object failed. Its test caught it.
String redactUrls(Object? o) => o.toString().replaceAllMapped(
    RegExp(r'(https?://[^\s,)]*)\?[^\s,)]*'), (m) => '${m[1]}?<signed>');

/// What went wrong, in terms the settings row can show a person.
///
/// A RAW STATUS CODE IS NOT AN ANSWER. `Bad state: list: 403` is what the
/// status row used to read when somebody mistyped one character of their key,
/// and it sends them to a search engine rather than back to the field they got
/// wrong. These are the three that actually happen during setup.
String _explain(Object e) {
  final s = redactUrls(e);
  if (s.contains('401') || s.contains('403')) {
    return 'Backblaze refused the key — check the Key ID and Application Key.';
  }
  if (s.contains('404')) {
    return 'No such bucket — check the bucket name and the endpoint.';
  }
  if (s.contains('400')) {
    return 'Backblaze rejected the request — check the endpoint and bucket.';
  }
  return s;
}

@visibleForTesting
String explainForTest(Object e) => _explain(e);

/// The `<Contents>` of a ListObjectsV2 response.
///
/// A regex rather than an XML parser: the shape is fixed, this app owns both
/// ends of it, and every key here is hex we wrote ourselves, so there is no
/// entity-escaping to get wrong except the ETag's own quotes — which B2 sends
/// as `&quot;` and which are stripped here.
///
/// Read as whole `<Contents>` blocks rather than as three separate scans: a
/// response where one object lacked a field would otherwise shift every
/// following value onto the wrong key.
List<B2Object> parseListing(String xml) {
  final out = <B2Object>[];
  for (final m
      in RegExp(r'<Contents>([\s\S]*?)</Contents>', multiLine: true)
          .allMatches(xml)) {
    final body = m.group(1)!;
    final key = RegExp(r'<Key>([^<]*)</Key>').firstMatch(body)?.group(1);
    if (key == null || key.isEmpty) continue;
    final etag = RegExp(r'<ETag>([^<]*)</ETag>').firstMatch(body)?.group(1) ?? '';
    final size = RegExp(r'<Size>(\d+)</Size>').firstMatch(body)?.group(1);
    final at = RegExp(r'<LastModified>([^<]*)</LastModified>')
        .firstMatch(body)
        ?.group(1);
    out.add(B2Object(
      key,
      etag.replaceAll('&quot;', '').replaceAll('"', ''),
      int.tryParse(size ?? '') ?? 0,
      DateTime.tryParse(at ?? '')?.millisecondsSinceEpoch ?? 0,
    ));
  }
  return out;
}

/// The token for the next page, or null when the listing was complete.
String? parseContinuation(String xml) {
  if (!RegExp(r'<IsTruncated>\s*true\s*</IsTruncated>', caseSensitive: false)
      .hasMatch(xml)) {
    return null;
  }
  return RegExp(r'<NextContinuationToken>([^<]+)</NextContinuationToken>')
      .firstMatch(xml)
      ?.group(1);
}

/// Hex sha256 of a string, for the group folder.
String sha256Hex(String s) => sha256.convert(utf8.encode(s)).toString();

/// How a cycle went, in the terms the person who pressed "sync" thinks in.
///
/// Deliberately not [SyncRefreshOutcome]: the two mirrors fail differently —
/// "nobody answered" is a real answer on a LAN and meaningless against a
/// bucket — and one enum covering both would have members that are impossible
/// on each side.
enum CloudOutcome {
  /// No account. Nothing was attempted.
  off,

  /// The bucket already matched this device.
  upToDate,

  /// Documents arrived or were replaced.
  updated,

  /// At least one document had been changed in two places and both copies
  /// were kept. Outranks [updated]: it is the thing worth reading.
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
