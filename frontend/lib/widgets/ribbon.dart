// Prototype — ribbon, 1:1 port of the mock's #ribbon.
// Panel order (binding): Layer, Create, Project Geometry, Pattern, Constrain,
// Insert, Format, Modify (last). Exit panel appears top-right in edit mode.
// Home view: all panels hidden except the single "Create New Sketch" panel.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../icon_preview.dart';
import 'package:native_menu/native_menu.dart' show NativeMenu, NativeMenuItem;

import '../app_state.dart';
import '../display_mode.dart';
import '../materials.dart';
import '../l10n/l.dart';
import '../log.dart';
import '../perf.dart';
import '../menus.dart';
import '../cycles_boot.dart' show cyclesReady;
import '../render_engine.dart';
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

Widget svg(String s, double size) => iconWidget(s, size);

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
    // M359 — THE RAIL'S CONTENT SITS IN THE MIDDLE OF THE RAIL.
    //
    // "Currently the items in the ribbon are at the top. They should be
    //  centered and always use all space available."
    //
    // A scroll view shrink-wraps its child, so a rail whose panels came to 700
    // points on a 900 point screen drew them from the top and left 200 points
    // of empty glass under them. The floor puts the child at the viewport's
    // own extent so the Column has room to centre in; longer content is
    // untouched (a minimum never caps) and still scrolls.
    //
    // Vertical only, on both docks: "at the top" is a rail's main axis and a
    // band's cross axis, and both of them are this complaint. A band is not
    // centred along its WIDTH — panels reading from the leading edge is the
    // one thing every ribbon in the world agrees on.
    final content = LayoutBuilder(builder: (ctx, bc) {
      final Widget body = vertical
          ? ConstrainedBox(
              constraints: BoxConstraints(
                  minHeight: bc.hasBoundedHeight ? bc.maxHeight : 0),
              // M360 — and the rail asks its own content whether it could
              // stand in ONE column. Inside the Center, so what is measured is
              // the panels rather than the floor above, which would always
              // "fit" by construction. See [RibbonRail].
              child: Center(
                child: RibbonLabels.on
                    ? _railBody(app)
                    : _RailFit(
                        available: bc.hasBoundedHeight ? bc.maxHeight : 0,
                        child: _railBody(app),
                      ),
              ),
            )
          : _bandBody(app);
      return SingleChildScrollView(
      scrollDirection: vertical ? Axis.vertical : Axis.horizontal,
      // The band is only as wide (or tall) as the screen and its panels
      // routinely overflow, so the scroll must never be disabled by a
      // shrink-wrapped parent. Explicit physics keeps the drag alive even when
      // the content happens to fit, which is what makes the ribbon feel like a
      // strip rather than a truncated row.
      physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics()),
      clipBehavior: Clip.hardEdge,
      child: body,
    );
    });

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

  /// M371 — the Measure panel, identical in all three ribbons.
  ///
  /// Inventor puts Measure on the TOOLS tab, which every document kind has;
  /// this app's ribbon is one tab per document kind, so the panel is repeated
  /// rather than the tab. Written once here for the reason [_bandBody] exists
  /// below: three copies of one button is three places for it to drift.
  ///
  /// It LIGHTS UP while the command is running, which is the rule M210
  /// established for every modeless command's button — and it is what makes
  /// the button a toggle rather than a thing that reopens what is already
  /// open.
  Widget _measurePanel(AppState app) {
    final t = L.of(context);
    return _panel(
      label: t.panelMeasure,
      arrow: false,
      child: _BigWide(
          width: 62,
          icon: MS['measure']!,
          label: t.btnMeasure,
          active: app.measuring,
          onTap: app.toggleMeasure),
    );
  }

  /// The panels for whichever document is open. One place, so the rail and
  /// the band cannot drift apart in which ribbon they show.
  Widget _bandBody(AppState app) => app.isHome
      ? _homeRibbon(app)
      : app.currentAssembly != null
          ? _assemblyRibbon(app)
          : (app.currentPart != null && app.activeChild == null
              ? _partRibbon(app)
              : _sketchRibbon(app));

  /// The same panels, in a rail. Named apart from [_bandBody] only so the
  /// centring above reads as the one difference it is.
  Widget _railBody(AppState app) => _bandBody(app);

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
      // M352 — a compact rail PACKS, it does not stretch.
      //
      // `stretch` is right when the children are labelled rows: they are all
      // as wide as the rail anyway, so a tight cross-axis constraint is what
      // lines their words up. With the words gone the children are 32 pt
      // squares, and stretching a square to the rail's width is what put the
      // report's ragged column on screen — every cell a different shape inside
      // a box it did not fill, each one centring or not according to which
      // widget drew it.
      //
      // A Wrap instead: cells at their own size, two to a row (2 x 32 + 2 =
      // 66 in the 68 pt a compact panel offers), packed from the top-left.
      // The rail becomes a grid, which is the shape a wall of unlabelled icons
      // has to be.
      if (!RibbonLabels.on) return _wrap(children);
      return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
    }
    // M352 — and a compact BAND does not stretch either. `stretch` is what
    // several of these call sites ask for, and with names on it is right: a
    // labelled button is as tall as the panel and its word sits on the panel's
    // baseline. A 32 pt square stretched to the band's height is a square
    // drawn inside a box three times its size, which is half of "they are not
    // aligned": the cell's wash, its border and its ▾ all followed the box
    // rather than the glyph.
    //
    // M359 — CENTRED, now that centring lines up.
    //
    // M352 used `start` here because a one-row panel centred itself seven
    // points below its neighbour's: a panel with an overflow ▼ had less body
    // to centre in than one without. The title strip is reserved on every
    // compact panel now (see [_panel]), so the bodies are the same height and
    // the centres agree — which is what "they should be centered and always
    // use all space available" asks for, without giving up the one property
    // M352 bought.
    return Row(
        crossAxisAlignment:
            RibbonLabels.on ? crossAxisAlignment : CrossAxisAlignment.center,
        children: children);
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
          padding: EdgeInsets.only(left: RibbonLabels.on ? leftPad : 0),
          child: smallStack([
              for (var i = 0; i < rows.length; i++)
                  _SmallRow(
                      icon: rows[i].$1,
                      label: rows[i].$2,
                      onTap: rows[i].$3,
                      active: rows[i].$4),
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
          padding: EdgeInsets.only(left: RibbonLabels.on ? leftPad : 0),
          child: smallStack([
              for (var i = 0; i < rows.length; i++)
                  _SmallRow(
                      icon: rows[i].$1,
                      label: rows[i].$2,
                      flyId: rows[i].$4,
                      onFly: rows[i].$4 == null ? null : toggleFly,
                      onTap: rows[i].$3),
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
        // M371 — Measure, immediately before Appearance. Both are Inventor
        // TOOLS-tab commands rather than modelling ones, so they belong after
        // everything that changes the model.
        _measurePanel(app),
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
          child: _appearanceBody(app),
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
          padding: EdgeInsets.only(left: RibbonLabels.on ? leftPad : 0),
          child: smallStack([
              for (var i = 0; i < rows.length; i++)
                  _SmallRow(
                      icon: rows[i].$1,
                      label: rows[i].$2,
                      onTap: rows[i].$3,
                      active: rows[i].$4),
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
          padding: EdgeInsets.only(left: RibbonLabels.on ? leftPad : 0),
          child: smallStack([
              for (var i = 0; i < rows.length; i++)
                  _SmallRow(
                      icon: rows[i].$1,
                      label: rows[i].$2,
                      enabled: rows[i].$3 != null,
                      onTap: rows[i].$3,
                      active: rows[i].$4),
            ]),
        );
    // M247 — small rows that are BUILT, each with the drop chip its flyout
    // needs. The part ribbon's `col` in every respect but the file it is
    // written in; it cannot simply be shared because both are closures over
    // their own ribbon's `toggleFly` context.
    Widget wfCol(List<(String, String, VoidCallback, String)> rows,
            {double leftPad = 8}) =>
        Padding(
          padding: EdgeInsets.only(left: RibbonLabels.on ? leftPad : 0),
          child: smallStack([
              for (var i = 0; i < rows.length; i++)
                  _SmallRow(
                      icon: rows[i].$1,
                      label: rows[i].$2,
                      flyId: rows[i].$4,
                      onFly: toggleFly,
                      onTap: rows[i].$3),
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
        // M371 — Measure, immediately before Appearance. Both are Inventor
        // TOOLS-tab commands rather than modelling ones, so they belong after
        // everything that changes the model.
        _measurePanel(app),
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
          child: _appearanceBody(app),
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
              padding: EdgeInsets.only(left: RibbonLabels.on ? 8 : 0),
              // M352 — [smallStack], like every other column of small rows.
              // Left as a hand-rolled Column it stayed three cells DEEP in a
              // band whose cells had grown to 32, which by itself set the
              // compact top band 100 pt tall — taller than the named band it
              // replaced.
              child: smallStack([
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
                    _SmallRow(icon: IC['text18']!, label: t.btnText, flyId: 'text', onFly: toggleFly,
                        // M44: parametric sketch text — tap places, the
                        // dialog takes <Param> placeholders
                        onTap: () => _startTool(Tool.text),
                        active: app.tool == Tool.text),
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
            padding: EdgeInsets.only(left: RibbonLabels.on ? 2 : 0),
            child: smallStack([
                  _SmallRow(icon: IC['patrect']!, label: t.btnRectangular,
                      onTap: () => _startTool(Tool.patRect),
                      active: app.tool == Tool.patRect),
                  _SmallRow(icon: IC['patcirc']!, label: t.btnCircular,
                      onTap: () => _startTool(Tool.patCirc),
                      active: app.tool == Tool.patCirc),
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
            if (!RibbonLabels.on)
              // M352 — one cell, like every other command in the band.
              _CompactCell(
                glyph: svg(CN['dim']!, RibbonMetrics.compactIcon),
                tooltip: t.btnDimension,
                active: app.tool == Tool.dimension,
                onTap: () => _startTool(Tool.dimension),
              )
            else
              ConstrainedBox(
                // Was a fixed 66 and it cramped the German: "Bemaßung" asks
                // for ~94 px where "Dimension" fitted in 66, so the label
                // wrapped. A floor, like [_Big] and [_BigWide].
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
              padding: EdgeInsets.only(left: RibbonLabels.on ? 6 : 0),
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
            // M352 — through [smallStack] like every other column of small
            // rows, rather than three hand-rolled Columns: they were the last
            // panels that did not reflow with the band, so in a compact rail
            // they stayed stacks of stretched rows beside neighbours that had
            // become squares.
            smallStack([
                  _SmallRow(
                      icon: IN['image']!,
                      label: t.btnImage,
                      onTap: () => _pickImage(app)),
                  _SmallRow(
                      icon: IN['acad']!,
                      label: t.btnAcad,
                      // M117 — Import moved to the gallery "+" menu; this
                      // button stays as the in-sketch DXF drop, which is a
                      // different job: it merges geometry into the sketch you
                      // already have open.
                      onTap: () => _pickDxfIntoSketch(app)),
                ]),
            smallStack([
                  _SmallRow(
                      icon: IN['constr']!,
                      label: t.btnConstruction,
                      onTap: app.toggleConstructionSelected),
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
            smallStack([
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
        // M371 — Measure. Before Exit, which stays last: Exit is the way out
        // of the sketch and must be the rightmost thing in the band.
        _measurePanel(app),
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
      padding: EdgeInsets.only(left: RibbonLabels.on ? leftPad : 0),
      child: smallStack([
          for (var i = 0; i < keys.length; i++)
              _SmallRow(
                  icon: MD[keys[i]]!,
                  label: labels[i],
                  onTap: _modToolOf[keys[i]] == null
                      ? null
                      : () => _startTool(_modToolOf[keys[i]]!),
                  active: widget.app.tool == _modToolOf[keys[i]]),
        ]),
    );
  }

  /// M351 — the Appearance panel's five controls, in whichever shape the band
  /// is in. One method, because the part ribbon and the assembly ribbon carry
  /// the same panel and always have (M272/M292).
  ///
  /// NAMES ON: the stack of chips M272/M273/M291 built, inside an
  /// IntrinsicWidth — and that is not decoration. The ribbon is a horizontal
  /// scrollable, so this Column is laid out with an UNBOUNDED width, and
  /// `stretch` inside that is an infinite constraint rather than a layout.
  /// Intrinsic gives the chips the width of the widest, which is also what
  /// makes them line up.
  ///
  /// NAMES OFF: glyphs at the band's one size, laid out by the same
  /// [smallStack] every other panel uses — one row on a band, a column in a
  /// rail. Five chips 130 pt wide and 150 pt tall fit neither shape, which is
  /// the report this answers: "the dropdowns in Aussehen go over the edge".
  Widget _appearanceBody(AppState app) {
    final controls = <Widget>[
      _MaterialChip(app: app, onOpen: toggleOver),
      // M273 — RIGHT UNDER the material, as asked, and in the same panel
      // because they are the same question asked twice: what the body looks
      // like, and how the body is drawn.
      _DisplayModeChip(app: app, onOpen: toggleOver),
      if (app.displayMode.isRendered) ...[
        _FloorToggle(app: app),
        // M340 — and WHICH renderer draws it. Only here, only in rendered
        // mode, and only when there are two to choose from.
        if (cyclesReady) _RendererChip(onOpen: toggleOver),
      ],
      // M291/M292 — and the section view, after the two that say how the model
      // is DRAWN. It is the third question this panel answers: what colour,
      // how shaded, and how much of it you can see. The same value on both
      // document types (AppState.documentSection); what differs is which
      // solids get cut, and that is sectionedPiece's business, not this
      // panel's.
      _SectionChip(app: app, onOpen: toggleOver),
    ];
    if (!RibbonLabels.on) return smallStack(controls);
    final column = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < controls.length; i++) ...[
          if (i > 0) const SizedBox(height: 4),
          controls[i],
        ]
      ],
    );
    // M351 — and NO IntrinsicWidth in a rail. Intrinsic asks a child how wide
    // it would like to be, and a chip's label answers with the whole word —
    // which is how the named rail still overflowed by 30 px after the labels
    // themselves had been taught to ellipsise. In a rail the panel's own width
    // is the bound, and `stretch` inside it is a layout rather than an
    // infinity, so the Column can be handed over as it is.
    return RibbonDock.isVertical ? column : IntrinsicWidth(child: column);
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
    // M349 — the panel's NAME is a name too, so it goes with the others. Its
    // ▼ does NOT: that arrow is the only way to the overflow commands (see
    // the note above), and a ribbon that got thinner by making commands
    // unreachable would be a different feature. A panel with no overflow
    // therefore contributes no title row at all with names off, and one with
    // overflow keeps a bare arrow.
    final bool names = RibbonLabels.on;
    final bool hasOver = arrow || over != null;
    // M351 — and in a RAIL the title shrinks like everything else in it. A
    // long German panel name plus its ▼ ran 30 px past a 168 pt rail; the rule
    // is [_SmallRow]'s, one panel up: Flexible only where the width is
    // bounded, because a flex child under the band's unbounded width is an
    // assertion.
    final titleRow = Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      if (names)
        if (RibbonDock.isVertical)
          Flexible(
            child: Text(label,
                style: ts(12, T.dim),
                softWrap: false,
                overflow: TextOverflow.ellipsis),
          )
        else
          Text(label, style: ts(12, T.dim), softWrap: false),
      if (hasOver) ...[
        if (names) const SizedBox(width: 6),
        Text('▼', style: ts(names ? 8 : 10, T.dim)),
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
      // M352 — tighter with no names: two cells and their gap have to fit the
      // rail, and 10 a side is 8 points the rail would have to be wider for.
      padding: RibbonMetrics.panelPad,
      // A vertical rail has no [IntrinsicHeight] around the whole row of panels,
      // so each panel supplies its own bounded height for its content's
      // `stretch` rows; the panel title sits under it instead of beside it.
      child: vertical
          ? IntrinsicHeight(child: child)
          : names
              ? child
              // M352 — a panel whose child is a single cell (New Layer,
              // Project Geometry) gets it straight from the call site rather
              // than through _flow, so the Expanded below handed it a TIGHT
              // height and the 32 pt square came out 80. A min Row gives it
              // loose height again.
              // M359 — and centres it, like every other compact panel.
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [child]),
    );
    // M359 — IN A COMPACT BAND EVERY PANEL RESERVES THE SAME TITLE STRIP.
    //
    // A panel with an overflow ▼ drew one and a panel without drew nothing, so
    // their bodies were different heights — and a body centred in its own
    // height puts neighbouring cells on different lines. That was the seven
    // points M352 fixed by aligning everything to the TOP instead, which is
    // the arrangement this report is about ("currently the items are at the
    // top"). Reserving the strip costs the band nothing: its height is set by
    // the tallest panel, and the tallest panel has a title.
    final Widget titlePad = (!names && !hasOver)
        ? (vertical
            ? const SizedBox.shrink()
            : const SizedBox(height: RibbonMetrics.compactTitleH))
        : names
            ? Padding(
                padding: const EdgeInsets.only(top: 3, bottom: 5),
                child: title,
              )
            // Exactly [RibbonMetrics.compactTitleH], not "about" it: the reservation above
            // has to match to the pixel, or the panels that draw a ▼ and the
            // panels that do not end up with bodies of different heights and
            // their centred cells land on different lines — which is the fault
            // being fixed, arriving by the back door.
            : SizedBox(
                height: RibbonMetrics.compactTitleH,
                child: Center(
                    child: Tooltip(message: label, child: title)));
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
              // M352 — a compact rail does not STRETCH its cells: a panel
              // holding one button (New Layer, Project Geometry) blew it up to
              // the rail's full width while its neighbours stayed 36.
              // M359 — and it centres them rather than packing them left. A
              // panel of one cell and a panel of two are different widths, so
              // packing left put their contents on different lines down the
              // rail; centred, every panel is symmetric about the rail's own
              // centre line and the whole column reads as one.
              crossAxisAlignment: RibbonLabels.on
                  ? CrossAxisAlignment.stretch
                  : CrossAxisAlignment.center,
              children: [body, titlePad],
            )
          // M359 — the body CENTRES what it holds. Every panel now reserves
          // the same title strip, so one centred row of cells lands on the
          // same line as its neighbour's, and a two-row panel straddles it.
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

/// M352 — ONE CELL, and every control in a nameless band is one.
///
/// "They are not aligned and are very weird. It doesn't look good."
///
/// The screenshots were of the compact rail, and what they showed was five
/// different boxes stacked on top of each other. M349/M351 had taken the words
/// away and shrunk the glyphs to one size, but each control kept the FRAME it
/// was given when it had a word in it:
///
///   _Big        a 52 pt minimum with a 46 x 26 flyout pill under the glyph —
///               which with no label above it read as an empty grey lozenge.
///   _BigWide    the same 52, no pill, a different top padding (6 vs 4).
///   _SmallRow   26 pt tall, glyph + a 14 pt chip column, laid out from the
///               LEFT while its neighbours centred.
///   _ConGrid    30 pt squares, on a 1 pt gap.
///   _ValueIcon  36 pt squares, on no gap at all.
///
/// In a horizontal band that is untidy. In a rail, where `_flow` stretches
/// every child to the full width, it is what the report says: a column of
/// boxes of five widths, some centred and some not, with grey pills between
/// them.
///
/// So there is one shape now. A [RibbonMetrics.compactCell] square, a
/// [RibbonMetrics.compactIcon] glyph centred in it, the same wash and the same
/// corner radius, whatever the control underneath happens to be. A rail is
/// then a grid of identical squares — which is the only thing a wall of
/// unlabelled icons can be and still read as deliberate.
///
/// THE FLYOUT, and what it costs. M205 made the opener a chip you could see
/// and hit, because a 7.5 pt arrow in a 40x14 box was a coin toss with a
/// Pencil. That chip cannot survive here: at 46 x 26 it is bigger than the
/// cell it would hang under, and it is exactly the "empty pill" the
/// screenshots show. What replaces it is Inventor's own split-button idiom on
/// a touch device, and the trade is stated rather than hidden:
///
///   * the corner carries a small ▾, so the cell still SAYS it has a list;
///   * a tap runs the default command, as it always did;
///   * a LONG PRESS opens the list.
///
/// The list is one gesture further away than it was, and the gesture is the
/// one iOS already uses for "show me the options" everywhere else. The named
/// band is untouched: turn the names back on and M205's chip is there, at full
/// size, exactly as it was. A control whose only action IS the list (the
/// Appearance dropdowns) opens it on a plain tap, because there is no default
/// to run.
class _CompactCell extends StatefulWidget {
  /// Drawn centred at [RibbonMetrics.compactIcon]. A widget rather than an
  /// icon name because three of these are not SVGs: the Parameters "fx", the
  /// material swatch, the floor's check.
  final Widget glyph;

  /// The command's name — the only place it is written, so it is required.
  /// A picture with no name is unreachable for VoiceOver and unreadable for
  /// anyone who does not already know the glyph (M349).
  final String tooltip;

  /// The default command. Null with [onFly] set means the cell IS the opener.
  final VoidCallback? onTap;

  /// The flyout, on a long press. Given the cell's own context so the menu
  /// anchors under the cell rather than under the panel.
  final void Function(BuildContext)? onFly;

  final bool enabled;

  /// Inventor's lit state: the tool this cell starts is the running one.
  final bool active;

  const _CompactCell({
    required this.glyph,
    required this.tooltip,
    this.onTap,
    this.onFly,
    this.enabled = true,
    this.active = false,
  });

  @override
  State<_CompactCell> createState() => _CompactCellState();
}

class _CompactCellState extends State<_CompactCell> {
  bool _h = false;

  @override
  Widget build(BuildContext context) {
    final on = widget.enabled && (widget.onTap != null || widget.onFly != null);
    final lit = widget.active;
    final wash = lit || (_h && on);
    final bool fly = widget.onFly != null && widget.onTap != null;
    return Tooltip(
      message: _flat(widget.tooltip),
      // A cell whose long press OPENS something must not also pop its own
      // tooltip on that press — two things answering one gesture. Where the
      // long press is free it stays the touch way to the name, which is what
      // M349 promised when it took the words off the buttons. Hover is not
      // governed by the trigger mode, so a trackpad reads the name either way,
      // and the semantics label is untouched for VoiceOver.
      triggerMode:
          fly ? TooltipTriggerMode.manual : TooltipTriggerMode.longPress,
      child: MouseRegion(
        cursor: on ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _h = true),
        onExit: (_) => setState(() => _h = false),
        child: Builder(
          builder: (ctx) => GestureDetector(
            // Opaque, for the reason _Hover states at length: the glyph is an
            // SVG in a plain RenderBox that reports no hit, so without this
            // the cell is dead everywhere except the pixels of the drawing.
            behavior: HitTestBehavior.opaque,
            onTap: !on
                ? null
                : (widget.onTap ??
                    (widget.onFly == null ? null : () => widget.onFly!(ctx))),
            onLongPress: !on || widget.onFly == null || widget.onTap == null
                ? null
                : () => widget.onFly!(ctx),
            child: Container(
              width: RibbonMetrics.compactCell,
              height: RibbonMetrics.compactCell,
              decoration: BoxDecoration(
                color: lit
                    ? T.mbActiveBg
                    : (_h && on ? T.hover7 : Colors.transparent),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: lit
                        ? T.mbActiveOutline
                        : (wash ? T.border10 : Colors.transparent)),
              ),
              child: Stack(children: [
                Positioned.fill(
                    child: Center(child: _dimmable(widget.glyph, on))),
                // The corner ▾. Bottom-right, outside the glyph's box rather
                // than under it, so the cell keeps its size and the icon keeps
                // its centre: this is a MARK that the list exists, not a
                // target — the whole cell is the target.
                if (widget.onFly != null)
                  Positioned(
                    right: 2,
                    bottom: 0,
                    child: Text('▾',
                        style: ts(9, on ? T.dim : T.dim.withValues(alpha: 0.4),
                            height: 1.0)),
                  ),
              ]),
            ),
          ),
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

  /// M247 — every _Big on every tab is now a built command, so this no longer
  /// carries the disabled flag its siblings do. The rule it stated has moved
  /// to [_BigWide.enabled], which still needs it (assembly > Component >
  /// Create, and Relationships > Joint).
  bool get enabled => true;

  @override
  Widget build(BuildContext context) {
    // M352 — one cell, and the 46 pt pill that used to hang under the glyph
    // goes with the words that explained it. See [_CompactCell].
    if (!RibbonLabels.on) {
      return Builder(builder: (ctx) {
        return _CompactCell(
          glyph: svg(icon, RibbonMetrics.compactIcon),
          tooltip: label,
          active: active,
          enabled: enabled,
          onTap: onDefault,
          onFly: showDd && id != null && onFly != null
              ? (c) => onFly!(id!, c)
              : null,
        );
      });
    }
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
        // M349 — with no word under it, the floor is what the flyout chip
        // needs (46) plus its padding, not what a German label needed.
        constraints: BoxConstraints(
            minWidth: RibbonLabels.on ? 62 : 52),
        child: named(label, _Hover(
          activeHighlight: active,
          onTap: !enabled
              ? null
              : onDefault ??
                  (id != null && onFly != null ? () => onFly!(id!, ctx) : null),
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _dimmable(svg(icon, RibbonMetrics.bigIcon), enabled),
              if (RibbonLabels.on) ...[
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
              ],
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
        )),
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
    // M352 — the same square as everything else in a nameless band.
    if (!RibbonLabels.on) {
      return _CompactCell(
        glyph: svg(icon, RibbonMetrics.compactIcon),
        tooltip: label,
        active: active,
        enabled: enabled,
        onTap: onTap,
      );
    }
    return ConstrainedBox(
      // Same change as [_Big], same reason: [width] is the floor the English
      // layout was tuned to, not a cap the German has to fit inside.
      // M349 — and with the word gone, that floor is a 34 pt glyph's, not a
      // word's: every wide button in the ribbon is asking for room it no
      // longer uses, and eleven of them side by side is scroll nobody needs.
      constraints: BoxConstraints(minWidth: RibbonLabels.on ? width : 52),
      child: named(label, _Hover(
        onTap: enabled ? onTap : null,
        activeHighlight: active,
        child: Stack(children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 4),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Center(child: _dimmable(svg(icon, RibbonMetrics.bigIcon), enabled)),
              if (RibbonLabels.on) ...[
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
              ],
            ]),
          ),
        ]),
      )),
    );
  }
}

/// M349 — the name of a command, where the ribbon is set to write names.
///
/// One helper rather than an `if` at five call sites, because the FALLBACK is
/// the part that must not be forgotten: with the word gone the button is a
/// picture, and a picture with no name is unreachable for VoiceOver and
/// unreadable for anyone who does not already know the glyph. So the name
/// becomes a tooltip — hover on a trackpad, long press on glass — which is
/// exactly what the constraint grid has done with its twelve icon-only cells
/// since M10.
Widget named(String label, Widget button) => RibbonLabels.on
    ? button
    : Tooltip(message: _flat(label), child: button);

/// A label as ONE line, for a tooltip: the deliberate two-line labels carry a
/// '\n' that a tooltip should not honour.
String _flat(String label) => label.replaceAll('\n', ' ');


/// M349/M351 — a column of small rows, LAID FLAT when the ribbon writes no
/// names.
///
/// With names on this is exactly the Column it replaced, down to the two-point
/// gap. With names off on a HORIZONTAL band each row is a glyph and its flyout
/// chip, and stacking four of them made the band 104 pt tall to show 40 pt of
/// content — so they go in one row instead: height is the scarce axis on a
/// horizontal band and width is free, because the band scrolls sideways.
///
/// ONE row, not two. The constraint grid is the single exception, by request
/// and because twelve icons in a line would be a panel the width of the
/// screen; see [_ConGrid].
///
/// A SIDE RAIL is left alone. There the scarce axis is the other one, and
/// laying the rows out sideways would widen the very thing the compact rail
/// exists to narrow.
Widget smallStack(List<Widget> rows) {
  if (RibbonLabels.on) {
    return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 2),
            rows[i],
          ]
        ]);
  }
  // M352 — a compact RAIL wraps its cells two to a row, for the reason _flow
  // gives: the children are squares now, and a column of squares stretched to
  // the rail's width is the ragged thing the report was about.
  if (RibbonDock.isVertical) return _wrap(rows);
  // ONE row on a horizontal band, and only the constraint grid is allowed two
  // ("just on the constraint icons in the sketch mode they can be 2 rowed").
  // Twelve constraints in a line would be a panel as wide as the screen; three
  // modify commands in a line are three icons.
  return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) SizedBox(width: RibbonMetrics.compactGap),
          rows[i],
        ]
      ]);
}

