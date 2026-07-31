// M176 — one document, one file.
//
// A part used to be a FOLDER: a .part.json beside a sketches/ directory, a
// preview PNG and an imports/ tree. That is invisible plumbing on a desktop
// and hostile on an iPad, where a document is something you move, rename,
// AirDrop and put in a folder. You cannot do any of that with a directory
// that only this app knows how to reassemble.
//
// So: two file types, mirroring Inventor's three-letter convention.
//   .ptp — Prototype Part    (Inventor's .ipt)
//   .pts — Prototype Sketch  (Inventor's .idw)
//
// The container is deliberately the simplest thing that opens fast:
//
//   magic  8 bytes  "PROTOv1\n"
//   u32    little-endian length of the index
//   index  UTF-8 JSON: {"kind":"part","entries":[{"n":..,"o":..,"l":..}]}
//   blobs  raw bytes, concatenated, in index order
//
// Opening reads the header and parses a few hundred bytes of JSON; the
// payload is never scanned, decoded or re-encoded to get at the metadata.
// Entries are raw — a DXF stays a DXF, a PNG stays a PNG — so nothing is
// base64'd, which is the usual reason single-file formats become slow.
//
// No new dependency. A zip would have been the other obvious answer and
// costs an archive package plus a compressor on the UI thread for files that
// are already small and mostly text.
import 'dart:convert';
import 'dart:typed_data';

/// File extension for a 3D part document.
const String kPartExt = 'ptp';

/// File extension for a standalone 2D sketch document.
const String kSketchExt = 'pts';

const List<int> _magic = [0x50, 0x52, 0x4F, 0x54, 0x4F, 0x76, 0x31, 0x0A];

/// One document, read or ready to write. [entries] maps a name to its raw
/// bytes; [kind] is 'part' or 'sketch'.
class DocFile {
  final String kind;
  final Map<String, Uint8List> entries;
  const DocFile(this.kind, this.entries);

  /// The JSON entry every document has, decoded. Null when absent or corrupt —
  /// a damaged file must not throw its way out of a gallery listing.
  Map<String, dynamic>? get meta {
    final b = entries['meta.json'];
    if (b == null) return null;
    try {
      final v = jsonDecode(utf8.decode(b));
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }

  String? textOf(String name) {
    final b = entries[name];
    return b == null ? null : utf8.decode(b, allowMalformed: true);
  }

  Uint8List encode() {
    final names = entries.keys.toList()..sort();
    final index = <Map<String, dynamic>>[];
    var offset = 0;
    for (final n in names) {
      final len = entries[n]!.length;
      index.add({'n': n, 'o': offset, 'l': len});
      offset += len;
    }
    final header =
        utf8.encode(jsonEncode({'v': 1, 'kind': kind, 'entries': index}));
    final out = BytesBuilder(copy: false);
    out.add(_magic);
    final lenBytes = ByteData(4)..setUint32(0, header.length, Endian.little);
    out.add(lenBytes.buffer.asUint8List());
    out.add(header);
    for (final n in names) {
      out.add(entries[n]!);
    }
    return out.takeBytes();
  }

  /// Parses [bytes], or null when this is not one of our documents.
  ///
  /// Never throws: a truncated or foreign file has to be REPORTED, not crash
  /// the gallery that is merely listing it.
  static DocFile? decode(Uint8List bytes) {
    try {
      if (bytes.length < _magic.length + 4) return null;
      for (var i = 0; i < _magic.length; i++) {
        if (bytes[i] != _magic[i]) return null;
      }
      final hlen = ByteData.sublistView(bytes, _magic.length, _magic.length + 4)
          .getUint32(0, Endian.little);
      final hStart = _magic.length + 4;
      if (hlen < 0 || hStart + hlen > bytes.length) return null;
      final head = jsonDecode(utf8.decode(bytes.sublist(hStart, hStart + hlen)));
      if (head is! Map) return null;
      final base = hStart + hlen;
      final out = <String, Uint8List>{};
      for (final e in (head['entries'] as List? ?? const [])) {
        if (e is! Map) continue;
        final n = e['n'] as String?;
        final o = (e['o'] as num?)?.toInt();
        final l = (e['l'] as num?)?.toInt();
        if (n == null || o == null || l == null || o < 0 || l < 0) continue;
        // A lying index must truncate, not read past the buffer.
        if (base + o + l > bytes.length) continue;
        out[n] = Uint8List.sublistView(bytes, base + o, base + o + l);
      }
      return DocFile(head['kind'] as String? ?? 'part', out);
    } catch (_) {
      return null;
    }
  }
}

/// The document name a file path carries, without its extension, or null when
/// the extension is not one of ours.
String? docNameOf(String path) {
  final slash = path.lastIndexOf('/');
  final file = slash < 0 ? path : path.substring(slash + 1);
  for (final ext in const [kPartExt, kSketchExt]) {
    if (file.toLowerCase().endsWith('.$ext')) {
      return file.substring(0, file.length - ext.length - 1);
    }
  }
  return null;
}

/// True when [path] is a part document (rather than a sketch).
bool isPartPath(String path) => path.toLowerCase().endsWith('.$kPartExt');
