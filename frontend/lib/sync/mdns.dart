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
  Timer? _burst;
  StreamSubscription<RawSocketEvent>? _sub;

  String? _deviceId;
  String? _deviceName;
  String? _fingerprint;
  int _version = 1;
  int _port = 0;
  void Function(SyncSighting)? _onSighting;

  /// False when port 5353 was taken and this device had to settle for asking
  /// from an ephemeral one. See [_bind].
  bool _canAnswer = true;

  /// One address per interface: what to advertise there, and — through
  /// `IP_MULTICAST_IF` — which way to send it. See [_sendEverywhere].
  List<InternetAddress> _outbound = const <InternetAddress>[];

  /// Interfaces the group has already been joined on, by name, so a network
  /// that appears while the app is running is joined exactly once.
  final Set<String> _joined = <String>{};

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

    if (!await _bind()) {
      Log.i('sync', 'mDNS: nothing would bind — no fallback discovery here');
      return;
    }

    await _refreshOutbound();
    Log.i(
        'sync',
        'mDNS up (pure-Dart fallback): $_serviceFqdn on $_port'
        '${_canAnswer ? "" : " — asking only, port 5353 is taken"}');
    // Announce right away — a browser that is already running should not
    // have to wait out its own query interval — and again shortly after,
    // which is the cheap way RFC 6762 recommends surviving a first packet
    // lost to an interface still coming up.
    _sendAnnounce();
    _sendQuery();
    // AND THEN KEEP ASKING, QUICKLY, FOR A WHILE. The steady cadence below is
    // a background heartbeat; the seconds right after launch are the ones
    // somebody is actually watching, having just typed a code into two
    // devices. Four extra rounds a second apart cost four small datagrams and
    // are the difference between "it paired" and "it sat there".
    var left = 4;
    _burst = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!running || left-- <= 0) {
        t.cancel();
        return;
      }
      _sendAnnounce();
      _sendQuery();
    });
    _announceTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _refreshOutbound().then((_) => _sendAnnounce());
    });
    _queryTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _sendQuery());
  }

  /// Opens the one receiving socket, on port 5353 if it can be had.
  ///
  /// ONE socket, bound to the wildcard, and not one per interface — which is
  /// the obvious way to reach every network and is wrong on two of the three
  /// platforms: a socket bound to a specific unicast address does not receive
  /// datagrams addressed to 224.0.0.251 at all on Linux or macOS. The
  /// interface is chosen per SEND instead (see [_sendEverywhere]), which is
  /// what `IP_MULTICAST_IF` is for.
  ///
  /// THE EPHEMERAL FALLBACK is not a nicety. On Windows, port 5353 is
  /// routinely held by Apple's own Bonjour service — installed by iTunes, by
  /// Adobe's tools, by anything that ships mDNSResponder.exe — and it does not
  /// always share. Binding elsewhere means this device can no longer be found
  /// (a responder ignores an answer that did not come from port 5353) but can
  /// still ASK, because a question carrying the unicast-reply bit is answered
  /// straight back to whatever port asked it. That leaves discovery one-way,
  /// and one-way is enough: `_maybeDial` in lan_sync.dart drops the
  /// lower-id-dials rule exactly when only one side can see the other.
  Future<bool> _bind() async {
    var s = await _open(_kMdnsPort);
    if (s != null) {
      _canAnswer = true;
    } else {
      s = await _open(0);
      _canAnswer = false;
    }
    if (s == null) return false;
    s.readEventsEnabled = true;
    s.multicastLoopback = true;
    _socket = s;
    _sub = s.listen(_onEvent, onError: (Object e) {
      Log.w('sync', 'mDNS socket stopped: $e');
    });
    return true;
  }

  Future<RawDatagramSocket?> _open(int port) async {
    try {
      return await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        port,
        reuseAddress: true,
        reusePort: !Platform.isWindows,
      );
    } catch (e) {
      if (port != 0) Log.i('sync', 'mDNS: could not bind :$port ($e)');
      return null;
    }
  }

  Future<void> stop() async {
    _announceTimer?.cancel();
    _queryTimer?.cancel();
    _burst?.cancel();
    _announceTimer = _queryTimer = _burst = null;
    await _sub?.cancel();
    _sub = null;
    _socket?.close();
    _socket = null;
    _joined.clear();
    _outbound = const <InternetAddress>[];
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
        _handle(dg.data, dg.address, dg.port);
      } catch (_) {
        // Malformed or irrelevant traffic. Not this device's problem.
      }
    }
  }

  void _handle(Uint8List data, InternetAddress source, int port) {
    final msg = _DnsMessage.parse(data, source, port);
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
    // An answer from a port other than 5353 is discarded by every responder
    // that receives it, this one included. Sending it anyway would be noise
    // on the wire and a misleading log line here.
    if (id == null || !_canAnswer) return;
    for (final q in msg.questions) {
      final name = q.name.toLowerCase();
      if (name == _serviceFqdn.toLowerCase() ||
          name == '${_instanceFqdn(id)}'.toLowerCase() ||
          name == '${_hostFqdn(id)}'.toLowerCase()) {
        _sendAnnounce();
        // AND STRAIGHT BACK TO THE ASKER when it asked for that (RFC 6762
        // §5.4). An iPad's browser sets the unicast-reply bit on its first
        // query, which is the one that decides whether a device appears the
        // moment sharing is switched on or a query round later. A directed
        // datagram also survives the multicast filtering some Wi-Fi access
        // points do to conserve airtime, which is otherwise invisible and
        // looks exactly like "it just doesn't find it".
        final to = msg.sourceAddress;
        if (q.unicastReply && to != null && msg.sourcePort > 0) {
          _answerTo(to, msg.sourcePort);
        }
        return;
      }
    }
  }

  /// The same record set as [_sendAnnounce], to one address.
  ///
  /// The A record carries the address of whichever interface can reach the
  /// asker — matched by /24, the same assumption lan_sync.dart's directed
  /// broadcast makes and for the same reason: Dart's NetworkInterface reports
  /// no netmask, and being wrong costs an A record the recipient can fall back
  /// from (it has our source address either way).
  void _answerTo(InternetAddress dest, int port) {
    final s = _socket;
    final id = _deviceId;
    if (s == null || id == null) return;
    final msg = mdnsAnnouncePacket(
      deviceId: id,
      deviceName: _deviceName ?? '?',
      fingerprint: _fingerprint ?? '',
      version: _version,
      port: _port,
      self: _nearest(dest),
    );
    try {
      s.send(msg, dest, port);
    } catch (e) {
      Log.i('sync', 'mDNS: could not answer ${dest.address} directly: $e');
    }
  }

  /// This device's address on the same /24 as [dest], or its first if none
  /// matches.
  InternetAddress? _nearest(InternetAddress dest) {
    if (_outbound.isEmpty) return null;
    final want = _prefix24(dest.address);
    for (final a in _outbound) {
      if (_prefix24(a.address) == want) return a;
    }
    return _outbound.first;
  }

  static String _prefix24(String a) {
    final dot = a.lastIndexOf('.');
    return dot <= 0 ? a : a.substring(0, dot);
  }

  void _maybeSight(_DnsMessage msg) {
    final myFp = _fingerprint;
    if (myFp == null) return;
    final s = _sightingFrom(msg, fingerprint: myFp, selfId: _deviceId ?? '');
    if (s != null) _onSighting?.call(s);
  }

  String _instanceFqdn(String id) => '$id.$_serviceFqdn';
  String _hostFqdn(String id) => '$id.$_kDomain';

  void _sendAnnounce() {
    final id = _deviceId;
    if (_socket == null || id == null || !_canAnswer) return;
    _sendEverywhere((self) => mdnsAnnouncePacket(
          deviceId: id,
          deviceName: _deviceName ?? '?',
          fingerprint: _fingerprint ?? '',
          version: _version,
          port: _port,
          self: self,
        ));
  }

  /// Asks who else is out there — with the unicast-reply bit set, always.
  ///
  /// TWO REASONS, and the second is the one that matters on Windows.
  ///
  /// A device that could not get port 5353 (see [_bind]) would never hear a
  /// multicast answer at all: the answer goes to :5353, which is precisely
  /// the port it does not have. For that device QU is not an optimisation, it
  /// is the only way an answer can arrive.
  ///
  /// And on a machine with the Windows firewall in its default state — every
  /// machine, until somebody changes it — INBOUND MULTICAST IS DROPPED. What
  /// is not dropped is a unicast reply to a multicast this machine itself
  /// just sent: the firewall keeps that hole open for a few seconds after
  /// each outbound datagram, which is exactly the shape of a query and its
  /// answer. So a QU query is answered through a firewall that a plain one is
  /// silently swallowed behind. "It never finds the iPad" is what that looks
  /// like from the front, and nothing in the app can see it happen.
  ///
  /// The cost is the one RFC 6762 §5.4 warns about: other browsers on the
  /// network do not get to overhear the answer and fill their caches from it.
  /// For one private service type that nothing else on the LAN has any use
  /// for, that is not a cost at all.
  void _sendQuery() {
    if (_socket == null) return;
    final msg = mdnsQueryPacket();
    _sendEverywhere((_) => msg);
  }

  /// Sends one message out EVERY interface, built afresh for each.
  ///
  /// A socket bound to 0.0.0.0 sends multicast out the default route and
  /// nowhere else. On a Windows machine that route is very often a virtual
  /// adapter — Hyper-V, WSL, VMware, a VPN client, any of which installs one
  /// — so the announcement leaves by a network with nothing on it while the
  /// Wi-Fi the iPad is actually on hears nothing at all. That is not an edge
  /// case; it is most development machines and a good many ordinary ones.
  /// lan_sync.dart's beacon already sends a directed broadcast per interface
  /// for this exact reason. `IP_MULTICAST_IF` is the multicast equivalent.
  ///
  /// The message is rebuilt per interface because the A record differs: each
  /// copy advertises the address of the interface it goes out of, which is by
  /// construction the address reachable from that network. The old single
  /// build advertised whichever address the OS happened to list first — on
  /// the same Windows machine, the 172.x address of a virtual switch that no
  /// iPad can reach.
  void _sendEverywhere(Uint8List Function(InternetAddress? self) build) {
    final s = _socket;
    if (s == null) return;
    if (_outbound.isEmpty) {
      _sendOne(s, build(null));
      return;
    }
    for (final self in _outbound) {
      _selectInterface(s, self);
      _sendOne(s, build(self));
    }
  }

  void _selectInterface(RawDatagramSocket s, InternetAddress self) {
    try {
      s.setRawOption(RawSocketOption(RawSocketOption.levelIPv4,
          RawSocketOption.IPv4MulticastInterface, self.rawAddress));
    } catch (_) {
      // Not every stack lets this change after the bind, and a refusal is not
      // worth a log line per datagram: the send below still happens, out the
      // default route, which is what every send used to do.
    }
  }

  void _sendOne(RawDatagramSocket s, Uint8List bytes) {
    try {
      s.send(bytes, InternetAddress(_kGroupV4), _kMdnsPort);
    } catch (e) {
      // One interface refusing (a link that just went down, a VPN adapter in
      // a state of its own) must not stop the others.
      Log.i('sync', 'mDNS send failed: $e');
    }
  }

  /// Re-reads the interfaces, and joins the group on any that are new.
  ///
  /// Called on start and every thirty seconds, so joining a different Wi-Fi
  /// network — or a laptop waking on a different one — starts being announced
  /// on it without anything having to be restarted.
  Future<void> _refreshOutbound() async {
    final s = _socket;
    List<NetworkInterface>? ifs;
    try {
      ifs = await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLoopback: false);
    } catch (e) {
      // The list is UNKNOWN, which is not the same as empty — an empty list
      // means every link is down and the announcements should stop, while a
      // refusal to enumerate means the last known list is still the best guess
      // there is. Only the first of those replaces what is held.
      Log.i('sync', 'mDNS: could not list the interfaces: $e');
    }
    final out = <InternetAddress>[];
    for (final i in ifs ?? const <NetworkInterface>[]) {
      for (final a in i.addresses) {
        out.add(a);
      }
      if (s != null && _joined.add(i.name)) {
        try {
          s.joinMulticast(InternetAddress(_kGroupV4), i);
        } catch (e) {
          // Some sandboxes and some adapters refuse a join; queries still go
          // out and this device can still be found by anyone who does hear
          // multicast, even if it cannot itself.
          _joined.remove(i.name);
          Log.i('sync', 'mDNS: no multicast on ${i.name}: $e');
        }
      }
    }
    if (ifs != null) {
      if (out.length != _outbound.length) {
        Log.i('sync', 'mDNS: announcing on ${out.length} interface(s)');
      }
      _outbound = out;
    }
    // AND A JOIN THAT NAMES NO INTERFACE, if none of them would take one.
    // Joining per interface is what makes a machine with several of them hear
    // all of them; joining at all is what makes it hear anything. An
    // interface list that came back empty, or every join refused, would
    // otherwise leave this socket in the group's port and not in the group —
    // receiving nothing, silently, for ever.
    if (s != null && _joined.isEmpty) {
      try {
        s.joinMulticast(InternetAddress(_kGroupV4));
        _joined.add('*');
        Log.i('sync', 'mDNS: joined the group on the default interface');
      } catch (e) {
        Log.i('sync', 'mDNS: could not join the multicast group at all: $e');
      }
    }
  }
}