/// M352/M359 — cells packed into the rail's width, on the one gap the compact
/// band uses in both directions.
///
/// M352 packed the runs from the leading edge, so every cell in the rail sat
/// on one of two columns. That is right for the FULL runs and wrong for the
/// last one: a panel with an odd number of commands left a single cell hanging
/// on the left with a hole beside it, seven times down the rail.
///
///   "always symmetrical if its possible so not 3 on the right and 1 on the
///    left just 2 and 2 for example"
///
/// So the runs are BALANCED first and centred second, and the two are not the
/// same thing. Centring alone would leave five cells as 2 + 2 + 1; balancing
/// splits them as 2 + 2 + 1 too, but seven as 3 + 2 + 2 rather than 3 + 3 + 1
/// — the tail is never more than one short of the run above it. Then each run
/// is centred, so the short one sits under the middle of the long ones instead
/// of against an edge.
Widget _wrap(List<Widget> cells) => Wrap(
      spacing: RibbonMetrics.compactGap,
      runSpacing: RibbonMetrics.compactGap,
      // The whole of the symmetry fix, in one word. A Wrap fills each run and
      // leaves the remainder in the last one, which at two cells to a run is
      // already the balanced split (2, 2, ..., 1 or 2) — what was wrong was
      // only WHERE the short run sat. Centred, it sits under the middle of the
      // runs above it instead of against the leading edge.
      //
      // A Wrap rather than the hand-rolled rows this first tried: these
      // children are not all one cell wide. The Constrain panel hands _flow
      // its Dimension button AND the entire constraint grid, and a run of
      // "two children" there is 112 points in a 68 point panel.
      alignment: WrapAlignment.center,
      runAlignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: cells,
    );

