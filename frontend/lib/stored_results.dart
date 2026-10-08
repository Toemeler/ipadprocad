// Stored feature results: what makes opening a big part fast.
//
// Opening a part used to rebuild every feature from nothing, because the
// document holds the feature tree and not the B-Rep it builds: a plate with
// 30 holes, a 120-hole pattern and a fillet took 5-6 s to open, every time.
// Inventor keeps the built body in the document and re-runs the tree only
// after something in it changes. This is that, on top of [ResultCache]:
//
//   * on save, the last feature of every body that built cleanly writes its
//     body to `results/<digest>.step.gz`, and `results/index.json` names the
//     feature, the digest of the fold's key there ([storedSigHash]), the
//     volume, and the faces each feature of the body contributed;
//   * on open, every entry that still fits (same format, same kernel, same
//     feature, readable file, same volume) becomes a [ResultCache.stored] on
//     its feature, and the fold's own key check decides whether it is used.
//
// Anything that does not fit is skipped without a word beyond the log, and
// the fold rebuilds the tree, which is exactly what happened before: the
// worst a damaged or foreign `results/` can cost is time, never geometry.
// The entries are an accelerator, not part of the model -- nothing in
// `meta.json` changes, and a build that does not know them ignores them.

import 'dart:convert';
import 'dart:io';

import 'part_model.dart';

/// Bump when an older `results/` must not be read any more.
const int kStoredResultsFormat = 1;

/// The folder inside a part's document.
const String kStoredResultsDir = 'results';

/// The features whose body is worth storing: per body, the last feature of
/// its chain, when everything on that body built and nothing about it needs
/// the bodies' intermediate states on the next open.
///
/// Left out, so they rebuild as before:
///   * a body with a failed or rolled-back-only chain -- its errors have to
///     come from a real build;
///   * a body read by a Combine, or that combines another body: the tool body
///     is read at the Combine's place in the timeline, which is an
///     intermediate state a stored result does not keep;
///   * a body with an imported or derived feature (re-read from its file or
///     origin anyway) or already carrying an Inventor result.
List<PartFeature> storableBodyEnds(PartModel part) {
  final read = <String>{for (final f in part.features) ...f.inputBodies};
  final last = <String, PartFeature>{};
  final bad = <String>{...read};
  for (final f in part.features) {
    if (f.rolledBack) continue;
    if (f.inputBodies.isNotEmpty ||
        f is DeriveFeature ||
        (f is ExtrudeFeature && f.imported) ||
        (f.resultCache != null && !f.resultCache!.stored) ||
        f.computeError != null) {
      bad.add(f.bodyName);
    }
    last[f.bodyName] = f;
  }
  return [
    for (final e in last.entries)
      if (!bad.contains(e.key) &&
          e.value.solid != null &&
          e.value.builtSig != null &&
          !e.value.consumedByJoin)
        e.value
  ];
}

List<double> faceSurfaceToList(FaceSurface s) => [
      s.id.toDouble(), s.type.toDouble(), //
      s.p.x, s.p.y, s.p.z, s.d.x, s.d.y, s.d.z, s.radius,
      s.lo.x, s.lo.y, s.lo.z, s.hi.x, s.hi.y, s.hi.z,
      s.centroid.x, s.centroid.y, s.centroid.z, s.area,
    ];

FaceSurface? faceSurfaceFromList(Object? o) {
  if (o is! List || o.length != 19 || o.any((v) => v is! num)) return null;
  final v = [for (final x in o) (x as num).toDouble()];
  Vec3 at(int i) => Vec3(v[i], v[i + 1], v[i + 2]);
  return FaceSurface(
      v[0].toInt(), v[1].toInt(), at(2), at(5), v[8], at(9), at(12), at(15),
      v[18]);
}

/// One body's entry in `results/index.json`.
class StoredResultEntry {
  StoredResultEntry({
    required this.feature,
    required this.kind,
    required this.body,
    required this.sigHash,
    required this.file,
    required this.volume,
    required this.surfaces,
    required this.occurrences,
  });

  final String feature, kind, body, sigHash, file;
  final double volume;
  final Map<String, List<FaceSurface>> surfaces;
  final Map<String, int> occurrences;

