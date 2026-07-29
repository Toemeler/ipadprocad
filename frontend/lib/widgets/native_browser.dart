// Prototype — the model browser as native Apple UI (M107).
//
// This file is the TRANSLATION LAYER only: AppState in, a flat list of
// [GlassRow] out, and events back. UIKit does the drawing, the indentation,
// the disclosure, the context menus and the End of Part drag; nothing here
// paints or hit-tests.
//
// Keeping the mapping in Dart (rather than teaching Swift about parts and
// sketches) means the browser's RULES stay in one place — timeline order,
// shared-sketch pinning, what counts as rolled back — and the native side
// stays a dumb, fast renderer.
import 'package:flutter/material.dart';
import 'package:native_menu/native_menu.dart';

import '../app_state.dart';
import '../part_model.dart';

/// Row id prefixes, so an event can be routed without ambiguity. Layer names
/// are arbitrary user text, hence the separators.
const String kIdLayer = 'ly:';
const String kIdSketch = 'sk:';
const String kIdNested = 'skn:';
const String kIdFeature = 'ft:';
const String kIdBody = 'bd:';
const String kIdOrigin = 'or:';
const String kIdEos = '__eos__';
const String kIdEop = '__eop__';

/// Builds the whole tree for the current document.
List<GlassRow> buildBrowserRows(
  AppState app, {
  required Set<String> expanded,
  int? dragEop,
  bool collapsed = false,
}) {
  // M118 — COLLAPSED: the timeline only, as icons. Sketches, features and the
  // End of Part marker are the spine of the document; the folders (Solid
  // Bodies, Origin) and the labels are what you open the panel FOR, so they
  // are what a collapse removes. Every row keeps its id, so a tap still does
  // the same thing at either width.
  if (collapsed) {
    final part = app.activeChild == null ? app.currentPart : null;
    if (part == null) return const [];
    final rows = <GlassRow>[];
    final timeline = partTimeline(part);
    final eop = (dragEop ?? part.eopAfter).clamp(0, timeline.length);
    for (var ti = 0; ti < timeline.length; ti++) {
      final n = timeline[ti];
      if (ti == eop) rows.add(_eopRow(compact: true));
      if (n.isFeature) {
        final f = n.feature!;
        rows.add(GlassRow(
          id: '$kIdFeature${f.name}',
          label: '',
          symbol: f.computeError != null ? 'exclamationmark.triangle' : 'cube',
          tint: f.computeError != null ? 'red' : null,
          dim: !f.visible || f.rolledBack,
          menu: _featureMenu(f),
        ));
      } else {
        final cs = n.sketch!;
        rows.add(GlassRow(
          id: '$kIdSketch${cs.model.name}',
          label: '',
          symbol: n.sharedCopy ? 'link' : 'square.on.square',
          tint: 'blue',
          dim: !cs.visible || cs.rolledBack,
          menu: _sketchMenu(part, cs),
        ));
      }
    }
    if (eop >= timeline.length) rows.add(_eopRow(compact: true));
    return rows;
  }
  final rows = <GlassRow>[];
  final part = app.activeChild == null ? app.currentPart : null;
  final s = app.current;

  rows.add(GlassRow(
    id: 'root',
    label: app.activeChild?.name ?? app.curTab ?? 'Sketch1',
    symbol: part != null ? 'cube' : 'square.on.square',
    tint: 'blue',
  ));

  if (part != null) {
    // ---- solid bodies -----------------------------------------------------
    final bodies = part.solidBodies();
    if (bodies.isNotEmpty) {
      rows.add(GlassRow(
        id: 'bodies',
        label: 'Solid Bodies(${bodies.length})',
        symbol: 'folder',
        depth: 1,
        expandable: true,
        expanded: expanded.contains('bodies'),
      ));
      if (expanded.contains('bodies')) {
        for (final (name, feats) in bodies) {
          final on = feats.any((f) => f.visible);
          rows.add(GlassRow(
            id: '$kIdBody$name',
            label: name,
            symbol: 'cube',
            depth: 2,
            hasEye: true,
            eyeOn: on,
            dim: !on,
            selected: app.pickingBody && app.hoverBody == name,
            menu: _bodyMenu(app, on),
          ));
        }
      }
    }

    // ---- origin -----------------------------------------------------------
    rows.add(GlassRow(
      id: 'origin',
      label: 'Origin',
      symbol: 'folder',
      depth: 1,
      expandable: true,
      expanded: expanded.contains('origin'),
    ));
    if (expanded.contains('origin')) {
      for (final (key, label, sym) in const [
        ('yz', 'YZ Plane', 'square.on.square'),
        ('xz', 'XZ Plane', 'square.on.square'),
        ('xy', 'XY Plane', 'square.on.square'),
        ('x', 'X Axis', 'line.diagonal'),
        ('y', 'Y Axis', 'line.diagonal'),
        ('z', 'Z Axis', 'line.diagonal'),
        ('cp', 'Center Point', 'smallcircle.filled.circle'),
      ]) {
        final on = part.vis[key] == true;
        rows.add(GlassRow(
          id: '$kIdOrigin$key',
          label: label,
          symbol: sym,
          depth: 2,
          hasEye: true,
          eyeOn: on,
          dim: !on,
        ));
      }
    }

    // ---- the timeline: sketches and features in creation order ------------
    // M113 — the marker counts ROWS now, so its position is simply an index
    // into the timeline. No conversion, and it can stand above a sketch.
    final timeline = partTimeline(part);
    final eop = (dragEop ?? part.eopAfter).clamp(0, timeline.length);
    for (var ti = 0; ti < timeline.length; ti++) {
      final n = timeline[ti];
      if (ti == eop) rows.add(_eopRow());
      if (n.isFeature) {
        final f = n.feature!;
        final consumed = part.sketchByName(f.sketchName);
        final nests = consumed != null &&
            identical(firstConsumerOf(part, f.sketchName), f);
        rows.add(GlassRow(
          id: '$kIdFeature${f.name}',
          label: f.name,
          symbol: f.computeError != null ? 'exclamationmark.triangle' : 'cube',
          tint: f.computeError != null ? 'red' : null,
          depth: 1,
          hasEye: true,
          eyeOn: f.visible,
          dim: !f.visible || f.rolledBack,
          expandable: nests,
          expanded: expanded.contains(f.name),
          menu: _featureMenu(f),
        ));
        if (nests && expanded.contains(f.name)) {
          rows.add(GlassRow(
            id: '$kIdNested${consumed.model.name}',
            label: consumed.model.name,
            symbol: 'square.on.square',
            tint: 'blue',
            depth: 2,
            hasEye: true,
            eyeOn: consumed.visible,
            dim: !consumed.visible,
            menu: _sketchMenu(part, consumed),
          ));
        }
      } else {
        final cs = n.sketch!;
        rows.add(GlassRow(
          id: '$kIdSketch${cs.model.name}',
          label: cs.model.name,
          // A SHARED sketch is marked, as Inventor marks it — link, because
          // that is what sharing means here.
          symbol: n.sharedCopy ? 'link' : 'square.on.square',
          tint: 'blue',
          depth: 1,
          hasEye: true,
          eyeOn: cs.visible,
          dim: !cs.visible || cs.rolledBack,
          menu: _sketchMenu(part, cs),
        ));
      }
    }
    if (eop >= timeline.length) rows.add(_eopRow());
    return rows;
  }

  // ---- sketch document: layers + End of Sketch -----------------------------
  if (s != null) {
    for (var i = 0; i < s.layers.length; i++) {
      final layer = s.layers[i];
      if (i == s.eosAfter.clamp(0, s.layers.length)) rows.add(_eosRow());
      final on = !s.hiddenLayers.contains(layer);
      rows.add(GlassRow(
        id: '$kIdLayer$layer',
        label: layer,
        symbol: 'square.3.layers.3d',
        depth: 1,
        hasEye: true,
        eyeOn: on,
        dim: !on || i >= s.eosAfter,
        selected: layer == app.editingLayer,
        menu: _layerMenu(),
      ));
    }
    if (s.eosAfter >= s.layers.length) rows.add(_eosRow());
  }
  return rows;
}

