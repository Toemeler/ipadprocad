// M372 — the scene payload, as a flutter_scene graph.
//
// THE PAYLOAD IS THE CONTRACT, and taking it verbatim is the whole point.
//
// `reality_scene.dart` maps the live editing state onto a set of plain maps —
// solids with their buffers, origin planes, axes, sketch polylines, a camera —
// and RealityKit consumes them on iOS. This file consumes the SAME maps. Not a
// parallel description of the scene: the same one, from the same builder, so
// there is exactly one answer to "what is in the viewport" and the two
// renderers cannot drift about it.
//
// The cost is decoding a map on every geometry change. That is bounded and
// small: the app already gates these pushes behind a mesh signature, because
// the RealityKit path could not afford to re-upload megabytes on a hover
// either.
//
// WHAT IT DOES NOT DO. Screen-space decorations — profile regions, hover
// rings, the plane label — are not here. They are Flutter's, drawn by
// `_OverlayPainter` over the render surface, exactly as they are over the
// RealityKit one.
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

import 'ortho_camera.dart';

/// Material tags on the wire. `kMatSteel` / `kMatPreview` in reality_payload.
const int _kMatSteel = 0;
const int _kMatPreview = 1;

/// "No tint", as an ARGB sentinel — a fully transparent black is never a
/// colour anyone asks for. `kNoTint` in reality_payload.
const int _kNoTint = 0;

/// EVERY line in the scene, in logical points — B-Rep outlines, sketch curves,
/// work-plane borders, origin axes. `Stroke.line` in PartScene.swift, and one
/// number rather than a family of them is the point there too: "thin, but
/// always the same" is not a property any single call site can hold.
const double _kStrokeLine = 1.0;

/// One solid, kept between pushes so a payload that omits the geometry can
/// still move or recolour it.
///
/// That is not an optimisation, it is the assembly path: two occurrences of
/// one part are two nodes over one uploaded mesh, and dragging one costs a
/// transform write instead of a multi-megabyte upload.
class _Solid {
  _Solid(this.rev, this.shaded, this.edges);
  int rev;
  Mesh shaded;
  Mesh? edges;

  /// The solid's own node, and its edges as a CHILD of it.
  ///
  /// A child rather than a second primitive on one mesh, and that is a
  /// measurement rather than a preference: a `Mesh.primitives` holding a
  /// triangle geometry and a [LineSegmentsGeometry] together draws the
  /// triangles and silently drops the segments — the two need different vertex
  /// shaders, and the encoder binds per mesh. (Diagnosed by fattening the
  /// edges to 0.4 mm and colouring them red: not one red pixel reached the
  /// frame.)
  ///
  /// A child still shares the parent's transform by construction, which is the
  /// property that mattered: an assembly component that moves must never leave
  /// its own edges behind.
  final Node node = Node();
  final Node edgeNode = Node();
}

/// Builds and keeps the graph for one viewport.
///
/// Stateful on purpose: `setScene` is handed payloads that say "this solid is
/// unchanged" by omitting its buffers, and something has to be holding the
/// mesh they refer to.
class SceneBuilder {
  SceneBuilder(this.scene) {
    scene.add(_world);
  }

  final Scene scene;

  /// EVERYTHING HANGS UNDER ONE NODE, AND THAT NODE IS A MIRROR.
  ///
  /// The app's world is right-handed — X right, Y up, Z toward the viewer —
  /// and its camera is the OpenGL one: `dir` points from the scene toward the
  /// eye, screen right is `s`, screen up is `u`, and the view looks along
  /// `-dir`.
  ///
  /// flutter_scene is the other convention. `_matrix4LookAt` derives
  /// `right = up x forward` and its projection puts `w = +z_view`, so its view
  /// basis is right-handed about a forward direction on +Z: a LEFT-handed
  /// world, X right, Y up, Z away from the viewer. The two differ by a
  /// reflection, and no choice of camera can make up for one — handed the
  /// app's camera unchanged, flutter_scene draws a correct picture of a
  /// mirrored scene, which reads as a modelling bug rather than a camera one.
  ///
  /// One negated Z reconciles them, and putting it on a NODE rather than in
  /// the projection is the point: a mirrored projection would reverse every
  /// triangle's winding against the back-face cull and turn the model inside
  /// out, while a mirrored node is a case flutter_scene already handles — Node
  /// recomputes `windingFlipped` from the determinant of the transform chain
  /// and reverses the winding order for everything below it.
  final Node _world = Node()
    ..localTransform = (Matrix4.identity()..setEntry(2, 2, -1.0));

