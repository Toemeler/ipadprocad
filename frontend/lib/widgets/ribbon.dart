// iPadProCAD — ribbon, 1:1 port of the mock's #ribbon.
// Panel order (binding): Layer, Create, Project Geometry, Pattern, Constrain,
// Insert, Format, Modify (last). Exit panel appears top-right in edit mode.
// Home view: all panels hidden except the single "Create New Sketch" panel.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../app_state.dart';
import '../log.dart';
import '../svg_icons.dart';
import '../tools.dart';
import '../theme.dart';

Widget svg(String s, double size) =>
    SvgPicture.string(s, width: size, height: size);

/// Descriptor for one flyout entry: icon key, bold line, subtitle, and the
/// (optional) real tool it activates.
class FlyItem {
  final String icon, b, sub;
  final Tool? tool;
  const FlyItem(this.icon, this.b, this.sub, [this.tool]);
}

/// One entry of a PANEL OVERFLOW menu (the ▼ next to a panel's title). These
/// are the commands that stay available but no longer earn permanent ribbon
/// width — Inventor does the same with its panel expanders. Unlike [FlyItem]
/// they carry a raw SVG string (the icon maps differ per panel) and a plain
/// callback, so toggles and settings fit as well as tools.
class OverItem {
  final String icon, label;
  final VoidCallback? onTap;
  final bool active;
  const OverItem(this.icon, this.label, this.onTap, {this.active = false});
}

const flyouts = <String, List<FlyItem>>{
  'line': [
    FlyItem('fline', 'Line', 'Line', Tool.line),
    FlyItem('fmidline', 'Line', 'Midpoint Line', Tool.lineMid),
    FlyItem('fsplinecv', 'Spline', 'Control Vertex', Tool.splineCV),
    FlyItem('fsplinei', 'Spline', 'Interpolation', Tool.splineInterp),
    FlyItem('feqcurve', 'Equation Curve', 'Equation Curve', Tool.eqCurve),
    FlyItem('fbridge', 'Bridge Curve', 'Bridge Curve', Tool.bridge),
  ],
  'circle': [
    FlyItem('fcirclecp', 'Circle', 'Center Point', Tool.circleCenter),
    FlyItem('fcircletan', 'Circle', 'Tangent', Tool.circleTangent),
    FlyItem('fellipse', 'Ellipse', 'Ellipse', Tool.ellipse),
  ],
  'arc': [
    FlyItem('farc3', 'Arc', 'Three Point', Tool.arcThreePoint),
    FlyItem('farctan', 'Arc', 'Tangent', Tool.arcTangent),
    FlyItem('farccp', 'Arc', 'Center Point', Tool.arcCenter),
  ],
  'rect': [
    FlyItem('frect2p', 'Rectangle', 'Two Point', Tool.rectTwoPoint),
    FlyItem('frect3p', 'Rectangle', 'Three Point', Tool.rect3P),
    FlyItem('frect2pc', 'Rectangle', 'Two Point Center', Tool.rect2PC),
    FlyItem('frect3pc', 'Rectangle', 'Three Point Center', Tool.rect3PC),
    FlyItem('fslotcc', 'Slot', 'Center to Center', Tool.slotCC),
    FlyItem('fslotov', 'Slot', 'Overall', Tool.slotOverall),
    FlyItem('fslotcp', 'Slot', 'Center Point', Tool.slotCP),
    FlyItem('fslot3a', 'Slot', 'Three Point Arc', Tool.slot3A),
    FlyItem('fslotcpa', 'Slot', 'Center Point Arc', Tool.slotCPA),
    FlyItem('fpolygon', 'Polygon', 'Polygon', Tool.polygon),
  ],
  'fillet': [
    FlyItem('ffillet', 'Fillet', '', Tool.fillet),
    FlyItem('fchamfer', 'Chamfer', '', Tool.chamfer),
  ],
  'text': [
    FlyItem('ftext', 'Text', ''),
    FlyItem('fgtext', 'Geometry Text', ''),
  ],
};

/// Which flyout group a tool belongs to (for the active highlight on the
/// big ribbon buttons). Esc clears the tool and thus the highlight.
const _toolGroup = <Tool, String>{
  Tool.line: 'line', Tool.lineMid: 'line', Tool.splineCV: 'line',
  Tool.splineInterp: 'line', Tool.eqCurve: 'line', Tool.bridge: 'line',
  Tool.circleCenter: 'circle', Tool.circleTangent: 'circle',
  Tool.ellipse: 'circle',
  Tool.arcThreePoint: 'arc', Tool.arcTangent: 'arc', Tool.arcCenter: 'arc',
  Tool.rectTwoPoint: 'rect', Tool.rect3P: 'rect', Tool.rect2PC: 'rect',
  Tool.rect3PC: 'rect', Tool.slotCC: 'rect', Tool.slotOverall: 'rect',
  Tool.slotCP: 'rect', Tool.slot3A: 'rect', Tool.slotCPA: 'rect',
  Tool.polygon: 'rect',
  Tool.fillet: 'fillet', Tool.chamfer: 'fillet',
  Tool.point: 'point',
};

