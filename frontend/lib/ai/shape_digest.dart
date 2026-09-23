/// What a body IS, measured from its geometry.
///
/// The assistant's document context is the AUTHORING RECORD — the feature
/// tree. For an imported STEP body that record is a placeholder, and the model
/// read the placeholder's unused default distance and reported it as a
/// diameter. Nothing about that was a prompt problem: the context contained no
/// geometry, one misleading number, and an instruction to be useful.
///
/// This file computes the other thing: a bounded, deterministic description of
/// the SHAPE, from the tessellation and the kernel's own per-face and per-edge
/// analytic records. Everything here is measured. Nothing is estimated from a
/// picture, and nothing is invented to fill a sentence.
///
/// THREE PROPERTIES IT HAS TO KEEP.
///
///   1. **Bounded.** A 900-face part and a 40-face part produce a digest of
///      the same length. Faces are GROUPED, never enumerated, and every
///      truncation states what it omitted.
///   2. **Honest.** B-Rep quantities and mesh-derived ones are never mixed in
///      one number, and the digest reports how much of the shape it could
///      describe analytically — [ShapeDigest.analyticCoverage] — so a model
///      reading it knows when to ask for a section or a view instead of
///      guessing at a blob.
///   3. **Deterministic.** The same geometry produces the same digest, byte
///      for byte. That is what makes caching sound and an evaluation suite
///      possible.
library;

import 'dart:math' as math;

import '../ffi/occt_engine.dart';
import '../part_model.dart';
import '../part_render.dart'
    show kFacePlane, kFaceCylinder, kFaceCone, kFaceSphere, kFaceTorus;

/// Surface-type names, as the digest prints them.
String faceTypeName(int t) => switch (t) {
      kFacePlane => 'plane',
      kFaceCylinder => 'cylinder',
      kFaceCone => 'cone',
      kFaceSphere => 'sphere',
      kFaceTorus => 'torus',
      _ => 'other',
    };

/// True for the surface types the kernel describes analytically. Anything else
/// is a B-spline or a trimmed surface the digest can only measure, not name.
bool isAnalyticType(int t) => t >= kFacePlane && t <= kFaceTorus;

/// One face, as read from the mesh's 15-double records plus the triangles.
class DigestFace {
  DigestFace({
    required this.id,
    required this.topoId,
    required this.type,
    required this.at,
    required this.dir,
    required this.radius,
    required this.area,
    required this.centroid,
    required this.concave,
    required this.tangent,
  });

  /// Index into the mesh's face list. Not stable across a rebuild — the
  /// FINGERPRINT (type/at/dir/radius/area) is what survives, and is what
  /// `faces_where` hands out for later ops to resolve against.
  final int id;

  /// 1-based topological index, or -1 when the shim did not supply one. Delete
  /// Face and Direct Edit address this one.
  final int topoId;

  final int type;
  final Vec3 at; // a point on the surface (plane origin, axis location)
  final Vec3 dir; // plane normal, or the axis of a cylinder/cone/torus
  final double radius;
  final double area; // mesh-derived
  final Vec3 centroid; // area-weighted, mesh-derived

  /// For a curved face: whether the surface normal points TOWARD its own axis.
  /// Concave means material is outside — a hole or an internal fillet. Convex
  /// means material is inside — a shaft, a boss or an external round.
  final bool concave;

  /// True when no display edge bounds this face. The shim filters
  /// tangent-continuous edges out of the display list, so a face with none is
  /// one that meets its neighbours smoothly — which is what a blend is.
  final bool tangent;

  double get diameter => radius * 2;

  /// The stable reference a later operation resolves. Deliberately geometric:
  /// OCCT re-indexes on every rebuild, so an id quoted back next turn would
  /// name a different face.
  Map<String, dynamic> get fingerprint => {
        'type': faceTypeName(type),
        'at': [_r(at.x), _r(at.y), _r(at.z)],
        'dir': [_r(dir.x), _r(dir.y), _r(dir.z)],
        if (radius > 0) 'radius': _r(radius),
        'area': _r(area),
      };
}

/// Holes of one diameter sharing an axis direction.
class HoleGroup {
  HoleGroup(this.diameter, this.axis, this.through, this.depth, this.centres);
  final double diameter;
  final Vec3 axis;

  /// Null when it could not be established — no kernel to cast a ray with.
  /// Never guessed: "unknown" is a fact and "through" is a claim.
  final bool? through;
  final double? depth;
  final List<Vec3> centres;
  int get count => centres.length;
}

/// Blends of one radius. Convex is Inventor's "round", concave its "fillet".
class BlendGroup {
  BlendGroup(this.radius, this.convex, this.count);
  final double radius;
  final bool convex;
  final int count;
}

/// One cross-section outline.
class SectionProfile {
  SectionProfile(this.at, this.loops, this.width, this.height, this.area);
  final double at;
  final int loops;
  final double width, height, area;
}

/// The digest itself.
class ShapeDigest {
  ShapeDigest({
    required this.body,
    required this.faces,
    required this.valid,
    required this.volume,
    required this.surfaceArea,
    required this.min,
    required this.max,
    required this.typeCounts,
    required this.analyticCoverage,
    required this.holes,
    required this.blends,
    required this.mirrors,
    required this.minWall,
    required this.minWallBetween,
    required this.notable,
    required this.sections,
    required this.sectionAxis,
    required this.frontAreas,
    required this.edgeCount,
    required this.sharpEdgeCount,
    required this.classifiedArea,
    required this.exact,
  });

