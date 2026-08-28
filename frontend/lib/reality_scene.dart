// Prototype — maps the PartModel onto the RealityKit surface's payloads (M60).
//
// These are PURE functions (no channels, no platform), so they are exercised
// by host tests exactly as the native side will receive them. The heavy mesh
// buffers are the very Float32List/Int32List objects OcctMeshData already
// holds, referenced (never copied) into the payload maps — StandardMessageCodec
// transmits them as raw typed-data byte buffers.
//
// The camera/plane/axis/sketch conventions here MUST match Cam3 and the Swift
// PartRenderer; the two are two ends of one wire.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/painting.dart' show Color;

import 'app_state.dart';
import 'ffi/occt_engine.dart' show OcctMeshData;
import 'log.dart';
import 'materials.dart';
import 'part_model.dart';
import 'reality_payload.dart';
import 'text_geometry.dart' show textContours, textLayerOf;
import 'theme.dart';
export 'reality_payload.dart';

/// The committed solids the viewport draws: visible, non-consumed features,
/// minus the one being edited (its live preview is sent separately) and minus
/// the body a live BOOLEAN preview is replacing (the combined join/cut/
/// intersect result stands in for it, sent as the preview). Keyed by the
/// feature name, which is unique within a part.
List<(String, KernelSolid)> visibleSolids(AppState app, PartModel p) {
  final sess = app.extrudeSession;
  final edge = app.edgeSession;
  // M210 — A PREVIEW ONLY HIDES WHAT IT CAN STAND IN FOR.
  //
  // "When i select extrude the solid is invisible suddenly."
  //
  // Editing a feature hides that feature, and a boolean preview hides the
  // whole body it is joining into or cutting from — because the preview shows
  // the combined result and drawing both would double the shape. Right, as
  // long as there IS a preview. From the bug20260805T230356 log:
  //
  //     feature: FAIL Extrusion5 ... err=the termination face is not
  //                                    reachable from this profile
  //     reality: setScene #98: 0 solid(s) —
  //
  // The extent's face reference did not survive the re-edit, so the preview
  // failed and was null — and the body it would have replaced stayed hidden
  // anyway. Nothing was drawn at all, and the part looked deleted while a
  // panel sat open over an empty viewport.
  //
  // The slice case three lines down already states this rule ("a failed slice
  // must never make the part vanish"); it simply was not applied to the two
  // previews. Nothing to stand in means nothing to hide.
  final sessHides = sess?.preview != null;
  final edgeHides = edge?.preview != null;
  // M212 — a pattern preview stands in for its whole body exactly like a
  // fillet's does: it IS that body with the occurrences in it, so leaving the
  // un-patterned original in the scene would draw the first hole through the
  // middle of the preview.
  final pat = app.patternSession;
  final patHides = pat?.preview != null;
  final out = <(String, KernelSolid)>[];
  for (final f in p.features) {
    if (f.visible &&
        f.solid != null &&
        !f.consumedByJoin &&
        !f.rolledBack && // M91 — below End of Part

        !(sessHides && f == sess?.editing) &&
        !(sessHides && f.bodyName == sess?.previewReplacesBody) &&
        // M126 — a fillet/chamfer preview REPLACES its body; leaving the
        // original in would draw the un-filleted edges straight through it.
        !(edgeHides && f == edge?.editing) &&
        !(edgeHides && f.bodyName == edge?.previewReplacesBody) &&
        !(patHides && f == pat?.editing) &&
        !(patHides && f.bodyName == pat?.previewReplacesBody)) {
      // M168 — Slice Graphics substitutes the CUT solid for the whole one, so
      // every consumer (payload, signature, triangle budget, thumbnails) sees
      // one consistent scene. Null means "not slicing" or "the cut failed",
      // and then the solid is shown whole — a failed slice must never make the
      // part vanish.
      out.add((f.name, app.slicedSolid(f.name, f.solid!) ?? f.solid!));
    }
  }
  return out;
}

final Set<int> _conventionLogged = <int>{};

/// ONE-SHOT SELF-REPORT per mesh — ONE line, everything a device round can
/// possibly need to know about a new solid. It exists because the surface
/// convention of these meshes could not be settled by reading the code, and
/// guessing it wrong has now cost several device rounds (invisible face
/// highlight, see-through holes, a solid that reads inside-out). Each device
/// run must answer as many open questions as possible at once, so this is
/// deliberately a permanent report, not a temporary probe.
///
/// Fields:
///  * `tris/faces/verts`  — size and B-Rep face count of the tessellation.
///  * `wind`   — share of triangles whose WINDING normal cross(p1-p0, p2-p0)
///               agrees with the supplied per-vertex normal. ~1.0 means
///               winding follows the normals, ~0.0 means they oppose.
///  * `out`    — share of sampled vertices whose normal points AWAY from the
///               mesh centroid. ~1.0 = outward normals as occt_capi.h claims.
///               Reliable only for convex-ish bodies; on joined bodies it
///               drops, which is exactly what `inward` then localises.
///  * `inward` — the B-Rep faces that actually carry INWARD normals (majority
///               vote per face). This is the actionable list: a renderer bug
///               that only affects some faces will name them here.
///  * `edges`  — non-manifold or boundary edges on quantised POSITIONS (OCCT
///               duplicates vertices along face seams, so index-based counting
///               would report every seam). 0 = watertight shell, i.e. the
///               kernel is fine and any visual defect sits in the renderer.
///  * `bbox`   — world extent, to catch scale/placement surprises.
/// When false (the default) the full [meshSelfReport] — an O(triangles) pass
/// that also builds a watertightness hash map — is replaced by [meshBrief].
///
/// Measured on the device-sized gear from the M63 session: 6.9 ms at 4 636
/// triangles and **49.9 ms at 34 236**. It ran synchronously inside
/// `_pushReality`, i.e. on the UI thread, EVERY time a solid was
/// re-tessellated — three dropped frames per zoom step on one gear, and it
/// scales with the whole scene. The report is genuinely useful when chasing a
/// winding/watertightness bug, so it stays one flag away.
bool meshDiagnostics = false;

