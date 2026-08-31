// M291 — SECTION VIEWS: half, quarter and three-quarter.
//
// Inventor puts these on the View tab's Appearance panel, and so does this
// app — the panel is already there, holding Material, Display Mode and the
// rendered floor toggle. They belong with those and not with Extrude: a
// section view does not change a face, it changes what you can see of one.
//
// ---------------------------------------------------------------------------
// WHAT INVENTOR ACTUALLY DOES, because the names are the wrong way round
// ---------------------------------------------------------------------------
//
// The name says what SURVIVES, not what is cut away, and only "half" reads the
// way you would guess:
//
//   Half Section View          one plane;   the near half is removed.
//   Quarter Section View       two planes;  three quarters are removed and a
//                              QUARTER of the model is left standing.
//   Three Quarter Section View two planes;  one quarter is removed — the
//                              corner notch — and THREE QUARTERS are left.
//
// So the two-plane commands are complements of each other, which is exactly
// what Autodesk's own help means by "quarter and three-quarter views can show
// the opposite view". Written as half-spaces, with A- meaning "the near side
// of plane A", the removed set is:
//
//   half           A-
//   quarter        A- union B-           (cut twice)
//   threeQuarter   A- intersect B-       (cut once, with the common solid)
//
// The rest of the workflow is Inventor's too: pick any plane or planar face,
// Flip to swap which side goes, drag or type an offset to slide the plane
// along its own normal, Continue for the second plane, and End Section View to
// get the whole model back. Both two-plane commands accept ANY two planes, not
// only perpendicular ones.
//
// ---------------------------------------------------------------------------
// AND SLICE GRAPHICS IS ONE OF THESE
// ---------------------------------------------------------------------------
//
// M168 built Slice Graphics — F7 inside a sketch, cutting away everything
// between you and the sketch plane — as its own state with its own cache and
// its own cut. It is a half section view whose plane is the open sketch's, and
// this milestone makes that literal rather than parallel: [SectionView.slice]
// builds exactly that value, and one cut path serves both. The sketch keeps
// its own toggle and its own F7, because that is the command a sketch has; it
// simply no longer has a second implementation behind it.
//
// This file is deliberately free of the kernel, of AppState and of widgets: it
// decides WHAT is cut. part_model.dart's sectionCutSolid does the cutting and
// app_state.dart owns the live state and the picking session.
import 'part_model.dart' show PlaneFrame, offsetPlaneFrame;

/// Which of Inventor's three section commands is running.
enum SectionMode {
  /// One plane, the near half removed.
  half,

  /// Two planes, a quarter of the model left standing.
  quarter,

  /// Two planes, a quarter of the model removed.
  threeQuarter;

  /// The id used in logs and in the ribbon's row keys. Stable across renames.
  String get id => name;

  /// How many planes the command needs before it can cut anything.
  int get planeCount => this == SectionMode.half ? 1 : 2;

  static SectionMode? byId(Object? v) {
    for (final m in SectionMode.values) {
      if (m.id == v) return m;
    }
    return null;
  }
}

/// One cutting plane of a section view: where it is, which way round it cuts,
/// and how far it has been slid along its own normal.
class SectionPlane {
  /// The plane as it was picked — an origin plane, a work plane or a planar
  /// face. Never moved; [offset] and [flipped] are applied on top, so the
  /// user can slide a plane to nothing and back without losing the pick.
  final PlaneFrame base;

  /// What the pick was, for the browser row and the log: 'XY', 'Work Plane1',
  /// 'face'. Not shown to the user as-is — the ARB names the origin planes.
  final String label;

  /// Which side goes. False removes the side the frame's normal points AWAY
  /// from (see [cutFrame]); Flip swaps it.
  final bool flipped;

  /// Millimetres along the base normal. Inventor's drag and its offset field
  /// are the same number.
  final double offset;

  const SectionPlane(this.base, this.label,
      {this.flipped = false, this.offset = 0});

  SectionPlane copyWith({bool? flipped, double? offset}) => SectionPlane(
        base,
        label,
        flipped: flipped ?? this.flipped,
        offset: offset ?? this.offset,
      );

  SectionPlane get flip => copyWith(flipped: !flipped);

  /// The plane the cut is actually taken at.
  ///
  /// The offset is applied along the ORIGINAL normal and the flip afterwards,
  /// so "slide it 5 mm that way" keeps meaning the same direction however many
  /// times the section has been flipped since.
  ///
  /// Flipping swaps u and v as well as negating n. That is not tidiness: the
  /// cut tool is an extrusion placed by [PlaneFrame.mat34], and a frame with a
  /// negated normal but the same u and v is left-handed — the box would be
  /// built mirrored, and on a non-square profile that is a different solid.
  PlaneFrame get cutFrame {
    final moved = offset == 0 ? base : offsetPlaneFrame(base, offset);
    if (!flipped) return moved;
    return PlaneFrame(moved.key, moved.v, moved.u, moved.n * -1, moved.origin);
  }

  /// Everything about this plane that changes the resulting cut. Part of the
  /// cache key; see [SectionView.signature].
  String get signature {
    final f = cutFrame;
    return '${f.origin.x},${f.origin.y},${f.origin.z},'
        '${f.n.x},${f.n.y},${f.n.z}';
  }
}

/// A live section view: the command, and the one or two planes it cuts with.
class SectionView {
  final SectionMode mode;
  final SectionPlane a;

  /// Null until the second plane is picked. A quarter or three-quarter view
  /// with only one plane cuts NOTHING rather than half — the command is not
  /// finished, and guessing halfway would show a shape the user never asked
  /// for and then change it under them when they picked the second plane.
  final SectionPlane? b;

  const SectionView(this.mode, this.a, [this.b]);

  /// M168's Slice Graphics, as the section view it always was: a half section
  /// at the open sketch's plane, cutting away what is between the viewer and
  /// it.
  ///
  /// The sketch frame's normal points at the viewer when you are looking at
  /// the sketch, and [SectionPlane] removes the side the normal points away
  /// from — so this is `flipped`, and that one word is the whole of what M168
  /// expressed by extruding its box backwards.
  factory SectionView.slice(PlaneFrame sketchPlane) => SectionView(
      SectionMode.half, SectionPlane(sketchPlane, 'sketch', flipped: true));

  /// True once every plane the command needs has been picked.
  bool get complete => mode.planeCount == 1 || b != null;

  /// The planes actually in use, in pick order.
  List<SectionPlane> get planes => b == null ? [a] : [a, b!];

  SectionView withPlane(int i, SectionPlane p) =>
      i == 0 ? SectionView(mode, p, b) : SectionView(mode, a, p);

  SectionView withSecond(SectionPlane p) => SectionView(mode, a, p);

  /// Everything that changes the resulting geometry, for the cut cache.
  ///
  /// The MODE is in it: the same two planes cut a quarter view and a
  /// three-quarter view into complementary shapes, and a cache that keyed only
  /// on the planes would hand one the other's solid.
  String get signature {
    final sb = StringBuffer(mode.id);
    for (final p in planes) {
      sb
        ..write(';')
        ..write(p.signature);
    }
    return sb.toString();
  }
}
