// Prototype — mounts the native browser and routes its events (M107).
//
// On iOS the panel is UIKit on Liquid Glass; everywhere else the original
// Flutter tree is used unchanged, so the desktop/host-test path keeps working
// and nothing here can regress it.
import 'package:flutter/material.dart';
import 'package:native_menu/native_menu.dart';

import '../app_state.dart';
import '../asm_constraints.dart';
import '../assembly.dart';
import '../menus.dart';
import '../log.dart';
import '../part_model.dart';
import '../theme.dart';
import 'model_browser.dart';
import 'native_browser.dart';
import 'native_prompts.dart';
import '../l10n/l.dart';

class NativeModelBrowser extends StatefulWidget {
  final AppState app;
  const NativeModelBrowser({super.key, required this.app});

  /// Total width the panel claims at the left edge when EXPANDED, card plus
  /// retract strip.
  static const double occupiedWidth = 264 + 24;

  /// M207 — what the panel claims RIGHT NOW, which is what the coordinate
  /// triad follows.
  ///
  /// M146 pinned the triad to the expanded width on purpose, reasoning that
  /// "a triad that slid sideways every time the browser collapsed would be
  /// worse than one standing a little clear of it". The device disagrees:
  /// "when the model browser retracts, the triad should also go to the left."
  /// Retracting the browser is a deliberate act to get the corner back, and a
  /// triad hovering in open space 288 points from the edge reads as a thing
  /// that was left behind rather than one that is standing clear.
  ///
  /// A notifier rather than app state: this is pure chrome geometry, the same
  /// shape as [RibbonMetrics.bottom], and it must not end up in a document.
  static final ValueNotifier<double> occupied =
      ValueNotifier<double>(occupiedWidth);

  @override
  State<NativeModelBrowser> createState() => _NativeModelBrowserState();
}

class _NativeModelBrowserState extends State<NativeModelBrowser> {
  /// Which folders/features are open. Purely presentational, so it lives here
  /// rather than on the document.
  final Set<String> _expanded = {'bodies'};

  /// In-flight End of Part drag: the slot it started from, and the live one.
  int? _eopStart;
  int? _dragEop;

  /// M118 — retracted to icons only.
  ///
  /// M242 — and RETRACTED IS THE DEFAULT, in every document kind. The panel is
  /// 264 pt of a 1024 pt screen and the thing being drawn is the point of the
  /// app; the retracted card keeps every id, glyph, tint and menu (that is
  /// what [buildBrowserRows]'s `collapsed` pass is for, M200), so nothing is
  /// unreachable — it costs one tap on the chevron to have the labels back.
  bool _collapsed = true;

  static const double _kWide = 264;
  /// M121 — retracted width. The card keeps its 28 pt left inset, so 62 left
  /// only ~34 pt of content and the 16 pt glyphs were clipped against the
  /// cell's own leading margin. 78 gives the icon column real room while still
  /// reading as "retracted".
  ///
  /// M204 — 78 -> 56. "the expand arrow is too much to the right." Since M199
  /// took the glass away there is nothing behind the retracted panel: what is
  /// left is a 16 pt glyph column, and 78 pt of it was 40 pt of empty air with
  /// the chevron parked out past all of it. 14 of card inset + 16 of glyph
  /// leaves the strip sitting just clear of the icons, which is where the eye
  /// looks for it. The wide panel is untouched.
  static const double _kNarrow = 56;

  /// M119 — the chevron lives OUTSIDE the glass, in a strip beside it, and
  /// only shows when the pointer is near the panel. A handle permanently
  /// stuck to a CAD panel is visual noise; you look for it when you want it.
  static const double _kHandle = 24;
  bool _near = false;

  /// True once a hovering pointer has been seen. Until then this is a
  /// touch-only session and the handle stays visible — hiding it behind hover
  /// on a device that never hovers would make it unreachable.
  bool _hasHover = false;

  AppState get app => widget.app;

