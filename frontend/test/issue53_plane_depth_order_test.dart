// #53, reopened 2026-09-12: "the workplanes still have issues with displaying
// the handling which is in front and what behind something is completely off",
// with two screenshots a few degrees of orbit apart in which the blue and red
// origin planes swap which one washes over the other.
//
// What is asserted here is the PROPERTY, not an arrangement: for a camera, a
// list of translucent polygons is in correct painter's order when, at every
// point of the screen, each polygon covering that point is nearer than the one
// drawn before it. [_orderViolations] measures exactly that, and every test
// below is that measurement under a different camera.
//
// The old behaviour is kept in the file as a permanent negative control:
// `_wholePlanesInKeyOrder` is what the painter did — the three plane quads,
// undivided, in `kPlaneKeys` order — and it is held to FAILING the same
// measurement. Two things make it fail and only one of them is the sort:
// intersecting quads have no correct order to be put in, and all three of
// their centroids sit on the origin so a renderer sorting by distance is
// breaking a tie with noise.
import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/part_render.dart';
import 'package:prototype/plane_stack.dart';
import 'package:prototype/reality_scene.dart';

const _size = Size(1000, 750);

PartModel _threePlanes() {
  final p = PartModel('Part1');
  for (final k in kPlaneKeys) {
    p.vis[k] = true;
  }
  return p;
}

List<PlanePiece> _pieces(PartModel p) => translucentPlanePieces(
    AppState(), p,
    visible: (key) => p.vis[key] == true);

/// The pre-fix draw list: one undivided quad per plane, in `kPlaneKeys` order.
List<PlanePiece> _wholePlanesInKeyOrder(PartModel p) => _pieces(p);

/// Signed view depth of the point of [pl] under screen point [sp]; null when
/// the plane is edge-on to the camera (nothing to be ordered there).
double? _depthAt(Cam3 cam, PlaneEq pl, Offset sp) {
  final fwd = cam.dir * -1;
  // Invert Cam3.project for the two in-screen coordinates.
  final a = (sp.dx / _size.width * 2 - 1) * (cam.halfH * cam.aspect) + cam.ox;
  final b = (1 - sp.dy / _size.height) * 2 * cam.halfH - cam.halfH + cam.oy;
  final nf = pl.n.dot(fwd);
  if (nf.abs() < 1e-9) return null;
  return (pl.d - a * pl.n.dot(cam.s) - b * pl.n.dot(cam.u)) / nf;
}

bool _inside(List<Offset> poly, Offset q) {
  var hit = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final a = poly[i], b = poly[j];
    if ((a.dy > q.dy) != (b.dy > q.dy) &&
        q.dx < (b.dx - a.dx) * (q.dy - a.dy) / (b.dy - a.dy) + a.dx) {
      hit = !hit;
    }
  }
  return hit;
}

/// Screen points where a polygon drawn EARLIER is nearer than one drawn after
/// it — i.e. where the blend lands in the wrong order. Zero is correct.
int _orderViolations(List<PlanePiece> order, PartCamera pc, {int grid = 70}) {
  final cam = Cam3(pc, _size);
  final screen = [
    for (final p in order) [for (final v in p.pts) cam.project(v)]
  ];
  var bad = 0;
  for (var ix = 0; ix < grid; ix++) {
    for (var iy = 0; iy < grid; iy++) {
      final q = Offset((ix + 0.5) / grid * _size.width,
          (iy + 0.5) / grid * _size.height);
      double? prev;
      for (var k = 0; k < order.length; k++) {
        if (!_inside(screen[k], q)) continue;
        final d = _depthAt(cam, order[k].plane, q);
        if (d == null) continue;
        // Smaller depth is NEARER (Cam3.depth). Each polygon drawn after the
        // last must be at least as near, or the wash goes on upside down.
        // 1e-6 mm of slack for the shared edges the split introduces.
        if (prev != null && d > prev + 1e-6) bad++;
        prev = d;
      }
    }
  }
  return bad;
}