/// Ribbon widget. Flyout state lives here; flyouts render in an Overlay
/// anchored DIRECTLY under the clicked element (mock: anchor.bottom).
class Ribbon extends StatefulWidget {
  final AppState app;
  const Ribbon({super.key, required this.app});
  @override
  State<Ribbon> createState() => _RibbonState();
}

class _RibbonState extends State<Ribbon> {
  OverlayEntry? _fly;
  String? _flyId;

  void closeFly() {
    _fly?.remove();
    _fly = null;
    _flyId = null;
  }

  @override
  void dispose() {
    closeFly();
    super.dispose();
  }

  void toggleFly(String id, BuildContext anchorCtx) {
    if (_flyId == id) {
      closeFly();
      return;
    }
    closeFly();
    final box = anchorCtx.findRenderObject() as RenderBox;
    final pos = box.localToGlobal(Offset.zero);
    final items = flyouts[id]!;
    _fly = OverlayEntry(
      builder: (_) => Stack(children: [
        Positioned.fill(
            child: GestureDetector(
                behavior: HitTestBehavior.translucent, onTap: closeFly)),
        Positioned(
          left: pos.dx,
          top: pos.dy + box.size.height + 1,
          child: _FlyMenu(
            items: items,
            onPick: (it) {
              closeFly();
              if (it.tool != null) _startTool(it.tool!);
            },
          ),
        ),
      ]),
    );
    Overlay.of(context).insert(_fly!);
    setState(() => _flyId = id);
  }

  /// Opens a PANEL OVERFLOW menu under the panel's title row. Same overlay
  /// lifecycle as [toggleFly] (one open menu at a time, tap-outside closes),
  /// but the items are arbitrary commands rather than tool variants.
  void toggleOver(String id, BuildContext anchorCtx, List<OverItem> items) {
    if (_flyId == id) {
      closeFly();
      return;
    }
    closeFly();
    final box = anchorCtx.findRenderObject() as RenderBox;
    final pos = box.localToGlobal(Offset.zero);
    _fly = OverlayEntry(
      builder: (_) => Stack(children: [
        Positioned.fill(
            child: GestureDetector(
                behavior: HitTestBehavior.translucent, onTap: closeFly)),
        Positioned(
          left: pos.dx,
          // the title sits at the panel's BOTTOM, so the menu opens upward
          bottom: MediaQuery.of(context).size.height - pos.dy + 1,
          child: _OverMenu(
            items: items,
            onPick: (it) {
              closeFly();
              it.onTap?.call();
            },
          ),
        ),
      ]),
    );
    Overlay.of(context).insert(_fly!);
    setState(() => _flyId = id);
  }

  /// Starts a tool; asks for parameters first where Inventor would
  /// (polygon sides, fillet radius, chamfer distance, equation + range).
  // ---- M44: Insert > Image / ACAD via the iOS file picker ----
  Future<void> _pickImage(AppState app) async {
    if (app.current == null) return;
    try {
      final res = await FilePicker.platform
          .pickFiles(type: FileType.image, withData: false);
      final path = res?.files.single.path;
      if (path == null) return;
      // decode once for the aspect ratio (the viewport re-decodes its copy)
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final fr = await codec.getNextFrame();
      // M45: placed AT THE CURSOR, sized to half the current view width
      app.addImage(path, app.insertAnchor,
          pxW: fr.image.width,
          pxH: fr.image.height,
          w: app.viewWidthWorld * 0.5);
    } catch (e) {
      Log.w('insert', 'image pick failed: $e');
      app.toast('Could not import the image.');
    }
  }

  Future<void> _pickDxf(AppState app) async {
    if (app.current == null) return;
    try {
      final res = await FilePicker.platform.pickFiles(
          type: FileType.custom, allowedExtensions: ['dxf', 'DXF']);
      final path = res?.files.single.path;
      if (path == null) return;
      app.importDxf(path);
    } catch (e) {
      Log.w('insert', 'dxf pick failed: $e');
      app.toast('Could not import the DXF file.');
    }
  }

