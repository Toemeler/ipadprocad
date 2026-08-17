// Prototype — M192: the quick tools, out of the long press and onto the screen.
//
// WHAT WAS WRONG
// --------------
// The M53 quick menu holds the two commands a running tool cannot do without:
// OK (Enter) and Cancel (Esc). On a Mac they are keys. On the iPad they were
// reachable ONLY by a 600 ms long press or a Pencil Pro squeeze — an
// undiscoverable gesture guarding the one control every half-drawn line needs.
// Undo and Redo were in the same shape: two- and three-finger taps (Procreate's
// language, M53), with nothing on screen to say so.
//
// So the commands now have a permanent home: a vertical Liquid Glass bar on the
// right edge, under the thumb of a hand holding the iPad, opposite the model
// browser, and clear of the ViewCube in the top-right corner. Icons only —
// labels would double its width for words a CAD user does not read twice.
//
// Nothing was taken away: the long press, the squeeze and the keys all keep
// working. This is the same command set with a surface.
//
// WHAT LIVES WHERE
// ----------------
// [buildQuickTools] and [runQuickTool] are PURE — the model of the bar and the
// meaning of a tap, in Dart, on the host, under test. UIKit owns the pixels
// (GlassToolBar.swift). Same split as the tab bar and the model browser, for
// the same reason: every expensive bug in this project has lived on the
// Flutter/UIKit boundary.
import 'package:flutter/material.dart';
import 'package:native_menu/native_menu.dart';

import '../app_state.dart';
import '../menus.dart';
import '../theme.dart';
import '../tools.dart';
import 'bottom_tabbar.dart';
import 'bug_button.dart';
import 'ribbon_chrome.dart';

/// Ids on the wire. They come back from UIKit verbatim and are dispatched by
/// [runQuickTool]; a rename on one side only is a dead button, so they are
/// constants rather than literals.
class QuickToolId {
  static const ok = 'ok';
  static const cancel = 'cancel';
  static const undo = 'undo';
  static const redo = 'redo';
  static const line = 'line';
  static const circle = 'circle';
  static const rect = 'rect';
  static const dimension = 'dimension';
  static const trim = 'trim';
  static const delete = 'delete';
  static const bug = 'bug';
}

/// True when Enter/OK would do something: a variable-length tool (spline) with
/// enough points to commit, or the freehand fit window waiting on its curve.
///
/// Fixed-point tools commit themselves on the last pick and are deliberately
/// NOT included — an OK that silently does nothing is worse than a dark one.
bool quickCanConfirm(AppState app) {
  final f = app.freehand;
  if (f != null) return !f.drawing;
  final meta = toolMeta[app.tool];
  if (meta != null &&
      meta.fixed == null &&
      app.toolPoints.length >= meta.minVar) {
    return true;
  }
  // M210 — the 3D panels have an OK too, and the bar is where a tablet reaches
  // for Enter. Paired with the Cancel below: a lone Cancel would be the only
  // half of the pair that ever lit.
  return app.extrudeSession != null ||
      app.edgeSession != null ||
      // M212 — the pattern panels have an OK too.
      app.patternSession != null ||
      // M225 — and so does the hole panel.
      app.holeSession != null ||
    app.combineSession != null ||
      // M227 — and the combine panel.
      app.combineSession != null;
}

/// True when Esc would do something: a command is running, ink is waiting, or
/// there is a selection to drop.
bool quickCanCancel(AppState app) =>
    app.tool != Tool.none ||
    app.freehand != null ||
    app.selection.isNotEmpty ||
    // M210 — the 3D side has commands too. "When a tool is in use the cancel
    // button in the toolbar should be there": an Extrude panel, a fillet
    // panel, an armed edge/plane/face/body pick and a work-plane drag are all
    // a tool in use, and every one of them had a dark Cancel next to it while
    // Esc — which a tablet does not have — worked fine.
    quickCancels3D(app);

/// True when there is a 3D command for Cancel to back out of. Mirrors exactly
/// what [AppState.escape3D] would act on, so the button is lit if and only if
/// pressing it does something.
bool quickCancels3D(AppState app) =>
    app.extrudeSession != null ||
    app.edgeSession != null ||
    app.patternSession != null ||
    app.holeSession != null ||
    app.combineSession != null ||
    app.pickingEdges ||
    app.pickingExtentFace ||
    app.pickingBody ||
    app.pickPlane;