  final String body;
  final List<DigestFace> faces;
  final bool valid;
  final double volume;
  final double surfaceArea;
  final Vec3 min, max;
  final Map<int, int> typeCounts;
  final double analyticCoverage;
  final List<HoleGroup> holes;
  final List<BlendGroup> blends;
  final List<String> mirrors;
  final double? minWall;
  final String? minWallBetween;
  final List<DigestFace> notable;
  final List<SectionProfile> sections;
  final String sectionAxis;
  final List<double> frontAreas; // projected area along X, Y, Z
  final int edgeCount, sharpEdgeCount;

  /// Face area the recogniser could name. The rest is reported as unclassified
  /// rather than passed over, because a recogniser that quietly ignores what
  /// it cannot name teaches the model that nothing is there.
  final double classifiedArea;

  /// True when a B-Rep was available. False means the numbers came from the
  /// tessellation alone (a test fake, or a build with no kernel linked), and
  /// the digest says so rather than presenting them as exact.
  final bool exact;

  Vec3 get size => Vec3(max.x - min.x, max.y - min.y, max.z - min.z);

  /// The middle of the bounding box, in world millimetres. What a model needs
  /// when it wants to put something "in the centre" of a body that was not
  /// drawn around the origin (issue #82).
  Vec3 get centre => Vec3(
      (min.x + max.x) / 2, (min.y + max.y) / 2, (min.z + max.z) / 2);

  double get bboxVolume => size.x * size.y * size.z;
  double get fill => bboxVolume <= 0 ? 0 : volume / bboxVolume;

  /// True when the analytic description is too thin to answer shape questions
  /// from — the routing signal that tells the model to ask for sections or a
  /// view instead of describing a blob it cannot see.
  bool get isFreeForm => analyticCoverage < 0.40;