  Future<void> _startTool(Tool t) async {
    final app = widget.app;
    // Nothing may be drawn outside a layer's edit mode — bail BEFORE any
    // parameter dialog, so the user isn't asked for a radius and then refused.
    if (!app.inEditMode) {
      app.toast('Enter a layer to sketch: double-tap it in the model browser.');
      return;
    }
    switch (t) {
      case Tool.polygon:
        final v = await _numDialog('Polygon', [('Sides', '6')]);
        if (v == null) return;
        app.toolParams = {'sides': v[0]};
        break;
      case Tool.fillet:
      case Tool.chamfer:
        // M36: no blocking prompt — the modeless 2D Fillet/Chamfer window
        // opens with the tool and stays editable between corners.
        app.toolParams = {};
        break;
      case Tool.eqCurve:
        final r = await _equationDialog();
        if (r == null) return;
        app.toolExpr = r.$1;
        app.toolParams = {'x0': r.$2, 'x1': r.$3};
        break;
      default:
        app.toolParams = {};
    }
    app.selectTool(t);
  }

  Future<List<double>?> _numDialog(
      String title, List<(String, String)> fields) async {
    final ctrls = [for (final f in fields) TextEditingController(text: f.$2)];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: T.fly,
        title: Text(title, style: ts(14, Colors.white, w: FontWeight.w600)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < fields.length; i++)
            TextField(
              controller: ctrls[i],
              autofocus: i == 0,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: ts(13, T.text),
              decoration: InputDecoration(
                  labelText: fields[i].$1,
                  labelStyle: ts(12, T.dim)),
              onSubmitted: (_) => Navigator.pop(ctx, true),
            ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: ts(12.5, T.dim))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('OK', style: ts(12.5, T.blue))),
        ],
      ),
    );
    if (ok != true) return null;
    final out = <double>[];
    for (final c in ctrls) {
      final v = double.tryParse(c.text.replaceAll(',', '.'));
      if (v == null) return null;
      out.add(v);
    }
    return out;
  }

  Future<(String, double, double)?> _equationDialog() async {
    final expr = TextEditingController(text: 'sin(x)*5');
    final x0 = TextEditingController(text: '0');
    final x1 = TextEditingController(text: '20');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: T.fly,
        title: Text('Equation Curve',
            style: ts(14, Colors.white, w: FontWeight.w600)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: expr,
              autofocus: true,
              style: ts(13, T.text),
              decoration: InputDecoration(
                  labelText: 'y = f(x)   (sin, cos, sqrt, ^, pi, ...)',
                  labelStyle: ts(12, T.dim))),
          Row(children: [
            Expanded(
                child: TextField(
                    controller: x0,
                    style: ts(13, T.text),
                    decoration: InputDecoration(
                        labelText: 'x min', labelStyle: ts(12, T.dim)))),
            const SizedBox(width: 10),
            Expanded(
                child: TextField(
                    controller: x1,
                    style: ts(13, T.text),
                    decoration: InputDecoration(
                        labelText: 'x max', labelStyle: ts(12, T.dim)))),
          ]),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: ts(12.5, T.dim))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('OK', style: ts(12.5, T.blue))),
        ],
      ),
    );
    if (ok != true) return null;
    final a = double.tryParse(x0.text.replaceAll(',', '.'));
    final b = double.tryParse(x1.text.replaceAll(',', '.'));
    if (a == null || b == null || b <= a) return null;
    if (ExprParser(expr.text).parse() == null) return null;
    return (expr.text, a, b);
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return Container(
      decoration: const BoxDecoration(
        color: T.panel,
        border: Border(
          top: BorderSide(color: T.ribbonTop, width: 2),
          bottom: BorderSide(color: T.ribbonBottom, width: 2),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: app.isHome ? _homeRibbon(app) : _sketchRibbon(app),
      ),
    );
  }

  // Home: single "Sketch" panel with the big Create New Sketch button.
  Widget _homeRibbon(AppState app) {
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _panel(
          label: 'Sketch',
          arrow: false,
          first: true,
          child: _BigWide(
              width: 78,
              icon: newSketchIcon,
              label: 'Create\nNew Sketch',
              onTap: app.createNewSketch),
        ),
      ]),
    );
  }

  Widget _sketchRibbon(AppState app) {
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // 1. Layer
        _panel(
          label: 'Layer',
          arrow: false,
          first: true,
          child: _BigWide(
              width: 70,
              icon: layerBigIcon,
              label: 'Start\nNew Layer',
              onTap: app.startNewLayer),
        ),
        // Outside layer edit mode there is NOTHING to do with these: every
        // drawing/modify/constrain tool refuses to run off the edit scope
        // (M16/M17), so showing them was offering buttons that silently did
        // nothing. Only "Start New Layer" — the way IN — stays visible.
        if (app.inEditMode) ...[
        // 2. Create
        _panel(
          label: 'Create',
          arrow: false,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _Big(id: 'line', label: 'Line', icon: IC['line34']!, onFly: toggleFly,
                onDefault: () => _startTool(Tool.line),
                active: _toolGroup[app.tool] == 'line'),
            _Big(id: 'circle', label: 'Circle', icon: IC['circle34']!, onFly: toggleFly,
                onDefault: () => _startTool(Tool.circleCenter),
                active: _toolGroup[app.tool] == 'circle'),
            _Big(id: 'arc', label: 'Arc', icon: IC['arc34']!, onFly: toggleFly,
                onDefault: () => _startTool(Tool.arcThreePoint),
                active: _toolGroup[app.tool] == 'arc'),
            _Big(id: 'rect', label: 'Rectangle', icon: IC['rect34']!, onFly: toggleFly,
                onDefault: () => _startTool(Tool.rectTwoPoint),
                active: _toolGroup[app.tool] == 'rect'),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SmallRow(icon: IC['fillet18']!, label: 'Fillet', flyId: 'fillet', onFly: toggleFly,
                        // Inventor split-button: tapping the BODY starts the
                        // default tool, the ▼ opens the flyout. Without this
                        // onTap only the 14-px arrow did anything and the
                        // Fillet button was effectively dead on touch.
                        onTap: () => _startTool(Tool.fillet),
                        active: _toolGroup[app.tool] == 'fillet'),
                    const SizedBox(height: 2),
                    _SmallRow(icon: IC['text18']!, label: 'Text', flyId: 'text', onFly: toggleFly,
                        // M44: parametric sketch text — tap places, the
                        // dialog takes <Param> placeholders
                        onTap: () => _startTool(Tool.text),
                        active: app.tool == Tool.text),
                    const SizedBox(height: 2),
                    _SmallRow(icon: IC['point18']!, label: 'Point',
                        onTap: () => _startTool(Tool.point),
                        active: app.tool == Tool.point),
                  ]),
            ),
          ]),
        ),
        // 3. Project Geometry (no dropdown)
        _panel(
          label: ' ',
          arrow: false,
          child: _BigWide(width: 76, icon: IC['projgeo']!, label: 'Project\nGeometry',
              onTap: () => _startTool(Tool.project),
              active: app.tool == Tool.project),
        ),
        // 4. Pattern
        _panel(
          label: 'Pattern',
          arrow: false,
          child: Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SmallRow(icon: IC['patrect']!, label: 'Rectangular',
                      onTap: () => _startTool(Tool.patRect),
                      active: app.tool == Tool.patRect),
                  const SizedBox(height: 2),
                  _SmallRow(icon: IC['patcirc']!, label: 'Circular',
                      onTap: () => _startTool(Tool.patCirc),
                      active: app.tool == Tool.patCirc),
                  const SizedBox(height: 2),
                  _SmallRow(icon: IC['patmir']!, label: 'Mirror',
                      onTap: () => _startTool(Tool.mirror),
                      active: app.tool == Tool.mirror),
                ]),
          ),
        ),
        // 5. Constrain — Smooth / Constraint Settings / Show Constraints are
        // rarely used, so they moved behind the title's ▼ instead of costing
        // permanent grid width. They are NOT gone, just one tap deeper.
        _panel(
          label: 'Constrain',
          arrow: false,
          overId: 'ov-constrain',
          over: () => [
            OverItem(CN['smooth']!, 'Smooth (G2)',
                () => _startTool(Tool.cSmooth),
                active: app.tool == Tool.cSmooth),
            OverItem(CN['conset']!, 'Constraint Settings',
                app.toggleShowDof, active: app.showDof),
            OverItem(CN['showcons']!, 'Show Constraints',
                app.toggleShowConstraints, active: app.showConstraints),
          ],
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              width: 66,
              child: _Hover(
                activeHighlight: app.tool == Tool.dimension,
                onTap: () => _startTool(Tool.dimension),
                child: const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: _BigPlainBody(label: 'Dimension'),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: _ConGrid(app: app, onTool: _startTool),
            ),
          ]),
        ),
        // 6. Insert + Format + Manage, MERGED into one narrow panel.
        // Visible: the four things actually reached for (Image, ACAD,
        // Construction, Parameters). Everything else — Points, Show Format,
        // Center Point, Centerline, Driven Dimension — is one tap away behind
        // the title's ▼ instead of eating three panels of ribbon width.
        _panel(
          label: 'Insert',
          arrow: false,
          overId: 'ov-insert',
          over: () => [
            OverItem(IN['points']!, 'Points', null),
            OverItem(IN['sphere']!, 'Centerline',
                app.toggleCenterlineSelected),
            OverItem(IN['center']!, 'Center Point', null),
            OverItem(IN['driven']!, 'Driven Dimension', null),
            OverItem(IN['showfmt']!, 'Show Format', null),
          ],
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SmallRow(
                      icon: IN['image']!,
                      label: 'Image',
                      onTap: () => _pickImage(app)),
                  const SizedBox(height: 2),
                  _SmallRow(
                      icon: IN['acad']!,
                      label: 'ACAD',
                      onTap: () => _pickDxf(app)),
                ]),
            Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SmallRow(
                      icon: IN['constr']!,
                      label: 'Construction',
                      onTap: app.toggleConstructionSelected),
                  const SizedBox(height: 2),
                  _SmallRow(
                      icon: IN['constr']!, // unused: iconWidget wins
                      iconWidget: const Text('fx',
                          style: TextStyle(
                              color: T.blue,
                              fontSize: 14,
                              height: 1.0,
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.w700)),
                      label: 'Parameters',
                      onTap: app.toggleParams,
                      active: app.showParams),
                ]),
          ]),
        ),
        // 8. Modify (LAST block). Only the three sketch-shaping commands keep
        // permanent width; the transform family (Move/Copy/Rotate/Scale/
        // Stretch) and Extend moved behind the title's ▼ — still there, just
        // not paid for in ribbon real estate.
        _panel(
          label: 'Modify',
          arrow: false,
          overId: 'ov-modify',
          over: () => [
            OverItem(MD['extend']!, 'Extend',
                () => _startTool(Tool.extendT),
                active: app.tool == Tool.extendT),
            OverItem(MD['move']!, 'Move', () => _startTool(Tool.move),
                active: app.tool == Tool.move),
            OverItem(MD['copy']!, 'Copy', () => _startTool(Tool.mcopy),
                active: app.tool == Tool.mcopy),
            OverItem(MD['mrotate']!, 'Rotate',
                () => _startTool(Tool.mrotate),
                active: app.tool == Tool.mrotate),
            OverItem(MD['mscale']!, 'Scale', () => _startTool(Tool.mscale),
                active: app.tool == Tool.mscale),
            OverItem(MD['stretch']!, 'Stretch',
                () => _startTool(Tool.mstretch),
                active: app.tool == Tool.mstretch),
          ],
          child: Row(children: [
            _modCol(['trim', 'split', 'moffset'], ['Trim', 'Split', 'Offset'],
                leftPad: 2),
          ]),
        ),
        ],
        // Exit panel (only in layer edit mode), pinned to the right in spirit;
        // in a scrolling ribbon it follows Modify like #panel-exit.on does.
        if (app.inEditMode)
          _panel(
            label: 'Exit',
            arrow: false,
            child: _BigWide(
                width: 64,
                icon: finishIcon,
                label: 'Finish',
                onTap: () => app.finishEdit()),
          ),
      ]),
    );
  }

  static const _modToolOf = <String, Tool>{
    'move': Tool.move, 'copy': Tool.mcopy, 'mrotate': Tool.mrotate,
    'trim': Tool.trim, 'extend': Tool.extendT, 'split': Tool.split,
    'mscale': Tool.mscale, 'stretch': Tool.mstretch, 'moffset': Tool.moffset,
  };

  Widget _modCol(List<String> keys, List<String> labels, {double leftPad = 8}) {
    return Padding(
      padding: EdgeInsets.only(left: leftPad),
      child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < keys.length; i++) ...[
              if (i > 0) const SizedBox(height: 2),
              _SmallRow(
                  icon: MD[keys[i]]!,
                  label: labels[i],
                  onTap: _modToolOf[keys[i]] == null
                      ? null
                      : () => _startTool(_modToolOf[keys[i]]!),
                  active: widget.app.tool == _modToolOf[keys[i]]),
            ]
          ]),
    );
  }

  Widget _panel(
      {required String label,
      required bool arrow,
      required Widget child,
      bool first = false,
      String? overId,
      List<OverItem> Function()? over}) {
    // The ▼ next to the title is the ONLY way to the overflow commands, so it
    // has to be a real hit target — the label goes with it (Inventor's panel
    // expander behaves the same).
    Widget title = Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(label, style: ts(12, T.dim)),
      if (arrow || over != null) ...[
        const SizedBox(width: 6),
        Text('▼', style: ts(8, T.dim)),
      ],
    ]);
    if (over != null && overId != null) {
      title = Builder(
        builder: (ctx) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => toggleOver(overId, ctx, over()),
          child: title,
        ),
      );
    }
    return Container(
      decoration: first
          ? null
          : const BoxDecoration(
              border: Border(left: BorderSide(color: T.panelSep, width: 1))),
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
              child: child,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 3, bottom: 5),
            child: title,
          ),
        ],
      ),
    );
  }
}

