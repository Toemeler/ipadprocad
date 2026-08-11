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

/// M165 — a user work plane row. They were created and saved but appeared
/// NOWHERE in the browser, so the only evidence a plane existed was the toast.
const String kIdWorkPlane = 'wp:';
// M213 — work axes and work points, interleaved by seq exactly like
// work planes and for exactly the same reasons (see planesBefore).
const String kIdWorkAxis = 'wa:';
const String kIdWorkPoint = 'wpt:';
const String kIdBody = 'bd:';
const String kIdOrigin = 'or:';
const String kIdEos = '__eos__';
const String kIdEop = '__eop__';

/// Builds the whole tree for the current document.
///
/// M200 — RETRACTED is a view of the same tree, not a different one. It used
/// to be a separate code path that drew only the part timeline, which meant
/// the panel went blank inside a sketch (there is no part there) and dropped
/// the folders in a part. "when the Modell browser is retracted i still want
/// to see all icons from it ... in 2d but also in 3d": so the collapse now
/// takes the tree it would have drawn and strips what there is no room for —
/// the labels, the indentation, the eye, and (M204) the disclosure box, which
/// no longer fits beside a glyph on the 56 pt card. Every id, glyph, tint, dim
/// state, selection and menu survives, so the narrow panel does everything the
/// wide one does and expanding again cannot show something different.
List<GlassRow> buildBrowserRows(
  AppState app, {
  required Set<String> expanded,
  int? dragEop,
  bool collapsed = false,
}) {
  final rows = _buildRows(app, expanded: expanded, dragEop: dragEop);
  return collapsed ? [for (final r in rows) r.compact()] : rows;
}

List<GlassRow> _buildRows(
  AppState app, {
  required Set<String> expanded,
  int? dragEop,
}) {
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
        // M129 — Inventor draws its container folders as FILLED amber, not a
        // grey outline; the two are the only true folders in the tree.
        symbol: 'folder.fill',
        tint: 'folder',
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
      symbol: 'folder.fill',
      tint: 'folder',
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
    // M169 — user work planes sit at their CREATION position, like everything
    // else the user made: a plane created after three extrusions belongs under
    // them. M165 put them in a block above the timeline, which read as an
    // "Origin"-style folder and is not where Inventor shows them.
    //
    // They are still not partTimeline NODES, deliberately: that list is what
    // the End of Part marker indexes into, and adding a third node kind would
    // shift the marker in every existing document — M113's whole point is that
    // it counts ROWS. A work plane is not rolled back by EOP either. So they
    // are interleaved by `seq` while the marker keeps counting only the
    // timeline's own rows.
    // M213 — ONE interleaved stream for all three work-feature kinds. They
    // were three separate emitters for about ten minutes, which put every
    // axis after every plane regardless of when either was made — the exact
    // "block of things grouped by type" layout M169 removed for planes.
    final work = <(int, GlassRow)>[
      for (final w in part.workPlanes)
        (
          w.seq,
          GlassRow(
            id: '$kIdWorkPlane${w.seq}',
            label: w.name,
            symbol: 'squareshape.dashed.squareshape',
            tint: 'blue',
            depth: 1,
            hasEye: true,
            eyeOn: w.visible,
            dim: !w.visible,
            selected: app.selectedWorkPlane?.seq == w.seq,
            menu: _workPlaneMenu(app, w),
          )
        ),
      for (final a in part.workAxes)
        (
          a.seq,
          GlassRow(
            id: '$kIdWorkAxis${a.seq}',
            label: a.name,
            symbol: 'line.diagonal',
            tint: 'blue',
            depth: 1,
            hasEye: true,
            eyeOn: a.visible,
            dim: !a.visible,
            selected: app.selectedWorkAxis?.seq == a.seq,
            menu: _workAxisMenu(a),
          )
        ),
      for (final pt in part.workPoints)
        (
          pt.seq,
          GlassRow(
            id: '$kIdWorkPoint${pt.seq}',
            label: pt.name,
            symbol: pt.grounded ? 'pin.fill' : 'smallcircle.filled.circle',
            tint: 'blue',
            depth: 1,
            hasEye: true,
            eyeOn: pt.visible,
            dim: !pt.visible,
            selected: app.selectedWorkPoint?.seq == pt.seq,
            menu: _workPointMenu(pt),
          )
        ),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    var nextPlane = 0;
    void planesBefore(int seq) {
      while (nextPlane < work.length && work[nextPlane].$1 < seq) {
        rows.add(work[nextPlane++].$2);
      }
    }

    final timeline = partTimeline(part);
    final eop = (dragEop ?? part.eopAfter).clamp(0, timeline.length);
    for (var ti = 0; ti < timeline.length; ti++) {
      final n = timeline[ti];
      planesBefore(n.isFeature ? n.feature!.seq : n.sketch!.seq);
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
          // M182 — the expansion key MUST be the row id ('ft:Name'): the host
          // stores exactly what onExpand handed it. It used to look up the
          // bare name here, so the set held 'ft:Extrusion1' while the row
          // asked for 'Extrusion1' — the chevron never expanded and the
          // consumed sketch could not be revealed.
          expanded: expanded.contains('$kIdFeature${f.name}'),
          menu: _featureMenu(f),
        ));
        if (nests && expanded.contains('$kIdFeature${f.name}')) {
          rows.add(GlassRow(
            id: '$kIdNested${consumed.model.name}',
            label: consumed.model.name,
            symbol: 'square.on.square',
            tint: 'blue',
            depth: 2,
            hasEye: true,
            eyeOn: consumed.visible,
            dim: !consumed.visible,
            selected: app.activeChild?.name == consumed.model.name,
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
          // M121 — the sketch you are currently inside is highlighted.
          selected: app.activeChild?.name == cs.model.name,
          menu: _sketchMenu(part, cs),
        ));
      }
    }
    // Planes made after the last timeline row still belong in the list, and
    // ABOVE End of Part — a work plane is never rolled back.
    planesBefore(1 << 30);
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