/// Cheap always-on summary: no per-triangle map or list allocation, one pass
/// for the bounding box only.
String meshBrief(String id, OcctMeshData m) {
  final pos = m.positions;
  final nTri = m.indices.length ~/ 3;
  final nV = pos.length ~/ 3;
  if (nV == 0) return 'mesh $id: EMPTY tris=$nTri verts=0';
  var minX = pos[0], minY = pos[1], minZ = pos[2];
  var maxX = pos[0], maxY = pos[1], maxZ = pos[2];
  for (var i = 1; i < nV; i++) {
    final x = pos[i * 3], y = pos[i * 3 + 1], z = pos[i * 3 + 2];
    if (x < minX) minX = x;
    if (y < minY) minY = y;
    if (z < minZ) minZ = z;
    if (x > maxX) maxX = x;
    if (y > maxY) maxY = y;
    if (z > maxZ) maxZ = z;
  }
  String r(double v) => v.toStringAsFixed(1);
  return 'mesh $id: tris=$nTri faces=${m.faceCount} verts=$nV '
      'bbox=${r(minX)},${r(minY)},${r(minZ)}..${r(maxX)},${r(maxY)},${r(maxZ)}';
}

String meshSelfReport(String id, OcctMeshData m) {
  final pos = m.positions, nor = m.normals, idx = m.indices;
  final nTri = idx.length ~/ 3;
  final nV = pos.length ~/ 3;
  if (nTri == 0 || nor.length != pos.length) {
    return 'mesh $id: EMPTY tris=$nTri verts=$nV '
        '(normals ${nor.length} != positions ${pos.length})';
  }

  var cx = 0.0, cy = 0.0, cz = 0.0;
  var minX = pos[0], minY = pos[1], minZ = pos[2];
  var maxX = pos[0], maxY = pos[1], maxZ = pos[2];
  for (var i = 0; i < nV; i++) {
    final x = pos[i * 3], y = pos[i * 3 + 1], z = pos[i * 3 + 2];
    cx += x;
    cy += y;
    cz += z;
    if (x < minX) minX = x;
    if (y < minY) minY = y;
    if (z < minZ) minZ = z;
    if (x > maxX) maxX = x;
    if (y > maxY) maxY = y;
    if (z > maxZ) maxZ = z;
  }
  cx /= nV;
  cy /= nV;
  cz /= nV;

  // Per-triangle votes. Sampled for the two global ratios (cheap on huge
  // meshes), but the per-face vote runs over ALL triangles: a single wrongly
  // oriented face is the whole point of the report and must not be sampled
  // away.
  var agree = 0, outward = 0, sampled = 0;
  final step = nTri > 600 ? nTri ~/ 600 : 1;
  final faceOut = <int, int>{};
  final faceTris = <int, int>{};
  final faceArea = <int, double>{};
  final faceNx = <int, double>{};
  final faceNy = <int, double>{};
  final faceNz = <int, double>{};
  final hasFaces = m.triFaces.length == nTri;
  for (var t = 0; t < nTri; t++) {
    final a = idx[t * 3], b = idx[t * 3 + 1], c = idx[t * 3 + 2];
    final ax = pos[a * 3], ay = pos[a * 3 + 1], az = pos[a * 3 + 2];
    final ux = pos[b * 3] - ax,
        uy = pos[b * 3 + 1] - ay,
        uz = pos[b * 3 + 2] - az;
    final vx = pos[c * 3] - ax,
        vy = pos[c * 3 + 1] - ay,
        vz = pos[c * 3 + 2] - az;
    final gx = uy * vz - uz * vy, gy = uz * vx - ux * vz, gz = ux * vy - uy * vx;
    final nx = nor[a * 3], ny = nor[a * 3 + 1], nz = nor[a * 3 + 2];
    final isOut = nx * (ax - cx) + ny * (ay - cy) + nz * (az - cz) > 0;
    if (t % step == 0) {
      if (gx * nx + gy * ny + gz * nz > 0) agree++;
      if (isOut) outward++;
      sampled++;
    }
    if (hasFaces) {
      final f = m.triFaces[t];
      faceTris[f] = (faceTris[f] ?? 0) + 1;
      if (isOut) faceOut[f] = (faceOut[f] ?? 0) + 1;
      // |cross| is twice the triangle area; the cross vector also gives the
      // face orientation. A face that is listed but renders as nothing is
      // either DEGENERATE (area ~ 0) or misplaced — these two numbers say
      // which, without needing another guess.
      final gl = math.sqrt(gx * gx + gy * gy + gz * gz);
      faceArea[f] = (faceArea[f] ?? 0) + 0.5 * gl;
      if (gl > 1e-12) {
        // Accumulate into three scalar maps. The previous version allocated a
        // fresh 3-element List for EVERY triangle, which on a 34k-triangle
        // mesh meant 34k throwaway lists inside a UI-thread frame.
        faceNx[f] = (faceNx[f] ?? 0) + gx / gl;
        faceNy[f] = (faceNy[f] ?? 0) + gy / gl;
        faceNz[f] = (faceNz[f] ?? 0) + gz / gl;
      }
    }
  }
  final w = (agree / sampled).toStringAsFixed(2);
  final o = (outward / sampled).toStringAsFixed(2);

  // Watertightness on quantised positions.
  int canon(int v) => Object.hash((pos[v * 3] * 1e5).round(),
      (pos[v * 3 + 1] * 1e5).round(), (pos[v * 3 + 2] * 1e5).round());
  final edgeUse = <int, int>{};
  for (var t = 0; t < nTri; t++) {
    final v0 = canon(idx[t * 3]),
        v1 = canon(idx[t * 3 + 1]),
        v2 = canon(idx[t * 3 + 2]);
    // unrolled: the old `for (final (a,b) in [ ... ])` allocated a list of
    // three records per triangle on top of the map work
    void bump(int a, int b) {
      final key = Object.hash(a < b ? a : b, a < b ? b : a);
      edgeUse[key] = (edgeUse[key] ?? 0) + 1;
    }
    bump(v0, v1);
    bump(v1, v2);
    bump(v2, v0);
  }
  final boundary = edgeUse.values.where((c) => c != 2).length;

  final inward = faceTris.keys
      .where((f) => (faceOut[f] ?? 0) * 2 < faceTris[f]!)
      .toList()
    ..sort();
  final inwardStr = !hasFaces
      ? 'n/a'
      : inward.isEmpty
          ? 'none'
          : inward.map((f) {
              final type = m.faceInfos.length > 15 * f
                  ? m.faceInfos[15 * f].round()
                  : -1;
              return 'f$f:t$type/${faceTris[f]}';
            }).join(',');

  String r(double v) => v.toStringAsFixed(1);

  // Per-face inventory, capped so the line stays readable.
  final fids = faceTris.keys.toList()..sort();
  final inv = fids.take(12).map((f) {
    final type =
        m.faceInfos.length > 15 * f ? m.faceInfos[15 * f].round() : -1;
    final k = faceTris[f]!;
    String c(double v) => (v / k).toStringAsFixed(1);
    return 'f$f:t$type/${k}tri/a${(faceArea[f] ?? 0).toStringAsFixed(1)}'
        '/n(${c(faceNx[f] ?? 0)},${c(faceNy[f] ?? 0)},${c(faceNz[f] ?? 0)})';
  }).join(' ');

  return 'mesh $id: tris=$nTri faces=${faceTris.length} verts=$nV '
      'wind=$w out=$o inward=$inwardStr '
      'edges=$boundary(0=watertight) '
      'bbox=${r(minX)},${r(minY)},${r(minZ)}..${r(maxX)},${r(maxY)},${r(maxZ)} '
      '[$inv]';
}