// ---- building blocks matching .big / .bigwide / .smallrow / grids ----

class _Hover extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color hoverBg;
  final bool hoverBorder;
  final bool activeHighlight; // Inventor-style: active tool stays lit
  const _Hover(
      {required this.child,
      this.onTap,
      this.hoverBg = T.hover6,
      this.hoverBorder = true,
      this.activeHighlight = false});
  @override
  State<_Hover> createState() => _HoverState();
}

class _HoverState extends State<_Hover> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    final act = widget.activeHighlight;
    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: GestureDetector(
        // THE tap target of every ribbon button. Without an explicit behavior a
        // GestureDetector is deferToChild, and the child here is a Container
        // with a *decoration* — that is a DecoratedBox, and a DecoratedBox
        // never absorbs a hit test (unlike Container(color:), which compiles to
        // a ColoredBox and does). So only the glyphs inside ever answered a
        // tap: the Text label of a big Create button worked, while every
        // icon-only cell — the whole Constrain and Modify grid, drawn by
        // flutter_svg into a plain RenderBox that reports no hit — was
        // completely dead. Opaque = the entire button box is the target, which
        // is the only thing that makes sense for a finger on a ribbon button.
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          decoration: BoxDecoration(
            color: act
                ? const Color(0xFF3A4149)
                : (_h ? widget.hoverBg : Colors.transparent),
            borderRadius: BorderRadius.circular(2),
            border: Border.all(
                color: act
                    ? const Color(0xFF5A88B5)
                    : (_h && widget.hoverBorder
                        ? T.border10
                        : Colors.transparent)),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class _Big extends StatelessWidget {
  final String? id;
  final String label;
  final String icon;
  final void Function(String, BuildContext)? onFly;
  final bool showDd;
  final bool active;
  final VoidCallback? onDefault; // button body = default tool (Inventor)
  const _Big({this.id, required this.label, required this.icon, this.onFly,
      this.active = false, this.onDefault})
      : showDd = true;
  const _Big.plain({required this.label, required this.icon})
      : id = null,
        onFly = null,
        showDd = false,
        active = false,
        onDefault = null;

  @override
  Widget build(BuildContext context) {
    return Builder(builder: (ctx) {
      return SizedBox(
        width: 62,
        child: _Hover(
          activeHighlight: active,
          onTap: onDefault ??
              (id != null && onFly != null ? () => onFly!(id!, ctx) : null),
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              svg(icon, 34),
              const SizedBox(height: 3),
              Text(label, style: ts(11.5, T.text)),
              if (showDd) ...[
                const SizedBox(height: 1),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: id != null && onFly != null
                      ? () => onFly!(id!, ctx)
                      : null,
                  child: SizedBox(
                    width: 40,
                    height: 14,
                    child: Center(child: Text('▼', style: ts(7.5, T.dim))),
                  ),
                ),
              ],
            ]),
          ),
        ),
      );
    });
  }
}

