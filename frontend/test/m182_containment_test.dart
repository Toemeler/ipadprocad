// M182 — a failure stays one failure, and a display choice is never a change.
//
// From a device session (build 29c203a) that turned a working part into
// rubble. The log tells the whole story, and it is three separate defects
// wearing one costume:
//
//   1. "if i only removed one extrusion by making it invisible the whole solid
//      broke" — `chainLast[bodyName]` was only updated `if (f.visible)`, so an
//      EYE decided whether a feature entered the boolean chain. Hiding one
//      extrusion re-meant every feature after it: the log shows Extrusion2/3/4
//      building with no base at all and Chamfer1 reporting "nothing to modify
//      — no solid before this feature" while the extrusions it sits on all
//      say ok. A body's shape must not depend on what is being drawn.
//
//   2. "the whole second solid broke completely and was unusable" — a failed
//      feature dropped the accumulator and the loop CARRIED ON. Revolution1
//      failed, and the cut that followed it, finding no base, quietly stopped
//      being a cut and materialised as a positive lump. One broken feature
//      rewrote the meaning of every feature after it, and nothing said which
//      one had actually gone wrong.
//
//   3. "revolutions failed suddenly and I couldn't get them back to work" —
//      two projected segments of the revolve profile followed their stored
//      INDEX onto edges ~100 mm away ("source CHANGED by 143.35 — following
//      it"). The sketch went from a closed loop to none, and every revolve
//      built on it failed with "no closed profile".
//
// The rule these tests pin is one rule: NOTHING may silently change the
// meaning of something else. A hidden feature still builds. A failed feature
// stops its body instead of re-meaning it, and says what it is waiting for. A
// re-projection that would leave a sketch with no profile is refused whole.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/widgets/native_browser.dart';

/// A kernel that builds anything, and fails exactly where it is told to.
class _Kernel implements PartKernel {
  /// Extrude HEIGHTS whose build must fail. Each feature in these tests has a
  /// distinct height, so this singles one out with no hook into the recompute
  /// loop — the fake needs no more than what the kernel is actually told.
  final Set<double> failing = {};

  int booleans = 0;

  @override
  bool get available => true;
  @override
  String get info => 'test';
  @override
  String get lastError => 'the kernel refused';
  @override
  List<KernelSolid> importStepSolids(String path) => const [];

  KernelSolid _solid(double v) => KernelSolid(
      OcctMeshData(
          Float64List.fromList(const [0, 0, 0, 1, 0, 0, 0, 1, 0]),
          Float64List.fromList(const [0, 0, 1, 0, 0, 1, 0, 0, 1]),
          Int32List.fromList(const [0, 1, 2]),
          Int32List.fromList(const [0, 3]),
          Float64List.fromList(const [0, 0, 0, 1, 0, 0, 0, 1, 0])),
      v,
      null);

  @override
  KernelSolid? extrude(List<List<List<Offset>>> groups, double height,
          double taperDeg, List<double> mat34) =>
      failing.contains(height) ? null : _solid(height);

  @override
  KernelSolid? fuseSolids(KernelSolid a, KernelSolid b) {
    booleans++;
    return _solid(a.volume + b.volume);
  }

  @override
  KernelSolid? cutSolids(KernelSolid a, KernelSolid b) {
    booleans++;
    return _solid(a.volume - b.volume);
  }

  @override
  noSuchMethod(Invocation i) => null;
}

AppState _app() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('prototype_m182_');
  return app;
}

void _addRect(SketchModel s, double x0, double y0, double x1, double y1,
    {required String layer}) {
  s.engine.setCurrentLayer(layer);
  s.engine.addLine(x0, y0, x1, y0);
  s.engine.addLine(x1, y0, x1, y1);
  s.engine.addLine(x1, y1, x0, y1);
  s.engine.addLine(x0, y1, x0, y0);
  s.refresh();
}

/// A part whose Solid1 is a CHAIN: new, then join, then cut.
Future<PartModel> _chainOfThree(AppState app) async {
  await app.createNamedPart('Part1');
  const outputs = ['new', 'join', 'cut'];
  for (var i = 0; i < outputs.length; i++) {
    app.startPartSketch();
    app.planePicked('xy');
    _addRect(app.activeChild!, i * 30.0, 0, i * 30.0 + 20, 10,
        layer: app.editingLayer!);
    app.finishPartSketch();
    app.openExtrude();
    app.setExtrude(exprA: '${_height(i)} mm', output: outputs[i]);
    await app.applyExtrude();
  }
  return app.currentPart!;
}

