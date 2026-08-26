// Prototype — model browser (300px, Inventor style), 1:1 port of #mb.
// Tree: blue cube "SketchName", Origin folder (+/- expander) with X Axis /
// Y Axis / Center Point (auto-projected), then the layer container, then
// "End of Sketch". Right-click on a layer row -> context menu (Edit on top),
// double-click -> edit mode. Active layer row highlighted Inventor-style.
// M53: the End-of-Sketch row is Inventor's End of Part marker — drag it up
// and down the layer list (Esc aborts, like Inventor), everything below is
// rolled back (dimmed, not drawn, not editable); right-click / long-press it
// for Move to Top / Move to End / Delete all layers below, and any layer row
// offers "Move End of Sketch here" (Inventor 2013's Move EOP Marker).
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../icon_theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:native_menu/native_menu.dart';

import '../app_state.dart';
import '../asm_constraints.dart';
import '../l10n/cad_terms.dart';
import '../asm_pattern.dart';
import '../assembly.dart';
import '../menus.dart';
import '../log.dart';
import '../part_model.dart';
import '../svg_icons.dart';
import '../theme.dart';
import 'native_prompts.dart';
import '../l10n/l.dart';

/// M107 — on iOS the whole panel is native (see native_browser.dart and
/// GlassBrowser). This Flutter implementation stays as the non-iOS path and as
/// the fallback if the platform view ever fails to come up, so the app is
/// never left without a browser.
class ModelBrowser extends StatefulWidget {
  final AppState app;
  const ModelBrowser({super.key, required this.app});
  @override
  State<ModelBrowser> createState() => _ModelBrowserState();
}

class _ModelBrowserState extends State<ModelBrowser> {
  bool originOpen = false;
  bool bodiesOpen = true; // Solid Bodies folder starts expanded (Inventor)

  /// M240 — the assembly's two empty container folders. Collapsed, because
  /// there is nothing in either of them yet and an expanded empty folder is a
  /// row that says less than the closed one does.
  bool reprOpen = false;

  /// M250 — the View folder inside Representations. Position and Level of
  /// Detail have no flag because they have no children: they are listed
  /// dimmed and childless, and asm_reps.dart says why.
  bool viewRepsOpen = true;
  bool relsOpen = false;
  OverlayEntry? _ctx;
  // M53 — End-of-Sketch drag: the marker's PREVIEW slot while the finger /
  // mouse moves; committed to the app on release, discarded on Escape.
  int? _dragEos;

  /// M91 — in-flight End of Part drag (null = not dragging), mirroring
  /// [_dragEos]. Kept separate so a drag in one tree cannot bleed into the
  /// other.
  int? _dragEop;
  bool _eopEscInstalled = false;
  final GlobalKey _eopKey = GlobalKey();
  final GlobalKey _eosKey = GlobalKey();
  bool _eosEscInstalled = false;

  /// M59: feature nodes whose consumed-sketch child is expanded (Inventor's
  /// "+" on Extrusion1 revealing Sketch1 beneath it).
  final Set<String> _expandedFeatures = {};

  int _shownEos(SketchModel s) =>
      (_dragEos ?? s.eosAfter).clamp(0, s.layers.length);

  // Native long-press menu (iOS). The Flutter overlay below stays for the
  // right-mouse path on desktop; the two never fight, because a long press
  // never reaches Flutter once UIKit claims it.
  final Map<String, GlobalKey> _rowKeys = {};
  final GlobalKey _treeKey = GlobalKey();
  String? _lastPayload;
  bool _pushScheduled = false;

  @override
  void initState() {
    super.initState();
    NativeMenu.setSelectionHandler(NativeMenu.kLayers, _onMenuSelection);
    _schedulePush();
  }

  GlobalKey _keyFor(String layer) =>
      _rowKeys.putIfAbsent(layer, () => GlobalKey());

  // M84 — menu-target ids for the PART tree. Prefixed so they can never
  // collide with a layer name (which is arbitrary user text): the selection
  // handler dispatches on the prefix.
  static const String _kSketchPrefix = 'sk:';
  static const String _kNestedSketchPrefix = 'skn:';
  static const String _kFeaturePrefix = 'ft:';

  GlobalKey _sketchKeyFor(String name, bool nested) => _rowKeys.putIfAbsent(
      '${nested ? _kNestedSketchPrefix : _kSketchPrefix}$name',
      () => GlobalKey());

  GlobalKey _featureKeyFor(String name) =>
      _rowKeys.putIfAbsent('$_kFeaturePrefix$name', () => GlobalKey());

  static const String _kBodyPrefix = 'bd:';

  GlobalKey _bodyKeyFor(String name) =>
      _rowKeys.putIfAbsent('$_kBodyPrefix$name', () => GlobalKey());

  /// M97 — the body context menu. Inventor offers visibility and a rename on a
  /// solid body; Delete removes every feature that builds it, which is why it
  /// is in its own destructive section.
  List<List<NativeMenuItem>> _bodyMenu(
      AppState app, PartModel part, String bodyName) {
    final feats = [for (final f in part.features) if (f.bodyName == bodyName) f];
    final on = feats.any((f) => f.visible);
    return [
      [
        if (app.extrudeSession != null)
          NativeMenuItem(
              id: 'bdPick',
              title: L.of(context).ctxUseAsTargetBody,
              symbol: 'scope'),
        NativeMenuItem(
            id: 'bdVisible',
            title: on ? L.of(context).hide : L.of(context).ctxShow,
            symbol: on ? 'eye.slash' : 'eye'),
        NativeMenuItem(
            id: 'bdRename', title: L.of(context).rename, symbol: 'pencil'),
      ],
      [
        // M255 — Inventor's Make Part, in its own section: the two above
        // change how this body LOOKS, this one creates two documents and
        // navigates away from the one you are in.
        NativeMenuItem(
            id: 'bdMakePart',
            title: L.of(context).ctxMakePart,
            symbol: 'shippingbox'),
      ],
      [
        NativeMenuItem(
            id: 'bdDelete',
            title: L.of(context).ctxDeleteBody,
            symbol: 'trash',
            destructive: true),
      ],
    ];
  }

  /// Inventor's sketch context menu. **Share Sketch** appears only on a
  /// CONSUMED, not-yet-shared sketch ("Available only when the sketch was
  /// consumed by a feature", Part Browser Reference); **Unshare** replaces it
  /// once shared, and only while a single feature consumes it.
  List<List<NativeMenuItem>> _sketchMenu(
      AppState app, PartModel part, ChildSketch cs) {
    final consumed = sketchIsConsumed(part, cs);
    return [
      [
        NativeMenuItem(
            id: 'skEdit', title: L.of(context).ctxEditSketch, symbol: 'pencil.tip'),
        NativeMenuItem(
            id: 'skVisible',
            title: cs.visible ? L.of(context).hide : L.of(context).ctxShow,
            symbol: cs.visible ? 'eye.slash' : 'eye'),
      ],
      [
        if (consumed && !cs.shared)
          NativeMenuItem(
              id: 'skShare',
              title: L.of(context).ctxShareSketch,
              symbol: 'square.on.square'),
        if (canUnshareSketch(part, cs))
          NativeMenuItem(
              id: 'skUnshare', title: L.of(context).ctxUnshare, symbol: 'square.slash'),
      ],
    ];
  }

  /// The feature context menu the HANDOFF has listed as open since M74:
  /// delete / rename / visibility on an Extrusion, plus Edit Feature, which is
  /// what the row's double-tap already does.
  List<List<NativeMenuItem>> _featureMenu(AppState app, PartFeature f) => [
        [
          NativeMenuItem(
              id: 'ftEdit', title: L.of(context).ctxEditFeature, symbol: 'slider.horizontal.3'),
          NativeMenuItem(
              id: 'ftVisible',
              title: f.visible ? L.of(context).hide : L.of(context).ctxShow,
              symbol: f.visible ? 'eye.slash' : 'eye'),
          NativeMenuItem(
              id: 'ftRename', title: L.of(context).rename, symbol: 'pencil'),
        ],
        [
          NativeMenuItem(
              id: 'ftDelete',
              title: L.of(context).delete,
              symbol: 'trash',
              destructive: true),
        ],
      ];