class _BigWide extends StatelessWidget {
  final double width;
  final String icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;
  const _BigWide(
      {required this.width,
      required this.icon,
      required this.label,
      this.onTap,
      this.active = false});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: _Hover(
        onTap: onTap,
        activeHighlight: active,
        child: Stack(children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 4),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Center(child: svg(icon, 34)),
              const SizedBox(height: 3),
              Text(label,
                  textAlign: TextAlign.center,
                  style: ts(11.5, T.text, height: 1.15)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _SmallRow extends StatelessWidget {
  final String icon;
  final String label;
  final String? flyId;
  final void Function(String, BuildContext)? onFly;
  final VoidCallback? onTap;
  final bool active;

  /// Replaces the SVG when the glyph is not an icon — Parameters uses
  /// Inventor's italic "fx", which is type, not artwork.
  final Widget? iconWidget;
  const _SmallRow(
      {required this.icon, required this.label, this.flyId, this.onFly,
      this.onTap, this.active = false, this.iconWidget});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 26,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _Hover(
          hoverBorder: false,
          activeHighlight: active,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                  width: 18,
                  height: 18,
                  child: Center(child: iconWidget ?? svg(icon, 18))),
              const SizedBox(width: 6),
              Text(label, style: ts(12.5, T.text)),
            ]),
          ),
        ),
        Builder(builder: (ctx) {
          if (flyId == null) {
            return const SizedBox(
                width: 14,
                child: Opacity(opacity: 0, child: Text('▼'))); // visibility:hidden
          }
          return SizedBox(
            width: 14,
            height: 26,
            child: _Hover(
              hoverBg: T.hover8,
              hoverBorder: false,
              onTap: () => onFly!(flyId!, ctx),
              child: Center(child: Text('▼', style: ts(7.5, T.dim))),
            ),
          );
        }),
      ]),
    );
  }
}

