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
import '../clipboard.dart';
import '../asm_constraints.dart';
import '../asm_work_features.dart';
import '../asm_pattern.dart';
import '../asm_reps.dart';
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

/// M361 — THE LETTER A FEATURE WEARS IN THE RETRACTED PANEL.
///
///   "the icons in the retracted Modell browser should have a letter small on
///    a corner of the icon. E for extrude and a number. E2, E3 and so on or r
///    for revolve. ... Also W for workplane"
///
/// Retracted, the panel is a column of pictures and nothing else — no labels,
/// no indentation, no eye. Three extrusions draw the same cube three times,
/// and the only way to tell the second from the third was to open the panel
/// and read. The badge is the name, compressed to what fits in a corner: a
/// letter for the KIND and a number for which one of them this is.
///
/// The letters are ENGLISH initials, because that is how they were asked for
/// (E, R, W) and because the German ones collide hopelessly — Extrusion,
/// Erhebung; Bohrung, Abrundung; Arbeitsebene, Arbeitsachse, Arbeitspunkt,
/// Ableiten all start on the same three letters. Where two English initials
/// collide the rarer command takes two letters rather than an arbitrary
/// single one: "Sw2" is readable, "U2" for a sweep is a riddle.
///
/// The numbering is per LETTER and in tree order, so it is the ordinal you
/// would count off the panel — not the feature's `seq`, which counts every
/// kind together and would give a part with two extrusions E1 and E4.
const Map<String, String> kFeatureBadge = {
  'extrude': 'E',
  'revolve': 'R',
  'hole': 'H',
  'fillet': 'F',
  'chamfer': 'C',
  'pattern': 'P',
  'loft': 'L',
  'derive': 'D',
  'combine': 'B', // Boolean, and B is free where C is not
  'split': 'T', // Inventor calls it Trim Solid
  'deleteface': 'X',
  'direct': 'M', // Move Face
  'sweep': 'Sw',
  'coil': 'Co',
};

/// The letters for the things that are not part features: work geometry and
/// sketches. Same table, kept apart because they are numbered apart — a
/// document's third work plane is W3 however many extrusions sit between them.
const String kBadgeWorkPlane = 'W';
const String kBadgeWorkAxis = 'A';
const String kBadgeWorkPoint = 'N'; // P is the pattern's
const String kBadgeSketch = 'S';

/// Numbers a run of badge letters in the order they are handed over.
///
/// Its own object rather than a map built up in place, because the count has
/// to be per LETTER and per DOCUMENT: two calls for the same part must give
/// the same answers, and a second part opened beside it must start again at 1.
class BadgeCounter {
  final Map<String, int> _n = {};

  /// 'E' -> 'E1', then 'E2', ...
  String next(String letter) {
    final i = (_n[letter] ?? 0) + 1;
    _n[letter] = i;
    return '$letter$i';
  }

  /// The badge for a part feature, or null for a kind that has none.
  String? feature(String kind) {
    final l = kFeatureBadge[kind];
    return l == null ? null : next(l);
  }
}

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

/// M242 — one assembly RELATIONSHIP: `rel:<Mate:1>`. Same shape as
/// [kIdComponent] and for the same reason: the constraint's own name carries a
/// colon, so the prefix is matched and the rest taken whole.
const String kIdConstraint = 'rel:';

/// M248 — one assembly PATTERN: `pat:<RectangularPattern1>`. The pattern's own
/// name has no colon in it, but the rule is the same one and is followed for
/// the same reason: match the prefix, take the rest whole.
const String kIdAsmPattern = 'pat:';

/// M240 — the assembly's two container folders.
const String kIdRepresentations = '__reprs__';
const String kIdRelationships = '__rels__';

/// M250 — the three folders inside Representations. Two of them are drawn
/// dimmed and childless on purpose; asm_reps.dart says which and why.
const String kIdViewReps = '__viewreps__';
const String kIdPositionalReps = '__posreps__';
const String kIdLodReps = '__lodreps__';

/// M250 — one VIEW REPRESENTATION: `vr:<Default>`. The same prefix rule as
/// [kIdComponent] — match the prefix, take the rest whole — because a
/// representation's name is user text and can hold anything.
const String kIdViewRep = 'vr:';