  @override
  void initState() {
    super.initState();
    // The triad is positioned against NativeModelBrowser.occupiedWidth, which
    // cannot see these private metrics. Keep the two in step here rather than
    // discovering the drift as a triad sitting on the panel.
    assert(NativeModelBrowser.occupiedWidth == _kWide + _kHandle);
    // M242 — the panel opens RETRACTED, so the triad has to be told the narrow
    // width before the first frame rather than after the first toggle.
    // occupiedWidth (the expanded figure) is what the notifier starts on.
    _publishWidth();
  }

  /// M207 — tell the triad how much room the panel is taking. Deferred: this
  /// runs from build and from setState, and a notifier fired mid-build would
  /// rebuild a listener that has already been laid out this frame.
  void _publishWidth() {
    final w = (_collapsed ? _kNarrow : _kWide) + _kHandle;
    if (NativeModelBrowser.occupied.value == w) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NativeModelBrowser.occupied.value = w;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!GlassBrowser.isSupported) return ModelBrowser(app: app);
    return AnimatedBuilder(
      animation: app,
      builder: (_, __) => MouseRegion(
        onEnter: (_) => setState(() {
          _near = true;
          _hasHover = true;
        }),
        onExit: (_) => setState(() => _near = false),
        child: AnimatedContainer(
        // M118 — retracts to the timeline icons. Animated so the panel reads
        // as one object sliding, not two states swapping.
        //
        // M204 — THE SLIDE IS GONE. "when its retracted i cant use the icons",
        // and bug20260805T131020 has not one browser event in it: the panel
        // draws, the icons are there, and no touch reaches Dart.
        //
        // The card is a UiKitView. Resizing one is not a layout change on the
        // Dart side — RenderUiKitView hands the new size to the platform view
        // controller and AWAITS the native resize, and the widget keeps
        // reporting the old geometry until that returns. Animating the width
        // fires that round trip on every frame of a 220 ms curve, so a dozen
        // resizes are in flight at once and the last one to land wins, which
        // need not be the last one sent. Flutter still paints the view's
        // texture at the widget's size, so a stale native frame is invisible:
        // you see icons where the touch interceptor no longer is, and the taps
        // go nowhere.
        //
        // One state change, one resize, no race. The cost is that the panel
        // snaps rather than slides — a fair trade for a panel you can press.
        // (The chevron still rotates; that is Flutter's own layer.)
        duration: Duration.zero,
        curve: Curves.easeOutCubic,
        // The strip is part of the widget's width so the handle sits BESIDE
        // the card, never over it.
        width: (_collapsed ? _kNarrow : _kWide) + _kHandle,
        child: Stack(children: [
        // M120 — the card ends WHERE THE STRIP BEGINS. Sizing it by width let
        // it run under the handle, and a Flutter GestureDetector on top of a
        // platform view swallows the touch: tapping a folder's disclosure
        // chevron hit the retract strip instead and collapsed the panel. With
        // `right: _kHandle` the two cannot overlap by construction.
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          right: _kHandle,
        child: GlassBrowser(
          // M199 — retracted, the panel is icons over the model and nothing
          // else: the glass goes with the labels.
          glass: !_collapsed,
          rows: buildBrowserRows(app,
              expanded: _expanded, dragEop: _dragEop, collapsed: _collapsed),
          onTap: _onTap,
          onEye: _onEye,
          onExpand: (id, on) => setState(() {
            Log.i('browser', 'expand $id on=$on');
            if (on) {
              _expanded.add(id);
            } else {
              _expanded.remove(id);
            }
          }),
          onMenu: _onMenu,
          onEopDrag: _onEopDrag,
          onEopEnd: _onEopEnd,
        ),
        ),
        // The handle: a chevron in the strip beside the card. Tap toggles; a
        // horizontal swipe on it does the same, in the direction you swipe —
        // the panel should obey the gesture you would try first. It fades in
        // when the pointer comes near, and on touch-only devices (no hover
        // events at all) it stays visible so it is never unreachable.
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: _kHandle,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: (!_hasHover || _near) ? 1 : 0,
            child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() {
              _collapsed = !_collapsed;
              _publishWidth();
            }),
            onHorizontalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v.abs() < 50) return;
              setState(() {
                _collapsed = v < 0;
                _publishWidth();
              });
            },
            child: Center(
              child: AnimatedRotation(
                duration: const Duration(milliseconds: 220),
                turns: _collapsed ? 0.5 : 0,
                child: Icon(Icons.chevron_left,
                    size: 18, color: T.dim),
              ),
            ),
          ),
          ),
        ),
        ]),
      ),
      ),
    );
  }

  // -- events ---------------------------------------------------------------

  void _onTap(String id) {
    // M204 — every native browser event is logged from here on.
    //
    // "when its retracted i cant use the icons" could not be answered from the
    // report: nothing in this panel wrote a line, so an empty log was equally
    // consistent with "the touch never arrived" and with "it arrived and the
    // handler did nothing". One line per event settles that next time, and it
    // is one line per deliberate tap, not per frame.
    Log.i('browser', 'tap $id (collapsed=$_collapsed)');
    // M205 — the tree is a UIKit view, so its tap comes back over a method
    // channel rather than as a pointer the Flutter barriers can see. A tap in
    // here while a ribbon flyout is open is still a click somewhere else.
    OpenMenus.closeAll();
    final part = app.currentPart;
    // M121 — tapping a FOLDER row toggles it, not just its little chevron.
    // The chevron is a 20 pt target on a 264 pt row; every file browser on
    // this platform lets you hit the row itself.
    if (id == 'bodies' ||
        id == 'origin' ||
        id == kIdRepresentations ||
        id == kIdRelationships) {
      setState(() {
        if (!_expanded.remove(id)) _expanded.add(id);
      });
      return;
    }
    if (id == 'root') return; // the document row is a label, not an action
    // M240 — tapping a component SELECTS it, which is the same selection the
    // assembly viewport highlights and drags. Tapping the selected one again
    // clears it, so there is a way back to "nothing picked" without having to
    // find empty space in the viewport.
    if (id.startsWith(kIdComponent)) {
      final o = _component(id);
      if (o != null) {
        // M242 — a component with relationships under it is a folder as well
        // as a selection. Selecting it and disclosing it are the same tap,
        // which is what the Origin folder already does one row above.
        if (app.currentAssembly?.constraintsOn(o.id).isNotEmpty == true) {
          setState(() {
            if (!_expanded.remove(id)) _expanded.add(id);
          });
        }
        app.selectOccurrence(
            identical(app.currentAssembly?.selected, o) ? null : o);
      }
      return;
    }
    // M242 — tapping a relationship SELECTS it; tapping the selected one
    // again OPENS it. There is no double-click on this tree (it is a UIKit
    // list reporting single taps), so "tap the selected one again" is the
    // gesture that stands in for Inventor's double-click-to-edit — the same
    // rule the component row already uses to clear its own selection.
    if (id.startsWith(kIdConstraint)) {
      final c = _constraint(id);
      if (c == null) return;
      if (identical(app.currentAssembly?.selectedConstraint, c)) {
        app.openConstraint(edit: c);
      } else {
        app.selectConstraint(c);
      }
      return;
    }
    if (id.startsWith(kIdBody) && app.pickingBody) {
      app.pickBody(id.substring(kIdBody.length));
      return;
    }
    if (id.startsWith(kIdLayer)) {
      app.enterEdit(id.substring(kIdLayer.length));
      return;
    }
    // M169 — tapping a work plane SELECTS it, the way Inventor does: the
    // plane highlights in 3D and its offset field opens, so the value is
    // immediately editable without hunting for a menu.
    if (id.startsWith(kIdWorkPlane)) {
      final w = _workPlane(part, id);
      if (w != null) {
        app.selectWorkPlane(w);
        if (w.offsetEditable) app.workPlaneOffsetEditing = true;
      }
      return;
    }
    // M215 — tapping a work axis or point SELECTS it, the way a work plane
    // does: it highlights in 3D so you can see which row is which.
    if (id.startsWith(kIdWorkAxis)) {
      app.selectWorkAxis(_workAxis(part, id));
      return;
    }
    if (id.startsWith(kIdWorkPoint)) {
      app.selectWorkPoint(_workPoint(part, id));
      return;
    }
    if (id.startsWith(kIdSketch) || id.startsWith(kIdNested)) {
      final n = id.startsWith(kIdNested)
          ? id.substring(kIdNested.length)
          : id.substring(kIdSketch.length);
      // M212 — while a sketch-driven pattern is asking for its points, a tap
      // on a sketch row PICKS that sketch instead of opening it.
      final cs = part?.sketchByName(n);
      if (cs != null && app.patternToggleSketch(cs)) return;
      app.openChildSketch(n);
      return;
    }
    if (id.startsWith(kIdFeature) && part != null) {
      final f = _feature(part, id.substring(kIdFeature.length));
      if (f == null) return;
      // M212 — while a pattern panel is waiting for features, a tap on a
      // feature row PICKS it. Opening its editor as well would close the
      // panel that asked for it.
      if (app.patternToggleFeature(f)) return;
      // M131 — dispatches by feature kind, so the native browser edits
      // fillets, chamfers and revolves too, not just extrusions.
      app.editFeature(f);
    }
  }

  void _onEye(String id) {
    Log.i('browser', 'eye $id');
    final part = app.currentPart;
    if (id.startsWith(kIdComponent)) {
      final o = _component(id);
      if (o != null) app.setOccurrenceVisible(o, !o.visible);
    } else if (id.startsWith(kIdLayer)) {
      app.toggleLayerVisible(id.substring(kIdLayer.length));
    } else if (id.startsWith(kIdOrigin)) {
      // M240 — the same seven keys drive an assembly's origin as a part's, so
      // the row id is identical and only the model behind it differs.
      final asm = app.currentAssembly;
      final key = id.substring(kIdOrigin.length);
      if (asm != null) {
        app.setAssemblyOriginVisible(key, asm.vis[key] != true);
      } else {
        app.togglePartOriginVis(key);
      }
    } else if (id.startsWith(kIdBody) && part != null) {
      app.toggleBodyVisible(part, id.substring(kIdBody.length));
    } else if (id.startsWith(kIdFeature) && part != null) {
      final f = _feature(part, id.substring(kIdFeature.length));
      if (f != null) app.toggleFeatureVisible(f);
    } else if (id.startsWith(kIdWorkPlane)) {
      final w = _workPlane(part, id);
      if (w != null) app.toggleWorkPlaneVisible(w);
    } else if (id.startsWith(kIdWorkAxis)) {
      final a = _workAxis(part, id);
      if (a != null) app.toggleWorkAxisVisible(a);
    } else if (id.startsWith(kIdWorkPoint)) {
      final pt = _workPoint(part, id);
      if (pt != null) app.toggleWorkPointVisible(pt);
    } else if (id.startsWith(kIdSketch) || id.startsWith(kIdNested)) {
      final n = id.startsWith(kIdNested)
          ? id.substring(kIdNested.length)
          : id.substring(kIdSketch.length);
      final cs = part?.sketchByName(n);
      if (cs != null) app.toggleSketchVisible(cs);
    }
  }

  // M215 — 'wp:' and 'wpt:' cannot collide: startsWith('wp:') compares the
  // third character against ':' and a work point has 't' there. Checked
  // rather than assumed, because a silent prefix collision here would route
  // every work point tap into the work plane branch.
  /// The occurrence a `cp:` row addresses. The id after the prefix is the
  /// occurrence id WHOLE — it contains a colon of its own ("Bracket:1"), so it
  /// must never be split on one.
  AssemblyOccurrence? _component(String rowId) =>
      app.currentAssembly?.byId(rowId.substring(kIdComponent.length));

  /// The relationship a `rel:` row addresses. Same rule as [_component]: the
  /// name after the prefix carries a colon of its own ("Mate:1").
  AsmConstraint? _constraint(String rowId) =>
      app.currentAssembly?.constraintNamed(
          rowId.substring(kIdConstraint.length));

  WorkAxis? _workAxis(PartModel? part, String rowId) {
    final seq = int.tryParse(rowId.substring(kIdWorkAxis.length));
    if (part == null || seq == null) return null;
    for (final a in part.workAxes) {
      if (a.seq == seq) return a;
    }
    return null;
  }

  WorkPoint? _workPoint(PartModel? part, String rowId) {
    final seq = int.tryParse(rowId.substring(kIdWorkPoint.length));
    if (part == null || seq == null) return null;
    for (final pt in part.workPoints) {
      if (pt.seq == seq) return pt;
    }
    return null;
  }

  WorkPlane? _workPlane(PartModel? part, String rowId) {
    final seq = int.tryParse(rowId.substring(kIdWorkPlane.length));
    if (part == null || seq == null) return null;
    for (final w in part.workPlanes) {
      if (w.seq == seq) return w;
    }
    return null;
  }

  Future<void> _onMenu(String id, String item) async {
    Log.i('browser', 'menu $id -> $item');
    final part = app.currentPart;
    if (id.startsWith(kIdComponent)) {
      final o = _component(id);
      if (o == null) return;
      switch (item) {
        case 'cpGrounded':
          app.setOccurrenceGrounded(o, !o.grounded);
          break;
        case 'cpDelete':
          app.deleteOccurrence(o);
          break;
      }
      return;
    }
    if (id.startsWith(kIdConstraint)) {
      final c = _constraint(id);
      if (c == null) return;
      switch (item) {
        case 'relEdit':
          app.openConstraint(edit: c);
          break;
        case 'relSuppress':
          app.toggleConstraintSuppressed(c);
          break;
        case 'relDelete':
          app.deleteConstraint(c);
          break;
      }
      return;
    }
    if (id == kIdEop && part != null) {
      switch (item) {
        case 'eoptop':
          app.setEndOfPart(0);
          break;
        case 'eopend':
          app.setEndOfPart(partTimeline(part).length);
          break;
        case 'eopDeleteBelow':
          // M182 — this permanently removes every feature below the marker;
          // the Flutter fallback has always confirmed, the native menu did
          // not. Ask first, like every other destructive row here.
          _confirmDeleteBelowPart();
          break;
      }
      return;
    }
    if (id == kIdEos) {
      final s = app.current;
      if (s == null) return;
      switch (item) {
        case 'eostop':
          app.setEndOfSketch(0);
          break;
        case 'eosend':
          app.setEndOfSketch(s.layers.length);
          break;
      }
      return;
    }
    if (id.startsWith(kIdBody) && part != null) {
      final name = id.substring(kIdBody.length);
      switch (item) {
        case 'bdPick':
          app.pickBody(name);
          break;
        case 'bdVisible':
          app.toggleBodyVisible(part, name);
          break;
        case 'bdRename':
          final r = await promptForText(context,
              title: L.of(context).dlgRenameBody,
              initialValue: name,
              placeholder: L.of(context).phBodyName,
              confirmLabel: L.of(context).rename);
          if (r != null && r.trim().isNotEmpty) app.renameBody(name, r.trim());
          break;
        case 'bdDelete':
          app.deleteBody(name);
          break;
      }
      return;
    }
    if (id.startsWith(kIdFeature) && part != null) {
      final f = _feature(part, id.substring(kIdFeature.length));
      if (f == null) return;
      switch (item) {
        case 'ftEdit':
          app.editFeature(f);
          break;
        case 'ftVisible':
          app.toggleFeatureVisible(f);
          break;
        case 'ftRename':
          final r = await promptForText(context,
              title: L.of(context).dlgRenameFeature,
              initialValue: f.name,
              placeholder: L.of(context).phFeatureName,
              confirmLabel: L.of(context).rename);
          if (r != null && r.trim().isNotEmpty) app.renameFeature(f, r.trim());
          break;
        case 'ftDelete':
          await app.deleteFeature(f);
          break;
      }
      return;
    }
    // M212 — suppress / restore ONE occurrence of a pattern.
    if (id.startsWith(kIdOccurrence) && part != null) {
      final rest = id.substring(kIdOccurrence.length);
      final hash = rest.lastIndexOf('#');
      if (hash < 0) return;
      final f = _feature(part, rest.substring(0, hash));
      final n = int.tryParse(rest.substring(hash + 1));
      if (f is! PatternFeature || n == null) return;
      app.patternSuppressOccurrence(f, n, item == 'ocSuppress');
      return;
    }
    if (id.startsWith(kIdWorkPlane)) {
      final w = _workPlane(part, id);
      if (w == null) return;
      switch (item) {
        case 'wpSketch': // M181
          app.startSketchOnWorkPlane(w);
          break;
        case 'wpOffset':
          app.selectWorkPlane(w);
          app.workPlaneOffsetEditing = true;
          break;
        case 'wpVis':
          app.toggleWorkPlaneVisible(w);
          break;
        case 'wpDelete':
          app.deleteWorkPlane(w);
          break;
      }
      return;
    }
    if (id.startsWith(kIdWorkAxis)) {
      final a = _workAxis(part, id);
      if (a == null) return;
      switch (item) {
        case 'waVis':
          app.toggleWorkAxisVisible(a);
          break;
        case 'waFlip':
          app.flipWorkAxis(a);
          break;
        case 'waDelete':
          app.deleteWorkAxis(a);
          break;
      }
      return;
    }
    if (id.startsWith(kIdWorkPoint)) {
      final pt = _workPoint(part, id);
      if (pt == null) return;
      switch (item) {
        case 'wptVis':
          app.toggleWorkPointVisible(pt);
          break;
        case 'wptDelete':
          app.deleteWorkPoint(pt);
          break;
      }
      return;
    }
    if (id.startsWith(kIdSketch) || id.startsWith(kIdNested)) {
      final n = id.startsWith(kIdNested)
          ? id.substring(kIdNested.length)
          : id.substring(kIdSketch.length);
      final cs = part?.sketchByName(n);
      if (cs == null) return;
      switch (item) {
        case 'skEdit':
          app.openChildSketch(n);
          break;
        case 'skVisible':
          app.toggleSketchVisible(cs);
          break;
        case 'skShare':
          app.shareSketch(cs);
          break;
        case 'skUnshare':
          app.unshareSketch(cs);
          break;
        case 'skDelete':
          app.deleteChildSketch(cs);
          break;
      }
      return;
    }
    if (id.startsWith(kIdLayer)) {
      final layer = id.substring(kIdLayer.length);
      switch (item) {
        case 'edit':
          app.enterEdit(layer);
          break;
        case 'rename':
          final r = await promptForText(context,
              title: L.of(context).dlgRenameLayer,
              initialValue: layer,
              placeholder: L.of(context).phLayerName,
              confirmLabel: L.of(context).rename);
          if (r != null && r.trim().isNotEmpty) app.renameLayer(layer, r);
          break;
        case 'move':
          app.moveSelectionToLayer(layer);
          break;
        case 'delete':
          app.deleteLayer(layer);
          break;
      }
    }
  }

  /// [steps] is the offset in ROWS from where the drag began. Converting rows
  /// to slots stays here, in Dart, because only Dart knows that sketch rows
  /// have no slot of their own — the native side just reports travel.
  void _onEopDrag(int steps) {
    final part = app.currentPart;
    if (part == null) return;
    // M113 — rows, not features: one drag step is one browser row, so the
    // marker follows the finger and can land above a sketch.
    final n = partTimeline(part).length;
    _eopStart ??= part.eopAfter.clamp(0, n);
    setState(() => _dragEop = (_eopStart! + steps).clamp(0, n));
  }

  void _onEopEnd() {
    final v = _dragEop;
    _eopStart = null;
    setState(() => _dragEop = null);
    if (v != null) app.setEndOfPart(v);
  }

  /// M131 — features are polymorphic now, so this returns the base type;
  /// callers that need extrude fields test for it.
  PartFeature? _feature(PartModel p, String name) {
    for (final f in p.features) {
      if (f.name == name) return f;
    }
    return null;
  }

  /// M182 — the native EOP menu used to delete everything below the marker
  /// without asking; the Flutter fallback has always confirmed. Same dialog,
  /// same wording.
  Future<void> _confirmDeleteBelowPart() async {
    final part = app.currentPart;
    if (part == null) return;
    final count = part.features.where((f) => f.rolledBack).length;
    if (count == 0) return;
    final ok = await confirmAction(
      context,
      title: L.of(context).dlgDeleteAllFeaturesBelowEop,
      message: L.of(context).msgFeaturesRemoved(count),
      confirmLabel: L.of(context).delete,
    );
    if (ok) app.deleteBelowEndOfPart();
  }
}