/// The distinct extrude height of chain member [i].
double _height(int i) => 5.0 + i;

/// name -> the volume its feature currently holds ('-' when it holds nothing).
Map<String, String> _shape(PartModel p) => {
      for (final f in p.features)
        f.name: f.solid == null ? '-' : f.solid!.volume.toStringAsFixed(6)
    };

void main() {
  group('M182 — an eye never changes the model', () {
    test('hiding a feature leaves every solid in the part identical', () async {
      final app = _app();
      final k = _Kernel();
      app.partKernel = k;
      final p = await _chainOfThree(app);
      expect(p.features.length, 3);

      recomputeAllFeatures(p, k, force: true);
      final before = _shape(p);
      expect(before.values.where((v) => v != '-'), isNotEmpty);

      // Hide each feature in turn — including the base of the chain, which is
      // the case that broke the part on the device.
      for (final f in p.features) {
        f.visible = false;
        recomputeAllFeatures(p, k, force: true);
        expect(_shape(p), before,
            reason: 'hiding ${f.name} changed the geometry of the part');
        f.visible = true;
      }
    });

    test('a hidden feature still carries the chain to the one after it',
        () async {
      final app = _app();
      final k = _Kernel();
      app.partKernel = k;
      final p = await _chainOfThree(app);
      p.features.first.visible = false;
      recomputeAllFeatures(p, k, force: true);
      for (final f in p.features.skip(1)) {
        expect(f.computeError, isNull,
            reason: '${f.name} lost its base because something was hidden');
      }
    });

    test('hiding does not invalidate the cached solid', () async {
      final app = _app();
      final k = _Kernel();
      app.partKernel = k;
      final p = await _chainOfThree(app);
      recomputeAllFeatures(p, k);
      final sigs = [for (final f in p.features) featureInputSig(p, f)];
      for (final f in p.features) {
        f.visible = !f.visible;
      }
      expect([for (final f in p.features) featureInputSig(p, f)], sigs,
          reason: 'an eye must not send the kernel back to work');
    });
  });

  group('M182 — a failure stops its body instead of re-meaning it', () {
    test('everything after the failure is HELD, holding no geometry', () async {
      final app = _app();
      final k = _Kernel();
      app.partKernel = k;
      final p = await _chainOfThree(app);
      final names = [for (final f in p.features) f.name];

      k.failing.add(_height(1));
      recomputeAllFeatures(p, k, force: true);

      expect(p.features[0].computeError, isNull);
      expect(p.features[1].computeError, isNotNull,
          reason: 'the feature that actually failed says so');
      expect(p.features[1].isBlocked, isFalse,
          reason: 'it failed; it is not waiting for anyone');

      final held = p.features[2];
      expect(held.isBlocked, isTrue);
      expect(held.blockedBy, names[1]);
      expect(held.computeError, contains(names[1]),
          reason: 'the error must name the feature to go and fix');
      expect(held.solid, isNull,
          reason: 'a cut with nothing to cut from must not materialise as a '
              'body — that is what made the second solid unusable');
    });

    test('fixing the failure brings the whole body back', () async {
      final app = _app();
      final k = _Kernel();
      app.partKernel = k;
      final p = await _chainOfThree(app);

      recomputeAllFeatures(p, k, force: true);
      final good = _shape(p);

      k.failing.add(_height(1));
      recomputeAllFeatures(p, k, force: true);
      expect(_shape(p), isNot(good));

      k.failing.clear();
      recomputeAllFeatures(p, k, force: true);
      expect(_shape(p), good,
          reason: 'nothing downstream was rewritten, so nothing has to be '
              'rebuilt by hand');
      for (final f in p.features) {
        expect(f.isBlocked, isFalse);
        expect(f.computeError, isNull);
      }
    });

    test('a second body is untouched by the first one breaking', () async {
      final app = _app();
      final k = _Kernel();
      app.partKernel = k;
      final p = await _chainOfThree(app);
      // Move the last feature onto its own body, as "New Solid" does.
      p.features.last
        ..bodyName = 'Solid2'
        ..output = 'new';
      recomputeAllFeatures(p, k, force: true);
      final other = p.features.last.solid?.volume;
      expect(other, isNotNull);

      k.failing.add(_height(0));
      recomputeAllFeatures(p, k, force: true);
      expect(p.features.last.isBlocked, isFalse,
          reason: 'Solid2 does not stand on Solid1');
      expect(p.features.last.solid?.volume, other);
    });
  });

  group('M182 — a feature opens to reveal its sketch', () {
    test('the disclosure key is the row id the browser hands back', () async {
      // onExpand stores the id it was given ('ft:Extrusion1'); the row asked
      // for the bare name ('Extrusion1'), so the set never matched and no
      // extrusion, revolve, sweep or coil could be opened at all.
      final app = _app();
      app.partKernel = _Kernel();
      final p = await _chainOfThree(app);
      final f = p.features.first;
      final rowId = '$kIdFeature${f.name}';

      final shut = buildBrowserRows(app, expanded: {});
      final row = shut.firstWhere((r) => r.id == rowId);
      expect(row.expandable, isTrue,
          reason: 'it consumes a sketch, so there is something to reveal');
      expect(row.expanded, isFalse);
      expect(shut.any((r) => r.id.startsWith(kIdNested)), isFalse);

      final open = buildBrowserRows(app, expanded: {rowId});
      expect(open.firstWhere((r) => r.id == rowId).expanded, isTrue);
      final nested = open.where((r) => r.id.startsWith(kIdNested));
      expect(nested, hasLength(1),
          reason: 'the sketch under the feature');
      expect(nested.single.label, f.sketchName);
    });

    test('the bare name is not a key', () async {
      final app = _app();
      app.partKernel = _Kernel();
      final p = await _chainOfThree(app);
      final f = p.features.first;
      final rows = buildBrowserRows(app, expanded: {f.name});
      expect(rows.firstWhere((r) => r.id == '$kIdFeature${f.name}').expanded,
          isFalse,
          reason: 'one key, and it is the id — not two that look alike');
    });
  });

  group('M182 — a re-projection may not empty a sketch', () {
    SketchModel closedSquare() {
      final s = SketchModel('S');
      s.layers.add(kDefaultLayer);
      _addRect(s, 0, 0, 20, 10, layer: kDefaultLayer);
      return s;
    }

    test('the guard only fires on a sketch that HAD a profile', () {
      final empty = SketchModel('E')..layers.add(kDefaultLayer);
      expect(projectionUpdateWouldEmptyProfile(empty, const []), isFalse,
          reason: 'nothing to lose, so nothing to refuse');
    });

    test('an update that keeps the loop closed is allowed', () {
      final s = closedSquare();
      expect(profileLoops(s), isNotEmpty);
      // The whole square moves 100 mm: still a square, still a profile.
      final moved = [
        for (final g in s.geometry)
          g.withData([
            for (var i = 0; i < g.data.length; i++)
              i.isEven ? g.data[i] + 100 : g.data[i]
          ])
      ];
      expect(projectionUpdateWouldEmptyProfile(s, moved), isFalse);
    });

    test('an update that breaks the loop is refused', () {
      final s = closedSquare();
      expect(profileLoops(s), isNotEmpty);
      // One segment teleports — exactly the "source CHANGED by 143" case. The
      // square stops closing, and every feature standing on it would fail with
      // "no closed profile".
      final broken = [...s.geometry];
      broken[0] = broken[0].withData([500.0, 500.0, 520.0, 500.0]);
      expect(projectionUpdateWouldEmptyProfile(s, broken), isTrue);
    });

    test('the sketch is left exactly as it was by the check itself', () {
      final s = closedSquare();
      final before = [for (final g in s.geometry) g.data.toList()];
      projectionUpdateWouldEmptyProfile(
          s, [s.geometry.first.withData([9.0, 9.0, 9.0, 9.0])]);
      expect([for (final g in s.geometry) g.data.toList()], before,
          reason: 'a question must not be an edit');
    });
  });
}