/// M250 — the row at the top of a PART tree that says this part is being
/// edited inside an assembly, and takes you back to it.
const String kIdInPlaceReturn = '__inplace__';
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

/// M345 — the clipboard section every row that can be copied carries.
///
/// One builder rather than five copies of two rows: Copy and Cut mean the same
/// thing everywhere, they are always their own section (they neither change
/// how a thing looks, like the rows above them, nor destroy it, like Delete
/// below), and a menu that spelled them out per row is a menu where they drift
/// apart. The ids are per KIND, because the row already knows what it is and
/// the host has to route the tap without guessing.
List<GlassMenuItem> clipSection(String copyId, String cutId,
        {bool cut = true}) =>
    [
      GlassMenuItem(id: copyId, title: t.btnCopy, symbol: 'doc.on.doc'),
      if (cut)
        GlassMenuItem(id: cutId, title: t.btnCut, symbol: 'scissors'),
    ];

/// M345 — "Paste Sketch Here" on a plane row, offered only while the
/// clipboard actually holds sketch geometry.
///
/// Offered rather than dimmed: an empty clipboard is not a state of the plane,
/// and a row that is dark on every plane in a document nobody has copied
/// anything in is noise on seven rows of the Origin folder.
List<GlassMenuItem> pasteSketchSection(AppState app) =>
    app.clipboard is SketchClip
        ? [
            GlassMenuItem(
                id: 'pasteSketch',
                title: t.ctxPasteSketchHere,
                symbol: 'doc.on.clipboard')
          ]
        : const [];

/// M250 — the context menu on the View node: Inventor's right-click New.
List<List<GlassMenuItem>> _viewRepsMenu() => [
      [
        GlassMenuItem(
            id: 'vrNew', title: t.ctxNewViewRep, symbol: 'plus.circle'),
      ],
    ];

/// M250 — the context menu on one view representation.
///
/// Default carries neither Rename nor Delete, which is Inventor's rule and
/// this app's for the same reason: it is the name a document falls back to
/// when the active representation has gone, so something has to answer to it.
/// A representation that has never been CAPTURED — Default, before anything
/// made it necessary to write it down — has no Lock either: there is nothing
/// yet to lock.
List<List<GlassMenuItem>> _viewRepMenu(String name, AsmViewRep? rep) => [
      [
        GlassMenuItem(
            id: 'vrActivate',
            title: t.ctxActivateViewRep,
            symbol: 'checkmark.circle'),
        GlassMenuItem(
            id: 'vrUpdate',
            title: t.ctxUpdateViewRep,
            symbol: 'arrow.clockwise'),
        if (rep != null)
          GlassMenuItem(
              id: 'vrLock',
              title: rep.locked ? t.ctxUnlockViewRep : t.ctxLockViewRep,
              symbol: rep.locked ? 'lock.open' : 'lock'),
      ],
      if (name != kDefaultViewRep)
        [
          GlassMenuItem(
              id: 'vrRename',
              title: t.ctxRenameEllipsis,
              symbol: 'character.cursor.ibeam'),
          GlassMenuItem(
              id: 'vrDelete',
              title: t.ctxDeleteViewRep,
              symbol: 'trash',
              destructive: true),
        ],
    ];

/// M240 — the context menu on a placed component.
///
/// Grounded and Delete, and nothing else: rename would rename the OCCURRENCE
/// and an occurrence is named after the part it is an instance of, so a free
/// name there would be a second thing to keep in step for no gain. Visibility
/// is the row's own eye.
List<List<GlassMenuItem>> _componentMenu(AssemblyOccurrence o) {
  // M248 — a PATTERN ELEMENT has neither of the component menu's two verbs.
  // Ground is the solver's, and an element is already driven (asmBodyIsFree);
  // Delete would leave the pattern to place it again on the next solve, which
  // is why Inventor gives an element Suppress instead and no Delete at all.
  if (o.isPatternElement) {
    return [
      [
        GlassMenuItem(
            id: 'elSuppress',
            title: o.visible ? t.ctxSuppress : t.ctxUnsuppress,
            symbol: o.visible ? 'eye.slash' : 'eye'),
      ],
    ];
  }
  return [
    [
      // M250 — Inventor's Edit, which for an assembly component means EDIT IN
      // PLACE: the part opens with the rest of the assembly around it. Only
      // for a PART — a subassembly would open an assembly document, and "the
      // assembly around it" would then have to mean its parent, which is a
      // second case with its own camera and its own way back. AppState says
      // so out loud rather than offering a row that toasts a refusal.
      if (!o.isSubAssembly)
        GlassMenuItem(
            id: 'cpEditInPlace',
            title: t.ctxEditInPlace,
            symbol: 'pencil'),
      GlassMenuItem(
          id: 'cpGrounded',
          title: t.ctxGrounded,
          symbol: o.grounded ? 'pin.fill' : 'pin'),
    ],
    clipSection('cpCopy', 'cpCut'),
    [
      GlassMenuItem(
          id: 'cpDelete',
          title: t.delete,
          symbol: 'trash',
          destructive: true),
    ],
  ];
}

