import 'dart:math' as math;
import 'package:flutter/material.dart';

// ============================================================
// iPadProCAD — AutoCAD-style dark UI
// Ribbon: Draw | Modify | Constraint (M4 UI milestone)
// Geometry is held in Dart state for now; FFI wiring to
// libqcadcapi (qcad_add_line/_circle/_arc/_polyline) follows.
// ============================================================

// ---- AutoCAD 2023 dark palette ----
const kTitleBar = Color(0xFF24272B);
const kRibbonTab = Color(0xFF2E3236);
const kRibbonBody = Color(0xFF33373C);
const kPanelLabel = Color(0xFF2A2D31);
const kCanvasBg = Color(0xFF212830);
const kCmdLine = Color(0xFF2B2F33);
const kStatusBar = Color(0xFF24272B);
const kAccent = Color(0xFF0696D7); // AutoCAD blue
const kText = Color(0xFFD8D8D8);
const kTextDim = Color(0xFF9A9A9A);
const kStroke = Color(0xFFE6E6E6);

void main() => runApp(const CadApp());

class CadApp extends StatelessWidget {
  const CadApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        home: const CadShell(),
      );
}

// ---------------- entities ----------------
enum Tool { none, line, polyline, circle, arc, rectangle, move, copy, erase, rotate, mirror }

abstract class Ent {
  void paint(Canvas c, Paint p);
  bool hit(Offset pt, double tol);
  void translate(Offset d);
}

class LineEnt extends Ent {
  Offset a, b;
  LineEnt(this.a, this.b);
  @override
  void paint(Canvas c, Paint p) => c.drawLine(a, b, p);
  @override
  bool hit(Offset pt, double tol) => _distSeg(pt, a, b) < tol;
  @override
  void translate(Offset d) { a += d; b += d; }
}

class CircleEnt extends Ent {
  Offset ctr; double r;
  CircleEnt(this.ctr, this.r);
  @override
  void paint(Canvas c, Paint p) => c.drawCircle(ctr, r, p);
  @override
  bool hit(Offset pt, double tol) => ((pt - ctr).distance - r).abs() < tol;
  @override
  void translate(Offset d) => ctr += d;
}

class ArcEnt extends Ent {
  Offset ctr; double r, a0, a1;
  ArcEnt(this.ctr, this.r, this.a0, this.a1);
  @override
  void paint(Canvas c, Paint p) =>
      c.drawArc(Rect.fromCircle(center: ctr, radius: r), a0, a1 - a0, false, p);
  @override
  bool hit(Offset pt, double tol) => ((pt - ctr).distance - r).abs() < tol;
  @override
  void translate(Offset d) => ctr += d;
}

class PolyEnt extends Ent {
  List<Offset> pts;
  PolyEnt(this.pts);
  @override
  void paint(Canvas c, Paint p) {
    for (var i = 0; i < pts.length - 1; i++) c.drawLine(pts[i], pts[i + 1], p);
  }
  @override
  bool hit(Offset pt, double tol) {
    for (var i = 0; i < pts.length - 1; i++) {
      if (_distSeg(pt, pts[i], pts[i + 1]) < tol) return true;
    }
    return false;
  }
  @override
  void translate(Offset d) => pts = pts.map((p) => p + d).toList();
}

double _distSeg(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final t = ((p - a).dx * ab.dx + (p - a).dy * ab.dy) / (ab.distanceSquared == 0 ? 1 : ab.distanceSquared);
  final tc = t.clamp(0.0, 1.0);
  return (p - (a + ab * tc)).distance;
}

// ---------------- shell ----------------
class CadShell extends StatefulWidget {
  const CadShell({super.key});
  @override
  State<CadShell> createState() => _CadShellState();
}

class _CadShellState extends State<CadShell> {
  Tool tool = Tool.none;
  final List<Ent> ents = [];
  final List<Offset> picked = [];
  Offset? cursor;
  Ent? selected;
  String prompt = 'Type a command';
  final List<String> history = ['iPadProCAD — QCAD core ready'];

  void _setTool(Tool t, String cmd, String firstPrompt) {
    setState(() {
      tool = t;
      picked.clear();
      selected = null;
      history.add('Command: $cmd');
      prompt = firstPrompt;
    });
  }