/// Things that are wrong with a mesh and cost nothing to notice.
///
/// The expensive watertightness pass stays behind [meshDiagnostics], but these
/// are single comparisons on counts that are already to hand, and each one is
/// a shape the user will see as broken. Catching them here turns "the fillet
/// looks wrong" into a logged line at the moment it was built.
List<String> meshAnomalies(OcctMeshData m) {
  final out = <String>[];
  final nTri = m.indices.length ~/ 3;
  final nV = m.positions.length ~/ 3;
  if (nV == 0 || nTri == 0) {
    out.add('EMPTY (tris=$nTri verts=$nV) — the solid exists but tessellated '
        'to nothing, so it is invisible');
    return out;
  }
  if (m.normals.length != m.positions.length) {
    out.add('normals ${m.normals.length} != positions ${m.positions.length} '
        '— shading will be wrong or the draw will be dropped');
  }
  for (var i = 0; i < m.positions.length; i++) {
    if (!m.positions[i].isFinite) {
      out.add('NON-FINITE vertex at component $i — Skia drops the whole draw, '
          'which is what "the body vanished" looks like');
      break;
    }
  }
  // Deliberately NOT flagged: a high triangle-per-face count.
  //
  // The device log that prompted this work showed 63 101 triangles across 21
  // faces, which looked like the signature of a self-intersecting blend. It
  // is not, on its own — the same solid had been meshed at 20 822 triangles a
  // moment earlier and the only thing that changed was the deflection getting
  // finer. A single tightly-curved face can legitimately carry thousands of
  // triangles. A threshold here would fire on ordinary zooming, and a warning
  // that cries wolf is worse for debugging than no warning, because it
  // teaches the reader to skim past this whole tag. The counts are already
  // logged by meshBrief on every mesh, which is where that judgement belongs.
  return out;
}

/// Emits a report once per distinct mesh object. Cheap by default; the full
/// convention/watertightness analysis only runs with [meshDiagnostics] on.
///
/// Anomalies are reported at WARN whatever the flag says: they are cheap to
/// detect and each one is a shape the user is about to call broken, so the
/// log must carry them without anybody having known to turn a flag on first.
void logMeshConvention(String id, OcctMeshData m) {
  if (!_conventionLogged.add(identityHashCode(m))) return;
  // Bounded: every re-tessellation makes a NEW mesh object, so this set would
  // otherwise grow for as long as the app runs.
  if (_conventionLogged.length > 256) _conventionLogged.clear();
  Log.i('mesh3d',
      meshDiagnostics ? meshSelfReport(id, m) : meshBrief(id, m));
  final bad = meshAnomalies(m);
  for (final a in bad) {
    Log.w('mesh3d', '$id: $a');
  }
  // One anomaly is worth the expensive report even when the flag is off —
  // this is the one mesh anyone will want the full analysis of.
  if (bad.isNotEmpty && !meshDiagnostics) {
    Log.w('mesh3d', 'full analysis: ${meshSelfReport(id, m)}');
  }
}

/// M186 — what actually crossed into the native renderer, and when.
///
/// On iOS the 3D body is drawn by RealityKit behind a platform view. Nothing
/// on the Dart side can see the result, and a screenshot cannot contain it
/// either, so "the model is there but the screen is wrong" had no evidence on
/// either side of the boundary. This is the Dart side of it: the exact solids,
/// revisions and camera last handed over. If this says a body was pushed with
/// 4 148 triangles and the screen is empty, the fault is past this line; if
/// the body was never pushed, it is before it.
class RealityPush {
  RealityPush._();

  static DateTime? lastSceneAt;
  static DateTime? lastCameraAt;
  static int sceneCount = 0;
  static int cameraCount = 0;
  static String lastSceneSig = '(no scene has ever been pushed)';
  static List<String> lastSolids = const [];
  static String lastCamera = '(none)';

  static void recordScene(String sig, List<String> solids) {
    lastSceneAt = DateTime.now();
    lastSceneSig = sig;
    lastSolids = List.unmodifiable(solids);
    sceneCount++;
    Log.i('reality',
        'setScene #$sceneCount: ${solids.length} solid(s) — ${solids.join(', ')}');
  }

  static void recordCamera(String cam) {
    lastCameraAt = DateTime.now();
    lastCamera = cam;
    cameraCount++;
  }

  /// Pulls the NATIVE timing table from the live RealityKit view, or an empty
  /// map when there is no view.
  ///
  /// The controller belongs to the 3D viewport's widget State, which the bug
  /// bundle has no business reaching into — and a global reference to it would
  /// outlive the view and push into a dead channel. So the viewport REGISTERS
  /// a drain closure while it is mounted and clears it on dispose, and this is
  /// the one place that knows the closure exists. Same shape as [dump]: the
  /// bundle asks RealityPush, not the widget tree.
  static Future<Map<String, dynamic>> Function()? nativeDrain;

