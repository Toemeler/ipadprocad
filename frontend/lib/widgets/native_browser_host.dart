// Prototype — mounts the native browser and routes its events (M107).
//
// On iOS the panel is UIKit on Liquid Glass; everywhere else the original
// Flutter tree is used unchanged, so the desktop/host-test path keeps working
// and nothing here can regress it.
import 'package:flutter/material.dart';
import 'package:native_menu/native_menu.dart';

import '../app_state.dart';
import '../part_model.dart';
import 'model_browser.dart';
import 'native_browser.dart';
import 'native_prompts.dart';

class NativeModelBrowser extends StatefulWidget {
  final AppState app;
  const NativeModelBrowser({super.key, required this.app});

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

  AppState get app => widget.app;

  @override
  Widget build(BuildContext context) {
    if (!GlassBrowser.isSupported) return ModelBrowser(app: app);
    return AnimatedBuilder(
      animation: app,
      builder: (_, __) => SizedBox(
        width: 300,
        child: GlassBrowser(
          rows: buildBrowserRows(app, expanded: _expanded, dragEop: _dragEop),
          onTap: _onTap,
          onEye: _onEye,
          onExpand: (id, on) => setState(() {
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
    );
  }

  // -- events ---------------------------------------------------------------

  void _onTap(String id) {
    final part = app.currentPart;
    if (id.startsWith(kIdBody) && app.pickingBody) {
      app.pickBody(id.substring(kIdBody.length));
      return;
    }
    if (id.startsWith(kIdLayer)) {
      app.enterEdit(id.substring(kIdLayer.length));
      return;
    }
    if (id.startsWith(kIdSketch) || id.startsWith(kIdNested)) {
      final n = id.startsWith(kIdNested)
          ? id.substring(kIdNested.length)
          : id.substring(kIdSketch.length);
      app.openChildSketch(n);
      return;
    }
    if (id.startsWith(kIdFeature) && part != null) {
      final f = _feature(part, id.substring(kIdFeature.length));
      if (f != null) app.openExtrude(f);
    }
  }

  void _onEye(String id) {
    final part = app.currentPart;
    if (id.startsWith(kIdLayer)) {
      app.toggleLayerVisible(id.substring(kIdLayer.length));
    } else if (id.startsWith(kIdOrigin)) {
      app.togglePartOriginVis(id.substring(kIdOrigin.length));
    } else if (id.startsWith(kIdBody) && part != null) {
      app.toggleBodyVisible(part, id.substring(kIdBody.length));
    } else if (id.startsWith(kIdFeature) && part != null) {
      final f = _feature(part, id.substring(kIdFeature.length));
      if (f != null) app.toggleFeatureVisible(f);
    } else if (id.startsWith(kIdSketch) || id.startsWith(kIdNested)) {
      final n = id.startsWith(kIdNested)
          ? id.substring(kIdNested.length)
          : id.substring(kIdSketch.length);
      final cs = part?.sketchByName(n);
      if (cs != null) app.toggleSketchVisible(cs);
    }
  }

  Future<void> _onMenu(String id, String item) async {
    final part = app.currentPart;
    if (id == kIdEop && part != null) {
      switch (item) {
        case 'eoptop':
          app.setEndOfPart(0);
          break;
        case 'eopend':
          app.setEndOfPart(partBuildOrder(part).length);
          break;
        case 'eopDeleteBelow':
          app.deleteBelowEndOfPart();
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
              title: 'Rename body',
              initialValue: name,
              placeholder: 'Body name',
              confirmLabel: 'Rename');
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
          app.openExtrude(f);
          break;
        case 'ftVisible':
          app.toggleFeatureVisible(f);
          break;
        case 'ftRename':
          final r = await promptForText(context,
              title: 'Rename feature',
              initialValue: f.name,
              placeholder: 'Feature name',
              confirmLabel: 'Rename');
          if (r != null && r.trim().isNotEmpty) app.renameFeature(f, r.trim());
          break;
        case 'ftDelete':
          await app.deleteFeature(f);
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
              title: 'Rename layer',
              initialValue: layer,
              placeholder: 'Layer name',
              confirmLabel: 'Rename');
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
    _eopStart ??= part.eopAfter.clamp(0, partBuildOrder(part).length);
    final n = partBuildOrder(part).length;
    setState(() => _dragEop = (_eopStart! + steps).clamp(0, n));
  }

  void _onEopEnd() {
    final v = _dragEop;
    _eopStart = null;
    setState(() => _dragEop = null);
    if (v != null) app.setEndOfPart(v);
  }

  ExtrudeFeature? _feature(PartModel p, String name) {
    for (final f in p.features) {
      if (f.name == name) return f;
    }
    return null;
  }
}
