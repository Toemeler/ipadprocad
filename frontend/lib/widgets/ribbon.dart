// Prototype — ribbon, 1:1 port of the mock's #ribbon.
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
import '../menus.dart';
import '../part_model.dart' show WorkPlaneKind;
import '../work_features.dart' show WorkAxisMethod, WorkPointMethod;
import '../svg_icons.dart';
import '../tools.dart';
import '../theme.dart';
import 'pattern_dialog.dart';
import 'ribbon_chrome.dart';
import 'scrub_field.dart';

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
    FlyItem('fsplinefree', 'Spline', 'Freehand', Tool.splineFree),
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
  // M213 — Work Features > Axis / Point. Every entry is REAL and every label
  // is Inventor's own wording, so a user who knows Inventor finds the method
  // they are looking for by name. `wa`/`wpt` prefixes keep the ids apart from
  // the plane list's.
  'axis': [
    FlyItem('waAuto', 'Axis', ''),
    FlyItem('waLine', 'On Line or Edge', ''),
    FlyItem('waParPt', 'Parallel to Line through Point', ''),
    FlyItem('wa2Pt', 'Through Two Points', ''),
    FlyItem('wa2Pl', 'Intersection of Two Planes', ''),
    FlyItem('waNormPt', 'Normal to Plane through Point', ''),
    FlyItem('waCirc', 'Through Center of Circular Edge', ''),
    FlyItem('waRev', 'Through Revolved Face or Feature', ''),
  ],
  'point': [
    FlyItem('wptAuto', 'Point', ''),
    FlyItem('wptGround', 'Grounded Point', ''),
    FlyItem('wptVertex', 'On Vertex, Sketch Point, or Midpoint', ''),
    FlyItem('wpt3Pl', 'Intersection of Three Planes', ''),
    FlyItem('wpt2Ln', 'Intersection of Two Lines', ''),
    FlyItem('wptPlLn', 'Intersection of Plane/Surface and Line', ''),
    FlyItem('wptLoop', 'Center Point of Loop of Edges', ''),
    FlyItem('wptTorus', 'Center Point of Torus', ''),
    FlyItem('wptSphere', 'Center Point of Sphere', ''),
  ],
  // M56 — Work Features > Plane (dummy items, real Inventor list)
  'plane': [
    FlyItem('plane', 'Plane', ''),
    FlyItem('offset', 'Offset from Plane', ''),
    FlyItem('parallelpt', 'Parallel to Plane through Point', ''),
    FlyItem('midplane2', 'Midplane between Two Planes', ''),
    FlyItem('midtorus', 'Midplane of Torus', ''),
    FlyItem('angleedge', 'Angle to Plane around Edge', ''),
    FlyItem('threepts', 'Three Points', ''),
    FlyItem('twoedges', 'Two Coplanar Edges', ''),
    FlyItem('tansurfedge', 'Tangent to Surface through Edge', ''),
    FlyItem('tansurfpt', 'Tangent to Surface through Point', ''),
    FlyItem('tanparallel', 'Tangent to Surface and Parallel to Plane', ''),
    FlyItem('normalaxis', 'Normal to Axis through Point', ''),
    FlyItem('normalcurve', 'Normal to Curve at Point', ''),
  ],
};

/// Group lookup for the active highlight. The table itself now lives in
/// app_state.dart as [toolFlyoutGroup], because AppState.selectTool needs it
/// to remember each split button's last variant (M85).
const _toolGroup = toolFlyoutGroup;

/// M85 — the FACE of a split button: the flyout variant it currently shows.
///
/// Inventor's split buttons are sticky: choose Slot from the Rectangle flyout
/// and the button becomes Slot — icon, label and what a tap on the body
/// starts — until you choose something else. It stays that way after the tool
/// finishes or is cancelled, which is the point.
///
/// [dflt] is the group's standard tool, with the hand-drawn 34-px icon and
/// short label the panel has always shown. While that is the pick, nothing
/// changes visually; a variant swaps in its own 26-px flyout icon (scaled to
/// 34) and the variant's name.
class _Face {
  final String icon, label;
  final Tool tool;
  const _Face(this.icon, this.label, this.tool);
}