  static Future<Map<String, dynamic>> drainNative() async {
    final f = nativeDrain;
    if (f == null) return const {};
    try {
      return await f();
    } catch (_) {
      return const {};
    }
  }

  static List<String> dump() => [
        'RealityKit is a PLATFORM VIEW: it composites outside Flutter, so it',
        'never appears in a screenshot and Dart cannot read back what it drew.',
        'This is what Dart HANDED IT — the last word before the boundary.',
        '',
        'scene pushes: $sceneCount, last at '
            '${lastSceneAt?.toIso8601String() ?? 'never'}',
        'camera pushes: $cameraCount, last at '
            '${lastCameraAt?.toIso8601String() ?? 'never'}',
        'last scene signature: $lastSceneSig',
        'last camera: $lastCamera',
        'solids in the last scene (${lastSolids.length}):',
        for (final s in lastSolids) '  $s',
        if (lastSolids.isEmpty)
          '  (none — if the viewport looks empty, it IS empty by this point,'
              ' and the fault is upstream of the renderer)',
      ];
}

/// Current mesh revision per visible solid. The widget keeps the last set it
/// pushed and hands it back as `knownRevs`, so unchanged solids travel as a
/// two-field stub instead of megabytes of geometry.
Map<String, int> sceneRevs(AppState app, PartModel p) => {
      for (final (id, s) in visibleSolids(app, p)) id: identityHashCode(s.mesh),
      // M250 — the in-place context, on the same terms. A surrounding
      // component's mesh does not change while you edit the part in front of
      // it, so without this entry every heavy push would re-upload the whole
      // assembly to say nothing had happened to it.
      for (final (path, _, sol) in app.inPlaceContextPieces)
        inPlaceContextId(app.inPlaceEdit!.assembly, path):
            identityHashCode(sol.mesh),
    };

List<Map<String, dynamic>> _planePayloads(AppState app, PartModel p,
    {String? hover}) {
  final out = <Map<String, dynamic>>[];
  for (final key in kPlaneKeys) {
    final f = planeFrame(key);
    // M83: the plane FRAMES the part — its own (u,v) rectangle, padded, and
    // asymmetric, so its width/height are the part's width/height. `ext` is
    // kept alongside as the largest half-extent purely so an older native
    // build (which reads only `ext`) still draws something sane.
    final (uMin, uMax, vMin, vMax) = originPlaneRect(p, key);
    out.add({
      'key': key,
      'frame': frame9(f),
      'origin': [f.origin.x, f.origin.y, f.origin.z],
      'uMin': uMin,
      'uMax': uMax,
      'vMin': vMin,
      'vMax': vMax,
      'ext': [uMin.abs(), uMax.abs(), vMin.abs(), vMax.abs()]
          .reduce((a, b) => a > b ? a : b),
      'visible': p.vis[key] == true || (app.pickPlane && !p.hasSolid),
      'hot': hover == key,
    });
  }
  // M165 — user work planes ride the SAME list. They were built, named and
  // saved (Part4.part.json has two) but never reached the renderer: this
  // payload only ever carried the three origin planes, so on the device a
  // work plane was invisible the moment it was created. Emitting them here
  // rather than as a new array means the native side draws them with the code
  // it already has, and they are sized by `planeRectFor` — the very function
  // the origin planes use (M151 kept it shared on purpose), so a work plane
  // frames the model exactly as they do instead of being a fixed square.
  for (final w in p.workPlanes) {
    final (uMin, uMax, vMin, vMax) = planeRectFor(p, w.frame);
    out.add({
      'key': w.id,
      'frame': frame9(w.frame),
      'origin': [w.frame.origin.x, w.frame.origin.y, w.frame.origin.z],
      'uMin': uMin,
      'uMax': uMax,
      'vMin': vMin,
      'vMax': vMax,
      'ext': [uMin.abs(), uMax.abs(), vMin.abs(), vMax.abs()]
          .reduce((a, b) => a > b ? a : b),
      'visible': w.visible,
      'hot': hover == w.id,
    });
  }
  // M174 — the plane being dragged into existence. Rides the same list so the
  // native side draws it with no new code, and is dropped the instant the
  // drag ends: it is a preview, not a document object.
  final prev = app.wpCreatePreview;
  if (prev != null) {
    final (uMin, uMax, vMin, vMax) = planeRectFor(p, prev);
    out.add({
      'key': 'wp:preview',
      'frame': frame9(prev),
      'origin': [prev.origin.x, prev.origin.y, prev.origin.z],
      'uMin': uMin,
      'uMax': uMax,
      'vMin': vMin,
      'vMax': vMax,
      'ext': [uMin.abs(), uMax.abs(), vMin.abs(), vMax.abs()]
          .reduce((a, b) => a > b ? a : b),
      'visible': true,
      'hot': true, // a preview reads as the thing under your finger
    });
  }
  return out;
}

const _axisDirs = <(String, Vec3)>[
  ('x', Vec3(1, 0, 0)),
  ('y', Vec3(0, 1, 0)),
  ('z', Vec3(0, 0, 1)),
];

List<Map<String, dynamic>> _axisPayloads(PartModel p, {String? hover}) {
  final out = <Map<String, dynamic>>[];
  for (final (key, d) in _axisDirs) {
    // M83: axes span the same padded box as the planes, so the triad neither
    // pokes out of a small plane nor vanishes inside a large part. `ext` stays
    // as the largest half-length for older native builds.
    final (lo, hi) = originAxisSpan(p, d);
    out.add({
      'key': key,
      'dir': [d.x, d.y, d.z],
      'lo': lo,
      'hi': hi,
      'ext': hi.abs() > lo.abs() ? hi.abs() : lo.abs(),
      'visible': p.vis[key] == true,
      'hot': hover == key,
    });
  }
  return out;
}

/// ARGB colour a sketch curve is drawn in, matching Viewport2D exactly.
///
/// The 2D editor uses four: white for geometry that is fully constrained on
/// the layer you are editing, blue-violet for under-constrained, yellow for a
/// projection, grey for reference geometry on another layer. 3D used to paint
/// every curve one flat colour, so a sketch read completely differently
/// depending on which viewport you were looking at.
int sketchGeoColor(
    {required bool projection,
    required bool dofKnown,
    required bool fullyConstrained}) {
  const white = 0xFFFFFFFF;
  const violet = 0xFF9A8CF5; // under-constrained
  const yellow = 0xFFE8C84A; // projected geometry
  if (projection) return yellow;
  // Mirrors Viewport2D exactly: `segFull(i,0) => hasAnalysis && carrierFixed`,
  // so NO analysis means NOT constrained, i.e. violet. M81 had this backwards
  // and defaulted to white, which is why curves showed white in 3D while 2D
  // showed them violet — most visibly right after an edit, before the next
  // _reanalyze() has run.
  if (!dofKnown) return violet;
  return fullyConstrained ? white : violet;
}