  /// The whole digest as the model reads it. Target: under 400 tokens for any
  /// part, which the grouping rules above make a structural property rather
  /// than a truncation.
  String toText() {
    final b = StringBuffer();
    final s = size;
    b.writeln('SHAPE $body — ${valid ? "valid" : "INVALID (self-intersecting "
        "or open)"}${exact ? "" : ", mesh-only (no kernel linked)"}');
    b.writeln('bbox ${_mm(s.x)} × ${_mm(s.y)} × ${_mm(s.z)} mm · '
        'vol ${_mm(volume)} mm³ · area ~${_mm(surfaceArea)} mm² · '
        'fill ${(fill * 100).round()}%');
    // ISSUE #72 — "das Modell ist falsch rotiert". A plate lying flat and the
    // same plate standing on its edge have identical bbox numbers in
    // different slots, and every mainstream CAD is Z-up while this app is
    // Y-up. Spelling out which number is the HEIGHT is what makes the
    // difference readable instead of inferable.
    b.writeln('stance up is +Y — ${_mm(s.y)} mm tall, footprint '
        '${_mm(s.x)} (X) × ${_mm(s.z)} (Z) mm');
    // ISSUE #82 — "the countersunk hole was not centered, it was on an edge",
    // and in the same session a cable clamp that missed the part altogether.
    //
    // Both came from ONE missing fact. The line above gives the SIZE of the
    // footprint and used to give the Y range alone, so where the body sits in
    // X and Z was never stated — and all three origin planes pass through the
    // world origin. A model that draws a plate with sketch_rounded_rect at
    // (0, 11) has put its centre at world z = -11, then places the next
    // feature at sketch (0, 0) because (0, 0) is "the middle" of every sketch
    // it has drawn. The hole landed 11 mm out, exactly half the depth, on the
    // boundary. The clamp landed half in open air.
    //
    // A size cannot answer "where is the middle"; a position can. So the
    // digest states the extent and the centre in world millimetres, and says
    // plainly that the origin is not the centre, because that is the
    // assumption that was actually being made.
    b.writeln('extent x ${_mm(min.x)}..${_mm(max.x)} · '
        'y ${_mm(min.y)}..${_mm(max.y)} · '
        'z ${_mm(min.z)}..${_mm(max.z)}');
    final c = centre;
    final atOrigin = c.x.abs() < 5e-3 && c.z.abs() < 5e-3;
    b.writeln('centre (${_mm(c.x)}, ${_mm(c.y)}, ${_mm(c.z)}) — '
        '${atOrigin ? "this body IS centred on the origin in X and Z" : "the "
            "WORLD ORIGIN IS NOT THE CENTRE of this body. Anything that must "
            "sit in the middle goes at x=${_mm(c.x)}, z=${_mm(c.z)}, not at "
            "0,0"}');
    if (faces.isNotEmpty) {
      final parts = typeCounts.entries.toList()
        ..sort((x, y) => y.value.compareTo(x.value));
      b.writeln('faces ${faces.length} — '
          '${parts.map((e) => "${e.value} ${faceTypeName(e.key)}").join(", ")}'
          ' · analytic ${(analyticCoverage * 100).round()}% of area');
    }
    if (edgeCount > 0) {
      b.writeln('edges $edgeCount, of which $sharpEdgeCount sharp');
    }
    if (mirrors.isNotEmpty) {
      b.writeln('symmetry mirror about ${mirrors.join(" and ")} (±0.01)');
    }
    for (final h in holes) {
      final deep = h.depth == null ? '' : ', ${_mm(h.depth!)} mm long';
      final where = h.through == null
          ? 'open/blind unknown (no kernel linked)'
          : h.through!
              ? 'THROUGH — open at both ends, nothing closes it'
              : 'blind — it has a floor';
      b.writeln('holes ${h.count}× Ø${_mm(h.diameter)} $where$deep, '
          'axis ${_axis(h.axis)}');
    }
    if (blends.isNotEmpty) {
      b.writeln('blends ${blends.map((x) => "${x.count}× R${_mm(x.radius)} "
          "${x.convex ? "round" : "fillet"}").join(" · ")}');
    }
    if (minWall != null) {
      b.writeln('walls min ${_mm(minWall!)} mm${minWallBetween == null ? "" :
          " $minWallBetween"}');
    }
    if (notable.isNotEmpty) {
      b.writeln('notable ${notable.map((f) => "F${f.id} ${faceTypeName(f.type)}"
          "${f.radius > 0 ? " Ø${_mm(f.diameter)}" : ""} "
          "${_axis(f.dir)} ${_mm(f.area)} mm²").join(" · ")}');
    }
    if (sections.isNotEmpty) {
      b.writeln('sections along $sectionAxis (mesh, ±0.1 mm)');
      for (final p in sections) {
        b.writeln('  $sectionAxis=${_mm(p.at)}  ${p.loops} loop'
            '${p.loops == 1 ? "" : "s"}, ${_mm(p.width)} × ${_mm(p.height)}, '
            'area ${_mm(p.area)} mm²');
      }
    }
    if (frontAreas.length == 3) {
      b.writeln('projected front area X ${_mm(frontAreas[0])} · '
          'Y ${_mm(frontAreas[1])} · Z ${_mm(frontAreas[2])} mm²');
    }
    final unclassified = surfaceArea <= 0
        ? 0
        : ((1 - classifiedArea / surfaceArea) * 100).round();
    b.writeln('recognised ${100 - unclassified}% of face area'
        '${unclassified > 0 ? "; $unclassified% unclassified" : ""}');
    b.write(isFreeForm
        ? 'FREE-FORM: the analytic description is thin here. Ask for a section '
            'or a view before describing the shape.'
        : 'Measured from the ${exact ? "B-Rep" : "tessellation"}; areas and '
            'sections are mesh-derived (±1%). No mass, strength, clearance or '
            'manufacturing check is implied.');
    return b.toString();
  }

  Map<String, dynamic> toJson() => {
        'body': body,
        'valid': valid,
        'exact': exact,
        'boundingBoxMm': {
          'min': [_r(min.x), _r(min.y), _r(min.z)],
          'max': [_r(max.x), _r(max.y), _r(max.z)],
          'size': [_r(size.x), _r(size.y), _r(size.z)],
        },
        'volumeMm3': _r(volume),
        'surfaceAreaMm2': _r(surfaceArea),
        'fill': _r(fill),
        'faceCount': faces.length,
        'analyticCoverage': _r(analyticCoverage),
        'freeForm': isFreeForm,
        'text': toText(),
      };
}

double _r(double v) =>
    v.isFinite ? (v * 10000).roundToDouble() / 10000 : 0;

/// Two decimals is a hundredth of a millimetre — finer than anything this
/// geometry is accurate to, and short enough to keep a digest readable.
String _mm(double v) {
  if (!v.isFinite) return '?';
  final a = v.abs();
  if (a >= 100000) return v.toStringAsExponential(2);
  return v.toStringAsFixed(a >= 100 ? 1 : 2);
}

/// A direction as an axis name when it is one, else as components. Naming the
/// common case is most of what makes the digest readable.
String _axis(Vec3 d) {
  const eps = 1e-3;
  if ((d.x.abs() - 1).abs() < eps && d.y.abs() < eps && d.z.abs() < eps) {
    return d.x > 0 ? '+X' : '−X';
  }
  if ((d.y.abs() - 1).abs() < eps && d.x.abs() < eps && d.z.abs() < eps) {
    return d.y > 0 ? '+Y' : '−Y';
  }
  if ((d.z.abs() - 1).abs() < eps && d.x.abs() < eps && d.y.abs() < eps) {
    return d.z > 0 ? '+Z' : '−Z';
  }
  return '(${_mm(d.x)},${_mm(d.y)},${_mm(d.z)})';
}

/// How many cross-sections a free-form digest reports.
const int kSectionStations = 5;

