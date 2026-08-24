// S5 (OPTIMIZATION_PLAN.md §5, Session 5) — the two provenance functions in
// `part_model.dart` were made cheaper without being allowed to become
// different. This file is the "without being allowed to become different"
// half, and it is the only thing standing between the optimisation and a part
// that silently attributes its faces to the wrong feature.
//
// Both tests work the same way: a REFERENCE implementation of the algorithm as
// it stood before the change lives here, in the test, and the production
// function is required to agree with it exactly — not `closeTo`, exactly. A
// provenance answer that is one face different is a fillet claiming a face it
// did not make.
//
// Why the reference lives in the test rather than behind a flag in the
// library: a second code path in production is a second thing to keep right.
// Here it can only ever be read by this file, and if someone changes the
// production algorithm again, this is the thing that has to be re-derived.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/part_model.dart';

// ---------------------------------------------------------------------------
// the references — the algorithms as they were before S5 touched them
// ---------------------------------------------------------------------------

/// `newSurfacesOf` exactly as it read before the direction index: one
/// `base.any(...)` per result face, in list order.
List<FaceSurface> refNewSurfacesOf(
    List<FaceSurface> result, List<FaceSurface> base) {
  if (base.isEmpty) return result;
  return [
    for (final f in result)
      if (!base.any((b) => b.sameSurfaceAs(f, kFaceMatchTol))) f
  ];
}

/// `faceSurfaces` exactly as it read before the flat accumulators: `Vec3`
/// arithmetic throughout, including the per-triangle `[a, b, c]` list.
List<FaceSurface> refFaceSurfaces(OcctMeshData m) {
  if (m.faceInfos.isEmpty || m.triFaces.length * 3 != m.indices.length) {
    return const [];
  }
  final n = m.faceCount;
  if (n <= 0) return const [];
  final lo = List<Vec3>.filled(n, const Vec3(1e30, 1e30, 1e30));
  final hi = List<Vec3>.filled(n, const Vec3(-1e30, -1e30, -1e30));
  final cx = List<Vec3>.filled(n, Vec3.zero);
  final ar = List<double>.filled(n, 0);
  for (var t = 0; t + 2 < m.indices.length; t += 3) {
    final f = m.triFaces[t ~/ 3];
    if (f < 0 || f >= n) continue;
    final i0 = m.indices[t] * 3,
        i1 = m.indices[t + 1] * 3,
        i2 = m.indices[t + 2] * 3;
    final a = Vec3(m.positions[i0], m.positions[i0 + 1], m.positions[i0 + 2]);
    final b = Vec3(m.positions[i1], m.positions[i1 + 1], m.positions[i1 + 2]);
    final c = Vec3(m.positions[i2], m.positions[i2 + 1], m.positions[i2 + 2]);
    final w = (b - a).cross(c - a).length * 0.5;
    cx[f] = cx[f] + (a + b + c) * (w / 3);
    ar[f] += w;
    for (final q in [a, b, c]) {
      lo[f] = Vec3(math.min(lo[f].x, q.x), math.min(lo[f].y, q.y),
          math.min(lo[f].z, q.z));
      hi[f] = Vec3(math.max(hi[f].x, q.x), math.max(hi[f].y, q.y),
          math.max(hi[f].z, q.z));
    }
  }
  final out = <FaceSurface>[];
  for (var f = 0; f < n; f++) {
    if (ar[f] <= 0) continue;
    final r = 15 * f;
    if (r + 15 > m.faceInfos.length) break;
    out.add(FaceSurface(
      f,
      m.faceInfos[r].round(),
      Vec3(m.faceInfos[r + 1], m.faceInfos[r + 2], m.faceInfos[r + 3]),
      Vec3(m.faceInfos[r + 4], m.faceInfos[r + 5], m.faceInfos[r + 6])
          .normalized(),
      m.faceInfos[r + 10],
      lo[f],
      hi[f],
      cx[f] * (1 / ar[f]),
      ar[f],
    ));
  }
  return out;
}