  void _schedulePush() {
    if (_pushScheduled) return;
    _pushScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pushScheduled = false;
      if (mounted) _pushTargets();
    });
  }

  Rect? _globalRect(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// Same item set as the Flutter overlay — built per layer, because Edit,
  /// Rename and Delete depend on locked/base state.
  List<List<NativeMenuItem>> _menuFor(String layer) {
    final app = widget.app;
    final locked = app.layerLocked(layer);
    final base = app.isBaseLayer(layer);
    final selCount = app.selection.length;
    // Below the marker only the marker itself and Delete remain — Inventor
    // dims rolled-back features and strips their menus down the same way.
    if (app.layerRolledBack(layer)) {
      return [
        [
          NativeMenuItem(
              id: 'eophere',
              title: L.of(context).ctxMoveEosHere,
              symbol: 'arrow.up.and.down.text.horizontal'),
        ],
        if (!base)
          [
            NativeMenuItem(
                id: 'delete',
                title: L.of(context).ctxDeleteLayer,
                symbol: 'trash',
                destructive: true),
          ],
      ];
    }
    return [
      [
        if (!locked)
          NativeMenuItem(id: 'edit', title: L.of(context).edit, symbol: 'pencil.tip'),
        NativeMenuItem(
            id: 'visible',
            title: app.layerVisible(layer) ? L.of(context).hide : L.of(context).ctxShow,
            symbol: app.layerVisible(layer) ? 'eye.slash' : 'eye'),
        NativeMenuItem(
            id: 'lock',
            title: locked ? L.of(context).ctxUnlock : L.of(context).ctxLock,
            symbol: locked ? 'lock.open' : 'lock'),
        if (!base)
          NativeMenuItem(id: 'rename', title: L.of(context).rename, symbol: 'pencil'),
        NativeMenuItem(
            id: 'move',
            title:
                selCount == 0
                    ? L.of(context).ctxMoveSelectionHere
                    : L.of(context).ctxMoveNHere(selCount),
            symbol: 'arrow.right.doc.on.clipboard'),
        NativeMenuItem(
            id: 'eophere',
            title: L.of(context).ctxMoveEosHere,
            symbol: 'arrow.up.and.down.text.horizontal'),
      ],
      if (!base)
        [
          NativeMenuItem(
              id: 'delete',
              title: L.of(context).ctxDeleteLayer,
              symbol: 'trash',
              destructive: true),
        ],
    ];
  }

  List<List<NativeMenuItem>> _eosMenuGroups(SketchModel s) {
    final eos = _shownEos(s);
    return [
      [
        if (eos > 0)
          NativeMenuItem(
              id: 'eostop', title: L.of(context).ctxMoveToTop, symbol: 'arrow.up.to.line'),
        if (eos < s.layers.length)
          NativeMenuItem(
              id: 'eosend', title: L.of(context).ctxMoveToEnd, symbol: 'arrow.down.to.line'),
      ],
      if (eos < s.layers.length)
        [
          NativeMenuItem(
              id: 'deleteBelow',
              title: L.of(context).ctxDeleteAllLayersBelow,
              symbol: 'trash',
              destructive: true),
        ],
    ];
  }

  void _pushTargets() {
    if (!NativeMenu.isSupported) return;
    final s = widget.app.current;
    final targets = <NativeMenuTarget>[];
    final clip = _globalRect(_treeKey);
    for (final layer in s?.layers ?? const <String>[]) {
      final key = _rowKeys[layer];
      if (key == null) continue;
      final full = _globalRect(key);
      if (full == null) continue;
      final hit = clip == null ? full : full.intersect(clip);
      if (hit.width <= 1 || hit.height <= 1) continue;
      targets.add(NativeMenuTarget(
        id: layer,
        title: layer,
        rect: hit,
        cornerRadius: 4,
        lift: false, // M90 — see the part-tree targets below
        groups: _menuFor(layer),
      ));
    }
    if (s != null) {
      final full = _globalRect(_eosKey);
      if (full != null) {
        final hit = clip == null ? full : full.intersect(clip);
        if (hit.width > 1 && hit.height > 1) {
          targets.add(NativeMenuTarget(
            id: '__eos__',
            title: L.of(context).nodeEndOfSketch,
            rect: hit,
            cornerRadius: 4,
            lift: false, // M90
            groups: _eosMenuGroups(s),
          ));
        }
      }
    }
    // M84 — part tree: sketches (top-level and the nested copy) and features.
    final part = widget.app.currentPart;
    if (part != null && widget.app.activeChild == null) {
      void addTarget(String id, String title, GlobalKey key,
          List<List<NativeMenuItem>> groups) {
        final full = _globalRect(key);
        if (full == null) return;
        final hit = clip == null ? full : full.intersect(clip);
        if (hit.width <= 1 || hit.height <= 1) return;
        // Empty sections would render as a stray separator; an entirely empty
        // menu would open a blank UIMenu, so the row is skipped instead.
        final live = [for (final g in groups) if (g.isNotEmpty) g];
        if (live.isEmpty) return;
        targets.add(NativeMenuTarget(
            id: id,
            title: title,
            rect: hit,
            cornerRadius: 4,
            // M90: a browser row cannot be lifted — its pixels are in the
            // Flutter Metal layer and UIKit cannot snapshot them, so a lift
            // showed an empty grey slab over the tree. The row stays put and
            // only the menu appears.
            lift: false,
            groups: live));
      }

      for (final cs in part.childSketches) {
        final name = cs.model.name;
        final groups = _sketchMenu(widget.app, part, cs);
        if (firstConsumerOf(part, name) == null || cs.shared) {
          addTarget('$_kSketchPrefix$name', name,
              _sketchKeyFor(name, false), groups);
        }
        if (_rowKeys.containsKey('$_kNestedSketchPrefix$name')) {
          addTarget('$_kNestedSketchPrefix$name', name,
              _sketchKeyFor(name, true), groups);
        }
      }
      for (final f in part.features) {
        addTarget('$_kFeaturePrefix${f.name}', f.name,
            _featureKeyFor(f.name), _featureMenu(widget.app, f));
      }
      // M102 — the End of Part row is deliberately NOT a native menu target.
      //
      // This is what defeated three attempts at the drag. A UIKit
      // UIContextMenuInteraction covers every registered rect, and its
      // long-press recogniser CANCELS the Flutter touch as soon as it begins
      // — about 150 ms in, which is exactly the DOWN → CANCEL gap in the
      // device log, with no MOVE in between. It was never the gesture arena
      // and never the slot maths: UIKit was taking the touch away before
      // Flutter could see a drag. Right-click and the native menu "worked"
      // precisely because they are the interaction that was stealing it.
      //
      // The row keeps its menu through the Flutter long-press fallback in
      // _eopRow, which does not compete for the pointer.
      // M97 — solid bodies.
      for (final b in part.solidBodies()) {
        addTarget('$_kBodyPrefix${b.$1}', b.$1, _bodyKeyFor(b.$1),
            _bodyMenu(widget.app, part, b.$1));
      }
    }
    final payload = jsonEncode([for (final t in targets) t.toMap()]);
    if (payload == _lastPayload) return;
    _lastPayload = payload;
    NativeMenu.setTargets(NativeMenu.kLayers, targets);
  }

  void _onMenuSelection(String layer, String item) {
    if (!mounted) return;
    final app = widget.app;
    final s = app.current;
    // M84 — part tree ids are prefixed; layer ids are raw user text.
    if (layer.startsWith(_kSketchPrefix) ||
        layer.startsWith(_kNestedSketchPrefix)) {
      final name = layer.startsWith(_kNestedSketchPrefix)
          ? layer.substring(_kNestedSketchPrefix.length)
          : layer.substring(_kSketchPrefix.length);
      final cs = app.currentPart?.sketchByName(name);
      if (cs == null) return;
      switch (item) {
        case 'skEdit':
          app.openChildSketch(name);
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
      }
      return;
    }
    if (layer.startsWith(_kFeaturePrefix)) {
      final name = layer.substring(_kFeaturePrefix.length);
      final part = app.currentPart;
      PartFeature? f;
      for (final c in part?.features ?? const <PartFeature>[]) {
        if (c.name == name) f = c;
      }
      if (f == null) return;
      switch (item) {
        case 'ftEdit':
          app.editFeature(f);
          break;
        case 'ftVisible':
          app.toggleFeatureVisible(f);
          break;
        case 'ftRename':
          _promptRenameFeature(f);
          break;
        case 'ftDelete':
          _confirmDeleteFeature(f);
          break;
      }
      return;
    }
    if (layer.startsWith(_kBodyPrefix)) {
      final name = layer.substring(_kBodyPrefix.length);
      final part = app.currentPart;
      if (part == null) return;
      switch (item) {
        case 'bdPick':
          app.pickBody(name);
          break;
        case 'bdVisible':
          app.toggleBodyVisible(part, name);
          break;
        case 'bdRename':
          _promptRenameBody(name);
          break;
        case 'bdMakePart':
          app.openMakePart(name); // M255
          break;
        case 'bdDelete':
          _confirmDeleteBody(name);
          break;
      }
      return;
    }
    if (layer == '__eop__') {
      final part = app.currentPart;
      if (part == null) return;
      switch (item) {
        case 'eoptop':
          app.setEndOfPart(0);
          break;
        case 'eopend':
          app.setEndOfPart(partTimeline(part).length);
          break;
        case 'eopDeleteBelow':
          _confirmDeleteBelowPart();
          break;
      }
      return;
    }
    if (layer == '__eos__') {
      if (s == null) return;
      switch (item) {
        case 'eostop':
          app.setEndOfSketch(0);
          break;
        case 'eosend':
          app.setEndOfSketch(s.layers.length);
          break;
        case 'deleteBelow':
          _confirmDeleteBelow();
          break;
      }
      return;
    }
    if (item == 'eophere') {
      final i = s?.layers.indexOf(layer) ?? -1;
      if (i >= 0) app.setEndOfSketch(i + 1);
      return;
    }
    switch (item) {
      case 'edit':
        app.enterEdit(layer);
        break;
      case 'visible':
        app.toggleLayerVisible(layer);
        break;
      case 'lock':
        app.toggleLayerLocked(layer);
        break;
      case 'rename':
        _promptRename(layer);
        break;
      case 'move':
        app.moveSelectionToLayer(layer);
        break;
      case 'delete':
        _confirmDelete(layer);
        break;
    }
  }

  void _closeCtx() {
    OpenMenus.unregister(_closeCtx);
    _ctx?.remove();
    _ctx = null;
  }

  @override
  void dispose() {
    _uninstallEosEsc();
    _closeCtx();
    NativeMenu.setSelectionHandler(NativeMenu.kLayers, null);
    NativeMenu.setTargets(NativeMenu.kLayers, const []);
    super.dispose();
  }

  void _showCtx(Offset globalPos, String layer) {
    _closeCtx();
    final app = widget.app;
    final locked = app.layerLocked(layer);
    final base = app.isBaseLayer(layer);
    final rolled = app.layerRolledBack(layer);
    final selCount = app.selection.length;
    final items = <Widget>[
      if (rolled) ...[
        _ctxItem(L.of(context).ctxMoveEosHere, () {
          _closeCtx();
          final i = app.current?.layers.indexOf(layer) ?? -1;
          if (i >= 0) app.setEndOfSketch(i + 1);
        }),
        if (!base)
          _ctxItem(L.of(context).ctxDeleteLayer, () {
            _closeCtx();
            _confirmDelete(layer);
          }, danger: true),
      ],
      if (!rolled) ...[
        if (!locked)
          _ctxItem(L.of(context).edit, () {
            _closeCtx();
            app.enterEdit(layer);
          }),
        _ctxItem(app.layerVisible(layer) ? L.of(context).hide : L.of(context).ctxShow, () {
          _closeCtx();
          app.toggleLayerVisible(layer);
        }),
        _ctxItem(locked ? L.of(context).ctxUnlock : L.of(context).ctxLock, () {
          _closeCtx();
          app.toggleLayerLocked(layer);
        }),
        if (!base)
          _ctxItem(L.of(context).ctxRenameEllipsis, () {
            _closeCtx();
            _promptRename(layer);
          }),
        _ctxItem(
            selCount == 0
                ? L.of(context).ctxMoveSelectionHere
                : L.of(context).ctxMoveNHere(selCount), () {
          _closeCtx();
          app.moveSelectionToLayer(layer);
        }),
        _ctxItem(L.of(context).ctxMoveEosHere, () {
          _closeCtx();
          final i = app.current?.layers.indexOf(layer) ?? -1;
          if (i >= 0) app.setEndOfSketch(i + 1);
        }),
        if (!base)
          _ctxItem(L.of(context).ctxDeleteLayer, () {
            _closeCtx();
            _confirmDelete(layer);
          }, danger: true),
      ],
    ];
    _ctx = OverlayEntry(
      builder: (_) => Stack(children: [
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => _closeCtx(),
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          left: globalPos.dx,
          top: globalPos.dy,
          child: Material(
            color: Colors.transparent,
            child: Container(
              // maxWidth is NOT optional: a Positioned(left/top) child of a
              // Stack is laid out unbounded, and _CtxRow uses
              // width: double.infinity — so without a ceiling every row's width
              // is literally infinite. Release builds have asserts off, the
              // non-finite fill is dropped by Impeller and the menu renders
              // without a background (same bug the ribbon flyout had).
              constraints: const BoxConstraints(minWidth: 180, maxWidth: 260),
              padding: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                color: T.fly,
                border: Border.all(color: T.sep),
                boxShadow: [
                  BoxShadow(
                      color: T.shadow,
                      blurRadius: 22,
                      offset: Offset(0, 8))
                ],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: items),
            ),
          ),
        ),
      ]),
    );
    Overlay.of(context).insert(_ctx!);
    OpenMenus.register(_closeCtx);
  }

  /// M91 — desktop/fallback End of Part menu. Same items as the native one.
  void _showEopCtx(Offset globalPos) {
    _closeCtx();
    final app = widget.app;
    final part = app.currentPart;
    if (part == null) return;
    final eop = _shownEop(part);
    final n = partTimeline(part).length;
    _showCtxItems(globalPos, [
      if (eop > 0)
        _ctxItem(L.of(context).ctxMoveToTop, () {
          _closeCtx();
          app.setEndOfPart(0);
        }),
      if (eop < n)
        _ctxItem(L.of(context).ctxMoveToEnd, () {
          _closeCtx();
          app.setEndOfPart(n);
        }),
      if (eop < n)
        _ctxItem(L.of(context).ctxDeleteAllFeaturesBelow, () {
          _closeCtx();
          _confirmDeleteBelowPart();
        }, danger: true),
    ]);
  }

  Future<void> _confirmDeleteBelowPart() async {
    final part = widget.app.currentPart;
    if (part == null) return;
    final count = part.features.where((f) => f.rolledBack).length;
    if (count == 0) return;
    final ok = await confirmAction(
      context,
      title: L.of(context).dlgDeleteAllFeaturesBelowEop,
      message: L.of(context).msgFeaturesRemoved(count),
      confirmLabel: L.of(context).delete,
    );
    if (ok) widget.app.deleteBelowEndOfPart();
  }

  void _showEosCtx(Offset globalPos) {
    _closeCtx();
    final app = widget.app;
    final s = app.current;
    if (s == null) return;
    final eos = _shownEos(s);
    final items = <Widget>[
      if (eos > 0)
        _ctxItem(L.of(context).ctxMoveToTop, () {
          _closeCtx();
          app.setEndOfSketch(0);
        }),
      if (eos < s.layers.length)
        _ctxItem(L.of(context).ctxMoveToEnd, () {
          _closeCtx();
          app.setEndOfSketch(s.layers.length);
        }),
      if (eos < s.layers.length)
        _ctxItem(L.of(context).ctxDeleteAllLayersBelow, () {
          _closeCtx();
          _confirmDeleteBelow();
        }, danger: true),
    ];
    _showCtxItems(globalPos, items);
  }

  /// The shared fallback-menu overlay (M91 — extracted so End of Sketch and
  /// End of Part cannot drift apart).
  void _showCtxItems(Offset globalPos, List<Widget> items) {
    if (items.isEmpty) return;
    _ctx = OverlayEntry(
      builder: (_) => Stack(children: [
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => _closeCtx(),
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          left: globalPos.dx,
          top: globalPos.dy,
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(minWidth: 180, maxWidth: 260),
              padding: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                color: T.fly,
                border: Border.all(color: T.sep),
                boxShadow: [
                  BoxShadow(
                      color: T.shadow,
                      blurRadius: 22,
                      offset: Offset(0, 8))
                ],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: items),
            ),
          ),
        ),
      ]),
    );
    Overlay.of(context).insert(_ctx!);
    OpenMenus.register(_closeCtx);
  }

  Future<void> _confirmDeleteBelow() async {
    final app = widget.app;
    final s = app.current;
    if (s == null) return;
    final eos = s.eosAfter.clamp(0, s.layers.length);
    final below = s.layers.sublist(eos);
    if (below.isEmpty) return;
    final names = below.toSet();
    final count = s.geometry.where((g) => names.contains(g.layer)).length;
    final ok = await confirmAction(
      context,
      title: L.of(context).dlgDeleteEverythingBelowEos,
      message: L.of(context)
          .msgLayersAndEntitiesRemoved(below.length, count),
      confirmLabel: L.of(context).delete,
    );
    if (ok) app.deleteBelowEndOfSketch();
  }

  // ---- M53: End-of-Sketch drag (Inventor's EOP reposition) ----

  /// The insertion slot for a pointer at global [dy]: the number of layer
  /// rows whose centre lies above it. Computed from the LIVE row rects, so
  /// scrolling and the marker's own slot are handled by construction.
  int _slotForDy(SketchModel s, double dy) {
    var slot = 0;
    for (final layer in s.layers) {
      final r = _globalRect(_rowKeys[layer] ?? GlobalKey());
      if (r != null && r.center.dy < dy) slot++;
    }
    return slot.clamp(0, s.layers.length);
  }

  int _shownEop(PartModel p) =>
      (_dragEop ?? p.eopAfter).clamp(0, partTimeline(p).length);

  /// M113 — the marker counts ROWS now, so a drag step is simply a row and the
  /// whole slot-to-row conversion this used to need is gone. Four attempts
  /// lived here; the fix was in the model, not the arithmetic.
  static const double _kRowH = 32;
  double? _eopDragStartDy;
  int? _eopDragStartSlot;

  int _slotForDyPart(PartModel p, double dy) {
    final n = partTimeline(p).length;
    final dy0 = _eopDragStartDy, s0 = _eopDragStartSlot;
    if (dy0 == null || s0 == null) return _shownEop(p);
    return (s0 + ((dy - dy0) / _kRowH).round()).clamp(0, n);
  }

  bool _eopEsc(KeyEvent e) {
    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
      _eopDragStartDy = null;
      _eopDragStartSlot = null;
      setState(() => _dragEop = null); // Inventor: Esc aborts the reposition
      _uninstallEopEsc();
      return true;
    }
    return false;
  }

  void _installEopEsc() {
    if (_eopEscInstalled) return;
    _eopEscInstalled = true;
    HardwareKeyboard.instance.addHandler(_eopEsc);
  }

  void _uninstallEopEsc() {
    if (!_eopEscInstalled) return;
    _eopEscInstalled = false;
    HardwareKeyboard.instance.removeHandler(_eopEsc);
  }

  /// M91 — the End of Part row: everything the End of Sketch row does.
  /// Draggable with a live preview of the new position, Esc aborts, secondary
  /// click and long press open the same menu.
  /// M100 — the End of Part row.
  ///
  /// The drag is driven by RAW POINTER EVENTS on a Listener, not by
  /// GestureDetector's onVerticalDrag*. That was the bug: this row lives
  /// inside the browser's ListView, and a vertical drag gesture has to win the
  /// gesture arena against the scrollable. The list won every time, so the
  /// marker never moved at all while the tree scrolled underneath — the menu
  /// path worked, which is why "Move to Top" was the only thing that ever
  /// repositioned it. A Listener does not enter the arena; it sees every
  /// pointer event unconditionally.
  ///
  /// Logs each phase, because this is the second attempt and the first one
  /// looked right in the source.
  Widget _eopRow(AppState app, PartModel part) {
    return Listener(
      key: _eopKey,
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        if (e.kind == PointerDeviceKind.mouse &&
            e.buttons == kSecondaryMouseButton) {
          _showEopCtx(e.position);
          return;
        }
        _installEopEsc();
        _eopDragStartDy = e.position.dy;
        _eopDragStartSlot = _shownEop(part);
        Log.i(
            'eop',
            'DOWN kind=${e.kind.name} dy=${e.position.dy.toStringAsFixed(1)} '
                'slot=$_eopDragStartSlot of ${partTimeline(part).length}');
        setState(() => _dragEop = _eopDragStartSlot);
      },
      onPointerMove: (e) {
        if (_eopDragStartDy == null) return;
        final slot = _slotForDyPart(part, e.position.dy);
        if (slot != _dragEop) {
          Log.i(
              'eop',
              'MOVE dy=${e.position.dy.toStringAsFixed(1)} '
                  'd=${(e.position.dy - _eopDragStartDy!).toStringAsFixed(1)} '
                  '-> slot $slot');
          setState(() => _dragEop = slot);
        }
      },
      onPointerUp: (e) {
        _uninstallEopEsc();
        final v = _dragEop;
        final moved = _eopDragStartDy == null
            ? 0.0
            : (e.position.dy - _eopDragStartDy!).abs();
        _eopDragStartDy = null;
        _eopDragStartSlot = null;
        setState(() => _dragEop = null);
        Log.i('eop',
            'UP moved=${moved.toStringAsFixed(1)}px -> commit slot=$v');
        // A tap (no travel) must not silently reposition the marker.
        if (v != null && moved > 4) app.setEndOfPart(v);
      },
      onPointerCancel: (_) {
        // With the list locked this should no longer fire mid-drag; if it
        // ever does, COMMIT what the user had rather than throwing the drag
        // away silently — that is the behaviour they experienced as "nothing
        // happens at all".
        _uninstallEopEsc();
        final v = _dragEop;
        final started = _eopDragStartSlot;
        _eopDragStartDy = null;
        _eopDragStartSlot = null;
        Log.i('eop', 'CANCEL at slot=$v (started $started)');
        setState(() => _dragEop = null);
        if (v != null && started != null && v != started) {
          widget.app.setEndOfPart(v);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // M102 — always the Flutter menu here, on device too: this row has no
        // UIKit interaction any more (see _pushTargets), so nothing else will
        // provide one. It fires only after the drag threshold has NOT been
        // met, so it cannot shadow the drag.
        onLongPressStart: (d) => _showEopCtx(d.globalPosition),
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: _row(
              indent: 8,
              exp: ' ',
              icon: endOfSketchIcon,
              label: L.of(context).nodeEndOfPart),
        ),
      ),
    );
  }

  List<List<NativeMenuItem>> _eopMenuGroups(PartModel part) {
    final eop = _shownEop(part);
    final n = partTimeline(part).length;
    return [
      [
        if (eop > 0)
          NativeMenuItem(
              id: 'eoptop', title: L.of(context).ctxMoveToTop, symbol: 'arrow.up.to.line'),
        if (eop < n)
          NativeMenuItem(
              id: 'eopend', title: L.of(context).ctxMoveToEnd, symbol: 'arrow.down.to.line'),
      ],
      [
        if (eop < n)
          NativeMenuItem(
              id: 'eopDeleteBelow',
              title: L.of(context).ctxDeleteAllFeaturesBelowEop,
              symbol: 'trash',
              destructive: true),
      ],
    ];
  }

  bool _eosEsc(KeyEvent e) {
    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
      // Inventor: Escape aborts an in-flight EOP reposition.
      setState(() => _dragEos = null);
      _uninstallEosEsc();
      return true;
    }
    return false;
  }

  void _installEosEsc() {
    if (_eosEscInstalled) return;
    _eosEscInstalled = true;
    HardwareKeyboard.instance.addHandler(_eosEsc);
  }

  void _uninstallEosEsc() {
    if (!_eosEscInstalled) return;
    _eosEscInstalled = false;
    HardwareKeyboard.instance.removeHandler(_eosEsc);
  }

  Widget _eosRow(AppState app, SketchModel s) {
    return Listener(
      key: _eosKey,
      onPointerDown: (e) {
        if (e.kind == PointerDeviceKind.mouse &&
            e.buttons == kSecondaryMouseButton) {
          _showEosCtx(e.position);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPressStart: NativeMenu.isSupported
            ? null // the UIKit menu owns the long press on device
            : (d) => _showEosCtx(d.globalPosition),
        onVerticalDragStart: (d) {
          _installEosEsc();
          setState(() => _dragEos = _shownEos(s));
        },
        onVerticalDragUpdate: (d) {
          final slot = _slotForDy(s, d.globalPosition.dy);
          if (slot != _dragEos) setState(() => _dragEos = slot);
        },
        onVerticalDragEnd: (_) {
          _uninstallEosEsc();
          final v = _dragEos;
          setState(() => _dragEos = null);
          if (v != null) app.setEndOfSketch(v);
        },
        onVerticalDragCancel: () {
          _uninstallEosEsc();
          setState(() => _dragEos = null);
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: _row(
              indent: 8,
              exp: ' ',
              icon: endOfSketchIcon,
              label: L.of(context).nodeEndOfSketch),
        ),
      ),
    );
  }

  Future<void> _promptRename(String layer) async {
    final app = widget.app;
    final result = await promptForText(
      context,
      title: L.of(context).dlgRenameLayer,
      initialValue: layer,
      placeholder: L.of(context).phLayerName,
      confirmLabel: L.of(context).rename,
    );
    if (result != null && result.trim().isNotEmpty) {
      app.renameLayer(layer, result);
    }
  }

  /// M84 — rename an Extrusion. Inventor renames the browser node only; the
  /// feature's identity for the solver is its position in the tree, not the
  /// label, so this is a pure display change.
  Future<void> _promptRenameFeature(PartFeature f) async {
    final app = widget.app;
    final result = await promptForText(
      context,
      title: L.of(context).dlgRenameFeature,
      initialValue: f.name,
      placeholder: L.of(context).phFeatureName,
      confirmLabel: L.of(context).rename,
    );
    if (result != null && result.trim().isNotEmpty) {
      app.renameFeature(f, result.trim());
    }
  }

  /// M97 — renaming a body renames it on every feature that builds it.
  Future<void> _promptRenameBody(String bodyName) async {
    final app = widget.app;
    final result = await promptForText(
      context,
      title: L.of(context).dlgRenameBody,
      initialValue: bodyName,
      placeholder: L.of(context).phBodyName,
      confirmLabel: L.of(context).rename,
    );
    if (result != null && result.trim().isNotEmpty) {
      app.renameBody(bodyName, result.trim());
    }
  }

  Future<void> _confirmDeleteBody(String bodyName) async {
    final part = widget.app.currentPart;
    if (part == null) return;
    final n = part.features.where((f) => f.bodyName == bodyName).length;
    if (n == 0) return;
    final t = L.of(context);
    final ok = await confirmAction(
      context,
      title: t.dlgDeleteNamed(bodyName),
      message: t.msgBodyFeaturesRemoved(n),
      confirmLabel: L.of(context).delete,
    );
    if (ok) widget.app.deleteBody(bodyName);
  }

  Future<void> _confirmDelete(String layer) async {
    final app = widget.app;
    final s = app.current;
    final count =
        s == null ? 0 : s.geometry.where((g) => g.layer == layer).length;
    final ok = await confirmAction(
      context,
      title: L.of(context).dlgDeleteNamed(layer),
      message: count == 0
          ? L.of(context).msgLayerEmptyRemoved
          : L.of(context).msgRemovesLayerAndEntitiesUndo(count),
      confirmLabel: L.of(context).delete,
    );
    if (ok) app.deleteLayer(layer);
  }

  Widget _ctxItem(String label, VoidCallback onTap, {bool danger = false}) {
    return _CtxRow(label: label, onTap: onTap, danger: danger);
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final s = app.current;
    final part = app.activeChild == null ? app.currentPart : null;
    final asm = app.currentAssembly;
    // Layers appear, vanish and get renamed without this widget remounting.
    _schedulePush();
    return Container(
      width: 300,
      decoration: BoxDecoration(
        // M106 — on iOS the panel's surface is REAL Apple Liquid Glass
        // (UIGlassEffect), laid in behind the tree; the opaque fill is only
        // for platforms without it. A colour here would sit on top of the
        // glass and hide it.
        color: GlassPanel.isSupported ? null : T.mbBg,
        border: Border(right: BorderSide(color: T.mbBorder)),
      ),
      child: Stack(children: [
        // The glass surface. IgnorePointer inside GlassPanel: every gesture in
        // this panel belongs to the Flutter rows above it, which is the
        // lesson M48 and M102 both cost a lot of debugging to learn.
        if (GlassPanel.isSupported)
          const Positioned.fill(child: GlassPanel()),
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // header
        Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: T.mbHead,
            border: Border(bottom: BorderSide(color: T.mbHeadBorder)),
          ),
          child: Row(children: [
            Container(
              height: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: T.mbBg,
                border: Border(right: BorderSide(color: T.mbHeadBorder)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(L.of(context).browserTitle, style: ts(12.5, T.mbText)),
                const SizedBox(width: 7),
                Text('✕', style: ts(11, T.mbDim)),
              ]),
            ),
            const Spacer(),
          ]),
        ),
        // tree
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (_) {
              _schedulePush();
              return false;
            },
            child: ListView(
              // M101 — WHY THE MARKER WOULD NOT DRAG. The log said it exactly:
              // "eop DOWN ... / eop CANCEL", down then cancel, never a move.
              // A Listener does not enter the gesture arena, but it is not
              // immune to it either: the moment the scrollable CLAIMS the
              // pointer, Flutter delivers a pointer-cancel to everyone below,
              // and the events stop. Raw pointers were therefore not enough.
              // Locking the list for the duration of the drag removes the only
              // competitor, so the pointer stays ours from down to up.
              physics: _eopDragStartDy != null
                  ? const NeverScrollableScrollPhysics()
                  : null,
              key: _treeKey,
              padding: const EdgeInsets.symmetric(vertical: 5),
              children: [
                _row(
                  indent: 0,
                  exp: ' ',
                  icon: asm != null
                      ? assemblyCubeIcon
                      : part != null
                          ? partCubeIcon
                          : sketchCubeIcon,
                  label: app.activeChild?.name ?? app.curTab ?? 'Sketch1',
                ),
                // M240 — Inventor's assembly browser, in Inventor's order:
                // Representations and Relationships above Origin, then the
                // placed components in placement order.
                if (asm != null) ...[
                  _row(
                    indent: 8,
                    exp: reprOpen ? '−' : '+',
                    icon: representationsIcon,
                    label: L.of(context).nodeRepresentations,
                    onTap: () => setState(() => reprOpen = !reprOpen),
                  ),
                  // M250 — Inventor's three sub-folders. The native tree's
                  // twin (see buildRepresentationRows' region in
                  // native_browser.dart): View is real and lists the saved
                  // representations with the active one ticked; Position and
                  // Level of Detail are drawn dimmed and childless, for the
                  // reasons asm_reps.dart sets out.
                  if (reprOpen) ...[
                    _row(
                      indent: 22,
                      exp: viewRepsOpen ? '−' : '+',
                      icon: representationsIcon,
                      label: L.of(context).nodeViewReps,
                      onTap: () => setState(() => viewRepsOpen = !viewRepsOpen),
                      trailing: _PlusButton(
                          tip: L.of(context).ctxNewViewRep,
                          onTap: () {
                            app.newViewRep();
                            setState(() => viewRepsOpen = true);
                          }),
                    ),
                    if (viewRepsOpen)
                      for (final name in asm.viewRepNames)
                        _row(
                          indent: 36,
                          exp: ' ',
                          icon: asm.activeViewRep == name
                              ? viewRepActiveIcon
                              : (asm.viewRepNamed(name)?.locked == true
                                  ? viewRepLockedIcon
                                  : viewRepIcon),
                          label: name,
                          active: asm.activeViewRep == name,
                          onTap: () => app.activateViewRep(name),
                        ),
                    for (final label in [
                      L.of(context).nodePositionalReps,
                      L.of(context).nodeLodReps,
                    ])
                      Opacity(
                        opacity: 0.45,
                        child: _row(
                            indent: 22,
                            exp: ' ',
                            icon: representationsIcon,
                            label: label),
                      ),
                  ],
                  _row(
                    indent: 8,
                    exp: relsOpen ? '−' : '+',
                    icon: relationshipsIcon,
                    label: L.of(context).nodeRelationships,
                    onTap: () => setState(() => relsOpen = !relsOpen),
                  ),
                  // M242 — the constraints themselves, in placement order.
                  if (relsOpen)
                    for (final c in asm.constraints)
                      _constraintRow(app, asm, c, indent: 30),
                ],
                // Inventor: the Solid Bodies folder sits ABOVE Origin, with a
                // (N) body count; expand it to list each body with its own
                // visibility eye. Only shown for a 3D part that has bodies.
                if (part != null && app.activeChild == null) ...[
                  if (part.solidBodies().isNotEmpty) ...[
                    _row(
                      indent: 8,
                      exp: bodiesOpen ? '−' : '+',
                      icon: originIcon,
                      label: L.of(context)
                  .nodeSolidBodies(part.solidBodies().length),
                      onTap: () => setState(() => bodiesOpen = !bodiesOpen),
                    ),
                    if (bodiesOpen)
                      for (final b in part.solidBodies())
                        _bodyRow(app, part, b.$1, b.$2),
                  ],
                ],
                _row(
                  indent: 8,
                  exp: originOpen ? '−' : '+',
                  icon: originIcon,
                  label: L.of(context).nodeOrigin,
                  onTap: () => setState(() => originOpen = !originOpen),
                ),
                if (originOpen) ...[
                  // An assembly carries the same seven origin entries a part
                  // does, and each eye drives the same painter.
                  if (asm != null) ...[
                    for (final o in _kOriginRows)
                      _asmOriginRow(app, asm, L.of(context), o.$1, o.$2),
                  ]
                  // A 3D part carries the FULL origin: 3 work planes, 3 axes
                  // and the centre point, each with its own visibility eye
                  // wired straight into the 3D scene (M56).
                  else if (part != null) ...[
                    for (final o in [
                      (L.of(context).nodeYzPlane, 'yz'),
                      (L.of(context).nodeXzPlane, 'xz'),
                      (L.of(context).nodeXyPlane, 'xy'),
                      (L.of(context).nodeXAxis, 'x'),
                      (L.of(context).nodeYAxis, 'y'),
                      (L.of(context).nodeZAxis, 'z'),
                      (L.of(context).nodeCenterPoint, 'cp'),
                    ])
                      _originRow(app, part, o.$1, o.$2),
                  ] else ...[
                    _row(indent: 30, icon: xAxisIcon, label: L.of(context).nodeXAxis),
                    _row(indent: 30, icon: yAxisIcon, label: L.of(context).nodeYAxis),
                    Tooltip(
                      message: L.of(context).nodeAutoProjected,
                      child: _row(
                          indent: 30,
                          icon: centerPointIcon,
                          label: L.of(context).nodeCenterPoint),
                    ),
                  ],
                ],
                // The placed components. Inventor lists them below Origin,
                // in the order they were placed.
                if (asm != null) ...[
                  for (final o in asm.occurrences)
                    // M248 — a pattern ELEMENT is listed under its pattern,
                    // not beside the components. Inventor's tree, and the
                    // reason the pattern node exists: a row per element at the
                    // top level buries the assembly.
                    if (!o.isPatternElement)
                      ..._componentRows(app, asm, o, indent: 8, path: ''),
                  for (final p in asm.patterns)
                    ..._patternRows(app, asm, p, indent: 8),
                ],
                // M250 — the assembly a part is being edited inside, and the
                // way back to it. The native tree's twin; see there for why it
                // is in the browser as well as in the ribbon.
                if (app.inPlaceEdit != null)
                  _row(
                    indent: 8,
                    exp: ' ',
                    icon: inPlaceReturnIcon,
                    label: app.inPlaceEdit!.assembly,
                    onTap: () => app.leaveInPlaceEdit(),
                  ),
                // A part shows its child sketches and features instead of
                // layers; the open child sketch falls through to the 2D tree.
                if (part != null && app.activeChild == null) ...[
                  // Inventor: a sketch consumed by a feature nests UNDER that
                  // feature (see _featureRow); only unconsumed sketches stay
                  // top-level. The eye is the per-sketch Visibility toggle.
                  // M84: a SHARED sketch also shows at the top level, next to
                  // its nested copy under the parent feature — Inventor's
                  // "a copy of the sketch displays above its parent feature".
                  // M91 — ONE TIMELINE. Inventor's browser is a history, not
                  // a set of folders: whatever was made last is at the bottom,
                  // so a sketch created after an extrusion sits BELOW it. A
                  // shared sketch's copy is pinned directly above the feature
                  // using it. partTimeline() owns both rules.
                  ...() {
                    final rows = <Widget>[];
                    // M113 — slot == row, so the marker simply goes at its
                    // index and can sit above a sketch.
                    final timeline = partTimeline(part);
                    final eop = _shownEop(part);
                    for (var ti = 0; ti < timeline.length; ti++) {
                      final n = timeline[ti];
                      if (ti == eop) rows.add(_eopRow(app, part));
                      if (n.isFeature) {
                        rows.add(_featureRow(app, part, n.feature!,
                            rolled: n.feature!.rolledBack));
                      } else {
                        rows.add(_sketchRow(app, n.sketch!, indent: 8));
                      }
                    }
                    if (eop >= timeline.length) rows.add(_eopRow(app, part));
                    return rows;
                  }(),
                ],
                // layers container, with the End-of-Sketch marker at its
                // slot (M53): everything after the marker renders rolled back
                if (s != null && part == null && asm == null) ...[
                  for (var i = 0; i < s.layers.length; i++) ...[
                    if (i == _shownEos(s)) _eosRow(app, s),
                    _layerRow(app, s.layers[i], rolled: i >= _shownEos(s)),
                  ],
                  if (_shownEos(s) >= s.layers.length) _eosRow(app, s),
                ] else if (part == null && asm == null)
                  _row(
                      indent: 8,
                      exp: ' ',
                      icon: endOfSketchIcon,
                      label: L.of(context).nodeEndOfSketch),
              ],
            ),
          ),
        ),
        ]),
      ]),
    );
  }

  /// The seven origin entries, in Inventor's order. One list, so the part tree
  /// and the assembly tree cannot drift apart on what an Origin folder holds.
  static const List<(String, String)> _kOriginRows = [
    ('yz', 'yz'),
    ('xz', 'xz'),
    ('xy', 'xy'),
    ('x', 'x'),
    ('y', 'y'),
    ('z', 'z'),
    ('cp', 'cp'),
  ];

  /// M240 — an origin entry of the ASSEMBLY. Same glyphs and same eye as
  /// [_originRow]; only the model behind the toggle differs.
  Widget _asmOriginRow(
      AppState app, AssemblyModel asm, AppL10n t, String key, String _) {
    final on = asm.vis[key] == true;
    final row = _row(
      indent: 30,
      icon: switch (key) {
        'yz' || 'xz' || 'xy' => planeIcon,
        'x' => xAxisIcon,
        'y' => yAxisIcon,
        'z' => zAxisIcon,
        _ => centerPointIcon,
      },
      label: switch (key) {
        'yz' => t.nodeYzPlane,
        'xz' => t.nodeXzPlane,
        'xy' => t.nodeXyPlane,
        'x' => t.nodeXAxis,
        'y' => t.nodeYAxis,
        'z' => t.nodeZAxis,
        _ => t.nodeCenterPoint,
      },
      trailing: _EyeButton(
          visible: on, onTap: () => app.setAssemblyOriginVisible(key, on)),
    );
    return on ? row : Opacity(opacity: 0.45, child: row);
  }

  /// M240 — one placed component. Tapping selects it, which is the same
  /// selection the viewport shows and drags; the eye hides it; a grounded
  /// component carries Inventor's pin instead of an expander.
  ///
  /// M242 — and it discloses the relationships ON it, when it has any.
  Widget _componentRow(AppState app, AssemblyModel asm, AssemblyOccurrence o,
      {required double indent, required String key}) {
    final expandable =
        o.sub != null || asm.constraintsOn(o.id).isNotEmpty;
    final open = _compOpen.contains(key);
    final row = _row(
      indent: indent,
      exp: !expandable ? ' ' : (open ? '−' : '+'),
      icon: o.grounded
          ? groundedPinIcon
          : (o.isSubAssembly ? assemblyCubeIcon : componentCubeIcon),
      label: o.id,
      active: identical(asm.selected, o),
      onTap: () {
        if (expandable) {
          setState(() {
            if (!_compOpen.remove(key)) _compOpen.add(key);
          });
        }
        app.selectOccurrence(identical(asm.selected, o) ? null : o);
      },
      trailing: _EyeButton(
          visible: o.visible,
          onTap: () => app.setOccurrenceVisible(o, !o.visible)),
    );
    return o.visible ? row : Opacity(opacity: 0.45, child: row);
  }

  /// Which components are disclosed, by their full nested path.
  final Set<String> _compOpen = {};

  /// M246 — a component and, when it is a SUBASSEMBLY and disclosed, the tree
  /// beneath it. The native tree's twin; see _componentRows there for why the
  /// path is slash-separated and what nests under what.
  List<Widget> _componentRows(
      AppState app, AssemblyModel asm, AssemblyOccurrence o,
      {required double indent, required String path}) {
    final key = '$path${o.id}';
    final rels = asm.constraintsOn(o.id);
    final sub = o.sub;
    final open = _compOpen.contains(key);
    return [
      _componentRow(app, asm, o, indent: indent, key: key),
      if (open) ...[
        // Inventor nests every constraint under each component it touches, as
        // well as listing it in the folder above.
        for (final c in rels)
          _constraintRow(app, asm, c, indent: indent + 22),
        if (sub != null)
          for (final child in sub.occurrences)
            ..._componentRows(app, sub, child,
                indent: indent + 22, path: '$key/'),
      ],
    ];
  }

  /// M248 — one pattern, and its elements when it is disclosed.
  ///
  /// The elements go through [_componentRows] unchanged, because that is what
  /// they are: ordinary occurrences with their own eye and their own
  /// relationships. Only the parent row is new — and its EYE is the pattern's
  /// suppression set rather than a visibility flag, which is Inventor's own
  /// verb for an element and the reason an element has no Delete.
  List<Widget> _patternRows(
      AppState app, AssemblyModel asm, AsmPattern p, {required double indent}) {
    final key = 'pat:${p.name}';
    final open = _compOpen.contains(key);
    final els = asm.elementsOf(p.name);
    final row = _row(
      indent: indent,
      exp: els.isEmpty ? ' ' : (open ? '−' : '+'),
      icon: asmPatternIcon,
      label: p.name,
      onTap: () {
        if (els.isEmpty) return;
        setState(() {
          if (!_compOpen.remove(key)) _compOpen.add(key);
        });
      },
      // A pattern whose last regeneration failed keeps its row and says why:
      // it is the row the user has to reach to repair it.
      trailing: p.error == null
          ? null
          : Tooltip(
              message: p.error!,
              child: SvgPicture.string(asmSickIcon, width: 11, height: 11)),
    );
    return [
      row,
      if (open)
        for (final e in els)
          ..._componentRows(app, asm, e, indent: indent + 22, path: ''),
    ];
  }

  /// M242 — one relationship. Tapping selects it, tapping the selected one
  /// again opens the dialog on it (there is no double-tap in this tree); a
  /// long press is the Edit / Suppress / Delete menu, matching the native
  /// browser's context menu on the same row.
  Widget _constraintRow(AppState app, AssemblyModel asm, AsmConstraint c,
      {required double indent}) {
    final t = L.of(context);
    final selected = identical(asm.selectedConstraint, c);
    final row = _row(
      indent: indent,
      icon: c.suppressed ? asmSuppressedIcon : asmConstraintIcon,
      label: c.name,
      active: selected,
      // Tap once to select, again to open — the same stand-in for a
      // double-click the native tree uses, since neither has one.
      onTap: () {
        if (!selected) {
          app.selectConstraint(c);
        } else if (c.isJoint) {
          app.openJoint(edit: c);
        } else {
          app.openConstraint(edit: c);
        }
      },
      // A SICK constraint is marked rather than described: the badge is the
      // signal, and the sentence is in the tooltip where it does not have to
      // fit in a 300 pt panel.
      // The row's own actions live behind a ⋯ button, because this tree has
      // no long-press menu and the native one (which does) puts Edit /
      // Suppress / Delete on exactly this row.
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (c.isSick && !c.suppressed)
          Tooltip(
              message: app.constraintErrorText(c),
              child: SvgPicture.string(themedIcon(asmSickIcon),
                  width: 13, height: 13)),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _constraintMenu(app, c),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('⋯', style: ts(12, T.dim)),
          ),
        ),
      ]),
    );
    final dim = c.suppressed;
    final wrapped = dim ? Opacity(opacity: 0.45, child: row) : row;
    return Tooltip(
      message:
          '${constraintLabel(t, c.kind)} · ${solutionLabel(t, c.solution)}',
      child: wrapped,
    );
  }

  Future<void> _constraintMenu(AppState app, AsmConstraint c) async {
    final box = context.findRenderObject();
    final at = box is RenderBox
        ? box.localToGlobal(Offset.zero) & box.size
        : Rect.zero;
    final t = L.of(context);
    final pick = await showMenu<String>(
      context: context,
      color: T.fly,
      position: RelativeRect.fromLTRB(at.left + 40, at.top + 80, at.right, at.bottom),
      items: [
        PopupMenuItem(value: 'edit', height: 36, child: Text(t.edit, style: ts(12.5, T.text))),
        // M249 — Inventor's own entry point for Drive: "the Drive dialog box
        // opens when you right-click a relationship in the browser and select
        // Drive". Only on the relationships that HAVE something to sweep —
        // Symmetry and Transitional carry no value and no shaft.
        if (canDriveConstraint(c))
          PopupMenuItem(
              value: 'drive',
              height: 36,
              child: Text(t.ctxDrive, style: ts(12.5, T.text))),
        PopupMenuItem(
            value: 'suppress',
            height: 36,
            child: Text(c.suppressed ? t.ctxUnsuppress : t.ctxSuppress,
                style: ts(12.5, T.text))),
        PopupMenuItem(
            value: 'delete',
            height: 36,
            child: Text(t.delete, style: ts(12.5, T.err))),
      ],
    );
    if (!mounted) return;
    switch (pick) {
      case 'edit':
        // M249 — a joint edits in the Joint dialog, a constraint in Place
        // Constraint. One row, one verb, two panels: which one is decided by
        // what the relationship IS, never by which folder it was reached from.
        if (c.isJoint) {
          app.openJoint(edit: c);
        } else {
          app.openConstraint(edit: c);
        }
      case 'drive':
        app.openDrive(c);
      case 'suppress':
        app.toggleConstraintSuppressed(c);
      case 'delete':
        app.deleteConstraint(c);
    }
  }

  /// A solid body in the Solid Bodies folder (Inventor). The eye toggles the
  /// whole body's visibility; the label is its bodyName.
  Widget _bodyRow(AppState app, PartModel part, String bodyName,
      List<PartFeature> feats) {
    final on = feats.any((f) => f.visible);
    // M97 — while the extrude dialog is waiting for a target body, a body row
    // is a PICK: hovering highlights it (in the 3D view too, since both read
    // app.hoverBody) and a tap chooses it. Outside that mode the row behaves
    // exactly as before.
    final picking = app.pickingBody;
    final hot = picking && app.hoverBody == bodyName;
    // Outside a pick the row is Inventor's ordinary selection: tap to select
    // (row highlighted here, body tinted in 3D — both read app.selectedBody),
    // tap the selected one again to clear it.
    final sel = !picking && app.selectedBody == bodyName;
    final row = _row(
      indent: 30,
      icon: partCubeIcon,
      label: bodyName,
      active: sel,
      onTap: picking
          ? () => app.pickBody(bodyName)
          : () => app.toggleBodySelected(bodyName),
      trailing: _EyeButton(
          visible: on, onTap: () => app.toggleBodyVisible(part, bodyName)),
    );
    // …and hovering one prehighlights it the same way, at half the strength of
    // the selection: the row here, the body in 3D (both read
    // app.browserHoverBody). A selected row keeps the selected look — two
    // washes on one body would only compound into a third colour that means
    // nothing, which is the rule the assembly tint follows too.
    final warm = !picking && !sel && app.browserHoverBody == bodyName;
    Widget out = Container(
      key: _bodyKeyFor(bodyName),
      color: hot
          ? T.accent.withValues(alpha: 0.28)
          : (warm ? T.accent.withValues(alpha: 0.14) : null),
      child: row,
    );
    // The hover is published in BOTH modes — as the dialog's target pick while
    // one is armed (it re-previews the boolean), as the plain prehighlight
    // otherwise.
    out = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        if (picking) {
          app.setHoverBody(bodyName);
        } else {
          app.setBrowserHoverBody(bodyName);
        }
      },
      onExit: (_) {
        if (picking) {
          app.setHoverBody(null);
        } else {
          app.setBrowserHoverBody(null);
        }
      },
      child: out,
    );
    return on ? out : Opacity(opacity: 0.45, child: out);
  }

  Widget _originRow(AppState app, PartModel part, String label, String key) {
    final on = part.vis[key] == true;
    final row = _row(
      indent: 30,
      icon: switch (key) {
        'yz' || 'xz' || 'xy' => planeIcon,
        'x' => xAxisIcon,
        'y' => yAxisIcon,
        'z' => zAxisIcon,
        _ => centerPointIcon,
      },
      label: label,
      trailing:
          _EyeButton(visible: on, onTap: () => app.togglePartOriginVis(key)),
    );
    return on ? row : Opacity(opacity: 0.45, child: row);
  }

  /// Sketch row with Inventor's per-sketch Visibility eye. Double-tap opens
  /// the sketch for editing (consumed ones too — Inventor allows reuse).
  Widget _sketchRow(AppState app, ChildSketch cs,
      {required double indent, bool nested = false}) {
    // The TOP-LEVEL copy of a shared sketch carries the badge; the nested
    // instance under its parent feature keeps the plain cube, so the two rows
    // are told apart at a glance (they carry the same name).
    final badged = cs.shared && !nested;
    final row = GestureDetector(
      onDoubleTap: () => app.openChildSketch(cs.model.name),
      child: Container(
        key: _sketchKeyFor(cs.model.name, nested),
        child: _row(
          indent: indent,
          exp: ' ',
          icon: badged ? sharedSketchCubeIcon : sketchCubeIcon,
          label: cs.model.name,
          // M212 — while a sketch-driven pattern is asking for its points, a
          // single tap on a sketch row picks that sketch.
          active: app.patternSession?.pointSketch == cs.model.name,
          onTap: () => app.patternToggleSketch(cs),
          trailing: _EyeButton(
              visible: cs.visible, onTap: () => app.toggleSketchVisible(cs)),
        ),
      ),
    );
    return cs.visible ? row : Opacity(opacity: 0.45, child: row);
  }

  /// One feature row (Extrusion1, ...): eye toggles it, double-tap edits
  /// it in the properties panel, long-press / right-click deletes. The "+"
  /// expander reveals the consumed sketch nested beneath (M59, Inventor).
  Widget _featureRow(AppState app, PartModel part, PartFeature f,
      {bool rolled = false}) {
    final broken = f.computeError != null;
    final consumedSketch = part.sketchByName(f.sketchName);
    final nests = consumedSketch != null &&
        identical(firstConsumerOf(part, f.sketchName), f);
    final open = _expandedFeatures.contains(f.name);
    // M212 — a pattern nests its OCCURRENCES the way Inventor lists them, so
    // one can be suppressed on its own. It consumes no sketch, so the two
    // uses of the expander never collide.
    final pat = f is PatternFeature ? f : null;
    final nestsOcc = pat != null && pat.occurrenceCount > 1;
    final canExpand = nests || nestsOcc;
    final row = _row(
      indent: 8,
      exp: canExpand ? (open ? '-' : '+') : ' ',
      // M255 — a DERIVED body is a link to another document, and the row says
      // so: it is the one feature in the tree whose shape is decided
      // somewhere else.
      icon: broken
          ? endOfSketchIcon
          : (f is DeriveFeature ? derivedCubeIcon : partCubeIcon),
      label: f.name,
      // While the pattern panel is picking features, a SINGLE tap picks this
      // one — the same rule the native browser follows.
      active: app.patternHasFeature(f.name),
      onTap: () {
        if (app.patternToggleFeature(f)) return;
        if (canExpand) {
          setState(() => open
              ? _expandedFeatures.remove(f.name)
              : _expandedFeatures.add(f.name));
        }
      },
      trailing: _EyeButton(
          visible: f.visible, onTap: () => app.toggleFeatureVisible(f)),
    );
    final wrapped = Listener(
      key: _featureKeyFor(f.name),
      onPointerDown: (e) {
        if (e.kind == PointerDeviceKind.mouse &&
            e.buttons == kSecondaryMouseButton) {
          _confirmDeleteFeature(f);
        }
      },
      child: GestureDetector(
        onDoubleTap: () => app.editFeature(f),
        onLongPress: () => _confirmDeleteFeature(f),
        child: broken ? Tooltip(message: f.computeError!, child: row) : row,
      ),
    );
    // M91 — below End of Part: dimmed exactly like a rolled-back layer, so a
    // part that is showing an earlier state of itself says so.
    Widget dim(Widget w) => rolled ? Opacity(opacity: 0.4, child: w) : w;
    if (pat != null && open) {
      return dim(Column(mainAxisSize: MainAxisSize.min, children: [
        wrapped,
        for (var i = 2; i <= pat.occurrenceCount; i++)
          _occurrenceRow(app, pat, i),
      ]));
    }
    if (!nests || !open) return dim(wrapped);
    // expanded: the consumed sketch sits nested one level deeper, with its
    // own eye — Inventor's Extrusion1 ▸ Sketch1
    return dim(Column(mainAxisSize: MainAxisSize.min, children: [
      wrapped,
      _sketchRow(app, consumedSketch, indent: 30, nested: true),
    ]));
  }

  /// One occurrence of a pattern. Tapping it suppresses or restores it,
  /// which is Inventor's "suppress an individual occurrence" — the reason the
  /// occurrences are listed at all.
  Widget _occurrenceRow(AppState app, PatternFeature f, int index) {
    final off = f.suppressed.contains(index);
    final row = _row(
      indent: 30,
      icon: partCubeIcon,
      label: L.of(context).nodeOccurrence(index),
      onTap: () => app.patternSuppressOccurrence(f, index, !off),
      trailing: _EyeButton(
          visible: !off,
          onTap: () => app.patternSuppressOccurrence(f, index, !off)),
    );
    return off ? Opacity(opacity: 0.4, child: row) : row;
  }

  Future<void> _confirmDeleteFeature(PartFeature f) async {
    final ok = await confirmAction(
      context,
      title: L.of(context).dlgDeleteNamed(f.name),
      message: L.of(context).msgFeatureAndSolidRemoved,
      confirmLabel: L.of(context).delete,
    );
    if (ok) await widget.app.deleteFeature(f);
  }

  Widget _layerRow(AppState app, String layer, {bool rolled = false}) {
    final active = app.editingLayer == layer;
    final row = _row(
      indent: 8,
      exp: ' ',
      icon: layerRowIcon,
      label: layer,
      active: active,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (app.layerLocked(layer)) const _LockedMark(),
        // no eye below the marker — a rolled-back layer is switched off by
        // the marker itself, exactly like Inventor's suppressed features
        if (!rolled)
          _EyeButton(
            visible: app.layerVisible(layer),
            onTap: () => app.toggleLayerVisible(layer),
          ),
      ]),
    );
    return Listener(
      key: _keyFor(layer),
      onPointerDown: (e) {
        if (e.kind == PointerDeviceKind.mouse &&
            e.buttons == kSecondaryMouseButton) {
          _showCtx(e.position, layer);
        }
      },
      child: GestureDetector(
        // Inventor: features below the EOP cannot be edited; enterEdit's own
        // guard would toast, but a dead double-tap is clearer than a scold.
        onDoubleTap: rolled ? null : () => app.enterEdit(layer),
        onLongPressStart: NativeMenu.isSupported
            ? null // the UIKit menu owns the long press on device
            : (d) => _showCtx(d.globalPosition, layer),
        child: rolled
            ? Opacity(opacity: 0.45, child: row) // dimmed, like Inventor
            : row,
      ),
    );
  }

  Widget _row(
      {required double indent,
      String? exp,
      required String icon,
      required String label,
      bool active = false,
      Widget? trailing,
      VoidCallback? onTap}) {
    return _TreeRow(
        indent: indent,
        exp: exp,
        icon: icon,
        label: label,
        active: active,
        trailing: trailing,
        onTap: onTap);
  }
}