/// Computes the digest of [solid].
///
/// [edges] is the kernel's topological edge list when one is available; pass
/// an empty list on a build with no kernel and the digest simply omits the
/// edge lines rather than inventing them.
ShapeDigest computeShapeDigest(KernelSolid solid,
    {String body = 'Solid1', List<OcctEdgeInfo> edges = const []}) {
  final m = solid.mesh;
  final shape = solid.shape;

  // ---- globals ---------------------------------------------------------
  var min = const Vec3(0, 0, 0), max = const Vec3(0, 0, 0);
  final bb = shape?.bbox();
  if (bb != null && bb.length == 6) {
    min = Vec3(bb[0], bb[1], bb[2]);
    max = Vec3(bb[3], bb[4], bb[5]);
  } else if (m.positions.length >= 3) {
    var x0 = m.positions[0], y0 = m.positions[1], z0 = m.positions[2];
    var x1 = x0, y1 = y0, z1 = z0;
    for (var i = 3; i + 2 < m.positions.length; i += 3) {
      final x = m.positions[i], y = m.positions[i + 1], z = m.positions[i + 2];
      if (x < x0) x0 = x;
      if (y < y0) y0 = y;
      if (z < z0) z0 = z;
      if (x > x1) x1 = x;
      if (y > y1) y1 = y;
      if (z > z1) z1 = z;
    }
    min = Vec3(x0, y0, z0);
    max = Vec3(x1, y1, z1);
  }

  // ---- per-face aggregation -------------------------------------------
  final faces = <DigestFace>[];
  final areaOf = <int, double>{};
  final centroidOf = <int, Vec3>{};
  final normalOf = <int, Vec3>{}; // one representative mesh normal per face
  final pointOf = <int, Vec3>{}; // one representative vertex per face

  for (var t = 0; t + 2 < m.indices.length; t += 3) {
    final f = (t ~/ 3) < m.triFaces.length ? m.triFaces[t ~/ 3] : -1;
    if (f < 0) continue;
    final i0 = m.indices[t] * 3, i1 = m.indices[t + 1] * 3,
        i2 = m.indices[t + 2] * 3;
    if (i2 + 2 >= m.positions.length) continue;
    final a = Vec3(m.positions[i0], m.positions[i0 + 1], m.positions[i0 + 2]);
    final b = Vec3(m.positions[i1], m.positions[i1 + 1], m.positions[i1 + 2]);
    final c = Vec3(m.positions[i2], m.positions[i2 + 1], m.positions[i2 + 2]);
    final cross = (b - a).cross(c - a);
    final area = cross.length * 0.5;
    if (!area.isFinite || area <= 0) continue;
    areaOf[f] = (areaOf[f] ?? 0) + area;
    final mid = Vec3((a.x + b.x + c.x) / 3, (a.y + b.y + c.y) / 3,
        (a.z + b.z + c.z) / 3);
    centroidOf[f] = (centroidOf[f] ?? const Vec3(0, 0, 0)) + mid * area;
    if (!normalOf.containsKey(f)) {
      if (i0 + 2 < m.normals.length) {
        normalOf[f] =
            Vec3(m.normals[i0], m.normals[i0 + 1], m.normals[i0 + 2]);
      } else {
        normalOf[f] = cross.length > 0 ? cross * (1 / cross.length) : cross;
      }
      pointOf[f] = a;
    }
  }

  // Display edges bounding each face — the shim filters tangent-continuous
  // edges out of that list, so a face with none meets its neighbours smoothly.
  final boundedBy = <int, int>{};
  for (var e = 0; e < m.edgeCount; e++) {
    for (final f in m.facesOfEdge(e)) {
      boundedBy[f] = (boundedBy[f] ?? 0) + 1;
    }
  }
  final haveAdjacency = m.edgeFaces.isNotEmpty;

  var surfaceArea = 0.0;
  for (var f = 0; f < m.faceCount; f++) {
    final rec = 15 * f;
    if (rec + 15 > m.faceInfos.length) continue;
    final type = m.faceInfos[rec].round();
    final at = Vec3(m.faceInfos[rec + 1], m.faceInfos[rec + 2],
        m.faceInfos[rec + 3]);
    final dir = Vec3(m.faceInfos[rec + 4], m.faceInfos[rec + 5],
        m.faceInfos[rec + 6]);
    final radius = m.faceInfos[rec + 10];
    final area = areaOf[f] ?? 0;
    surfaceArea += area;
    final centroid = area > 0 && centroidOf[f] != null
        ? centroidOf[f]! * (1 / area)
        : at;

    // Concavity: does the surface normal point toward the axis? Only
    // meaningful for a curved face with an axis.
    var concave = false;
    if (type != kFacePlane && radius > 0) {
      final p = pointOf[f], n = normalOf[f];
      if (p != null && n != null) {
        final along = dir.length > 0 ? dir * (1 / dir.length) : dir;
        final rel = p - at;
        final radial = rel - along * rel.dot(along);
        if (radial.length > 1e-9) {
          concave = radial.dot(n) < 0;
        }
      }
    }
    faces.add(DigestFace(
      id: f,
      topoId: m.topoFaceId(f),
      type: type,
      at: at,
      dir: dir.length > 0 ? dir * (1 / dir.length) : dir,
      radius: radius,
      area: area,
      centroid: centroid,
      concave: concave,
      tangent: haveAdjacency && (boundedBy[f] ?? 0) == 0,
    ));
  }

  final typeCounts = <int, int>{};
  var analyticArea = 0.0;
  for (final f in faces) {
    typeCounts[f.type] = (typeCounts[f.type] ?? 0) + 1;
    if (isAnalyticType(f.type)) analyticArea += f.area;
  }
  final coverage = surfaceArea > 0 ? analyticArea / surfaceArea : 0.0;

  // ---- recognition -----------------------------------------------------
  var classified = 0.0;
  final diagonal = (max - min).length;
  final holes = _holes(faces, shape, m, diagonal, (a) => classified += a);
  final blends = _blends(faces, (a) => classified += a);
  for (final f in faces) {
    if (f.type == kFacePlane) classified += f.area;
  }

  final minWallResult = _minWall(faces, shape);
  final mirrors = _mirrors(faces, min, max);

  final planes = [for (final f in faces) if (f.type == kFacePlane) f]
    ..sort((a, b) => b.area.compareTo(a.area));
  final notable = planes.take(3).toList();

  // ---- free-form descriptors ------------------------------------------
  final size = Vec3(max.x - min.x, max.y - min.y, max.z - min.z);
  final longest = size.x >= size.y && size.x >= size.z
      ? 0
      : size.y >= size.z
          ? 1
          : 2;
  final sections = coverage < 0.80
      ? sectionProfiles(m, longest, min, max)
      : const <SectionProfile>[];

  return ShapeDigest(
    body: body,
    faces: faces,
    valid: shape?.valid ?? true,
    volume: solid.volume.isFinite && solid.volume > 0 ? solid.volume : 0,
    surfaceArea: surfaceArea,
    min: min,
    max: max,
    typeCounts: typeCounts,
    analyticCoverage: coverage,
    holes: holes,
    blends: blends,
    mirrors: mirrors,
    minWall: minWallResult?.$1,
    minWallBetween: minWallResult?.$2,
    notable: notable,
    sections: sections,
    sectionAxis: const ['X', 'Y', 'Z'][longest],
    frontAreas: frontAreas(m),
    edgeCount: edges.length,
    sharpEdgeCount:
        edges.where((e) => e.dihedralDeg.abs() > 15).length,
    classifiedArea: math.min(classified, surfaceArea),
    exact: shape != null,
  );
}