class _BigPlainBody extends StatelessWidget {
  final String label;
  const _BigPlainBody({required this.label});
  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      svg(CN['dim']!, 34),
      const SizedBox(height: 3),
      Text(label, style: ts(11.5, T.text)),
    ]);
  }
}

class _ConGrid extends StatelessWidget {
  final AppState app;
  final void Function(Tool) onTool;
  const _ConGrid({required this.app, required this.onTool});

  /// Maps constraint grid keys to their tools (autodim/showcons/conset are
  /// toggles/settings, not tools, and are handled before this lookup).
  static const _toolOf = <String, Tool>{
    'coincident': Tool.cCoincident,
    'collinear': Tool.cCollinear,
    'concentric': Tool.cConcentric,
    'lock': Tool.cFix,
    'parallel': Tool.cParallel,
    'perp': Tool.cPerpendicular,
    'horiz': Tool.cHorizontal,
    'vert': Tool.cVertical,
    'tangent': Tool.cTangent,
    'smooth': Tool.cSmooth,
    'symmetric': Tool.cSymmetric,
    'equal': Tool.cEqual,
  };

  /// The grid holds only the constraints worth permanent ribbon width.
  /// Smooth / Constraint Settings / Show Constraints live behind the panel
  /// title's ▼ (see the Constrain panel). 11 cells over 4 columns = 3 rows,
  /// which is both shorter and NARROWER than the old 5-column grid.
  static const cons = [
    ('coincident', 'Coincident'),
    ('collinear', 'Collinear'),
    ('concentric', 'Concentric'),
    ('lock', 'Lock'),
    ('parallel', 'Parallel'),
    ('perp', 'Perpendicular'),
    ('horiz', 'Horizontal'),
    ('vert', 'Vertical'),
    ('tangent', 'Tangent'),
    ('symmetric', 'Symmetric'),
    ('equal', 'Equal'),
  ];
  bool _isActive(String key) {
    if (key == 'autodim') return app.autoConstrain;
    if (key == 'showcons') return app.showConstraints;
    if (key == 'conset') return app.showDof;
    final t = _toolOf[key];
    return t != null && app.tool == t;
  }

