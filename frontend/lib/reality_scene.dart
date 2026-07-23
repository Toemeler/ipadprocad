// iPadProCAD — maps the PartModel onto the RealityKit surface's payloads (M60).
//
// These are PURE functions (no channels, no platform), so they are exercised
// by host tests exactly as the native side will receive them. The heavy mesh
// buffers are the very Float64List/Int32List objects OcctMeshData already
// holds, referenced (never copied) into the payload maps — StandardMessageCodec
// transmits them as raw typed-data byte buffers.
//
// The camera/plane/axis/sketch conventions here MUST match Cam3 and the Swift
// PartRenderer; the two are two ends of one wire.
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'app_state.dart';
import 'ffi/occt_engine.dart' show OcctMeshData;
import 'log.dart';
import 'part_model.dart';

/// Material tags understood by Materials.swift.
const int kMatSteel = 0;
const int kMatPreview = 1;

/// The five orthographic camera doubles + the viewport size (for aspect).
Map<String, dynamic> cameraPayload(PartCamera c, Size size) => {
      'az': c.az,
      'pol': c.pol,
      'halfH': c.halfH,
      'ox': c.ox,
      'oy': c.oy,
      'w': size.width,
      'h': size.height,
    };

/// The committed solids the viewport draws: visible, non-consumed features,
/// minus the one being edited (its live preview is sent separately). Keyed by
/// the feature name, which is unique within a part.
List<(String, KernelSolid)> visibleSolids(AppState app, PartModel p) {
  final sess = app.extrudeSession;
  final out = <(String, KernelSolid)>[];
  for (final f in p.features) {
    if (f.visible &&
        f.solid != null &&
        !f.consumedByJoin &&
        f != sess?.editing) {
      out.add((f.name, f.solid!));
    }
  }
  return out;
}

final Set<int> _conventionLogged = <int>{};

/// ONE-SHOT DIAGNOSTIC per mesh — it exists because the surface convention of
/// these meshes could not be settled by reading the code, and guessing it wrong
/// has now cost three device rounds (invisible face highlight, see-through
/// holes, a solid that reads inside-out).
///
/// It measures the two unknowns directly and writes them to the device log:
///  * `wind`  — share of triangles whose WINDING normal cross(p1-p0, p2-p0)
///              agrees with the supplied per-vertex normal. ~1.0 means winding
///              and normals point the same way, ~0.0 means they oppose.
///  * `out`   — share of sampled vertices whose normal points AWAY from the
///              mesh centroid. ~1.0 means the normals really are outward (as
///              occt_capi.h claims), ~0.0 means they are inward. Reliable for
///              the convex-ish test bodies (cylinder, box).
/// Together these pin down both the winding and the normal orientation, which
/// is everything the renderer needs to be made correct rather than lucky.
void logMeshConvention(String id, OcctMeshData m) {
  if (!_conventionLogged.add(identityHashCode(m))) return;
  final pos = m.positions, nor = m.normals, idx = m.indices;
  final nTri = idx.length ~/ 3;
  if (nTri == 0 || nor.length != pos.length) return;

  var cx = 0.0, cy = 0.0, cz = 0.0;
  final nV = pos.length ~/ 3;
  for (var i = 0; i < nV; i++) {
    cx += pos[i * 3];
    cy += pos[i * 3 + 1];
    cz += pos[i * 3 + 2];
  }
  cx /= nV;
  cy /= nV;
  cz /= nV;

  var agree = 0, outward = 0, sampled = 0;
  final step = nTri > 600 ? nTri ~/ 600 : 1;
  for (var t = 0; t < nTri; t += step) {
    final a = idx[t * 3], b = idx[t * 3 + 1], c = idx[t * 3 + 2];
    final ax = pos[a * 3], ay = pos[a * 3 + 1], az = pos[a * 3 + 2];
    final ux = pos[b * 3] - ax, uy = pos[b * 3 + 1] - ay, uz = pos[b * 3 + 2] - az;
    final vx = pos[c * 3] - ax, vy = pos[c * 3 + 1] - ay, vz = pos[c * 3 + 2] - az;
    // winding normal
    final gx = uy * vz - uz * vy, gy = uz * vx - ux * vz, gz = ux * vy - uy * vx;
    final nx = nor[a * 3], ny = nor[a * 3 + 1], nz = nor[a * 3 + 2];
    if (gx * nx + gy * ny + gz * nz > 0) agree++;
    // does the vertex normal point away from the centroid?
    if (nx * (ax - cx) + ny * (ay - cy) + nz * (az - cz) > 0) outward++;
    sampled++;
  }
  if (sampled == 0) return;
  final w = (agree / sampled).toStringAsFixed(2);
  final o = (outward / sampled).toStringAsFixed(2);

  // WATERTIGHT CHECK + FACE INVENTORY (only worth it on the coarse first
  // tessellation). A missing face is invisible in a render but unmistakable
  // here: in a closed shell EVERY edge is shared by exactly two triangles.
  // OCCT duplicates vertices along face boundaries, so the check is done on
  // quantised POSITIONS rather than on indices, otherwise every face seam
  // would count as a boundary.
  if (nTri <= 400) {
    int canon(int v) {
      final x = (pos[v * 3] * 1e5).round();
      final y = (pos[v * 3 + 1] * 1e5).round();
      final z = (pos[v * 3 + 2] * 1e5).round();
      return Object.hash(x, y, z);
    }

    final edgeUse = <int, int>{};
    final triPerFace = <int, int>{};
    for (var t = 0; t < nTri; t++) {
      final vs = [idx[t * 3], idx[t * 3 + 1], idx[t * 3 + 2]].map(canon).toList();
      for (var k = 0; k < 3; k++) {
        final a = vs[k], b = vs[(k + 1) % 3];
        final key = Object.hash(a < b ? a : b, a < b ? b : a);
        edgeUse[key] = (edgeUse[key] ?? 0) + 1;
      }
      if (m.triFaces.length == nTri) {
        final f = m.triFaces[t];
        triPerFace[f] = (triPerFace[f] ?? 0) + 1;
      }
    }
    final boundary = edgeUse.values.where((c) => c != 2).length;
    final faces = triPerFace.keys.toList()..sort();
    final inv = faces.map((f) {
      final type = m.faceInfos.length > 15 * f
          ? m.faceInfos[15 * f].round()
          : -1;
      return 'f$f:t$type/${triPerFace[f]}';
    }).join(' ');
    Log.i(
        'mesh3d',
        'shell $id: tris=$nTri faces=${faces.length} '
            'nonManifoldOrBoundaryEdges=$boundary '
            '(0 = watertight) [$inv]');
  }
  Log.i('mesh3d',
      'convention $id: tris=$nTri wind_agrees_normal=$w normal_outward=$o');
}