class _TreeRow extends StatefulWidget {
  final double indent;
  final String? exp;
  final String icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  /// Right-aligned control (the layer's visibility eye).
  final Widget? trailing;
  const _TreeRow(
      {required this.indent,
      this.exp,
      required this.icon,
      required this.label,
      this.trailing,
      this.active = false,
      this.onTap});
  @override
  State<_TreeRow> createState() => _TreeRowState();
}

class _TreeRowState extends State<_TreeRow> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 23,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: widget.active
              ? BoxDecoration(
                  color: T.mbActiveBg,
                  border: Border.all(color: T.mbActiveOutline, width: 1),
                )
              : BoxDecoration(color: _h ? T.mbHover : Colors.transparent),
          child: Row(children: [
            SizedBox(width: widget.indent),
            if (widget.exp != null)
              SizedBox(
                width: 11,
                child: Text(widget.exp!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 10, color: T.mbDim, fontFamily: 'Menlo')),
              ),
            const SizedBox(width: 6),
            SvgPicture.string(themedIcon(widget.icon), width: 15, height: 15),
            const SizedBox(width: 6),
            Expanded(
              child: Text(widget.label,
                  style: ts(12.5, widget.active ? T.text : T.mbText),
                  overflow: TextOverflow.ellipsis),
            ),
            if (widget.trailing != null) widget.trailing!,
          ]),
        ),
      ),
    );
  }
}