/// Material intervals along a ray, from the sorted distances at which it
/// crosses the faces of a closed solid. Entering and leaving pair up; a
/// trailing unpaired crossing is a grazing hit and is dropped rather than
/// turned into a span that runs to infinity.
List<(double, double)> solidSpans(List<double> hits) {
  final out = <(double, double)>[];
  for (var i = 0; i + 1 < hits.length; i += 2) {
    if (hits[i + 1] > hits[i]) out.add((hits[i], hits[i + 1]));
  }
  return out;
}

/// Is parameter [t] strictly inside material?
bool insideSpans(List<(double, double)> spans, double t, double tol) {
  for (final s in spans) {
    if (t > s.$1 + tol && t < s.$2 - tol) return true;
  }
  return false;
}

/// Whether a bore is open at both ends, from its own axial extent and what a
/// ray along its axis crosses.
///
/// ISSUE #72 — THE BUG THIS REPLACES, because it produced a part with no
/// floor and a digest that could not say so. The old test cast a ray from
/// `centroid - axis * 1e6`, and a bore's mesh centroid lies ON THE BORE WALL,
/// not on its axis — so the ray ran tangent to the cylinder, from a million
/// millimetres away. Then it read the result backwards: along the axis of a
/// THROUGH hole a ray crosses nothing at all (it is in free air the whole
/// way), which the old code scored as "depth unknown", while a BLIND hole
/// gives two crossings, which it scored as "through".
///
/// The honest test is containment, not crossing count: a bore is through when
/// there is no material immediately beyond EITHER end of it. The depth is the
/// bore's own axial length either way, which is a fact about the cylindrical
/// face and needs no ray at all — so a build with no kernel linked still
/// reports a depth instead of a shrug.
({bool? through, double depth}) classifyBore({
  required double t0,
  required double t1,
  required List<double> hits,
  required bool haveShape,
}) {
  final depth = (t1 - t0).abs();
  if (!haveShape) return (through: null, depth: depth);
  final spans = solidSpans(hits);
  // Far enough off the ends to clear the mouth faces, small enough that a
  // 1 mm-deep counterbore is still measured rather than stepped over.
  final eps = math.max(1e-3, depth * 0.02);
  final capped = insideSpans(spans, t0 - eps, 1e-9) ||
      insideSpans(spans, t1 + eps, 1e-9);
  return (through: !capped, depth: depth);
}

