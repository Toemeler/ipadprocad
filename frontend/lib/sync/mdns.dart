// Prototype — Bonjour, in pure Dart, for the two platforms with no plugin
// behind `prototype/sync_discovery` (see bonjour.dart's header): Windows and
// Linux.
//
// THE BUG THIS FIXES: an iPad only ever browses Bonjour (`_prototypesync._tcp`
// over mDNS) — a raw UDP broadcast needs an entitlement Apple grants case by
// case, so the beacon in lan_sync.dart is not something an iPad can rely on
// sending OR hearing. A desktop with no Bonjour plugin therefore never shows
// up on an iPad's radar at all, whatever the beacon does — "the iPad doesn't
// see the device" is not a flaky report, it is what a Windows machine that
// never advertises on the one channel the iPad trusts looks like from the
// iPad's side, in every case, every time.
//
// bonjour.dart's own comment called the gap deliberate ("Windows have no
// implementation behind this channel and are not supposed to") on the
// reasoning that the beacon covers desktop-to-desktop discovery. It does not
// cover desktop-to-iPad, and nothing else did either.
//
// WHAT THIS IS. Just enough of RFC 6762 (multicast DNS) and RFC 6763 (DNS-SD)
// to interoperate with Apple's own Bonjour stack for one service type:
// advertise (answer queries for `_prototypesync._tcp.local.` with a
// PTR/SRV/TXT/A set, and announce them unsolicited on start so a browser
// already running does not have to wait out its next query) and browse (ask
// the same question, and turn PTR/SRV/TXT/A answers from other devices —
// iPads and, on a machine with no plugin either, other desktops — into the
// same [SyncSighting] the native channel produces). It is not a general mDNS
// resolver: unrelated services and record types on the wire are decoded only
// as far as skipping their RDATA correctly, never acted on.
//
// OUTGOING NAMES ARE NOT COMPRESSED. RFC 6762 allows an uncompressed name
// anywhere a compressed one would go; compression is a size optimisation,
// never a correctness requirement, and skipping it keeps the encoder small
// enough to read in one sitting. INCOMING names ARE decompressed — every
// real responder, Apple's included, uses pointers, and refusing to follow
// them would mean refusing to understand any answer.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../log.dart';
import 'bonjour.dart' show SyncSighting, kBonjourServiceType;

const String _kGroupV4 = '224.0.0.251';
const int _kMdnsPort = 5353;
const String _kDomain = 'local';

const int _kTypeA = 1;
const int _kTypePtr = 12;
const int _kTypeTxt = 16;
const int _kTypeSrv = 33;
const int _kClassIn = 1;

/// The full DNS-SD name for the service, e.g. `_prototypesync._tcp.local`.
String get _serviceFqdn => '$kBonjourServiceType.$_kDomain';

/// Pure-Dart stand-in for the platform channel [Bonjour] normally speaks to.
/// Same shape — `start`/`stop`/`running`/a sighting callback — so
/// bonjour.dart can hand off to this without either caller (lan_sync.dart) or
/// the protocol it drives knowing the difference.
class MdnsFallback {
  RawDatagramSocket? _socket;
  Timer? _announceTimer;
  Timer? _queryTimer;
  StreamSubscription<RawSocketEvent>? _sub;

  String? _deviceId;
  String? _deviceName;
  String? _fingerprint;
  int _version = 1;
  int _port = 0;
  void Function(SyncSighting)? _onSighting;

  bool get running => _socket != null;

  Future<void> start({
    required String fingerprint,
    required String deviceId,
    required String deviceName,
    required int port,
    required void Function(SyncSighting) onSighting,
  }) async {
    await stop();
    _deviceId = deviceId;
    _deviceName = deviceName;
    _fingerprint = fingerprint;
    _port = port;
    _onSighting = onSighting;

    try {
      // Bound to the mDNS port on every interface, and joined to the mDNS
      // group so multicast traffic actually arrives — a socket merely SENT
      // to 224.0.0.251 without joining does not receive the replies.
      final s = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _kMdnsPort,
        reuseAddress: true,
        reusePort: !Platform.isWindows,
      );
      s.readEventsEnabled = true;
      s.multicastLoopback = true;
      try {
        s.joinMulticast(InternetAddress(_kGroupV4));
      } catch (e) {
        // Some sandboxes and some adapters refuse a join; queries still go
        // out and this device can still be found by anyone who does hear
        // multicast, even if it cannot itself.
        Log.w('sync', 'mDNS: could not join the multicast group: $e');
      }
      _socket = s;
      _sub = s.listen(_onEvent, onError: (Object e) {
        Log.w('sync', 'mDNS socket stopped: $e');
      });
    } catch (e) {
      Log.i('sync', 'mDNS: could not bind :$_kMdnsPort ($e) — no fallback '
          'discovery here');
      return;
    }