/// M248 — one PATTERN row, and its elements when it is disclosed.
///
/// The elements go through [_componentRows] unchanged, because that is what
/// they are: ordinary occurrences with their own eye, their own selection and
/// their own relationships. Only the parent row is new.
void _patternRows(List<GlassRow> rows, AssemblyModel asm, AsmPattern p,
    Set<String> expanded, {required int depth}) {
  final id = '$kIdAsmPattern${p.name}';
  final open = expanded.contains(id);
  final els = asm.elementsOf(p.name);
  rows.add(GlassRow(
    id: id,
    label: p.name,
    // A pattern whose last regeneration failed says so with the GLYPH, which
    // is how this tree already draws a sick constraint: the row stays, because
    // it is the row the user has to reach to repair it.
    symbol: p.error != null
        ? 'exclamationmark.triangle.fill'
        : (p.mode == PatternKind.mirror
            ? 'flip.horizontal'
            : 'square.grid.2x2'),
    tint: p.error != null ? 'red' : null,
    depth: depth,
    expandable: els.isNotEmpty,
    expanded: open,
    menu: [
      [GlassMenuItem(id: 'patEdit', title: t.edit, symbol: 'slider.horizontal.3')],
      [
        GlassMenuItem(
            id: 'patDelete', title: t.delete, symbol: 'trash', destructive: true)
      ],
    ],
  ));
  if (!open) return;
  for (final e in els) {
    _componentRows(rows, asm, e, expanded, depth: depth + 1, path: '');
  }
}

/// M246 — one component and, when it is a SUBASSEMBLY and disclosed, the
/// tree beneath it.
///
/// Inventor nests a subassembly's own browser under its occurrence, and the
/// rows down there are the real thing: each is selectable, has its own eye,
/// and lists its own relationships. What they are NOT is independently
/// draggable — a subassembly is one rigid body in its parent (see
/// asm_solver), so the parent's solver never sees the parts inside it.
///
/// [path] prefixes the row id so two occurrences of one subassembly do not
/// collide: `cp:Machine:1/Bracket:1`. The prefix is stripped by the host when
/// it resolves the row back to an occurrence.
void _componentRows(List<GlassRow> rows, AssemblyModel asm,
    AssemblyOccurrence o, Set<String> expanded,
    {required int depth, required String path}) {
  final id = '$kIdComponent$path${o.id}';
  final rels = asm.constraintsOn(o.id);
  final sub = o.sub;
  // A subassembly discloses its contents; a part discloses its relationships.
  final expandable = sub != null || rels.isNotEmpty;
  final open = expanded.contains(id);
  rows.add(GlassRow(
    id: id,
    label: o.id,
    // A grounded component takes Inventor's pin, the same glyph a grounded
    // work point already uses in this tree; a subassembly takes the stacked
    // cubes its own document root does.
    symbol: o.grounded
        ? 'pin.fill'
        : (o.isSubAssembly ? 'square.stack.3d.up' : 'cube'),
    depth: depth,
    hasEye: true,
    eyeOn: o.visible,
    // A component whose source document is gone still gets a row — that is
    // how the user finds out and removes it — and it is dimmed, because
    // nothing of it is on screen.
    dim: !o.visible || !o.loaded,
    selected: identical(asm.selected, o),
    // M242 — a component with relationships gains a disclosure box, so the
    // constraints ON it can be reached from the component rather than only
    // from the flat Relationships folder. That is Inventor's tree: every
    // constraint appears twice, once in the folder and once under each
    // component it touches.
    expandable: expandable,
    expanded: open,
    menu: _componentMenu(o),
  ));
  if (!open) return;
  for (final c in rels) {
    rows.add(_constraintRow(asm, c, depth: depth + 1));
  }
  if (sub == null) return;
  for (final child in sub.occurrences) {
    _componentRows(rows, sub, child, expanded,
        depth: depth + 1, path: '$path${o.id}/');
  }
}