GlassRow _eopRow({bool compact = false}) => GlassRow(
      id: kIdEop,
      label: compact ? '' : 'End of Part',
      symbol: 'xmark.circle.fill',
      tint: 'red',
      depth: compact ? 0 : 1,
      isEop: true,
      menu: const [
        [
          GlassMenuItem(
              id: 'eoptop', title: 'Move to Top', symbol: 'arrow.up.to.line'),
          GlassMenuItem(
              id: 'eopend', title: 'Move to End', symbol: 'arrow.down.to.line'),
        ],
        [
          GlassMenuItem(
              id: 'eopDeleteBelow',
              title: 'Delete All Features Below EOP',
              symbol: 'trash',
              destructive: true),
        ],
      ],
    );

GlassRow _eosRow() => const GlassRow(
      id: kIdEos,
      label: 'End of Sketch',
      symbol: 'xmark.circle.fill',
      tint: 'red',
      depth: 1,
      menu: [
        [
          GlassMenuItem(
              id: 'eostop', title: 'Move to Top', symbol: 'arrow.up.to.line'),
          GlassMenuItem(
              id: 'eosend', title: 'Move to End', symbol: 'arrow.down.to.line'),
        ],
        [
          GlassMenuItem(
              id: 'deleteBelow',
              title: 'Delete all layers below',
              symbol: 'trash',
              destructive: true),
        ],
      ],
    );

