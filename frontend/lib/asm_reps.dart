// M250 — the assembly's REPRESENTATIONS, and specifically its VIEW
// representations.
//
// The Representations folder has been an empty browser container since M240:
// listed because it is what tells you an assembly document is open, and empty
// because nothing filled it. This file fills it, with the one of Inventor's
// three that this document can actually hold.
//
// ---------------------------------------------------------------------------
// What Inventor actually has (researched 2026-08; help.autodesk.com and
// knowledge.autodesk.com are blocked from this network, so this is assembled
// from search summaries of those pages plus Autodesk's own class handout
// IM196136 and two reseller write-ups. Anything INFERRED is marked.)
// ---------------------------------------------------------------------------
//
// Representations holds three folders:
//
//   View                a saved DISPLAY configuration: which components are
//                       visible, the camera, component colours, and whether a
//                       component is enabled. Recalled by name. The default
//                       one is called "Default" in current releases (it was
//                       "Master"), and it is UNLOCKED — you can Lock a rep to
//                       stop your working view from being written into it.
//                       The active one carries a check mark in the browser,
//                       and a new one is made by right-clicking the View node.
//                       Private view reps (an external .idv file) are gone.
//
//   Position            component POSITIONS and per-component overrides:
//                       flexible subassembly positions, constraint value
//                       overrides, suppression, all editable as a table.
//
//   Level of Detail     which components are SUPPRESSED, to keep a large
//                       assembly out of memory. Suppressed here means "not
//                       loaded", not "not drawn".
//
// ---------------------------------------------------------------------------
// Honest scope note — why this file is View representations and nothing else
// ---------------------------------------------------------------------------
//
// POSITIONAL representations are not built, and the reason is not effort. A
// positional rep overrides a constraint's VALUE and a subassembly's FLEXIBLE
// flag per representation; this document has no flexible subassemblies (M246
// made a subassembly one rigid body on purpose, which is Inventor's own rule
// for the non-flexible case) and no per-representation override layer at all.
// Building the folder without those two would be a table with one column that
// could not change anything — which is exactly the empty container this
// milestone exists to remove.
//
// LEVEL OF DETAIL is not built, and there it IS the design that makes it
// pointless rather than a missing part. Inventor's LOD saves memory by not
// loading a component's file. M245 made a component BORROW the one model per
// document — placing a bracket four times costs four transforms and one mesh,
// and the model is very often the one already open in the part's own tab — so
// there is no per-occurrence memory for an LOD to reclaim. An LOD here would
// suppress drawing, which is what the visibility eye already does, and what a
// VIEW representation already saves.
//
// Both are still LISTED in the browser, dimmed and childless, for the reason
// ribbon.dart states at its Work Features panel: a command that is drawn and
// honestly disabled tells the truth, and one that is silently absent tells the
// user their memory of the product is wrong. See buildRepresentationRows.
import 'part_model.dart' show PartCamera;

/// Inventor's name for the representation an assembly has before anyone makes
/// one, and the one that cannot be renamed or deleted.
///
/// A literal rather than a localised string, and deliberately: this is the
/// NAME OF A THING IN THE DOCUMENT, in the same class as "Extrusion1" and
/// "RectangularPattern1". Translating it would rename the user's saved
/// representation when they switched language, and the .pas file would then
/// name a rep that no longer exists.
const String kDefaultViewRep = 'Default';

/// One VIEW representation: a saved display configuration, by name.
///
/// What it holds is exactly what this document can express as "display", and
/// no more:
///
///   * which components are VISIBLE — the browser's eye, per occurrence id
///   * the CAMERA — where you were looking from
///   * the ORIGIN scaffolding's visibility — the same seven keys a part has
///
/// Inventor's also carries per-component colour overrides and the
/// enabled/disabled flag. Neither exists in this document: a component is
/// drawn in the one steel material (see reality_assembly.assemblyTint, where
/// the only per-component colour is the SELECTION), and "disabled" is a
/// picking state with no model behind it here. They are absent rather than
/// stubbed.
class AsmViewRep {
  AsmViewRep({
    required this.name,
    Map<String, bool>? hidden,
    Map<String, bool>? origin,
    this.az = 0,
    this.pol = 0,
    this.halfH = 27,
    this.ox = 0,
    this.oy = 0,
    this.roll = 0,
    this.locked = false,
  })  : hidden = hidden ?? {},
        origin = origin ?? {};

