/// ISSUE #89 — a picture the model can ACT on.
///
/// "das ergebniss ist komplett falsch und kapput". The model had a picture of
/// the part on nine of fifteen requests and still spent 43 000 characters of
/// reasoning in one round working out which face was which from centroids and
/// normals ("the profile y=339.7 > 310 — inconsistent … a=5.0 and exprA says
/// 5mm. Confusing … Enough. Let me just look"). The picture could not help:
/// every op names a face as `F12`, and nothing in the picture said which face
/// that was. It could see a panel with lips; it could not point at one.
///
/// So every view is now LABELLED, the way a person marks up a screenshot for
/// a colleague: each face big enough to read carries the same F-number
/// `faces_where` hands out and the world direction it faces, and a small
/// triad says where X, Y (up) and Z are. Picking "the bottom" or "that
/// pocket" becomes reading a label instead of deriving one.
///
/// WHICH FACE IS WHERE is decided by the geometry, never by the picture: the
/// body's own triangles are rasterised with a depth test through the SAME
/// camera the picture was taken with, so a label sits on a pixel where that
/// face is the nearest thing to the eye. A face hidden behind another gets no
/// label, and each label goes at the point of its face furthest from any
/// other face, so it reads as belonging to that face and not its neighbour.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../ffi/occt_engine.dart' show OcctMeshData;
import '../part_model.dart' show Vec3;
import '../part_render.dart' show Cam3, kFacePlane, kFaceCylinder;
import '../theme.dart'
    show kAiLabelInk, kAiLabelFill, kAiAxisX, kAiAxisY, kAiAxisZ;
import '../desktop_radius.dart';

/// One label: face [face] of the mesh, drawn at [at] in the view's logical
/// pixels, visible over [cells] cells of the id grid.
class FaceMark {
  const FaceMark(this.face, this.text, this.at, this.cells);
  final int face;
  final String text;
  final Offset at;
  final int cells;
}

/// A face's label: its id plus what the model most needs to tell faces apart
/// — which world direction a flat face looks, or a round face's diameter.
String faceMarkText(OcctMeshData m, int face) {
  final o = face * 15;
  if (o + 10 >= m.faceInfos.length) return 'F$face';
  final type = m.faceInfos[o].round();
  if (type == kFacePlane) {
    final d = Vec3(m.faceInfos[o + 4], m.faceInfos[o + 5], m.faceInfos[o + 6]);
    final dir = axisName(d);
    return dir == null ? 'F$face' : 'F$face $dir';
  }
  if (type == kFaceCylinder) {
    final r = m.faceInfos[o + 10];
    if (r > 0) {
      final dia = r * 2;
      return 'F$face Ø${dia >= 10 ? dia.toStringAsFixed(0) : dia.toStringAsFixed(1)}';
    }
  }
  return 'F$face';
}

/// "+X", "-Y" … for a direction within about 2.5° of an axis, else null. A
/// label that names a direction 12° off an axis would be a small lie in the
/// one place the model is trying to establish which way a face looks.
String? axisName(Vec3 d) {
  final len = d.length;
  if (!(len > 0)) return null;
  const names = ['X', 'Y', 'Z'];
  final c = [d.x / len, d.y / len, d.z / len];
  for (var i = 0; i < 3; i++) {
    if (c[i].abs() > 0.999) return '${c[i] > 0 ? "+" : "-"}${names[i]}';
  }
  return null;
}

/// The faces of [m] worth labelling as seen through [cam], largest visible
/// first, at most [max]. [grid] is the id buffer's width in cells; the view
/// is small and the labels are coarse, so a few thousand cells are plenty.
///
/// [occluders] are the part's other bodies: drawn into the depth test so a
/// face behind one of them is not labelled, never labelled themselves.
List<FaceMark> faceMarks(OcctMeshData m, Cam3 cam,
    {int grid = 128, int max = 12, List<OcctMeshData> occluders = const []}) {
  final idx = m.indices, tri = m.triFaces, pos = m.positions;
  if (idx.length < 3 || tri.length * 3 != idx.length) return const [];
  final size = cam.size;
  if (!(size.width > 0 && size.height > 0)) return const [];
  final w = grid;
  final h = (grid * size.height / size.width).round().clamp(8, grid * 4);
  final sx = w / size.width, sy = h / size.height;

  final depth = Float64List(w * h)..fillRange(0, w * h, double.infinity);
  final owner = Int32List(w * h)..fillRange(0, w * h, -1);
  for (final o in occluders) {
    _raster(o.positions, o.indices, null, cam, sx, sy, w, h, depth, owner);
  }
  _raster(pos, idx, tri, cam, sx, sy, w, h, depth, owner);
  return _place(m, owner, w, h, sx, sy, size, max);
}

