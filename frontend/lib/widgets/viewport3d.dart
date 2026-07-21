// iPadProCAD — 3D part viewport (M56), a 1:1 Flutter port of the HTML
// dummy's Part3D module: orthographic turntable camera about the origin,
// the three 20x20mm orange work planes + axes + centre point with green
// hover highlights, a ViewCube (face/edge/corner snap + Home + face-view
// nav arrows), the coordinate triad, zoom-to-cursor, plane-pick mode for
// "Start 2D Sketch", profile-region picking for Extrude, and the shaded
// solids of the part's features (depth-sorted triangles + B-Rep edges from
// the OCCT tessellation — no GPU dependency, plain CustomPainter).
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../app_state.dart';
import '../part_model.dart';
import '../part_render.dart';
import '../svg_icons.dart' show homeTabIcon;
import '../theme.dart';

const double _ext = 10; // origin half-extent (20mm planes/axes), like the mock
const _orange = Color(0xFFEA9E5C);
const _orangeEdge = Color(0xE6F0A868);
const _green = Color(0xFF39D65B);
const _greenBright = Color(0xFF8DFFA0);
// Cam3 (orthographic turntable camera) and paintPartSolids live in
// ../part_render.dart now — shared verbatim with off-screen thumbnail
// rendering (AppState._writePartPreview). kSolidBase/kSolidEdge moved with
// them.

class Viewport3D extends StatefulWidget {
  final AppState app;
  const Viewport3D({super.key, required this.app});
  @override
  State<Viewport3D> createState() => _Viewport3DState();
}