// ---------------------------------------------------------------------------
// fixtures
// ---------------------------------------------------------------------------

/// The largest angle two axes may differ by and still be called parallel:
/// `|d·o.d| >= 1 - 1e-6` gives `|u - s.v| <= sqrt(2e-6)`.
const double kParallelAngle = 1.4142135623730951e-3;

Vec3 _unit(double a, double b) =>
    Vec3(math.cos(a) * math.cos(b), math.sin(a) * math.cos(b), math.sin(b));

/// A face with everything a `sameSurfaceAs` branch could look at.
FaceSurface _face(int id, int type, Vec3 p, Vec3 d, double radius, Vec3 lo,
        Vec3 hi, Vec3 centroid) =>
    FaceSurface(id, type, p, d, radius, lo, hi, centroid, 1.0);

/// A population built so that matches are COMMON — a generator that never
/// produces a match tests nothing, because "no match" is the answer a broken
/// filter also gives.
List<FaceSurface> _population(int n, math.Random r) {
  // Small pools, so different faces keep landing on the same surface.
  final axes = [
    for (var i = 0; i < 6; i++) _unit(r.nextDouble() * 6.3, r.nextDouble() - .5)
  ];
  final offsets = [0.0, 0.02, 0.049, 0.051, 1.0, -7.5];
  final radii = [1.0, 1.03, 5.0];
  return [
    for (var i = 0; i < n; i++) _one(i, r, axes, offsets, radii)
  ];
}

FaceSurface _one(int id, math.Random r, List<Vec3> axes, List<double> offsets,
    List<double> radii) {
  // Types weighted towards planes, which is what a real body is mostly made
  // of, but every branch of sameSurfaceAs appears.
  const types = [0, 0, 0, 0, 1, 1, 2, 3];
  final type = types[r.nextInt(types.length)];
  var d = axes[r.nextInt(axes.length)];
  // A perturbation that straddles the parallelism threshold in both
  // directions, so pairs land on either side of it.
  final wobble = (r.nextDouble() * 3 - 1) * kParallelAngle;
  d = _rotateSmall(d, wobble, r);
  if (r.nextInt(20) == 0) d = Vec3.zero; // a degenerate normal from the shim
  if (r.nextInt(20) == 1) d = d * -1.0; // the opposite orientation
  final p = axes[r.nextInt(axes.length)] * offsets[r.nextInt(offsets.length)];
  final c = Vec3(r.nextDouble() * 4 - 2, r.nextDouble() * 4 - 2,
      r.nextDouble() * 4 - 2);
  final h = r.nextDouble() * 2;
  return _face(id, type, p, d, radii[r.nextInt(radii.length)],
      c - Vec3(h, h, h), c + Vec3(h, h, h), c);
}

/// Rotates [v] by [a] radians about an arbitrary axis perpendicular to it.
Vec3 _rotateSmall(Vec3 v, double a, math.Random r) {
  var k = Vec3(r.nextDouble() - .5, r.nextDouble() - .5, r.nextDouble() - .5)
      .cross(v);
  if (k.length < 1e-9) k = Vec3(1, 0, 0).cross(v);
  if (k.length < 1e-9) return v;
  return rotateAboutAxis(v, k.normalized(), a).normalized();
}

void _sameAnswer(List<FaceSurface> result, List<FaceSurface> base, String why) {
  final got = newSurfacesOf(result, base);
  final want = refNewSurfacesOf(result, base);
  expect(got.length, want.length, reason: '$why — different number of faces');
  for (var i = 0; i < want.length; i++) {
    expect(identical(got[i], want[i]), isTrue,
        reason: '$why — face $i differs (id ${got[i].id} vs ${want[i].id})');
  }
}

// ---------------------------------------------------------------------------

