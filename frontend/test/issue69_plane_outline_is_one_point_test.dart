// #69 — "plane outlines should in every case be just one pixel in thickness.
// their highlight corner points a few more but Not much".
//
// The corner points are already that: [kPlaneCornerMark] is 3, set in M254's
// third pass against "the plane's border is a 1 pt line, and a corner marker
// that reads as a point on that line has to be of the same order". The border
// it was set against is what this is about — the measure was right and the
// thing it measured was not, in two engines, for two different reasons. The
// report was filed from the iPad (build cf0ce5c, ios 27.0), so the first of
// them is the one that was seen.
//
// REALITYKIT — the border is the one line in the scene that is not a ribbon.
// Every other stroke (solid edges, sketch curves, the accent) is a quad aimed
// at the camera and is therefore exactly its stated width whatever the camera
// does. #50 made the plane border a BOX instead, to get sharp square corners,
// `2r` across in the in-plane perpendicular and `2r` along the plane normal.
// The silhouette of that square is
//
//     2r * (|u.perp| + |u.normal|)
//
// across the screen direction `u`, which is 2r only when the camera looks
// along one of those two axes and 2r*sqrt(2) — 41% over — at 45 degrees, the
// default three-quarter view. Worse, PlaneEntity.setStyle returned early on a
// pure camera turn, on the by-then-false grounds that "a tube is
// orientation-independent": the width did not even swing, it FROZE at whatever
// the last zoom had made it. "In every case" is the report noticing both.
//
// The fix is OutlineStyle.silhouetteScale, and the first three tests here are
// the arithmetic it does — written out independently, and held over a sweep of
// orientations rather than at the one angle that would pass by luck. The
// square that was there before is the negative control, and it fails the same
// sweep by up to 41%.
//
// THE CPU PAINTER had a plainer version of the same disagreement: origin
// planes stroked at 1, work planes at 1.2, and at 2.0 while hot. Three things
// already said 1 — the origin planes beside them, Stroke.line in
// PartScene.swift, and kPlaneCornerMark's own reasoning — so the work plane
// was simply the odd one out. That half is a source test, because a painter
// this deep in a scene cannot be rasterised in isolation and the number is the
// whole of the claim.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/widgets/viewport3d.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

/// One logical point of stroke, as a half-width — `Stroke.line` is 1.0 and
/// `OutlineStyle.halfWidth` halves it. Millimetres per point is 1 here so the
/// numbers below read as points directly.
const double _r = 0.5;

/// [OutlineStyle.silhouetteScale] in PartScene.swift, written out again.
///
/// Deliberately a second implementation rather than a port: if this were the
/// same expression the Swift makes, agreeing with it would prove nothing. What
/// it has to agree with is the geometry, and the geometry is in
/// [_silhouetteWidth] below.
double _scale(Vector3 view, Vector3 dir, Vector3 perp, Vector3 normal) {
  final across = view.cross(dir);
  if (across.length <= 1e-5) return 1;
  final u = across.normalized();
  final w = u.dot(perp).abs() + u.dot(normal).abs();
  return w > 1e-5 ? 1 / w : 1;
}

/// What a box of half-widths [r] along [perp] and [r] along [normal], swept
/// along [dir], actually covers on screen — the extent of its four cross-
/// section corners along the screen direction across the line.
///
/// This is the measurement the report is about, and it makes no reference to
/// the fix: it is the projection of the box, whatever built it.
double _silhouetteWidth(
    Vector3 view, Vector3 dir, Vector3 perp, Vector3 normal, double r) {
  final across = view.cross(dir);
  if (across.length <= 1e-5) return 0; // end-on: the line is a point
  final u = across.normalized();
  var lo = double.infinity, hi = -double.infinity;
  for (final sp in [-1.0, 1.0]) {
    for (final sn in [-1.0, 1.0]) {
      final corner = perp * (sp * r) + normal * (sn * r);
      final t = corner.dot(u);
      lo = math.min(lo, t);
      hi = math.max(hi, t);
    }
  }
  return hi - lo;
}