/// Where run [i] of [runs] starts, when [n] cells are shared out as evenly as
/// they go: the first `n % runs` runs take one more than the rest.
///
/// A function rather than a list because [_ConGrid] asks the same question and
/// the two must agree — a grid that balanced differently from the panel beside
/// it would be the report all over again.
int _runStart(int n, int runs, int i) {
  if (runs <= 0) return 0;
  final base = n ~/ runs;
  final extra = n % runs;
  return base * i + (i < extra ? i : extra);
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
    // M352 — a small row with no word in it is not a row, it is a cell: a
    // glyph, and a 14 pt chip column beside it that lined up with nothing its
    // neighbours drew. Same square as the rest of the band now, and the chip
    // becomes the corner mark and the long press [_CompactCell] documents.
    if (!RibbonLabels.on) {
      return _CompactCell(
        glyph: iconWidget ?? svg(icon, RibbonMetrics.compactIcon),
        tooltip: label,
        active: active,
        enabled: enabled,
        onTap: onTap,
        onFly: flyId != null && onFly != null ? (c) => onFly!(flyId!, c) : null,
      );
    }
    // M290 — the hit target may shrink in a rail, and only in a rail. It has
    // to be flexible HERE, on the outer row, or the bound never reaches the
    // label: _Hover shrink-wraps to its child's natural width, so a Flexible
    // further in has nothing to shrink against.
    final Widget hit = named(label, _Hover(
          hoverBorder: false,
          activeHighlight: active,
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                  width: RibbonMetrics.smallIcon,
                  height: RibbonMetrics.smallIcon,
                  child: Center(
                      child: _dimmable(
                          iconWidget ?? svg(icon, RibbonMetrics.smallIcon),
                          enabled))),
              // M349 — no word, no gap before it. A small row with names off
              // is a glyph and its flyout chip, which is what makes a rail
              // 76 pt wide instead of 168.
              if (RibbonLabels.on) const SizedBox(width: 6),
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
              if (!RibbonLabels.on)
                const SizedBox.shrink()
              else if (RibbonDock.isVertical)
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
        ));
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
    // M352 — Dimension is the one big button whose tap lives at its call site
    // (it shares the Constrain panel's _Hover), so the cell it becomes is
    // built there; see the Constrain panel in _sketchRibbonInner.
    return named(
        label,
        Column(mainAxisSize: MainAxisSize.min, children: [
          svg(CN['dim']!, RibbonMetrics.bigIcon),
          if (RibbonLabels.on) ...[
            const SizedBox(height: 3),
            Text(label,
                style: ts(11.5, T.text),
                textAlign: TextAlign.center,
                softWrap: false),
          ],
        ]));
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

  /// M352 — the compact cell IS the compact button now.
  ///
  /// M351 held this at 30 against the band's 32, because two 32 pt squares and
  /// their gap did not fit the rail's 62 pt of content. M352 makes the rail's
  /// panel padding tighter (6 a side instead of 10), so 68 is what a compact
  /// panel offers and 2 x 32 + 2 fits it — which is how the grid finally draws
  /// the SAME square as its neighbours instead of one that is two points off.
  static double get _compactCell => RibbonMetrics.compactCell;

  /// M349 — the grid reflows when the names are off, because it is what the
  /// band's size is actually made of.
  ///
  /// Measured: with names on, a top band is 112 pt tall and this grid is 84 of
  /// them (three rows of 28). Hiding the words under the buttons alone took
  /// the band to 105 — seven points, which is not "thinner", it is a rounding
  /// error. The grid is the tallest thing in the sketch ribbon and it has to
  /// move with the rest.
  ///
  /// So: on a horizontal band the twelve cells go SIX wide and two deep, which
  /// trades width (free — the band scrolls sideways) for height (the whole
  /// point). In a compact side rail they go TWO wide, because there the
  /// scarce axis is the other one: four columns are 123 pt and the compact
  /// rail is 88.
  /// M352 — the same gap the rest of the compact band leaves between two
  /// cells. It was 1 here and 2 everywhere else, which is exactly the kind of
  /// difference that reads as "not aligned" without being nameable.
  double get _gap => RibbonLabels.on ? 1 : RibbonMetrics.compactGap;

  int get _cols => RibbonLabels.on
      ? 4
      : RibbonDock.isVertical
          ? 2
          : 6;

  Widget _cell((String, String) c) {
    // M352 — the grid was already the one panel that drew icon-only cells, and
    // it is now the shape the whole compact band copies rather than a shape of
    // its own.
    if (!RibbonLabels.on) {
      return _CompactCell(
        glyph: svg(CN[c.$1]!, RibbonMetrics.compactIcon),
        tooltip: c.$2,
        active: _isActive(c.$1),
        onTap: () => _tap(c.$1),
      );
    }
    return Tooltip(
      message: c.$2,
      child: SizedBox(
        width: 30,
        height: 27,
        child: _Hover(
            hoverBg: T.hover7,
            activeHighlight: _isActive(c.$1),
            onTap: () => _tap(c.$1),
            child: Center(child: svg(CN[c.$1]!, RibbonMetrics.smallIcon))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The row count is DERIVED from `cons` and every cell is bounds-checked.
    // (A hard-coded 3x5 grid survived the removal of the 'autodim' cell in
    // M10c: cons went 15 -> 14, cons[14] threw RangeError on every build, the
    // ErrorWidget expanded to the full viewport height and pushed the model
    // browser, the viewport and the tab bar off screen. Never index a fixed
    // grid into a variable-length list again.)
    final cons = consOf(L.of(context));
    final cols = _cols;
    final rows = (cons.length + cols - 1) ~/ cols;
    // M359 — BALANCED ROWS, and the short one CENTRED.
    //
    // Eleven cells over six columns used to be a row of six and a row of five
    // hanging off the left, with a blank cell drawn to hold the sixth place.
    // In a two-column rail the same rule gave five rows of two and a lone cell
    // on the left — "not 3 on the right and 1 on the left". They are shared
    // out evenly now (six and five, or two-two-two-two-two-one), and every row
    // is centred under the one above it, so a panel of constraints reads as a
    // block rather than as a shape with a corner missing.
    //
    // M360 — and in a compact RAIL it hands its cells to the same [_wrap]
    // every other panel uses. Two reasons, and the second is the load-bearing
    // one: the rail's width is chosen by asking the content how tall it would
    // be in one column, and only a Wrap can answer that. A hand-laid grid of
    // rows reports the height of the row count it was BUILT with, which makes
    // the measurement depend on the answer.
    if (!RibbonLabels.on && RibbonDock.isVertical) {
      return _wrap([for (final c in consOf(L.of(context))) _cell(c)]);
    }
    // Named mode keeps its blank: three rows of four with a hole in the last
    // is what the labelled grid has looked like since M10, and the words on
    // the panels beside it are what that grid lines up against.
    final bal = !RibbonLabels.on;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var row = 0; row < rows; row++)
          Padding(
            padding: EdgeInsets.only(top: row == 0 ? 0 : _gap),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: bal
                  ? [
                      for (var j = _runStart(cons.length, rows, row);
                          j < _runStart(cons.length, rows, row + 1);
                          j++) ...[
                        if (j > _runStart(cons.length, rows, row))
                          SizedBox(width: _gap),
                        _cell(cons[j]),
                      ],
                    ]
                  : [
                      for (var col = 0; col < cols; col++)
                        Padding(
                          padding: EdgeInsets.only(left: col == 0 ? 0 : _gap),
                          child: (row * cols + col) < cons.length
                              ? _cell(cons[row * cols + col])
                              : const SizedBox(width: 30, height: 27),
                        ),
                    ],
            ),
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

/// M351 — an Appearance control in a band that writes no names.
///
/// "The dropdowns in Aussehen have to be redesigned with icons because they go
/// over the edge currently." They did, and by a lot: the material chip is a
/// swatch plus a 90 pt label plus a ▼, the display-mode chip a 112 pt label,
/// and five of them stacked make a panel 150 pt tall in a band that is 80 —
/// and 130 pt wide in a rail that is 88.
///
/// So in the compact band each of them is what every other control in that
/// band is: one glyph at [RibbonMetrics.compactIcon], in a box of
/// [RibbonMetrics.compactButton]. What is lost is the VALUE written out, and
/// it comes back two ways — the glyph itself says it where there are only two
/// or three (the display mode, the section, the material's own colour), and
/// the tooltip names the control and its current setting for the rest.
///
/// The chip's own hover wash and border are kept, because they are what says
/// "this opens something" once the ▼ has gone.
class _ValueIcon extends StatefulWidget {
  final Widget glyph;

  /// "Aussehen: Aluminium" — the control AND what it is set to, because the
  /// glyph can only carry one of the two.
  final String tooltip;
  final bool enabled;

  /// Lit, for the two controls that are a state rather than a choice: the
  /// floor, and a section that is up.
  final bool active;
  final void Function(BuildContext) onTap;

  const _ValueIcon({
    required this.glyph,
    required this.tooltip,
    required this.onTap,
    this.enabled = true,
    this.active = false,
  });

  @override
  State<_ValueIcon> createState() => _ValueIconState();
}

/// M352 — and it is [_CompactCell], like everything else in the band.
///
/// M351 gave it a resting fill and a border, to say "this opens something"
/// once the ▼ had gone. That made the five Appearance controls the only lit
/// boxes in a band of bare glyphs — the report's "very weird", in the one
/// panel that had five of them in a row. The corner ▾ says the same thing
/// without a frame, and it says it the same way a split button does.
class _ValueIconState extends State<_ValueIcon> {
  @override
  Widget build(BuildContext context) => _CompactCell(
        glyph: widget.glyph,
        tooltip: widget.tooltip,
        enabled: widget.enabled,
        active: widget.active,
        // No default command: the list IS what this control does, so a plain
        // tap opens it (see [_CompactCell]).
        onFly: (ctx) => widget.onTap(ctx),
      );
}

/// M351 — the label inside an Appearance chip, in a shape its box can hold.
///
/// The four chips gave their label a FLOOR (90 pt for the material, 112 for
/// the display mode and the renderer) and switched soft wrapping off, which is
/// exactly right in the horizontal band: it is a scrollable of unbounded
/// width, so a floor costs scroll and never layout (M235).
///
/// A SIDE RAIL is bounded, and 168 pt of rail minus the panel's 20 pt of
/// padding cannot hold a 150 pt chip: the named rail overflowed by up to 115
/// pixels — "the dropdowns in Aussehen go over the edge". So there the label
/// shrinks and ellipsises instead, which is the rule [_SmallRow] has followed
/// since M290 and for the same reason. Flexible ONLY in the rail: a flex child
/// under the band's unbounded width is an assertion, not a layout.
Widget chipLabel(String text, TextStyle style, {required double floor}) =>
    RibbonDock.isVertical
        ? Flexible(
            child: Text(text,
                style: style, softWrap: false, overflow: TextOverflow.ellipsis))
        : ConstrainedBox(
            constraints: BoxConstraints(minWidth: floor),
            child: Text(text, softWrap: false, style: style),
          );

/// M272 — one appearance, as a filled disc.
///
/// A ring around it, and it is not decoration: Aluminium on the light palette
/// and Graphite on the dark one are both within a few percent of the menu's
/// own ground, and without an edge the swatch simply disappears on the one row
/// where the user most needs to see it.
class _Swatch extends StatelessWidget {
  final int argb;

  /// M351 — bigger in the compact band, where the swatch is not a bullet
  /// beside a word but the control's whole glyph.
  final double? size;
  const _Swatch({required this.argb, this.size});

  static const double defaultSize = 14;

  @override
  Widget build(BuildContext context) => Container(
        width: size ?? defaultSize,
        height: size ?? defaultSize,
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
    // M351 — compact: the swatch, which is this control's value anyway. No
    // icon had to be drawn for it, and none should be: the appearance IS a
    // colour.
    if (!RibbonLabels.on) {
      return _ValueIcon(
        glyph: _Swatch(
            argb: materialArgb(cur) ?? T.solid.toARGB32(),
            // The band's ONE icon size, like every glyph beside it: the disc
            // is not a bullet before a word any more, it is the icon.
            size: RibbonMetrics.compactIcon),
        tooltip: '${t.panelAppearance}: '
            '${on ? materialName(t, cur) : t.matPickBody}',
        enabled: on,
        onTap: (ctx) => widget.onOpen('ov-material', ctx, _items(t)),
      );
    }
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
        chipLabel(on ? materialName(t, cur) : t.matPickBody,
            ts(12, on ? T.text : T.dim),
            floor: 90),
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
    // M351 — compact: the same glyph as a button, lit when the floor is there.
    // A 13 pt checkbox with a word beside it is the one shape in this panel
    // that has no icon form of its own, so it takes the panel's.
    if (!RibbonLabels.on) {
      return _ValueIcon(
        glyph: svg(VW['floor']!, RibbonMetrics.compactIcon),
        tooltip: t.viewFloor,
        active: on,
        onTap: (_) => app.setShowFloor(!on),
      );
    }
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
    List<OverItem> items() => [
          OverItem('', t.sectionNone, app.endSection, active: cur == null),
          for (final m in SectionMode.values)
            OverItem('', _name(t, m), () => app.beginSection(m),
                active: m == cur),
          // Flip, one entry per plane the live section actually has. Absent
          // while a command is still picking, because there is nothing yet to
          // flip.
          if (live != null)
            OverItem('', t.sectionFlip1, () => app.flipSectionPlane(0)),
          if (live != null && live.planes.length > 1)
            OverItem('', t.sectionFlip2, () => app.flipSectionPlane(1)),
        ];
    // M351 — compact: one glyph, LIT while a section is up. Which of the three
    // section kinds it is does not fit in an icon and does not need to: the
    // viewport is showing it, and the tooltip names it.
    if (!RibbonLabels.on) {
      return _ValueIcon(
        glyph: svg(VW['section']!, RibbonMetrics.compactIcon),
        tooltip: '${t.panelAppearance}: ${_name(t, cur)}',
        enabled: on,
        active: cur != null,
        onTap: (ctx) => widget.onOpen('ov-section', ctx, items()),
      );
    }
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
        chipLabel(_name(t, cur),
            ts(12, !on ? T.dim : (cur == null ? T.text : T.accent)),
            floor: 112),
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
          onTap: on ? () => widget.onOpen('ov-section', ctx, items()) : null,
          child: chip,
        ),
      ),
    );
  }
}

