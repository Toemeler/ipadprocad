// Prototype — ribbon, 1:1 port of the mock's #ribbon.
// Panel order (binding): Layer, Create, Project Geometry, Pattern, Constrain,
// Insert, Format, Modify (last). Exit panel appears top-right in edit mode.
// Home view: all panels hidden except the single "Create New Sketch" panel.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../icon_theme.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:native_menu/native_menu.dart' show NativeMenu, NativeMenuItem;

import '../app_state.dart';
import '../display_mode.dart';
import '../materials.dart';
import '../l10n/l.dart';
import '../log.dart';
import '../perf.dart';
import '../menus.dart';
import '../ribbon_dock.dart';
import '../section_view.dart';
import '../part_model.dart' show FaceEditKind, PatternKind, WorkPlaneKind;
import '../work_features.dart'
    show WorkAxisMethod, WorkPlaneMethod, WorkPointMethod;
import '../svg_icons.dart';
import '../tools.dart';
import '../theme.dart';
import 'pattern_dialog.dart';
import 'ribbon_chrome.dart';
import 'scrub_field.dart';

Widget svg(String s, double size) =>
    SvgPicture.string(themedIcon(s), width: size, height: size);

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

  /// M272 — a solid colour swatch INSTEAD of [icon], as 0xAARRGGBB.
  ///
  /// Only the appearance menu uses it, and it cannot go through [icon]: an SVG
  /// swatch would be re-mapped by `themedIcon`, which is exactly right for a
  /// glyph modelled in the palette's own hues and exactly wrong for a colour
  /// that IS the value being chosen.
  final int? tint;
  const OverItem(this.icon, this.label, this.onTap,
      {this.active = false, this.tint});
}

/// The flyout lists, in the current language.
///
/// Built per locale and cached, because this map is read from ribbon BUILD
/// methods: rebuilding a hundred-odd FlyItems on every frame of a drag would
/// be a real cost in an app whose ribbon build time is a tracked number. The
/// cache key is the [AppL10n] instance itself — Flutter hands out one per
/// loaded locale, so identity is exactly "the language did not change".
Map<String, List<FlyItem>> _flyCache = const <String, List<FlyItem>>{};
AppL10n? _flyCacheFor;

Map<String, List<FlyItem>> flyoutsOf(AppL10n t) {
  if (!identical(_flyCacheFor, t)) {
    _flyCacheFor = t;
    _flyCache = _buildFlyouts(t);
  }
  return _flyCache;
}

/// Tests only: drop the cache so the next read rebuilds in the new language.
@visibleForTesting
void resetFlyoutCacheForTest() {
  _flyCacheFor = null;
  _flyCache = const <String, List<FlyItem>>{};
}