  /// A world-space vector, in the mirrored frame [_world] draws in.
  static Vector3 _flip(Vector3 v) => Vector3(v.x, v.y, -v.z);

  final Map<String, _Solid> _solids = {};
  final List<Node> _decor = [];

  /// The camera basis of the last `setCamera`, which the edge ribbons and the
  /// coplanar lift both need.
  var _basis = (dir: Vector3(0, 0, 1), right: Vector3(1, 0, 0), up: Vector3(0, 1, 0));
  double _halfH = 50;

  // ---- materials ----------------------------------------------------------
  //
  // Matched to Materials.swift, which is what RealityKit shades with. Steel is
  // a dielectric with a trace of metal in it: fully metallic reads as a mirror
  // and a CAD part is not one, and fully dielectric reads as plastic.
  Material _steel(int tint) {
    final m = PhysicallyBasedMaterial();
    m.baseColorFactor = tint == _kNoTint
        ? Vector4(0.62, 0.64, 0.66, 1.0)
        : _argb(tint);
    m.metallicFactor = 0.15;
    m.roughnessFactor = 0.45;
    return m;
  }

  Material _preview() {
    final m = PhysicallyBasedMaterial();
    // The extrude preview: the app's accent, and translucent, because the
    // whole point is seeing the body it is about to cut into.
    m.baseColorFactor = Vector4(0.29, 0.62, 0.91, 0.55);
    m.metallicFactor = 0.0;
    m.roughnessFactor = 0.5;
    m.alphaMode = AlphaMode.blend;
    return m;
  }

  /// Edges, planes, axes and sketches are all UNLIT.
  ///
  /// A B-Rep edge is not a physical object with a normal; it is a line the
  /// drawing is made of, and lighting one makes it fade on the side of the
  /// part facing away from the light — which is the side you most need it.
  Material _line(Vector4 colour) {
    final m = UnlitMaterial();
    m.baseColorFactor = colour;
    if (colour.w < 1.0) m.alphaMode = AlphaMode.blend;
    // NO CULLING, and without it a ribbon is invisible half the time.
    //
    // LineSegmentsGeometry expands each segment into a camera-facing quad in
    // the vertex shader, and which way that quad ends up wound depends on the
    // segment's direction relative to the camera — so a back-face cull throws
    // away an arbitrary half of the edges of a model, and every one of them as
    // the model turns. flutter_scene's own ribbon component sets
    // `CullMode.none` for exactly this; a material is the only place a mesh
    // can say so.
    m.doubleSided = true;
    return m;
  }

  static Vector4 _argb(int argb) => Vector4(
        ((argb >> 16) & 0xFF) / 255.0,
        ((argb >> 8) & 0xFF) / 255.0,
        (argb & 0xFF) / 255.0,
        ((argb >> 24) & 0xFF) / 255.0,
      );

  // ---- the camera ---------------------------------------------------------

  /// The camera for the current payload, or null before the first `setCamera`.
  OrthographicCamera? camera;