  void _cancel() => setState(() {
        tool = Tool.none;
        picked.clear();
        selected = null;
        prompt = 'Type a command';
      });

  void _tap(Offset p) {
    setState(() {
      switch (tool) {
        case Tool.line:
          picked.add(p);
          if (picked.length == 2) {
            ents.add(LineEnt(picked[0], picked[1]));
            history.add('LINE  ${_fmt(picked[0])} → ${_fmt(picked[1])}');
            picked.clear();
            prompt = 'LINE  Specify first point:';
          } else {
            prompt = 'LINE  Specify next point:';
          }
        case Tool.polyline:
          picked.add(p);
          prompt = 'PLINE  Specify next point (double-tap to finish):';
        case Tool.circle:
          picked.add(p);
          if (picked.length == 2) {
            ents.add(CircleEnt(picked[0], (picked[1] - picked[0]).distance));
            history.add('CIRCLE  r=${(picked[1] - picked[0]).distance.toStringAsFixed(1)}');
            picked.clear();
            prompt = 'CIRCLE  Specify center point:';
          } else {
            prompt = 'CIRCLE  Specify radius:';
          }
        case Tool.arc:
          picked.add(p);
          if (picked.length == 3) {
            final r = (picked[1] - picked[0]).distance;
            final a0 = math.atan2(picked[1].dy - picked[0].dy, picked[1].dx - picked[0].dx);
            final a1 = math.atan2(picked[2].dy - picked[0].dy, picked[2].dx - picked[0].dx);
            ents.add(ArcEnt(picked[0], r, a0, a1));
            history.add('ARC  r=${r.toStringAsFixed(1)}');
            picked.clear();
            prompt = 'ARC  Specify center point:';
          } else {
            prompt = picked.length == 1 ? 'ARC  Specify start point:' : 'ARC  Specify end angle:';
          }
        case Tool.rectangle:
          picked.add(p);
          if (picked.length == 2) {
            final a = picked[0], b = picked[1];
            ents.add(PolyEnt([a, Offset(b.dx, a.dy), b, Offset(a.dx, b.dy), a]));
            history.add('RECTANG  ${_fmt(a)} → ${_fmt(b)}');
            picked.clear();
            prompt = 'RECTANG  Specify first corner:';
          } else {
            prompt = 'RECTANG  Specify other corner:';
          }
        case Tool.erase:
          final e = _pick(p);
          if (e != null) {
            ents.remove(e);
            history.add('ERASE  1 found');
          }
        case Tool.move:
        case Tool.copy:
          if (selected == null) {
            selected = _pick(p);
            if (selected != null) prompt = '${tool == Tool.move ? 'MOVE' : 'COPY'}  Specify base point:';
          } else if (picked.isEmpty) {
            picked.add(p);
            prompt = 'Specify second point:';
          } else {
            final d = p - picked[0];
            if (tool == Tool.copy) {
              final src = selected!;
              Ent cp;
              if (src is LineEnt) cp = LineEnt(src.a, src.b);
              else if (src is CircleEnt) cp = CircleEnt(src.ctr, src.r);
              else if (src is ArcEnt) cp = ArcEnt(src.ctr, src.r, src.a0, src.a1);
              else cp = PolyEnt(List.of((src as PolyEnt).pts));
              cp.translate(d);
              ents.add(cp);
            } else {
              selected!.translate(d);
            }
            history.add(tool == Tool.move ? 'MOVE  done' : 'COPY  done');
            selected = null;
            picked.clear();
            prompt = 'Select object:';
          }
        default:
          selected = _pick(p);
      }
    });
  }

  void _finishPolyline() {
    if (tool == Tool.polyline && picked.length > 1) {
      setState(() {
        ents.add(PolyEnt(List.of(picked)));
        history.add('PLINE  ${picked.length} vertices');
        picked.clear();
        prompt = 'PLINE  Specify start point:';
      });
    }
  }

  Ent? _pick(Offset p) {
    for (final e in ents.reversed) {
      if (e.hit(p, 8)) return e;
    }
    return null;
  }

