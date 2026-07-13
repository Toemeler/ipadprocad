// iPadProCAD — model browser (300px, Inventor style), 1:1 port of #mb.
// Tree: blue cube "SketchName", Origin folder (+/- expander) with X Axis /
// Y Axis / Center Point (auto-projected), then the layer container, then
// "End of Sketch". Right-click on a layer row -> context menu (Edit on top),
// double-click -> edit mode. Active layer row highlighted Inventor-style.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../app_state.dart';
import '../svg_icons.dart';
import '../theme.dart';

class ModelBrowser extends StatefulWidget {
  final AppState app;
  const ModelBrowser({super.key, required this.app});
  @override
  State<ModelBrowser> createState() => _ModelBrowserState();
}

class _ModelBrowserState extends State<ModelBrowser> {
  bool originOpen = false;
  OverlayEntry? _ctx;

  void _closeCtx() {
    _ctx?.remove();
    _ctx = null;
  }

  @override
  void dispose() {
    _closeCtx();
    super.dispose();
  }

  void _showCtx(Offset globalPos, String layer) {
    _closeCtx();
    final app = widget.app;
    final locked = app.layerLocked(layer);
    final base = app.isBaseLayer(layer);
    final selCount = app.selection.length;
    final items = <Widget>[
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
      if (!base)
        _ctxItem('Delete layer', () {
          _closeCtx();
          _confirmDelete(layer);
        }, danger: true),
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

  Future<void> _promptRename(String layer) async {
    final ctrl = TextEditingController(text: layer);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF292D33),
        title: Text('Rename layer', style: ts(14, T.mbText)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: ts(13, Colors.white),
          cursorColor: T.blue,
          decoration: InputDecoration(
            hintText: 'Layer name',
            hintStyle: ts(13, T.mbDim),
            enabledBorder:
                const UnderlineInputBorder(borderSide: BorderSide(color: T.sep)),
            focusedBorder:
                const UnderlineInputBorder(borderSide: BorderSide(color: T.blue)),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel', style: ts(13, T.mbDim))),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text),
              child: Text('Rename', style: ts(13, T.blue))),
        ],
      ),
    );
    ctrl.dispose();
    if (result != null) widget.app.renameLayer(layer, result);
  }

  Future<void> _confirmDelete(String layer) async {
    final app = widget.app;
    final s = app.current;
    final count =
        s == null ? 0 : s.geometry.where((g) => g.layer == layer).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF292D33),
        title: Text('Delete “$layer”?', style: ts(14, T.mbText)),
        content: Text(
          count == 0
              ? 'This layer is empty and will be removed.'
              : 'This removes the layer and its $count '
                  '${count == 1 ? "entity" : "entities"}. This can’t be undone.',
          style: ts(12.5, T.mbDim),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel', style: ts(13, T.mbDim))),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Delete', style: ts(13, const Color(0xFFE05A56))),
          ),
        ],
      ),
    );
    if (ok == true) widget.app.deleteLayer(layer);
  }

  Widget _ctxItem(String label, VoidCallback onTap, {bool danger = false}) {
    return _CtxRow(label: label, onTap: onTap, danger: danger);
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final s = app.current;
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text('+', style: ts(15, T.mbDim)),
            ),
            const Spacer(),
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text('🔍', style: ts(13, T.mbDim))),
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text('☰', style: ts(13, T.mbDim))),
          ]),
        ),
        // tree
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 5),
            children: [
              _row(
                indent: 0,
                exp: ' ',
                icon: sketchCubeIcon,
                label: app.curTab ?? 'Sketch1',
              ),
              _row(
                indent: 8,
                exp: originOpen ? '−' : '+',
                icon: originIcon,
                label: 'Origin',
                onTap: () => setState(() => originOpen = !originOpen),
              ),
              if (originOpen) ...[
                _row(indent: 30, icon: xAxisIcon, label: 'X Axis'),
                _row(indent: 30, icon: yAxisIcon, label: 'Y Axis'),
                Tooltip(
                  message: 'Automatically projected',
                  child:
                      _row(indent: 30, icon: centerPointIcon, label: 'Center Point'),
                ),
              ],
              // layers container
              if (s != null)
                for (final layer in s.layers)
                  _layerRow(app, layer),
              _row(indent: 8, exp: ' ', icon: endOfSketchIcon, label: 'End of Sketch'),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _layerRow(AppState app, String layer) {
    final active = app.editingLayer == layer;
    return Listener(
      onPointerDown: (e) {
        if (e.kind == PointerDeviceKind.mouse &&
            e.buttons == kSecondaryMouseButton) {
          _showCtx(e.position, layer);
        }
      },
      child: GestureDetector(
        onDoubleTap: () => app.enterEdit(layer),
        child: _row(
          indent: 8,
          exp: ' ',
          icon: layerRowIcon,
          label: layer,
          active: active,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            _LockButton(
              locked: app.layerLocked(layer),
              onTap: () => app.toggleLayerLocked(layer),
            ),
            _EyeButton(
              visible: app.layerVisible(layer),
              onTap: () => app.toggleLayerVisible(layer),
            ),
          ]),
        ),
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
class _LockButton extends StatefulWidget {
  final bool locked;
  final VoidCallback onTap;
  const _LockButton({required this.locked, required this.onTap});
  @override
  State<_LockButton> createState() => _LockButtonState();
}

class _LockButtonState extends State<_LockButton> {
  bool _h = false;

  @override
  Widget build(BuildContext context) {
    final locked = widget.locked;
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
            locked ? Icons.lock_outline : Icons.lock_open_outlined,
            size: 14,
            color: locked
                ? const Color(0xFFD65A56)
                : (_h ? T.mbText : T.mbDimmed),
          ),
        ),
      ),
    );
  }
}