  void _tap(String key) {
    if (key == 'autodim') {
      app.toggleAutoConstrain();
      return;
    }
    if (key == 'showcons') {
      app.toggleShowConstraints();
      return;
    }
    if (key == 'conset') {
      app.toggleShowDof(); // Inventor: View > Degrees of Freedom
      return;
    }
    final t = _toolOf[key];
    if (t != null) onTool(t);
  }

  static const _cols = 4;

  Widget _cell((String, String) c) => Tooltip(
        message: c.$2,
        child: SizedBox(
          width: 30,
          height: 27,
          child: _Hover(
              hoverBg: T.hover7,
              activeHighlight: _isActive(c.$1),
              onTap: () => _tap(c.$1),
              child: Center(child: svg(CN[c.$1]!, 18))),
        ),
      );

  @override
  Widget build(BuildContext context) {
    // The row count is DERIVED from `cons` and every cell is bounds-checked.
    // (A hard-coded 3x5 grid survived the removal of the 'autodim' cell in
    // M10c: cons went 15 -> 14, cons[14] threw RangeError on every build, the
    // ErrorWidget expanded to the full viewport height and pushed the model
    // browser, the viewport and the tab bar off screen. Never index a fixed
    // grid into a variable-length list again.)
    final rows = (cons.length + _cols - 1) ~/ _cols;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var row = 0; row < rows; row++)
          Padding(
            padding: EdgeInsets.only(top: row == 0 ? 0 : 1),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (var col = 0; col < _cols; col++)
                Padding(
                  padding: EdgeInsets.only(left: col == 0 ? 0 : 1),
                  child: (row * _cols + col) < cons.length
                      ? _cell(cons[row * _cols + col])
                      : const SizedBox(width: 30, height: 27),
                ),
            ]),
          ),
      ],
    );
  }
}