class _Viewport3DState extends State<Viewport3D> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent e) {
    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
      if (widget.app.pickPlane || widget.app.extrudeSession != null) {
        widget.app.escape3D();
        return true;
      }
    }
    return false;
  }

  String? _hover; // 'yz'|'xz'|'xy'|'x'|'y'|'z'|'cp'
  int? _hoverRegion; // outer-loop id of the hovered profile region
  // MMB drag (desktop): pan with shift, orbit without
  bool _mmb = false, _mmbPan = false;
  Offset _mmbLast = Offset.zero;
  double _scaleStartH = 27;

  PartModel? get part => widget.app.currentPart;

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final p = part;
    if (p == null) return const ColoredBox(color: T.viewport);
    return LayoutBuilder(builder: (context, bc) {
      final size = Size(bc.maxWidth, bc.maxHeight);
      final cam = Cam3(p.camera, size);
      return Stack(children: [
        Positioned.fill(
          child: Listener(
            onPointerDown: (e) {
              if (e.kind == PointerDeviceKind.mouse &&
                  e.buttons == kMiddleMouseButton) {
                _mmb = true;
                _mmbPan = HardwareKeyboard.instance.isShiftPressed;
                _mmbLast = e.localPosition;
              }
            },
            onPointerMove: (e) {
              if (_mmb) {
                final d = e.localPosition - _mmbLast;
                _mmbLast = e.localPosition;
                setState(() {
                  if (_mmbPan) {
                    final wpp = (2 * p.camera.halfH) / size.height;
                    p.camera.ox -= d.dx * wpp;
                    p.camera.oy += d.dy * wpp;
                  } else {
                    _orbit(p, d);
                  }
                });
              }
            },
            onPointerUp: (_) => _mmb = false,
            onPointerCancel: (_) => _mmb = false,
            onPointerSignal: (e) {
              if (e is PointerScrollEvent) {
                setState(() => _zoomAt(p, cam, e.localPosition,
                    e.scrollDelta.dy > 0 ? 1.1 : 0.9));
              }
            },
            child: MouseRegion(
              cursor: _hover != null || _hoverRegion != null
                  ? SystemMouseCursors.click
                  : MouseCursor.defer,
              onHover: (e) => _updateHover(cam, e.localPosition),
              onExit: (_) => setState(() {
                _hover = null;
                _hoverRegion = null;
              }),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) => _tap(cam, d.localPosition),
                onScaleStart: (d) {
                  _scaleStartH = p.camera.halfH;
                  _mmbLast = d.localFocalPoint;
                },
                onScaleUpdate: (d) => setState(() {
                  if (d.pointerCount >= 2) {
                    if (d.scale > 0) {
                      final f = (_scaleStartH / d.scale) / p.camera.halfH;
                      _zoomAt(p, Cam3(p.camera, size), d.localFocalPoint, f);
                    }
                    final mv = d.localFocalPoint - _mmbLast;
                    final wpp = (2 * p.camera.halfH) / size.height;
                    p.camera.ox -= mv.dx * wpp;
                    p.camera.oy += mv.dy * wpp;
                  } else if (!_mmb) {
                    _orbit(p, d.localFocalPoint - _mmbLast);
                  }
                  _mmbLast = d.localFocalPoint;
                }),
                child: CustomPaint(
                  painter: _ScenePainter(app, p, _hover, _hoverRegion),
                  size: Size.infinite,
                ),
              ),
            ),
          ),
        ),
        // ViewCube + Home (top-right)
        Positioned(
            top: 8,
            right: 10,
            child: _ViewCube(
                camera: p.camera, onChanged: () => setState(() {}))),
        // coordinate triad (bottom-left)
        Positioned(
            left: 0,
            bottom: 0,
            child: IgnorePointer(
                child: CustomPaint(
                    painter: _TriadPainter(p.camera),
                    size: const Size(118, 118)))),
        if (app.message != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 44,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xE6402F1F),
                  border: Border.all(color: const Color(0xFF8A6A3A)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(app.message!,
                    style: ts(12, const Color(0xFFF2D6A2))),
              ),
            ),
          ),
      ]);
    });
  }

  void _orbit(PartModel p, Offset d) {
    p.camera.az -= d.dx * 0.01;
    p.camera.pol =
        (p.camera.pol - d.dy * 0.01).clamp(0.02, math.pi - 0.02);
  }

  void _zoomAt(PartModel p, Cam3 cam, Offset px, double factor) {
    final a = cam.aspect;
    final nx = (px.dx / cam.size.width) * 2 - 1;
    final ny = -((px.dy / cam.size.height) * 2 - 1);
    final old = p.camera.halfH;
    p.camera.halfH = (old * factor).clamp(3.0, 200.0);
    p.camera.ox += nx * a * (old - p.camera.halfH);
    p.camera.oy += ny * (old - p.camera.halfH);
  }

  void _updateHover(Cam3 cam, Offset px) {
    final app = widget.app;
    final p = part!;
    String? hit;
    int? region;
    // profile-region hover while the extrude dialog is picking profiles
    final sess = app.extrudeSession;
    if (sess != null && sess.sketchName != null) {
      final cs = p.sketchByName(sess.sketchName!);
      if (cs != null) {
        final frame = planeFrame(cs.plane);
        final w = cam.rayOnPlane(px, frame.n);
        if (w != null) {
          final sp = Offset(w.dot(frame.u), w.dot(frame.v));
          final r = regionAt(app.sessionRegions(cs), sp);
          region = r?.outer.id;
        }
      }
    }
    if (region == null) {
      hit = _hitOrigin(cam, px, p, planesOnly: app.pickPlane);
    }
    if (hit != _hover || region != _hoverRegion) {
      setState(() {
        _hover = hit;
        _hoverRegion = region;
      });
    } else {
      setState(() {}); // cursor moved (plane-pick marker etc.)
    }
  }

  /// Points/edges win over planes, exactly like the mock's raycast order.
  String? _hitOrigin(Cam3 cam, Offset px, PartModel p,
      {bool planesOnly = false}) {
    const pickPx = 8.0;
    if (!planesOnly) {
      if (p.vis['cp'] == true &&
          (cam.project(Vec3.zero) - px).distance < pickPx) {
        return 'cp';
      }
      for (final e in [
        ('x', const Vec3(1, 0, 0)),
        ('y', const Vec3(0, 1, 0)),
        ('z', const Vec3(0, 0, 1))
      ]) {
        if (p.vis[e.$1] != true) continue;
        final a = cam.project(e.$2 * -_ext), b = cam.project(e.$2 * _ext);
        if (_distToSeg(px, a, b) < pickPx) return e.$1;
      }
    }
    // planes, nearest first
    String? best;
    var bestD = double.infinity;
    for (final key in kPlaneKeys) {
      if (!(p.vis[key] == true || (planesOnly && widget.app.pickPlane))) {
        continue;
      }
      final f = planeFrame(key);
      final w = cam.rayOnPlane(px, f.n);
      if (w == null) continue;
      final uu = w.dot(f.u), vv = w.dot(f.v);
      if (uu.abs() <= _ext && vv.abs() <= _ext) {
        final d = cam.depth(w);
        if (d < bestD) {
          bestD = d;
          best = key;
        }
      }
    }
    return best;
  }

  void _tap(Cam3 cam, Offset px) {
    final app = widget.app;
    final p = part!;
    // 1. plane pick (Start 2D Sketch)
    if (app.pickPlane) {
      final key = _hitOrigin(cam, px, p, planesOnly: true);
      if (key != null && kPlaneKeys.contains(key)) {
        app.planePicked(key);
      }
      return;
    }
    // 2. profile pick for the extrude dialog
    final sess = app.extrudeSession;
    if (sess != null) {
      // the pick may LOCK the session to a sketch: try the session sketch
      // first, then every child sketch (nearest plane wins)
      final order = <ChildSketch>[
        if (sess.sketchName != null && p.sketchByName(sess.sketchName!) != null)
          p.sketchByName(sess.sketchName!)!,
        ...p.childSketches
            .where((c) => c.model.name != sess.sketchName),
      ];
      for (final cs in order) {
        final frame = planeFrame(cs.plane);
        final w = cam.rayOnPlane(px, frame.n);
        if (w == null) continue;
        final sp = Offset(w.dot(frame.u), w.dot(frame.v));
        final r = regionAt(app.sessionRegions(cs), sp);
        if (r != null) {
          app.toggleSessionProfile(cs.model.name, r);
          return;
        }
        if (sess.sketchName == cs.model.name) break; // locked, no fallback
      }
      return;
    }
  }

  static double _distToSeg(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) /
            (ab.distance * ab.distance + 1e-12))
        .clamp(0.0, 1.0);
    return (a + ab * t - p).distance;
  }
}