/// Depth-tested rasterisation of one mesh into [owner]: the face id of each
/// triangle from [tri], or -2 (an occluder, labelled never) when it is null.
void _raster(Float64List pos, Int32List idx, Int32List? tri, Cam3 cam,
    double sx, double sy, int w, int h, Float64List depth, Int32List owner) {
  final nv = pos.length ~/ 3;
  final px = Float64List(nv), py = Float64List(nv), pd = Float64List(nv);
  for (var i = 0; i < nv; i++) {
    final v = Vec3(pos[i * 3], pos[i * 3 + 1], pos[i * 3 + 2]);
    final s = cam.project(v);
    px[i] = s.dx * sx;
    py[i] = s.dy * sy;
    pd[i] = cam.depth(v);
  }
  for (var t = 0; t + 2 < idx.length; t += 3) {
    final f = tri == null ? -2 : tri[t ~/ 3];
    final a = idx[t], b = idx[t + 1], c = idx[t + 2];
    if (f < 0 && f != -2 || a >= nv || b >= nv || c >= nv) continue;
    final ax = px[a],
        ay = py[a],
        bx = px[b],
        by = py[b],
        cx = px[c],
        cy = py[c];
    final area = (bx - ax) * (cy - ay) - (cx - ax) * (by - ay);
    if (!(area.abs() > 1e-12)) continue; // edge-on or degenerate
    final c0 = math.max(0, math.min(ax, math.min(bx, cx)).floor());
    final c1 = math.min(w - 1, math.max(ax, math.max(bx, cx)).ceil());
    final r0 = math.max(0, math.min(ay, math.min(by, cy)).floor());
    final r1 = math.min(h - 1, math.max(ay, math.max(by, cy)).ceil());
    for (var r = r0; r <= r1; r++) {
      final qy = r + 0.5;
      for (var col = c0; col <= c1; col++) {
        final qx = col + 0.5;
        final w1 = ((qx - ax) * (cy - ay) - (cx - ax) * (qy - ay)) / area;
        final w2 = ((bx - ax) * (qy - ay) - (qx - ax) * (by - ay)) / area;
        final w0 = 1 - w1 - w2;
        if (w0 < 0 || w1 < 0 || w2 < 0) continue;
        final d = w0 * pd[a] + w1 * pd[b] + w2 * pd[c];
        final i = r * w + col;
        if (d < depth[i]) {
          depth[i] = d;
          owner[i] = f;
        }
      }
    }
  }
}