/// Child sketches as world-space polylines, honouring hidden layers, the
/// end-of-sketch marker and session visibility (mirrors Viewport3D._paintSketch).
List<Map<String, dynamic>> _sketchPayloads(AppState app, PartModel p) {
  final sess = app.extrudeSession;
  final out = <Map<String, dynamic>>[];
  for (final cs in p.childSketches) {
    final showForSession = sess?.sketchName == cs.model.name ||
        (sess != null && sess.sketchName == null);
    if (!cs.visible && !showForSession) continue;
    final frame = sketchFrameOf(cs);
    final polylines = <Float32List>[];
    final keys = <String>[];
    final colors = <int>[];
    // Construction geometry is scaffolding, hidden unless this sketch is the
    // one being edited — Viewport2D's
    // `if (!app.inEditMode && g.isConstruction) continue`.
    final editing = app.inEditMode &&
        app.activeChild != null &&
        (identical(app.activeChild, cs.model) ||
            app.activeChild!.name == cs.model.name);
    // M93 — THE SKETCH BEING EDITED IS NOT SENT TO 3D AT ALL.
    //
    // Viewport2D draws it live, on top, every frame. The RealityKit copy is
    // rebuilt only when the scene payload is rebuilt, so while you drag a grip
    // the two drift apart and you see the SAME rectangle twice: the live one
    // under your finger and a frozen ghost where it used to be (reported with
    // a screenshot; the drag log shows 2D following the finger exactly while
    // the 3D copy stayed put). It also leaked construction geometry into the
    // 3D view, because `editing` was the very flag that switched construction
    // ON here.
    //
    // Inventor keeps the MODEL live behind an open sketch — the solids, the
    // other sketches — not a second copy of the sketch you are drawing. So the
    // rule is simply: whoever owns the live rendering owns it alone.
    if (editing) continue;
    // M113 — a sketch below End of Part is not part of the model yet.
    if (cs.rolledBack) continue;

    // DOF colouring needs the analysis, and app.analysis describes app.current
    // ONLY — its indices mean nothing for any other sketch, so DOF is applied
    // just to that one. Note this is independent of edit mode: 2D tints by DOF
    // whether or not you are editing.
    final cur = app.current;
    final dofSketch = cur != null &&
        (identical(cur, cs.model) || cur.name == cs.model.name);
    for (var gi = 0; gi < cs.model.geometry.length; gi++) {
      final g = cs.model.geometry[gi];
      if (cs.model.hiddenLayers.contains(g.layer)) continue;
      final li = cs.model.layers.indexOf(g.layer);
      if (li >= 0 && li >= cs.model.eosAfter) continue;
      // Construction lines are scaffolding: hidden unless this sketch is the
      // one being edited. Mirrors viewport.dart's
      // `if (!app.inEditMode && g.isConstruction) continue`.
      if (!editing && g.isConstruction) continue;
      final pts = sketchCurve(g);
      if (pts.length < 2) continue;
      keys.add(sketchKey(cs.model.name, gi));
      final a = dofSketch ? app.analysis : null;
      colors.add(sketchGeoColor(
          projection: g.isProjection,
          dofKnown: a != null,
          fullyConstrained: a?.carrierFixed(gi, 0) ?? false));
      // Float32 (M74) — must match the solid buffers, because Swift decodes
      // both through the same Payload.floats. Sending one of them as Float64
      // would make it read the bytes as Float32 and produce garbage.
      final buf = Float32List(pts.length * 3);
      for (var i = 0; i < pts.length; i++) {
        final w = frame.toWorld(pts[i]);
        buf[i * 3] = w.x;
        buf[i * 3 + 1] = w.y;
        buf[i * 3 + 2] = w.z;
      }
      polylines.add(buf);
    }
    // M220 — the sketch's TEXTS, as the closed contours they now are. Their
    // key carries an index PAST the geometry list: a long press still finds
    // the sketch (everything before the '#'), while nothing can mistake a
    // letter for entity number so-and-so.
    var tk = cs.model.geometry.length;
    for (final t in cs.model.texts) {
      final layer = textLayerOf(t);
      if (cs.model.hiddenLayers.contains(layer)) continue;
      final li = cs.model.layers.indexOf(layer);
      if (li >= 0 && li >= cs.model.eosAfter) continue;
      for (final c in textContours(cs.model, t)) {
        if (c.length < 3) continue;
        final ring = [...c, c.first];
        keys.add(sketchKey(cs.model.name, tk++));
        colors.add(sketchGeoColor(
            projection: false, dofKnown: false, fullyConstrained: false));
        final buf = Float32List(ring.length * 3);
        for (var i = 0; i < ring.length; i++) {
          final w = frame.toWorld(ring[i]);
          buf[i * 3] = w.x;
          buf[i * 3 + 1] = w.y;
          buf[i * 3 + 2] = w.z;
        }
        polylines.add(buf);
      }
    }
    if (polylines.isNotEmpty) {
      out.add({
        'polylines': polylines,
        'keys': keys,
        'colors': colors,
        // Normal of the sketch plane: lets the renderer lift a sketch drawn ON
        // a solid face clear of that face (they are exactly coplanar).
        'n': [frame.n.x, frame.n.y, frame.n.z],
      });
    }
  }
  return out;
}

/// Stable address of one sketch curve: sketch name + its index in the sketch's
/// geometry list. Used to highlight and select individual curves in 3D.
String sketchKey(String sketchName, int geoIndex) => '$sketchName#$geoIndex';