/// Cylindrical faces whose normals point inward, grouped by diameter and axis.
///
/// A concave cylinder that is NOT tangentially blended into its neighbours is
/// a hole. A concave cylinder that is tangent is an internal fillet, and is
/// counted by [_blends] instead.
List<HoleGroup> _holes(List<DigestFace> faces, OcctShape? shape,
    OcctMeshData mesh, double diagonal, void Function(double) claim) {
  final candidates = [
    for (final f in faces)
      if (f.type == kFaceCylinder && f.concave && !f.tangent && f.radius > 0) f
  ];
  final groups = <String, List<DigestFace>>{};
  for (final f in candidates) {
    // Round the key so two faces of one drilled hole land together, and an
    // axis and its reverse are the same axis.
    final d = (f.diameter * 100).round();
    final ax = f.dir.x.abs() > f.dir.y.abs() && f.dir.x.abs() > f.dir.z.abs()
        ? 'x'
        : f.dir.y.abs() > f.dir.z.abs()
            ? 'y'
            : 'z';
    groups.putIfAbsent('$d|$ax', () => []).add(f);
  }
  final out = <HoleGroup>[];
  for (final g in groups.values) {
    final first = g.first;
    for (final f in g) {
      claim(f.area);
    }
    // How far the bore runs along its own axis, measured from the triangles
    // of its wall. This is the hole's depth, and it does not need a kernel.
    final ids = {for (final f in g) f.id};
    final n = first.dir;
    var t0 = double.infinity, t1 = -double.infinity;
    for (var t = 0; t + 2 < mesh.indices.length; t += 3) {
      final face = t ~/ 3 < mesh.triFaces.length ? mesh.triFaces[t ~/ 3] : -1;
      if (!ids.contains(face)) continue;
      for (var k = 0; k < 3; k++) {
        final i = mesh.indices[t + k] * 3;
        if (i + 2 >= mesh.positions.length) continue;
        final rel = Vec3(mesh.positions[i], mesh.positions[i + 1],
                mesh.positions[i + 2]) -
            first.at;
        final along = rel.dot(n);
        if (along < t0) t0 = along;
        if (along > t1) t1 = along;
      }
    }
    bool? through;
    double? depth;
    if (t0.isFinite && t1.isFinite && t1 > t0) {
      List<double> hits = const [];
      if (shape != null) {
        // ON THE AXIS, and starting a body-length clear of the near mouth —
        // not from a point on the bore wall a million millimetres away.
        final margin = (t1 - t0) + diagonal + 1;
        final o = first.at + n * (t0 - margin);
        hits = [
          for (final d in shape.rayHits(o.x, o.y, o.z, n.x, n.y, n.z))
            t0 - margin + d
        ];
      }
      final verdict = classifyBore(
          t0: t0, t1: t1, hits: hits, haveShape: shape != null);
      through = verdict.through;
      depth = verdict.depth;
    }
    // Merge the two half-cylinders OCCT splits a bore into: distinct faces,
    // one hole. Centres closer than the radius are the same bore.
    final centres = <Vec3>[];
    for (final f in g) {
      final axisPoint = f.at;
      if (!centres.any((c) => (c - axisPoint).length < math.max(f.radius, 0.01))) {
        centres.add(axisPoint);
      }
    }
    out.add(HoleGroup(first.diameter, first.dir, through, depth, centres));
  }
  out.sort((a, b) => b.count.compareTo(a.count));
  return out;
}

/// Tangentially connected curved faces — Inventor's rounds and fillets.
List<BlendGroup> _blends(List<DigestFace> faces, void Function(double) claim) {
  final byKey = <String, int>{};
  final radiusOf = <String, double>{};
  final convexOf = <String, bool>{};
  for (final f in faces) {
    if (!f.tangent || f.radius <= 0) continue;
    if (f.type != kFaceCylinder && f.type != kFaceTorus) continue;
    claim(f.area);
    final key = '${(f.radius * 100).round()}|${f.concave}';
    byKey[key] = (byKey[key] ?? 0) + 1;
    radiusOf[key] = f.radius;
    convexOf[key] = !f.concave;
  }
  final out = [
    for (final e in byKey.entries)
      BlendGroup(radiusOf[e.key]!, convexOf[e.key]!, e.value)
  ]..sort((a, b) => b.count.compareTo(a.count));
  return out.take(6).toList();
}

/// Thinnest wall and the two faces it lies between, by casting inward from
/// planar face centroids. Null without a B-Rep — a thickness nobody measured
/// is not a number worth printing.
(double, String)? _minWall(List<DigestFace> faces, OcctShape? shape) {
  if (shape == null) return null;
  double? best;
  String? where;
  final planes = [for (final f in faces) if (f.type == kFacePlane) f]
    ..sort((a, b) => b.area.compareTo(a.area));
  for (final f in planes.take(24)) {
    final n = f.dir;
    if (n.length < 0.5) continue;
    final p = f.centroid;
    // Start a hair inside so the face we came from is not the first hit.
    final o = p - n * 1e-4;
    final hits = shape.rayHits(o.x, o.y, o.z, -n.x, -n.y, -n.z);
    if (hits.isEmpty) continue;
    final d = hits.first.abs();
    // A crossing within microns of the origin is the face we started on,
    // returned because the ray origin sits inside the kernel's tolerance —
    // not a wall. Printing it gave every part "walls min 0.00 mm", which is
    // a number no reader can use and every reader has to discount.
    if (!d.isFinite || d <= 0.01) continue;
    if (best == null || d < best) {
      best = d;
      where = 'between F${f.id} and the face behind it';
    }
  }
  return best == null ? null : (best, where!);
}