    Log.i('sync', 'mDNS up (pure-Dart fallback): $_serviceFqdn on $port');
    await _refreshLocalAddress();
    // Announce right away — a browser that is already running should not
    // have to wait out its own query interval — and again shortly after,
    // which is the cheap way RFC 6762 recommends surviving a first packet
    // lost to an interface still coming up.
    _sendAnnounce();
    Timer(const Duration(milliseconds: 250), () {
      if (running) _sendAnnounce();
    });
    _announceTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _refreshLocalAddress().then((_) => _sendAnnounce());
    });
    _sendQuery();
    _queryTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _sendQuery());
  }

  Future<void> stop() async {
    _announceTimer?.cancel();
    _queryTimer?.cancel();
    _announceTimer = null;
    _queryTimer = null;
    await _sub?.cancel();
    _sub = null;
    _socket?.close();
    _socket = null;
  }

  void _onEvent(RawSocketEvent e) {
    final s = _socket;
    if (s == null || e != RawSocketEvent.read) return;
    // A socket bound to the mDNS port and joined to the group also receives
    // OTHER programs' mDNS traffic (printers, Chromecasts, every service on
    // the LAN); every non-matching message is expected and silently
    // dropped, not logged — that would be a warning on every packet a
    // browser on the same network produces.
    for (var dg = s.receive(); dg != null; dg = s.receive()) {
      try {
        _handle(dg.data, dg.address);
      } catch (_) {
        // Malformed or irrelevant traffic. Not this device's problem.
      }
    }
  }

  void _handle(Uint8List data, InternetAddress source) {
    final msg = _DnsMessage.parse(data, source);
    if (msg == null) return;
    if (msg.isQuery) {
      _maybeAnswer(msg);
    } else {
      _maybeSight(msg);
    }
  }

  /// A question for our service type, or for our own instance/host names
  /// (a browser that already has our SRV record asking to refresh the A
  /// record), gets the same full record set back. Answering ALL of it
  /// rather than only the record actually asked for is what RFC 6763's
  /// "known answer" browsers expect — cheap here since the set is four
  /// records for one service.
  void _maybeAnswer(_DnsMessage msg) {
    final id = _deviceId;
    if (id == null) return;
    for (final q in msg.questions) {
      final name = q.name.toLowerCase();
      if (name == _serviceFqdn.toLowerCase() ||
          name == '${_instanceFqdn(id)}'.toLowerCase() ||
          name == '${_hostFqdn(id)}'.toLowerCase()) {
        _sendAnnounce();
        return;
      }
    }
  }

  /// An answer naming OUR service type: pull out the instance's SRV (host +
  /// port) and TXT (id/name/fingerprint/version), resolve the host to an
  /// address from the same packet's A record where present, and report a
  /// sighting once both halves are in hand.
  void _maybeSight(_DnsMessage msg) {
    final myFp = _fingerprint;
    if (myFp == null) return;
    final records = [...msg.answers, ...msg.additional];

    String? instanceName;
    for (final r in records) {
      if (r.type == _kTypePtr &&
          r.name.toLowerCase() == _serviceFqdn.toLowerCase() &&
          r.ptrTarget != null) {
        instanceName = r.ptrTarget;
        break;
      }
    }
    // No PTR in THIS packet is normal — an unsolicited announce and a
    // query's reply both repeat the SRV/TXT even when only the PTR was
    // asked for, but a peer that sent SRV/TXT/A alone (answering a direct
    // SRV question) has no PTR to find. Fall back to any SRV whose owner
    // name is under our service type.
    if (instanceName == null) {
      final anySrv = records.firstWhere(
        (r) => r.type == _kTypeSrv &&
            r.name.toLowerCase().endsWith('.${_serviceFqdn.toLowerCase()}'),
        orElse: () => _ResourceRecord.empty(),
      );
      if (anySrv.name.isEmpty) return;
      instanceName = anySrv.name;
    }

    _ResourceRecord? srv, txt, a;
    for (final r in records) {
      final owner = r.name.toLowerCase();
      if (r.type == _kTypeSrv && owner == instanceName.toLowerCase()) srv = r;
      if (r.type == _kTypeTxt && owner == instanceName.toLowerCase()) txt = r;
    }
    if (srv == null) return;
    final target = srv.srvTarget?.toLowerCase();
    if (target != null) {
      for (final r in records) {
        if (r.type == _kTypeA && r.name.toLowerCase() == target) a = r;
      }
    }
    // `.address`, because the two halves of this ?? are different types:
    // aAddress is an InternetAddress and _hostHint already returns its
    // `.address` string. Without it the expression is an Object, which is
    // what SyncSighting.host — a String — refused.
    final host = a?.aAddress?.address ?? _hostHint(msg.sourceAddress);
    if (host == null) return;

    final kv = txt?.txtEntries ?? const <String, String>{};
    final fp = kv['fp'] ?? '';
    if (fp != myFp) return; // a different group, or a non-answering peer
    final id = kv['id'] ?? '';
    if (id.isEmpty || id == _deviceId) return; // our own announce, come back
    final version = int.tryParse(kv['v'] ?? '') ?? 0;
    _onSighting?.call(SyncSighting(
      id: id,
      name: kv['n'] ?? '?',
      host: host,
      port: srv.srvPort ?? 0,
      fingerprint: fp,
      version: version,
    ));
  }

  /// When a peer's A record is missing from the packet — it answered only
  /// the question asked, e.g. — the packet's OWN source address is still
  /// the peer's address on this LAN; mDNS travels one hop, so whoever sent
  /// it is reachable at the address it sent it from.
  String? _hostHint(InternetAddress? source) => source?.address;

  String _instanceFqdn(String id) => '$id.$_serviceFqdn';
  String _hostFqdn(String id) => '$id.$_kDomain';

  void _sendAnnounce() {
    final s = _socket;
    final id = _deviceId;
    if (s == null || id == null) return;
    final instance = _instanceFqdn(id);
    final host = _hostFqdn(id);
    final txt = <String, String>{
      'id': id,
      'n': _deviceName ?? '?',
      'fp': _fingerprint ?? '',
      'v': '$_version',
    };
    final msg = _DnsMessageBuilder(isResponse: true)
      ..addAnswer(_ResourceRecord.ptr(_serviceFqdn, instance))
      ..addAnswer(_ResourceRecord.srv(instance, host, _port))
      ..addAnswer(_ResourceRecord.txt(instance, txt))
      ..addAnswer(_ResourceRecord.a(host, _localAddress));
    _send(msg.build());
  }

  void _sendQuery() {
    final s = _socket;
    if (s == null) return;
    final msg = _DnsMessageBuilder(isResponse: false)
      ..addQuestion(_serviceFqdn, _kTypePtr);
    _send(msg.build());
  }

  /// This device's own IPv4 address, best guess. A wrong guess here only
  /// costs a peer resolving us by our SOURCE address instead (see
  /// [_hostHint]) — the A record is a convenience, not the only path to one.
  InternetAddress? _localAddressCache;
  InternetAddress? get _localAddress => _localAddressCache;

  Future<void> _refreshLocalAddress() async {
    try {
      final ifs = await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLoopback: false);
      for (final i in ifs) {
        for (final a in i.addresses) {
          _localAddressCache = a;
          return;
        }
      }
    } catch (_) {
      // Left null; _sendAnnounce simply omits the A record.
    }
  }

  void _send(Uint8List bytes) {
    final s = _socket;
    if (s == null) return;
    try {
      s.send(bytes, InternetAddress(_kGroupV4), _kMdnsPort);
    } catch (e) {
      Log.w('sync', 'mDNS send failed: $e');
    }
  }
}