void main() {
  group('newSurfacesOf — the direction index answers what the plain scan '
      'answered', () {
    test('over randomised populations, on both sides of the index threshold',
        () {
      // The threshold below which no index is built is 64 base faces, so the
      // sizes deliberately bracket it: an optimisation that only ever runs on
      // the big path would leave the small one unpinned, and vice versa.
      const sizes = [0, 1, 2, 7, 63, 64, 65, 128, 257];
      var matched = 0, total = 0;
      for (var seed = 0; seed < 40; seed++) {
        final r = math.Random(seed);
        for (final b in sizes) {
          final base = _population(b, r);
          final result = _population(sizes[r.nextInt(sizes.length)], r);
          _sameAnswer(result, base, 'seed $seed, base $b');
          total += result.length;
          matched += result.length - refNewSurfacesOf(result, base).length;
        }
      }
      // The generator has to actually produce matches, or the whole run above
      // proves only that two functions agree on "nothing matches".
      expect(matched, greaterThan(total ~/ 20),
          reason: 'the fixture produced too few matches to be testing '
              'anything: $matched of $total');
    });

    test('a match that straddles a cell boundary of the direction key is '
        'still found', () {
      // The index is a counting sort into cells 7e-3 wide on
      // |d.x| + 2|d.y| + 4|d.z|, probed one cell either side. This sweep walks
      // a direction continuously across hundreds of those boundaries and pairs
      // each position with partners either side of the parallelism threshold,
      // which is the case the +-1 probe exists for.
      final pad = _population(80, math.Random(7)); // forces the indexed path
      for (var i = 0; i < 400; i++) {
        final t = i * 4e-3;
        final a = _unit(t, t * 0.37);
        for (final f in const [0.0, 0.4, 0.7, 0.99, 1.01, 1.4]) {
          final b = _rotateSmall(a, kParallelAngle * f, math.Random(i));
          // Two coincident planes, differing only by that rotation: the plain
          // scan says "same surface" whenever the rotation is under the
          // threshold, and the index must not be the reason it stops saying so.
          final base = [
            ...pad,
            _face(0, 0, Vec3.zero, a, 0, const Vec3(-1, -1, -1),
                const Vec3(1, 1, 1), Vec3.zero)
          ];
          final result = [
            _face(1, 0, Vec3.zero, b, 0, const Vec3(-1, -1, -1),
                const Vec3(1, 1, 1), Vec3.zero)
          ];
          _sameAnswer(result, base, 'sweep i=$i factor=$f');
        }
      }
    });

    test('cylinders are separated from planes without either being lost', () {
      // Same axis, same everything a plane would be compared on — only `type`
      // differs. The index keeps the two types in separate blocks of cells, so
      // this is the case that catches a block-offset mistake.
      final axis = _unit(0.3, 0.2);
      final pad = _population(80, math.Random(11));
      final base = [
        ...pad,
        _face(0, 0, Vec3.zero, axis, 2, const Vec3(-1, -1, -1),
            const Vec3(1, 1, 1), Vec3.zero),
        _face(1, 1, Vec3.zero, axis, 2, const Vec3(-1, -1, -1),
            const Vec3(1, 1, 1), Vec3.zero),
      ];
      final result = [
        _face(2, 0, Vec3.zero, axis, 2, const Vec3(-1, -1, -1),
            const Vec3(1, 1, 1), Vec3.zero),
        _face(3, 1, Vec3.zero, axis, 2, const Vec3(-1, -1, -1),
            const Vec3(1, 1, 1), Vec3.zero),
        _face(4, 1, Vec3.zero, axis, 9, const Vec3(-1, -1, -1),
            const Vec3(1, 1, 1), Vec3.zero),
      ];
      _sameAnswer(result, base, 'plane and cylinder on one axis');
      // ...and the answer itself is the interesting one: the r=9 cylinder is
      // new, the other two are not.
      expect(newSurfacesOf(result, base).map((f) => f.id), [4]);
    });

    test('non-analytic and degenerate faces are never dropped', () {
      // Types >= 2 match by bounding box, which has no direction condition at
      // all, and a zero normal survives `normalized()` unchanged. Both are held
      // outside the cells and must therefore be compared against everything.
      final pad = _population(80, math.Random(13));
      final box = _face(0, 3, Vec3.zero, const Vec3(0, 0, 1), 0,
          const Vec3(0, 0, 0), const Vec3(2, 2, 2), const Vec3(1, 1, 1));
      final inside = _face(1, 3, Vec3.zero, const Vec3(1, 0, 0), 0,
          const Vec3(0.9, 0.9, 0.9), const Vec3(1.1, 1.1, 1.1), const Vec3(1, 1, 1));
      final far = _face(2, 3, Vec3.zero, const Vec3(0, 0, 1), 0,
          const Vec3(50, 50, 50), const Vec3(51, 51, 51), const Vec3(50, 50, 50));
      final zero = _face(3, 0, Vec3.zero, Vec3.zero, 0, const Vec3(0, 0, 0),
          const Vec3(1, 1, 1), Vec3.zero);
      final base = [...pad, box, zero];
      _sameAnswer([inside, far, zero, box], base, 'non-analytic faces');
      expect(newSurfacesOf([inside, far, zero, box], base).map((f) => f.id),
          [2, 3],
          reason: 'the far box is new because nothing contains it, and the '
              'zero-normal face is new because a zero normal matches NOTHING '
              '— not even the identical zero normal in base, since the '
              'parallelism test is a dot product against 1 - 1e-6. That is '
              'the plain scan\'s answer and the index must not improve on it');
    });

    test('a base normal that is not quite a unit vector still matches', () {
      // The +-1 cell probe is derived from |u - s.v| <= sqrt(2 - 2|u·v|),
      // which assumes unit vectors. A base face whose normal is NOT unit
      // breaks that derivation, so the index refuses to place it and scans it
      // against every query instead. Nothing in production produces one —
      // `Vec3.normalized()` is accurate to a couple of ulp — but the plain
      // scan would happily match it, so the index has to as well. Without
      // this case the tail is dead weight no test can tell is missing.
      final axis = _unit(0.9, 0.15);
      final swollen = axis * (1 + 1e-6); // d.d = 1 + 2e-6, outside the band
      expect(swollen.dot(axis).abs() >= 1 - 1e-6, isTrue,
          reason: 'the fixture must still count as parallel, or it proves '
              'nothing');
      final base = [
        ..._population(80, math.Random(17)), // forces the indexed path
        _face(0, 0, Vec3.zero, swollen, 0, const Vec3(-1, -1, -1),
            const Vec3(1, 1, 1), Vec3.zero),
      ];
      final result = [
        _face(1, 0, Vec3.zero, axis, 0, const Vec3(-1, -1, -1),
            const Vec3(1, 1, 1), Vec3.zero)
      ];
      expect(refNewSurfacesOf(result, base), isEmpty,
          reason: 'the plain scan matches these two, so the index must too');
      _sameAnswer(result, base, 'non-unit base normal');
    });

    test('an empty base still returns the result list itself', () {
      final r = _population(5, math.Random(1));
      expect(identical(newSurfacesOf(r, const []), r), isTrue);
    });
  });

  // -------------------------------------------------------------------------
  group('faceSurfaces — flat accumulators, identical numbers', () {
    test('every field of every face matches the Vec3 implementation bit for '
        'bit', () {
      for (var seed = 0; seed < 25; seed++) {
        final m = _mesh(math.Random(seed));
        final got = faceSurfaces(m);
        final want = refFaceSurfaces(m);
        expect(got.length, want.length, reason: 'seed $seed: face count');
        for (var i = 0; i < want.length; i++) {
          final g = got[i], w = want[i];
          final at = 'seed $seed, face $i';
          expect(g.id, w.id, reason: '$at: id');
          expect(g.type, w.type, reason: '$at: type');
          _exactVec(g.p, w.p, '$at: p');
          _exactVec(g.d, w.d, '$at: d');
          expect(g.radius, w.radius, reason: '$at: radius');
          _exactVec(g.lo, w.lo, '$at: lo');
          _exactVec(g.hi, w.hi, '$at: hi');
          _exactVec(g.centroid, w.centroid, '$at: centroid');
          expect(g.area, w.area, reason: '$at: area');
        }
      }
    });

    test('the guards still fire: no metadata, mismatched arrays, no faces',
        () {
      final r = math.Random(3);
      final ok = _mesh(r);
      expect(faceSurfaces(_strip(ok, faceInfos: true)), isEmpty,
          reason: 'no face metadata means UNKNOWN, and unknown is empty');
      expect(faceSurfaces(_strip(ok, triFaces: true)), isEmpty,
          reason: 'triFaces that does not agree with indices is not readable');
      // A face nothing was tessellated into has zero area and is skipped, in
      // both implementations.
      expect(faceSurfaces(ok).length, refFaceSurfaces(ok).length);
    });
  });
}