  void setCamera(Map<String, dynamic> p) {
    final az = _d(p['az']), pol = _d(p['pol']), roll = _d(p['roll']);
    _halfH = _d(p['halfH'], 50);
    _basis = cameraBasis(az: az, pol: pol, roll: roll);
    // The payload carries the viewport in logical points, which is what turns
    // a stroke in points into one in millimetres. Guarded: a zero height would
    // make every line in the scene infinitely wide.
    final hPt = _d(p['h'], 0);
    if (hPt > 1) _mmPerPoint = 2 * _halfH / hPt;
    _restroke();

    // The same fit RealityPartView.cameraFit() makes, and for its reason: an
    // orthographic depth buffer is linear, so the range has to bracket the
    // scene tightly or the edge ribbons speckle against the faces they lie on.
    final pad = (_sceneRadius > _halfH ? _sceneRadius : _halfH) + 10;
    final dist = pad * 4;
    final centre = _basis.right * _d(p['ox']) + _basis.up * _d(p['oy']);
    // The camera lives in the mirrored frame with everything else, so the two
    // cancel and what this projects is `Cam3.project` exactly.
    camera = OrthographicCamera(
      eye: _flip(centre + _basis.dir * dist),
      target: _flip(centre),
      upVector: _flip(_basis.up),
      orthographic: OrthographicProjection(
        halfHeight: _halfH,
        near: (dist - pad * 2) < 0.001 ? 0.001 : dist - pad * 2,
        far: dist + pad * 2,
      ),
    );
  }

  double _sceneRadius = 50;

  // ---- the scene ----------------------------------------------------------

  void setScene(Map<String, dynamic> p) {
    final solids = (p['solids'] as List?) ?? const [];
    final seen = <String>{};
    double radius = 1;

    for (final raw in solids) {
      final s = raw as Map;
      final id = s['id'] as String? ?? '';
      if (id.isEmpty) continue;
      seen.add(id);
      radius = _apply(id, s, radius);
    }

    // A preview rides the same list: it is a solid with a reserved id, and
    // giving it its own path would be a second place for the transform and the
    // material to be got wrong.
    final preview = p['preview'];
    if (preview is Map) {
      seen.add(preview['id'] as String? ?? '__preview__');
      radius = _apply(preview['id'] as String? ?? '__preview__', preview, radius);
    }

    // Whatever is no longer in the payload is no longer in the scene. Removing
    // by DIFFERENCE rather than clearing and rebuilding is what keeps an
    // unchanged solid's GPU buffers alive across a push.
    for (final gone in _solids.keys.toList()) {
      if (seen.contains(gone)) continue;
      _world.remove(_solids.remove(gone)!.node);
    }
    _sceneRadius = radius;

    _rebuildDecor(p);
  }

  /// The light push: visibility and highlight only, no geometry.
  ///
  /// The payload is a subset of the scene's own keys, so it is applied through
  /// the same code — a second decoder for the same shapes would be a second
  /// place for "is this plane visible" to be answered differently.
  void setOverlays(Map<String, dynamic> p) {
    if (p.containsKey('planes') || p.containsKey('axes') ||
        p.containsKey('sketches')) {
      _rebuildDecor(p);
    }
    for (final raw in (p['solids'] as List?) ?? const []) {
      final s = raw as Map;
      final id = s['id'] as String? ?? '';
      final solid = _solids[id];
      if (solid == null) continue;
      if (s.containsKey('tint') || s.containsKey('material')) {
        _apply(id, s, _sceneRadius);
      }
      if (s['visible'] is bool) solid.node.visible = s['visible'] as bool;
    }
  }

  double _apply(String id, Map s, double radius) {
    final rev = (s['rev'] as int?) ?? 0;
    final existing = _solids[id];
    final positions = s['positions'];

    if (positions is Float32List) {
      final normals = s['normals'] as Float32List?;
      final indices = s['indices'] as Int32List?;
      final geometry = MeshGeometry.fromArrays(
        positions: positions,
        normals: normals,
        indices: indices?.toList(),
      );
      final material = (s['material'] as int? ?? _kMatSteel) == _kMatPreview
          ? _preview()
          : _steel(s['tint'] as int? ?? _kNoTint);
      final shaded = Mesh(geometry, material);
      final edges = _edgeMesh(s);
      if (existing == null) {
        final made = _Solid(rev, shaded, edges);
        _solids[id] = made;
        _attach(made);
        _world.add(made.node);
      } else {
        existing.rev = rev;
        existing.shaded = shaded;
        existing.edges = edges;
        _attach(existing);
      }
      for (var i = 0; i + 2 < positions.length; i += 3) {
        final r = Vector3(positions[i], positions[i + 1], positions[i + 2]).length;
        if (r > radius) radius = r;
      }
    } else if (existing != null) {
      // Geometry omitted: the material and the placement may still have moved.
      final material = (s['material'] as int? ?? _kMatSteel) == _kMatPreview
          ? _preview()
          : _steel(s['tint'] as int? ?? _kNoTint);
      existing.shaded = Mesh(existing.shaded.primitives.first.geometry, material);
      _attach(existing);
    }

    final node = _solids[id]?.node;
    if (node != null) node.localTransform = _placement(s);
    return radius;
  }

