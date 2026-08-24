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
import '../assembly.dart';
import '../part_model.dart';
import '../l10n/l.dart';

/// The current strings.
///
/// This file is a pure model-to-rows translation with no BuildContext
/// anywhere in it — the rows are handed to a UIKit view over a method
/// channel, not built as widgets — so it reads the app-wide language
/// directly. The app has exactly one, so there is nothing to disagree with.
AppL10n get t => L.current;

/// Row id prefixes, so an event can be routed without ambiguity. Layer names
/// are arbitrary user text, hence the separators.
const String kIdLayer = 'ly:';
const String kIdSketch = 'sk:';
const String kIdNested = 'skn:';
const String kIdFeature = 'ft:';

/// M165 — a user work plane row. They were created and saved but appeared
/// NOWHERE in the browser, so the only evidence a plane existed was the toast.
const String kIdWorkPlane = 'wp:';
// M215 — work axes and work points, interleaved by seq exactly like
// work planes and for exactly the same reasons (see planesBefore).
const String kIdWorkAxis = 'wa:';
const String kIdWorkPoint = 'wpt:';
const String kIdBody = 'bd:';
const String kIdOrigin = 'or:';

/// M212 — one OCCURRENCE of a pattern feature: `oc:<feature>#<index>`, with
/// the index in Inventor's numbering (the original is 1). Suppressing one is
/// a property of the pattern, so the row addresses the pattern plus a number
/// rather than an object of its own.
const String kIdOccurrence = 'oc:';

/// M240 — one placed ASSEMBLY COMPONENT: `cp:<Part>:<n>`. The occurrence id
/// already carries a colon, which is exactly why the prefix is matched and the
/// rest taken whole rather than split on the separator.
const String kIdComponent = 'cp:';

/// M240 — the assembly's two container folders.
const String kIdRepresentations = '__reprs__';
const String kIdRelationships = '__rels__';
const String kIdEos = '__eos__';
const String kIdEop = '__eop__';

/// The Origin folder's seven entries: key, label, SF Symbol.
///
/// M240 — a getter rather than a const, because the labels are localised and
/// a const would freeze the language of whichever locale loaded first. One
/// list, so the part tree and the assembly tree cannot disagree about what an
/// Origin folder holds.
List<(String, String, String)> get kOriginRows => [
      ('yz', t.nodeYzPlane, 'square.on.square'),
      ('xz', t.nodeXzPlane, 'square.on.square'),
      ('xy', t.nodeXyPlane, 'square.on.square'),
      ('x', t.nodeXAxis, 'line.diagonal'),
      ('y', t.nodeYAxis, 'line.diagonal'),
      ('z', t.nodeZAxis, 'line.diagonal'),
      ('cp', t.nodeCenterPoint, 'smallcircle.filled.circle'),
    ];

