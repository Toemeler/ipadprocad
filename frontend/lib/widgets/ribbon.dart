// iPadProCAD — ribbon, 1:1 port of the mock's #ribbon.
// Panel order (binding): Layer, Create, Project Geometry, Pattern, Constrain,
// Insert, Format, Modify (last). Exit panel appears top-right in edit mode.
// Home view: all panels hidden except the single "Create New Sketch" panel.
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../app_state.dart';
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

  /// Starts a tool; asks for parameters first where Inventor would
  /// (polygon sides, fillet radius, chamfer distance, equation + range).
  Future<void> _startTool(Tool t) async {
    final app = widget.app;
    switch (t) {
      case Tool.polygon:
        final v = await _numDialog('Polygon', [('Sides', '6')]);
        if (v == null) return;
        app.toolParams = {'sides': v[0]};
        break;
      case Tool.fillet:
        final v = await _numDialog('Fillet', [('Radius', '5')]);
        if (v == null) return;
        app.toolParams = {'radius': v[0]};
        break;
      case Tool.chamfer:
        final v = await _numDialog('Chamfer', [('Distance', '5')]);
        if (v == null) return;
        app.toolParams = {'dist': v[0]};
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
              cornerDd: true,
              onTap: app.startNewLayer),
        ),
        // 2. Create
        _panel(
          label: 'Create',
          arrow: true,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _Big(id: 'line', label: 'Line', icon: IC['line34']!, onFly: toggleFly,
                active: _toolGroup[app.tool] == 'line'),
            _Big(id: 'circle', label: 'Circle', icon: IC['circle34']!, onFly: toggleFly,
                active: _toolGroup[app.tool] == 'circle'),
            _Big(id: 'arc', label: 'Arc', icon: IC['arc34']!, onFly: toggleFly,
                active: _toolGroup[app.tool] == 'arc'),
            _Big(id: 'rect', label: 'Rectangle', icon: IC['rect34']!, onFly: toggleFly,
                active: _toolGroup[app.tool] == 'rect'),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SmallRow(icon: IC['fillet18']!, label: 'Fillet', flyId: 'fillet', onFly: toggleFly,
                        active: _toolGroup[app.tool] == 'fillet'),
                    const SizedBox(height: 2),
                    _SmallRow(icon: IC['text18']!, label: 'Text', flyId: 'text', onFly: toggleFly),
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
          child: _BigWide(width: 76, icon: IC['projgeo']!, label: 'Project\nGeometry'),
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
                  _SmallRow(icon: IC['patrect']!, label: 'Rectangular'),
                  const SizedBox(height: 2),
                  _SmallRow(icon: IC['patcirc']!, label: 'Circular'),
                  const SizedBox(height: 2),
                  _SmallRow(icon: IC['patmir']!, label: 'Mirror'),
                ]),
          ),
        ),
        // 5. Constrain
        _panel(
          label: 'Constrain',
          arrow: true,
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
        // 6. Insert
        _panel(
          label: 'Insert',
          arrow: false,
          child: Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SmallRow(icon: IN['image']!, label: 'Image'),
                  const SizedBox(height: 2),
                  _SmallRow(icon: IN['points']!, label: 'Points'),
                  const SizedBox(height: 2),
                  _SmallRow(icon: IN['acad']!, label: 'ACAD'),
                ]),
          ),
        ),
        // 7. Format
        _panel(label: 'Format', arrow: true, child: _FormatGrid()),
        // 8. Modify (LAST block)
        _panel(
          label: 'Modify',
          arrow: false,
          child: Row(children: [
            _modCol(['move', 'copy', 'mrotate'], ['Move', 'Copy', 'Rotate'], leftPad: 2),
            _modCol(['trim', 'extend', 'split'], ['Trim', 'Extend', 'Split']),
            _modCol(['mscale', 'stretch', 'moffset'], ['Scale', 'Stretch', 'Offset']),
          ]),
        ),
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
                cornerDdBelow: true,
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
      bool first = false}) {
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
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(label, style: ts(12, T.dim)),
              if (arrow) ...[
                const SizedBox(width: 6),
                Text('▼', style: ts(8, T.dim)),
              ],
            ]),
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
  const _Big({this.id, required this.label, required this.icon, this.onFly,
      this.active = false})
      : showDd = true;
  const _Big.plain({required this.label, required this.icon})
      : id = null,
        onFly = null,
        showDd = false,
        active = false;

  @override
  Widget build(BuildContext context) {
    return Builder(builder: (ctx) {
      return SizedBox(
        width: 62,
        child: _Hover(
          activeHighlight: active,
          onTap: id != null && onFly != null ? () => onFly!(id!, ctx) : null,
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              svg(icon, 34),
              const SizedBox(height: 3),
              Text(label, style: ts(11.5, T.text)),
              if (showDd) ...[
                const SizedBox(height: 3),
                Text('▼', style: ts(7.5, T.dim)),
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
  final bool cornerDd;
  final bool cornerDdBelow;
  final VoidCallback? onTap;
  const _BigWide(
      {required this.width,
      required this.icon,
      required this.label,
      this.cornerDd = false,
      this.cornerDdBelow = false,
      this.onTap});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: _Hover(
        onTap: onTap,
        child: Stack(children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 4),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Center(child: svg(icon, 34)),
              const SizedBox(height: 3),
              Text(label,
                  textAlign: TextAlign.center,
                  style: ts(11.5, T.text, height: 1.15)),
              if (cornerDdBelow) ...[
                const SizedBox(height: 1),
                Text('▼', style: ts(7.5, T.dim)),
              ],
            ]),
          ),
          if (cornerDd)
            Positioned(
                right: 3, bottom: 3, child: Text('▼', style: ts(7.5, T.dim))),
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
  const _SmallRow(
      {required this.icon, required this.label, this.flyId, this.onFly,
      this.onTap, this.active = false});
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
              svg(icon, 18),
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

  static const cons = [
    ('autodim', 'Automatic Dimensions and Constraints'),
    ('coincident', 'Coincident'),
    ('collinear', 'Collinear'),
    ('concentric', 'Concentric'),
    ('lock', 'Lock'),
    ('showcons', 'Show Constraints'),
    ('parallel', 'Parallel'),
    ('perp', 'Perpendicular'),
    ('horiz', 'Horizontal'),
    ('vert', 'Vertical'),
    ('conset', 'Constraint Settings'),
    ('tangent', 'Tangent'),
    ('smooth', 'Smooth (G2)'),
    ('symmetric', 'Symmetric'),
    ('equal', 'Equal'),
  ];
  bool _isActive(String key) {
    if (key == 'autodim') return app.autoConstrain;
    if (key == 'showcons') return app.showConstraints;
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
    if (key == 'conset') return; // settings dialog: later milestone
    final t = _toolOf[key];
    if (t != null) onTool(t);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var row = 0; row < 3; row++)
          Padding(
            padding: EdgeInsets.only(top: row == 0 ? 0 : 1),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (var col = 0; col < 5; col++)
                Padding(
                  padding: EdgeInsets.only(left: col == 0 ? 0 : 1),
                  child: Tooltip(
                    message: cons[row * 5 + col].$2,
                    child: SizedBox(
                      width: 30,
                      height: 27,
                      child: _Hover(
                          hoverBg: T.hover7,
                          activeHighlight: _isActive(cons[row * 5 + col].$1),
                          onTap: () => _tap(cons[row * 5 + col].$1),
                          child: Center(
                              child: svg(CN[cons[row * 5 + col].$1]!, 18))),
                    ),
                  ),
                ),
            ]),
          ),
      ],
    );
  }
}