  /// The holder transform. `at` is the placement and `rot` the orientation;
  /// a part sends neither, because its solids are already in world coordinates.
  Matrix4 _placement(Map s) {
    final at = s['at'] as List?;
    final rot = s['rot'] as List?;
    final m = Matrix4.identity();
    if (rot != null && rot.length == 4) {
      // (x, y, z, w) — simd_quatf's component order, which is what the payload
      // is written in.
      m.setFromTranslationRotation(
        Vector3.zero(),
        Quaternion(_d(rot[0]), _d(rot[1]), _d(rot[2]), _d(rot[3])),
      );
    }
    if (at != null && at.length == 3) {
      m.setTranslation(Vector3(_d(at[0]), _d(at[1]), _d(at[2])));
    }
    return m;
  }

  /// The shaded surface and its edges as ONE mesh of two primitives.
  ///
  /// Two primitives rather than two nodes so they share a transform by
  /// construction: an assembly component that moves must never leave its own
  /// edges behind, and that is a class of bug this shape cannot have.
  void _attach(_Solid s) {
    s.node.mesh = s.shaded;
    s.edgeNode.mesh = s.edges;
    if (!s.node.children.contains(s.edgeNode)) s.node.add(s.edgeNode);
    // THE EDGES ARE LIFTED TOWARD THE CAMERA, as RealityKit lifts them
    // (`for e in edgeEntities { e.position = dir * bias }` in placeCamera):
    // a B-Rep edge lies exactly on the two faces it borders, so without a lift
    // it z-fights them and comes and goes as the model turns.
    //
    // Through [_flip], because this node hangs under the mirrored [_world] and
    // the lift has to be toward the camera in the frame it is drawn in — the
    // unmirrored vector pushes the edges INTO the model along z, which loses
    // most of them and keeps the few whose faces happen to face away.
    s.edgeNode.localTransform = Matrix4.translation(_flip(_basis.dir) * _edgeLift);
  }

  /// How far toward the camera a coplanar overlay is pushed, in world units.
  /// `max(halfH * 5e-4, 1e-6)` — RealityPartView.placeCamera's own bias.
  double get _edgeLift =>
      (_halfH * 5e-4).clamp(1e-6, double.infinity).toDouble();

  /// The B-Rep edges of one solid.
  ///
  /// `edgePts` is every edge's polyline points end to end and `edgeStarts` is
  /// the offsets into it, so a span of n points is n-1 segments.
  ///
  /// [LineSegmentsGeometry] rather than a line-primitive draw, and the
  /// difference is width: it instances a camera-facing quad per segment, so an
  /// edge has a real world-space thickness that survives a zoom, which is
  /// exactly what PartScene.swift builds ribbons for. A one-pixel line list
  /// would be cheaper and would look like a wireframe rather than like the
  /// drawn edge of a machined part.
  Mesh? _edgeMesh(Map s) {
    final pts = s['edgePts'];
    final starts = s['edgeStarts'];
    if (pts is! Float32List || starts is! Int32List || starts.length < 2) {
      return null;
    }
    return _segments(_spansToSegments(pts, starts), _edgeWidth,
        Vector4(0.09, 0.10, 0.11, 1.0));
  }