/// Where each visible face's label goes, from the id grid [owner].
List<FaceMark> _place(OcctMeshData m, Int32List owner, int w, int h, double sx,
    double sy, Size size, int max) {
  // Distance, in cells, from every covered cell to the nearest cell that is
  // NOT the same face (another face, background, or the frame). Two chamfer
  // passes; the maximum over a face is the point of it furthest from its
  // neighbours — where a label is unmistakably on that face.
  const diag = 1.4142;
  final dist = Float64List(w * h);
  for (var r = 0; r < h; r++) {
    for (var col = 0; col < w; col++) {
      final i = r * w + col;
      final o = owner[i];
      if (o < 0) continue;
      var edge = r == 0 || col == 0 || r == h - 1 || col == w - 1;
      for (var dr = -1; !edge && dr <= 1; dr++) {
        for (var dc = -1; dc <= 1; dc++) {
          if (owner[(r + dr) * w + col + dc] != o) {
            edge = true;
            break;
          }
        }
      }
      dist[i] = edge ? 1 : 1e9;
    }
  }
  void relax(int i, int j, double step) {
    if (owner[j] == owner[i] && dist[j] + step < dist[i])
      dist[i] = dist[j] + step;
  }

  for (var r = 1; r < h - 1; r++) {
    for (var col = 1; col < w - 1; col++) {
      final i = r * w + col;
      if (owner[i] < 0) continue;
      relax(i, i - 1, 1);
      relax(i, i - w, 1);
      relax(i, i - w - 1, diag);
      relax(i, i - w + 1, diag);
    }
  }
  for (var r = h - 2; r >= 1; r--) {
    for (var col = w - 2; col >= 1; col--) {
      final i = r * w + col;
      if (owner[i] < 0) continue;
      relax(i, i + 1, 1);
      relax(i, i + w, 1);
      relax(i, i + w + 1, diag);
      relax(i, i + w - 1, diag);
    }
  }

  final count = <int, int>{};
  final far = <int, double>{};
  final sumC = <int, double>{}, sumR = <int, double>{};
  for (var i = 0; i < owner.length; i++) {
    final f = owner[i];
    if (f < 0) continue;
    count[f] = (count[f] ?? 0) + 1;
    far[f] = math.max(far[f] ?? 0, dist[i]);
    sumC[f] = (sumC[f] ?? 0) + i % w;
    sumR[f] = (sumR[f] ?? 0) + i ~/ w;
  }
  // A long strip is equally far from its sides all along its middle; of
  // the cells nearly that deep, take the one nearest where the face is
  // seen, so its label sits mid-strip rather than at one end.
  final best = <int, int>{};
  final bestOff = <int, double>{};
  for (var i = 0; i < owner.length; i++) {
    final f = owner[i];
    if (f < 0 || dist[i] < far[f]! * 0.7) continue;
    final n = count[f]!;
    final dc = i % w - sumC[f]! / n, dr = i ~/ w - sumR[f]! / n;
    final off = dc * dc + dr * dr;
    if (best[f] == null || off < bestOff[f]!) {
      best[f] = i;
      bestOff[f] = off;
    }
  }

  // A face too thin to hold a label, or a sliver of a few cells, would get a
  // label that covers its neighbours more than itself.
  final minCells = math.max(6, (w * h * 0.002).round());
  final faces = [
    for (final f in count.keys)
      if (count[f]! >= minCells && dist[best[f]!] >= 1.9) f
  ]..sort((a, b) => count[b]!.compareTo(count[a]!));

  final placed = <Rect>[];
  final out = <FaceMark>[];
  for (final f in faces) {
    if (out.length >= max) break;
    final i = best[f]!;
    final at = Offset(((i % w) + 0.5) / sx, ((i ~/ w) + 0.5) / sy);
    final text = faceMarkText(m, f);
    final box = labelBox(at, text, size);
    if (placed.any((p) => p.overlaps(box))) continue;
    placed.add(box);
    out.add(FaceMark(f, text, at, count[f]!));
  }
  return out;
}

/// The label's footprint in logical pixels, for keeping labels apart. Sized
/// from the view so a label stays legible at any resolution the model asks
/// for, and the same function draws it, so what was kept apart stays apart.
Rect labelBox(Offset at, String text, Size view) {
  final fs = labelFontSize(view);
  return Rect.fromCenter(
      center: at, width: text.length * fs * 0.62 + fs * 0.8, height: fs * 1.5);
}

double labelFontSize(Size view) =>
    (math.min(view.width, view.height) / 38).clamp(10, 22).toDouble();

