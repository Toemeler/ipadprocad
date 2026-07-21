// iPadProCAD — model browser (300px, Inventor style), 1:1 port of #mb.
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
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:native_menu/native_menu.dart';

import '../app_state.dart';
import '../part_model.dart';
import '../svg_icons.dart';
import '../theme.dart';
import 'native_prompts.dart';

class ModelBrowser extends StatefulWidget {
  final AppState app;
  const ModelBrowser({super.key, required this.app});
  @override
  State<ModelBrowser> createState() => _ModelBrowserState();
}

class _ModelBrowserState extends State<ModelBrowser> {
  bool originOpen = false;
  OverlayEntry? _ctx;
  // M53 — End-of-Sketch drag: the marker's PREVIEW slot while the finger /
  // mouse moves; committed to the app on release, discarded on Escape.
  int? _dragEos;
  final GlobalKey _eosKey = GlobalKey();
  bool _eosEscInstalled = false;

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
          const NativeMenuItem(
              id: 'eophere',
              title: 'Move End of Sketch here',
              symbol: 'arrow.up.and.down.text.horizontal'),
        ],
        if (!base)
          [
            const NativeMenuItem(
                id: 'delete',
                title: 'Delete layer',
                symbol: 'trash',
                destructive: true),
          ],
      ];
    }
    return [
      [
        if (!locked)
          const NativeMenuItem(id: 'edit', title: 'Edit', symbol: 'pencil.tip'),
        NativeMenuItem(
            id: 'visible',
            title: app.layerVisible(layer) ? 'Hide' : 'Show',
            symbol: app.layerVisible(layer) ? 'eye.slash' : 'eye'),
        NativeMenuItem(
            id: 'lock',
            title: locked ? 'Unlock' : 'Lock',
            symbol: locked ? 'lock.open' : 'lock'),
        if (!base)
          const NativeMenuItem(id: 'rename', title: 'Rename', symbol: 'pencil'),
        NativeMenuItem(
            id: 'move',
            title: selCount == 0 ? 'Move selection here' : 'Move $selCount here',
            symbol: 'arrow.right.doc.on.clipboard'),
        const NativeMenuItem(
            id: 'eophere',
            title: 'Move End of Sketch here',
            symbol: 'arrow.up.and.down.text.horizontal'),
      ],
      if (!base)
        [
          const NativeMenuItem(
              id: 'delete',
              title: 'Delete layer',
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
          const NativeMenuItem(
              id: 'eostop', title: 'Move to Top', symbol: 'arrow.up.to.line'),
        if (eos < s.layers.length)
          const NativeMenuItem(
              id: 'eosend',
              title: 'Move to End',
              symbol: 'arrow.down.to.line'),
      ],
      if (eos < s.layers.length)
        [
          const NativeMenuItem(
              id: 'deleteBelow',
              title: 'Delete all layers below',
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
            title: 'End of Sketch',
            rect: hit,
            cornerRadius: 4,
            groups: _eosMenuGroups(s),
          ));
        }
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
        _ctxItem('Move End of Sketch here', () {
          _closeCtx();
          final i = app.current?.layers.indexOf(layer) ?? -1;
          if (i >= 0) app.setEndOfSketch(i + 1);
        }),
        if (!base)
          _ctxItem('Delete layer', () {
            _closeCtx();
            _confirmDelete(layer);
          }, danger: true),
      ],
      if (!rolled) ...[
      if (!locked)
        _ctxItem('Edit', () {
          _closeCtx();
          app.enterEdit(layer);
        }),
      _ctxItem(app.layerVisible(layer) ? 'Hide' : 'Show', () {
        _closeCtx();
        app.toggleLayerVisible(layer);
      }),
      _ctxItem(locked ? 'Unlock' : 'Lock', () {
        _closeCtx();
        app.toggleLayerLocked(layer);
      }),
      if (!base)
        _ctxItem('Rename…', () {
          _closeCtx();
          _promptRename(layer);
        }),
      _ctxItem(selCount == 0 ? 'Move selection here' : 'Move $selCount here', () {
        _closeCtx();
        app.moveSelectionToLayer(layer);
      }),
      _ctxItem('Move End of Sketch here', () {
        _closeCtx();
        final i = app.current?.layers.indexOf(layer) ?? -1;
        if (i >= 0) app.setEndOfSketch(i + 1);
      }),
      if (!base)
        _ctxItem('Delete layer', () {
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
                color: const Color(0xFF212429),
                border: Border.all(color: T.sep),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x8C000000),
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
  }

  void _showEosCtx(Offset globalPos) {
    _closeCtx();
    final app = widget.app;
    final s = app.current;
    if (s == null) return;
    final eos = _shownEos(s);
    final items = <Widget>[
      if (eos > 0)
        _ctxItem('Move to Top', () {
          _closeCtx();
          app.setEndOfSketch(0);
        }),
      if (eos < s.layers.length)
        _ctxItem('Move to End', () {
          _closeCtx();
          app.setEndOfSketch(s.layers.length);
        }),
      if (eos < s.layers.length)
        _ctxItem('Delete all layers below', () {
          _closeCtx();
          _confirmDeleteBelow();
        }, danger: true),
    ];
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
                color: const Color(0xFF212429),
                border: Border.all(color: T.sep),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x8C000000),
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
      title: 'Delete everything below End of Sketch?',
      message: 'This removes ${below.length} '
          '${below.length == 1 ? "layer" : "layers"} and '
          '$count ${count == 1 ? "entity" : "entities"}.',
      confirmLabel: 'Delete',
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
              indent: 8, exp: ' ', icon: endOfSketchIcon, label: 'End of Sketch'),
        ),
      ),
    );
  }

  Future<void> _promptRename(String layer) async {
    final app = widget.app;
    final result = await promptForText(
      context,
      title: 'Rename layer',
      initialValue: layer,
      placeholder: 'Layer name',
      confirmLabel: 'Rename',
    );
    if (result != null && result.trim().isNotEmpty) {
      app.renameLayer(layer, result);
    }
  }

  Future<void> _confirmDelete(String layer) async {
    final app = widget.app;
    final s = app.current;
    final count =
        s == null ? 0 : s.geometry.where((g) => g.layer == layer).length;
    final ok = await confirmAction(
      context,
      title: 'Delete “$layer”?',
      message: count == 0
          ? 'This layer is empty and will be removed.'
          : 'This removes the layer and its $count '
              '${count == 1 ? "entity" : "entities"}. This can’t be undone.',
      confirmLabel: 'Delete',
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
    // Layers appear, vanish and get renamed without this widget remounting.
    _schedulePush();
    return Container(
      width: 300,
      decoration: const BoxDecoration(
        color: T.mbBg,
        border: Border(right: BorderSide(color: T.mbBorder)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // header
        Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: const BoxDecoration(
            color: T.mbHead,
            border: Border(bottom: BorderSide(color: T.mbHeadBorder)),
          ),
          child: Row(children: [
            Container(
              height: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: const BoxDecoration(
                color: T.mbBg,
                border: Border(right: BorderSide(color: T.mbHeadBorder)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('Model', style: ts(12.5, T.mbText)),
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
            key: _treeKey,
            padding: const EdgeInsets.symmetric(vertical: 5),
            children: [
              _row(
                indent: 0,
                exp: ' ',
                icon: part != null ? partCubeIcon : sketchCubeIcon,
                label: app.activeChild?.name ?? app.curTab ?? 'Sketch1',
              ),
              _row(
                indent: 8,
                exp: originOpen ? '−' : '+',
                icon: originIcon,
                label: 'Origin',
                onTap: () => setState(() => originOpen = !originOpen),
              ),
              if (originOpen) ...[
                // A 3D part carries the FULL origin: 3 work planes, 3 axes
                // and the centre point, each with its own visibility eye
                // wired straight into the 3D scene (M56).
                if (part != null) ...[
                  for (final o in const [
                    ('YZ Plane', 'yz'),
                    ('XZ Plane', 'xz'),
                    ('XY Plane', 'xy'),
                    ('X Axis', 'x'),
                    ('Y Axis', 'y'),
                    ('Z Axis', 'z'),
                    ('Center Point', 'cp'),
                  ])
                    _originRow(app, part, o.$1, o.$2),
                ] else ...[
                  _row(indent: 30, icon: xAxisIcon, label: 'X Axis'),
                  _row(indent: 30, icon: yAxisIcon, label: 'Y Axis'),
                  Tooltip(
                    message: 'Automatically projected',
                    child: _row(
                        indent: 30, icon: centerPointIcon, label: 'Center Point'),
                  ),
                ],
              ],
              // A part shows its child sketches and features instead of
              // layers; the open child sketch falls through to the 2D tree.
              if (part != null && app.activeChild == null) ...[
                for (final cs in part.childSketches)
                  GestureDetector(
                    onDoubleTap: () => app.openChildSketch(cs.model.name),
                    child: _row(
                        indent: 8,
                        exp: ' ',
                        icon: sketchCubeIcon,
                        label: cs.model.name),
                  ),
                for (final f in part.features) _featureRow(app, f),
              ],
              // layers container, with the End-of-Sketch marker at its
              // slot (M53): everything after the marker renders rolled back
              if (s != null && part == null) ...[
                for (var i = 0; i < s.layers.length; i++) ...[
                  if (i == _shownEos(s)) _eosRow(app, s),
                  _layerRow(app, s.layers[i],
                      rolled: i >= _shownEos(s)),
                ],
                if (_shownEos(s) >= s.layers.length) _eosRow(app, s),
              ] else if (part == null)
                _row(indent: 8,
                    exp: ' ',
                    icon: endOfSketchIcon,
                    label: 'End of Sketch'),
            ],
          ),
          ),
        ),
      ]),
    );
  }

  Widget _originRow(
      AppState app, PartModel part, String label, String key) {
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
      trailing: _EyeButton(
          visible: on, onTap: () => app.togglePartOriginVis(key)),
    );
    return on ? row : Opacity(opacity: 0.45, child: row);
  }

  /// One feature row (Extrusion1, ...): eye toggles it, double-tap edits
  /// it in the properties panel, long-press / right-click deletes.
  Widget _featureRow(AppState app, ExtrudeFeature f) {
    final broken = f.computeError != null;
    final row = _row(
      indent: 8,
      exp: ' ',
      icon: broken ? endOfSketchIcon : partCubeIcon,
      label: f.name,
      trailing: _EyeButton(
          visible: f.visible, onTap: () => app.toggleFeatureVisible(f)),
    );
    return Listener(
      onPointerDown: (e) {
        if (e.kind == PointerDeviceKind.mouse &&
            e.buttons == kSecondaryMouseButton) {
          _confirmDeleteFeature(f);
        }
      },
      child: GestureDetector(
        onDoubleTap: () => app.openExtrude(f),
        onLongPress: () => _confirmDeleteFeature(f),
        child: broken
            ? Tooltip(message: f.computeError!, child: row)
            : row,
      ),
    );
  }

  Future<void> _confirmDeleteFeature(ExtrudeFeature f) async {
    final ok = await confirmAction(
      context,
      title: 'Delete “${f.name}”?',
      message: 'The feature and its solid are removed from the part.',
      confirmLabel: 'Delete',
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
                    style: const TextStyle(
                        fontSize: 10,
                        color: T.mbDim,
                        fontFamily: 'Menlo')),
              ),
            const SizedBox(width: 6),
            SvgPicture.string(widget.icon, width: 15, height: 15),
            const SizedBox(width: 6),
            Expanded(
              child: Text(widget.label,
                  style: ts(12.5, widget.active ? Colors.white : T.mbText),
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
  const _CtxRow({required this.label, required this.onTap, this.danger = false});
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
              style: ts(12.5,
                  widget.danger ? const Color(0xFFE05A56) : T.mbText)),
        ),
      ),
    );
  }
}


/// Layer visibility toggle. A hidden layer is not drawn, not picked, not
/// snapped and not grippable — the eye is the single switch for all of it.
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
                ? (_h ? Colors.white : T.mbDim)
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
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Icon(Icons.lock_outline, size: 14, color: Color(0xFFD65A56)),
    );
  }
}
