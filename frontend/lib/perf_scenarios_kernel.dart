// Every 3D kernel operation, swept.
//
// WHY THIS IS SEPARATE FROM perf_scenarios.dart
// ---------------------------------------------
// That file grew out of one investigation (the crash inside `allEdges`) and
// covers what that investigation needed. This one is the systematic pass: EVERY
// operation the OCCT shim exposes, each measured against the input dimension
// that actually drives its cost. Twenty scenarios that answer "what does this
// op cost, and how does that grow" beat one profile of a session nobody can
// reproduce.
//
// WHAT EACH SWEEP IS SWEPT AGAINST — and why that choice matters
// --------------------------------------------------------------
// A cost curve is only meaningful against the RIGHT axis. Extrude scales with
// profile point count; fillet scales with the number of edges being blended;
// tessellation scales with deflection AND with B-Rep complexity, which are
// two different axes and are therefore two different sweeps. Picking the wrong
// axis produces a flat line and the false conclusion that an operation is
// cheap, which is the M75 mistake with a graph attached.
//
// EVERY SCENARIO IS GUARDED
// -------------------------
// A kernel op can fail on a degenerate input (a self-intersecting sweep, a
// fillet radius larger than the local geometry allows), and a benchmark that
// throws loses every number after it. Failures are counted, not thrown:
// `kernel.<op>.fail` in the counters is the signal that a scenario measured
// nothing, so a zero can never be mistaken for "free".
import 'dart:math' as math;

import 'ffi/occt_engine.dart';
import 'perf.dart';
import 'perf_scenarios.dart' show PerfScenario, ringProfile;

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/// Row-major 3x4 identity placement, the shape [PlaneFrame.mat34] produces for
/// the XY plane at zero offset. Every placed op takes one of these; using the
/// identity keeps the measurement about the operation rather than about where
/// the result landed.
List<double> identityMat34() => const [
      1, 0, 0, 0, //
      0, 1, 0, 0, //
      0, 0, 1, 0, //
    ];

/// A closed ring as flat (x, y, BULGE) triplets, optionally off-centre.
///
/// The encoding split matters and is easy to get wrong: `extrudeProfile` and
/// `extrudePolygon` take (x, y) PAIRS, while `extrudeProfileArcs`, `revolve`,
/// `sweep`, `loft` and `coil` all take (x, y, bulge) TRIPLETS. Handing the
/// wrong one over does not throw — the arity check simply returns null, the
/// scenario records a fast zero, and the operation looks free. `_guard` counts
/// those nulls for exactly this reason.
List<double> arcRing(int n, double r, {double cx = 0, double cy = 0}) {
  final out = <double>[];
  for (var i = 0; i < n; i++) {
    final a = 2 * math.pi * i / n;
    out
      ..add(cx + r * math.cos(a))
      ..add(cy + r * math.sin(a))
      ..add(0.0);
  }
  return out;
}

/// A closed polygon as flat (x, y) PAIRS — what [extrudeProfile] and
/// [extrudePolygon] expect, as opposed to the (x, y, bulge) triplets
/// [ringProfile] produces for the arc-aware entry point.
List<double> polyProfile(int n, double r, {double cx = 0, double cy = 0}) {
  final out = <double>[];
  for (var i = 0; i < n; i++) {
    final a = 2 * math.pi * i / n;
    out..add(cx + r * math.cos(a))..add(cy + r * math.sin(a));
  }
  return out;
}

/// An outer boundary with [holes] circular holes strictly inside it — the
/// multi-loop case, which is what a real part profile almost always is and
/// which the single-loop sweeps deliberately do not cover.
List<List<double>> holedProfile(int n, double r, int holes) {
  final loops = <List<double>>[polyProfile(n, r)];
  for (var h = 0; h < holes; h++) {
    final a = 2 * math.pi * h / math.max(holes, 1);
    loops.add(polyProfile(12, r * 0.12,
        cx: r * 0.55 * math.cos(a), cy: r * 0.55 * math.sin(a)));
  }
  return loops;
}