/// The modify family (M49): one button that ENTERS Trim and, once inside,
/// steps Split -> Trim -> Extend exactly like Inventor's right-click.
const _modifyRing = {Tool.split, Tool.trim, Tool.extendT};

/// The bar's contents for the current state.
///
/// Three tiers, and each one earns its place:
///
///  * On the home gallery only the bug reporter — there is no document for
///    any command to act on.
///  * Undo and Redo everywhere else, because a wrong move is possible
///    everywhere else.
///  * OK and Cancel wherever the SKETCHER is live (a sketch tab, or a child
///    sketch open over a part), whether or not a layer is being edited. In a
///    part with no sketch open they are omitted rather than shown permanently
///    dark: there is no sketch tool for them to finish or abort, and a button
///    that can never light up is a lie about what the bar does.
///  * The four everyday drawing tools plus Trim only inside a layer's edit
///    mode, which is the only place a tool can be armed at all (selectTool
///    refuses outside it).
///  * Delete (M193) only with a deletable selection, below the tools. It is
///    the one button that has no meaning at all without a selection, which is
///    why it appears rather than greys out.
///  * The bug reporter (M194) last of all, always, separated from everything
///    above it.
///
/// Otherwise the buttons never move: they grey out instead of vanishing,
/// because a target that shifts under the thumb cannot be hit without looking.
List<GlassToolItem> buildQuickTools(AppState app) {
  if (app.isHome) return _withBugReport(const []);
  final items = <GlassToolItem>[];
  // M210 — ...and in a PART with a command running. The rule below (omit the
  // pair where nothing could ever light them) was right about an idle part and
  // wrong about one with the Extrude panel open: there the two most wanted
  // buttons in the app were simply absent.
  if (app.current != null || quickCancels3D(app)) {
    items.addAll([
      GlassToolItem(
        id: QuickToolId.ok,
        symbol: 'checkmark',
        label: 'Done',
        enabled: quickCanConfirm(app),
      ),
      GlassToolItem(
        id: QuickToolId.cancel,
        symbol: 'xmark',
        label: 'Cancel',
        enabled: quickCanCancel(app),
        destructive: true,
      ),
      const GlassToolItem.separator('sep1'),
    ]);
  }
  items.addAll([
    GlassToolItem(
      id: QuickToolId.undo,
      symbol: 'arrow.uturn.backward',
      label: 'Undo',
      enabled: quickCanUndo(app),
    ),
    GlassToolItem(
      id: QuickToolId.redo,
      symbol: 'arrow.uturn.forward',
      label: 'Redo',
      enabled: quickCanRedo(app),
    ),
  ]);
  if (!app.inEditMode) return _withBugReport(items);
  items.addAll([
    const GlassToolItem.separator('sep2'),
    GlassToolItem(
      id: QuickToolId.line,
      // SF Symbols 4 (iOS 16); on anything older it falls back to a plain
      // stroke rather than to an empty button.
      symbol: 'line.diagonal',
      fallback: 'minus',
      label: 'Line',
      selected: app.tool == Tool.line,
    ),
    GlassToolItem(
      id: QuickToolId.circle,
      symbol: 'circle',
      label: 'Circle',
      selected: app.tool == Tool.circleCenter,
    ),
    GlassToolItem(
      id: QuickToolId.rect,
      symbol: 'rectangle',
      label: 'Rectangle',
      selected: app.tool == Tool.rectTwoPoint,
    ),
    GlassToolItem(
      id: QuickToolId.dimension,
      symbol: 'ruler',
      label: 'Dimension',
      selected: app.tool == Tool.dimension,
    ),
    GlassToolItem(
      id: QuickToolId.trim,
      symbol: 'scissors',
      label: 'Trim',
      selected: _modifyRing.contains(app.tool),
    ),
  ]);
  // M193 — Delete APPEARS with a selection instead of sitting there dark: it
  // is the one button that is meaningless without one. It goes BELOW the
  // tools, so no tool is ever replaced by Delete at the slot the finger was
  // already heading for. (The bar is centred vertically, so it does shift by
  // half a button when this arrives — that moves every target by the same 23
  // pt, which is a different thing from swapping what is under one of them.)
  if (app.canDeleteSelection) {
    items.addAll([
      const GlassToolItem.separator('sep3'),
      const GlassToolItem(
        id: QuickToolId.delete,
        symbol: 'trash',
        label: 'Delete',
        destructive: true,
      ),
    ]);
  }
  return _withBugReport(items);
}