/// M242 — one relationship row.
///
/// The three states it can be in are exactly Inventor's, and each is said
/// with the GLYPH rather than with a suffix on the label: healthy, SICK (the
/// solver could not meet it — a red badge), and SUPPRESSED (switched off — the
/// struck-through glyph, dimmed, which is how this tree already draws a
/// suppressed feature).
GlassRow _constraintRow(AssemblyModel asm, AsmConstraint c,
        {required int depth}) =>
    GlassRow(
      id: '$kIdConstraint${c.name}',
      label: c.name,
      symbol: c.suppressed
          ? 'link.badge.plus'
          : (c.isSick ? 'exclamationmark.triangle.fill' : 'link'),
      tint: c.isSick && !c.suppressed ? 'red' : null,
      depth: depth,
      dim: c.suppressed,
      selected: identical(asm.selectedConstraint, c),
      menu: _constraintMenu(c),
    );

/// M242 — the context menu on a relationship.
///
/// Edit / Suppress / Delete, which is Inventor's own three: a constraint has
/// no visibility of its own to toggle (the Show Relationships command works on
/// the whole assembly), and renaming one is done in the dialog's `>>` drawer
/// where the name is already shown.
List<List<GlassMenuItem>> _constraintMenu(AsmConstraint c) => [
      [
        GlassMenuItem(id: 'relEdit', title: t.edit, symbol: 'slider.horizontal.3'),
        // M249 — Drive, on the row Inventor puts it on. Symmetry and
        // Transitional carry no value and no shaft to turn, so the entry is
        // absent rather than present and inert; a context menu has no disabled
        // state on this tree, and an entry that did nothing would be worse
        // than one that is not offered.
        if (canDriveConstraint(c))
          GlassMenuItem(id: 'relDrive', title: t.ctxDrive, symbol: 'play.circle'),
        GlassMenuItem(
            id: 'relSuppress',
            title: c.suppressed ? t.ctxUnsuppress : t.ctxSuppress,
            symbol: c.suppressed ? 'eye' : 'eye.slash'),
      ],
      [
        GlassMenuItem(
            id: 'relDelete',
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
/// M243 — [hoverId] is the row under the pointer, which every row has to know
/// about rather than only the ones that mean something in 3D: retracted, the
/// hovered glyph is the only feedback there is.
List<GlassRow> buildBrowserRows(
  AppState app, {
  required Set<String> expanded,
  int? dragEop,
  bool collapsed = false,
  String? hoverId,
}) {
  final rows = _spaceFolders(_buildRows(app, expanded: expanded, dragEop: dragEop));
  return [
    for (final r in rows)
      (collapsed ? r.compact() : r).hover(hoverId != null && r.id == hoverId)
  ];
}

/// M361 — a gap where a folder BEGINS and where one ENDS.
///
///   "there should be spacing when a folder ends or starts"
///
/// The wide panel says this with indentation. The retracted one cannot —
/// [GlassRow.compact] takes the depth away, because a 34 pt column has no room
/// to indent in — so a part's timeline ran straight into the seven rows of its
/// Origin folder as one undifferentiated stack of glyphs. A gap is the only
/// grouping left when the words and the indentation have both gone.
///
/// Two rules, and the second is the one that is easy to forget: a gap above
/// every folder row (a folder STARTS), and a gap above the first row that
/// comes back OUT to a shallower depth (a folder ENDED). Without the second,
/// the last child of a folder and the next sibling of the folder itself are
/// flush against each other, which reads as if the child belonged to the
/// timeline.
///
/// Never above the first row: a gap at the very top of the panel is not a
/// separation from anything, it is a misalignment.
List<GlassRow> _spaceFolders(List<GlassRow> rows) {
  final out = <GlassRow>[];
  for (var i = 0; i < rows.length; i++) {
    final r = rows[i];
    final starts = r.tint == 'folder';
    final ends = i > 0 && r.depth < rows[i - 1].depth;
    out.add(i > 0 && (starts || ends) ? r.spaced() : r);
  }
  return out;
}

/// The work-feature rows of a document, paired with the `seq` the caller
/// interleaves them by.
///
/// M247 — the lists are parameters because an ASSEMBLY has the same three, and
/// a row that looked different depending on which document it was in would be
/// the fork this milestone is avoiding. The glyphs, the eye, the selection and
/// the menus are one implementation.
///
/// [inAssembly] changes exactly two things, and each because the command
/// behind it does not exist there: an assembly has no sketches to start on a
/// work plane, and an assembly work AXIS is re-derived after every solve, so a
/// stored flip would be undone by the next drag (see AppState.flipWorkAxis).
List<(int, GlassRow)> workFeatureRows(
  AppState app, {
  required List<WorkPlane> planes,
  required List<WorkAxis> axes,
  required List<WorkPoint> points,
  bool inAssembly = false,
  int depth = 1,
  // M361 — the panel's letters. Optional so the assembly's own call site and
  // every existing test keep working unbadged; a null counter simply means no
  // badge, which is what a row that is never retracted wants.
  BadgeCounter? badges,
}) =>
    <(int, GlassRow)>[
      for (final w in planes)
        (
          w.seq,
          GlassRow(
            id: '$kIdWorkPlane${w.seq}',
            badge: badges?.next(kBadgeWorkPlane),
            label: w.name,
            symbol: 'squareshape.dashed.squareshape',
            // M247 — red when the last re-solve could not place it: a work
            // feature whose input has gone parallel, or whose component has
            // left the document, is exactly as sick as an unmet constraint
            // and is marked the way one is.
            tint: workFeatureError(w) != null ? 'red' : 'blue',
            depth: depth,
            hasEye: true,
            eyeOn: w.visible,
            dim: !w.visible,
            selected: app.selectedWorkPlane?.seq == w.seq,
            menu: _workPlaneMenu(app, w, inAssembly: inAssembly),
          )
        ),
      for (final a in axes)
        (
          a.seq,
          GlassRow(
            id: '$kIdWorkAxis${a.seq}',
            badge: badges?.next(kBadgeWorkAxis),
            label: a.name,
            symbol: 'line.diagonal',
            tint: workFeatureError(a) != null ? 'red' : 'blue',
            depth: depth,
            hasEye: true,
            eyeOn: a.visible,
            dim: !a.visible,
            selected: app.selectedWorkAxis?.seq == a.seq,
            menu: _workAxisMenu(a, inAssembly: inAssembly),
          )
        ),
      for (final pt in points)
        (
          pt.seq,
          GlassRow(
            id: '$kIdWorkPoint${pt.seq}',
            badge: badges?.next(kBadgeWorkPoint),
            label: pt.name,
            symbol: pt.grounded ? 'pin.fill' : 'smallcircle.filled.circle',
            tint: workFeatureError(pt) != null ? 'red' : 'blue',
            depth: depth,
            hasEye: true,
            eyeOn: pt.visible,
            dim: !pt.visible,
            selected: app.selectedWorkPoint?.seq == pt.seq,
            menu: _workPointMenu(pt),
          )
        ),
    ]..sort((a, b) => a.$1.compareTo(b.$1));

/// Why [f] could not be re-derived, or null. A PART's work features are baked
/// and can never be in error, so only the assembly subclasses answer.
String? workFeatureError(Object f) => switch (f) {
      AsmWorkPlane w => w.error,
      AsmWorkAxis a => a.error,
      AsmWorkPoint p => p.error,
      _ => null,
    };

List<GlassRow> _buildRows(
  AppState app, {
  required Set<String> expanded,
  int? dragEop,
}) {
  final rows = <GlassRow>[];
  // M361 — one counter per document, so the numbers are the ones you would
  // count off the panel and a second document opened beside this one starts
  // again at 1.
  final badges = BadgeCounter();
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
    // M250 — the folder FILLS. Inventor's three sub-folders, of which View is
    // real and the other two are listed dimmed and childless; asm_reps.dart is
    // where the research and the decision are written down.
    if (expanded.contains(kIdRepresentations)) {
      rows.add(GlassRow(
        id: kIdViewReps,
        label: t.nodeViewReps,
        symbol: 'folder.fill',
        tint: 'folder',
        depth: 2,
        expandable: true,
        expanded: expanded.contains(kIdViewReps),
        menu: _viewRepsMenu(),
      ));
      if (expanded.contains(kIdViewReps)) {
        for (final name in asm.viewRepNames) {
          final rep = asm.viewRepNamed(name);
          final active = asm.activeViewRep == name;
          rows.add(GlassRow(
            id: '$kIdViewRep$name',
            label: name,
            // Inventor ticks the ACTIVE representation. A locked one that is
            // not active shows its padlock instead — one symbol per row, and
            // "which one am I looking at" is the more urgent question.
            symbol: active
                ? 'checkmark.circle.fill'
                : (rep?.locked == true ? 'lock.fill' : 'circle'),
            depth: 3,
            selected: active,
            menu: _viewRepMenu(name, rep),
          ));
        }
      }
      // Drawn and honestly empty. The alternative was to leave them out, and
      // that reads as "Inventor has three of these and this has one" only if
      // you already knew — see ribbon.dart at the Work Features panel for the
      // same rule applied to a command.
      for (final (id, label) in [
        (kIdPositionalReps, t.nodePositionalReps),
        (kIdLodReps, t.nodeLodReps),
      ]) {
        rows.add(GlassRow(
          id: id,
          label: label,
          symbol: 'folder',
          tint: 'folder',
          depth: 2,
          dim: true,
        ));
      }
    }
    rows.add(GlassRow(
      id: kIdRelationships,
      label: t.nodeRelationships,
      symbol: 'folder.fill',
      tint: 'folder',
      depth: 1,
      expandable: true,
      expanded: expanded.contains(kIdRelationships),
    ));
    // M242 — the constraints themselves, in the order they were placed.
    if (expanded.contains(kIdRelationships)) {
      for (final c in asm.constraints) {
        rows.add(_constraintRow(asm, c, depth: 2));
      }
    }
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
      // M248 — a pattern ELEMENT is listed under its pattern, not beside the
      // components. Inventor's tree, and the reason the pattern node exists
      // at all: a row per element at the top level buries the assembly.
      if (o.isPatternElement) continue;
      _componentRows(rows, asm, o, expanded, depth: 1, path: '');
    }
    for (final p in asm.patterns) {
      _patternRows(rows, asm, p, expanded, depth: 1);
    }
    // M247 — the assembly's OWN work features, below the components and in
    // creation order. Beside them rather than under one of them, because that
    // is what they are: a work plane mating two components belongs to neither,
    // and Inventor lists an assembly's work features at the component level
    // for the same reason.
    for (final (_, row) in workFeatureRows(app,
        planes: asm.workPlanes,
        axes: asm.workAxes,
        points: asm.workPoints,
        inAssembly: true,
        badges: badges)) {
      rows.add(row);
    }
    return rows;
  }

  if (part != null) {
    // ---- M250: EDIT IN PLACE ----------------------------------------------
    //
    // Inventor's browser shows the ASSEMBLY while you edit a part inside it,
    // with the edited component in bold. This tree is the part's — the part
    // tab is what is current, which is what makes every part command work
    // unchanged — so the assembly appears as one row above it that says where
    // you are and takes you back.
    //
    // It is in the browser as well as in the ribbon because the ribbon's
    // Return disappears while a SKETCH is open inside the edit (the sketch
    // ribbon replaces the part one), and a mode with no visible way out is the
    // failure this row exists to prevent.
    final inPlace = app.inPlaceEdit;
    if (inPlace != null) {
      rows.add(GlassRow(
        id: kIdInPlaceReturn,
        label: inPlace.assembly,
        symbol: 'arrow.uturn.backward',
        tint: 'blue',
        depth: 1,
      ));
    }

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
        // M345 — the three origin PLANES are a destination for a pasted
        // sketch. The axes and the centre point are not: a sketch needs a
        // plane, and offering the row on a line would be a menu entry that
        // could only ever fail.
        final isPlane = key == 'xy' || key == 'yz' || key == 'xz';
        final paste = isPlane ? pasteSketchSection(app) : const <GlassMenuItem>[];
        rows.add(GlassRow(
          id: '$kIdOrigin$key',
          label: label,
          symbol: sym,
          depth: 2,
          hasEye: true,
          eyeOn: on,
          dim: !on,
          menu: paste.isEmpty ? const [] : [paste],
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
    final work = workFeatureRows(app,
        planes: part.workPlanes,
        axes: part.workAxes,
        points: part.workPoints,
        badges: badges);
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
          badge: badges.feature(f.kind),
          symbol: f.computeError != null
              ? 'exclamationmark.triangle'
              // M255 — a DERIVED body is a link to another document, and the
              // row says so: it is the one feature in the tree whose shape is
              // decided somewhere else.
              : f is DeriveFeature
                  ? 'link'
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
          badge: badges.next(kBadgeSketch),
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
        menu: _layerMenu(app),
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
      clipSection('bdCopy', 'bdCut'),
      [
        // M255 — Inventor's Make Part, and its own section: the two above
        // change how this body LOOKS, this one creates two documents and
        // navigates away from the one you are in.
        GlassMenuItem(
            id: 'bdMakePart', title: t.ctxMakePart, symbol: 'shippingbox'),
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
List<List<GlassMenuItem>> _workPlaneMenu(AppState app, WorkPlane w,
        {bool inAssembly = false}) =>
    [
      [
        // M181 — FIRST, as in Inventor. This is the route that cannot miss:
        // "Start 2D Sketch" then a tap in the viewport has to beat a solid
        // face and the origin planes the command itself switched on, and
        // failing that race is what "I still can't sketch on a work plane"
        // has been every time. Naming the plane leaves nothing to hit.
        //
        // M247 — absent in an assembly, where there is nothing to sketch: an
        // .pas holds components and relationships, and a sketch would have to
        // belong to a part. Offering it would be a menu entry that could only
        // ever fail.
        if (!inAssembly)
          GlassMenuItem(
              id: 'wpSketch',
              title: t.ctxCreateSketch,
              symbol: 'square.on.square'),
        // M345 — and the same thing with the clipboard's sketch in it.
        if (!inAssembly) ...pasteSketchSection(app),
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
List<List<GlassMenuItem>> _workAxisMenu(WorkAxis a,
        {bool inAssembly = false}) =>
    [
      [
        GlassMenuItem(
            id: 'waVis',
            title: a.visible ? t.hide : t.ctxShow,
            symbol: a.visible ? 'eye.slash' : 'eye'),
        // The axis carries a SIGN that revolve and pattern directions inherit
        // (see WorkAxis.flip), and re-picking two points in the other order to
        // change it would be absurd.
        //
        // M247 — not offered in an assembly. There the axis is RE-DERIVED from
        // its picks after every solve, and the solver hands back the sign the
        // method chose, so a flip would survive exactly until the next drag.
        // A command that silently undoes itself is worse than one that is not
        // there.
        if (!inAssembly)
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
    // M345 — Cut only when nothing is built on it: cutting a consumed sketch
    // would take the feature with it, which is the same rule its Delete
    // follows and the reason Delete is absent from a consumed sketch too.
    [
      ...clipSection('skCopy', 'skCut', cut: !consumed),
      // M345 — "this sketch, as a document of its own". Beside Copy because
      // it is the same idea with a destination: a 2D document rather than the
      // clipboard.
      GlassMenuItem(
          id: 'skToDocument',
          title: t.ctxSketchToDocument,
          symbol: 'square.and.arrow.down.on.square'),
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

List<List<GlassMenuItem>> _layerMenu(AppState app) => [
      [
        GlassMenuItem(id: 'edit', title: t.ctxEditLayer, symbol: 'pencil'),
        GlassMenuItem(id: 'rename', title: t.rename, symbol: 'character.cursor.ibeam'),
        GlassMenuItem(id: 'move', title: t.ctxMoveSelectionHere, symbol: 'arrow.right.doc.on.clipboard'),
      ],
      // M345 — Copy takes the whole layer; Paste puts the clipboard ON this
      // layer, whichever layer is being edited. That is what makes a layer row
      // a destination as well as a thing.
      [
        GlassMenuItem(id: 'lyCopy', title: t.btnCopy, symbol: 'doc.on.doc'),
        if (app.clipboard is SketchClip)
          GlassMenuItem(
              id: 'lyPaste', title: t.btnPaste, symbol: 'doc.on.clipboard'),
      ],
      [
        GlassMenuItem(
            id: 'delete', title: t.delete, symbol: 'trash', destructive: true),
      ],
    ];