  /// Polyline spans to endpoint pairs: six floats per segment, which is what
  /// [LineSegmentData] takes.
  static Float32List? _spansToSegments(Float32List pts, Int32List starts) {
    var count = 0;
    for (var e = 0; e + 1 < starts.length; e++) {
      final n = starts[e + 1] - starts[e];
      if (n > 1) count += n - 1;
    }
    if (count == 0) return null;
    final out = Float32List(count * 6);
    var w = 0;
    for (var e = 0; e + 1 < starts.length; e++) {
      final a = starts[e], b = starts[e + 1];
      for (var i = a; i + 1 < b; i++) {
        if ((i + 1) * 3 + 2 >= pts.length) break;
        out[w++] = pts[i * 3];
        out[w++] = pts[i * 3 + 1];
        out[w++] = pts[i * 3 + 2];
        out[w++] = pts[(i + 1) * 3];
        out[w++] = pts[(i + 1) * 3 + 1];
        out[w++] = pts[(i + 1) * 3 + 2];
      }
    }
    return out;
  }

  Mesh? _segments(Float32List? endpoints, double width, Vector4 colour) {
    if (endpoints == null || endpoints.isEmpty) return null;
    return Mesh(
      LineSegmentsGeometry(LineSegmentData(positions: endpoints), width: width),
      _line(colour),
    );
  }

  /// The world length of one logical POINT at the current camera.
  ///
  /// This is the whole of PartScene.swift's `OutlineStyle`: a stroke is asked
  /// for in points — the unit the 2D sketcher draws in — and comes back in
  /// millimetres, so its weight on screen is the same at every zoom and on
  /// every screen size.
  ///
  /// The constant that used to be here, `halfH * 1.2e-3`, is the one that file
  /// names as the BUG it replaced: it is a fixed fraction of the view height
  /// and so is only right at one viewport size, and because the ribbons were
  /// rebuilt lazily its on-screen weight swung over a 3:1 range while zooming.
  double _mmPerPoint = 0.05;

  /// Every line in the scene, at [Stroke.line] — one point, the same weight
  /// the 2D sketcher strokes with and the same one the iPad draws.
  double get _edgeWidth => (_mmPerPoint * _kStrokeLine).clamp(1e-5, 10.0);

  /// The [LineSegmentsGeometry] of everything currently in the graph, so a
  /// zoom can restroke them all without rebuilding a single buffer.
  ///
  /// PartScene.swift rebuilds its ribbons through one style for exactly this
  /// reason ("lines cannot disagree with each other and cannot disagree with
  /// the zoom"); here the width is a live property of the geometry, so the
  /// same guarantee costs a walk instead of a re-tube.
  final List<LineSegmentsGeometry> _lines = [];

  void _restroke() {
    final w = _edgeWidth;
    for (final g in _lines) {
      if (g.width != w) g.width = w;
    }
    // The lift is toward the CAMERA, so it moves with it — the same reason
    // RealityKit redoes it in placeCamera rather than in setScene.
    final lift = Matrix4.translation(_flip(_basis.dir) * _edgeLift);
    for (final s in _solids.values) {
      s.edgeNode.localTransform = lift;
    }
  }

  /// Collects the line geometry of everything in the graph. Called whenever
  /// the graph changes, not whenever the camera does.
  void _collectLines() {
    _lines.clear();
    void take(Mesh? m) {
      if (m == null) return;
      for (final prim in m.primitives) {
        final g = prim.geometry;
        if (g is LineSegmentsGeometry) _lines.add(g);
      }
    }
    for (final s in _solids.values) {
      take(s.edges);
    }
    for (final n in _decor) {
      take(n.mesh);
    }
    _restroke();
  }

  // ---- origin planes, axes, centre point, sketches ------------------------

  void _rebuildDecor(Map<String, dynamic> p) {
    for (final n in _decor) {
      _world.remove(n);
    }
    _decor.clear();

    for (final raw in (p['planes'] as List?) ?? const []) {
      final n = _plane(raw as Map);
      if (n != null) _decor.add(n);
    }
    for (final raw in (p['axes'] as List?) ?? const []) {
      final n = _axis(raw as Map);
      if (n != null) _decor.add(n);
    }
    for (final raw in (p['sketches'] as List?) ?? const []) {
      _decor.addAll(_sketch(raw as Map));
    }
    for (final n in _decor) {
      _world.add(n);
    }
    // EVERY path that changes the graph ends here — setScene and the overlay
    // push both — so this is the one place the line list has to be refreshed.
    _collectLines();
  }