List<List<GlassMenuItem>> _bodyMenu(AppState app, bool on) => [
      [
        if (app.extrudeSession != null)
          const GlassMenuItem(
              id: 'bdPick', title: 'Use as Target Body', symbol: 'scope'),
        GlassMenuItem(
            id: 'bdVisible',
            title: on ? 'Hide' : 'Show',
            symbol: on ? 'eye.slash' : 'eye'),
        const GlassMenuItem(id: 'bdRename', title: 'Rename', symbol: 'pencil'),
      ],
      [
        const GlassMenuItem(
            id: 'bdDelete',
            title: 'Delete Body',
            symbol: 'trash',
            destructive: true),
      ],
    ];

List<List<GlassMenuItem>> _featureMenu(PartFeature f) => [
      [
        const GlassMenuItem(
            id: 'ftEdit',
            title: 'Edit Feature',
            symbol: 'slider.horizontal.3'),
        GlassMenuItem(
            id: 'ftVisible',
            title: f.visible ? 'Hide' : 'Show',
            symbol: f.visible ? 'eye.slash' : 'eye'),
        const GlassMenuItem(id: 'ftRename', title: 'Rename', symbol: 'pencil'),
      ],
      [
        const GlassMenuItem(
            id: 'ftDelete',
            title: 'Delete',
            symbol: 'trash',
            destructive: true),
      ],
    ];

List<List<GlassMenuItem>> _sketchMenu(PartModel part, ChildSketch cs) {
  final consumed = sketchIsConsumed(part, cs);
  return [
    [
      const GlassMenuItem(
          id: 'skEdit', title: 'Edit Sketch', symbol: 'pencil.tip'),
      GlassMenuItem(
          id: 'skVisible',
          title: cs.visible ? 'Hide' : 'Show',
          symbol: cs.visible ? 'eye.slash' : 'eye'),
    ],
    [
      if (consumed && !cs.shared)
        const GlassMenuItem(
            id: 'skShare', title: 'Share Sketch', symbol: 'square.on.square'),
      if (canUnshareSketch(part, cs))
        const GlassMenuItem(
            id: 'skUnshare', title: 'Unshare', symbol: 'square.slash'),
    ],
  ];
}

List<List<GlassMenuItem>> _layerMenu() => [
      [
        const GlassMenuItem(id: 'edit', title: 'Edit Layer', symbol: 'pencil'),
        const GlassMenuItem(id: 'rename', title: 'Rename', symbol: 'character.cursor.ibeam'),
        const GlassMenuItem(id: 'move', title: 'Move Selection Here', symbol: 'arrow.right.doc.on.clipboard'),
      ],
      [
        const GlassMenuItem(
            id: 'delete', title: 'Delete', symbol: 'trash', destructive: true),
      ],
    ];