/// M340 — WHICH RENDERER draws the rendered view, under the mode that turns it
/// on.
///
/// Shown only while [DisplayMode] is rendered, exactly like the floor toggle
/// above it and for the same reason: the working views do not path-trace
/// anything, so in them this is a control that does nothing. And shown only
/// when there IS a second renderer — a build with no Cycles in it, or a device
/// whose libraries did not load, offers no choice, and a chip with one entry
/// is a worse way of saying that than no chip at all.
///
/// The same chip shape as Material, Display Mode and Section rather than a
/// pair of buttons, for the reason _DisplayModeChip gives: it SAYS which
/// renderer you are on, which two lit buttons only do by which of them is lit.
///
/// It does not go dim while Cycles is still compiling its kernels. Switching
/// TO Cycles during the warm-up is exactly when you would want to — the layer
/// puts up the progress panel and the render starts when it can — and a
/// control that silently refuses for thirty seconds is worse than one that
/// works and tells you to wait.
class _RendererChip extends StatefulWidget {
  final void Function(String id, BuildContext anchor, List<OverItem> items)
      onOpen;
  const _RendererChip({required this.onOpen});

  @override
  State<_RendererChip> createState() => _RendererChipState();
}

class _RendererChipState extends State<_RendererChip> {
  bool _h = false;

