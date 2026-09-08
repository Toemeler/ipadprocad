// M176 — one document, one file.
//
// A part used to be a FOLDER: a .part.json beside a sketches/ directory, a
// preview PNG and an imports/ tree. That is invisible plumbing on a desktop
// and hostile on an iPad, where a document is something you move, rename,
// AirDrop and put in a folder. You cannot do any of that with a directory
// that only this app knows how to reassemble.
//
// So: two file types, mirroring Inventor's three-letter convention.
//   .ptp — Prototype Part     (Inventor's .ipt)
//   .pts — Prototype Sketch   (Inventor's .idw)
//   .pas — Prototype Assembly (Inventor's .iam)  — M240
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
import 'dart:math' as math;
import 'dart:typed_data';

/// File extension for a 3D part document.
const String kPartExt = 'ptp';

/// File extension for a standalone 2D sketch document.
const String kSketchExt = 'pts';

/// File extension for an assembly document (M240).
const String kAsmExt = 'pas';

/// The `kind` string an assembly carries — in its container header, in its
/// [DocRef] and in the gallery. Spelled ONCE, here in the leaf file both the
/// document layer and the assembly model can reach without importing each
/// other.
const String kAssemblyDocKind = 'assembly';

/// Every document extension this app writes, in the order the gallery scans
/// them. A single list, so adding a fourth kind cannot leave one scanner
/// behind — which is exactly what the assembly nearly did to [docNameOf].
const List<String> kDocExtensions = [kPartExt, kSketchExt, kAsmExt];

/// The extension a document of [kind] is stored in. Unknown kinds fall back to
/// a part, matching [DocFile.decode]'s own default.
String extForKind(String kind) => switch (kind) {
      'sketch' => kSketchExt,
      kAssemblyDocKind => kAsmExt,
      _ => kPartExt,
    };

/// M390 — an entry name, in the one spelling a document may carry.
///
/// Entry names are POSIX-relative and always have been ("`sketches/Sketch1.dxf`
/// stays `sketches/Sketch1.dxf`"). On Windows they were not, and nothing said
/// so until the gallery went blank.
///
/// `packDir` derives the name by slicing the staging folder's path off the
/// front of each file's path. `Directory.listSync` joins the two with the
/// PLATFORM separator — dart:io appends one itself before it calls the native
/// lister (`FileSystemEntity._ensureTrailingPathSeparators`), and on Windows
/// that is a backslash — so a stage at `C:/…/docs/Bracket` yields
/// `C:/…/docs/Bracket\preview.png`, and the slice came back as
/// `\preview.png`. Every document ever written by the Windows build carries
/// its entries under names like that.
///
/// What that cost, in the order it was noticed:
///
///   * `readDocEntry(path, 'preview.png')` matched nothing, so the gallery had
///     no thumbnail for any document whose extracted copy was not still in the
///     cache — which is every document that arrived over sync, every document
///     after a cache drop, and every document on a fresh install. The cards
///     fell back to the cube glyph. That is the report;
///   * `readDocMeta` was equally blind, and
///   * `unpackDoc` dropped the entries outright: `_safeRelative` rejects any
///     name containing a backslash, and it is right to — a document is a file
///     people send each other, and `..\..\x` must not escape. So reopening a
///     Windows-written document in a later session, on any platform, unpacked
///     an EMPTY staging folder.
///
/// The last one never bit only because `_commitStage` marks a document staged
/// as it saves, so the session that wrote it keeps working from the warm stage.
///
/// This is applied on both sides. Writing it makes new documents portable;
/// reading it makes the ones already on disk readable again, without a
/// migration and without rewriting a single file.
String docEntryName(String raw) {
  var s = raw.replaceAll('\\', '/');
  while (s.startsWith('/')) {
    s = s.substring(1);
  }
  return s;
}

const List<int> _magic = [0x50, 0x52, 0x4F, 0x54, 0x4F, 0x76, 0x31, 0x0A];

/// One document, read or ready to write. [entries] maps a name to its raw
/// bytes; [kind] is 'part', 'sketch' or 'assembly'.
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
        // Normalised on READ, which is what repairs the documents already on
        // disk. See [docEntryName].
        out[docEntryName(n)] = Uint8List.sublistView(bytes, base + o, base + o + l);
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
  // M390 — BOTH separators. A file chosen from the Windows picker arrives as
  // `C:\Users\t\Desktop\Bracket.ptp`, which has no forward slash in it at
  // all, so the "file name" was the whole path: the gallery would have shown a
  // document called `C:\Users\t\Desktop\Bracket`, and `adoptDocument` would
  // have tried to write that name into the app folder as a file.
  final slash = math.max(path.lastIndexOf('/'), path.lastIndexOf('\\'));
  final file = slash < 0 ? path : path.substring(slash + 1);
  for (final ext in kDocExtensions) {
    if (file.toLowerCase().endsWith('.$ext')) {
      return file.substring(0, file.length - ext.length - 1);
    }
  }
  return null;
}

/// True when [path] is a part document (rather than a sketch).
bool isPartPath(String path) => path.toLowerCase().endsWith('.$kPartExt');

/// True when [path] is an assembly document (M240).
bool isAssemblyPath(String path) => path.toLowerCase().endsWith('.$kAsmExt');