/// Principal planes the face set is symmetric about.
List<String> _mirrors(List<DigestFace> faces, Vec3 min, Vec3 max) {
  if (faces.length < 2) return const [];
  final c = Vec3((min.x + max.x) / 2, (min.y + max.y) / 2, (min.z + max.z) / 2);
  const tol = 0.01;
  final out = <String>[];
  for (var axis = 0; axis < 3; axis++) {
    var ok = true;
    for (final f in faces) {
      final m = _mirrorPoint(f.at, c, axis);
      final d = _mirrorDir(f.dir, axis);
      final found = faces.any((g) =>
          g.type == f.type &&
          (g.radius - f.radius).abs() < tol &&
          (g.at - m).length < tol &&
          ((g.dir - d).length < tol || (g.dir + d).length < tol));
      if (!found) {
        ok = false;
        break;
      }
    }
    if (ok) out.add(const ['YZ', 'XZ', 'XY'][axis]);
  }
  return out;
}

Vec3 _mirrorPoint(Vec3 p, Vec3 c, int axis) => switch (axis) {
      0 => Vec3(2 * c.x - p.x, p.y, p.z),
      1 => Vec3(p.x, 2 * c.y - p.y, p.z),
      _ => Vec3(p.x, p.y, 2 * c.z - p.z),
    };

Vec3 _mirrorDir(Vec3 d, int axis) => switch (axis) {
      0 => Vec3(-d.x, d.y, d.z),
      1 => Vec3(d.x, -d.y, d.z),
      _ => Vec3(d.x, d.y, -d.z),
    };

/// Cross-sections of the tessellation, evenly spaced along [axis] (0=X,1=Y,
/// 2=Z). Pure triangle/plane intersection — no kernel, milliseconds.
List<SectionProfile> sectionProfiles(
    OcctMeshData m, int axis, Vec3 min, Vec3 max) {
  final lo = [min.x, min.y, min.z][axis], hi = [max.x, max.y, max.z][axis];
  if (!(hi > lo)) return const [];
  final extent =
      math.max(max.x - min.x, math.max(max.y - min.y, max.z - min.z));
  final tol = math.max(extent * 1e-7, 1e-9);
  final out = <SectionProfile>[];
  for (var i = 0; i < kSectionStations; i++) {
    // Inset from the ends: a plane exactly on a cap intersects it degenerately
    // and reports a profile that is an artefact of where it was placed.
    final t = (i + 0.5) / kSectionStations;
    final at = lo + (hi - lo) * t;
    final loops = _sliceLoops(m, axis, at, tol);
    if (loops.isEmpty) continue;
    var x0 = double.infinity, y0 = double.infinity;
    var x1 = -double.infinity, y1 = -double.infinity;
    final areas = <double>[];
    for (final loop in loops) {
      var a2 = 0.0;
      for (var k = 0; k < loop.length; k++) {
        final p = loop[k], q = loop[(k + 1) % loop.length];
        a2 += p.$1 * q.$2 - q.$1 * p.$2;
        if (p.$1 < x0) x0 = p.$1;
        if (p.$2 < y0) y0 = p.$2;
        if (p.$1 > x1) x1 = p.$1;
        if (p.$2 > y1) y1 = p.$2;
      }
      areas.add((a2 / 2).abs());
    }
    // The largest outline is material; anything inside it is a hole, so it
    // comes off rather than adding. Taking |area| per loop and subtracting is
    // what makes this independent of the direction each loop was traced in.
    areas.sort();
    final solid = areas.last;
    final holes = areas.length < 2
        ? 0.0
        : areas.sublist(0, areas.length - 1).fold<double>(0, (a, b) => a + b);
    out.add(SectionProfile(
        at, loops.length, x1 - x0, y1 - y0, math.max(solid - holes, 0)));
  }
  return out;
}

/// The plane `axis = at` crossed with the mesh, chained into ordered outlines.
///
/// Chaining is what makes the area computable at all: the segments come out of
/// the triangles in arbitrary order AND arbitrary direction, so a shoelace over
/// the raw soup sums terms whose signs cancel. It returned zero for a shape
/// with an obvious area, which is exactly how this was caught.
/// The closed outlines where the plane `axis = at` cuts the mesh, in the
/// plane's own two coordinates (for Y: world X and Z).
List<List<(double, double)>> aiSliceLoops(
        OcctMeshData m, int axis, double at) =>
    _sliceLoops(m, axis, at, 1e-6);

List<List<(double, double)>> _sliceLoops(
    OcctMeshData m, int axis, double at, double tol) {
  final segs = _sliceSegments(m, axis, at);
  if (segs.isEmpty) return const [];
  bool same((double, double) a, (double, double) b) =>
      (a.$1 - b.$1).abs() <= tol && (a.$2 - b.$2).abs() <= tol;

  final used = List<bool>.filled(segs.length, false);
  final loops = <List<(double, double)>>[];
  for (var i = 0; i < segs.length; i++) {
    if (used[i]) continue;
    used[i] = true;
    final loop = <(double, double)>[segs[i].$1, segs[i].$2];
    var grew = true;
    while (grew) {
      grew = false;
      for (var j = 0; j < segs.length; j++) {
        if (used[j]) continue;
        final (a, b) = segs[j];
        if (same(a, loop.last)) {
          loop.add(b);
        } else if (same(b, loop.last)) {
          loop.add(a);
        } else if (same(b, loop.first)) {
          loop.insert(0, a);
        } else if (same(a, loop.first)) {
          loop.insert(0, b);
        } else {
          continue;
        }
        used[j] = true;
        grew = true;
      }
    }
    // Drop the duplicated closing point so the shoelace does not count it.
    if (loop.length > 2 && same(loop.first, loop.last)) loop.removeLast();
    if (loop.length >= 3) loops.add(loop);
  }
  return loops;
}