// ---------------------------------------------------------------------------
// WHAT GOES ON THE WIRE, as three pure functions.
//
// Separated from [MdnsFallback] because they are the half that can be wrong
// silently. A mistake in when to send costs a round trip; a mistake in WHAT is
// sent means an iPad quietly never sees a device, on somebody else's network,
// where nothing can be attached to it. These take arguments and return bytes,
// so they can be driven from a test with no socket and no permission.
// ---------------------------------------------------------------------------

/// The browse question: "who is offering `_prototypesync._tcp`?"
///
/// Always with the unicast-reply bit — see [MdnsFallback._sendQuery] for the
/// two reasons, the second of which is the Windows firewall.
Uint8List mdnsQueryPacket() =>
    (_DnsMessageBuilder(isResponse: false)
          ..addQuestion(_serviceFqdn, _kTypePtr, unicastReply: true))
        .build();

/// This device's own record set: PTR, SRV, TXT and (when [self] is known) A.
///
/// [self] is the address to advertise, which is the address of the interface
/// this copy is going out of — see [MdnsFallback._sendEverywhere]. Null omits
/// nothing: [_ResourceRecord.a] writes 0.0.0.0, which the receiver rejects as
/// unusable and falls back from to the packet's source address.
Uint8List mdnsAnnouncePacket({
  required String deviceId,
  required String deviceName,
  required String fingerprint,
  required int version,
  required int port,
  InternetAddress? self,
}) {
  final instance = '$deviceId.$_serviceFqdn';
  final host = '$deviceId.$_kDomain';
  return (_DnsMessageBuilder(isResponse: true)
        ..addAnswer(_ResourceRecord.ptr(_serviceFqdn, instance))
        ..addAnswer(_ResourceRecord.srv(instance, host, port))
        ..addAnswer(_ResourceRecord.txt(instance, <String, String>{
          'id': deviceId,
          'n': deviceName,
          'fp': fingerprint,
          'v': '$version',
        }))
        ..addAnswer(_ResourceRecord.a(host, self)))
      .build();
}