/// A sweep of cameras covering every octant plus the awkward near-axis ones.
List<PartCamera> _cameras() => [
      for (var i = 0; i < 16; i++)
        for (var j = 1; j < 6; j++)
          PartCamera(az: i * math.pi / 8 + 0.03, pol: j * math.pi / 6),
      // The two screenshots: an isometric view and a few degrees off it.
      PartCamera(az: math.pi / 4, pol: 0.955),
      PartCamera(az: math.pi / 4 + 0.04, pol: 0.955),
      PartCamera(az: math.pi / 4 - 0.04, pol: 0.97),
    ];

void main() {
  test('the split leaves no two pieces intersecting', () {
    final pieces =
        planesBackToFront(buildPlaneBsp(_pieces(_threePlanes())), orthoEye(
            PartCamera().dir));
    expect(pieces.length, 12, reason: 'three planes, four quadrants each');
    for (final a in pieces) {
      for (final b in pieces) {
        if (identical(a, b)) continue;
        // Every vertex of b is on ONE side of a's plane (or in it). Two
        // surfaces that satisfy this for each other cannot cross, which is
        // the whole reason an order exists to be found.
        var pos = false, neg = false;
        for (final v in b.pts) {
          final s = a.plane.side(v);
          if (s > 1e-6) pos = true;
          if (s < -1e-6) neg = true;
        }
        expect(pos && neg, isFalse,
            reason: 'a piece of ${b.key} still crosses the plane of ${a.key}');
      }
    }
  });

  test('every piece keeps the plane it was cut from', () {
    final pieces = planesBackToFront(
        buildPlaneBsp(_pieces(_threePlanes())), orthoEye(PartCamera().dir));
    for (final p in pieces) {
      for (final v in p.pts) {
        expect(p.plane.side(v).abs(), lessThan(1e-9));
      }
      expect(kPlaneKeys, contains(p.key));
    }
  });

  test('the draw order is correct from every camera', () {
    final part = _threePlanes();
    final tree = buildPlaneBsp(_pieces(part));
    for (final pc in _cameras()) {
      final order = planesBackToFront(tree, orthoEye(pc.dir));
      expect(_orderViolations(order, pc), 0,
          reason: 'wrong blend order at az=${pc.az} pol=${pc.pol}');
    }
  });

  test('NEGATIVE CONTROL: undivided planes in key order cannot be correct',
      () {
    // The behaviour being replaced. If this ever reports zero violations the
    // measurement above has stopped measuring anything.
    final part = _threePlanes();
    var camerasWrong = 0;
    for (final pc in _cameras()) {
      if (_orderViolations(_wholePlanesInKeyOrder(part), pc) > 0) {
        camerasWrong++;
      }
    }
    expect(camerasWrong, greaterThan(_cameras().length ~/ 2),
        reason: 'three intersecting quads are mis-ordered from most cameras');
  });

  test('NEGATIVE CONTROL: the three whole planes shared one centroid', () {
    // Why the two screenshots differ at all. RealityKit orders transparent
    // entities by distance to their bounds centre, and these three numbers
    // were equal, so the order was decided by floating-point noise and a few
    // degrees of orbit flipped it. After the split every piece has its own.
    final whole = _wholePlanesInKeyOrder(_threePlanes());
    for (final p in whole) {
      expect(p.centroid.length, lessThan(1e-9));
    }
    final split = planesBackToFront(
        buildPlaneBsp(_pieces(_threePlanes())), orthoEye(PartCamera().dir));
    final seen = <String>{};
    for (final p in split) {
      final c = p.centroid;
      expect(seen.add('${c.x.toStringAsFixed(6)},'
          '${c.y.toStringAsFixed(6)},${c.z.toStringAsFixed(6)}'),
          isTrue,
          reason: 'two pieces still share a centroid, so a distance sort '
              'still has a tie to break with noise');
    }
  });

  test('a small orbit never flips an overlap the wrong way', () {
    // The literal report: same scene, a few degrees apart, different picture.
    // Correctness at both ends is what rules that out, so both are measured
    // across a fine sweep rather than compared to each other.
    final part = _threePlanes();
    final tree = buildPlaneBsp(_pieces(part));
    for (var i = 0; i < 60; i++) {
      final pc = PartCamera(az: math.pi / 4 + i * 0.002, pol: 0.955);
      expect(_orderViolations(tree == null ? [] : planesBackToFront(tree,
              orthoEye(pc.dir)), pc, grid: 40),
          0,
          reason: 'az=${pc.az}');
    }
  });

  test('arbitrary planes, not just the three: still exact, still bounded', () {
    // Origin planes are the reported case and the easy one — mutually
    // perpendicular, all through the origin. Work planes are neither, so the
    // ordering is exercised on a set that is skew, offset and uneven, and the
    // ceilings that stop the splitting from doubling forever are exercised
    // with it.
    final rnd = math.Random(7);
    final pieces = <PlanePiece>[];
    for (final k in kPlaneKeys) {
      final f = planeFrame(k);
      pieces.add(planePieceFromQuad(k, [
        f.toWorld(const Offset(-10, -10)),
        f.toWorld(const Offset(10, -10)),
        f.toWorld(const Offset(10, 10)),
        f.toWorld(const Offset(-10, 10)),
      ], const Color(0x47FF8844)));
    }
    for (var i = 0; i < 9; i++) {
      final n = Vec3(rnd.nextDouble() * 2 - 1, rnd.nextDouble() * 2 - 1,
              rnd.nextDouble() * 2 - 1)
          .normalized();
      final u = (n.cross(const Vec3(0.13, 0.97, 0.21))).normalized();
      final v = n.cross(u);
      final o = n * (rnd.nextDouble() * 8 - 4);
      final w = 6 + rnd.nextDouble() * 8, h = 6 + rnd.nextDouble() * 8;
      pieces.add(planePieceFromQuad('wp$i', [
        o - u * w - v * h,
        o + u * w - v * h,
        o + u * w + v * h,
        o - u * w + v * h,
      ], const Color(0x38FFAA55)));
    }
    final split = splitPiecesApart(pieces);
    expect(split.length, lessThanOrEqualTo(kMaxSplitPieces * 2),
        reason: 'the ceiling keeps a busy scene from doubling forever');
    final tree = buildPlaneBsp(pieces);
    for (final pc in _cameras()) {
      expect(_orderViolations(planesBackToFront(tree, orthoEye(pc.dir)), pc,
              grid: 40),
          0,
          reason: 'twelve arbitrary planes at az=${pc.az} pol=${pc.pol}');
    }
  });

  test('the payload carries the tree, not a finished order', () {
    final st = planeStackPayload(AppState(), _threePlanes())!;
    final pieces = st['pieces'] as List;
    final nodes = st['nodes'] as List;
    expect(pieces.length, 12);
    expect(nodes.length, greaterThanOrEqualTo(3));
    for (final n in nodes as List<Map<String, dynamic>>) {
      expect((n['n'] as List).length, 3);
      for (final k in ['front', 'back']) {
        final i = n[k] as int;
        expect(i, anyOf(-1, inInclusiveRange(0, nodes.length - 1)));
      }
      for (final i in n['pieces'] as List<int>) {
        expect(i, inInclusiveRange(0, pieces.length - 1));
      }
    }
    // Every piece is reachable exactly once through the tree: a piece the
    // native walk cannot reach is a piece the device never draws.
    final reached = <int>[];
    for (final n in nodes as List<Map<String, dynamic>>) {
      reached.addAll(n['pieces'] as List<int>);
    }
    expect(reached.toSet().length, pieces.length);
    for (final p in pieces as List<Map<String, dynamic>>) {
      expect((p['pts'] as List).length % 3, 0);
      expect((p['pts'] as List).length ~/ 3, greaterThanOrEqualTo(3));
      // ARGB with the wash alpha baked in — the native side reads one number.
      expect((p['argb'] as int) >> 24 & 0xFF, greaterThan(0));
      expect((p['argb'] as int) >> 24 & 0xFF, lessThan(255));
    }
  });
}