/// Segments where the plane `axis = at` crosses the mesh, in the plane's own
/// two coordinates.
List<((double, double), (double, double))> _sliceSegments(
    OcctMeshData m, int axis, double at) {
  final out = <((double, double), (double, double))>[];
  double coord(int i, int k) => m.positions[i * 3 + k];
  final (u, v) = switch (axis) {
    0 => (1, 2),
    1 => (0, 2),
    _ => (0, 1),
  };
  for (var t = 0; t + 2 < m.indices.length; t += 3) {
    final idx = [m.indices[t], m.indices[t + 1], m.indices[t + 2]];
    final crossings = <(double, double)>[];
    for (var e = 0; e < 3; e++) {
      final a = idx[e], b = idx[(e + 1) % 3];
      if (a * 3 + 2 >= m.positions.length || b * 3 + 2 >= m.positions.length) {
        continue;
      }
      final da = coord(a, axis) - at, db = coord(b, axis) - at;
      if ((da > 0 && db > 0) || (da < 0 && db < 0)) continue;
      if (da == db) continue;
      final f = da / (da - db);
      crossings.add((
        coord(a, u) + (coord(b, u) - coord(a, u)) * f,
        coord(a, v) + (coord(b, v) - coord(a, v)) * f,
      ));
    }
    if (crossings.length >= 2) out.add((crossings[0], crossings[1]));
  }
  return out;
}

/// Projected front area down each axis: the silhouette a view from that
/// direction would show, summed over front-facing triangles.
List<double> frontAreas(OcctMeshData m) {
  final out = [0.0, 0.0, 0.0];
  for (var t = 0; t + 2 < m.indices.length; t += 3) {
    final i0 = m.indices[t] * 3, i1 = m.indices[t + 1] * 3,
        i2 = m.indices[t + 2] * 3;
    if (i2 + 2 >= m.positions.length) continue;
    final a = Vec3(m.positions[i0], m.positions[i0 + 1], m.positions[i0 + 2]);
    final b = Vec3(m.positions[i1], m.positions[i1 + 1], m.positions[i1 + 2]);
    final c = Vec3(m.positions[i2], m.positions[i2 + 1], m.positions[i2 + 2]);
    final n = (b - a).cross(c - a) * 0.5;
    if (n.x > 0) out[0] += n.x;
    if (n.y > 0) out[1] += n.y;
    if (n.z > 0) out[2] += n.z;
  }
  return out;
}

// ---------------------------------------------------------------------------
// The part-level entry point, with the cache that keeps it free to ask for.
// ---------------------------------------------------------------------------

/// Digests keyed by body name, cached against the geometry they describe.
///
/// The key is the concatenated [PartFeature.builtSig] of the features that
/// make each body — the same signature the rebuild uses to decide whether a
/// feature needs recomputing. So a digest is computed at most once per change
/// to the geometry, and a turn that changed nothing costs nothing.
class ShapeDigestCache {
  final Map<String, (String, ShapeDigest)> _byBody = {};

  ShapeDigest? of(PartModel part, String body, PartKernel kernel) {
    final solid = currentBodySolid(part, body);
    if (solid == null) return null;
    final key = [
      for (final f in part.features)
        if (f.bodyName == body) '${f.name}:${f.builtSig ?? "-"}'
    ].join('|');
    final hit = _byBody[body];
    if (hit != null && hit.$1 == key) return hit.$2;
    final made = computeShapeDigest(solid,
        body: body, edges: kernel.available ? kernel.edgesOf(solid) : const []);
    _byBody[body] = (key, made);
    return made;
  }

  /// Every built body of [part], largest first — the order a person would
  /// describe them in.
  List<ShapeDigest> all(PartModel part, PartKernel kernel) {
    final out = <ShapeDigest>[];
    for (final name in part.bodyNames) {
      final d = of(part, name, kernel);
      if (d != null) out.add(d);
    }
    out.sort((a, b) => b.volume.compareTo(a.volume));
    return out;
  }

  void clear() => _byBody.clear();
}

/// What goes into the assistant's context for a part: one digest per body,
/// capped so a twenty-body assembly cannot flood the turn.
String shapeContextFor(PartModel part, PartKernel kernel,
    ShapeDigestCache cache) {
  final digests = cache.all(part, kernel);
  if (digests.isEmpty) {
    return part.features.isEmpty
        ? 'No geometry yet: this part has no built body.'
        : 'No built geometry. '
            '${part.features.where((f) => f.computeError != null).length} '
            'feature(s) failed to build; the timeline above says which.';
  }
  const maxBodies = 3;
  final shown = digests.take(maxBodies);
  final text = shown.map((d) => d.toText()).join('\n\n');
  return digests.length > maxBodies
      ? '$text\n\n(${digests.length - maxBodies} smaller body/bodies not '
          'described here; ask with describe_shape for one by name.)'
      : text;
}