class _FormatGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // row 1: Driven Dimension (colspan 2)
          Tooltip(
            message: 'Driven Dimension',
            child: SizedBox(
                width: 65,
                height: 27,
                child: _Hover(
                    hoverBg: T.hover7,
                    child: Center(child: svg(IN['driven']!, 18)))),
          ),
          const SizedBox(height: 1),
          // row 2: sphere + crosshair (crosshair ACTIVE, blue frame)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Tooltip(
              message: 'Sketch Only',
              child: SizedBox(
                  width: 32,
                  height: 27,
                  child: _Hover(
                      hoverBg: T.hover7,
                      child: Center(child: svg(IN['sphere']!, 18)))),
            ),
            const SizedBox(width: 1),
            Tooltip(
              message: 'Center Point',
              child: Container(
                width: 32,
                height: 27,
                decoration: BoxDecoration(
                  color: T.conActiveBg,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: T.conActiveBorder),
                ),
                child: Center(child: svg(IN['center']!, 18)),
              ),
            ),
          ]),
          const SizedBox(height: 1),
          // row 3: Show Format (colspan 2, must not overflow)
          Tooltip(
            message: 'Show Format',
            child: _Hover(
              hoverBg: T.hover7,
              hoverBorder: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: SizedBox(
                  height: 25,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    svg(IN['showfmt']!, 18),
                    const SizedBox(width: 6),
                    Text('Show Format',
                        style: ts(12.5, T.text), softWrap: false),
                  ]),
                ),
              ),
            ),
          ),
        ],
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
    // Rendered with the most primitive paints available (ColoredBox, no
    // BoxShadow): the drop shadow's saveLayer rendered the menu see-through
    // on the iPadOS beta (Impeller), so the shadow is gone for now.
    return Material(
      type: MaterialType.transparency,
      child: ClipRect(
        child: ColoredBox(
          color: T.fly,
          child: Container(
            constraints: const BoxConstraints(minWidth: 186),
            decoration: BoxDecoration(
              border: Border.all(color: T.sep),
            ),
            child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items.length; i++)
              _FlyRow(item: items[i], first: i == 0, last: i == items.length - 1, onPick: onPick),
          ],
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
