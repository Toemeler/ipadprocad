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
              constraints: const BoxConstraints(minWidth: 180),
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
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _ctxItem('Edit', () {
                  _closeCtx();
                  widget.app.enterEdit(layer);
                }),
                _ctxItem('Copy', _closeCtx),
                _ctxItem('Duplicate', _closeCtx),
                _ctxItem('Export only this layer', _closeCtx),
                _ctxItem('Toggle visibility', _closeCtx),
              ]),
            ),
          ),
        ),
      ]),
    );
    Overlay.of(context).insert(_ctx!);
  }

  Widget _ctxItem(String label, VoidCallback onTap) {
    return _CtxRow(label: label, onTap: onTap);
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
      VoidCallback? onTap}) {
    return _TreeRow(
        indent: indent,
        exp: exp,
        icon: icon,
        label: label,
        active: active,
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
  const _TreeRow(
      {required this.indent,
      this.exp,
      required this.icon,
      required this.label,
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
            Text(widget.label,
                style: ts(12.5, widget.active ? Colors.white : T.mbText),
                overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
    );
  }
}

class _CtxRow extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _CtxRow({required this.label, required this.onTap});
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
          child: Text(widget.label, style: ts(12.5, T.mbText)),
        ),
      ),
    );
  }
}