  String name;

  /// The occurrences this representation HIDES, by id.
  ///
  /// The hidden ones rather than all of them, which matters the moment a
  /// component is placed AFTER the representation was saved: an absent id
  /// reads as visible, so activating an old representation shows the new
  /// component instead of making it vanish for a reason nothing in the
  /// browser could explain. Inventor behaves the same way — a view rep
  /// records overrides, not a census.
  final Map<String, bool> hidden;

  /// Origin plane / axis / centre-point visibility, same seven keys as
  /// [AssemblyModel.vis]. Absent keys keep whatever the document has.
  final Map<String, bool> origin;

  double az, pol, halfH, ox, oy, roll;

  /// M250 — Inventor's Lock, and the reason it exists.
  ///
  /// LEAVING an unlocked representation writes the current display state back
  /// into it, which is what makes "Default" useful: work in Default, activate
  /// a saved rep to check something, come back, and your working view is
  /// where you left it. It is also what would quietly destroy a rep you had
  /// carefully set up and then merely LOOKED at from another one — so Inventor
  /// gives you a padlock, and so does this. A locked rep is applied and never
  /// written.
  bool locked;

  bool get isDefault => name == kDefaultViewRep;

  /// Reads the display state of an assembly into this representation.
  ///
  /// Takes the occurrence ids rather than the model, so this file stays free
  /// of assembly.dart: a representation is a bag of names and numbers, and
  /// keeping it that way is what lets it be tested without a kernel.
  void capture({
    required Iterable<(String, bool)> occurrences,
    required Map<String, bool> originVis,
    required PartCamera camera,
  }) {
    hidden.clear();
    for (final (id, visible) in occurrences) {
      if (!visible) hidden[id] = true;
    }
    origin
      ..clear()
      ..addAll(originVis);
    az = camera.az;
    pol = camera.pol;
    halfH = camera.halfH;
    ox = camera.ox;
    oy = camera.oy;
    roll = camera.roll;
  }

  /// True when [id] should be visible under this representation.
  bool visible(String id) => hidden[id] != true;

  /// Writes this representation's camera onto [camera].
  ///
  /// halfH goes through [PartCamera.clampHalfH] for the reason
  /// AssemblyModel.loadJson does it: a representation read from a hand-edited
  /// file can carry a zero or a negative, and a camera with no height renders
  /// nothing at all.
  void applyCamera(PartCamera camera) {
    camera.az = az;
    camera.pol = pol;
    camera.halfH = PartCamera.clampHalfH(halfH);
    camera.ox = ox;
    camera.oy = oy;
    camera.roll = roll;
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        if (hidden.isNotEmpty) 'hidden': hidden.keys.toList(),
        if (origin.isNotEmpty) 'origin': origin,
        'az': az,
        'pol': pol,
        'halfH': halfH,
        'ox': ox,
        'oy': oy,
        'roll': roll,
        if (locked) 'locked': true,
      };

  static AsmViewRep? fromJson(Map j) {
    final name = (j['name'] as String?)?.trim();
    if (name == null || name.isEmpty) return null;
    double n(String k, double dflt) => (j[k] as num?)?.toDouble() ?? dflt;
    return AsmViewRep(
      name: name,
      hidden: {
        for (final id in (j['hidden'] as List? ?? const []))
          if (id is String) id: true
      },
      origin: {
        for (final e in ((j['origin'] as Map?) ?? const {}).entries)
          if (e.key is String && e.value is bool) e.key as String: e.value as bool
      },
      az: n('az', 0),
      pol: n('pol', 0),
      halfH: n('halfH', 27),
      ox: n('ox', 0),
      oy: n('oy', 0),
      roll: n('roll', 0),
      locked: j['locked'] == true,
    );
  }
}

/// A fresh representation name, counting the way every other named thing in
/// this app does: "View1", then "View2".
///
/// [taken] is every name already in use, [kDefaultViewRep] included — a
/// document whose first rep was renamed to "View1" must not be handed "View1"
/// again by the next New.
String nextViewRepName(Iterable<String> taken) {
  final have = taken.toSet();
  var n = 1;
  while (have.contains('View$n')) {
    n++;
  }
  return 'View$n';
}
