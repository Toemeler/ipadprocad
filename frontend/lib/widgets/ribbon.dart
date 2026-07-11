// iPadProCAD — ribbon, 1:1 port of the mock's #ribbon.
// Panel order (binding): Layer, Create, Project Geometry, Pattern, Constrain,
// Insert, Format, Modify (last). Exit panel appears top-right in edit mode.
// Home view: all panels hidden except the single "Create New Sketch" panel.
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../app_state.dart';
import '../svg_icons.dart';
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
    FlyItem('fmidline', 'Line', 'Midpoint Line'),
    FlyItem('fsplinecv', 'Spline', 'Control Vertex'),
    FlyItem('fsplinei', 'Spline', 'Interpolation'),
    FlyItem('feqcurve', 'Equation Curve', 'Equation Curve'),
    FlyItem('fbridge', 'Bridge Curve', 'Bridge Curve'),
  ],
  'circle': [
    FlyItem('fcirclecp', 'Circle', 'Center Point', Tool.circleCenter),
    FlyItem('fcircletan', 'Circle', 'Tangent'),
    FlyItem('fellipse', 'Ellipse', 'Ellipse'),
  ],
  'arc': [
    FlyItem('farc3', 'Arc', 'Three Point', Tool.arcThreePoint),
    FlyItem('farctan', 'Arc', 'Tangent'),
    FlyItem('farccp', 'Arc', 'Center Point'),
  ],
  'rect': [
    FlyItem('frect2p', 'Rectangle', 'Two Point', Tool.rectTwoPoint),
    FlyItem('frect3p', 'Rectangle', 'Three Point'),
    FlyItem('frect2pc', 'Rectangle', 'Two Point Center'),
    FlyItem('frect3pc', 'Rectangle', 'Three Point Center'),
    FlyItem('fslotcc', 'Slot', 'Center to Center'),
    FlyItem('fslotov', 'Slot', 'Overall'),
    FlyItem('fslotcp', 'Slot', 'Center Point'),
    FlyItem('fslot3a', 'Slot', 'Three Point Arc'),
    FlyItem('fslotcpa', 'Slot', 'Center Point Arc'),
    FlyItem('fpolygon', 'Polygon', 'Polygon'),
  ],
  'fillet': [
    FlyItem('ffillet', 'Fillet', ''),
    FlyItem('fchamfer', 'Chamfer', ''),
  ],
  'text': [
    FlyItem('ftext', 'Text', ''),
    FlyItem('fgtext', 'Geometry Text', ''),
  ],
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
              if (it.tool != null) widget.app.selectTool(it.tool!);
            },
          ),
        ),
      ]),
    );
    Overlay.of(context).insert(_fly!);
    setState(() => _flyId = id);
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
            _Big(id: 'line', label: 'Line', icon: IC['line34']!, onFly: toggleFly),
            _Big(id: 'circle', label: 'Circle', icon: IC['circle34']!, onFly: toggleFly),
            _Big(id: 'arc', label: 'Arc', icon: IC['arc34']!, onFly: toggleFly),
            _Big(id: 'rect', label: 'Rectangle', icon: IC['rect34']!, onFly: toggleFly),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SmallRow(icon: IC['fillet18']!, label: 'Fillet', flyId: 'fillet', onFly: toggleFly),
                    const SizedBox(height: 2),
                    _SmallRow(icon: IC['text18']!, label: 'Text', flyId: 'text', onFly: toggleFly),
                    const SizedBox(height: 2),
                    _SmallRow(icon: IC['point18']!, label: 'Point'),
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
              child: _Big.plain(label: 'Dimension', icon: CN['dim']!),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: _ConGrid(),
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

  Widget _modCol(List<String> keys, List<String> labels, {double leftPad = 8}) {
    return Padding(
      padding: EdgeInsets.only(left: leftPad),
      child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < keys.length; i++) ...[
              if (i > 0) const SizedBox(height: 2),
              _SmallRow(icon: MD[keys[i]]!, label: labels[i]),
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
  const _Hover(
      {required this.child,
      this.onTap,
      this.hoverBg = T.hover6,
      this.hoverBorder = true});
  @override
  State<_Hover> createState() => _HoverState();
}

class _HoverState extends State<_Hover> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          decoration: BoxDecoration(
            color: _h ? widget.hoverBg : Colors.transparent,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(
                color: _h && widget.hoverBorder ? T.border10 : Colors.transparent),
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
  const _Big({this.id, required this.label, required this.icon, this.onFly})
      : showDd = true;
  const _Big.plain({required this.label, required this.icon})
      : id = null,
        onFly = null,
        showDd = false;

  @override
  Widget build(BuildContext context) {
    return Builder(builder: (ctx) {
      return SizedBox(
        width: 62,
        child: _Hover(
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
  const _SmallRow(
      {required this.icon, required this.label, this.flyId, this.onFly});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 26,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _Hover(
          hoverBorder: false,
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

class _ConGrid extends StatelessWidget {
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
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(minWidth: 186),
        decoration: BoxDecoration(
          color: T.fly,
          border: Border.all(color: T.sep),
          boxShadow: const [
            BoxShadow(
                color: Color(0x8C000000), blurRadius: 22, offset: Offset(0, 8))
          ],
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
            color: (_h || widget.first) ? T.flyHov : Colors.transparent,
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