/// Current mesh revision per visible solid. The widget keeps the last set it
/// pushed and hands it back as `knownRevs`, so unchanged solids travel as a
/// two-field stub instead of megabytes of geometry.
Map<String, int> sceneRevs(AppState app, PartModel p) => {
      for (final (id, s) in visibleSolids(app, p)) id: identityHashCode(s.mesh),
    };

/// One solid's mesh payload. Buffers are passed by reference (no copy).
/// With [includeGeometry] false only the identity travels — the renderer then
/// keeps the mesh it already holds for this id.
Map<String, dynamic> solidPayload(String id, KernelSolid s,
    {int material = kMatSteel, bool includeGeometry = true}) {
  final m = s.mesh;
  if (!includeGeometry) {
    return {'id': id, 'rev': identityHashCode(m), 'material': material};
  }
  return {
    'id': id,
    'rev': identityHashCode(m),
    'positions': m.positions, // Float64List, world xyz per vertex
    'normals': m.normals, // Float64List, unit outward
    'indices': m.indices, // Int32List, CCW from outside
    'edgePts': m.edgePoints, // Float64List, B-Rep edge polyline points
    'edgeStarts': m.edgeStarts, // Int32List, nEdges+1 offsets
    'triFaces': m.triFaces, // Int32List (empty on legacy meshes)
    'material': material,
  };
}

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
    final polylines = <Float64List>[];
    for (final g in cs.model.geometry) {
      if (cs.model.hiddenLayers.contains(g.layer)) continue;
      final li = cs.model.layers.indexOf(g.layer);
      if (li >= 0 && li >= cs.model.eosAfter) continue;
      final pts = sketchCurve(g);
      if (pts.length < 2) continue;
      final buf = Float64List(pts.length * 3);
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
        // Normal of the sketch plane: lets the renderer lift a sketch drawn ON
        // a solid face clear of that face (they are exactly coplanar).
        'n': [frame.n.x, frame.n.y, frame.n.z],
      });
    }
  }
  return out;
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
Map<String, dynamic> buildScenePayload(AppState app, PartModel p,
    {String? hover,
    (KernelSolid, int)? hoverFace,
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
  return scene;
}

/// Light per-move push: hover tints + visibility + face highlight, no meshes.
Map<String, dynamic> buildOverlaysPayload(AppState app, PartModel p,
    {String? hover, (KernelSolid, int)? hoverFace}) {
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