// ---------------------------------------------------------------------------
// scene painter
// ---------------------------------------------------------------------------
class _ScenePainter extends CustomPainter {
  final AppState app;
  final PartModel part;
  final String? hover;
  final int? hoverRegion;
  _ScenePainter(this.app, this.part, this.hover, this.hoverRegion);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = T.viewport);
    final cam = Cam3(part.camera, size);

    // ---- origin planes (fills first: everything else draws over them) ----
    for (final key in kPlaneKeys) {
      final visible = part.vis[key] == true || app.pickPlane;
      if (!visible) continue;
      final f = planeFrame(key);
      final corners = [
        f.toWorld(const Offset(-_ext, -_ext)),
        f.toWorld(const Offset(_ext, -_ext)),
        f.toWorld(const Offset(_ext, _ext)),
        f.toWorld(const Offset(-_ext, _ext)),
      ];
      final path = Path()
        ..addPolygon([for (final c in corners) cam.project(c)], true);
      final hot = hover == key;
      canvas.drawPath(
          path,
          Paint()
            ..color = (hot ? _green : _orange)
                .withOpacity(hot ? 0.45 : 0.30));
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = hot ? _greenBright : _orangeEdge);
      if (hot) {
        // corner rings + centre dot + name label lying on the plane
        for (final c in corners) {
          canvas.drawCircle(
              cam.project(c),
              6,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2
                ..color = _greenBright);
        }
        canvas.drawCircle(cam.project(Vec3.zero), 4,
            Paint()..color = const Color(0xFFFFE07A));
        final p0 = cam.project(f.toWorld(Offset(-_ext + 0.6, -_ext + 1.4)));
        final p1 = cam.project(f.toWorld(Offset(-_ext + 4.6, -_ext + 1.4)));
        final ang = math.atan2(p1.dy - p0.dy, p1.dx - p0.dx);
        canvas.save();
        canvas.translate(p0.dx, p0.dy);
        canvas.rotate(ang);
        final tp = TextPainter(
            text: TextSpan(
                text: planeLabel(key),
                style: ts(12, _greenBright, w: FontWeight.w700)),
            textDirection: TextDirection.ltr)
          ..layout();
        tp.paint(canvas, Offset(0, -tp.height));
        canvas.restore();
      }
    }

    // ---- axes + centre point ----
    for (final e in [
      ('x', const Vec3(1, 0, 0)),
      ('y', const Vec3(0, 1, 0)),
      ('z', const Vec3(0, 0, 1))
    ]) {
      if (part.vis[e.$1] != true) continue;
      final hot = hover == e.$1;
      final a = cam.project(e.$2 * -_ext), b = cam.project(e.$2 * _ext);
      canvas.drawLine(
          a,
          b,
          Paint()
            ..strokeWidth = 1
            ..color = hot ? _green : _orange);
      if (hot) {
        for (final p in [a, b]) {
          canvas.drawCircle(
              p,
              6,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2
                ..color = _greenBright);
        }
      }
    }
    if (part.vis['cp'] == true) {
      final c = cam.project(Vec3.zero);
      final hot = hover == 'cp';
      canvas.drawCircle(c, hot ? 5 : 3.5,
          Paint()..color = hot ? _green : _orange);
      if (hot) {
        canvas.drawCircle(
            c,
            9,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = _greenBright);
      }
    }

    // ---- unconsumed child sketches as curves on their planes ----
    final consumed = <String>{
      for (final f in part.features)
        if (f.visible && f.solid != null) f.sketchName
    };
    final sess = app.extrudeSession;
    for (final cs in part.childSketches) {
      final showForSession = sess?.sketchName == cs.model.name ||
          (sess != null && sess.sketchName == null);
      if (consumed.contains(cs.model.name) && !showForSession) continue;
      _paintSketch(canvas, cam, cs);
      if (sess != null && showForSession) {
        _paintRegions(canvas, cam, cs, sess);
      }
    }

    // ---- solids: depth-sorted triangles + B-Rep edges (painter algo) ----
    // The feature being edited is hidden while its live preview stands in;
    // that preview is drawn translucent on top. Same picture the gallery
    // thumbnail renders off-screen (minus the session preview) via the shared
    // paintPartSolids in part_render.dart.
    final solids = [
      for (final f in part.features)
        if (f.visible && f.solid != null && f != sess?.editing) f.solid!
    ];
    paintPartSolids(canvas, cam, solids, previewSolid: sess?.preview);
  }

  void _paintSketch(Canvas canvas, Cam3 cam, ChildSketch cs) {
    final frame = planeFrame(cs.plane);
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFFC4C9CE);
    for (final g in cs.model.geometry) {
      if (cs.model.hiddenLayers.contains(g.layer)) continue;
      final li = cs.model.layers.indexOf(g.layer);
      if (li >= 0 && li >= cs.model.eosAfter) continue;
      final pts = sketchCurve(g);
      if (pts.length < 2) continue;
      final path = Path();
      for (var i = 0; i < pts.length; i++) {
        final s = cam.project(frame.toWorld(pts[i]));
        i == 0 ? path.moveTo(s.dx, s.dy) : path.lineTo(s.dx, s.dy);
      }
      canvas.drawPath(path, pen);
    }
  }

  void _paintRegions(
      Canvas canvas, Cam3 cam, ChildSketch cs, ExtrudeSession sess) {
    final frame = planeFrame(cs.plane);
    for (final r in app.sessionRegions(cs)) {
      final selected = sess.sketchName == cs.model.name &&
          sess.hasProfileAt(interiorPointOf(r.outer));
      final hovered = hoverRegion == r.outer.id;
      if (!selected && !hovered) continue;
      final path = Path()..fillType = PathFillType.evenOdd;
      void loopPath(List<Offset> pts) {
        for (var i = 0; i < pts.length; i++) {
          final s = cam.project(frame.toWorld(pts[i]));
          i == 0 ? path.moveTo(s.dx, s.dy) : path.lineTo(s.dx, s.dy);
        }
        path.close();
      }

      loopPath(r.outer.pts);
      for (final h in r.holes) {
        loopPath(h.pts);
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = T.blue.withOpacity(selected ? 0.38 : 0.16));
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = selected ? 1.6 : 1
            ..color = selected ? T.hover : T.blue.withOpacity(0.7));
    }
  }

  @override
  bool shouldRepaint(covariant _ScenePainter old) => true;
}