/// M127 — accented B-Rep edges, sent as RAW WORLD POLYLINES.
///
/// Was "display edge N of solid X", which broke the moment a fillet preview
/// went up: the previewed body is hidden, so it is no longer in the scene, so
/// the renderer has no geometry to hang the ribbon on and the hover
/// prehighlight silently vanished. Sending the points themselves makes the
/// accent independent of whether its body is drawn — which is the whole point,
/// since you pick edges on a body precisely while it is being replaced by a
/// preview of what filleting them would do.
///
/// Hover and selection merge into one set, as before.
Map<String, dynamic>? _edgeAccentPayload(AppState app) {
  final sel = app.pickedEdgeSolid;
  final hov = app.hoverEdge3d;
  if (sel == null && hov == null) return null;
  final lines = <Float32List>[];

  /// The edge's points as a FLOAT32 slice — the wire format every other point
  /// payload uses (`edgePoints32`, read back by Payload.floats as 32-bit).
  /// Sending the float64 buffer instead hands the renderer 64-bit doubles
  /// reinterpreted as 32-bit floats, which is not "slightly off" but complete
  /// nonsense: lines nowhere near the part, some of them enormous.
  Float32List? poly(KernelSolid s, int i) {
    final m = s.mesh;
    if (i < 0 || i + 1 >= m.edgeStarts.length) return null;
    final a = m.edgeStarts[i], b = m.edgeStarts[i + 1];
    final src = m.edgePoints32;
    if (b - a < 2 || b * 3 > src.length) return null;
    return Float32List.sublistView(src, a * 3, b * 3);
  }

  if (sel != null) {
    for (final d in app.pickedEdgeDisplay) {
      final l = poly(sel, d);
      if (l != null) lines.add(l);
    }
  }
  if (hov != null && hov.$2 >= 0) {
    // Skip a hovered edge already in the set: one ribbon, not two stacked.
    if (!(identical(hov.$1, sel) && app.pickedEdgeDisplay.contains(hov.$2))) {
      final l = poly(hov.$1, hov.$2);
      if (l != null) lines.add(l);
    }
  }
  return lines.isEmpty ? null : {'lines': lines};
}

/// The blue prehighlight target ({solid id, face id}) or null.
Map<String, dynamic>? _highlightPayload(
    AppState app, PartModel p, (KernelSolid, int)? hoverFace) {
  if (hoverFace == null || hoverFace.$2 < 0) return null;
  for (final (id, s) in visibleSolids(app, p)) {
    if (identical(s, hoverFace.$1)) {
      return {'solid': id, 'face': hoverFace.$2};
    }
  }
  return null;
}

/// The full scene: geometry + overlays' current visibility/hover. Sent only
/// when [sceneSignature] changes.
/// M250 — the id prefix every EDIT-IN-PLACE context piece travels under.
///
/// The renderer keys its entity cache on the id, so a context piece needs one
/// that can collide with nothing else in the scene. The prefix separates it
/// from the part's own features, and it says what the entity IS, so a stale
/// context entity can be told apart from a feature that has been deleted.
const String kInPlaceContextId = 'ctx/';

/// The payload id of one context piece.
///
/// The ASSEMBLY's name is in it, and that is not decoration. The renderer's
/// cache holds a mesh per id, and a mesh travels only when its revision has
/// changed (see [sceneRevs]) — a reflected component's flip is in its BUFFERS,
/// not in its transform, so two documents that both place a "Lid:1" of the
/// same part, one mirrored and one not, would share an id, share a revision,
/// and the second would be drawn with the first one's handedness. Naming the
/// document makes the two different entities, which is what they are.
String inPlaceContextId(String assembly, String path) =>
    '$kInPlaceContextId$assembly/$path';

/// The surrounding assembly's pieces, as scene solids, for an in-place edit.
///
/// Steel like everything else, with the DIM tint the CPU painter's veil says
/// the same thing with (see paintPartSolids' `contextTint`): on device a
/// component is dimmed by its material, because that is the only per-solid
/// colour the payload carries. Empty for every ordinary part render.
List<Map<String, dynamic>> _inPlaceContextPayloads(AppState app,
    {Map<String, int>? knownRevs}) {
  final ctx = app.inPlaceContextPieces;
  if (ctx.isEmpty) return const [];
  final dim =
      (Color.lerp(T.solid, T.viewport, 0.55) ?? T.solid).toARGB32();
  final asm = app.inPlaceEdit!.assembly;
  return [
    for (final (path, at, sol) in ctx)
      solidPayload(
        inPlaceContextId(asm, path),
        sol,
        at: at.at,
        rot: at.rot,
        mirror: at.reflect,
        tint: dim,
        includeGeometry: knownRevs?[inPlaceContextId(asm, path)] !=
            identityHashCode(sol.mesh),
      ),
  ];
}