/// A plane's four border edges, as (dir, perp) pairs, for a plane whose own
/// in-plane axes are [u] and [v] and whose normal is [n]. A rectangle's four
/// edges run +u, +v, -u, -v, and `perp` is `n x dir` exactly as rectFrame
/// takes it.
List<(Vector3, Vector3)> _edges(Vector3 u, Vector3 v, Vector3 n) =>
    [u, v, -u, -v].map((d) => (d, n.cross(d).normalized())).toList();

/// Camera directions to hold the claim over: a sweep in both angles, so no
/// single lucky orientation can carry it. Includes the axis-aligned cases
/// where the old square was already right, which must not get worse.
Iterable<Vector3> _viewSweep() sync* {
  for (var az = 0; az < 360; az += 15) {
    for (var el = -75; el <= 75; el += 15) {
      final a = az * math.pi / 180, e = el * math.pi / 180;
      yield Vector3(math.cos(e) * math.cos(a), math.sin(e),
              math.cos(e) * math.sin(a))
          .normalized();
    }
  }
}

void main() {
  // The plane the sweep is measured on. Tilted off every axis on purpose: an
  // axis-aligned plane under an axis-aligned camera is exactly the case the
  // square already got right, and a test that only ever looked at those would
  // have passed before the fix.
  final n = Vector3(0.37, 0.82, -0.44).normalized();
  final u = Vector3(1, 0, 0).cross(n).normalized();
  final v = n.cross(u).normalized();

  test('the border is one point wide from every direction', () {
    for (final view in _viewSweep()) {
      for (final (dir, perp) in _edges(u, v, n)) {
        final w = _silhouetteWidth(
            view, dir, perp, n, _r * _scale(view, dir, perp, n));
        if (w == 0) continue; // seen end-on: no width to be right about
        expect(w, closeTo(2 * _r, 1e-6),
            reason: 'view $view, edge $dir came out $w');
      }
    }
  });

  test('NEGATIVE CONTROL: the unscaled square is up to 41% too wide', () {
    var worst = 0.0;
    for (final view in _viewSweep()) {
      for (final (dir, perp) in _edges(u, v, n)) {
        final w = _silhouetteWidth(view, dir, perp, n, _r);
        if (w == 0) continue;
        worst = math.max(worst, w / (2 * _r));
        // Never THINNER than asked: a square's silhouette is its side at
        // best. So the defect is one-sided, which is why it reads as "too
        // thick" rather than as noise.
        expect(w, greaterThan(2 * _r - 1e-6));
      }
    }
    // sqrt(2), to the resolution of a 15-degree sweep.
    expect(worst, greaterThan(1.4));
  });

  test('a camera turn alone changes the width, so it must re-stroke', () {
    // Why PlaneEntity.setStyle can no longer compare mmPerPoint alone. Same
    // zoom, same plane, same edge — two facings, two widths.
    final (dir, perp) = _edges(u, v, n).first;
    final faceOn = perp.normalized();
    final skew = (perp + n).normalized();
    final a = _silhouetteWidth(faceOn, dir, perp, n, _r);
    final b = _silhouetteWidth(skew, dir, perp, n, _r);
    expect((a - b).abs(), greaterThan(0.2 * _r),
        reason: 'if these were equal the early return would have been safe');
    // And with the scale applied, both land on the stated width — which is
    // what makes re-stroking on a turn the right answer rather than a
    // workaround.
    for (final view in [faceOn, skew]) {
      expect(
          _silhouetteWidth(view, dir, perp, n, _r * _scale(view, dir, perp, n)),
          closeTo(2 * _r, 1e-6));
    }
  });

  test('the corner stays covered when two edges differ in width', () {
    // Per-edge scaling means adjacent edges are no longer the same half-width,
    // and #50's flush corner was argued FROM their being equal. rectFrame now
    // extends each edge by its NEIGHBOUR's half-width; in the plane's own
    // (dir_i, dir_j) coordinates about the shared corner, the arriving edge
    // then spans the full depth of the leaving one and reaches exactly across
    // it, so the corner square is covered for ANY pair of widths.
    for (final (ri, rj) in const [(0.5, 0.5), (0.5, 0.35), (0.35, 0.5)]) {
      // Edge i lies along dir_i, is +-ri deep across it (i.e. along dir_j),
      // and is extended past the corner by rj.
      final reach = rj, depth = ri;
      // The corner square is +-rj along dir_i by +-ri along dir_j.
      expect(reach, greaterThanOrEqualTo(rj),
          reason: 'edge i must reach the far side of the corner square');
      expect(depth, greaterThanOrEqualTo(ri),
          reason: 'and cover its full depth while doing so');
    }
  });

  test('every plane border in the CPU painter is one point', () {
    // Both kinds of plane, hot and cold. The origin planes were already 1;
    // #69 is the work planes, which were 1.2 and 2.0.
    final src = File('lib/widgets/viewport3d.dart').readAsStringSync();
    // The scene painter draws the two kinds of plane in two consecutive
    // blocks and the axes right after them, each opened by a comment of its
    // own. Slicing on those rather than on the loop headers is what keeps
    // this pointed at the borders: `for (final key in kPlaneKeys)` also opens
    // the HIT TEST several hundred lines above, and the axes below stroke at
    // widths of their own that are not a plane's business.
    String between(String from, String to) {
      final a = src.indexOf(from);
      expect(a, greaterThan(0), reason: 'the "$from" block is still there');
      final b = src.indexOf(to, a);
      expect(b, greaterThan(a), reason: 'and "$to" still follows it');
      return src.substring(a, b);
    }

    final blocks = {
      'work planes': between('for (final w in part.workPlanes) {',
          '// ---- origin planes (fills first'),
      'origin planes': between('// ---- origin planes (fills first',
          '// ---- axes + centre point ----'),
    };
    for (final MapEntry(key: what, value: body) in blocks.entries) {
      final widths = RegExp(r'\.\.strokeWidth = ([^\n;]+)')
          .allMatches(body)
          .map((m) => m.group(1)!.trim())
          .toList();
      expect(widths, isNotEmpty, reason: '$what: the border is still stroked');
      for (final w in widths) {
        expect(w, '1',
            reason: '$what: a plane border is stroked at $w, not one point');
      }
    }
  });

  test('the corner mark is still a few points, and still more than the border',
      () {
    // The other half of the sentence — "their highlight corner points a few
    // more but Not much" — is already true, and this is what keeps it true
    // while the border it is measured against is being changed.
    expect(kPlaneCornerMark, greaterThan(1));
    expect(kPlaneCornerMark, lessThanOrEqualTo(4));
  });

  test('RealityKit scales the border to its silhouette, and re-strokes on a '
      'turn', () {
    // The engine that drew what was reported is Swift, so this is the one
    // place the two halves of the fix can be held together. Source text, in
    // the idiom issue50's own cross-painter test uses: a rasteriser cannot
    // reach RealityKit from here, and CI's iOS build is what compiles it.
    final swift =
        File('packages/reality_view/ios/Classes/PartScene.swift')
            .readAsStringSync();
    // `contains` on the whole file, not `expect(swift, contains(...))`: the
    // matcher prints its subject, and the subject here is 1500 lines of
    // Swift that would bury the one line of the reason.
    expect(swift.contains('func silhouetteScale('), isTrue,
        reason: 'OutlineStyle has no silhouetteScale');
    // rectFrame applies it rather than merely having it available.
    final at = swift.indexOf('static func rectFrame(');
    expect(at, greaterThan(0));
    final frame = swift.substring(at, swift.indexOf('MeshDescriptor', at));
    expect(frame, contains('silhouetteScale('),
        reason: 'the plane border is scaled to its silhouette');
    // And the PLANE's setStyle compares the whole style, not the width alone
    // — the frozen half of the report. Anchored to the class: AxisEntity has
    // a setStyle of its own that still compares widths alone, correctly, an
    // origin axis being the 16-gon tube this border stopped being in #50.
    final cls = swift.indexOf('final class PlaneEntity');
    expect(cls, greaterThan(0));
    final st = swift.indexOf('func setStyle(', cls);
    expect(st, greaterThan(cls));
    final body = swift.substring(st, st + 200);
    expect(body.contains('mmPerPoint != '), isFalse,
        reason: 'a pure camera turn now changes the border too');
  });
}