  /// Built from [end], the last feature of its body, as it stands now.
  static StoredResultEntry of(PartModel part, PartFeature end) {
    final hash = storedSigHash(end.builtSig!);
    final surfaces = <String, List<FaceSurface>>{};
    final occ = <String, int>{};
    for (final g in part.features) {
      if (g.bodyName != end.bodyName || g.rolledBack) continue;
      if (g.ownSurfaces.isNotEmpty) surfaces[g.name] = g.ownSurfaces;
      if (g is PatternFeature) occ[g.name] = g.builtOccurrences;
    }
    return StoredResultEntry(
      feature: end.name,
      kind: end.kind,
      body: end.bodyName,
      sigHash: hash,
      file: '$kStoredResultsDir/${hash.substring(0, 24)}.step.gz',
      volume: end.solid!.volume,
      surfaces: surfaces,
      occurrences: occ,
    );
  }

  Map<String, dynamic> toJson() => {
        'feature': feature,
        'kind': kind,
        'body': body,
        'sig': sigHash,
        'file': file,
        'volume': volume,
        'surfaces': {
          for (final e in surfaces.entries)
            e.key: [for (final s in e.value) faceSurfaceToList(s)]
        },
        if (occurrences.isNotEmpty) 'occurrences': occurrences,
      };

  static StoredResultEntry? fromJson(Object? o) {
    if (o is! Map) return null;
    final feature = o['feature'], kind = o['kind'], body = o['body'];
    final sig = o['sig'], file = o['file'], volume = o['volume'];
    if (feature is! String ||
        kind is! String ||
        body is! String ||
        sig is! String ||
        file is! String ||
        volume is! num) {
      return null;
    }
    // The file must be one of ours: an entry naming `../x` or another folder
    // of the document is not something to read.
    if (!RegExp('^$kStoredResultsDir/[0-9a-f]+\\.step\\.gz\$').hasMatch(file)) {
      return null;
    }
    final surfaces = <String, List<FaceSurface>>{};
    final rawS = o['surfaces'];
    if (rawS is Map) {
      for (final e in rawS.entries) {
        final list = e.value;
        if (e.key is! String || list is! List) return null;
        final out = <FaceSurface>[];
        for (final x in list) {
          final s = faceSurfaceFromList(x);
          if (s == null) return null;
          out.add(s);
        }
        surfaces[e.key as String] = out;
      }
    }
    final occ = <String, int>{};
    final rawO = o['occurrences'];
    if (rawO is Map) {
      for (final e in rawO.entries) {
        if (e.key is String && e.value is num) {
          occ[e.key as String] = (e.value as num).toInt();
        }
      }
    }
    return StoredResultEntry(
      feature: feature,
      kind: kind,
      body: body,
      sigHash: sig,
      file: file,
      volume: volume.toDouble(),
      surfaces: surfaces,
      occurrences: occ,
    );
  }
}

/// `results/index.json`: the format, the kernel that wrote the bodies, and
/// one entry per stored body.
String encodeStoredResultsIndex(String kernel, List<StoredResultEntry> e) =>
    jsonEncode({
      'format': kStoredResultsFormat,
      'kernel': kernel,
      'bodies': [for (final x in e) x.toJson()],
    });

/// The entries of an index written by [kernel] in this format, or null when
/// it is anything else (another kernel build, a newer format, damage).
List<StoredResultEntry>? decodeStoredResultsIndex(String text, String kernel) {
  try {
    final j = jsonDecode(text);
    if (j is! Map) return null;
    if (j['format'] != kStoredResultsFormat || j['kernel'] != kernel) {
      return null;
    }
    final bodies = j['bodies'];
    if (bodies is! List) return null;
    final out = <StoredResultEntry>[];
    for (final b in bodies) {
      final e = StoredResultEntry.fromJson(b);
      if (e != null) out.add(e);
    }
    return out;
  } catch (_) {
    return null;
  }
}

/// Gzip, so a body's STEP text costs a fraction of its size in the document.
List<int> packStoredBody(List<int> step) => gzip.encode(step);

/// The STEP bytes back, or null when the entry is damaged.
List<int>? unpackStoredBody(List<int> bytes) {
  try {
    return gzip.decode(bytes);
  } catch (_) {
    return null;
  }
}