/// M240 — the context menu on a placed component.
///
/// Grounded and Delete, and nothing else: rename would rename the OCCURRENCE
/// and an occurrence is named after the part it is an instance of, so a free
/// name there would be a second thing to keep in step for no gain. Visibility
/// is the row's own eye.
List<List<GlassMenuItem>> _componentMenu(AssemblyOccurrence o) => [
      [
        GlassMenuItem(
            id: 'cpGrounded',
            title: t.ctxGrounded,
            symbol: o.grounded ? 'pin.fill' : 'pin'),
      ],
      [
        GlassMenuItem(
            id: 'cpDelete',
            title: t.delete,
            symbol: 'trash',
            destructive: true),
      ],
    ];

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
  final asm = app.currentAssembly;
  final s = app.current;

  rows.add(GlassRow(
    id: 'root',
    label: app.activeChild?.name ?? app.curTab ?? 'Sketch1',
    symbol: asm != null
        ? 'square.stack.3d.up'
        : part != null
            ? 'cube'
            : 'square.on.square',
    tint: 'blue',
  ));

  // ---- M240: the ASSEMBLY tree ------------------------------------------
  //
  // Representations, Relationships, Origin, then the placed components — in
  // Inventor's own order. The first two are empty containers today and are
  // listed anyway, because they are what tells you an assembly document is
  // open at all; the Origin folder and the components are live.
  if (asm != null) {
    rows.add(GlassRow(
      id: kIdRepresentations,
      label: t.nodeRepresentations,
      symbol: 'folder.fill',
      tint: 'folder',
      depth: 1,
      expandable: true,
      expanded: expanded.contains(kIdRepresentations),
    ));
    rows.add(GlassRow(
      id: kIdRelationships,
      label: t.nodeRelationships,
      symbol: 'folder.fill',
      tint: 'folder',
      depth: 1,
      expandable: true,
      expanded: expanded.contains(kIdRelationships),
    ));
    rows.add(GlassRow(
      id: 'origin',
      label: t.nodeOrigin,
      symbol: 'folder.fill',
      tint: 'folder',
      depth: 1,
      expandable: true,
      expanded: expanded.contains('origin'),
    ));
    if (expanded.contains('origin')) {
      for (final (key, label, sym) in kOriginRows) {
        final on = asm.vis[key] == true;
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
    for (final o in asm.occurrences) {
      rows.add(GlassRow(
        id: '$kIdComponent${o.id}',
        label: o.id,
        // A grounded component takes Inventor's pin, the same glyph a
        // grounded work point already uses in this tree.
        symbol: o.grounded ? 'pin.fill' : 'cube',
        depth: 1,
        hasEye: true,
        eyeOn: o.visible,
        // A component whose source part is gone still gets a row — that is
        // how the user finds out and removes it — and it is dimmed, because
        // nothing of it is on screen.
        dim: !o.visible || !o.loaded,
        selected: identical(asm.selected, o),
        menu: _componentMenu(o),
      ));
    }
    return rows;
  }

  if (part != null) {
    // ---- solid bodies -----------------------------------------------------
    final bodies = part.solidBodies();
    if (bodies.isNotEmpty) {
      rows.add(GlassRow(
        id: 'bodies',
        label: t.nodeSolidBodies(bodies.length),
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
            selected: app.pickingBody
                ? app.hoverBody == name
                : app.selectedBody == name,
            menu: _bodyMenu(app, on),
          ));
        }
      }
    }

    // ---- origin -----------------------------------------------------------
    rows.add(GlassRow(
      id: 'origin',
      label: t.nodeOrigin,
      symbol: 'folder.fill',
      tint: 'folder',
      depth: 1,
      expandable: true,
      expanded: expanded.contains('origin'),
    ));
    if (expanded.contains('origin')) {
      for (final (key, label, sym) in kOriginRows) {
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
    // M215 — ONE interleaved stream for all three work-feature kinds. They
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
        // M212 — a pattern's OCCURRENCES nest under it, exactly as Inventor
        // lists them, so one of them can be suppressed without touching the
        // rest. A pattern never nests a consumed sketch (it consumes none),
        // so the two uses of the chevron cannot collide.
        final pat = f is PatternFeature ? f : null;
        rows.add(GlassRow(
          id: '$kIdFeature${f.name}',
          label: f.name,
          symbol: f.computeError != null
              ? 'exclamationmark.triangle'
              : (pat == null ? 'cube' : _patternSymbol(pat.mode)),
          tint: f.computeError != null ? 'red' : null,
          depth: 1,
          hasEye: true,
          eyeOn: f.visible,
          dim: !f.visible || f.rolledBack,
          // M212 — while the pattern panel is picking features, a tap on a
          // feature row ADDS it to the selection, so it is highlighted like
          // any other picked thing.
          selected: app.patternHasFeature(f.name),
          expandable: nests || (pat != null && pat.occurrenceCount > 1),
          // M182 — the expansion key MUST be the row id ('ft:Name'): the host
          // stores exactly what onExpand handed it. It used to look up the
          // bare name here, so the set held 'ft:Extrusion1' while the row
          // asked for 'Extrusion1' — the chevron never expanded and the
          // consumed sketch could not be revealed.
          expanded: expanded.contains('$kIdFeature${f.name}'),
          menu: _featureMenu(f),
        ));
        if (pat != null && expanded.contains('$kIdFeature${f.name}')) {
          for (var i = 2; i <= pat.occurrenceCount; i++) {
            final off = pat.suppressed.contains(i);
            rows.add(GlassRow(
              id: '$kIdOccurrence${f.name}#$i',
              label: t.nodeOccurrence(i),
              symbol: off ? 'circle.dashed' : 'cube',
              depth: 2,
              dim: off,
              menu: [
                [
                  GlassMenuItem(
                      id: off ? 'ocRestore' : 'ocSuppress',
                      title: off ? t.ctxRestoreOccurrence : t.ctxSuppressOccurrence,
                      symbol: off ? 'eye' : 'eye.slash'),
                ]
              ],
            ));
          }
        }
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

GlassRow _eopRow() => GlassRow(
      id: kIdEop,
      label: t.nodeEndOfPart,
      symbol: 'xmark.circle.fill',
      tint: 'red',
      depth: 1,
      isEop: true,
      menu: [
        [
          GlassMenuItem(
              id: 'eoptop', title: t.ctxMoveToTop, symbol: 'arrow.up.to.line'),
          GlassMenuItem(
              id: 'eopend', title: t.ctxMoveToEnd, symbol: 'arrow.down.to.line'),
        ],
        [
          GlassMenuItem(
              id: 'eopDeleteBelow',
              title: t.ctxDeleteAllFeaturesBelowEop,
              symbol: 'trash',
              destructive: true),
        ],
      ],
    );

GlassRow _eosRow() => GlassRow(
      id: kIdEos,
      label: t.nodeEndOfSketch,
      symbol: 'xmark.circle.fill',
      tint: 'red',
      depth: 1,
      menu: [
        [
          GlassMenuItem(
              id: 'eostop', title: t.ctxMoveToTop, symbol: 'arrow.up.to.line'),
          GlassMenuItem(
              id: 'eosend', title: t.ctxMoveToEnd, symbol: 'arrow.down.to.line'),
        ],
        [
          GlassMenuItem(
              id: 'deleteBelow',
              title: t.ctxDeleteAllLayersBelow,
              symbol: 'trash',
              destructive: true),
        ],
      ],
    );

List<List<GlassMenuItem>> _bodyMenu(AppState app, bool on) => [
      [
        if (app.extrudeSession != null)
          GlassMenuItem(
              id: 'bdPick', title: t.ctxUseAsTargetBody, symbol: 'scope'),
        GlassMenuItem(
            id: 'bdVisible',
            title: on ? t.hide : t.ctxShow,
            symbol: on ? 'eye.slash' : 'eye'),
        GlassMenuItem(id: 'bdRename', title: t.rename, symbol: 'pencil'),
      ],
      [
        GlassMenuItem(
            id: 'bdDelete',
            title: t.ctxDeleteBody,
            symbol: 'trash',
            destructive: true),
      ],
    ];

/// SF Symbol for each pattern kind, so the browser row says WHICH pattern it
/// is without opening it.
String _patternSymbol(PatternKind k) => switch (k) {
      PatternKind.rectangular => 'square.grid.3x3',
      PatternKind.circular => 'circle.grid.cross',
      PatternKind.sketchDriven => 'point.3.connected.trianglepath.dotted',
      PatternKind.mirror => 'flip.horizontal',
    };

List<List<GlassMenuItem>> _featureMenu(PartFeature f) => [
      [
        GlassMenuItem(
            id: 'ftEdit',
            title: t.ctxEditFeature,
            symbol: 'slider.horizontal.3'),
        GlassMenuItem(
            id: 'ftVisible',
            title: f.visible ? t.hide : t.ctxShow,
            symbol: f.visible ? 'eye.slash' : 'eye'),
        GlassMenuItem(id: 'ftRename', title: t.rename, symbol: 'pencil'),
      ],
      [
        GlassMenuItem(
            id: 'ftDelete',
            title: t.delete,
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
        GlassMenuItem(
            id: 'wpSketch', title: t.ctxCreateSketch, symbol: 'square.on.square'),
        if (w.offsetEditable)
          GlassMenuItem(
              id: 'wpOffset', title: t.ctxEditOffset, symbol: 'ruler'),
        GlassMenuItem(
            id: 'wpVis',
            title: w.visible ? t.hide : t.ctxShow,
            symbol: w.visible ? 'eye.slash' : 'eye'),
      ],
      [
        GlassMenuItem(
            id: 'wpDelete',
            title: t.delete,
            symbol: 'trash',
            destructive: true),
      ],
    ];

/// M215 — a work axis's row menu. No "Edit": unlike a work plane's offset
/// there is no single number behind an axis to change, so offering an editor
/// that could only re-open the pick flow would be a button that lies.
List<List<GlassMenuItem>> _workAxisMenu(WorkAxis a) => [
      [
        GlassMenuItem(
            id: 'waVis',
            title: a.visible ? t.hide : t.ctxShow,
            symbol: a.visible ? 'eye.slash' : 'eye'),
        // The axis carries a SIGN that revolve and pattern directions inherit
        // (see WorkAxis.flip), and re-picking two points in the other order to
        // change it would be absurd.
        GlassMenuItem(
            id: 'waFlip',
            title: t.ctxFlipDirection,
            symbol: 'arrow.up.arrow.down'),
      ],
      [
        GlassMenuItem(
            id: 'waDelete',
            title: t.delete,
            symbol: 'trash',
            destructive: true),
      ],
    ];

List<List<GlassMenuItem>> _workPointMenu(WorkPoint pt) => [
      [
        GlassMenuItem(
            id: 'wptVis',
            title: pt.visible ? t.hide : t.ctxShow,
            symbol: pt.visible ? 'eye.slash' : 'eye'),
      ],
      [
        GlassMenuItem(
            id: 'wptDelete',
            title: t.delete,
            symbol: 'trash',
            destructive: true),
      ],
    ];

List<List<GlassMenuItem>> _sketchMenu(PartModel part, ChildSketch cs) {
  final consumed = sketchIsConsumed(part, cs);
  return [
    [
      GlassMenuItem(
          id: 'skEdit', title: t.ctxEditSketch, symbol: 'pencil.tip'),
      GlassMenuItem(
          id: 'skVisible',
          title: cs.visible ? t.hide : t.ctxShow,
          symbol: cs.visible ? 'eye.slash' : 'eye'),
    ],
    [
      if (consumed && !cs.shared)
        GlassMenuItem(
            id: 'skShare', title: t.ctxShareSketch, symbol: 'square.on.square'),
      if (canUnshareSketch(part, cs))
        GlassMenuItem(
            id: 'skUnshare', title: t.ctxUnshare, symbol: 'square.slash'),
    ],
    [
      // M152 — Delete. Offered only when the sketch is NOT consumed: deleting
      // a sketch an extrusion is built on would take the feature with it, and
      // Inventor makes you remove the feature first for the same reason.
      if (!consumed)
        GlassMenuItem(
            id: 'skDelete',
            title: t.delete,
            symbol: 'trash',
            destructive: true),
    ],
  ];
}

List<List<GlassMenuItem>> _layerMenu() => [
      [
        GlassMenuItem(id: 'edit', title: t.ctxEditLayer, symbol: 'pencil'),
        GlassMenuItem(id: 'rename', title: t.rename, symbol: 'character.cursor.ibeam'),
        GlassMenuItem(id: 'move', title: t.ctxMoveSelectionHere, symbol: 'arrow.right.doc.on.clipboard'),
      ],
      [
        GlassMenuItem(
            id: 'delete', title: t.delete, symbol: 'trash', destructive: true),
      ],
    ];