  /// The user-visible name of a renderer. In the ARB, like every other string
  /// — the enum's own ids are 'realitykit'/'cycles' and are storage keys.
  String _name(AppL10n t, RenderEngine e) => switch (e) {
        RenderEngine.realityKit => t.rendererRealtime,
        RenderEngine.cycles => t.rendererRaytraced,
      };

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    final cur = RenderEngines.current;
    List<OverItem> items() => [
          for (final e in RenderEngine.values)
            OverItem('', _name(t, e), () {
              RenderEngines.set(e);
              // This rebuilds the LABEL. The viewport rebuilds itself:
              // RenderEngines.engine is a ValueNotifier and CyclesLayer
              // listens to it, the same way it listens to the warm-up.
              if (mounted) setState(() {});
            }, active: e == cur),
        ];
    // M351 — compact: an aperture, lit while the path tracer is the one
    // drawing (which is what the accent-coloured name said before).
    if (!RibbonLabels.on) {
      return _ValueIcon(
        glyph: svg(VW['engine']!, RibbonMetrics.compactIcon),
        tooltip: '${t.panelAppearance}: ${_name(t, cur)}',
        active: cur == RenderEngine.cycles,
        onTap: (ctx) => widget.onOpen('ov-renderer', ctx, items()),
      );
    }
    final chip = Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
      decoration: BoxDecoration(
        color: _h ? T.hover7 : T.hover6,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: _h ? T.accent.withValues(alpha: 0.45) : T.border10),
      ),
      // A floor, not a fixed width, like every other chip in this panel (M235).
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        chipLabel(_name(t, cur),
            ts(12, cur == RenderEngine.cycles ? T.accent : T.text),
            floor: 112),
        const SizedBox(width: 6),
        Text('\u25BC', style: ts(8, T.dim)),
      ]),
    );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: Builder(
        builder: (ctx) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onOpen('ov-renderer', ctx, items()),
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
    List<OverItem> items() => [
          for (final m in DisplayMode.values)
            OverItem('', displayModeName(t, m), () => app.setDisplayMode(m),
                active: m == cur),
        ];
    // M351 — compact: the mode's own glyph, so the band still SAYS which view
    // you are in — which is the whole reason this is a chip and not two
    // buttons (M273).
    if (!RibbonLabels.on) {
      return _ValueIcon(
        glyph: svg(VW[cur.isRendered ? 'rendered' : 'shaded']!,
            RibbonMetrics.compactIcon),
        tooltip: '${t.panelAppearance}: ${displayModeName(t, cur)}',
        enabled: on,
        onTap: (ctx) => widget.onOpen('ov-view', ctx, items()),
      );
    }
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
        chipLabel(displayModeName(t, cur), ts(12, on ? T.text : T.dim),
            floor: 112),
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
          onTap: on ? () => widget.onOpen('ov-view', ctx, items()) : null,
          child: chip,
        ),
      ),
    );
  }
}