  /// One origin plane: a translucent quad in its own frame.
  ///
  /// Lifted a hair toward the camera along its own normal, so a plane that is
  /// exactly coincident with a solid face wins — "the work plane is in front",
  /// which is what Inventor does and what makes a plane pickable at all.
  Node? _plane(Map p) {
    if (p['visible'] != true) return null;
    final frame = p['frame'] as List?;
    final origin = p['origin'] as List?;
    final ext = _d(p['ext'], 25);
    if (frame == null || frame.length < 9 || origin == null) return null;
    final u = Vector3(_d(frame[0]), _d(frame[1]), _d(frame[2]));
    final v = Vector3(_d(frame[3]), _d(frame[4]), _d(frame[5]));
    final n = Vector3(_d(frame[6]), _d(frame[7]), _d(frame[8]));
    final o = Vector3(_d(origin[0]), _d(origin[1]), _d(origin[2]));
    final bias = (_halfH * 5e-4).clamp(1e-6, double.infinity);
    final c = o + n * (n.dot(_basis.dir) > 0 ? bias : -bias);
    final e = ext <= 0 ? 25.0 : ext;
    final corners = <Vector3>[
      c - u * e - v * e,
      c + u * e - v * e,
      c + u * e + v * e,
      c - u * e + v * e,
    ];
    final positions = Float32List(12);
    for (var i = 0; i < 4; i++) {
      positions[i * 3] = corners[i].x;
      positions[i * 3 + 1] = corners[i].y;
      positions[i * 3 + 2] = corners[i].z;
    }
    final hot = p['hot'] == true;
    return Node(
      mesh: Mesh(
        MeshGeometry.fromArrays(
          positions: positions,
          normals: Float32List.fromList([
            n.x, n.y, n.z, n.x, n.y, n.z, n.x, n.y, n.z, n.x, n.y, n.z,
          ]),
          indices: const [0, 1, 2, 0, 2, 3],
        ),
        _line(hot
            ? Vector4(0.29, 0.62, 0.91, 0.32)
            : Vector4(0.55, 0.60, 0.66, 0.16)),
      ),
    );
  }

  /// One origin axis, as a segment from `lo` to `hi` along `dir`.
  Node? _axis(Map a) {
    if (a['visible'] != true) return null;
    final d = a['dir'] as List?;
    if (d == null || d.length < 3) return null;
    final dir = Vector3(_d(d[0]), _d(d[1]), _d(d[2]));
    final lo = dir * _d(a['lo'], -25), hi = dir * _d(a['hi'], 25);
    final mesh = _segments(
      Float32List.fromList([lo.x, lo.y, lo.z, hi.x, hi.y, hi.z]),
      _edgeWidth * 1.4,
      a['hot'] == true
          ? Vector4(0.29, 0.62, 0.91, 1.0)
          : Vector4(0.45, 0.48, 0.52, 1.0),
    );
    if (mesh == null) return null;
    return Node(mesh: mesh);
  }

  /// One sketch's polylines, in the sketch's own frame.
  List<Node> _sketch(Map s) {
    final lines = s['lines'] ?? s['polylines'];
    if (lines is! List) return const [];
    final out = <Node>[];
    for (final raw in lines) {
      if (raw is! Float32List || raw.length < 6) continue;
      // One open polyline: the whole run is a single span.
      final mesh = _segments(
        _spansToSegments(raw, Int32List.fromList([0, raw.length ~/ 3])),
        _edgeWidth * 1.6,
        Vector4(0.24, 0.56, 0.86, 1.0),
      );
      if (mesh != null) out.add(Node(mesh: mesh));
    }
    return out;
  }

  static double _d(Object? v, [double fallback = 0]) =>
      v is num ? v.toDouble() : fallback;
}
