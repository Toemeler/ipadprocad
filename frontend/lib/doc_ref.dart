// M177 — where a document LIVES, and where Save puts it back.
//
// Until now every document lived in one place: the app's own folder. The
// model the app needs is two:
//
//   INTERNAL — in the app's documents folder. Anything you create lives here,
//              and anything DROPPED here (a .ptp copied in over AirDrop or
//              from Files) is picked up on the next open, with no import step.
//   EXTERNAL — opened from somewhere else through Open. The app remembers the
//              path, lists it in the gallery with its preview, and Save writes
//              back THERE. Silently saving an internal copy instead is the
//              behaviour that makes a document app untrustworthy: you edit a
//              file, save, and your edits are not in the file you opened.
//
// An IMPORT is neither. A STEP or DXF is not one of our documents, so opening
// one CONVERTS it: a new internal .ptp/.pts is created and the original is
// left untouched. That is why Open takes all three and only imports two of
// them — the button is one verb, the behaviour follows from what you picked.
import 'dart:convert';

import 'doc_file.dart';

enum DocSource { internal, external }

/// A document the gallery knows about.
class DocRef {
  final String name;

  /// 'part' or 'sketch'.
  final String kind;

  /// Absolute path. For an internal document this is inside the app folder;
  /// for an external one it is wherever the user opened it from.
  final String path;

  final DocSource source;

  /// When it was last opened, so the gallery can order by recency. Null for
  /// something merely discovered in the folder and never opened.
  final DateTime? lastOpened;

  const DocRef(this.name, this.kind, this.path, this.source, [this.lastOpened]);

  bool get isPart => kind == 'part';

  Map<String, dynamic> toJson() => {
        'name': name,
        'kind': kind,
        'path': path,
        'src': source.name,
        if (lastOpened != null) 'at': lastOpened!.toIso8601String(),
      };

  static DocRef? fromJson(Map<String, dynamic> j) {
    final name = j['name'] as String?;
    final path = j['path'] as String?;
    if (name == null || path == null) return null;
    return DocRef(
      name,
      j['kind'] as String? ?? 'part',
      path,
      j['src'] == 'external' ? DocSource.external : DocSource.internal,
      DateTime.tryParse(j['at'] as String? ?? ''),
    );
  }

  DocRef withOpenedAt(DateTime t) => DocRef(name, kind, path, source, t);
}

/// What Open should do with the file the user picked.
enum OpenAction {
  /// One of ours, from outside the app folder: remember it and edit in place.
  openExternal,

  /// One of ours, already inside the app folder: just open it.
  openInternal,

  /// Not one of ours: convert it into a NEW internal document.
  import,

  /// Nothing we can read.
  unsupported,
}

/// Decides what Open does, from the path alone.
///
/// [appDir] must be the app's documents directory. The comparison is on the
/// PARENT folder, not a prefix: a file in a sub-folder of the app directory is
/// still external, because saving back into it must not silently relocate it.
OpenAction openActionFor(String path, String appDir) {
  final lower = path.toLowerCase();
  final ours = docNameOf(path) != null;
  if (ours) {
    return _parentOf(path) == _stripSlash(appDir)
        ? OpenAction.openInternal
        : OpenAction.openExternal;
  }
  if (lower.endsWith('.dxf') ||
      lower.endsWith('.step') ||
      lower.endsWith('.stp')) {
    return OpenAction.import;
  }
  return OpenAction.unsupported;
}

String _stripSlash(String p) =>
    p.endsWith('/') ? p.substring(0, p.length - 1) : p;

String _parentOf(String path) {
  final i = path.lastIndexOf('/');
  return i <= 0 ? '' : path.substring(0, i);
}

/// Where Save writes [ref].
///
/// External documents are written back where they came from. This is the
/// whole reason DocRef exists: Ctrl+S on a file you opened from Files has to
/// land in that file.
String saveTargetFor(DocRef ref, String appDir) => ref.source ==
        DocSource.external
    ? ref.path
    : '${_stripSlash(appDir)}/${ref.name}.${ref.isPart ? kPartExt : kSketchExt}';

/// The documents sitting in the app folder, from a directory listing.
///
/// Pure so it can be tested without a filesystem, and so the rule is stated
/// once: ANY .ptp or .pts in the folder is a document, whether this app wrote
/// it or someone dropped it in. That is what makes "copy a file into the app
/// folder and it appears" work without an import step.
List<DocRef> scanAppFolder(Iterable<String> fileNames, String appDir) {
  final out = <DocRef>[];
  for (final f in fileNames) {
    final name = docNameOf(f);
    if (name == null) continue;
    out.add(DocRef(name, isPartPath(f) ? 'part' : 'sketch',
        '${_stripSlash(appDir)}/$f', DocSource.internal));
  }
  out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return out;
}

/// The remembered EXTERNAL documents, merged with what is in the app folder.
///
/// An external entry whose file has gone is dropped rather than shown as a
/// dead row — but only when [stillExists] can actually say so, because on iOS
/// a security-scoped path can be temporarily unreachable and forgetting the
/// document then would lose the user's link to it for good.
List<DocRef> mergedLibrary(
  List<DocRef> internal,
  List<DocRef> remembered, {
  bool Function(String path)? stillExists,
}) {
  final byPath = {for (final d in internal) d.path: d};
  for (final e in remembered) {
    if (e.source != DocSource.external) continue;
    if (stillExists != null && !stillExists(e.path)) continue;
    byPath[e.path] = e;
  }
  final out = byPath.values.toList();
  out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return out;
}

/// Serialises the remembered externals. Internals are NOT stored: they are
/// discovered by scanning, so a stale list can never hide a file that is
/// really there.
String encodeRemembered(List<DocRef> refs) => jsonEncode([
      for (final r in refs)
        if (r.source == DocSource.external) r.toJson()
    ]);

List<DocRef> decodeRemembered(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  try {
    final v = jsonDecode(raw);
    if (v is! List) return const [];
    return [
      for (final e in v)
        if (e is Map<String, dynamic>)
          if (DocRef.fromJson(e) case final r?)
            if (r.source == DocSource.external) r
    ];
  } catch (_) {
    return const [];
  }
}