// ---------------------------------------------------------------------------
// ViewCube (84x84 with a Home icon above-left) + face-view nav arrows
// ---------------------------------------------------------------------------
const _cubeFaces = <(String, Vec3)>[
  ('RIGHT', Vec3(1, 0, 0)),
  ('LEFT', Vec3(-1, 0, 0)),
  ('TOP', Vec3(0, 1, 0)),
  ('BOTTOM', Vec3(0, -1, 0)),
  ('FRONT', Vec3(0, 0, 1)),
  ('BACK', Vec3(0, 0, -1)),
];

(Vec3, Vec3) faceBasis(Vec3 n) {
  final up = n.y.abs() > 0.9 ? const Vec3(0, 0, 1) : const Vec3(0, 1, 0);
  final u = up.cross(n).normalized();
  final v = n.cross(u).normalized();
  return (u, v);
}

/// Snap direction for a pointer on the cube: the face normal plus the
/// edge/corner components when the hit sits in the outer 22% band.
(Vec3, Set<String>)? cubePick(PartCamera c, Offset px, double sizePx) {
  final cam = Cam3(c, Size(sizePx, sizePx));
  // ray/unit-cube (slab method), camera-plane origin scaled to half 0.86
  final o0 = cam.unprojectOnCamPlane(px);
  final o = o0 * (0.86 / cam.halfH); // cube canvas uses its own half-height
  final rd = cam.dir * -1;
  var tmin = -1e9, tmax = 1e9;
  Vec3 nEnter = Vec3.zero;
  for (final ax in [
    (const Vec3(1, 0, 0), o.x, rd.x),
    (const Vec3(0, 1, 0), o.y, rd.y),
    (const Vec3(0, 0, 1), o.z, rd.z)
  ]) {
    final (n, oc, dc) = ax;
    if (dc.abs() < 1e-9) {
      if (oc.abs() > 0.5) return null;
      continue;
    }
    var t1 = (-0.5 - oc) / dc, t2 = (0.5 - oc) / dc;
    var nn = n * (dc > 0 ? -1.0 : 1.0);
    if (t1 > t2) {
      final t = t1;
      t1 = t2;
      t2 = t;
      nn = nn * -1;
    }
    if (t1 > tmin) {
      tmin = t1;
      nEnter = nn;
    }
    if (t2 < tmax) tmax = t2;
    if (tmin > tmax) return null;
  }
  final hit = o + rd * tmin;
  final (u, v) = faceBasis(nEnter);
  final du = hit.dot(u), dv = hit.dot(v);
  final cu = du < -0.28 ? -1.0 : (du > 0.28 ? 1.0 : 0.0);
  final cv = dv < -0.28 ? -1.0 : (dv > 0.28 ? 1.0 : 0.0);
  final lit = <String>{_nkey(nEnter)};
  if (cu != 0) lit.add(_nkey(u * cu));
  if (cv != 0) lit.add(_nkey(v * cv));
  final dir = (nEnter + u * cu + v * cv).normalized();
  return (dir, lit);
}