void _exactVec(Vec3 a, Vec3 b, String why) {
  expect(a.x, b.x, reason: '$why.x');
  expect(a.y, b.y, reason: '$why.y');
  expect(a.z, b.z, reason: '$why.z');
}

/// A mesh with several faces, degenerate triangles, out-of-range face ids and
/// a face with no triangles at all — the shapes of input the loop guards for.
OcctMeshData _mesh(math.Random r) {
  final faces = 3 + r.nextInt(5);
  final pos = <double>[];
  final idx = <int>[];
  final tri = <int>[];
  for (var f = 0; f < faces; f++) {
    // One face deliberately gets no triangles: ar[f] stays 0 and it is skipped.
    if (f == 2) continue;
    final tris = 1 + r.nextInt(6);
    for (var t = 0; t < tris; t++) {
      final base = pos.length ~/ 3;
      for (var v = 0; v < 3; v++) {
        pos.addAll([
          r.nextDouble() * 20 - 10,
          r.nextDouble() * 20 - 10,
          r.nextDouble() * 20 - 10,
        ]);
      }
      // Every few triangles, a degenerate one: zero area, so it contributes
      // nothing to the centroid but still moves the bounding box.
      if (t == 1) {
        pos.setRange((base + 1) * 3, (base + 2) * 3,
            pos.sublist(base * 3, (base + 1) * 3));
      }
      idx.addAll([base, base + 1, base + 2]);
      // An out-of-range face id now and then: the loop must skip it.
      tri.add(t == 2 ? faces + 5 : f);
    }
  }
  final infos = <double>[];
  for (var f = 0; f < faces; f++) {
    final d = _unit(r.nextDouble() * 6.3, r.nextDouble() - .5);
    infos.addAll([
      (r.nextInt(4)).toDouble(), // type
      r.nextDouble(), r.nextDouble(), r.nextDouble(), // p
      d.x, d.y, d.z, // d, normalised again inside faceSurfaces
      0, 0, 0,
      r.nextDouble() * 3, // radius
      0, 0, 0, 0,
    ]);
  }
  return OcctMeshData(
    Float64List.fromList(pos),
    Float64List(pos.length),
    Int32List.fromList(idx),
    Int32List.fromList(const [0]),
    Float64List(0),
    triFaces: Int32List.fromList(tri),
    faceInfos: Float64List.fromList(infos),
  );
}

OcctMeshData _strip(OcctMeshData m,
        {bool faceInfos = false, bool triFaces = false}) =>
    OcctMeshData(
      m.positions,
      m.normals,
      m.indices,
      m.edgeStarts,
      m.edgePoints,
      triFaces: triFaces
          ? Int32List.fromList(m.triFaces.take(1).toList())
          : m.triFaces,
      faceInfos: faceInfos ? Float64List(0) : m.faceInfos,
    );