_Face _faceFor(AppState app, String group,
    {required Tool dflt, required String icon, required String label}) {
  final pick = app.ribbonPick[group] ?? dflt;
  if (pick == dflt) return _Face(icon, label, dflt);
  for (final it in flyouts[group] ?? const <FlyItem>[]) {
    if (it.tool == pick) {
      return _Face(IC[it.icon] ?? icon, it.b, pick);
    }
  }
  return _Face(icon, label, dflt);
}

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
    OpenMenus.unregister(closeFly);
    _fly?.remove();
    _fly = null;
    _flyId = null;
  }

  /// M205 — the barrier behind every flyout. A raw pointer DOWN, not a tap:
  /// onTap has to win the gesture arena, so a trackpad click that jitters or a
  /// press that becomes a drag left the menu standing. Clicking anywhere else
  /// is a cancel, whatever the arena eventually decides that click was.
  Widget _barrier() => Positioned.fill(
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => closeFly(),
          child: const SizedBox.expand(),
        ),
      );

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
        _barrier(),
        Positioned(
          left: pos.dx,
          top: pos.dy + box.size.height + 1,
          child: _FlyMenu(
            items: items,
            onPick: (it) {
              closeFly();
              if (it.tool != null) {
                _startTool(it.tool!);
                return;
              }
              // M151 — the Work Features > Plane list has been dummy entries
              // since M56. Two of them are real.
              switch (it.icon) {
                // M157 — the generic "Plane" is Inventor's most-used entry and
                // fell through to nothing, as did a tap on the button BODY
                // (onDefault was an empty closure). Both now start the offset
                // flow, which is the plane you get in Inventor by picking one
                // face — the overwhelmingly common case.
                case 'plane':
                case 'offset':
                  widget.app.startWorkPlane(WorkPlaneKind.offset);
                  break;
                case 'midplane2':
                  widget.app.startWorkPlane(WorkPlaneKind.midplane);
                  break;
                // M213 — Work Axis.
                case 'waAuto':
                  widget.app.startWorkAxis(WorkAxisMethod.auto);
                  break;
                case 'waLine':
                  widget.app.startWorkAxis(WorkAxisMethod.onLineOrEdge);
                  break;
                case 'waParPt':
                  widget.app.startWorkAxis(
                      WorkAxisMethod.parallelToLineThroughPoint);
                  break;
                case 'wa2Pt':
                  widget.app.startWorkAxis(WorkAxisMethod.throughTwoPoints);
                  break;
                case 'wa2Pl':
                  widget.app
                      .startWorkAxis(WorkAxisMethod.intersectionOfTwoPlanes);
                  break;
                case 'waNormPt':
                  widget.app
                      .startWorkAxis(WorkAxisMethod.normalToPlaneThroughPoint);
                  break;
                case 'waCirc':
                  widget.app.startWorkAxis(
                      WorkAxisMethod.throughCenterOfCircularEdge);
                  break;
                case 'waRev':
                  widget.app
                      .startWorkAxis(WorkAxisMethod.throughRevolvedFace);
                  break;
                // M213 — Work Point.
                case 'wptAuto':
                  widget.app.startWorkPoint(WorkPointMethod.auto);
                  break;
                case 'wptGround':
                  widget.app.startWorkPoint(WorkPointMethod.grounded);
                  break;
                case 'wptVertex':
                  widget.app.startWorkPoint(WorkPointMethod.onVertex);
                  break;
                case 'wpt3Pl':
                  widget.app.startWorkPoint(
                      WorkPointMethod.intersectionOfThreePlanes);
                  break;
                case 'wpt2Ln':
                  widget.app
                      .startWorkPoint(WorkPointMethod.intersectionOfTwoLines);
                  break;
                case 'wptPlLn':
                  widget.app.startWorkPoint(
                      WorkPointMethod.intersectionOfPlaneAndLine);
                  break;
                case 'wptLoop':
                  widget.app.startWorkPoint(WorkPointMethod.centerOfLoop);
                  break;
                case 'wptTorus':
                  widget.app.startWorkPoint(WorkPointMethod.centerOfTorus);
                  break;
                case 'wptSphere':
                  widget.app.startWorkPoint(WorkPointMethod.centerOfSphere);
                  break;
                default:
                  // Silence is the worst answer: the user cannot tell a broken
                  // tool from an unbuilt one. Say which it is.
                  widget.app.toast('${it.b}: not built yet — '
                      'use Offset from Plane or Midplane.');
              }
            },
          ),
        ),
      ]),
    );
    Overlay.of(context).insert(_fly!);
    OpenMenus.register(closeFly);
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
        _barrier(),
        Positioned(
          left: pos.dx,
          // Downward, like every other ribbon flyout: the menu hangs BELOW the
          // title row and over the canvas. It used to open upward (the title
          // sits at the panel's bottom edge, so that felt symmetrical), but
          // upward means it climbs over the ribbon it belongs to and runs into
          // the iOS status bar. Down is also what the sibling _FlyMenu does.
          top: pos.dy + box.size.height + 1,
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
    OpenMenus.register(closeFly);
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

  /// M117 — in-sketch DXF import: merges into the OPEN sketch. Creating a new
  /// document from a file is the gallery's job (the "+" menu).
  Future<void> _pickDxfIntoSketch(AppState app) async {
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
    // M196 — a ribbon button TOGGLES. Tapping the tool that is already armed
    // puts it away, exactly as Esc would ("it should be deselected and not
    // used anymore. like canceling"). Before this, the second tap re-armed the
    // same tool and threw away any picks already made, which looks identical
    // to nothing happening — so the only way out of a tool with a finger was
    // the long press.
    //
    // FIRST, before the parameter dialogs below: cancelling a polygon must not
    // ask how many sides it should have on the way out.
    //
    // Exact tool only. Tapping a DIFFERENT variant from the same flyout
    // (Rectangle -> centre Rectangle) is a switch, not a cancel.
    if (app.tool == t) {
      // Esc's own semantics, twice: the first drops any pending picks (or
      // closes a modeless Pattern/Fillet/Gear window) and DELIBERATELY leaves
      // the command armed for the next chain (M53); the second puts it away.
      // A button press means "off", so it does both — but the second only
      // while the tool is still up, because a cancelTool() with no tool armed
      // clears the SELECTION, and putting a tool away must not cost the user
      // what they had selected.
      app.cancelTool();
      if (app.tool == t) app.cancelTool();
      return;
    }
    // Nothing may be drawn outside a layer's edit mode — bail BEFORE any
    // parameter dialog, so the user isn't asked for a radius and then refused.
    if (!app.inEditMode) {
      app.toast('Enter a layer to sketch: double-tap it in the model browser.');
      return;
    }
    switch (t) {
      case Tool.polygon:
        // M207 — no blocking prompt any more. The side count rides along in
        // the modeless Polygon window, exactly like the 2D Fillet radius: the
        // tool arms at once, and the value applies to the next polygon placed.
        // The old AlertDialog put a modal barrier under the number pad, which
        // is what "the small number input field doesn't work, it just closes
        // directly" was.
        app.toolParams = {
          'sides': (app.toolParams['sides'] ??
                  PolygonDialog.defaultSides.toDouble())
              .clamp(PolygonDialog.minSides.toDouble(),
                  PolygonDialog.maxSides.toDouble()),
        };
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
                child: ScrubField(
                    app: widget.app,
                    controller: x0,
                    child: TextField(
                        controller: x0,
                        stylusHandwritingEnabled: kValueHandwriting, // M179
                        style: ts(13, T.text),
                        decoration: InputDecoration(
                            labelText: 'x min', labelStyle: ts(12, T.dim))))),
            const SizedBox(width: 10),
            Expanded(
                child: ScrubField(
                    app: widget.app,
                    controller: x1,
                    child: TextField(
                        controller: x1,
                        stylusHandwritingEnabled: kValueHandwriting, // M179
                        style: ts(13, T.text),
                        decoration: InputDecoration(
                            labelText: 'x max', labelStyle: ts(12, T.dim))))),
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
    // M146 — the bar is a FLOATING glass card, not a bordered strip: padded
    // in from the edges with the model browser's own inset and corner radius,
    // with the viewport running behind and around it. The two blue borders are
    // gone; a lit edge on a floating card is a seam looking for a wall.
    final content = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      // The bar is only as wide as the screen and its panels routinely
      // overflow, so the scroll must never be disabled by a shrink-wrapped
      // parent. Explicit physics keeps the drag alive even when the content
      // happens to fit, which is what makes the ribbon feel like a strip
      // rather than a truncated row.
      physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics()),
      clipBehavior: Clip.hardEdge,
      child: app.isHome
          ? _homeRibbon(app)
          : (app.currentPart != null && app.activeChild == null
              ? _partRibbon(app)
              : _sketchRibbon(app)),
    );

    return RibbonMeasure(
      child: Padding(
        padding: RibbonMetrics.pad,
        child: Stack(
          children: [
            // The glass, sized to the card by the content below it.
            const Positioned.fill(child: RibbonSurface()),
            content,
          ],
        ),
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


  // ---- M56: the 3D part ribbon (Inventor's Part tab, ported from the
  // approved HTML dummy). Only Extrude is wired; the rest are the same
  // inert placeholders the dummy ships, so the layout is final while the
  // behaviour grows feature by feature.
  Widget _partRibbon(AppState app) {
    // M213 — [flyIds] maps a row's LABEL to a flyout id, so a small row can
    // carry the same drop chip the big split buttons have. _SmallRow has
    // supported flyId/onFly since M205; nothing in the part ribbon had ever
    // passed them, which is why Axis and Point could only ever have been
    // one-shot buttons with eight unreachable methods behind them.
    // M214 — the callback is NON-nullable, deliberately. Every row here used
    // to accept null and fall back to `?? () {}`, which is how nine dead
    // buttons sat in this ribbon looking finished. An unbuilt command now
    // cannot be put in a visible column at all: it goes in the panel's `over`
    // list, where _OverRow renders it dimmed and untappable. The rule is a
    // type, not a convention somebody has to remember.
    Widget col(List<(String, String, VoidCallback)> rows,
            {double leftPad = 8, Map<String, String> flyIds = const {}}) =>
        Padding(
          padding: EdgeInsets.only(left: leftPad),
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) const SizedBox(height: 2),
                  _SmallRow(
                      icon: rows[i].$1,
                      label: rows[i].$2,
                      flyId: flyIds[rows[i].$2],
                      onFly: flyIds[rows[i].$2] == null ? null : toggleFly,
                      onTap: rows[i].$3),
                ]
              ]),
        );
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _panel(
          label: 'Sketch',
          arrow: false,
          first: true,
          child: _BigWide(
              width: 70,
              icon: newSketchIcon,
              label: 'Start\n2D Sketch',
              onTap: app.startPartSketch,
              active: app.pickPlane),
        ),
        // M214 — the part ribbon shows what is BUILT; everything else is one
        // tap away behind the panel title's ▼.
        //
        // Same treatment the sketch ribbon has had since M50 (Constrain) and
        // the Insert+Format+Manage merge, and the same rule M157 stated for
        // the Plane button: a control that is visible must do something,
        // because silence reads as broken. Nine of Modify's twelve entries,
        // three of Create's six and all four Pattern commands did nothing at
        // all, so two thirds of the 3D ribbon was furniture — and furniture
        // that costs permanent width AND makes the working tools harder to
        // find among it.
        //
        // NOT deleted: an unbuilt OverItem passes a null onTap, which _OverRow
        // already renders dimmed and untappable. The roadmap stays visible and
        // honest instead of the ribbon quietly pretending these commands were
        // never planned.
        _panel(
          label: 'Create',
          arrow: false,
          overId: 'ov-create3d',
          over: () => [
            OverItem(CR['emboss']!, 'Emboss', null),
            OverItem(CR['derive']!, 'Derive', null),
            OverItem(CR['decal']!, 'Decal', null),
          ],
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _BigWide(
                width: 58,
                icon: CR['extrude']!,
                label: 'Extrude',
                onTap: () => app.openExtrude(),
                // M210 — the highlight names THIS command, not "some panel is
                // open": it toggles now, and a button that lights for a
                // revolve would toggle the wrong thing off.
                active: app.extrudeSession?.kind == 'extrude'),
            _BigWide(
                width: 58,
                icon: CR['revolve']!,
                label: 'Revolve',
                onTap: () => app.openRevolve(),
                active: app.extrudeSession?.isRevolve == true),
            col([
              (CR['sweep']!, 'Sweep', () => app.openSweep()),
              (CR['loft']!, 'Loft', () => app.openLoft()),
              (CR['coil']!, 'Coil', () => app.openCoil()),
            ]),
          ]),
        ),
        // Modify ALSO carries the Pattern commands, because Pattern had no
        // built entry at all and a panel that is nothing but a title and a ▼
        // is worse than a slightly longer list. Pattern operations are
        // modifications of an existing body, so they read fine here. The
        // moment one of them is built, Pattern gets its panel back.
        //
        // Hole is in the list too: its onTap was `() {}` — an empty closure,
        // the exact thing M157 called out on the Plane button. A big button
        // that silently does nothing is the most expensive kind of lie in a
        // ribbon, because it looks the most finished.
        _panel(
          label: 'Modify',
          arrow: false,
          overId: 'ov-modify3d',
          over: () => [
            OverItem(MO['hole']!, 'Hole', null),
            OverItem(MO['shell']!, 'Shell', null),
            OverItem(MO['draft']!, 'Draft', null),
            OverItem(MO['thread']!, 'Thread', null),
            OverItem(MO['combine']!, 'Combine', null),
            OverItem(MO['thicken']!, 'Thicken / Offset', null),
            OverItem(MO['split']!, 'Split', null),
            OverItem(MO['direct']!, 'Direct', null),
            OverItem(MO['deleteface']!, 'Delete Face', null),
            OverItem(PT['rect']!, 'Rectangular Pattern', null),
            OverItem(PT['circ']!, 'Circular Pattern', null),
            OverItem(PT['sketch']!, 'Sketch Driven Pattern', null),
            OverItem(PT['mirror']!, 'Mirror', null),
          ],
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _BigWide(
                width: 58,
                icon: MO['fillet']!,
                label: 'Fillet',
                onTap: () => app.openFillet(),
                active: app.edgeSession?.isFillet == true),
            col([
              (MO['chamfer']!, 'Chamfer', () => app.openChamfer()),
            ]),
          ]),
        ),
        _panel(
          label: 'Work Features',
          arrow: false,
          overId: 'ov-work3d',
          // UCS is deliberately still inert: it is a coordinate SYSTEM with
          // its own triad and placement gestures, not a third variant of Axis
          // and Point, and a button that half-works would be worse than one
          // that says it is not built (M157). Behind the ▼ it is listed,
          // dimmed and honest instead of sitting in the panel looking ready.
          over: () => [
            OverItem(WF['ucs']!, 'UCS', null),
          ],
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _Big(
                id: 'plane',
                label: 'Plane',
                icon: WF['plane']!,
                onFly: toggleFly,
                // M157 — was an empty closure, so tapping the button did
                // nothing at all and the tool looked broken.
                onDefault: () =>
                    widget.app.startWorkPlane(WorkPlaneKind.offset)),
            col([
              // M213 — the two that are built. Tapping the row runs the
              // LEGACY method (Inventor's plain "Axis" / "Point"), which is
              // the one people actually use: pick geometry and it works out
              // what you meant. The flyout carries the eight/nine named
              // methods for the cases where a pick is ambiguous.
              (
                WF['axis']!,
                'Axis',
                () => widget.app.startWorkAxis(WorkAxisMethod.auto)
              ),
              (
                WF['point']!,
                'Point',
                () => widget.app.startWorkPoint(WorkPointMethod.auto)
              ),
            ], flyIds: const {'Axis': 'axis', 'Point': 'point'}),
          ]),
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
            _BigSplit(app: app, id: 'line', dflt: Tool.line,
                icon: IC['line34']!, label: 'Line',
                onFly: toggleFly, onStart: _startTool),
            _BigSplit(app: app, id: 'circle', dflt: Tool.circleCenter,
                icon: IC['circle34']!, label: 'Circle',
                onFly: toggleFly, onStart: _startTool),
            _BigSplit(app: app, id: 'arc', dflt: Tool.arcThreePoint,
                icon: IC['arc34']!, label: 'Arc',
                onFly: toggleFly, onStart: _startTool),
            _BigSplit(app: app, id: 'rect', dflt: Tool.rectTwoPoint,
                icon: IC['rect34']!, label: 'Rectangle',
                onFly: toggleFly, onStart: _startTool),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Inventor split-button: tapping the BODY starts the
                    // CURRENT variant (M85 — Chamfer once chosen), the ▼ opens
                    // the flyout. Without the body tap only the 14-px arrow did
                    // anything and the Fillet button was dead on touch.
                    Builder(builder: (_) {
                      final f = _faceFor(app, 'fillet',
                          dflt: Tool.fillet,
                          icon: IC['fillet18']!,
                          label: 'Fillet');
                      return _SmallRow(
                          icon: f.icon,
                          label: f.label,
                          flyId: 'fillet',
                          onFly: toggleFly,
                          onTap: () => _startTool(f.tool),
                          active: _toolGroup[app.tool] == 'fillet');
                    }),
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
                      // M117 — Import moved to the gallery "+" menu; this
                      // button stays as the in-sketch DXF drop, which is a
                      // different job: it merges geometry into the sketch you
                      // already have open.
                      onTap: () => _pickDxfIntoSketch(app)),
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
            Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SmallRow(
                      icon: IN['gear']!,
                      label: 'Gear',
                      onTap: app.toggleGear,
                      active: app.gear != null),
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
        // M168 — VIEW panel, last before Exit: Inventor's Slice Graphics.
        // Shown only when there is actually a solid to cut through, which is
        // the same rule Inventor uses to grey it out. Not shown rather than
        // disabled, per M157: a visible button that does nothing reads as
        // broken, and this ribbon has had nine of those.
        if (app.canSliceGraphics)
          _panel(
            label: 'View',
            arrow: false,
            child: _BigWide(
                width: 74,
                icon: WF['plane']!,
                label: 'Slice\nGraphics',
                active: app.sliceGraphics,
                onTap: app.toggleSliceGraphics),
          ),
        // Exit panel (only in layer edit mode), pinned to the right in spirit;
        // in a scrolling ribbon it follows Modify like #panel-exit.on does.
        if (app.inEditMode || app.activeChild != null)
          _panel(
            label: 'Exit',
            arrow: false,
            child: _BigWide(
                width: 64,
                icon: finishIcon,
                label: app.activeChild != null ? 'Finish\nSketch' : 'Finish',
                onTap: () => app.activeChild != null
                    ? app.finishPartSketch()
                    : app.finishEdit()),
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
    //
    // FALLE (M50 shipped this and it crashed every frame): the inner widget
    // MUST be captured in its own final. Writing
    //     Widget title = Row(...);
    //     title = Builder(builder: (_) => GestureDetector(child: title));
    // does not do what it reads like — a Dart closure captures the VARIABLE,
    // not the value it held at the time. By the time the builder runs, `title`
    // points at the Builder itself, so every build inflates
    // Builder -> GestureDetector -> Builder -> ... until the stack blows.
    // Symptoms on the device: the three panel titles never rendered (no ▼ at
    // all) and the whole frame pipeline died in exception handling, which read
    // as broken pan/zoom. Never let a widget-valued variable be reassigned to
    // something that closes over itself.
    final titleRow = Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(label, style: ts(12, T.dim)),
      if (arrow || over != null) ...[
        const SizedBox(width: 6),
        Text('▼', style: ts(8, T.dim)),
      ],
    ]);
    final Widget title = (over != null && overId != null)
        ? Builder(
            builder: (ctx) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => toggleOver(overId, ctx, over()),
              child: titleRow,
            ),
          )
        : titleRow;
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