String _nkey(Vec3 v) =>
    '${v.x.round()},${v.y.round()},${v.z.round()}';

class _ViewCube extends StatefulWidget {
  final PartCamera camera;
  final VoidCallback onChanged;
  const _ViewCube({required this.camera, required this.onChanged});
  @override
  State<_ViewCube> createState() => _ViewCubeState();
}

class _ViewCubeState extends State<_ViewCube> {
  Set<String> _lit = const {};

  bool get _faceView {
    final d = widget.camera.dir;
    return [d.x.abs(), d.y.abs(), d.z.abs()]
            .reduce((a, b) => a > b ? a : b) >
        0.999;
  }

  void _snapTo(Vec3 d) {
    final c = widget.camera;
    c.pol = math.acos(d.y.clamp(-1.0, 1.0));
    if (d.y.abs() < 0.999) c.az = math.atan2(d.x, d.z);
    if (c.pol < 0.001) c.pol = 0.001;
    if (c.pol > math.pi - 0.001) c.pol = math.pi - 0.001;
    c.ox = 0;
    c.oy = 0;
    c.halfH = 27;
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.camera;
    return SizedBox(
      width: 120,
      height: 120,
      child: Stack(children: [
        Positioned(
          top: 0,
          left: 14,
          child: GestureDetector(
            onTap: () {
              c.home();
              widget.onChanged();
            },
            child: Tooltip(
              message: 'Home view',
              child: SizedBox(
                  width: 22,
                  height: 22,
                  child: SvgPicture.string(homeTabIcon)),
            ),
          ),
        ),
        Positioned(
          top: 18,
          left: 18,
          child: MouseRegion(
            onHover: (e) {
              final r = cubePick(c, e.localPosition, 84);
              setState(() => _lit = r?.$2 ?? const {});
            },
            onExit: (_) => setState(() => _lit = const {}),
            child: GestureDetector(
              onTapUp: (d) {
                final r = cubePick(c, d.localPosition, 84);
                if (r != null) _snapTo(r.$1);
              },
              child: CustomPaint(
                  painter: _CubePainter(c, _lit),
                  size: const Size(84, 84)),
            ),
          ),
        ),
        // face-view navigation arrows (rotate 90° to the neighbouring face)
        if (_faceView) ..._navArrows(c),
      ]),
    );
  }