class _CtxRow extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final bool danger;
  const _CtxRow(
      {required this.label, required this.onTap, this.danger = false});
  @override
  State<_CtxRow> createState() => _CtxRowState();
}

class _CtxRowState extends State<_CtxRow> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: double.infinity,
          color: _h ? T.flyHov : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Text(widget.label,
              style:
                  ts(12.5, widget.danger ? T.err : T.mbText)),
        ),
      ),
    );
  }
}

/// Layer visibility toggle. A hidden layer is not drawn, not picked, not
/// snapped and not grippable — the eye is the single switch for all of it.
/// M250 — the "+" on the View folder: Inventor's right-click New, as a
/// button.
///
/// The native tree puts New in the row's context menu, where Inventor's is.
/// This tree has context menus only on the rows that already had them (layers
/// and features), and adding one here would be an overlay, a hit-test and a
/// dismiss path for a single item — so the affordance is a trailing glyph
/// instead, in the slot the visibility eye occupies on every other row.
class _PlusButton extends StatefulWidget {
  final String tip;
  final VoidCallback onTap;
  const _PlusButton({required this.tip, required this.onTap});
  @override
  State<_PlusButton> createState() => _PlusButtonState();
}

class _PlusButtonState extends State<_PlusButton> {
  bool _h = false;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: widget.tip,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _h = true),
          onExit: (_) => setState(() => _h = false),
          child: GestureDetector(
            onTap: widget.onTap,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.add,
                  size: 14, color: _h ? T.mbText : T.mbDim),
            ),
          ),
        ),
      );
}