Map<String, List<FlyItem>> _buildFlyouts(AppL10n t) => <String, List<FlyItem>>{
  'line': [
    FlyItem('fline', t.flyLineB, t.flyLineSub, Tool.line),
    FlyItem('fmidline', t.flyLineB, t.flyMidlineSub, Tool.lineMid),
    FlyItem('fsplinecv', t.flySplineB, t.flySplineCvSub, Tool.splineCV),
    FlyItem('fsplinei', t.flySplineB, t.flySplineInterpSub, Tool.splineInterp),
    FlyItem('fsplinefree', t.flySplineB, t.flySplineFreeSub, Tool.splineFree),
    FlyItem('feqcurve', t.flyEqCurveB, t.flyEqCurveB, Tool.eqCurve),
    FlyItem('fbridge', t.flyBridgeB, t.flyBridgeB, Tool.bridge),
  ],
  'circle': [
    FlyItem('fcirclecp', t.flyCircleB, t.flyCenterPointSub, Tool.circleCenter),
    FlyItem('fcircletan', t.flyCircleB, t.flyTangentSub, Tool.circleTangent),
    FlyItem('fellipse', t.flyEllipseB, t.flyEllipseB, Tool.ellipse),
  ],
  'arc': [
    FlyItem('farc3', t.flyArcB, t.flyThreePointSub, Tool.arcThreePoint),
    FlyItem('farctan', t.flyArcB, t.flyTangentSub, Tool.arcTangent),
    FlyItem('farccp', t.flyArcB, t.flyCenterPointSub, Tool.arcCenter),
  ],
  'rect': [
    FlyItem('frect2p', t.flyRectB, t.flyTwoPointSub, Tool.rectTwoPoint),
    FlyItem('frect3p', t.flyRectB, t.flyThreePointSub, Tool.rect3P),
    FlyItem('frect2pc', t.flyRectB, t.flyTwoPointCenterSub, Tool.rect2PC),
    FlyItem('frect3pc', t.flyRectB, t.flyThreePointCenterSub, Tool.rect3PC),
    FlyItem('fslotcc', t.flySlotB, t.flySlotCcSub, Tool.slotCC),
    FlyItem('fslotov', t.flySlotB, t.flySlotOverallSub, Tool.slotOverall),
    FlyItem('fslotcp', t.flySlotB, t.flyCenterPointSub, Tool.slotCP),
    FlyItem('fslot3a', t.flySlotB, t.flySlot3aSub, Tool.slot3A),
    FlyItem('fslotcpa', t.flySlotB, t.flySlotCpaSub, Tool.slotCPA),
    FlyItem('fpolygon', t.flyPolygonB, t.flyPolygonB, Tool.polygon),
  ],
  'fillet': [
    FlyItem('ffillet', t.flyFilletB, '', Tool.fillet),
    FlyItem('fchamfer', t.flyChamferB, '', Tool.chamfer),
  ],
  'text': [
    FlyItem('ftext', t.flyTextB, ''),
    FlyItem('fgtext', t.flyGeomTextB, ''),
  ],
  // M215 — Work Features > Axis / Point. Every entry is REAL and every label
  // is Inventor's own wording — in German, Inventor's GERMAN wording — so a
  // user who knows Inventor finds the method they are looking for by name.
  // `wa`/`wpt` prefixes keep the ids apart from the plane list's.
  // M217 — Inventor's Direct panel. Move/Size/Scale/Delete are built; Rotate
  // is listed because Inventor lists it and left inert because rotating a face
  // needs a BRepTools_Modification whose failure modes only show on real
  // shapes — see DirectEditFeature.
  'direct': [
    FlyItem('deMove', t.flyMoveB, ''),
    FlyItem('deSize', t.flySizeB, ''),
    FlyItem('deScale', t.flyScaleB, ''),
    FlyItem('deRotate', t.flyRotateB, ''),
    FlyItem('deDelete', t.flyDeleteB, ''),
  ],
  'axis': [
    FlyItem('waAuto', t.flyAxisB, ''),
    FlyItem('waLine', t.flyAxisOnLineB, ''),
    FlyItem('waParPt', t.flyAxisParPtB, ''),
    FlyItem('wa2Pt', t.flyAxisTwoPtB, ''),
    FlyItem('wa2Pl', t.flyAxisTwoPlB, ''),
    FlyItem('waNormPt', t.flyAxisNormPtB, ''),
    FlyItem('waCirc', t.flyAxisCircB, ''),
    FlyItem('waRev', t.flyAxisRevB, ''),
  ],
  'point': [
    FlyItem('wptAuto', t.flyPointB, ''),
    FlyItem('wptGround', t.flyPointGroundB, ''),
    FlyItem('wptVertex', t.flyPointVertexB, ''),
    FlyItem('wpt3Pl', t.flyPointThreePlB, ''),
    FlyItem('wpt2Ln', t.flyPointTwoLnB, ''),
    FlyItem('wptPlLn', t.flyPointPlLnB, ''),
    FlyItem('wptLoop', t.flyPointLoopB, ''),
    FlyItem('wptTorus', t.flyPointTorusB, ''),
    FlyItem('wptSphere', t.flyPointSphereB, ''),
  ],
  // M56 — Work Features > Plane (dummy items, real Inventor list)
  'plane': [
    FlyItem('plane', t.flyPlaneB, ''),
    FlyItem('offset', t.flyPlaneOffsetB, ''),
    FlyItem('parallelpt', t.flyPlaneParallelPtB, ''),
    FlyItem('midplane2', t.flyPlaneMid2B, ''),
    FlyItem('midtorus', t.flyPlaneMidTorusB, ''),
    FlyItem('angleedge', t.flyPlaneAngleEdgeB, ''),
    FlyItem('threepts', t.flyPlaneThreePtsB, ''),
    FlyItem('twoedges', t.flyPlaneTwoEdgesB, ''),
    FlyItem('tansurfedge', t.flyPlaneTanSurfEdgeB, ''),
    FlyItem('tansurfpt', t.flyPlaneTanSurfPtB, ''),
    FlyItem('tanparallel', t.flyPlaneTanParallelB, ''),
    FlyItem('normalaxis', t.flyPlaneNormalAxisB, ''),
    FlyItem('normalcurve', t.flyPlaneNormalCurveB, ''),
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

_Face _faceFor(AppState app, AppL10n t, String group,
    {required Tool dflt, required String icon, required String label}) {
  final pick = app.ribbonPick[group] ?? dflt;
  if (pick == dflt) return _Face(icon, label, dflt);
  for (final it in flyoutsOf(t)[group] ?? const <FlyItem>[]) {
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

  /// Positions a flyout beside its anchor in the direction the dock leaves
  /// room: down from a top band, up from a bottom band, and to the side from a
  /// side rail. A side-docked band previously opened the menu downward, which
  /// put a right rail's menu off the screen edge.
  Positioned _anchoredFly(Offset pos, Size size, Widget child) {
    final screen = MediaQuery.of(context).size;
    switch (RibbonDock.current) {
      case RibbonPosition.top:
        return Positioned(
            left: pos.dx, top: pos.dy + size.height + 1, child: child);
      case RibbonPosition.bottom:
        return Positioned(
            left: pos.dx, bottom: screen.height - pos.dy + 1, child: child);
      case RibbonPosition.left:
        return Positioned(
            left: pos.dx + size.width + 1, top: pos.dy, child: child);
      case RibbonPosition.right:
        return Positioned(
            right: screen.width - pos.dx + 1, top: pos.dy, child: child);
    }
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
    final items = flyoutsOf(L.of(context))[id]!;
    _fly = OverlayEntry(
      builder: (_) => Stack(children: [
        _barrier(),
        _anchoredFly(pos, box.size, _FlyMenu(
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
                // (onDefault was an empty closure).
                //
                // M258 — and it is no longer Offset in disguise. Offset is one
                // of the things the generic entry can produce, not the only
                // one: it now arms the INFERRING command, which reads a drag
                // as an offset and a second parallel face as the midplane,
                // the way Inventor's Plane button does. `offset` keeps the
                // narrow command for anyone who wants exactly that.
                case 'plane':
                  widget.app.startWorkPlaneMethod(WorkPlaneMethod.auto);
                  break;
                case 'offset':
                  widget.app.startWorkPlane(WorkPlaneKind.offset);
                  break;
                case 'midplane2':
                  widget.app.startWorkPlane(WorkPlaneKind.midplane);
                  break;
                // M223 — the pick-only Plane methods, on M215's WorkRef
                // machinery. The five that are missing are missing for a
                // reason, and each says so rather than doing nothing:
                // silence reads as broken (M157).
                case 'parallelpt':
                  widget.app.startWorkPlaneMethod(
                      WorkPlaneMethod.parallelToPlaneThroughPoint);
                  break;
                case 'threepts':
                  widget.app
                      .startWorkPlaneMethod(WorkPlaneMethod.threePoints);
                  break;
                case 'twoedges':
                  widget.app
                      .startWorkPlaneMethod(WorkPlaneMethod.twoCoplanarEdges);
                  break;
                case 'normalaxis':
                  widget.app.startWorkPlaneMethod(
                      WorkPlaneMethod.normalToAxisThroughPoint);
                  break;
                case 'midtorus':
                  widget.app
                      .startWorkPlaneMethod(WorkPlaneMethod.midplaneOfTorus);
                  break;
                case 'angleedge':
                  widget.app.startWorkPlaneMethod(
                      WorkPlaneMethod.angleToPlaneAroundEdge);
                  break;
                case 'normalcurve':
                  widget.app.startWorkPlaneMethod(
                      WorkPlaneMethod.normalToCurveAtPoint);
                  break;
                // M224 — the tangent trio, now that a pick carries the side
                // of the face it landed on.
                case 'tansurfpt':
                  widget.app.startWorkPlaneMethod(
                      WorkPlaneMethod.tangentToSurfaceThroughPoint);
                  break;
                case 'tansurfedge':
                  widget.app.startWorkPlaneMethod(
                      WorkPlaneMethod.tangentToSurfaceThroughEdge);
                  break;
                case 'tanparallel':
                  widget.app.startWorkPlaneMethod(
                      WorkPlaneMethod.tangentToSurfaceParallelToPlane);
                  break;
                // M217 — Direct Edit.
                case 'deMove':
                  widget.app.openDirectMove();
                  break;
                case 'deSize':
                  widget.app.openDirectSize();
                  break;
                case 'deScale':
                  widget.app.openDirectScale();
                  break;
                case 'deDelete':
                  widget.app.openDeleteFace();
                  break;
                // M215 — Work Axis.
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
                // M215 — Work Point.
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
                  widget.app.toast(L.current.msgNotBuiltYet(it.b));
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
        _anchoredFly(pos, box.size, _OverMenu(
          items: items,
          onPick: (it) {
            closeFly();
            it.onTap?.call();
          },
        )),
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
      app.toast(L.current.msgCouldNotImportImage);
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
      app.toast(L.current.msgCouldNotImportDxf);
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
      app.toast(L.current.msgEnterLayerToSketch);
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
    final t = L.of(context);
    // The default expression is CODE, not prose: it goes straight into the
    // parser and stays as it is in both languages.
    final expr = TextEditingController(text: 'sin(x)*5');
    final x0 = TextEditingController(text: '0');
    final x1 = TextEditingController(text: '20');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: T.fly,
        title: Text(t.dlgEquationCurve,
            style: ts(14, T.text, w: FontWeight.w600)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: expr,
              autofocus: true,
              style: ts(13, T.text),
              decoration: InputDecoration(
                  labelText: t.lblEquationHint,
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
                            labelText: t.lblXMin,
                            labelStyle: ts(12, T.dim))))),
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
                            labelText: t.lblXMax,
                            labelStyle: ts(12, T.dim))))),
          ]),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t.cancel, style: ts(12.5, T.dim))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t.ok, style: ts(12.5, T.accent))),
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
    // Counted, not timed. Building the ribbon is Dart widget work of a few
    // hundred microseconds; the interesting number is HOW OFTEN it happens.
    // The bar rebuilds off AppState, so a count that tracks the frame count
    // means the whole menu is being rebuilt during a drag — which no duration
    // would reveal, because each individual build looks cheap.
    Perf.count('menu.ribbon.builds');
    // M146 (surface A, M284) — the bar is no longer a FLOATING card. It is a
    // FLUSH band: no side inset, no corner radius, no shadow, just one hairline
    // seam on the edge facing the viewport.
    //
    // M290 — and it is a ROW of the layout rather than an overlay on top of
    // one, so nothing runs behind it and nothing has to be told where it ends.
    // See ribbon_chrome.dart for what that replaced.
    final bool vertical = RibbonDock.isVertical;
    final content = SingleChildScrollView(
      scrollDirection: vertical ? Axis.vertical : Axis.horizontal,
      // The band is only as wide (or tall) as the screen and its panels
      // routinely overflow, so the scroll must never be disabled by a
      // shrink-wrapped parent. Explicit physics keeps the drag alive even when
      // the content happens to fit, which is what makes the ribbon feel like a
      // strip rather than a truncated row.
      physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics()),
      clipBehavior: Clip.hardEdge,
      child: app.isHome
          ? _homeRibbon(app)
          : app.currentAssembly != null
              ? _assemblyRibbon(app)
              : (app.currentPart != null && app.activeChild == null
                  ? _partRibbon(app)
                  : _sketchRibbon(app)),
    );

    // M290 — no RibbonMeasure. The band used to publish its own thickness so
    // seven floating panels could subtract it; it takes a row of the layout
    // now, so its size is the layout's business and nobody else's.
    return Padding(
      padding: RibbonMetrics.pad,
      child: Stack(
        children: [
          // The glass, sized to the band by the content below it.
          const Positioned.fill(child: RibbonSurface()),
          _seam(),
          content,
        ],
      ),
    );
  }

  /// The single hairline that separates the flush band from the viewport, on
  /// the band's inner edge.
  Widget _seam() {
    final color = T.sep;
    return switch (RibbonDock.current) {
      RibbonPosition.top => Positioned(
          left: 0, right: 0, bottom: 0,
          child: Container(height: 1, color: color)),
      RibbonPosition.bottom => Positioned(
          left: 0, right: 0, top: 0,
          child: Container(height: 1, color: color)),
      RibbonPosition.left => Positioned(
          top: 0, bottom: 0, right: 0,
          child: Container(width: 1, color: color)),
      RibbonPosition.right => Positioned(
          top: 0, bottom: 0, left: 0,
          child: Container(width: 1, color: color)),
    };
  }

  /// Lays the panels in a horizontal strip (top/bottom) or a vertical rail
  /// (left/right). The horizontal form needs [IntrinsicHeight] so every panel
  /// is as tall as the tallest and its own [Expanded] has a bound.
  Widget _orient({required List<Widget> children}) {
    if (RibbonDock.isVertical) {
      return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
    }
    return IntrinsicHeight(
      child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }

  /// Lays the buttons INSIDE a panel in a horizontal row (top/bottom) or a
  /// vertical column (left/right). In a side rail the tools stack under each
  /// other instead of running off the rail's edge.
  Widget _flow({
    required List<Widget> children,
    CrossAxisAlignment crossAxisAlignment = CrossAxisAlignment.center,
  }) {
    if (RibbonDock.isVertical) {
      return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
    }
    return Row(crossAxisAlignment: crossAxisAlignment, children: children);
  }

  // Home: single "Sketch" panel with the big Create New Sketch button.
  Widget _homeRibbon(AppState app) =>
      Perf.span('menu.ribbon.home', () => _homeRibbonInner(app));

  Widget _homeRibbonInner(AppState app) {
    final t = L.of(context);
    return _orient(children: [
        _panel(
          label: t.panelSketch,
          arrow: false,
          first: true,
          child: _BigWide(
              width: 78,
              icon: newSketchIcon,
              label: t.btnCreateNewSketch,
              onTap: app.createNewSketch),
        ),
    ]);
  }


  // ---- M56: the 3D part ribbon (Inventor's Part tab, ported from the
  // approved HTML dummy). Only Extrude is wired; the rest are the same
  // inert placeholders the dummy ships, so the layout is final while the
  // behaviour grows feature by feature.
  Widget _partRibbon(AppState app) =>
      Perf.span('menu.ribbon.part', () => _partRibbonInner(app));

  Widget _partRibbonInner(AppState app) {
    final t = L.of(context);
    // Like [col], but each row can also LIGHT UP — a part command that is
    // currently open says so, the way the Extrude button does.
    //
    // M216 — the callback is non-nullable here too. It arrived taking a
    // `VoidCallback?` with a `?? () {}` fallback, which is exactly the hole
    // [col] had; every colActive row today is a real command, so closing it
    // costs nothing and stops the next dead button being added by accident.
    Widget colActive(List<(String, String, VoidCallback, bool)> rows,
            {double leftPad = 8}) =>
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
                      onTap: rows[i].$3,
                      active: rows[i].$4),
                ]
              ]),
        );
    // M215 — [flyIds] maps a row's LABEL to a flyout id, so a small row can
    // carry the same drop chip the big split buttons have. _SmallRow has
    // supported flyId/onFly since M205; nothing in the part ribbon had ever
    // passed them, which is why Axis and Point could only ever have been
    // one-shot buttons with eight unreachable methods behind them.
    // M216 — the callback is NON-nullable, deliberately. Every row here used
    // to accept null and fall back to `?? () {}`, which is how nine dead
    // buttons sat in this ribbon looking finished. An unbuilt command now
    // cannot be put in a visible column at all: it goes in the panel's `over`
    // list, where _OverRow renders it dimmed and untappable. The rule is a
    // type, not a convention somebody has to remember.
    //
    // M234 — the flyout id is the ROW'S OWN fourth field. It used to be looked
    // up in a `Map<String, String>` keyed by the row's LABEL, which worked
    // only for as long as the label was a compile-time English constant: the
    // moment 'Axis' became 'Achse' the lookup missed and the drop chip
    // vanished from two buttons. Structure never keys off display text.
    Widget col(List<(String, String, VoidCallback, String?)> rows,
            {double leftPad = 8}) =>
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
                      flyId: rows[i].$4,
                      onFly: rows[i].$4 == null ? null : toggleFly,
                      onTap: rows[i].$3),
                ]
              ]),
        );
    final inPlace = app.inPlaceEdit;
    return _orient(children: [
        // M250 — RETURN, and only while this part is being edited IN PLACE.
        //
        // Inventor puts Return at the far RIGHT of the tab; this ribbon
        // SCROLLS horizontally (see build), so the right-hand end is off
        // screen on an iPad and the only way out of the mode would be a
        // button nobody could see. It goes first instead, which is also where
        // the eye lands when the viewport suddenly has an assembly in it.
        //
        // A sketch open inside the edit shows the SKETCH ribbon rather than
        // this one, so the way out is then Finish Sketch and then this — which
        // is Inventor's order too, and why this button does not try to close a
        // sketch on the user's behalf.
        if (inPlace != null)
          _panel(
            label: t.panelReturn,
            arrow: false,
            first: true,
            child: _BigWide(
                width: 64,
                icon: returnIcon,
                label: t.btnReturn,
                onTap: () => app.leaveInPlaceEdit()),
          ),
        _panel(
          label: t.panelSketch,
          arrow: false,
          first: inPlace == null,
          child: _BigWide(
              width: 70,
              icon: newSketchIcon,
              label: t.btnStart2dSketch,
              onTap: app.startPartSketch,
              active: app.pickPlane),
        ),
        // M216 — the part ribbon shows what is BUILT; everything else is one
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
          label: t.panelCreate,
          arrow: false,
          overId: 'ov-create3d',
          over: () => [
            OverItem(CR['emboss']!, t.btnEmboss, null),
            OverItem(CR['derive']!, t.btnDerive, null),
            OverItem(CR['decal']!, t.btnDecal, null),
          ],
          child: _flow(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _BigWide(
                width: 58,
                icon: CR['extrude']!,
                label: t.btnExtrude,
                onTap: () => app.openExtrude(),
                // M210 — the highlight names THIS command, not "some panel is
                // open": it toggles now, and a button that lights for a
                // revolve would toggle the wrong thing off.
                active: app.extrudeSession?.kind == 'extrude'),
            _BigWide(
                width: 58,
                icon: CR['revolve']!,
                label: t.btnRevolve,
                onTap: () => app.openRevolve(),
                active: app.extrudeSession?.isRevolve == true),
            col([
              (CR['sweep']!, t.btnSweep, () => app.openSweep(), null),
              (CR['loft']!, t.btnLoft, () => app.openLoft(), null),
              (CR['coil']!, t.btnCoil, () => app.openCoil(), null),
            ]),
          ]),
        ),
        // Hole is in the list: its onTap was `() {}` — an empty closure,
        // the exact thing M157 called out on the Plane button. A big button
        // that silently does nothing is the most expensive kind of lie in a
        // ribbon, because it looks the most finished.
        _panel(
          label: t.panelModify,
          arrow: false,
          overId: 'ov-modify3d',
          over: () => [
            OverItem(MO['shell']!, t.btnShell, null),
            OverItem(MO['draft']!, t.btnDraft, null),
            OverItem(MO['thread']!, t.btnThread, null),
            // M227 — built. It stays in the ▼ rather than moving out: the
            // dropdown is for commands that are available but do not earn
            // permanent ribbon width (M216's own words for the sketch side),
            // and Modify's visible column is full. A live callback is what
            // separates built from unbuilt here, not which list it is in.
            OverItem(MO['combine']!, t.btnCombine, () => app.openCombine(),
                active: app.combineSession != null),
            OverItem(MO['thicken']!, t.btnThickenOffset, null),
            // M228 — Trim Solid, built. Splitting a body INTO TWO needs a
            // feature that spawns a body, which the fold does not do.
            OverItem(MO['split']!, t.btnSplit, () => app.openSplit(),
                active: app.splitSession != null),
          ],
          child: _flow(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _BigWide(
                width: 58,
                icon: MO['fillet']!,
                label: t.btnFillet,
                onTap: () => app.openFillet(),
                active: app.edgeSession?.isFillet == true),
            colActive([
              (MO['chamfer']!, t.btnChamfer, app.openChamfer,
                  app.edgeSession?.isFillet == false),
              // M217 — built, so they leave the ▼ and take their place in the
              // panel. The rule cuts both ways: the dropdown is where a
              // command waits to be built, not where it stays after it is.
              (MO['deleteface']!, t.btnDeleteFace, app.openDeleteFace,
                  app.faceEdit?.kind == FaceEditKind.delete),
              // M225 — Hole, the same way: built, so it leaves the ▼. It sat
              // there as an OverItem with a null onTap, and before M216 as a
              // full-size button with an empty closure.
              (MO['hole']!, t.btnHole, () => app.openHole(),
                  app.holeSession != null),
            ]),
            col([
              (MO['direct']!, t.btnDirect, () => app.openDirectMove(), 'direct'),
            ], leftPad: 0),
          ]),
        ),
        _panel(
          label: t.panelWorkFeatures,
          arrow: false,
          overId: 'ov-work3d',
          // UCS is deliberately still inert: it is a coordinate SYSTEM with
          // its own triad and placement gestures, not a third variant of Axis
          // and Point, and a button that half-works would be worse than one
          // that says it is not built (M157). Behind the ▼ it is listed,
          // dimmed and honest instead of sitting in the panel looking ready.
          over: () => [
            OverItem(WF['ucs']!, t.btnUcs, null),
          ],
          child: _flow(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _Big(
                id: 'plane',
                label: t.btnPlane,
                icon: WF['plane']!,
                onFly: toggleFly,
                // M157 — was an empty closure, so tapping the button did
                // nothing at all and the tool looked broken.
                //
                // M258 — and it runs the LEGACY method now, which is what the
                // Axis and Point buttons beside it have done since M215: pick
                // geometry and it works out what you meant. The flyout keeps
                // the named entries for the picks that are genuinely
                // ambiguous.
                onDefault: () =>
                    widget.app.startWorkPlaneMethod(WorkPlaneMethod.auto)),
            col([
              // M215 — the two that are built. Tapping the row runs the
              // LEGACY method (Inventor's plain "Axis" / "Point"), which is
              // the one people actually use: pick geometry and it works out
              // what you meant. The flyout carries the eight/nine named
              // methods for the cases where a pick is ambiguous.
              (
                WF['axis']!,
                t.btnAxis,
                () => widget.app.startWorkAxis(WorkAxisMethod.auto),
                'axis'
              ),
              (
                WF['point']!,
                t.btnPoint,
                () => widget.app.startWorkPoint(WorkPointMethod.auto),
                'point'
              ),
            ]),
          ]),
        ),
        // M212 — the four pattern commands, wired. They toggle like every
        // other part command (M210) and light for the one that is open.
        //
        // M216 — this panel is VISIBLE and stays visible. The dropdown pass
        // had folded Pattern away on the evidence of its own branch, where
        // all four were inert; main had built them in the meantime. "Hide
        // what does not work" is only ever as good as the reading of what
        // works, so the rule is applied to the MERGED truth, not to a
        // snapshot of one side.
        _panel(
          label: t.panelPattern,
          arrow: false,
          child: _flow(children: [
            colActive([
              (PT['rect']!, t.btnRectangular, app.openRectPattern,
                  app.patternKind == PatternKind.rectangular),
              (PT['circ']!, t.btnCircular, app.openCircPattern,
                  app.patternKind == PatternKind.circular),
              (PT['sketch']!, t.btnSketchDriven, app.openSketchPattern,
                  app.patternKind == PatternKind.sketchDriven),
            ], leftPad: 2),
            colActive([
              (PT['mirror']!, t.btnMirror, app.openMirror,
                  app.patternKind == PatternKind.mirror)
            ]),
          ]),
        ),
        // ---- M272: Appearance, on the FAR RIGHT of both 3D ribbons ------
        //
        // Last, deliberately, and identical in the part and the assembly. It
        // is not a modelling command — nothing it does changes a face — so it
        // belongs after the commands that do, where Inventor also parks its
        // Appearance drop-down. One control, two selections: a body in a part,
        // a component in an assembly, and _MaterialChip does not know which.
        _panel(
          label: t.panelAppearance,
          arrow: false,
          // IntrinsicWidth, and it is not decoration: the ribbon is a
          // horizontal scrollable, so this Column is laid out with an
          // UNBOUNDED width and `stretch` inside that is an infinite
          // constraint, not a layout. Intrinsic gives the pair the width of
          // the WIDER chip, which is also what makes them line up.
          child: IntrinsicWidth(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MaterialChip(app: app, onOpen: toggleOver),
                const SizedBox(height: 4),
                // M273 — RIGHT UNDER the material, as asked, and in the same
                // panel because they are the same question asked twice: what
                // the body looks like, and how the body is drawn.
                _DisplayModeChip(app: app, onOpen: toggleOver),
                if (app.displayMode.isRendered) ...[
                  const SizedBox(height: 4),
                  _FloorToggle(app: app),
                ],
                // M291 — and the section view, under the two that say how the
                // model is DRAWN. It is the third question this panel answers:
                // what colour, how shaded, and how much of it you can see.
                //
                // Part only. Inventor sections an assembly too, and the state
                // and the cut here would carry over unchanged, but the pick
                // has to reach a component's faces and that is the assembly
                // viewport's hit test, not this one's. Left off rather than
                // drawn dead (M157).
                const SizedBox(height: 4),
                _SectionChip(app: app, onOpen: toggleOver),
              ],
            ),
          ),
        ),
    ]);
  }

  Widget _sketchRibbon(AppState app) =>
      Perf.span('menu.ribbon.sketch', () => _sketchRibbonInner(app));

  // ---- M240: the ASSEMBLY ribbon (Inventor's Assemble tab).
  //
  // Component / Position / Relationships / Pattern / Work Features, in
  // Inventor's own order and with Inventor's own wording. Place (M240),
  // Constrain (M242) and the whole Work Features panel (M247) are wired;
  // every other button is drawn in Inventor's DISABLED state rather than
  // folded behind a ▼ (see [_BigWide.enabled] for why this tab gets that third
  // option and the part ribbon does not).
  //
  // Work Features reuses the part ribbon's WF icons, its Plane/Axis/Point/UCS
  // layout AND its commands: the entries below call the same AppState methods
  // the part panel calls, and those route on the open document. An assembly
  // work plane is built by the same thirteen Inventor methods a part's is, so
  // giving it a second ribbon would be inventing a difference that is not
  // there.
  Widget _assemblyRibbon(AppState app) {
    final t = L.of(context);
    // M249 + M250 — `offCol`, the helper that drew small rows for commands
    // that were NOT built, is gone: it had exactly two callers and the two
    // milestones emptied it from opposite ends. M249 wired the Relationships
    // panel's Show / Show Sick / Hide All, M250 wired the Position panel's
    // Free Move and Free Rotate, and this tab now has no drawn-and-disabled
    // small row at all.
    //
    // Not kept "in case one comes back", because one should not: M216's rule
    // is that an unbuilt command goes behind the panel's ▼, where _OverRow
    // draws it dimmed and untappable, rather than taking permanent width in
    // the panel. UCS is the tab's only unbuilt command and that is where it
    // lives.
    //
    // M248 — small rows that are BUILT and can LIGHT UP, for the Pattern
    // panel. [_partRibbon.colActive], in the file that needs it; the two
    // cannot be shared for the same reason [wfCol] below cannot.
    Widget asmCol(List<(String, String, VoidCallback, bool)> rows,
            {double leftPad = 8}) =>
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
                      onTap: rows[i].$3,
                      active: rows[i].$4),
                ]
              ]),
        );
    // M249 — small rows whose callback may be NULL, which is a third state
    // neither [offCol] nor [asmCol] can say: those two mean "not built" and
    // "built", and Show Sick is built and unavailable — Inventor greys it out
    // when every relationship is healthy. A row drawn disabled for that reason
    // has to look exactly like one drawn disabled for the other, or the ribbon
    // would be teaching two meanings for one appearance.
    Widget maybeCol(List<(String, String, VoidCallback?, bool)> rows,
            {double leftPad = 8}) =>
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
                      enabled: rows[i].$3 != null,
                      onTap: rows[i].$3,
                      active: rows[i].$4),
                ]
              ]),
        );
    // M247 — small rows that are BUILT, each with the drop chip its flyout
    // needs. The part ribbon's `col` in every respect but the file it is
    // written in; it cannot simply be shared because both are closures over
    // their own ribbon's `toggleFly` context.
    Widget wfCol(List<(String, String, VoidCallback, String)> rows,
            {double leftPad = 8}) =>
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
                      flyId: rows[i].$4,
                      onFly: toggleFly,
                      onTap: rows[i].$3),
                ]
              ]),
        );
    return _orient(children: [
        // ---- Component: Place (wired) + Create -----------------------------
        _panel(
          label: t.panelComponent,
          arrow: true,
          first: true,
          child: _flow(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // The drop chip is Inventor's: Place has a list behind it (Place
            // Component / Place from Content Center / Place Imported CAD).
            // Only the default action exists here, so the chip runs the same
            // command the body does rather than opening an empty menu.
            _Big(
                label: t.btnPlace,
                icon: AS['place']!,
                onDefault: () => _placeComponent(app),
                active: _placing),
            // M250 — WIRED. Inventor's Create In-Place Component: name the
            // part, pick a plane to sketch on, and it is written, placed and
            // opened for editing with the assembly still around it. The
            // button stays lit for as long as the command is open — through
            // the dialog AND through the plane pick that follows it, because
            // both are the one command.
            _BigWide(
                width: 58,
                icon: AS['create']!,
                label: t.btnCreateComponent,
                onTap: () => app.openCreateComponent(),
                active: app.createComponentSession != null),
          ]),
        ),
        // ---- Position: Free Move / Free Rotate -----------------------------
        //
        // M250 — both WIRED, and the distinction the old comment here drew is
        // exactly what they are for. The viewport has dragged a component
        // since M240 and through the solver since M242; that is direct
        // manipulation and needs no command. Inventor's Free Move is the
        // COMMAND, and what it does that a drag does not is TEMPORARILY
        // OVERRIDE the relationships — the component goes where you put it
        // and stays there until the next update takes it back.
        //
        // Free Rotate is the half that had no existing anything: the viewport
        // has never had a rotation gesture. It arms Inventor's 3D rotate
        // glyph on the selected component. Both are toggles and both light
        // while armed, like every other command in this ribbon.
        _panel(
          label: t.panelPosition,
          arrow: true,
          child: asmCol([
            (
              AS['freemove']!,
              t.btnFreeMove,
              app.startFreeMove,
              app.asmPositionMode == AsmPositionMode.move
            ),
            (
              AS['freerotate']!,
              t.btnFreeRotate,
              app.startFreeRotate,
              app.asmPositionMode == AsmPositionMode.rotate
            ),
          ], leftPad: 2),
        ),
        // ---- Relationships: Joint / Constrain + Show / Show Sick / Hide All
        _panel(
          label: t.panelRelationships,
          arrow: true,
          child: _flow(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // M249 — Joint is WIRED. Inventor's own claim for it is that ONE
            // pick pair replaces the two or three constraints you would
            // otherwise place by hand, and the dialog it opens is the modeless
            // sibling of Place Constraint's: it collects its two origins from
            // the viewport through the same session (see
            // ConstraintSession.jointType).
            _BigWide(
                width: 52,
                icon: AS['joint']!,
                label: t.btnJoint,
                onTap: () => app.openJoint(),
                active: app.constraintSession?.isJoint == true),
            // M242 — Constrain is WIRED. It opens Inventor's modeless Place
            // Constraint panel, which then collects its selections from the
            // viewport; the button stays lit for as long as the panel is up,
            // the way every other open command's does.
            _BigWide(
                width: 62,
                icon: AS['constrain']!,
                label: t.btnConstrain,
                onTap: () => app.openConstraint(),
                active: app.constraintSession != null),
            // M249 — the three relationship-visibility rows, wired. They
            // control whether the constraint GLYPHS are drawn in the viewport
            // (paintRelationshipGlyphs), which is the thing that had to exist
            // before the commands could mean anything.
            //
            // Show LIGHTS while it is waiting for a component, because
            // Inventor's is modal in exactly that way ("click Show, then
            // select the component"); the other two are one-shots and never
            // light. Show Sick is DISABLED when nothing is sick, which is
            // Inventor's own rule — "the command is not available if all
            // relationships are healthy" — and the one place in this ribbon
            // where a command's enablement depends on the document rather than
            // on whether it has been built.
            maybeCol([
              (
                AS['show']!,
                t.btnShowRelationships,
                app.showRelationships,
                app.showRelationshipsPicking
              ),
              (
                AS['showsick']!,
                t.btnShowSick,
                app.currentAssembly?.hasSickRelationships == true
                    ? app.showSickRelationships
                    : null,
                false
              ),
              (AS['hideall']!, t.btnHideAll, app.hideAllRelationships, false),
            ]),
          ]),
        ),
        // ---- Pattern: Pattern / Mirror / Copy ------------------------------
        //
        // M248 — all three WIRED, and Pattern and Mirror open the PART's
        // pattern panel with an assembly session in it. Inventor draws
        // Pattern Component and Mirror Components as two dialogs; here they
        // are the two modes of one panel that already serves four commands,
        // for the reason PatternPanel3D states about serving four: the chrome,
        // the seed list, the counts, the distributions, the irregular rows and
        // the OK/Cancel behaviour are identical, and a second panel would be a
        // second place to keep them in step.
        //
        // Pattern opens on Rectangular, Inventor's most-used. Circular and
        // the Associative flavour are reached through the panel's own RAIL,
        // which is where Inventor puts them too — its Pattern Component
        // dialog is one dialog with three tabs, not three ribbon buttons —
        // and switching there keeps the seeds already picked. Each button
        // lights while its command is open, the way every other one does.
        _panel(
          label: t.panelPattern,
          arrow: false,
          child: _flow(children: [
            asmCol([
              (
                PT['rect']!,
                t.btnPatternComponent,
                () => app.openAsmPattern(PatternKind.rectangular),
                app.asmPatternSession?.mode == PatternKind.rectangular
              ),
              (
                PT['mirror']!,
                t.btnMirror,
                () => app.openAsmPattern(PatternKind.mirror),
                app.asmPatternSession?.mode == PatternKind.mirror
              ),
              // Copy is a one-shot on the SELECTION, not a panel: it places
              // another occurrence of the selected component as it sits. See
              // AppState.copySelectedComponent for why it is not Inventor's
              // (which writes new part documents, and rule 1 forbids that).
              (AS['copy']!, t.btnCopy, app.copySelectedComponent, false),
            ], leftPad: 2),
          ]),
        ),
        // ---- Work Features: the part ribbon's panel, on this document ------
        //
        // M247 — WIRED, and deliberately the part ribbon's panel rather than a
        // second one. An assembly work plane is built by the same commands
        // from the same flyout lists: every entry below calls the SAME
        // AppState method the part panel calls, and that method arms whichever
        // document is open (see startWorkAxis and its three siblings). Two
        // ribbons calling two sets of commands would be two places for the
        // Inventor method list to drift.
        //
        // UCS stays behind the ▼, dimmed and untappable, exactly as it does in
        // the part panel and for the reason stated there: it is a coordinate
        // SYSTEM with its own triad and placement gestures, not a third
        // variant of Axis and Point. It is unbuilt in BOTH modes; building it
        // in one would be the half-built version of the same lie M157 named.
        _panel(
          label: t.panelWorkFeatures,
          arrow: false,
          overId: 'ov-workasm',
          over: () => [
            OverItem(WF['ucs']!, t.btnUcs, null),
          ],
          child: _flow(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _Big(
                id: 'plane',
                label: t.btnPlane,
                icon: WF['plane']!,
                onFly: toggleFly,
                // The button BODY runs Inventor's most-used entry, Offset
                // from Plane — the same default the part button has had since
                // M157. The flyout carries the other twelve.
                onDefault: () => app.startWorkPlane(WorkPlaneKind.offset)),
            wfCol([
              (
                WF['axis']!,
                t.btnAxis,
                () => app.startWorkAxis(WorkAxisMethod.auto),
                'axis'
              ),
              (
                WF['point']!,
                t.btnPoint,
                () => app.startWorkPoint(WorkPointMethod.auto),
                'point'
              ),
            ]),
          ]),
        ),
        // ---- M272: Appearance, on the FAR RIGHT of both 3D ribbons ------
        //
        // Last, deliberately, and identical in the part and the assembly. It
        // is not a modelling command — nothing it does changes a face — so it
        // belongs after the commands that do, where Inventor also parks its
        // Appearance drop-down. One control, two selections: a body in a part,
        // a component in an assembly, and _MaterialChip does not know which.
        _panel(
          label: t.panelAppearance,
          arrow: false,
          // IntrinsicWidth, and it is not decoration: the ribbon is a
          // horizontal scrollable, so this Column is laid out with an
          // UNBOUNDED width and `stretch` inside that is an infinite
          // constraint, not a layout. Intrinsic gives the pair the width of
          // the WIDER chip, which is also what makes them line up.
          child: IntrinsicWidth(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MaterialChip(app: app, onOpen: toggleOver),
                const SizedBox(height: 4),
                // M273 — RIGHT UNDER the material, as asked, and in the same
                // panel because they are the same question asked twice: what
                // the body looks like, and how the body is drawn.
                _DisplayModeChip(app: app, onOpen: toggleOver),
                if (app.displayMode.isRendered) ...[
                  const SizedBox(height: 4),
                  _FloorToggle(app: app),
                ],
              ],
            ),
          ),
        ),
    ]);
  }

  /// True while the Place picker is up, so the button stays lit under it the
  /// way every other open command's button does (M210).
  bool _placing = false;

  /// Place Component: pick a part from the gallery, drop it into the assembly.
  ///
  /// The picker is the NATIVE action sheet on iOS and a Flutter menu
  /// elsewhere, exactly like the gallery's "+" — one list of documents to
  /// choose from is the same problem, and having it behave differently in the
  /// one place it is reached from the ribbon would be gratuitous.
  Future<void> _placeComponent(AppState app) async {
    final t = L.of(context);
    final parts = app.placeableParts();
    if (parts.isEmpty) {
      app.toast(t.msgAsmNoPartsToPlace);
      return;
    }
    final box = context.findRenderObject();
    final anchor = box is RenderBox
        ? box.localToGlobal(Offset.zero) & box.size
        : Rect.zero;
    setState(() => _placing = true);
    try {
      String? pick;
      if (NativeMenu.isSupported) {
        pick = await NativeMenu.menu(
          items: [
            for (final n in parts)
              NativeMenuItem(
                  id: 'p:$n',
                  title: n,
                  // M246 — a SUBASSEMBLY is placed by the same command and
                  // has to be told apart in the list, because "Gearbox" says
                  // nothing about which kind of document it is.
                  symbol: app.isAssemblyName(n)
                      ? 'square.stack.3d.up'
                      : 'cube'),
          ],
          anchor: anchor,
          cancelLabel: t.cancel,
        );
      } else {
        pick = await showMenu<String>(
          context: context,
          color: T.fly,
          position: RelativeRect.fromLTRB(
              anchor.left + 8, anchor.bottom, anchor.right, anchor.bottom),
          items: [
            for (final n in parts)
              PopupMenuItem(
                value: 'p:$n',
                height: 40,
                child: Row(children: [
                  svg(app.isAssemblyName(n) ? assemblyMenuIcon : part3dMenuIcon,
                      18),
                  const SizedBox(width: 10),
                  Text(n, style: ts(12.5, T.text)),
                ]),
              ),
          ],
        );
      }
      if (!mounted) return;
      if (pick != null && pick.startsWith('p:')) {
        await app.placeComponent(pick.substring(2));
      }
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  Widget _sketchRibbonInner(AppState app) {
    final t = L.of(context);
    return _orient(children: [
        // 1. Layer
        _panel(
          label: t.panelLayer,
          arrow: false,
          first: true,
          child: _BigWide(
              width: 70,
              icon: layerBigIcon,
              label: t.btnStartNewLayer,
              onTap: app.startNewLayer),
        ),
        // Outside layer edit mode there is NOTHING to do with these: every
        // drawing/modify/constrain tool refuses to run off the edit scope
        // (M16/M17), so showing them was offering buttons that silently did
        // nothing. Only "Start New Layer" — the way IN — stays visible.
        if (app.inEditMode) ...[
        // 2. Create
        _panel(
          label: t.panelCreate,
          arrow: false,
          child: _flow(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _BigSplit(app: app, id: 'line', dflt: Tool.line,
                icon: IC['line34']!, label: t.btnLine,
                onFly: toggleFly, onStart: _startTool),
            _BigSplit(app: app, id: 'circle', dflt: Tool.circleCenter,
                icon: IC['circle34']!, label: t.btnCircle,
                onFly: toggleFly, onStart: _startTool),
            _BigSplit(app: app, id: 'arc', dflt: Tool.arcThreePoint,
                icon: IC['arc34']!, label: t.btnArc,
                onFly: toggleFly, onStart: _startTool),
            _BigSplit(app: app, id: 'rect', dflt: Tool.rectTwoPoint,
                icon: IC['rect34']!, label: t.btnRectangle,
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
                      final f = _faceFor(app, t, 'fillet',
                          dflt: Tool.fillet,
                          icon: IC['fillet18']!,
                          label: t.btnFillet);
                      return _SmallRow(
                          icon: f.icon,
                          label: f.label,
                          flyId: 'fillet',
                          onFly: toggleFly,
                          onTap: () => _startTool(f.tool),
                          active: _toolGroup[app.tool] == 'fillet');
                    }),
                    const SizedBox(height: 2),
                    _SmallRow(icon: IC['text18']!, label: t.btnText, flyId: 'text', onFly: toggleFly,
                        // M44: parametric sketch text — tap places, the
                        // dialog takes <Param> placeholders
                        onTap: () => _startTool(Tool.text),
                        active: app.tool == Tool.text),
                    const SizedBox(height: 2),
                    _SmallRow(icon: IC['point18']!, label: t.btnPoint,
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
          child: _BigWide(width: 76, icon: IC['projgeo']!, label: t.btnProjectGeometry,
              onTap: () => _startTool(Tool.project),
              active: app.tool == Tool.project),
        ),
        // 4. Pattern
        _panel(
          label: t.panelPattern,
          arrow: false,
          child: Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SmallRow(icon: IC['patrect']!, label: t.btnRectangular,
                      onTap: () => _startTool(Tool.patRect),
                      active: app.tool == Tool.patRect),
                  const SizedBox(height: 2),
                  _SmallRow(icon: IC['patcirc']!, label: t.btnCircular,
                      onTap: () => _startTool(Tool.patCirc),
                      active: app.tool == Tool.patCirc),
                  const SizedBox(height: 2),
                  _SmallRow(icon: IC['patmir']!, label: t.btnMirror,
                      onTap: () => _startTool(Tool.mirror),
                      active: app.tool == Tool.mirror),
                ]),
          ),
        ),
        // 5. Constrain — Smooth / Constraint Settings / Show Constraints are
        // rarely used, so they moved behind the title's ▼ instead of costing
        // permanent grid width. They are NOT gone, just one tap deeper.
        _panel(
          label: t.panelConstrain,
          arrow: false,
          overId: 'ov-constrain',
          over: () => [
            OverItem(CN['smooth']!, t.btnSmoothG2,
                () => _startTool(Tool.cSmooth),
                active: app.tool == Tool.cSmooth),
            OverItem(CN['conset']!, t.btnConstraintSettings,
                app.toggleShowDof, active: app.showDof),
            OverItem(CN['showcons']!, t.btnShowConstraints,
                app.toggleShowConstraints, active: app.showConstraints),
          ],
          child: _flow(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ConstrainedBox(
              // Was a fixed 66 and it cramped the German: "Bemaßung" asks for
              // ~94 px where "Dimension" fitted in 66, so the label wrapped.
              // A floor, like [_Big] and [_BigWide].
              constraints: const BoxConstraints(minWidth: 66),
              child: _Hover(
                activeHighlight: app.tool == Tool.dimension,
                onTap: () => _startTool(Tool.dimension),
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _BigPlainBody(label: t.btnDimension),
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
          label: t.panelInsert,
          arrow: false,
          overId: 'ov-insert',
          over: () => [
            OverItem(IN['points']!, t.btnPointsTool, null),
            OverItem(IN['sphere']!, t.btnCenterline,
                app.toggleCenterlineSelected),
            OverItem(IN['center']!, t.btnCenterPoint, null),
            OverItem(IN['driven']!, t.btnDrivenDimension, null),
            OverItem(IN['showfmt']!, t.btnShowFormat, null),
          ],
          child: _flow(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SmallRow(
                      icon: IN['image']!,
                      label: t.btnImage,
                      onTap: () => _pickImage(app)),
                  const SizedBox(height: 2),
                  _SmallRow(
                      icon: IN['acad']!,
                      label: t.btnAcad,
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
                      label: t.btnConstruction,
                      onTap: app.toggleConstructionSelected),
                  const SizedBox(height: 2),
                  _SmallRow(
                      icon: IN['constr']!, // unused: iconWidget wins
                      // An icon drawn as type, so it must not wrap the way a
                      // label would; it is centred in the 18 px icon column
                      // that lines this row up with its SVG neighbours.
                      iconWidget: Text('fx',
                          softWrap: false,
                          style: TextStyle(
                              color: T.accent,
                              fontSize: 14,
                              height: 1.0,
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.w700)),
                      label: t.btnParameters,
                      onTap: app.toggleParams,
                      active: app.showParams),
                ]),
            Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SmallRow(
                      icon: IN['gear']!,
                      label: t.btnGear,
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
          label: t.panelModify,
          arrow: false,
          overId: 'ov-modify',
          over: () => [
            OverItem(MD['extend']!, t.btnExtend,
                () => _startTool(Tool.extendT),
                active: app.tool == Tool.extendT),
            OverItem(MD['move']!, t.flyMoveB, () => _startTool(Tool.move),
                active: app.tool == Tool.move),
            OverItem(MD['copy']!, t.btnCopy, () => _startTool(Tool.mcopy),
                active: app.tool == Tool.mcopy),
            OverItem(MD['mrotate']!, t.flyRotateB,
                () => _startTool(Tool.mrotate),
                active: app.tool == Tool.mrotate),
            OverItem(MD['mscale']!, t.flyScaleB, () => _startTool(Tool.mscale),
                active: app.tool == Tool.mscale),
            OverItem(MD['stretch']!, t.btnStretch,
                () => _startTool(Tool.mstretch),
                active: app.tool == Tool.mstretch),
          ],
          child: _flow(children: [
            _modCol(['trim', 'split', 'moffset'],
                [t.btnTrim, t.btnSplitCurve, t.btnOffsetCurve],
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
            label: t.panelView,
            arrow: false,
            child: _BigWide(
                width: 74,
                icon: WF['plane']!,
                label: t.btnSliceGraphics,
                active: app.sliceGraphics,
                onTap: app.toggleSliceGraphics),
          ),
        // Exit panel (only in layer edit mode), pinned to the right in spirit;
        // in a scrolling ribbon it follows Modify like #panel-exit.on does.
        if (app.inEditMode || app.activeChild != null)
          _panel(
            label: t.panelExit,
            arrow: false,
            child: _BigWide(
                width: 64,
                icon: finishIcon,
                label: app.activeChild != null
                    ? t.btnFinishSketch
                    : t.btnFinish,
                onTap: () => app.activeChild != null
                    ? app.finishPartSketch()
                    : app.finishEdit()),
          ),
    ]);
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
      Text(label, style: ts(12, T.dim), softWrap: false),
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
    final vertical = RibbonDock.isVertical;
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
      // A vertical rail has no [IntrinsicHeight] around the whole row of panels,
      // so each panel supplies its own bounded height for its content's
      // `stretch` rows; the panel title sits under it instead of beside it.
      child: vertical ? IntrinsicHeight(child: child) : child,
    );
    final titlePad = Padding(
      padding: const EdgeInsets.only(top: 3, bottom: 5),
      child: title,
    );
    return Container(
      decoration: first
          ? null
          : BoxDecoration(
              border: vertical
                  ? Border(top: BorderSide(color: T.panelSep, width: 1))
                  : Border(left: BorderSide(color: T.panelSep, width: 1))),
      padding: EdgeInsets.zero,
      child: vertical
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [body, titlePad],
            )
          : Column(children: [Expanded(child: body), titlePad]),
    );
  }
}

// ---- building blocks matching .big / .bigwide / .smallrow / grids ----

class _Hover extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  /// Null means "the standard hover wash" — resolved through [hoverColor] at
  /// build time rather than defaulted here, because a default value has to be
  /// a compile-time constant and a palette token is no longer one (M236).
  final Color? hoverBg;
  final bool hoverBorder;
  final bool activeHighlight; // Inventor-style: active tool stays lit
  _Hover(
      {required this.child,
      this.onTap,
      this.hoverBg,
      this.hoverBorder = true,
      this.activeHighlight = false});

  Color get hoverColor => hoverBg ?? T.hover6;
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
                ? T.mbActiveBg
                : (_h ? widget.hoverColor : Colors.transparent),
            borderRadius: BorderRadius.circular(2),
            border: Border.all(
                color: act
                    ? T.mbActiveOutline
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
                    color: lit ? T.accent.withValues(alpha: 0.45) : T.border10),
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
    final f = _faceFor(app, L.of(context), id, dflt: dflt, icon: icon, label: label);
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

  /// M247 — every _Big on every tab is now a built command, so this no longer
  /// carries the disabled flag its siblings do. The rule it stated has moved
  /// to [_BigWide.enabled], which still needs it (assembly > Component >
  /// Create, and Relationships > Joint).
  bool get enabled => true;

  @override
  Widget build(BuildContext context) {
    return Builder(builder: (ctx) {
      return ConstrainedBox(
        // M235 — a MINIMUM width, not a fixed one.
        //
        // 62 was measured against the ENGLISH labels. German runs longer
        // ("Rechteck", "Konstruktion", "Bemaßung"), and because this Text had
        // no line limit a label wider than the box did not clip — it WRAPPED,
        // which pushed the whole ribbon a line taller. Growing the box is the
        // fix rather than shrinking the type: the ribbon is a horizontal
        // SingleChildScrollView (see [_RibbonState.build]) whose panels
        // "routinely overflow", so width here costs scroll, not layout.
        //
        // The floor stays 62, so a label that already fitted is laid out
        // exactly where it was: a minWidth only ever grows a box that was
        // being cut off. How many labels that is depends on the device's SF
        // Pro Text metrics, which cannot be measured on a host test runner --
        // so this is stated as a property of the constraint, not as a claim
        // about which buttons move.
        constraints: const BoxConstraints(minWidth: 62),
        child: _Hover(
          activeHighlight: active,
          onTap: !enabled
              ? null
              : onDefault ??
                  (id != null && onFly != null ? () => onFly!(id!, ctx) : null),
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _dimmable(svg(icon, 34), enabled),
              const SizedBox(height: 3),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Text(label,
                    style: ts(11.5, enabled ? T.text : T.dim),
                    textAlign: TextAlign.center,
                    // A hard '\n' still breaks; only SOFT wrapping is off.
                    // That is the whole distinction being drawn here: a label
                    // is allowed to be two lines because it was WRITTEN that
                    // way, never because it ran out of room.
                    softWrap: false),
              ),
              if (showDd)
                // No SizedBox gap: the chip carries its own transparent
                // padding, and stacking a gap on top of it only pushes the
                // ribbon taller for nothing.
                _DropChip(
                  width: 46,
                  onTap: enabled && id != null && onFly != null
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

  /// M240 — Inventor's DISABLED state, and the honest middle ground between
  /// M216's two options.
  ///
  /// M216's rule is that a command which does nothing must not take permanent
  /// ribbon width: it goes behind the panel's ▼, where _OverRow draws it
  /// dimmed and untappable. That rule assumes the panel around it is real. The
  /// assembly tab is a LAYOUT being built — the whole point of it is that the
  /// panels stand where Inventor's stand — so folding eleven of its twelve
  /// commands away would leave a tab that shows nothing of what it is going to
  /// be. Inventor itself draws these greyed rather than hidden (Free Move,
  /// Free Rotate and Show Sick are greyed in an empty assembly), so the third
  /// state is Inventor's own, not an excuse: dimmed, no hover, no tap, no lie.
  ///
  /// M249 + M250 — and as of those two, NOTHING passes it any more: every big
  /// button on the assembly tab is built. The analyzer says so, and it is
  /// worth reading as the milestone report it is rather than as dead weight.
  /// Kept, because the state it draws is still the right answer for a command
  /// that is built and momentarily UNAVAILABLE — which Show Sick now is, and
  /// which it expresses through a null onTap in a small row instead. The next
  /// big button in that position should use this rather than reinvent it.
  final bool enabled;
  const _BigWide(
      {required this.width,
      required this.icon,
      required this.label,
      this.onTap,
      this.active = false,
      this.enabled = true});
  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      // Same change as [_Big], same reason: [width] is the floor the English
      // layout was tuned to, not a cap the German has to fit inside.
      constraints: BoxConstraints(minWidth: width),
      child: _Hover(
        onTap: enabled ? onTap : null,
        activeHighlight: active,
        child: Stack(children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 4),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Center(child: _dimmable(svg(icon, 34), enabled)),
              const SizedBox(height: 3),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Text(label,
                    textAlign: TextAlign.center,
                    style: ts(11.5, enabled ? T.text : T.dim, height: 1.15),
                    // The six deliberate two-line labels (btnCreateNewSketch,
                    // btnStart2dSketch, btnStartNewLayer, btnProjectGeometry,
                    // btnSliceGraphics, btnFinishSketch) carry their own '\n'
                    // and keep both lines — in English too. Everything else
                    // now stays on one.
                    softWrap: false),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// A ribbon glyph in its disabled state.
///
/// Opacity rather than a grey re-draw: the icons are multi-colour SVG strings
/// (steel, blue, the green "new" marker), and a colour filter over that comes
/// out as a muddy smear where the eye still has to tell Place from Create.
/// Fading keeps the SHAPE readable, which is what a disabled icon has to do —
/// it says "this command, not yet", not "some button".
Widget _dimmable(Widget child, bool enabled) =>
    enabled ? child : Opacity(opacity: 0.38, child: child);

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

  /// See [_BigWide.enabled] — Inventor's greyed state, for the assembly tab.
  final bool enabled;

  /// Replaces the SVG when the glyph is not an icon — Parameters uses
  /// Inventor's italic "fx", which is type, not artwork.
  final Widget? iconWidget;
  const _SmallRow(
      {required this.icon, required this.label, this.flyId, this.onFly,
      this.onTap, this.active = false, this.enabled = true, this.iconWidget});
  @override
  Widget build(BuildContext context) {
    // M290 — the hit target may shrink in a rail, and only in a rail. It has
    // to be flexible HERE, on the outer row, or the bound never reaches the
    // label: _Hover shrink-wraps to its child's natural width, so a Flexible
    // further in has nothing to shrink against.
    final Widget hit = _Hover(
          hoverBorder: false,
          activeHighlight: active,
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                  width: 18,
                  height: 18,
                  child: Center(
                      child: _dimmable(iconWidget ?? svg(icon, 18), enabled))),
              const SizedBox(width: 6),
              // M290 — IN A SIDE RAIL THE LABEL MAY SHRINK.
              //
              // A rail is 168 pt wide and these rows are laid out inside it,
              // where the horizontal scroll that saves the band does not
              // apply: a row wider than the rail is a RenderFlex overflow, and
              // on a device that is the yellow-and-black bar, not a clipped
              // word. ("Geometrie projizieren" overflowed a left dock by
              // 36 px.) Flexible only in the rail, deliberately: the
              // horizontal band lives in an unbounded-width scroll view, and a
              // flex child under unbounded constraints is an assertion.
              if (RibbonDock.isVertical)
                Flexible(
                  child: Text(label,
                      style: ts(12.5, enabled ? T.text : T.dim),
                      softWrap: false,
                      overflow: TextOverflow.ellipsis),
                )
              else
                Text(label,
                    style: ts(12.5, enabled ? T.text : T.dim), softWrap: false),
            ]),
          ),
        );
    return SizedBox(
      height: 26,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (RibbonDock.isVertical) Flexible(child: hit) else hit,
        Builder(builder: (ctx) {
          // M205: same chip as the big split buttons — the 14-px column that
          // used to hold a 7.5-px glyph was the hardest target in the app. The
          // placeholder keeps the SAME width so rows without a flyout still
          // line up with the ones that have one.
          if (flyId == null || !enabled) {
            return const SizedBox(width: _smallDropWidth);
          }
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
      Text(label,
          style: ts(11.5, T.text),
          textAlign: TextAlign.center,
          softWrap: false),
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
  //
  // M234 — a FUNCTION of the strings now, not a const list. The ids on the
  // left are what the grid dispatches on and they never move; only the labels
  // change with the language.
  static List<(String, String)> consOf(AppL10n t) => [
    ('coincident', t.conCoincident),
    ('collinear', t.conCollinear),
    ('concentric', t.conConcentric),
    ('lock', t.conLock),
    ('parallel', t.conParallel),
    ('perp', t.conPerpendicular),
    ('horiz', t.conHorizontal),
    ('vert', t.conVertical),
    ('tangent', t.conTangent),
    ('symmetric', t.conSymmetric),
    ('equal', t.conEqual),
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
    final cons = consOf(L.of(context));
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
                : Border(bottom: BorderSide(color: T.hover6)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            // M273 — a row may have neither glyph nor swatch. The display
            // modes are a two-item choice list and iOS does not put icons in
            // one; the gap keeps their labels on the same left edge as every
            // other menu's, so the two kinds of menu still read as one family.
            if (it.tint != null)
              _Swatch(argb: it.tint!)
            else if (it.icon.isNotEmpty)
              svg(it.icon, 18)
            else
              const SizedBox(width: 18),
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
                : Border(
                    bottom: BorderSide(color: T.hover6)),
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
                          : ts(12.5, T.text,
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

/// M272 — one appearance, as a filled disc.
///
/// A ring around it, and it is not decoration: Aluminium on the light palette
/// and Graphite on the dark one are both within a few percent of the menu's
/// own ground, and without an edge the swatch simply disappears on the one row
/// where the user most needs to see it.
class _Swatch extends StatelessWidget {
  final int argb;
  const _Swatch({required this.argb});

  static const double size = 14;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Color(argb),
          shape: BoxShape.circle,
          border: Border.all(color: T.sep, width: 0.5),
        ),
      );
}

/// M272 — the ribbon's appearance control: a swatch, a name and a ▼.
///
/// Not a _SmallRow with a flyout, because the two say different things. A
/// ribbon button is a VERB with variants behind its chip; this is a VALUE that
/// happens to be editable, and it has to show what is currently set even when
/// it is not being used. Inventor draws its Appearance drop-down the same way,
/// and for the same reason.
///
/// DIMMED WITH NOTHING SELECTED, and it still says why rather than going
/// blank: "Nothing selected" is an instruction, an empty box is a bug report.
class _MaterialChip extends StatefulWidget {
  final AppState app;

  /// The ribbon's own overflow-menu opener, passed in rather than reached for:
  /// this widget lives outside _RibbonState and the menu has to be part of the
  /// one-open-menu-at-a-time discipline every other ribbon flyout follows.
  final void Function(String id, BuildContext anchor, List<OverItem> items)
      onOpen;
  const _MaterialChip({required this.app, required this.onOpen});

  @override
  State<_MaterialChip> createState() => _MaterialChipState();
}

class _MaterialChipState extends State<_MaterialChip> {
  bool _h = false;

  List<OverItem> _items(AppL10n t) {
    final app = widget.app;
    final cur = app.selectedMaterial;
    return [
      // Steel first: "back to plain" is a choice in the same list, not a
      // separate command somewhere else.
      for (final id in materialIds)
        OverItem(
          '', // never drawn — see OverItem.tint
          materialName(t, id),
          () => app.setSelectedMaterial(id),
          active: (cur ?? kMaterialSteel) == id,
          tint: materialArgb(id) ?? T.solid.toARGB32(),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    final app = widget.app;
    final on = app.canSetMaterial;
    final cur = app.selectedMaterial;
    // The 132 is a FLOOR, not a cap, and that is M235's rule rather than a
    // preference: a fixed box with an ellipsis inside it is exactly the shape
    // that made every long German ribbon label wrap or clip. The chip is as
    // wide as its widest state needs and no narrower, and because it is the
    // LAST panel of a horizontally scrolling bar the extra width costs scroll
    // rather than layout — which is the same bargain every other panel makes.
    // The 90 is a FLOOR on the LABEL, not a cap on the chip, and that is
    // M235's rule rather than a preference: a fixed box with an ellipsis in it
    // is exactly the shape that made every long German ribbon label wrap or
    // clip. So the chip is as wide as its widest state needs and never
    // narrower than a steady 90 — and because it is the LAST panel of a
    // horizontally scrolling bar, the extra width costs scroll, not layout.
    //
    // MainAxisSize.min throughout, and not a style choice either: the ribbon
    // is a horizontal scrollable, so this Row is laid out with an UNBOUNDED
    // width and an Expanded inside it is an assertion, not a layout.
    final chip = Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
      decoration: BoxDecoration(
        // A dropdown chip on the glass ribbon is a translucent wash, not the
        // opaque dark "field" well: T.field reads as a hole punched into the
        // liquid glass, and the hard T.sep edge is the same kind of seam the
        // bar's own hairline is. The hover washes are the idiom _DropChip
        // already uses, so the whole bar reads as one surface.
        color: (_h && on) ? T.hover7 : T.hover6,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: (_h && on) ? T.accent.withValues(alpha: 0.45) : T.border10),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _Swatch(argb: materialArgb(cur) ?? T.solid.toARGB32()),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 90),
          child: Text(on ? materialName(t, cur) : t.matPickBody,
              softWrap: false, style: ts(12, on ? T.text : T.dim)),
        ),
        const SizedBox(width: 6),
        Text('▼', style: ts(8, T.dim)),
      ]),
    );
    return MouseRegion(
      cursor: on ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: Builder(
        builder: (ctx) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: on ? () => widget.onOpen('ov-material', ctx, _items(t)) : null,
          child: chip,
        ),
      ),
    );
  }
}

/// M286 — the floor toggle, shown only while the model is drawn in rendered
/// mode. The working view never draws a floor, so a checkbox there would be a
/// control that does nothing; the chip above only offers this row once
/// `displayMode` is rendered. Same drawing as the rest of the app's check
/// marks (see `asmCheckMark`), with the label kept short like every ribbon row.
class _FloorToggle extends StatelessWidget {
  final AppState app;
  const _FloorToggle({required this.app});

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    final on = app.showFloor;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => app.setShowFloor(!on),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 13,
          height: 13,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? T.accent : T.fly,
            border: Border.all(color: on ? T.accent : T.panelSep),
            borderRadius: BorderRadius.circular(2),
          ),
          child: on
              ? const Icon(Icons.check, size: 10, color: Colors.white)
              : null,
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(t.viewFloor,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: ts(11, T.text)),
        ),
      ]),
    );
  }
}


/// M273 — the ribbon's display-mode control: the same chip as the material's,
/// one row down.
///
/// Deliberately the same shape rather than a pair of toggle buttons. Two modes
/// today, and Inventor has six; a chip that names the current one grows to a
/// third without the panel changing shape, and — more to the point — it SAYS
/// which view you are in, which two buttons only do by which of them is lit.
// M291 — SECTION VIEWS, in the panel Inventor puts them in.
//
// Inventor's View tab has Half / Quarter / Three Quarter / End Section View as
// four buttons on the Appearance panel. Here they are one chip with four
// settings, for the same reason Material and Display Mode are: this panel is a
// stack of chips, four more buttons would be the widest panel on the ribbon,
// and the four commands ARE one control — starting one while another is up
// replaces it, and "End Section View" is simply the setting called None.
//
// Flip joins them in the same flyout when a section is up. Inventor puts it on
// the right-click menu, which this app spends on the sketch context menu, and
// a command reachable only by a gesture the app does not have is a command
// that does not exist.
class _SectionChip extends StatefulWidget {
  final AppState app;
  final void Function(String id, BuildContext anchor, List<OverItem> items)
      onOpen;
  const _SectionChip({required this.app, required this.onOpen});

  @override
  State<_SectionChip> createState() => _SectionChipState();
}

class _SectionChipState extends State<_SectionChip> {
  bool _h = false;

  /// The user-visible name of a mode, from the ARB like every other string.
  String _name(AppL10n t, SectionMode? m) => switch (m) {
        null => t.sectionNone,
        SectionMode.half => t.sectionHalf,
        SectionMode.quarter => t.sectionQuarter,
        SectionMode.threeQuarter => t.sectionThreeQuarter,
      };

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    final app = widget.app;
    final on = app.canSection;
    // While a command is waiting for a plane the chip shows THAT mode, not the
    // one still applied: the user has committed to it, and the viewport is
    // asking them for a plane on its behalf.
    final cur = app.sectionArm ?? app.partSection?.mode;
    final live = app.partSection;
    final chip = Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
      decoration: BoxDecoration(
        color: (_h && on) ? T.hover7 : T.hover6,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: (_h && on) ? T.accent.withValues(alpha: 0.45) : T.border10),
      ),
      // The same floor-not-a-cap rule as the two chips above it (M235).
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 112),
          child: Text(_name(t, cur),
              softWrap: false,
              style: ts(12, !on ? T.dim : (cur == null ? T.text : T.accent))),
        ),
        const SizedBox(width: 6),
        Text('▼', style: ts(8, T.dim)),
      ]),
    );
    return MouseRegion(
      cursor: on ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: Builder(
        builder: (ctx) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: on
              ? () => widget.onOpen('ov-section', ctx, [
                    OverItem('', t.sectionNone, app.endSection,
                        active: cur == null),
                    for (final m in SectionMode.values)
                      OverItem('', _name(t, m), () => app.beginSection(m),
                          active: m == cur),
                    // Flip, one entry per plane the live section actually has.
                    // Absent while a command is still picking, because there
                    // is nothing yet to flip.
                    if (live != null)
                      OverItem(
                          '', t.sectionFlip1, () => app.flipSectionPlane(0)),
                    if (live != null && live.planes.length > 1)
                      OverItem(
                          '', t.sectionFlip2, () => app.flipSectionPlane(1)),
                  ])
              : null,
          child: chip,
        ),
      ),
    );
  }
}