Map<String, dynamic> buildScenePayload(AppState app, PartModel p,
    {String? hover,
    (KernelSolid, int)? hoverFace,
    String? hoverSketch,
    Set<String>? selSketch,
    Map<String, int>? knownRevs}) {
  final sess = app.extrudeSession;
  final scene = <String, dynamic>{
    'solids': [
      // M98 — while a target body is being picked, the body under the cursor
      // is drawn in the PREVIEW material, so 3D lights up the same body the
      // browser row does. Both sides read app.hoverBody, so they cannot
      // disagree about what a click would take.
      for (final (id, s) in visibleSolids(app, p))
        solidPayload(id, s,
            // M100 — no extra tint on the hovered body. The hover already
            // re-previews the extrusion against it (AppState.setHoverBody), so
            // tinting as well produced two overlapping highlights on the same
            // solid, which is what looked "really off".
            material: kMatSteel,
            // A body SELECTED in the browser is tinted, the way a selected
            // assembly component is: the whole body answers, because that is
            // what the row names — and the one merely HOVERED there gets the
            // same hue mixed most of the way back to steel. The renderer
            // carries the tint on the material, so this travels even when the
            // mesh does not.
            tint: _bodyRowTint(app, p, id),
            // M99 — a hovered body must carry its geometry even when the mesh
            // has not changed: the renderer applies the material while it
            // builds the mesh, so a material-only payload was silently
            // ignored and the browser row lit up while 3D did not.
            // Every solid, not just the hovered one: when the hover MOVES
            // AWAY, the body that was lit needs its steel material applied
            // again, and that only happens if its geometry travels too.
            includeGeometry: app.pickingBody ||
                knownRevs?[id] != identityHashCode(s.mesh)),
      // M250 — and the rest of the assembly, when this part is being edited
      // in place. They ride the SAME list as the part's own bodies, which is
      // what puts them in the same depth buffer: RealityKit sorts by depth
      // whatever order the payload arrives in, so a component in front of the
      // part hides it, exactly as the CPU painter's shared occluder does.
      ..._inPlaceContextPayloads(app, knownRevs: knownRevs),
    ],
    // M273 — the RENDERED view: PBR materials, lights that cast shadows, no
    // edge overlay. One boolean, because it is one decision; every difference
    // it makes is the renderer's own.
    'render': p.displayMode.isRendered,
    'planes': _planePayloads(app, p, hover: hover),
    'axes': _axisPayloads(p, hover: hover),
    'cp': {'visible': p.vis['cp'] == true, 'hot': hover == 'cp'},
    'sketches': _sketchPayloads(app, p),
  };
  final preview = sess?.preview;
  if (preview != null) {
    scene['preview'] = solidPayload('__preview__', preview, material: kMatPreview);
  } else if (app.edgeSession?.preview != null) {
    // Normal steel, not kMatPreview: this preview stands in for the WHOLE
    // body, and a translucent body is much harder to judge a fillet on than
    // a solid one. The open panel is the signal that it is uncommitted.
    scene['preview'] =
        solidPayload('__preview__', app.edgeSession!.preview!);
  } else if (app.patternSession?.preview != null) {
    // Same reasoning as the fillet preview: it is the whole body, so it is
    // drawn as one — you cannot count holes through frosted glass.
    scene['preview'] =
        solidPayload('__preview__', app.patternSession!.preview!);
  }
  final hl = _highlightPayload(app, p, hoverFace);
  if (hl != null) scene['highlight'] = hl;
  final ea = _edgeAccentPayload(app);
  if (ea != null) scene['edgeAccent'] = ea;
  if (hoverSketch != null) scene['hoverSketch'] = hoverSketch;
  scene['selSketch'] = (selSketch ?? const <String>{}).toList();
  return scene;
}

/// Light per-move push: hover tints + visibility + face highlight, no meshes.
Map<String, dynamic> buildOverlaysPayload(AppState app, PartModel p,
    {String? hover,
    (KernelSolid, int)? hoverFace,
    String? hoverSketch,
    Set<String>? selSketch}) {
  final out = <String, dynamic>{
    'planes': [
      for (final key in kPlaneKeys)
        {
          'key': key,
          'visible': p.vis[key] == true || (app.pickPlane && !p.hasSolid),
          'hot': hover == key,
        }
    ],
    'axes': [
      for (final (key, _) in _axisDirs)
        {'key': key, 'visible': p.vis[key] == true, 'hot': hover == key}
    ],
    'cp': {'visible': p.vis['cp'] == true, 'hot': hover == 'cp'},
  };
  final hl = _highlightPayload(app, p, hoverFace);
  if (hl != null) out['highlight'] = hl;
  // Always present on the LIGHT path, even when empty: an accent that has
  // just been cleared has to travel, or the last highlight stays on screen.
  out['edgeAccent'] =
      _edgeAccentPayload(app) ?? const <String, dynamic>{};
  if (hoverSketch != null) out['hoverSketch'] = hoverSketch;
  out['selSketch'] = (selSketch ?? const <String>{}).toList();
  return out;
}

/// A cheap signature over everything that lives in a [buildScenePayload]. When
/// it is unchanged the app skips re-uploading the (large) mesh buffers. Mesh
/// identity flips on extrude/refine; sketch geometry is static in the 3D view
/// (edits happen in the 2D sketcher, which shows a different widget), so a
/// count/eos/visibility fingerprint suffices there.
/// M98 — is the solid published under [featureId] part of the hovered body?
///
/// `visibleSolids` keys solids by FEATURE name; a body is the name several
/// features build into, so the whole body lights up rather than just the
/// feature the cursor happens to be over.
bool _bodyIsHovered(AppState app, PartModel p, String featureId) {
  if (!app.pickingBody) return false;
  final hb = app.hoverBody;
  if (hb == null) return false;
  for (final f in p.features) {
    if (f.name == featureId) return f.bodyName == hb;
  }
  return false;
}

/// M242 — the tint for the solid published under [featureId]: the selection
/// colour when the feature builds the body selected in the browser, the hover
/// tone when it builds the one under the pointer there, [kNoTint] otherwise.
///
/// Selection WINS on a body that is both. Two tints would compound into a
/// third colour that means nothing, and "selected" is the stronger statement —
/// the same rule, and the same two tones, as [assemblyTint].
///
/// M272 — and under both of them, the body's own MATERIAL. Same field, same
/// renderer; the difference is only that a material outlives the pointer. The
/// order is the point: selection is a question the user just asked, an
/// appearance is a fact they set once, so the question is on top.
///
/// Feature-keyed like [_bodyIsHovered], and for the same reason: a body is the
/// name several features build into, so the WHOLE body lights up rather than
/// the one feature the row happens to sit over.
///
/// M284 — [AppState.previewMaterial] wins over the selection highlight on the
/// SELECTED body while the appearance menu is open: hovering a swatch has to
/// show what the body would actually look like, and a colour can't be judged
/// through a translucent blue wash over it.
int _bodyRowTint(AppState app, PartModel p, String featureId) {
  final sel = app.selectedBody;
  final hov = app.browserHoverBody;
  for (final f in p.features) {
    if (f.name != featureId) continue;
    if (f.bodyName == sel) {
      final pv = app.previewMaterial;
      if (pv != null) return materialArgb(pv) ?? kNoTint;
      return T.faceHighlight.toARGB32();
    }
    if (f.bodyName == hov) {
      return (Color.lerp(T.solid, T.faceHighlight, 0.38) ?? T.faceHighlight)
          .toARGB32();
    }
    return materialArgb(p.bodyMaterials[f.bodyName]) ?? kNoTint;
  }
  return kNoTint;
}

