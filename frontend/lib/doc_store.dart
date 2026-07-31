// M177 — reading and writing the single-file documents.
//
// The save and load code for a part is large, old and correct: DXF through the
// FFI engine (which needs a real path on disk), a dozen JSON sidecars, a
// preview PNG, imported STEP files. Rewriting all of it to serialise into a
// byte map would be the obvious way to get one file per document, and it would
// put every one of those formats at risk at once.
//
// So the document file is a PACKED DIRECTORY instead. Save renders the part
// into a private staging folder with exactly the layout the existing writers
// already produce, then packs that folder into one .ptp. Open reverses it.
// The readers and writers never learn that anything changed, the engine still
// gets a real file path for its DXF, and the thing the user moves around is a
// single file.
//
// The staging folder is a CACHE. It lives in a dot-directory the gallery never
// scans, is rebuilt from the document whenever it is missing, and can be
// deleted at any time without losing anything.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'doc_file.dart';

/// One entry in a document's index, as read from the header alone.
class DocEntryRef {
  final String name;
  final int offset;
  final int length;
  const DocEntryRef(this.name, this.offset, this.length);
}

/// A document's header: what is inside, and where, without reading any of it.
class DocHeader {
  final String kind;
  final List<DocEntryRef> entries;

  /// Byte offset where the blobs start.
  final int base;
  const DocHeader(this.kind, this.entries, this.base);

  DocEntryRef? entry(String name) {
    for (final e in entries) {
      if (e.name == name) return e;
    }
    return null;
  }
}

const List<int> _magic = [0x50, 0x52, 0x4F, 0x54, 0x4F, 0x76, 0x31, 0x0A];

/// Reads only the header of [path].
///
/// This is what the gallery uses. Listing twenty parts must not mean reading
/// twenty whole documents, so the index is parsed from the first few hundred
/// bytes and the payload is never touched.
DocHeader? readDocHeader(String path) {
  RandomAccessFile? raf;
  try {
    final f = File(path);
    if (!f.existsSync()) return null;
    raf = f.openSync();
    final head = raf.readSync(_magic.length + 4);
    if (head.length < _magic.length + 4) return null;
    for (var i = 0; i < _magic.length; i++) {
      if (head[i] != _magic[i]) return null;
    }
    final hlen =
        ByteData.sublistView(head, _magic.length).getUint32(0, Endian.little);
    if (hlen <= 0 || hlen > 1 << 24) return null;
    final json = jsonDecode(utf8.decode(raf.readSync(hlen)));
    if (json is! Map) return null;
    final out = <DocEntryRef>[];
    for (final e in (json['entries'] as List? ?? const [])) {
      if (e is! Map) continue;
      final n = e['n'] as String?;
      final o = (e['o'] as num?)?.toInt();
      final l = (e['l'] as num?)?.toInt();
      if (n == null || o == null || l == null || o < 0 || l < 0) continue;
      out.add(DocEntryRef(n, o, l));
    }
    return DocHeader(
        json['kind'] as String? ?? 'part', out, _magic.length + 4 + hlen);
  } catch (_) {
    return null;
  } finally {
    try {
      raf?.closeSync();
    } catch (_) {}
  }
}

/// Reads one entry out of [path] without decoding the rest.
Uint8List? readDocEntry(String path, String entryName, {DocHeader? header}) {
  final h = header ?? readDocHeader(path);
  final e = h?.entry(entryName);
  if (h == null || e == null) return null;
  if (e.length == 0) return Uint8List(0);
  RandomAccessFile? raf;
  try {
    raf = File(path).openSync();
    raf.setPositionSync(h.base + e.offset);
    final b = raf.readSync(e.length);
    return b.length == e.length ? b : null;
  } catch (_) {
    return null;
  } finally {
    try {
      raf?.closeSync();
    } catch (_) {}
  }
}

/// The decoded meta.json of [path], or null. Header + one blob, nothing else.
Map<String, dynamic>? readDocMeta(String path) {
  final b = readDocEntry(path, kMetaEntry);
  if (b == null) return null;
  try {
    final v = jsonDecode(utf8.decode(b));
    return v is Map<String, dynamic> ? v : null;
  } catch (_) {
    return null;
  }
}

/// The entry every document carries: the model JSON.
const String kMetaEntry = 'meta.json';

/// The gallery thumbnail, when the document has one.
const String kPreviewEntry = 'preview.png';

/// Packs everything under [dir] into a document.
///
/// Entry names are POSIX-relative to [dir], so `sketches/Sketch1.dxf` stays
/// `sketches/Sketch1.dxf` and [unpackDoc] can put it back where the readers
/// expect it. Files are read in sorted order so the same folder always packs
/// to the same bytes — a document that has not changed should not look changed
/// to a sync service.
DocFile packDir(Directory dir, String kind) {
  final entries = <String, Uint8List>{};
  if (dir.existsSync()) {
    final files = dir.listSync(recursive: true).whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files) {
      var rel = f.path.substring(dir.path.length);
      while (rel.startsWith('/')) {
        rel = rel.substring(1);
      }
      if (rel.isEmpty) continue;
      try {
        entries[rel] = f.readAsBytesSync();
      } catch (_) {
        // An unreadable file is skipped rather than aborting the save: losing
        // one sidecar is recoverable, losing the whole save is not.
      }
    }
  }
  return DocFile(kind, entries);
}

/// Writes [doc] to [path], replacing whatever is there.
///
/// Written to a sibling temp file and renamed, so an interrupted save cannot
/// leave a half-written document where a working one used to be. If the
/// sibling cannot be created — an external folder that permits replacing a
/// file but not creating one — the direct write is the fallback, because
/// refusing to save at all would be worse.
bool writeDoc(String path, DocFile doc) {
  final bytes = doc.encode();
  final tmp = File('$path.tmp');
  try {
    tmp.parent.createSync(recursive: true);
    tmp.writeAsBytesSync(bytes, flush: true);
    tmp.renameSync(path);
    return true;
  } catch (_) {
    try {
      if (tmp.existsSync()) tmp.deleteSync();
    } catch (_) {}
    try {
      File(path).writeAsBytesSync(bytes, flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// Unpacks [doc] into [dir], which is emptied first.
///
/// Entry names are treated as untrusted: anything that would escape [dir] is
/// dropped. A document is a file people send each other, so its index must not
/// be able to name `../../Library/Preferences/...`.
void unpackDoc(DocFile doc, Directory dir) {
  if (dir.existsSync()) {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  }
  dir.createSync(recursive: true);
  for (final e in doc.entries.entries) {
    final rel = _safeRelative(e.key);
    if (rel == null) continue;
    final f = File('${dir.path}/$rel');
    try {
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync(e.value);
    } catch (_) {}
  }
}

/// Null when [name] is not a plain relative path inside the target folder.
String? _safeRelative(String name) {
  if (name.isEmpty) return null;
  if (name.startsWith('/') || name.contains('\\')) return null;
  final parts = name.split('/');
  for (final p in parts) {
    if (p.isEmpty || p == '.' || p == '..') return null;
  }
  return parts.join('/');
}

/// Reads the whole document at [path].
DocFile? readDoc(String path) {
  try {
    final f = File(path);
    if (!f.existsSync()) return null;
    return DocFile.decode(f.readAsBytesSync());
  } catch (_) {
    return null;
  }
}