  List<Widget> _navArrows(PartCamera c) {
    Widget arrow(String key, Alignment a, double turns) => Align(
          alignment: a,
          child: GestureDetector(
            onTap: () {
              switch (key) {
                case 'up':
                  c.pol = (c.pol - math.pi / 2).clamp(0.001, math.pi - 0.001);
                  break;
                case 'down':
                  c.pol = (c.pol + math.pi / 2).clamp(0.001, math.pi - 0.001);
                  break;
                case 'left':
                  c.az -= math.pi / 2;
                  break;
                default:
                  c.az += math.pi / 2;
              }
              c.ox = 0;
              c.oy = 0;
              c.halfH = 27;
              widget.onChanged();
            },
            child: RotatedBox(
              quarterTurns: (turns * 4).round(),
              child: const Icon(Icons.arrow_drop_up,
                  size: 22, color: Color(0xFFC5CACE)),
            ),
          ),
        );
    return [
      arrow('up', Alignment.topCenter, 0),
      arrow('down', Alignment.bottomCenter, 0.5),
      arrow('left', Alignment.centerLeft, 0.75),
      arrow('right', Alignment.centerRight, 0.25),
    ];
  }
}

class _CubePainter extends CustomPainter {
  final PartCamera camera;
  final Set<String> lit;
  _CubePainter(this.camera, this.lit);