class _OverMenu extends StatelessWidget {
  final List<OverItem> items;
  final void Function(OverItem) onPick;
  const _OverMenu({required this.items, required this.onPick});
  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 170, maxWidth: 280),
        child: IntrinsicWidth(
          child: ColoredBox(
            color: T.fly,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: T.fly,
                border: Border.all(color: T.sep),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < items.length; i++)
                    _OverRow(
                        item: items[i], last: i == items.length - 1,
                        onPick: onPick),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OverRow extends StatefulWidget {
  final OverItem item;
  final bool last;
  final void Function(OverItem) onPick;
  const _OverRow(
      {required this.item, required this.last, required this.onPick});
  @override
  State<_OverRow> createState() => _OverRowState();
}

class _OverRowState extends State<_OverRow> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: GestureDetector(
        // opaque, or only the label text would be tappable (see _FlyRow)
        behavior: HitTestBehavior.opaque,
        onTap: it.onTap == null ? null : () => widget.onPick(it),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 7, 14, 7),
          decoration: BoxDecoration(
            color: (_h || it.active) ? T.flyHov : T.fly,
            border: widget.last
                ? null
                : const Border(bottom: BorderSide(color: Color(0x08FFFFFF))),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            svg(it.icon, 18),
            const SizedBox(width: 10),
            Text(it.label,
                style: ts(12.5, it.onTap == null ? T.dim : T.text,
                    height: 1.25)),
          ]),
        ),
      ),
    );
  }
}

class _FlyMenu extends StatelessWidget {
  final List<FlyItem> items;
  final void Function(FlyItem) onPick;
  const _FlyMenu({required this.items, required this.onPick});
  @override
  Widget build(BuildContext context) {
    // WHY THE MENU WAS SEE-THROUGH (and why removing the BoxShadow in M7 did
    // not help): this is a LAYOUT bug, not a paint bug. A Positioned(left/top)
    // child of a Stack is laid out with UNBOUNDED constraints, and
    // CrossAxisAlignment.stretch on a Column means
    // `BoxConstraints.tightFor(width: constraints.maxWidth)` — i.e.
    // tightFor(width: INFINITY). Every row, and the menu itself, ended up with
    // a non-finite width. `BoxConstraints(minWidth: 186)` sets a floor, never a
    // ceiling, so nothing caught it. In a debug build that throws ("was given
    // an infinite size during layout"); in the RELEASE ipa asserts are off, so
    // the size stays infinite, Impeller drops the non-finite drawRect — the
    // fill — and paints only the finite glyphs. Result: icons and labels
    // floating over the sketch with no panel behind them.
    //
    // The fix is to give the menu a finite width: a hard ceiling
    // (ConstrainedBox) plus IntrinsicWidth so it still hugs its widest row from
    // 186px up, exactly like the mock. NEVER let a menu inherit the Stack's
    // unbounded constraints again.
    return Material(
      // Transparent: paints nothing, only provides the text-style scope.
      type: MaterialType.transparency,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 186, maxWidth: 320),
        child: IntrinsicWidth(
          child: ColoredBox(
            // Opaque fill, and hit-opaque: a tap on the menu can never fall
            // through to the dismiss barrier behind it.
            color: T.fly,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: T.fly,
                border: Border.all(color: T.sep),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < items.length; i++)
                    _FlyRow(
                        item: items[i],
                        first: i == 0,
                        last: i == items.length - 1,
                        onPick: onPick),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FlyRow extends StatefulWidget {
  final FlyItem item;
  final bool first, last;
  final void Function(FlyItem) onPick;
  const _FlyRow(
      {required this.item,
      required this.first,
      required this.last,
      required this.onPick});
  @override
  State<_FlyRow> createState() => _FlyRowState();
}

class _FlyRowState extends State<_FlyRow> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final oneline = it.sub.isEmpty;
    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: GestureDetector(
        // Same deferToChild trap as _Hover, and it is what made the flyout
        // tools unusable: the row's Container is a DecoratedBox, so a tap only
        // landed if it hit the label text exactly. Anywhere else in the row —
        // the icon, the padding, the gap — hit the menu's ColoredBox, which IS
        // hit-opaque, so the tap was swallowed and NOTHING happened: the menu
        // just sat there. Opaque = the whole row picks the tool.
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onPick(it),
        child: Container(
          padding: oneline
              ? const EdgeInsets.fromLTRB(10, 8, 14, 8)
              : const EdgeInsets.fromLTRB(10, 7, 14, 7),
          decoration: BoxDecoration(
            color: (_h || widget.first) ? T.flyHov : T.fly,
            border: widget.last
                ? null
                : const Border(
                    bottom: BorderSide(color: Color(0x08FFFFFF))),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            svg(IC[it.icon]!, 26),
            const SizedBox(width: 10),
            Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(it.b,
                      style: oneline
                          ? ts(12.5, T.text, height: 1.25)
                          : ts(12.5, Colors.white,
                              w: FontWeight.w600, height: 1.25)),
                  if (!oneline)
                    Text(it.sub, style: ts(12, T.dim, height: 1.25)),
                ]),
          ]),
        ),
      ),
    );
  }
}
