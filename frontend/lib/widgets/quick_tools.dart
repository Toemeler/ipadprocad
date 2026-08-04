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
import '../theme.dart';
import '../tools.dart';
import 'bottom_tabbar.dart';
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
  return meta != null &&
      meta.fixed == null &&
      app.toolPoints.length >= meta.minVar;
}

/// True when Esc would do something: a command is running, ink is waiting, or
/// there is a selection to drop.
bool quickCanCancel(AppState app) =>
    app.tool != Tool.none ||
    app.freehand != null ||
    app.selection.isNotEmpty;

/// The modify family (M49): one button that ENTERS Trim and, once inside,
/// steps Split -> Trim -> Extend exactly like Inventor's right-click.
const _modifyRing = {Tool.split, Tool.trim, Tool.extendT};

/// The bar's contents for the current state.
///
/// Three tiers, and each one earns its place:
///
///  * Nothing on the home gallery — there is no document to act on.
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
///  * Delete (M193) only with a deletable selection, and LAST, so its arrival
///    moves nothing above it. It is the one button that has no meaning at all
///    without a selection, which is why it appears rather than greys out.
///
/// Otherwise the buttons never move: they grey out instead of vanishing,
/// because a target that shifts under the thumb cannot be hit without looking.
List<GlassToolItem> buildQuickTools(AppState app) {
  if (app.isHome) return const [];
  final items = <GlassToolItem>[];
  if (app.current != null) {
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
  if (!app.inEditMode) return items;
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
  // is the one button that is meaningless without one. It goes LAST, so
  // nothing above it moves when it arrives and no button is ever hit by
  // accident because the bar grew under the thumb.
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
  return items;
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
void runQuickTool(AppState app, String id) {
  switch (id) {
    case QuickToolId.ok:
      // Same precedence as Enter in the viewport: the freehand window owns it
      // while it is up, otherwise it commits the variable-length tool.
      if (app.freehand != null) {
        app.freehandCommit();
      } else {
        app.finishVariableTool();
      }
      break;
    case QuickToolId.cancel:
      // Same precedence as Esc: the freehand window throws its ink away and
      // leaves the tool armed for the next stroke.
      if (app.freehand != null) {
        app.freehandCancel();
      } else {
        app.cancelTool();
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
                  onTap: (id) => runQuickTool(app, id),
                )
              : _flutterBar(items),
        ),
      ),
    );
  }

  Widget _flutterBar(List<GlassToolItem> items) {
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
              _flutterButton(i),
        ],
      ),
    );
  }

  Widget _flutterButton(GlassToolItem i) {
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
    };
    return Semantics(
      label: i.label,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: i.enabled ? () => runQuickTool(app, i.id) : null,
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