// ---------------------------------------------------------------------------
// The wire format: just enough of RFC 1035 (names, header) and RFC 1035 §3.4
// / RFC 2782 / RFC 6763 (A, SRV, TXT, PTR RDATA) to build and read the four
// record types above.
// ---------------------------------------------------------------------------

class _DnsQuestion {
  final String name;
  final int type;
  const _DnsQuestion(this.name, this.type);
}

class _ResourceRecord {
  final String name;
  final int type;
  final Uint8List rdata;
  _ResourceRecord(this.name, this.type, this.rdata);
  _ResourceRecord.empty()
      : name = '',
        type = 0,
        rdata = Uint8List(0);

  factory _ResourceRecord.ptr(String owner, String target) =>
      _ResourceRecord(owner, _kTypePtr, _encodeName(target));

  factory _ResourceRecord.srv(String owner, String target, int port) {
    final b = BytesBuilder();
    b.add(_u16(0)); // priority
    b.add(_u16(0)); // weight
    b.add(_u16(port));
    b.add(_encodeName(target));
    return _ResourceRecord(owner, _kTypeSrv, b.toBytes());
  }

  factory _ResourceRecord.txt(String owner, Map<String, String> kv) {
    final b = BytesBuilder();
    kv.forEach((k, v) {
      final s = utf8.encode('$k=$v');
      final chunk = s.length > 255 ? s.sublist(0, 255) : s;
      b.addByte(chunk.length);
      b.add(chunk);
    });
    if (kv.isEmpty) b.addByte(0);
    return _ResourceRecord(owner, _kTypeTxt, b.toBytes());
  }

