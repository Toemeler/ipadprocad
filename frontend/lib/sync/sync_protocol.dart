// Prototype — the wire between two devices sharing a code.
//
// One frame shape for everything, because the alternative — a text protocol
// for the small messages and something else for the file bodies — is two
// parsers and one of them is always the one with the bug.
//
//   [4 bytes  header length, big-endian]
//   [n bytes  UTF-8 JSON header]
//   [m bytes  raw payload, present iff the header has "bytes": m]
//
// The header always carries "t" (the type). Everything else is per type, and
// unknown keys are ignored on purpose: a newer peer must be able to add a
// field without an older one refusing the frame.
//
// WHY NOT WEBSOCKETS, which Dart also has. Because this is a file mirror on a
// LAN and a WebSocket would add a HTTP upgrade, a masking layer and a
// fragmentation scheme in front of a socket that is already point-to-point and
// already framed. The four bytes above are the whole of what was needed.
import 'dart:convert';
import 'dart:typed_data';

/// The protocol's own version, sent in the beacon and the handshake.
///
/// Bumped when a change would make an older peer misread a frame rather than
/// merely miss a field. Two devices at different versions refuse each other
/// with a message that says so, which is a better failure than a half-mirror.
const int kSyncProtocolVersion = 1;

/// The UDP port devices announce themselves on, and the default TCP port.
///
/// Above the registered range and not one anything common claims. The TCP
/// listener takes the first free port from this one upward, and says which in
/// its beacon, so two copies of the app on ONE machine still pair — which is
/// exactly how this gets tested.
const int kSyncBeaconPort = 47820;
const int kSyncFirstDataPort = 47821;

/// Frame types.
class SyncMsg {
  /// Server -> client, first: "here is a nonce, prove you know the code".
  static const String hello = 'hello';

  /// Client -> server: the proof, and a nonce of its own.
  static const String auth = 'auth';

  /// Server -> client: its own proof. Both sides are now satisfied.
  static const String ready = 'ready';

  /// Either way: everything I have, so you can tell me what you want.
  static const String manifest = 'manifest';

  /// Either way: send me these.
  static const String want = 'want';

  /// Either way: here is one, with its bytes.
  static const String file = 'file';

  /// Either way: this one just changed on me — sent live, without a manifest.
  static const String changed = 'changed';

  /// Either way, on refusal. Carries "why" for the log.
  static const String bye = 'bye';
}

/// One frame, as read or as written.
class SyncFrame {
  final Map<String, Object?> header;
  final Uint8List? payload;

  const SyncFrame(this.header, [this.payload]);

  String get type => '${header['t']}';

  Uint8List encode() {
    final h = Map<String, Object?>.of(header);
    if (payload != null) h['bytes'] = payload!.length;
    final hb = utf8.encode(jsonEncode(h));
    final out = BytesBuilder(copy: false);
    final len = ByteData(4)..setUint32(0, hb.length);
    out.add(len.buffer.asUint8List());
    out.add(hb);
    if (payload != null) out.add(payload!);
    return out.takeBytes();
  }
}

/// Turns a byte stream into frames.
///
/// A StreamTransformer rather than a loop over `await for`: a socket hands out
/// whatever arrived, which is never the same shape as what was sent, and every
/// bug in a protocol like this one is a reassembly bug. Keeping the buffering
/// in one place with one test is what stops that.
class SyncFrameReader {
  /// The largest header this will assemble. A header is a few hundred bytes;
  /// anything near a megabyte is a peer that is confused or hostile, and
  /// buffering it is how a mirror becomes an out-of-memory crash.
  static const int maxHeader = 1 << 20;

  /// The largest single file body. Documents are megabytes, not gigabytes.
  static const int maxPayload = 256 << 20;

  final BytesBuilder _buf = BytesBuilder(copy: false);
  int _have = 0;

  /// Feeds bytes in; returns whatever complete frames they finished.
  ///
  /// Throws [FormatException] on a frame that cannot be honoured, which the
  /// session turns into a disconnect: there is no way to resynchronise a
  /// length-prefixed stream once a length is wrong.
  List<SyncFrame> add(List<int> data) {
    _buf.add(data);
    _have += data.length;
    final out = <SyncFrame>[];
    while (true) {
      if (_have < 4) break;
      final bytes = _peek();
      final hlen = ByteData.sublistView(bytes, 0, 4).getUint32(0);
      if (hlen == 0 || hlen > maxHeader) {
        throw FormatException('header length $hlen');
      }
      if (bytes.length < 4 + hlen) break;
      final header = jsonDecode(utf8.decode(bytes.sublist(4, 4 + hlen)));
      if (header is! Map) throw const FormatException('header is not an object');
      final plen = (header['bytes'] as num?)?.toInt() ?? 0;
      if (plen < 0 || plen > maxPayload) {
        throw FormatException('payload length $plen');
      }
      final total = 4 + hlen + plen;
      if (bytes.length < total) break;
      out.add(SyncFrame(
        <String, Object?>{for (final e in header.entries) '${e.key}': e.value},
        plen == 0 ? null : Uint8List.sublistView(bytes, 4 + hlen, total),
      ));
      _reset(bytes.sublist(total));
    }
    return out;
  }

  Uint8List _peek() {
    final b = _buf.toBytes();
    _buf
      ..clear()
      ..add(b);
    return b;
  }

  void _reset(Uint8List rest) {
    _buf
      ..clear()
      ..add(rest);
    _have = rest.length;
  }
}