class _DisplayModeChip extends StatefulWidget {
  final AppState app;
  final void Function(String id, BuildContext anchor, List<OverItem> items)
      onOpen;
  const _DisplayModeChip({required this.app, required this.onOpen});

  @override
  State<_DisplayModeChip> createState() => _DisplayModeChipState();
}

class _DisplayModeChipState extends State<_DisplayModeChip> {
  bool _h = false;

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    final app = widget.app;
    final on = app.canSetDisplayMode;
    final cur = app.displayMode;
    final chip = Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
      decoration: BoxDecoration(
        // Same glass wash as the material chip above, for the same reason.
        color: (_h && on) ? T.hover7 : T.hover6,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: (_h && on) ? T.accent.withValues(alpha: 0.45) : T.border10),
      ),
      // MainAxisSize.min and a FLOOR rather than a fixed width, for the same
      // two reasons _MaterialChip gives: the ribbon is a horizontal scrollable,
      // and M235 exists because fixed label boxes wrap or clip.
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 112),
          child: Text(displayModeName(t, cur),
              softWrap: false, style: ts(12, on ? T.text : T.dim)),
        ),
        const SizedBox(width: 6),
        Text('▼', style: ts(8, T.dim)),
      ]),
    );
    return MouseRegion(
      cursor: on ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: Builder(
        builder: (ctx) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: on
              ? () => widget.onOpen('ov-view', ctx, [
                    for (final m in DisplayMode.values)
                      OverItem('', displayModeName(t, m),
                          () => app.setDisplayMode(m),
                          active: m == cur),
                  ])
              : null,
          child: chip,
        ),
      ),
    );
  }
}