  factory _ResourceRecord.a(String owner, InternetAddress? addr) {
    final bytes = addr?.rawAddress ??
        Uint8List.fromList(const [0, 0, 0, 0]);
    return _ResourceRecord(owner, _kTypeA, Uint8List.fromList(bytes));
  }

  // ---- typed readers, valid only for a record parsed off the wire --------
  // (RDATA here may reference offsets into the FULL message for name
  // compression, so these are only meaningful on records _DnsMessage.parse
  // produced, which stash the full message alongside.)

  String? ptrTarget;
  String? srvTarget;
  int? srvPort;
  Map<String, String>? txtEntries;
  InternetAddress? aAddress;
}

/// Builds one DNS/mDNS message: a header, questions, and answers (no
/// authority or additional section — everything this app sends fits in
/// answers, and a receiver that expects PTR-then-additional still accepts a
/// flatter layout; nothing in RFC 6762 requires the split on send).
class _DnsMessageBuilder {
  final bool isResponse;
  final List<_DnsQuestion> _questions = [];
  final List<_ResourceRecord> _answers = [];
  _DnsMessageBuilder({required this.isResponse});

  void addQuestion(String name, int type) =>
      _questions.add(_DnsQuestion(name, type));
  void addAnswer(_ResourceRecord r) => _answers.add(r);

  Uint8List build() {
    final b = BytesBuilder();
    b.add(_u16(0)); // ID: 0, as RFC 6762 §18.1 recommends for multicast
    b.add(_u16(isResponse ? 0x8400 : 0x0000)); // QR/AA, or a plain query
    b.add(_u16(_questions.length));
    b.add(_u16(isResponse ? _answers.length : 0));
    b.add(_u16(0));
    b.add(_u16(0));
    for (final q in _questions) {
      b.add(_encodeName(q.name));
      b.add(_u16(q.type));
      b.add(_u16(_kClassIn));
    }
    if (isResponse) {
      for (final r in _answers) {
        b.add(_encodeName(r.name));
        b.add(_u16(r.type));
        b.add(_u16(_kClassIn));
        b.add(_u32(120)); // TTL seconds — short-lived on purpose: a device
        // that goes offline should age out of a browser's cache in about the
        // time _sweep() in lan_sync.dart already uses for the beacon, not
        // linger for the RFC's own default of 75 minutes.
        b.add(_u16(r.rdata.length));
        b.add(r.rdata);
      }
    }
    return b.toBytes();
  }
}

Uint8List _u16(int v) => Uint8List(2)..buffer.asByteData().setUint16(0, v);
Uint8List _u32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v);

/// Encodes a dotted name as DNS labels, uncompressed. `\.` and `\\` inside a
/// label are unescaped first — RFC 6763 instance names may legitimately
/// contain a literal dot, escaped exactly that way — everything else in this
/// app's own names is base64url or ASCII and never needs it.
Uint8List _encodeName(String dotted) {
  final b = BytesBuilder();
  final labels = <String>[];
  final cur = StringBuffer();
  for (var i = 0; i < dotted.length; i++) {
    final c = dotted[i];
    if (c == '\\' && i + 1 < dotted.length) {
      cur.write(dotted[i + 1]);
      i++;
    } else if (c == '.') {
      if (cur.isNotEmpty) labels.add(cur.toString());
      cur.clear();
    } else {
      cur.write(c);
    }
  }
  if (cur.isNotEmpty) labels.add(cur.toString());
  for (final l in labels) {
    final enc = utf8.encode(l);
    b.addByte(enc.length.clamp(0, 63));
    b.add(enc.length > 63 ? enc.sublist(0, 63) : enc);
  }
  b.addByte(0);
  return b.toBytes();
}

class _DnsMessage {
  final bool isQuery;
  final List<_DnsQuestion> questions;
  final List<_ResourceRecord> answers;
  final List<_ResourceRecord> additional;
  final InternetAddress? sourceAddress;

