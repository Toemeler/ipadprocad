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

import 'app_state.dart';
import 'ffi/occt_engine.dart' show OcctMeshData;
import 'log.dart';
import 'part_model.dart';
import 'reality_payload.dart';
export 'reality_payload.dart';

/// The committed solids the viewport draws: visible, non-consumed features,
/// minus the one being edited (its live preview is sent separately) and minus
/// the body a live BOOLEAN preview is replacing (the combined join/cut/
/// intersect result stands in for it, sent as the preview). Keyed by the
/// feature name, which is unique within a part.
List<(String, KernelSolid)> visibleSolids(AppState app, PartModel p) {
  final sess = app.extrudeSession;
  final out = <(String, KernelSolid)>[];
  for (final f in p.features) {
    if (f.visible &&
        f.solid != null &&
        !f.consumedByJoin &&
        f != sess?.editing &&
        f.bodyName != sess?.previewReplacesBody) {
      out.add((f.name, f.solid!));
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

/// Emits a report once per distinct mesh object. Cheap by default; the full
/// convention/watertightness analysis only runs with [meshDiagnostics] on.
void logMeshConvention(String id, OcctMeshData m) {
  if (!_conventionLogged.add(identityHashCode(m))) return;
  // Bounded: every re-tessellation makes a NEW mesh object, so this set would
  // otherwise grow for as long as the app runs.
  if (_conventionLogged.length > 256) _conventionLogged.clear();
  Log.i('mesh3d',
      meshDiagnostics ? meshSelfReport(id, m) : meshBrief(id, m));
}

/// Current mesh revision per visible solid. The widget keeps the last set it
/// pushed and hands it back as `knownRevs`, so unchanged solids travel as a
/// two-field stub instead of megabytes of geometry.
Map<String, int> sceneRevs(AppState app, PartModel p) => {
      for (final (id, s) in visibleSolids(app, p)) id: identityHashCode(s.mesh),
    };

Float64List _frame9(PlaneFrame f) => Float64List.fromList([
      f.u.x, f.u.y, f.u.z, //
      f.v.x, f.v.y, f.v.z, //
      f.n.x, f.n.y, f.n.z, //
    ]);

List<Map<String, dynamic>> _planePayloads(AppState app, PartModel p,
    {String? hover}) {
  final out = <Map<String, dynamic>>[];
  for (final key in kPlaneKeys) {
    final f = planeFrame(key);
    out.add({
      'key': key,
      'frame': _frame9(f),
      'origin': [f.origin.x, f.origin.y, f.origin.z],
      'ext': 10.0,
      'visible': p.vis[key] == true || (app.pickPlane && !p.hasSolid),
      'hot': hover == key,
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
  return [
    for (final (key, d) in _axisDirs)
      {
        'key': key,
        'dir': [d.x, d.y, d.z],
        'ext': 10.0,
        'visible': p.vis[key] == true,
        'hot': hover == key,
      }
  ];
}

/// ARGB colour a sketch curve is drawn in, matching Viewport2D exactly.
///
/// The 2D editor uses four: white for geometry that is fully constrained on
/// the layer you are editing, blue-violet for under-constrained, yellow for a
/// projection, grey for reference geometry on another layer. 3D used to paint
/// every curve one flat colour, so a sketch read completely differently
/// depending on which viewport you were looking at.
int sketchGeoColor({required bool projection, required bool editing,
    required bool fullyConstrained}) {
  const white = 0xFFFFFFFF;
  const violet = 0xFF9A8CF5; // under-constrained, an EDITING signal
  const yellow = 0xFFE8C84A; // projected geometry
  if (projection) return yellow;
  // Outside the sketch being edited, DOF is not information the viewer can
  // act on, so everything reads plain white — same as 2D.
  if (!editing) return white;
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
    // Whether THIS sketch is the one open for editing. Construction geometry
    // and the under-constrained tint are editing aids, so outside that they
    // are not shown — exactly the rule Viewport2D already applies.
    final editing = app.inEditMode &&
        app.activeChild != null &&
        (identical(app.activeChild, cs.model) ||
            app.activeChild!.name == cs.model.name);
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
      colors.add(sketchGeoColor(
          projection: g.isProjection,
          editing: editing,
          // carrierFixed is the same DOF source Viewport2D paints from; with
          // no analysis yet, treat it as constrained rather than flashing
          // every curve violet on the first frame.
          fullyConstrained:
              !editing || (app.analysis?.carrierFixed(gi, 0) ?? true)));
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
Map<String, dynamic> buildScenePayload(AppState app, PartModel p,
    {String? hover,
    (KernelSolid, int)? hoverFace,
    String? hoverSketch,
    Set<String>? selSketch,
    Map<String, int>? knownRevs}) {
  final sess = app.extrudeSession;
  final scene = <String, dynamic>{
    'solids': [
      for (final (id, s) in visibleSolids(app, p))
        solidPayload(id, s,
            includeGeometry: knownRevs?[id] != identityHashCode(s.mesh)),
    ],
    'planes': _planePayloads(app, p, hover: hover),
    'axes': _axisPayloads(p, hover: hover),
    'cp': {'visible': p.vis['cp'] == true, 'hot': hover == 'cp'},
    'sketches': _sketchPayloads(app, p),
  };
  final preview = sess?.preview;
  if (preview != null) {
    scene['preview'] = solidPayload('__preview__', preview, material: kMatPreview);
  }
  final hl = _highlightPayload(app, p, hoverFace);
  if (hl != null) scene['highlight'] = hl;
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
  if (hoverSketch != null) out['hoverSketch'] = hoverSketch;
  out['selSketch'] = (selSketch ?? const <String>{}).toList();
  return out;
}

/// A cheap signature over everything that lives in a [buildScenePayload]. When
/// it is unchanged the app skips re-uploading the (large) mesh buffers. Mesh
/// identity flips on extrude/refine; sketch geometry is static in the 3D view
/// (edits happen in the 2D sketcher, which shows a different widget), so a
/// count/eos/visibility fingerprint suffices there.
String sceneSignature(AppState app, PartModel p) {
  final sess = app.extrudeSession;
  final sb = StringBuffer();
  for (final (id, s) in visibleSolids(app, p)) {
    sb..write(id)..write(':')..write(identityHashCode(s.mesh))..write(';');
  }
  sb
    ..write('prev:')
    ..write(sess?.preview == null ? 0 : identityHashCode(sess!.preview!.mesh))
    ..write(';prevrepl:')
    ..write(sess?.previewReplacesBody ?? '')
    ..write(';pick:')
    ..write(app.pickPlane ? 1 : 0)
    ..write(';vis:');
  for (final k in const ['yz', 'xz', 'xy', 'x', 'y', 'z', 'cp']) {
    sb.write(p.vis[k] == true ? '1' : '0');
  }
  sb.write(';sk:');
  for (final cs in p.childSketches) {
    sb
      ..write(cs.model.name)
      ..write('#')
      ..write(cs.model.geometry.length)
      ..write('/')
      ..write(cs.model.eosAfter)
      ..write('/')
      ..write(cs.visible ? 1 : 0)
      ..write(',');
  }
  return sb.toString();
}

