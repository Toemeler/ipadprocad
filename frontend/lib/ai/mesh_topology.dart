/// How many separate pieces of material a tessellated body is.
///
/// ISSUE #82 — a cable clamp landed with 86% of its volume outside the part,
/// and a join that misses its body entirely leaves a lump floating in the air
/// inside the SAME body. Neither shows up in a volume, a bounding box or a
/// feature list; all three still read as one healthy solid. What does show it
/// is connectivity: material that touches shares edges, so its triangles are
/// joined, and material that does not is a separate island.
///
/// The kernel tessellates each face on its own, so two faces meeting along an
/// edge do NOT share vertex INDICES — they share vertex POSITIONS, because
/// OCCT discretises the edge once and both faces use that discretisation. So
/// the count welds by position (to 0.1 µm, far below anything a part is
/// modelled at and far above floating-point noise) and then unions every
/// triangle's corners. Linear in the mesh, a few milliseconds for a
/// fifty-thousand-triangle body.
library;

import '../ffi/occt_engine.dart' show OcctMeshData;

/// Pieces of connected material in [mesh]; 0 for an empty mesh.
int meshComponentCount(OcctMeshData mesh) {
  final pos = mesh.positions;
  final idx = mesh.indices;
  final n = pos.length ~/ 3;
  if (n == 0 || idx.length < 3) return 0;
  final parent = List<int>.generate(n, (i) => i);
  int find(int x) {
    while (parent[x] != x) {
      parent[x] = parent[parent[x]];
      x = parent[x];
    }
    return x;
  }

  void union(int a, int b) {
    final ra = find(a), rb = find(b);
    if (ra != rb) parent[ra] = rb;
  }

  // Weld by position.
  final first = <String, int>{};
  for (var i = 0; i < n; i++) {
    final key = '${(pos[i * 3] * 1e4).round()},'
        '${(pos[i * 3 + 1] * 1e4).round()},'
        '${(pos[i * 3 + 2] * 1e4).round()}';
    final seen = first[key];
    if (seen == null) {
      first[key] = i;
    } else {
      union(i, seen);
    }
  }
  final used = List<bool>.filled(n, false);
  for (var t = 0; t + 2 < idx.length; t += 3) {
    final a = idx[t], b = idx[t + 1], c = idx[t + 2];
    if (a < 0 || b < 0 || c < 0 || a >= n || b >= n || c >= n) continue;
    union(a, b);
    union(b, c);
    used[a] = used[b] = used[c] = true;
  }
  final roots = <int>{};
  for (var i = 0; i < n; i++) {
    if (used[i]) roots.add(find(i));
  }
  return roots.length;
}