/// M194 — the bug reporter, pinned to the FOOT of the bar.
///
/// It used to be a red circle floating over the canvas. It belongs here
/// instead: it is chrome, not a tool. Last and separated on purpose — it is
/// the one button that must never be hit while reaching for a tool, and the
/// foot of the bar is the furthest any of them gets from it. Red, because it
/// is the prototype-phase affordance and should keep looking temporary.
///
/// It survives on the home gallery, where the bar has nothing else: a bug in
/// the gallery is still a bug, and the old floating button could be pressed
/// there too.
List<GlassToolItem> _withBugReport(List<GlassToolItem> items) {
  if (!BugReport.enabled) return items;
  return [
    ...items,
    if (items.isNotEmpty) const GlassToolItem.separator('sepBug'),
    const GlassToolItem(
      id: QuickToolId.bug,
      // SF Symbols 4 (iOS 16). Older systems get the classic ant rather than
      // an empty button.
      symbol: 'ladybug.fill',
      fallback: 'ant.fill',
      label: 'Report a bug',
      destructive: true,
    ),
  ];
}

/// Undo/Redo mean the SKETCH journal inside a sketch and the PART journal in a
/// part — the same split the Ctrl+Z path takes. Asking `canUndo` in a part
/// would answer for a sketch that is not open.
bool quickCanUndo(AppState app) =>
    app.current != null ? app.canUndo : app.canUndoPart;

bool quickCanRedo(AppState app) =>
    app.current != null ? app.canRedo : app.canRedoPart;

/// What a tap means. Kept out of the widget so the host suite can press every
/// button without a platform view.
///
/// [context] is only needed by the buttons that open a dialog (the bug
/// reporter); everything else is pure state and works without one, which is
/// what lets the tests press them all.
void runQuickTool(AppState app, String id, {BuildContext? context}) {
  // M205 — this bar is a UIKit platform view, so a press on it never reaches
  // the Flutter barrier a ribbon flyout puts up behind itself: the tap arrives
  // here, over a method channel, with no pointer event left to dismiss
  // anything with. Clicking a tool while a menu is open is still "clicking
  // somewhere else", so the menu goes.
  OpenMenus.closeAll();
  switch (id) {
    case QuickToolId.ok:
      // Same precedence as Enter in the viewport: the freehand window owns it
      // while it is up, otherwise it commits the variable-length tool.
      if (app.freehand != null) {
        app.freehandCommit();
      } else if (app.tool != Tool.none) {
        app.finishVariableTool();
      } else if (app.holeSession != null) {
        app.applyHole(); // M225 — the hole panel's OK
      } else if (app.combineSession != null) {
        app.applyCombine(); // M227 — the combine panel's OK
      } else if (app.patternSession != null) {
        app.applyPattern(); // M212 — the pattern panel's OK
      } else if (app.edgeSession != null) {
        app.applyEdgeFeature(); // M210 — the fillet/chamfer panel's OK
      } else if (app.extrudeSession != null) {
        app.applyExtrude(); // M210 — the Extrusion panel's OK
      } else {
        app.finishVariableTool();
      }
      break;
    case QuickToolId.cancel:
      // Same precedence as Esc: the freehand window throws its ink away and
      // leaves the tool armed for the next stroke.
      if (app.freehand != null) {
        app.freehandCancel();
      } else if (app.tool != Tool.none) {
        app.cancelTool();
      } else {
        // M210 — and in a part, Cancel is Esc. escape3D already knows the
        // order (a pick backs out of the pick, not out of the panel it
        // belongs to), so this is the same key by another name.
        app.escape3D();
      }
      break;
    case QuickToolId.undo:
      if (app.current != null) {
        app.undo();
      } else {
        app.undoPart();
      }
      break;
    case QuickToolId.redo:
      if (app.current != null) {
        app.redo();
      } else {
        app.redoPart();
      }
      break;
    case QuickToolId.line:
      app.selectTool(Tool.line);
      break;
    case QuickToolId.circle:
      app.selectTool(Tool.circleCenter);
      break;
    case QuickToolId.rect:
      app.selectTool(Tool.rectTwoPoint);
      break;
    case QuickToolId.dimension:
      app.selectTool(Tool.dimension);
      break;
    case QuickToolId.trim:
      // Inside the family this is the right-click role (M49): Split -> Trim ->
      // Extend. Outside it, it enters Trim.
      if (!app.cycleModifyTool()) app.selectTool(Tool.trim);
      break;
    case QuickToolId.delete:
      app.deleteSelection();
      break;
    case QuickToolId.bug:
      if (context != null) BugReport.open(context, app);
      break;
  }
}