/// Reads one packet's worth of bytes as a sighting of another device, or null
/// for every packet that is not one — which on a real network is nearly all of
/// them, since this socket hears every printer and television on the LAN.
///
/// [source] is where the datagram came from, used when the sender's A record
/// is missing or unusable.
SyncSighting? mdnsSightingFromPacket(
  Uint8List data, {
  required String fingerprint,
  String selfId = '',
  InternetAddress? source,
}) {
  final msg = _DnsMessage.parse(data, source);
  if (msg == null || msg.isQuery) return null;
  return _sightingFrom(msg, fingerprint: fingerprint, selfId: selfId);
}

/// An answer naming OUR service type: pull out the instance's SRV (host +
/// port) and TXT (id/name/fingerprint/version), resolve the host to an
/// address from the same packet's A record where present, and report a
/// sighting once both halves are in hand.
SyncSighting? _sightingFrom(
  _DnsMessage msg, {
  required String fingerprint,
  required String selfId,
}) {
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
  // No PTR in THIS packet is normal — an unsolicited announce and a query's
  // reply both repeat the SRV/TXT even when only the PTR was asked for, but a
  // peer that sent SRV/TXT/A alone (answering a direct SRV question) has no
  // PTR to find. Fall back to any SRV whose owner name is under our service
  // type.
  if (instanceName == null) {
    final anySrv = records.firstWhere(
      (r) => r.type == _kTypeSrv &&
          r.name.toLowerCase().endsWith('.${_serviceFqdn.toLowerCase()}'),
      orElse: () => _ResourceRecord.empty(),
    );
    if (anySrv.name.isEmpty) return null;
    instanceName = anySrv.name;
  }

  _ResourceRecord? srv, txt, a;
  for (final r in records) {
    final owner = r.name.toLowerCase();
    if (r.type == _kTypeSrv && owner == instanceName.toLowerCase()) srv = r;
    if (r.type == _kTypeTxt && owner == instanceName.toLowerCase()) txt = r;
  }
  if (srv == null) return null;
  final target = srv.srvTarget?.toLowerCase();
  if (target != null) {
    for (final r in records) {
      if (r.type == _kTypeA && r.name.toLowerCase() == target) a = r;
    }
  }
  // THE SOURCE ADDRESS WINS over an unroutable A record. A device with more
  // than one interface may advertise the wrong one of its addresses — this
  // app did, until _sendEverywhere — and the address a packet actually
  // arrived from is the one demonstrably able to reach this machine.
  final advertised = a?.aAddress?.address;
  final hinted = msg.sourceAddress?.address;
  final host = _usableAddress(advertised) ? advertised : hinted;
  // AND NO SIGHTING AT ALL rather than one that cannot be dialled. A peer
  // reported at 0.0.0.0 takes a slot in the peer map, fails to connect, is
  // retried on every sweep and logs a refusal each time — a worse outcome
  // than never having heard it, and the only thing it can ever produce.
  if (host == null || host.isEmpty || host == '0.0.0.0') return null;

  final kv = txt?.txtEntries ?? const <String, String>{};
  final fp = kv['fp'] ?? '';
  if (fp != fingerprint) return null; // a different group, or another service
  final id = kv['id'] ?? '';
  if (id.isEmpty || id == selfId) return null; // our own announce, come back
  return SyncSighting(
    id: id,
    name: kv['n'] ?? '?',
    host: host,
    port: srv.srvPort ?? 0,
    fingerprint: fp,
    version: int.tryParse(kv['v'] ?? '') ?? 0,
  );
}