  @override
  void paint(Canvas canvas, Size size) {
    final cam = Cam3(
        PartCamera(az: camera.az, pol: camera.pol, halfH: 0.86),
        size);
    const tint = {
      'RIGHT': Color(0xFFDFE3E7),
      'LEFT': Color(0xFFDFE3E7),
      'TOP': Color(0xFFFFFFFF),
      'BOTTOM': Color(0xFFC7CCD1),
      'FRONT': Color(0xFFEEF1F3),
      'BACK': Color(0xFFEEF1F3),
    };
    final faces = <(double, String, Vec3, List<Offset>)>[];
    for (final (label, n) in _cubeFaces) {
      if (n.dot(cam.dir) <= 0.02) continue; // back faces of the cube
      final (u, v) = faceBasis(n);
      final centre = n * 0.5;
      final quad = [
        cam.project(centre + u * -0.5 + v * -0.5),
        cam.project(centre + u * 0.5 + v * -0.5),
        cam.project(centre + u * 0.5 + v * 0.5),
        cam.project(centre + u * -0.5 + v * 0.5),
      ];
      faces.add((cam.depth(centre), label, n, quad));
    }
    faces.sort((a, b) => b.$1.compareTo(a.$1));
    for (final (_, label, n, quad) in faces) {
      final path = Path()..addPolygon(quad, true);
      canvas.drawPath(path, Paint()..color = tint[label]!);
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = const Color(0xFFAAB1B8));
      if (lit.contains(_nkey(n))) {
        canvas.drawPath(
            path, Paint()..color = const Color(0x8C7EC0F0));
      }
      // label at the face centre, following the face's screen orientation
      final c0 = (quad[0] + quad[2]) / 2;
      final dirX = (quad[1] - quad[0]);
      final tp = TextPainter(
          text: TextSpan(
              text: label,
              style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF565B61))),
          textDirection: TextDirection.ltr)
        ..layout();
      canvas.save();
      canvas.translate(c0.dx, c0.dy);
      canvas.rotate(math.atan2(dirX.dy, dirX.dx));
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _CubePainter old) => true;
}

class _TriadPainter extends CustomPainter {
  final PartCamera camera;
  _TriadPainter(this.camera);

  @override
  void paint(Canvas canvas, Size size) {
    final cam = Cam3(
        PartCamera(az: camera.az, pol: camera.pol, halfH: 1.5), size);
    void arrow(Vec3 d, Color col, String label) {
      final a = cam.project(Vec3.zero), b = cam.project(d);
      final p = Paint()
        ..color = col
        ..strokeWidth = 2;
      canvas.drawLine(a, b, p);
      final dir = (b - a);
      if (dir.distance > 1e-6) {
        final u = dir / dir.distance;
        final n = Offset(-u.dy, u.dx);
        canvas.drawPath(
            Path()
              ..addPolygon(
                  [b, b - u * 9 + n * 4.5, b - u * 9 - n * 4.5], true),
            Paint()..color = col);
      }
      final lp = cam.project(d * 1.28);
      final tp = TextPainter(
          text: TextSpan(
              text: label,
              style:
                  TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: col)),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, lp - Offset(tp.width / 2, tp.height / 2));
    }

    arrow(const Vec3(1, 0, 0), const Color(0xFFE0554F), 'X');
    arrow(const Vec3(0, 1, 0), const Color(0xFF54B24C), 'Y');
    arrow(const Vec3(0, 0, 1), const Color(0xFF3D7BD6), 'Z');
  }

  @override
  bool shouldRepaint(covariant _TriadPainter old) => true;
}