/// A gentle 3D arc as flat (x, y, z) triplets — a sweep path with real
/// curvature. A straight path would let the kernel take a fast route that a
/// user's sweep never gets.
List<double> arcPath(int n, double r) {
  final out = <double>[];
  for (var i = 0; i < n; i++) {
    final t = i / (n - 1);
    final a = t * math.pi / 2;
    out
      ..add(r * math.sin(a) * 0.3)
      ..add(r * (1 - math.cos(a)) * 0.3)
      ..add(t * r);
  }
  return out;
}

/// Records that an op returned null. See the header: a silent failure is
/// indistinguishable from a fast success in a timing report.
T? _guard<T>(String op, T? Function() f) {
  try {
    final r = f();
    if (r == null) Perf.count('kernel.$op.fail');
    return r;
  } catch (_) {
    Perf.count('kernel.$op.throw');
    return null;
  }
}

// ---------------------------------------------------------------------------
// The suite
// ---------------------------------------------------------------------------

List<PerfScenario> buildKernelScenarios() {
  final out = <PerfScenario>[];
  final occt = OcctFfi.instance();
  if (occt == null) return out;

  // ---- creation: the five profile-driven feature kinds --------------------
  //
  // All five swept against PROFILE POINT COUNT, the one axis they share, so
  // their curves are directly comparable: "a loft costs 8x an extrude at the
  // same profile size" is a sentence you can only write if both were measured
  // the same way.

  for (final n in const [12, 48, 120]) {
    out.add(PerfScenario(
      'kernel.extrude.arcs.$n',
      () {
        Perf.gauge('kernel.profilePts', n);
        _guard('extrude', () => occt.extrudeProfileArcs([ringProfile(n, 40)], 10.0))
            ?.dispose();
      },
      note: 'extrude via the arc-aware entry point (what a sketch profile with '
          'bulges actually uses) vs profile point count',
    ));
  }

  out.add(PerfScenario(
    'kernel.extrude.plain',
    () {
      for (final n in const [12, 48, 120]) {
        _guard('extrudePlain', () => occt.extrudeProfile([polyProfile(n, 40)], 10.0))
            ?.dispose();
      }
    },
    note: 'the (x,y)-pair entry point; compare against kernel.extrude.arcs at '
        'the same n to price the bulge handling',
  ));

  out.add(PerfScenario(
    'kernel.extrude.taper',
    () {
      for (final d in const [0.0, 5.0, 15.0]) {
        _guard('extrudeTaper',
                () => occt.extrudeProfileArcs([ringProfile(48, 40)], 10.0, taperDeg: d))
            ?.dispose();
      }
    },
    note: 'draft angle cost: 0 deg is a prism, non-zero is a lofted solid — '
        'compare the three to see what turning taper on costs',
  ));

  out.add(PerfScenario(
    'kernel.extrude.holes',
    () {
      for (final h in const [0, 4, 12]) {
        Perf.gauge('kernel.holes', h);
        _guard('extrudeHoles',
                () => occt.extrudeProfile(holedProfile(48, 40, h), 10.0))
            ?.dispose();
      }
    },
    note: 'inner loops (holes) vs cost — a real part profile is never a single '
        'loop, and the single-loop sweeps do not cover this at all',
  ));

  for (final n in const [12, 48, 120]) {
    out.add(PerfScenario(
      'kernel.revolve.$n',
      () {
        Perf.gauge('kernel.profilePts', n);
        // Profile offset well clear of the axis: a profile touching its own
        // axis of revolution is a degenerate case with a different cost, and
        // measuring it by accident would misprice every revolve.
        final loops = [arcRing(n, 8, cx: 40)];
        _guard(
                'revolve',
                () => occt.revolveProfile(loops, 360.0,
                    axPx: 0, axPy: 0, axDx: 0, axDy: 1))
            ?.dispose();
      },
      note: 'full revolution vs profile point count',
    ));
  }

  out.add(PerfScenario(
    'kernel.revolve.angle',
    () {
      for (final a in const [45.0, 180.0, 360.0]) {
        _guard(
                'revolveAngle',
                () => occt.revolveProfile([arcRing(48, 8, cx: 40)], a,
                    axPx: 0, axPy: 0, axDx: 0, axDy: 1))
            ?.dispose();
      }
    },
    note: 'partial vs full revolution — a partial one has two extra cap faces, '
        'so cheaper is not the obvious answer',
  ));

  for (final n in const [12, 48]) {
    out.add(PerfScenario(
      'kernel.sweep.$n',
      () {
        Perf.gauge('kernel.profilePts', n);
        Perf.gauge('kernel.pathPts', 24);
        _guard(
                'sweep',
                () => occt.sweepProfile(
                    [arcRing(n, 6)], identityMat34(), arcPath(24, 60)))
            ?.dispose();
      },
      note: 'sweep along a curved path vs profile point count',
    ));
  }

  out.add(PerfScenario(
    'kernel.sweep.path',
    () {
      for (final p in const [6, 24, 96]) {
        Perf.gauge('kernel.pathPts', p);
        _guard(
                'sweepPath',
                () => occt.sweepProfile(
                    [arcRing(24, 6)], identityMat34(), arcPath(p, 60)))
            ?.dispose();
      }
    },
    note: 'the OTHER axis of a sweep: path resolution at a fixed profile. If '
        'this grows faster than kernel.sweep.* then the path, not the profile, '
        'is what makes a sweep expensive',
  ));

  out.add(PerfScenario(
    'kernel.sweep.twist',
    () {
      for (final t in const [0.0, 90.0, 360.0]) {
        _guard(
                'sweepTwist',
                () => occt.sweepProfile(
                    [arcRing(24, 6)], identityMat34(), arcPath(24, 60),
                    twistDeg: t))
            ?.dispose();
      }
    },
    note: 'twist cost on an otherwise identical sweep',
  ));

  for (final sections in const [2, 4, 8]) {
    out.add(PerfScenario(
      'kernel.loft.$sections',
      () {
        Perf.gauge('kernel.loftSections', sections);
        final enc = <List<double>>[];
        final mats = <List<double>>[];
        for (var i = 0; i < sections; i++) {
          // Radius varies per section so the loft has real work to do; equal
          // sections would let the kernel produce something close to a prism.
          enc.add(arcRing(24, 20 + 6.0 * i));
          final m = List<double>.from(identityMat34());
          m[11] = i * 15.0; // translate along +Z
          mats.add(m);
        }
        _guard('loft', () => occt.loftSections(enc, mats))?.dispose();
      },
      note: 'loft vs SECTION COUNT at a fixed profile size — the axis a user '
          'controls directly by adding sketches',
    ));
  }

  out.add(PerfScenario(
    'kernel.loft.ruled',
    () {
      final enc = [for (var i = 0; i < 4; i++) arcRing(24, 20 + 6.0 * i)];
      final mats = [
        for (var i = 0; i < 4; i++)
          (List<double>.from(identityMat34())..[11] = i * 15.0)
      ];
      for (final ruled in const [false, true]) {
        _guard('loftRuled', () => occt.loftSections(enc, mats, ruled: ruled))
            ?.dispose();
      }
    },
    note: 'smooth vs ruled loft — ruled is straight segments between sections '
        'and should be dramatically cheaper; if it is not, the cost is not in '
        'the surfacing',
  ));

  for (final rev in const [1.0, 4.0, 12.0]) {
    out.add(PerfScenario(
      'kernel.coil.${rev.toInt()}',
      () {
        Perf.gauge('kernel.coilRevs', rev.toInt());
        _guard(
                'coil',
                () => occt.coilProfile(
                    [arcRing(16, 4, cx: 30)],
                    identityMat34(),
                    const [0, 0, 0],
                    const [0, 0, 1],
                    revolutions: rev,
                    height: rev * 10))
            ?.dispose();
      },
      note: 'coil vs revolution count — a spring with 12 turns is the case '
          'that hurts, and this says by how much',
    ));
  }

  // ---- body modification -------------------------------------------------
  //
  // Fillet and chamfer are swept against EDGE COUNT, not profile size: the
  // user picks edges, and the picked count is what they control. The device
  // session showed the fillet FLOW dominated by finding the candidates rather
  // than by blending them, so both halves are measured.

  for (final k in const [1, 4, 12]) {
    out.add(PerfScenario(
      'kernel.fillet.edges.$k',
      () {
        final s = _guard('filletBase',
            () => occt.extrudeProfileArcs([ringProfile(24, 40)], 10.0));
        if (s == null) return;
        try {
          final cands = s.allEdges().where((e) => e.filletable).toList();
          if (cands.length < k) {
            Perf.count('kernel.fillet.tooFewEdges');
            return;
          }
          final ids = [for (final e in cands.take(k)) e.index];
          Perf.gauge('kernel.blendEdges', k);
          _guard('fillet',
                  () => s.filletEdges(ids, [for (final _ in ids) 1.0]))
              ?.dispose();
        } finally {
          s.dispose();
        }
      },
      note: 'blend cost vs NUMBER OF EDGES filleted at once. Linear means '
          'batching is free; superlinear means one fillet feature per edge is '
          'the cheaper shape for a part',
    ));
  }

  out.add(PerfScenario(
    'kernel.fillet.radius',
    () {
      for (final r in const [0.5, 2.0, 4.0]) {
        final s = _guard('filletRadBase',
            () => occt.extrudeProfileArcs([ringProfile(24, 40)], 10.0));
        if (s == null) continue;
        try {
          final cands = s.allEdges().where((e) => e.filletable).toList();
          if (cands.isEmpty) continue;
          final ids = [for (final e in cands.take(4)) e.index];
          _guard('filletRad', () => s.filletEdges(ids, [for (final _ in ids) r]))
              ?.dispose();
        } finally {
          s.dispose();
        }
      }
    },
    note: 'does a BIGGER radius cost more? It changes how much of the '
        'neighbouring geometry the blend has to interact with, so this is not '
        'obviously flat',
  ));

  for (final k in const [1, 4, 12]) {
    out.add(PerfScenario(
      'kernel.chamfer.edges.$k',
      () {
        final s = _guard('chamferBase',
            () => occt.extrudeProfileArcs([ringProfile(24, 40)], 10.0));
        if (s == null) return;
        try {
          final cands = s.allEdges().where((e) => e.filletable).toList();
          if (cands.length < k) {
            Perf.count('kernel.chamfer.tooFewEdges');
            return;
          }
          final ids = [for (final e in cands.take(k)) e.index];
          Perf.gauge('kernel.blendEdges', k);
          _guard(
                  'chamfer',
                  () => s.chamferEdges(ids, [for (final _ in ids) 0],
                      [for (final _ in ids) 1.0]))
              ?.dispose();
        } finally {
          s.dispose();
        }
      },
      note: 'chamfer vs edge count; compare against kernel.fillet.edges.N at '
          'the same N — chamfer is a planar face and should be much cheaper',
    ));
  }

  // ---- booleans ----------------------------------------------------------
  //
  // The existing kernel.boolean measures the FLOOR (a box and a cylinder).
  // What a part actually does is fuse increasingly complicated bodies, so
  // this sweeps against the complexity of the operands.

  for (final n in const [12, 48, 120]) {
    out.add(PerfScenario(
      'kernel.boolean.complex.$n',
      () {
        final a = _guard('boolA',
            () => occt.extrudeProfileArcs([ringProfile(n, 40)], 10.0));
        final b = _guard('boolB',
            () => occt.extrudeProfileArcs([ringProfile(n, 25)], 20.0));
        if (a == null || b == null) {
          a?.dispose();
          b?.dispose();
          return;
        }
        try {
          Perf.gauge('kernel.boolOperandEdges', a.edgeCount);
          _guard('fuse', () => occt.fuse(a, b))?.dispose();
          _guard('cut', () => occt.cut(a, b))?.dispose();
          _guard('common', () => occt.common(a, b))?.dispose();
        } finally {
          a.dispose();
          b.dispose();
        }
      },
      note: 'boolean cost vs OPERAND complexity, not the trivial pair. This is '
          'the number that says whether a 30-feature part is viable',
    ));
  }

  out.add(PerfScenario(
    'kernel.boolean.chain',
    () {
      // What a real part is: one accumulating body, fused with feature after
      // feature. If cost per fuse grows with the accumulated body, a long
      // feature tree gets quadratically slower — and nothing in the existing
      // suite would show that.
      var acc = _guard('chainBase', () => occt.makeBox(60, 60, 10));
      if (acc == null) return;
      try {
        for (var i = 0; i < 8; i++) {
          final b = occt.makeCylinder(
              -20 + i * 6.0, -20 + i * 4.0, 0, 4, 20);
          if (b == null) continue;
          final next = _guard('chainFuse', () => occt.fuse(acc!, b));
          b.dispose();
          if (next == null) continue;
          acc!.dispose();
          acc = next;
          Perf.gauge('kernel.chainEdges', next.edgeCount);
        }
      } finally {
        acc?.dispose();
      }
    },
    note: 'EIGHT successive fuses onto one accumulating body — the shape of a '
        'real feature tree. Compare ffi.occt.fuse avgMs against worstMs: a big '
        'gap means the later fuses cost more, i.e. the tree is superlinear',
  ));

  out.add(PerfScenario(
    'kernel.unify',
    () {
      final a = occt.makeBox(60, 60, 10);
      final b = occt.makeBox(60, 60, 10);
      if (a == null || b == null) {
        a?.dispose();
        b?.dispose();
        return;
      }
      try {
        final f = _guard('unifyFuse', () => occt.fuse(a, b));
        if (f == null) return;
        try {
          Perf.gauge('kernel.unify.facesBefore', f.counts()?.faces ?? -1);
          final u = _guard('unify', () => occt.unify(f));
          if (u != null) {
            Perf.gauge('kernel.unify.facesAfter', u.counts()?.faces ?? -1);
            u.dispose();
          }
        } finally {
          f.dispose();
        }
      } finally {
        a.dispose();
        b.dispose();
      }
    },
    note: 'face merging after a boolean; the two face-count gauges say whether '
        'it earned its time',
  ));

  // ---- topology queries --------------------------------------------------
  //
  // allEdges is already swept in perf_scenarios.dart because it is the known
  // defect. These are its neighbours, measured so the comparison is fair: if
  // counts() and bbox() are instant on the same solid where allEdges takes
  // 600 ms, the cost is specific to edge_info and not to crossing the boundary
  // or to touching the shape at all.

  out.add(PerfScenario(
    'kernel.query.cheap',
    () {
      final s = _guard('queryBase',
          () => occt.extrudeProfileArcs([ringProfile(120, 40)], 10.0));
      if (s == null) return;
      try {
        for (var i = 0; i < 20; i++) {
          Perf.span('kernel.counts', () => s.counts());
          Perf.span('kernel.bbox', () => s.bbox());
        }
        Perf.gauge('kernel.query.edges', s.edgeCount);
      } finally {
        s.dispose();
      }
    },
    note: 'counts() and bbox() on the SAME 360-edge solid where allEdges costs '
        '600 ms. Near-zero here proves the quadratic is inside edge_info, not '
        'in the FFI crossing or in touching the shape',
  ));

  out.add(PerfScenario(
    'kernel.query.edgeInfoOne',
    () {
      final s = _guard('edgeInfoBase',
          () => occt.extrudeProfileArcs([ringProfile(120, 40)], 10.0));
      if (s == null) return;
      try {
        // ONE edge, twenty times. allEdges asks for all 360; if a single query
        // already costs ~1.7 ms then every call walks the whole topology and
        // the fix is a bulk entry point. If it is fast, the cost is elsewhere
        // and the diagnosis changes completely.
        for (var i = 0; i < 20; i++) {
          Perf.span('kernel.edgeInfo1', () => s.edgeInfo(1));
        }
      } finally {
        s.dispose();
      }
    },
    note: 'THE decisive measurement for the allEdges defect: cost of ONE '
        'edgeInfo on a 360-edge solid. Multiply by 360 and compare against the '
        'measured allEdges — if they match, every call re-walks the topology',
  ));

  out.add(PerfScenario(
    'kernel.rayHits',
    () {
      final s = _guard('rayBase',
          () => occt.extrudeProfileArcs([ringProfile(48, 40)], 10.0));
      if (s == null) return;
      try {
        for (var i = 0; i < 60; i++) {
          final t = i / 60.0;
          Perf.span('kernel.rayHit',
              () => s.rayHits(-100 + t * 10, 0, 5, 1, 0, 0));
        }
      } finally {
        s.dispose();
      }
    },
    note: 'the 3D pick path, 60 rays — one second of dragging a pick across a '
        'model. Compare against 2d.pickEntity for the 2D equivalent',
  ));

  out.add(PerfScenario(
    'kernel.transform',
    () {
      final s = _guard('xfBase',
          () => occt.extrudeProfileArcs([ringProfile(48, 40)], 10.0));
      if (s == null) return;
      try {
        for (var i = 0; i < 20; i++) {
          final m = List<double>.from(identityMat34())..[11] = i * 1.0;
          _guard('transform', () => s.transformed(m))?.dispose();
        }
      } finally {
        s.dispose();
      }
    },
    note: 'rigid placement, applied to every feature result. 20 calls on a '
        '144-edge solid; if this is not near-free it is being paid per feature '
        'per rebuild',
  ));

  // ---- tessellation ------------------------------------------------------
  //
  // The existing kernel.mesh.sweep varies DEFLECTION at a fixed solid. This
  // varies the SOLID at a fixed deflection, which is the axis a user moves
  // when they make a part more complicated.

  for (final n in const [12, 48, 120]) {
    out.add(PerfScenario(
      'kernel.mesh.complexity.$n',
      () {
        final s = _guard('meshBase',
            () => occt.extrudeProfileArcs([ringProfile(n, 40)], 10.0));
        if (s == null) return;
        try {
          Perf.gauge('kernel.mesh.srcEdges', s.edgeCount);
          final m = _guard('mesh', () => s.mesh(linDeflection: 0.2));
          if (m != null) Perf.gauge('kernel.mesh.tris', m.triangleCount);
        } finally {
          s.dispose();
        }
      },
      note: 'tessellation vs B-REP COMPLEXITY at fixed quality — the axis a '
          'user moves. kernel.mesh.sweep is the other axis (quality at fixed '
          'complexity); both are needed to predict a real part',
    ));
  }

  out.add(PerfScenario(
    'kernel.mesh.repeat',
    () {
      final s = _guard('meshRepeatBase',
          () => occt.extrudeProfileArcs([ringProfile(48, 40)], 10.0));
      if (s == null) return;
      try {
        for (var i = 0; i < 5; i++) {
          _guard('meshRepeat', () => s.mesh(linDeflection: 0.2));
        }
      } finally {
        s.dispose();
      }
    },
    note: 'five tessellations of the SAME solid at the same quality. OCCT '
        'caches a triangulation on the shape, so a flat non-zero average here '
        'means the cache is being missed and every re-mesh is paid in full',
  ));

  return out;
}