/// Whether an advertised address is worth PREFERRING to the address the
/// packet arrived from. `0.0.0.0` is what [_ResourceRecord.a] writes when the
/// sender could not work out its own address, and a loopback address is right
/// only for the machine that sent it — in both cases the source address, which
/// demonstrably reached this machine, is the better answer.
bool _usableAddress(String? a) =>
    a != null && a.isNotEmpty && a != '0.0.0.0' && !a.startsWith('127.');

// ---------------------------------------------------------------------------
// The wire format: just enough of RFC 1035 (names, header) and RFC 1035 §3.4
// / RFC 2782 / RFC 6763 (A, SRV, TXT, PTR RDATA) to build and read the four
// record types above.
// ---------------------------------------------------------------------------

class _DnsQuestion {
  final String name;
  final int type;

  /// RFC 6762 §5.4: the top bit of QCLASS on a question asks for the answer
  /// UNICAST, straight back to the asker's own address and port, rather than
  /// multicast to :5353. Set only by a device that could not have port 5353,
  /// which would otherwise never hear the reply to its own question.
  final bool unicastReply;

  const _DnsQuestion(this.name, this.type, {this.unicastReply = false});
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

  void addQuestion(String name, int type, {bool unicastReply = false}) =>
      _questions.add(_DnsQuestion(name, type, unicastReply: unicastReply));
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
      b.add(_u16(q.unicastReply ? (_kClassIn | 0x8000) : _kClassIn));
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
  final int sourcePort;

  const _DnsMessage({
    required this.isQuery,
    required this.questions,
    required this.answers,
    required this.additional,
    this.sourceAddress,
    this.sourcePort = 0,
  });

  static _DnsMessage? parse(Uint8List data,
      [InternetAddress? source, int sourcePort = 0]) {
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
      final qclass = bd.getUint16(next + 2);
      off = next + 4; // type(2) + class(2)
      questions.add(_DnsQuestion(name, type,
          unicastReply: (qclass & 0x8000) != 0));
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
      sourcePort: sourcePort,
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