/// The bar itself: native UIKit on iOS, a plain Flutter column everywhere else
/// so the host tests and any desktop run keep a working bar.
class QuickToolsBar extends StatelessWidget {
  final AppState app;
  const QuickToolsBar({super.key, required this.app});

  /// Gap between the glass and the screen edge. Matches the ribbon's side
  /// inset, so the right edge lines up with the left one.
  static const double margin = RibbonMetrics.side;

  /// Horizontal space the bar claims on the right of the content area, for
  /// anything else anchored there (the modeless Pattern and Fillet dialogs).
  static double get occupiedWidth => GlassToolBar.width + margin;

  @override
  Widget build(BuildContext context) {
    final items = buildQuickTools(app);
    if (items.isEmpty) return const SizedBox.shrink();
    // Vertically centred between the ribbon and the tab bar: the top-right
    // corner belongs to the ViewCube and the bottom-right to the constraint
    // readout, and both were there first.
    return RibbonMetrics.build(
      (_, top) => Positioned(
        top: top,
        bottom: BottomTabBar.floatingHeight,
        right: margin,
        // widthFactor 1 — WITHOUT it the Align expands to the whole stack
        // width, and a platform view eats every touch inside its frame: the
        // bar would have swallowed the viewport.
        child: Align(
          alignment: Alignment.centerRight,
          widthFactor: 1,
          child: GlassToolBar.isSupported
              ? GlassToolBar(
                  items: items,
                  onTap: (id) => runQuickTool(app, id, context: context),
                )
              : _flutterBar(context, items),
        ),
      ),
    );
  }

  Widget _flutterBar(BuildContext context, List<GlassToolItem> items) {
    return Container(
      width: GlassToolBar.width,
      padding: const EdgeInsets.symmetric(vertical: GlassToolBar.padding),
      decoration: BoxDecoration(
        color: T.fly,
        border: Border.all(color: T.sep),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final i in items)
            if (i.separator)
              const SizedBox(
                height: GlassToolBar.separatorSlot,
                child: Center(
                  child: Divider(
                      height: 1, thickness: 1, indent: 8, endIndent: 8),
                ),
              )
            else
              _flutterButton(context, i),
        ],
      ),
    );
  }

  Widget _flutterButton(BuildContext context, GlassToolItem i) {
    // Off iOS there are no SF Symbols; the fallback bar is chrome for the host
    // suite and desktop runs, so Material glyphs are the honest choice.
    const glyphs = <String, IconData>{
      QuickToolId.ok: Icons.check,
      QuickToolId.cancel: Icons.close,
      QuickToolId.undo: Icons.undo,
      QuickToolId.redo: Icons.redo,
      QuickToolId.line: Icons.horizontal_rule,
      QuickToolId.circle: Icons.circle_outlined,
      QuickToolId.rect: Icons.crop_square,
      QuickToolId.dimension: Icons.straighten,
      QuickToolId.trim: Icons.content_cut,
      QuickToolId.delete: Icons.delete_outline,
      QuickToolId.bug: Icons.bug_report,
    };
    return Semantics(
      label: i.label,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: i.enabled
            ? () => runQuickTool(app, i.id, context: context)
            : null,
        child: Container(
          width: GlassToolBar.buttonSize,
          height: GlassToolBar.buttonSize,
          margin: const EdgeInsets.only(bottom: GlassToolBar.spacing),
          decoration: BoxDecoration(
            color: i.selected ? T.blue.withValues(alpha: 0.30) : null,
            borderRadius: BorderRadius.circular(GlassToolBar.buttonSize / 2),
          ),
          child: Opacity(
            opacity: i.enabled ? 1.0 : 0.32,
            child: Icon(
              glyphs[i.id] ?? Icons.circle,
              size: 19,
              color: i.destructive ? const Color(0xFFE5544B) : T.text,
            ),
          ),
        ),
      ),
    );
  }
}