/// M205 — the flyout opener, as a button you can SEE and HIT.
///
/// "The arrow to expand the list on rectangle or circle for example is really
/// small and difficult to hit with pencil or touch. Fix this and try to show
/// it more. Not just a tiny arrow, maybe a swift button or something i can
/// actually see is a button."
///
/// What it replaced was a 7.5-pixel ▼ glyph, dim grey on dark grey, inside an
/// invisible 40x14 box. Two separate faults in one control: nothing on screen
/// said "button", and 14 points of height is a third of Apple's floor for a
/// touch target — with a Pencil that is a coin toss, and a miss lands on the
/// button BODY, which starts the default tool instead of opening the list.
///
/// So it is a chip now: filled, outlined, rounded, with a real triangle in it,
/// and it reacts on press the way a UIKit control does. The chrome makes it
/// readable as a control; [tapHeight] is what makes it hittable — the visible
/// pill stays ribbon-sized while the TAP TARGET is padded out around it, so
/// the finger gets its slack without the ribbon growing to match.
///
/// On a split button that is 46 x 26 against the old 40 x 14: more than double
/// the area, and every point of it is now something the eye can aim at.
///
/// WHY THE SMALL ROWS DID NOT ALSO GET WIDER. Fillet, Text and their kind
/// carry the same opener in a 14-point column, and widening THAT costs ribbon
/// WIDTH — 16 points per column, six columns, 96 points. The sketch ribbon is
/// already 1681 points wide against a screen that is barely more than that, so
/// those 96 points come off the right-hand end, and the right-hand end is
/// Finish Sketch. They get the chrome — the pill, the drawn arrow, the press
/// state — and the full 26-point height of their row, at exactly their old
/// width. The thing the report actually named, the split buttons under
/// Rectangle and Circle, gets all of it.
class _DropChip extends StatefulWidget {
  final double width;
  final VoidCallback? onTap;