  String _fmt(Offset p) => '${p.dx.toStringAsFixed(1)},${p.dy.toStringAsFixed(1)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCanvasBg,
      body: Column(children: [
        _titleBar(),
        _ribbonTabs(),
        _ribbon(),
        Expanded(child: _canvas()),
        _commandLine(),
        _statusBar(),
      ]),
    );
  }

  // ---------- chrome ----------
  Widget _titleBar() => Container(
        height: 34,
        color: kTitleBar,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: const Color(0xFFC22026), borderRadius: BorderRadius.circular(2)),
            child: const Text('iP', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
          const SizedBox(width: 12),
          const Text('iPadProCAD    Drawing1.dwg',
              style: TextStyle(color: kText, fontSize: 12)),
          const Spacer(),
          const Icon(Icons.search, size: 15, color: kTextDim),
        ]),
      );

  Widget _ribbonTabs() {
    const tabs = ['Home', 'Insert', 'Annotate', 'Parametric', 'View', 'Manage', 'Output'];
    return Container(
      height: 28,
      color: kRibbonTab,
      child: Row(children: [
        for (var i = 0; i < tabs.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            color: i == 0 ? kRibbonBody : Colors.transparent,
            child: Text(tabs[i],
                style: TextStyle(fontSize: 12, color: i == 0 ? Colors.white : kTextDim)),
          ),
      ]),
    );
  }

  Widget _ribbon() => Container(
        height: 96,
        color: kRibbonBody,
        child: Row(children: [
          _panel('Draw', [
            _tb(Icons.show_chart, 'Line', tool == Tool.line,
                () => _setTool(Tool.line, 'LINE', 'LINE  Specify first point:')),
            _tb(Icons.timeline, 'Polyline', tool == Tool.polyline,
                () => _setTool(Tool.polyline, 'PLINE', 'PLINE  Specify start point:')),
            _tb(Icons.circle_outlined, 'Circle', tool == Tool.circle,
                () => _setTool(Tool.circle, 'CIRCLE', 'CIRCLE  Specify center point:')),
            _tb(Icons.architecture, 'Arc', tool == Tool.arc,
                () => _setTool(Tool.arc, 'ARC', 'ARC  Specify center point:')),
            _tb(Icons.crop_square, 'Rectangle', tool == Tool.rectangle,
                () => _setTool(Tool.rectangle, 'RECTANG', 'RECTANG  Specify first corner:')),
          ]),
          _panel('Modify', [
            _tb(Icons.open_with, 'Move', tool == Tool.move,
                () => _setTool(Tool.move, 'MOVE', 'MOVE  Select object:')),
            _tb(Icons.copy, 'Copy', tool == Tool.copy,
                () => _setTool(Tool.copy, 'COPY', 'COPY  Select object:')),
            _tb(Icons.rotate_right, 'Rotate', tool == Tool.rotate,
                () => _setTool(Tool.rotate, 'ROTATE', 'ROTATE  (coming with FFI ops)')),
            _tb(Icons.flip, 'Mirror', tool == Tool.mirror,
                () => _setTool(Tool.mirror, 'MIRROR', 'MIRROR  (coming with FFI ops)')),
            _tb(Icons.close, 'Erase', tool == Tool.erase,
                () => _setTool(Tool.erase, 'ERASE', 'ERASE  Select object:')),
          ]),
          _panel('Constraint', [
            _tb(Icons.horizontal_rule, 'Horizontal', false, () => _note('GCHORIZONTAL')),
            _tb(Icons.height, 'Vertical', false, () => _note('GCVERTICAL')),
            _tb(Icons.menu, 'Parallel', false, () => _note('GCPARALLEL')),
            _tb(Icons.add, 'Perpend.', false, () => _note('GCPERPENDICULAR')),
            _tb(Icons.adjust, 'Coincident', false, () => _note('GCCOINCIDENT')),
          ]),
        ]),
      );

  void _note(String cmd) => setState(() => history.add('$cmd  — constraint solver lands in M5'));

  Widget _panel(String label, List<Widget> tools) => Container(
        margin: const EdgeInsets.only(right: 1),
        child: Column(children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(mainAxisSize: MainAxisSize.min, children: tools),
            ),
          ),
          Container(
            width: double.infinity,
            color: kPanelLabel,
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10, color: kTextDim)),
          ),
        ]),
      );

  Widget _tb(IconData ic, String label, bool active, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Container(
          width: 58,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: active ? kAccent.withOpacity(.25) : Colors.transparent,
            border: Border.all(color: active ? kAccent : Colors.transparent),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(ic, size: 24, color: active ? kAccent : kText),
            const SizedBox(height: 3),
            Text(label, style: const TextStyle(fontSize: 9.5, color: kText)),
          ]),
        ),
      );

  // ---------- canvas ----------
  Widget _canvas() => GestureDetector(
        onTapUp: (d) => _tap(d.localPosition),
        onDoubleTap: _finishPolyline,
        child: MouseRegion(
          onHover: (e) => setState(() => cursor = e.localPosition),
          cursor: SystemMouseCursors.precise,
          child: CustomPaint(
            painter: _CadPainter(ents, picked, cursor, tool, selected),
            size: Size.infinite,
          ),
        ),
      );

  Widget _commandLine() => Container(
        color: kCmdLine,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(history.last, style: const TextStyle(fontSize: 11, color: kTextDim, fontFamily: 'monospace')),
          Row(children: [
            const Icon(Icons.keyboard_arrow_right, size: 14, color: kAccent),
            Expanded(
              child: Text(prompt,
                  style: const TextStyle(fontSize: 12, color: kText, fontFamily: 'monospace')),
            ),
            if (tool != Tool.none)
              TextButton(onPressed: _cancel, child: const Text('Esc', style: TextStyle(fontSize: 11))),
          ]),
        ]),
      );

  Widget _statusBar() => Container(
        height: 26,
        color: kStatusBar,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(children: [
          Text(cursor == null ? '' : _fmt(cursor!),
              style: const TextStyle(fontSize: 11, color: kTextDim, fontFamily: 'monospace')),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            color: kAccent.withOpacity(.2),
            child: const Text('MODEL', style: TextStyle(fontSize: 10, color: kAccent)),
          ),
          const SizedBox(width: 10),
          Text('${ents.length} entities', style: const TextStyle(fontSize: 11, color: kTextDim)),
        ]),
      );
}