class _EyeButton extends StatefulWidget {
  final bool visible;
  final VoidCallback onTap;
  const _EyeButton({required this.visible, required this.onTap});
  @override
  State<_EyeButton> createState() => _EyeButtonState();
}

class _EyeButtonState extends State<_EyeButton> {
  bool _h = false;

  @override
  Widget build(BuildContext context) {
    final on = widget.visible;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Icon(
            on ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            size: 14,
            color: on
                ? (_h ? T.mbText : T.mbDim)
                : (_h ? T.mbText : T.mbDimmed),
          ),
        ),
      ),
    );
  }
}

/// Layer lock toggle. A locked layer stays visible but is read-only: no tool
/// activates on it and its geometry can't be picked, dragged or constrained.
/// Shown faint when unlocked so it stays discoverable without cluttering the
/// row; a closed padlock in the accent red once locked.
/// Lock STATE marker. A locked layer stays visible but is read-only: no tool,
/// drag or delete touches it. Only LOCKED layers carry the padlock — an
/// unlocked layer shows nothing, because an open padlock on every row was
/// permanent noise for the default state. Locking and unlocking happen through
/// the row's right-click / long-press menu, which is also where Rename and
/// Delete live, so nothing became unreachable.
class _LockedMark extends StatelessWidget {
  const _LockedMark();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Icon(Icons.lock_outline, size: 14, color: T.err),
    );
  }
}