  /// Height of the touch target. The pill inside is [chipHeight]; the rest is
  /// transparent padding that still takes the hit. 26 because that is what a
  /// [_SmallRow] is tall, and the two chips must not be different sizes.
  static const double tapHeight = 26;

  /// A narrow chip cannot hold an 18-point glyph, and it has no vertical
  /// neighbour to keep clear of, so it uses its full row height instead.
  bool get _narrow => width < 24;
  double get chipHeight => _narrow ? 24 : 20;
  double get iconSize => _narrow ? 14 : 18;

  const _DropChip({required this.width, this.onTap});

  @override
  State<_DropChip> createState() => _DropChipState();
}

class _DropChipState extends State<_DropChip> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final lit = _down || _hover;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onTap,
        child: SizedBox(
          width: widget.width,
          height: _DropChip.tapHeight,
          child: Center(
            child: Container(
              width: widget.width,
              height: widget.chipHeight,
              decoration: BoxDecoration(
                color: _down ? T.hover8 : (lit ? T.hover7 : T.hover6),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: lit ? const Color(0x40FFFFFF) : T.border10),
              ),
              child: Center(
                child: Icon(Icons.arrow_drop_down,
                    size: widget.iconSize, color: lit ? T.text : T.dim),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A big Create-panel button that REMEMBERS its last flyout variant (M85).
///
/// Thin wrapper over [_Big]: it resolves the face through [_faceFor] and wires
/// the body tap to the variant currently shown, so the visible icon and what a
/// tap does can never disagree.
class _BigSplit extends StatelessWidget {
  final AppState app;
  final String id;
  final Tool dflt;
  final String icon, label;
  final void Function(String, BuildContext) onFly;
  final void Function(Tool) onStart;
  const _BigSplit({
    required this.app,
    required this.id,
    required this.dflt,
    required this.icon,
    required this.label,
    required this.onFly,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    final f = _faceFor(app, id, dflt: dflt, icon: icon, label: label);
    return _Big(
      id: id,
      label: f.label,
      icon: f.icon,
      onFly: onFly,
      onDefault: () => onStart(f.tool),
      active: _toolGroup[app.tool] == id,
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
              if (showDd)
                // No SizedBox gap: the chip carries its own transparent
                // padding, and stacking a gap on top of it only pushes the
                // ribbon taller for nothing.
                _DropChip(
                  width: 46,
                  onTap: id != null && onFly != null
                      ? () => onFly!(id!, ctx)
                      : null,
                ),
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

/// Width of the flyout chip in a [_SmallRow] (Fillet, Text, ...) — and of the
/// blank that keeps rows without one in line. UNCHANGED from the bare glyph it
/// replaced, on purpose: this column's width is ribbon width, and the ribbon
/// has none to give (see [_DropChip]).
const double _smallDropWidth = 14;

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
          // M205: same chip as the big split buttons — the 14-px column that
          // used to hold a 7.5-px glyph was the hardest target in the app. The
          // placeholder keeps the SAME width so rows without a flyout still
          // line up with the ones that have one.
          if (flyId == null) return const SizedBox(width: _smallDropWidth);
          return _DropChip(
            width: _smallDropWidth,
            onTap: () => onFly!(flyId!, ctx),
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
        constraints: const BoxConstraints(minWidth: 170, maxWidth: 320),
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
            // Flexible + ellipsis: the row must not be able to overflow its
            // menu no matter how wide the platform renders the label.
            Flexible(
              child: Text(it.label,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: ts(12.5, it.onTap == null ? T.dim : T.text,
                      height: 1.25)),
            ),
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
            svg(IC[it.icon] ?? PL[it.icon] ?? IC['line34']!, 26),
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