class _CadPainter extends CustomPainter {
  final List<Ent> ents;
  final List<Offset> picked;
  final Offset? cursor;
  final Tool tool;
  final Ent? selected;
  _CadPainter(this.ents, this.picked, this.cursor, this.tool, this.selected);

  @override
  void paint(Canvas c, Size s) {
    final grid = Paint()..color = const Color(0xFF2C3540)..strokeWidth = 1;
    for (double x = 0; x < s.width; x += 40) c.drawLine(Offset(x, 0), Offset(x, s.height), grid);
    for (double y = 0; y < s.height; y += 40) c.drawLine(Offset(0, y), Offset(s.width, y), grid);

    final p = Paint()..color = kStroke..strokeWidth = 1.4..style = PaintingStyle.stroke;
    for (final e in ents) e.paint(c, p);
    if (selected != null) {
      selected!.paint(c, Paint()..color = kAccent..strokeWidth = 2..style = PaintingStyle.stroke);
    }

    // rubber band
    if (cursor != null && picked.isNotEmpty) {
      final rb = Paint()..color = kAccent..strokeWidth = 1..style = PaintingStyle.stroke;
      switch (tool) {
        case Tool.line:
        case Tool.polyline:
          for (var i = 0; i < picked.length - 1; i++) c.drawLine(picked[i], picked[i + 1], rb);
          c.drawLine(picked.last, cursor!, rb);
        case Tool.circle:
          c.drawCircle(picked[0], (cursor! - picked[0]).distance, rb);
        case Tool.rectangle:
          c.drawRect(Rect.fromPoints(picked[0], cursor!), rb);
        case Tool.arc:
          c.drawCircle(picked[0], picked.length > 1 ? (picked[1] - picked[0]).distance : (cursor! - picked[0]).distance, rb..color = kAccent.withOpacity(.5));
        default:
      }
    }

    // crosshair
    if (cursor != null) {
      final ch = Paint()..color = const Color(0xFF8FBF8F)..strokeWidth = .8;
      c.drawLine(Offset(cursor!.dx - 30, cursor!.dy), Offset(cursor!.dx + 30, cursor!.dy), ch);
      c.drawLine(Offset(cursor!.dx, cursor!.dy - 30), Offset(cursor!.dx, cursor!.dy + 30), ch);
      c.drawRect(Rect.fromCenter(center: cursor!, width: 8, height: 8), ch..style = PaintingStyle.stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _CadPainter old) => true;
}