  const _DnsMessage({
    required this.isQuery,
    required this.questions,
    required this.answers,
    required this.additional,
    this.sourceAddress,
  });

  static _DnsMessage? parse(Uint8List data, [InternetAddress? source]) {
    if (data.length < 12) return null;
    final bd = ByteData.sublistView(data);
    final flags = bd.getUint16(2);
    final qd = bd.getUint16(4);
    final an = bd.getUint16(6);
    final ns = bd.getUint16(8);
    final ar = bd.getUint16(10);
    var off = 12;

    final questions = <_DnsQuestion>[];
    for (var i = 0; i < qd; i++) {
      final (name, next) = _decodeName(data, off);
      if (next + 4 > data.length) return null;
      final type = bd.getUint16(next);
      off = next + 4; // type(2) + class(2)
      questions.add(_DnsQuestion(name, type));
    }

    List<_ResourceRecord> readRRs(int count) {
      final out = <_ResourceRecord>[];
      for (var i = 0; i < count; i++) {
        final (name, afterName) = _decodeName(data, off);
        if (afterName + 10 > data.length) return out;
        final type = bd.getUint16(afterName);
        final rdlen = bd.getUint16(afterName + 8);
        final rdataStart = afterName + 10;
        final rdataEnd = rdataStart + rdlen;
        if (rdataEnd > data.length) return out;
        final rr = _ResourceRecord(name, type,
            Uint8List.sublistView(data, rdataStart, rdataEnd));
        _decodeRdata(rr, data, rdataStart, type);
        out.add(rr);
        off = rdataEnd;
      }
      return out;
    }

    final answers = readRRs(an);
    readRRs(ns); // authority — not used, but must be walked to find offsets
    final additional = readRRs(ar);

    return _DnsMessage(
      isQuery: (flags & 0x8000) == 0,
      questions: questions,
      answers: answers,
      additional: additional,
      sourceAddress: source,
    );
  }

  static void _decodeRdata(
      _ResourceRecord rr, Uint8List data, int start, int type) {
    switch (type) {
      case _kTypePtr:
        rr.ptrTarget = _decodeName(data, start).$1;
        break;
      case _kTypeSrv:
        if (start + 6 > data.length) break;
        rr.srvPort = ByteData.sublistView(data).getUint16(start + 4);
        rr.srvTarget = _decodeName(data, start + 6).$1;
        break;
      case _kTypeTxt:
        final kv = <String, String>{};
        var p = start;
        final end = start + rr.rdata.length;
        while (p < end && p < data.length) {
          final len = data[p];
          p++;
          if (p + len > data.length || p + len > end) break;
          final entry = utf8.decode(data.sublist(p, p + len),
              allowMalformed: true);
          final eq = entry.indexOf('=');
          if (eq >= 0) {
            kv[entry.substring(0, eq)] = entry.substring(eq + 1);
          } else if (entry.isNotEmpty) {
            kv[entry] = '';
          }
          p += len;
        }
        rr.txtEntries = kv;
        break;
      case _kTypeA:
        if (start + 4 > data.length) break;
        rr.aAddress =
            InternetAddress.fromRawAddress(data.sublist(start, start + 4));
        break;
    }
  }
}

/// Decodes a (possibly compressed) DNS name starting at [start]. Returns the
/// dotted name and the offset just past the name AS IT APPEARED AT [start]
/// (i.e. past the first compression pointer, not past whatever it points
/// to) — which is the offset the caller must resume reading from, per
/// RFC 1035 §4.1.4.
(String, int) _decodeName(Uint8List data, int start) {
  final labels = <String>[];
  var pos = start;
  var end = -1; // where reading resumes, once a pointer is followed
  var jumps = 0;
  while (pos < data.length) {
    final len = data[pos];
    if (len == 0) {
      pos++;
      if (end < 0) end = pos;
      break;
    }
    if ((len & 0xC0) == 0xC0) {
      if (pos + 1 >= data.length) break;
      if (end < 0) end = pos + 2;
      if (++jumps > 64) break; // a malicious or corrupt loop, not a name
      pos = ((len & 0x3F) << 8) | data[pos + 1];
      continue;
    }
    pos++;
    if (pos + len > data.length) break;
    labels.add(utf8.decode(data.sublist(pos, pos + len), allowMalformed: true));
    pos += len;
  }
  return (labels.join('.'), end < 0 ? pos : end);
}