String sceneSignature(AppState app, PartModel p) {
  final sess = app.extrudeSession;
  final sb = StringBuffer();
  for (final (id, s) in visibleSolids(app, p)) {
    sb..write(id)..write(':')..write(identityHashCode(s.mesh))..write(';');
  }
  // M250 — the in-place context is part of the STRUCTURE: entering or leaving
  // an in-place edit adds or removes whole solids, and so does hiding a
  // component of the parent assembly while you are inside one. Without this
  // the heavy push would not fire and the assembly would stay on screen after
  // Return, or never appear on the way in.
  //
  // The PLACEMENT is in here too, unlike the assembly viewport's signature
  // which deliberately leaves placements out (a drag rides the light push).
  // There is no drag here: nothing moves the surrounding components while a
  // part is being edited, and a placement that changed between edits has to
  // reach the renderer on the only push that carries one.
  final inPlace = app.inPlaceEdit;
  for (final (path, at, sol) in app.inPlaceContextPieces) {
    sb
      ..write(inPlaceContextId(inPlace!.assembly, path))
      ..write(':')
      ..write(identityHashCode(sol.mesh))
      ..write('@')
      ..write(at.at.x.toStringAsFixed(3))
      ..write(',')
      ..write(at.at.y.toStringAsFixed(3))
      ..write(',')
      ..write(at.at.z.toStringAsFixed(3))
      ..write(',')
      ..write(at.rot.x.toStringAsFixed(4))
      ..write(',')
      ..write(at.rot.y.toStringAsFixed(4))
      ..write(',')
      ..write(at.rot.z.toStringAsFixed(4))
      ..write(',')
      ..write(at.rot.w.toStringAsFixed(4))
      ..write(at.mirrored ? ',m' : '')
      ..write(';');
  }
  // The marker itself: rolling it changes which features are drawn, and after
  // a recompute the surviving meshes can be the SAME objects as before.
  sb..write('eop:')..write(p.eopAfter)..write(';');
  sb
    ..write('prev:')
    ..write(sess?.preview == null ? 0 : identityHashCode(sess!.preview!.mesh))
    ..write(';prevrepl:')
    ..write(sess?.previewReplacesBody ?? '')
    ..write(';eprev:')
    ..write(app.edgeSession?.preview == null
        ? 0
        : identityHashCode(app.edgeSession!.preview!.mesh))
    ..write(';eprevrepl:')
    ..write(app.edgeSession?.previewReplacesBody ?? '')
    ..write(';pprev:')
    ..write(app.patternSession?.preview == null
        ? 0
        : identityHashCode(app.patternSession!.preview!.mesh))
    ..write(';pprevrepl:')
    ..write(app.patternSession?.previewReplacesBody ?? '')
    ..write(';pick:')
    ..write(app.pickPlane ? 1 : 0)
    ..write(';vis:');
  for (final k in const ['yz', 'xz', 'xy', 'x', 'y', 'z', 'cp']) {
    sb.write(p.vis[k] == true ? '1' : '0');
  }
  // M165 — work planes must be IN the signature. M95 and M122 were both the
  // same lesson: anything that changes the picture and is not here means no
  // rebuild is sent and the change "does not work". A plane's position is
  // part of that, not just its existence — re-offsetting one moves it.
  sb..write(';slice:')..write(app.sliceGraphics ? '1' : '0');
  // The preview MOVES every frame of the drag, so its offset is part of the
  // signature or the plane would appear frozen while the finger moves.
  sb
    ..write(';wpnew:')
    ..write(app.wpCreateBase == null
        ? '-'
        : app.wpCreateOffset.toStringAsFixed(4));
  sb.write(';wp:');
  for (final w in p.workPlanes) {
    sb
      ..write(w.id)
      ..write(w.visible ? '+' : '-')
      ..write(w.frame.origin.x.toStringAsFixed(4))
      ..write(',')
      ..write(w.frame.origin.y.toStringAsFixed(4))
      ..write(',')
      ..write(w.frame.origin.z.toStringAsFixed(4))
      ..write(';');
  }
  // M95 — WHICH sketch is open belongs in the signature. Since M93 the sketch
  // being edited is deliberately left out of the payload (Viewport2D draws it
  // live), so opening and CLOSING a sketch changes what the scene contains —
  // but nothing here noticed, so no rebuild was pushed and the finished sketch
  // stayed invisible in 3D until some unrelated change (opening the extrude
  // dialog, which moves `prev:`) forced one. That is exactly the reported
  // "sketch is gone until I open and cancel Extrude".
  sb
    // M98 — the hovered body changes what the solids look like, so it must
    // move the signature or no rebuild is pushed and nothing lights up. Only
    // while picking, so ordinary hovering costs nothing.
    ..write(';hb:')
    ..write(app.pickingBody ? (app.hoverBody ?? '') : '')
    // The selected and hovered bodies are TINTED, so they change the picture:
    // without them in the signature no rebuild is pushed and the browser row
    // would light up on its own — the M98 lesson, one state later.
    ..write(';selb:')
    ..write(app.selectedBody ?? '')
    ..write(';hbrow:')
    ..write(app.browserHoverBody ?? '')
    // M272 — an APPEARANCE is a tint too, and the part's light push carries no
    // solid tints at all (see buildOverlaysPayload — only the assembly's
    // does). Without this a body painted brass would keep its old colour until
    // something else happened to move the signature. The same lesson as the
    // two lines above, one state later again.
    ..write(';mat:')
    ..write([
      for (final e in (p.bodyMaterials.keys.toList()..sort()))
        '$e=${p.bodyMaterials[e]}'
    ].join(','))
    // M273 — the display mode changes every material AND whether the edge
    // overlay exists, so it is the heaviest rebuild there is.
    ..write(';view:')
    ..write(p.displayMode.id)
    ..write(';edit:')
    ..write(app.inEditMode ? (app.activeChild?.name ?? '?') : '')
    ..write(';sk:');
  for (final cs in p.childSketches) {
    sb
      ..write(cs.model.name)
      ..write('#')
      ..write(cs.model.geometry.length)
      ..write('/')
      ..write(cs.model.eosAfter)
      ..write('/')
      ..write(cs.visible ? 1 : 0)
      // M122 — rolled-back sketches are dropped from the payload, so the
      // marker moving past one CHANGES the scene. Without this the signature
      // was identical, no rebuild was pushed, and End of Part appeared to have
      // no effect on sketches at all.
      ..write(cs.rolledBack ? 'R' : '-')
      ..write(',');
  }
  return sb.toString();
}