/// M360 — the rail, asking its own panels whether they would fit in ONE
/// column, and publishing the answer.
///
/// A render object because the question is a layout question: `Wrap` can say
/// how tall it would be at a given width, and that is exactly what
/// "under each other" means — every cell on its own run, at one cell's width.
/// The query runs at that fixed width whatever the rail is currently drawing,
/// which is what makes the answer the same in both states and therefore
/// stable; see [RibbonRail] for the oscillation this avoids.
///
/// [available] is passed in rather than read off `constraints`: this sits
/// inside the scroll view, so its own maximum height is unbounded. The
/// LayoutBuilder outside the scroll view is where the screen's height is
/// known.
class _RailFit extends SingleChildRenderObjectWidget {
  final double available;
  const _RailFit({required this.available, required Widget child})
      : super(child: child);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderRailFit(available);

  @override
  void updateRenderObject(BuildContext context, _RenderRailFit r) =>
      r.available = available;
}

class _RenderRailFit extends RenderProxyBox {
  double _available;
  _RenderRailFit(this._available);

  set available(double v) {
    if (v == _available) return;
    _available = v;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final c = child;
    if (c == null || _available <= 0) {
      super.performLayout();
      return;
    }
    // One column's worth of content: a single cell, which is what a panel
    // offers inside RibbonMetrics.railWidthCompact1.
    final one = c.getMaxIntrinsicHeight(RibbonMetrics.compactCell);
    RibbonRail.publish(one <= _available ? 1 : 2);
    super.performLayout();
  }
}