/// Draws [marks] and an axis triad over [png], which was rendered through
/// [cam] at [cam.size] logical pixels (the image itself may be larger — the
/// native renderer draws at the device's scale). Returns null, never a
/// half-drawn picture, when the image does not have the view's proportions:
/// a label drawn through the wrong mapping would point at the wrong face,
/// which is worse than no label.
Future<Uint8List?> drawFaceMarks(
    Uint8List png, Cam3 cam, List<FaceMark> marks) async {
  final view = cam.size;
  ui.Image? img;
  ui.Image? out;
  try {
    final codec = await ui.instantiateImageCodec(png);
    img = (await codec.getNextFrame()).image;
    codec.dispose();
    final k = img.width / view.width;
    if (!(k > 0) || (img.height / k - view.height).abs() > view.height * 0.02) {
      return null;
    }
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawImage(img, Offset.zero, Paint());
    c.scale(k);
    final fs = labelFontSize(view);

    for (final m in marks) {
      final tp = TextPainter(
          text: TextSpan(
              text: m.text,
              style: TextStyle(
                  color: kAiLabelInk,
                  fontSize: fs,
                  fontWeight: FontWeight.w700)),
          textDirection: TextDirection.ltr)
        ..layout();
      final box = Rect.fromCenter(
          center: m.at,
          width: tp.width + fs * 0.8,
          height: tp.height + fs * 0.3);
      final rr = RRect.fromRectAndRadius(box, Radius.circular(desktopRadius(fs * 0.35)));
      c.drawRRect(rr, Paint()..color = kAiLabelFill);
      c.drawRRect(
          rr,
          Paint()
            ..color = kAiLabelInk
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1, fs / 12));
      tp.paint(c, Offset(box.left + fs * 0.4, box.top + fs * 0.15));
      tp.dispose();
    }

    _drawTriad(c, cam, view, fs);

    out = await rec.endRecording().toImage(img.width, img.height);
    final bytes = await out.toByteData(format: ui.ImageByteFormat.png);
    return bytes?.buffer.asUint8List();
  } catch (_) {
    return null;
  } finally {
    img?.dispose();
    out?.dispose();
  }
}

/// X red, Y green (up), Z blue, in the bottom-left corner, foreshortened
/// exactly as the camera sees them — an axis pointing at the eye is a short
/// stub, which is the truth about it.
void _drawTriad(Canvas c, Cam3 cam, Size view, double fs) {
  final len = fs * 2.6;
  // A full axis length plus a label of margin on every side: any of the
  // three may point straight at a corner.
  final o = Offset(len + fs * 1.8, view.height - len - fs * 1.8);
  const axes = [
    (Vec3(1, 0, 0), 'X', kAiAxisX),
    (Vec3(0, 1, 0), 'Y up', kAiAxisY),
    (Vec3(0, 0, 1), 'Z', kAiAxisZ),
  ];
  for (final (v, axis, colour) in axes) {
    final d = Offset(v.dot(cam.s), -v.dot(cam.u));
    // An axis along the line of sight is a dot on screen; say which way it
    // runs, or "from below" and "from above" read the same.
    final name = d.distance > 0.2
        ? axis
        : '$axis ${v.dot(cam.dir) > 0 ? "toward you" : "away from you"}';
    final tip = o + d * len;
    c.drawLine(
        o,
        tip,
        Paint()
          ..color = colour
          ..strokeWidth = math.max(2, fs / 6)
          ..strokeCap = StrokeCap.round);
    final tp = TextPainter(
        text: TextSpan(
            text: name,
            style: TextStyle(
                color: colour,
                fontSize: fs * 0.9,
                fontWeight: FontWeight.w700)),
        textDirection: TextDirection.ltr)
      ..layout();
    if (d.distance <= 0.2) {
      // Under the triad, clear of the two axes that do have a direction.
      tp.paint(c, Offset(o.dx - fs * 0.4, o.dy + fs * 0.5));
    } else {
      final dir = d / d.distance;
      final at = tip + dir * (fs * 0.5);
      tp.paint(
          c,
          Offset(at.dx - tp.width / 2 + dir.dx * tp.width / 2,
              at.dy - tp.height / 2 + dir.dy * tp.height / 2));
    }
    tp.dispose();
  }
}

/// Where a face runs, in world millimetres: "x=40 · y 2..334 · z -270..-40".
/// An axis the face is flat across prints as one value, so a plane reads as
/// the plane it is and its two spans as the size it has.
String faceSpan(Vec3 lo, Vec3 hi) {
  String one(String n, double a, double b) {
    String f(double v) {
      final r = (v * 100).roundToDouble() / 100;
      final t = r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toString();
      return t == '-0' ? '0' : t;
    }

    return (b - a).abs() < 0.01
        ? '$n=${f((a + b) / 2)}'
        : '$n ${f(a)}..${f(b)}';
  }

  return '${one('x', lo.x, hi.x)} · ${one('y', lo.y, hi.y)} · '
      '${one('z', lo.z, hi.z)}';
}