GlassRow _eopRow() => const GlassRow(
      id: kIdEop,
      label: 'End of Part',
      symbol: 'xmark.circle.fill',
      tint: 'red',
      depth: 1,
      isEop: true,
      menu: [
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

/// M169 — Inventor's work-plane context menu. Only the entries that DO
/// something appear: "Edit Offset" is meaningless on a midplane, which has no
/// base to measure from, so it is omitted rather than shown dead (M157).
List<List<GlassMenuItem>> _workPlaneMenu(AppState app, WorkPlane w) => [
      [
        // M181 — FIRST, as in Inventor. This is the route that cannot miss:
        // "Start 2D Sketch" then a tap in the viewport has to beat a solid
        // face and the origin planes the command itself switched on, and
        // failing that race is what "I still can't sketch on a work plane"
        // has been every time. Naming the plane leaves nothing to hit.
        const GlassMenuItem(
            id: 'wpSketch', title: 'Create Sketch', symbol: 'square.on.square'),
        if (w.offsetEditable)
          const GlassMenuItem(
              id: 'wpOffset', title: 'Edit Offset', symbol: 'ruler'),
        GlassMenuItem(
            id: 'wpVis',
            title: w.visible ? 'Hide' : 'Show',
            symbol: w.visible ? 'eye.slash' : 'eye'),
      ],
      [
        const GlassMenuItem(
            id: 'wpDelete',
            title: 'Delete',
            symbol: 'trash',
            destructive: true),
      ],
    ];

/// M213 — a work axis's row menu. No "Edit": unlike a work plane's offset
/// there is no single number behind an axis to change, so offering an editor
/// that could only re-open the pick flow would be a button that lies.
List<List<GlassMenuItem>> _workAxisMenu(WorkAxis a) => [
      [
        GlassMenuItem(
            id: 'waVis',
            title: a.visible ? 'Hide' : 'Show',
            symbol: a.visible ? 'eye.slash' : 'eye'),
        // The axis carries a SIGN that revolve and pattern directions inherit
        // (see WorkAxis.flip), and re-picking two points in the other order to
        // change it would be absurd.
        const GlassMenuItem(
            id: 'waFlip',
            title: 'Flip Direction',
            symbol: 'arrow.up.arrow.down'),
      ],
      [
        const GlassMenuItem(
            id: 'waDelete',
            title: 'Delete',
            symbol: 'trash',
            destructive: true),
      ],
    ];

List<List<GlassMenuItem>> _workPointMenu(WorkPoint pt) => [
      [
        GlassMenuItem(
            id: 'wptVis',
            title: pt.visible ? 'Hide' : 'Show',
            symbol: pt.visible ? 'eye.slash' : 'eye'),
      ],
      [
        const GlassMenuItem(
            id: 'wptDelete',
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
    [
      // M152 — Delete. Offered only when the sketch is NOT consumed: deleting
      // a sketch an extrusion is built on would take the feature with it, and
      // Inventor makes you remove the feature first for the same reason.
      if (!consumed)
        const GlassMenuItem(
            id: 'skDelete',
            title: 'Delete',
            symbol: 'trash',
            destructive: true),
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
