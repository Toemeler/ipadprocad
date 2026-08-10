// M213 — the systematic pass, and the tests that keep it honest.
//
// M212 taught the lesson these tests exist to enforce: a scenario that measures
// NOTHING still produces a number, and that number is indistinguishable from a
// fast one. `gear.curve` read 0.000 ms for two builds because the memo swallowed
// nineteen of twenty calls; `2d.snap` was absent from every report ever produced
// because the scenario never reached the snap path; `ent.dofColour` read ~0
// because the fixture had no constraints for it to colour.
//
// So these tests do not check timings — a CI runner's milliseconds mean nothing.
// They check that each scenario REACHED ITS SUBJECT:
//
//   * every drawing tool actually produced geometry (a null result is a zero),
//   * the modify fixtures really intersect (on parallel lines trim exits early),
//   * the kernel scenarios really built solids,
//   * every scenario carries a note a reader can act on.
@Timeout(Duration(minutes: 15))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:native_menu/native_menu.dart';
import 'package:prototype/constraints.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/ffi/perf_hook.dart';
import 'package:prototype/modify.dart';
import 'package:prototype/perf.dart';
import 'package:prototype/perf_scenarios.dart';
import 'package:prototype/perf_scenarios_app.dart';
import 'package:prototype/perf_scenarios_kernel.dart';
import 'package:prototype/perf_scenarios_tools.dart';
import 'package:prototype/perf_scenarios_stress.dart';
import 'package:prototype/perf_scenarios_ui.dart';
import 'package:prototype/reality_scene.dart';
import 'package:prototype/tools.dart';

void main() {
  setUp(Perf.resetForTest);

  group('coverage — the suite reaches every subsystem', () {
    test('the headless suite covers tools, kernel and the original probes', () {
      final names = buildScenarios().map((s) => s.name).toSet();
      // One representative per area. Naming them individually is deliberate:
      // a count would still pass if an entire module stopped being wired in.
      expect(names.any((n) => n.startsWith('solve.')), isTrue);
      expect(names.any((n) => n.startsWith('analysis.')), isTrue);
      expect(names.any((n) => n.startsWith('gear.')), isTrue);
      expect(names.any((n) => n.startsWith('tools.')), isTrue);
      expect(names.any((n) => n.startsWith('modify.')), isTrue);
      expect(names.any((n) => n.startsWith('constraints.')), isTrue);
    });

    test('the UI suite covers paint, drag, snap and the app-level paths', () {
      final names = buildUiScenarios().map((s) => s.name).toSet();
      expect(names.any((n) => n.startsWith('ui.paint')), isTrue);
      expect(names, contains('ui.drag60'));
      expect(names, contains('ui.snapHover'));
      expect(names.any((n) => n.startsWith('app.pattern')), isTrue);
      expect(names.any((n) => n.startsWith('app.history')), isTrue);
      expect(names.any((n) => n.startsWith('app.scene')), isTrue);
    });

    test('every scenario name is unique across BOTH runners', () {
      // The two reports are read side by side and diffed on name. A collision
      // would silently overwrite one of them in any tool that merges them.
      final all = [
        ...buildScenarios().map((s) => s.name),
        ...buildUiScenarios().map((s) => s.name),
      ];
      expect(all.toSet().length, all.length);
    });

    test('every scenario carries an interpretable note', () {
      for (final s in [...buildScenarios(), ...buildUiScenarios()]) {
        expect(s.note.length, greaterThan(20),
            reason: '${s.name} has no note — a number nobody can interpret is '
                'not worth collecting');
      }
    });
  });

  group('the tool fixtures actually build geometry', () {
    // The whole point of tools.buildAll is per-tool cost. A tool that returns
    // null contributes a fast zero and looks like the cheapest thing in the
    // app, so the fixture has to be able to drive every one of them.
    test('every tool in toolMeta produces geometry from the fixture', () {
      // Driven through buildToolForPerf — the SAME entry point the scenario
      // uses. Reproducing the call here with its own points and parameters is
      // how a test ends up passing while the benchmark it guards measures
      // something else entirely.
      final existing = toolExistingFixture();
      final failed = <String>[];
      for (final t in toolMeta.keys) {
        final r = buildToolForPerf(t, existing);
        if (r == null || r.isEmpty) failed.add(t.name);
      }
      // Fillet and chamfer need two picks landing on two DIFFERENT existing
      // entities AND a radius that fits the corner between them; the generic
      // point generator cannot guarantee that against an arbitrary sketch, and
      // they have dedicated scenarios (tools.fillet2d / tools.chamfer2d) that
      // set it up properly. Everything else must build.
      //
      // The first run of this test earned its keep immediately: eqCurve
      // (parametric expression the parser does not accept), circleTangent
      // (three picks resolving to fewer than three distinct lines) and
      // slotOverall (width >= half the length) all returned null and were
      // being timed as if they were the fastest tools in the app.
      expect(failed.where((n) => n != 'fillet' && n != 'chamfer'), isEmpty,
          reason: 'these tools produced nothing, so their numbers in '
              'tools.buildAll would be measurements of an early return');
    });

    test('the corner fixture supports a real 2D fillet and chamfer', () {
      final gs = cornerFixture();
      expect(filletInventor(gs, const Offset(30, 2), const Offset(58, 30), 5),
          isNotNull,
          reason: 'tools.fillet2d would otherwise time a null');
      expect(
          chamferInventor(gs, const Offset(30, 2), const Offset(58, 30),
              mode: 0, d1: 5),
          isNotNull);
    });

    test('the cross fixture really crosses', () {
      // On parallel or disjoint lines trim/extend/split exit immediately, and
      // the whole modify sweep would measure the early exit.
      final gs = crossFixture(10);
      expect(gs.length, 20);
      final hits = intersectionsWithOthers(gs, 0);
      expect(hits.length, 10,
          reason: 'each horizontal line must meet all ten verticals');
    });

    test('trim on the cross fixture actually changes the geometry', () {
      final gs = crossFixture(10);
      final before = [for (final g in gs) g.data.toList()];
      final after = trimEntity(List.from(gs), 0, Offset(5, gs[0].data[1]));
      var changed = after.length != gs.length;
      for (var i = 0; i < after.length && !changed; i++) {
        if (after[i].data.toString() != before[i].toString()) changed = true;
      }
      expect(changed, isTrue,
          reason: 'a trim that changes nothing measured a no-op');
    });
  });

  group('the constraint sampler covers every type', () {
    test('every CType is either exercised or explicitly out of scope', () {
      // Pinned so that adding a constraint type cannot silently skip it: the
      // scenario counts unsupported types, but nothing would have FAILED.
      final scen = buildScenarios()
          .firstWhere((s) => s.name == 'constraints.addEachType');
      Perf.resetForTest();
      Perf.scenario(scen.name, scen.run);
      final skipped = Perf.counters.keys
          .where((k) => k.startsWith('constraints.unsupportedInFixture.'))
          .map((k) => k.split('.').last)
          .toSet();
      // `pattern` ties a copy to a source produced by the pattern tool; the
      // ring fixture has no patterned geometry, and app.pattern.* covers it.
      expect(skipped, {'pattern'},
          reason: 'a newly added constraint type must either be sampled here '
              'or be a deliberate, named exception');
      for (final t in CType.values) {
        if (skipped.contains(t.name)) continue;
        expect(Perf.stats.containsKey('constraints.add.${t.name}'), isTrue,
            reason: '${t.name} was never timed');
      }
    });
  });

  group('kernel coverage', () {
    test('every kernel op the shim exposes has a scenario', () {
      final names = buildKernelScenarios().map((s) => s.name).toList();
      if (!OcctFfi.available) {
        // On a host without the kernel the list is empty BY DESIGN — better an
        // empty section than scenarios reporting zeros for ops that never ran.
        expect(names, isEmpty);
        return;
      }
      for (final op in const [
        'extrude', 'revolve', 'sweep', 'loft', 'coil',
        'fillet', 'chamfer', 'boolean', 'unify', 'mesh',
        // M220 — mirror is occt_mirror (shim v17), which came in with M212's
        // pattern features. It belongs in THIS list rather than in a test of
        // its own: this list is the thing that fails when the next kernel
        // entry point arrives without a scenario, and that is the failure
        // worth having.
        'query', 'rayHits', 'transform', 'mirror',
      ]) {
        expect(names.any((n) => n.contains(op)), isTrue,
            reason: 'no scenario covers $op');
      }
    });

    test('the profile encodings are the ones the shim expects', () {
      // The trap this pins: pairs vs triplets. Handing the wrong one over does
      // not throw — the arity check returns null and the op reads as free.
      expect(polyProfile(12, 40).length, 24, reason: '(x,y) pairs');
      expect(arcRing(12, 40).length, 36, reason: '(x,y,bulge) triplets');
      expect(arcPath(24, 60).length, 72, reason: '(x,y,z) triplets');
      expect(identityMat34().length, 12);
      expect(holedProfile(48, 40, 4).length, 5, reason: 'outer + 4 holes');
    });

    test('the kernel scenarios really build solids, on a host that has one',
        () {
      if (!OcctFfi.available) return;
      Perf.resetForTest();
      final scen = buildKernelScenarios();
      for (final s in scen.where((s) =>
          s.name.startsWith('kernel.revolve') ||
          s.name.startsWith('kernel.sweep') ||
          s.name.startsWith('kernel.loft') ||
          s.name.startsWith('kernel.coil'))) {
        Perf.scenario(s.name, s.run);
      }
      // The failure counters are the point: a null return is a fast zero, and
      // these four ops are the ones whose profile encoding is easiest to get
      // wrong.
      final fails = Perf.counters.entries
          .where((e) => e.key.endsWith('.fail') || e.key.endsWith('.throw'))
          .toList();
      expect(fails, isEmpty,
          reason: 'these ops returned null or threw, so their scenarios timed '
              'nothing: ${fails.map((e) => '${e.key}=${e.value}').join(', ')}');
    });
  });

  group('M214 — the OS probe and the end-to-end rebuild', () {
    test('the native probe degrades to an empty map off-device', () {
      // On a host with no plugin the channel throws MissingPluginException.
      // Returning {} rather than propagating is what lets the bug bundle and
      // the suite call it unconditionally; a probe that can take down a bug
      // report is worse than no probe.
      expect(NativeMenu.perfProbe(), completion(isEmpty));
    });

    test('setNative namespaces by phase and mirrors the key gauges', () {
      Perf.resetForTest();
      Perf.setNative('preSuite', const {
        'thermalState': 'fair',
        'thermalOrdinal': 1,
        'footprintMB': 512,
        'availableMB': 2048,
      });
      Perf.setNative('postSuite', const {
        'thermalState': 'serious',
        'thermalOrdinal': 2,
        'footprintMB': 890,
        'availableMB': 1200,
      });
      // BOTH ends survive. This is the whole point: a thermal state that rose
      // across the run invalidates the numbers from its second half, and only
      // a before/after pair can show that.
      expect(Perf.native['preSuite.thermalState'], 'fair');
      expect(Perf.native['postSuite.thermalState'], 'serious');
      expect(Perf.gauges['native.thermal.preSuite'], 1);
      expect(Perf.gauges['native.thermal.postSuite'], 2);
      expect(Perf.gauges['native.footprintMB.postSuite'], 890);
    });

    test('an empty probe records nothing rather than empty keys', () {
      Perf.resetForTest();
      Perf.setNative('preSuite', const {});
      expect(Perf.native, isEmpty,
          reason: 'a host without the plugin must leave no trace, or every '
              'report grows a section of nulls');
    });

    test('the snapshot carries the native block only when it has one', () {
      Perf.resetForTest();
      expect(Perf.jsonSnapshot().containsKey('native'), isFalse);
      Perf.setNative('preSuite', const {'thermalOrdinal': 0});
      expect(Perf.jsonSnapshot()['native'], isNotNull);
    });

    test('the native reality drain is a safe no-op without a view', () async {
      // The 3D viewport registers a drain closure while mounted and clears it
      // on dispose. With no view registered the bundle must get an empty map,
      // not an exception and not a push into a dead channel — a diagnostic
      // that can take down a bug report is worse than no diagnostic.
      RealityPush.nativeDrain = null;
      expect(await RealityPush.drainNative(), isEmpty);
    });

    test('a throwing drain is swallowed, not propagated', () async {
      RealityPush.nativeDrain = () async => throw StateError('dead channel');
      expect(await RealityPush.drainNative(), isEmpty);
      RealityPush.nativeDrain = null;
    });

    test('the rebuild scenarios exist and are swept', () {
      final names = buildAppScenarios().map((s) => s.name).toSet();
      expect(names, containsAll(
          ['app.rebuildPart.1', 'app.rebuildPart.3', 'app.rebuildPart.6']));
    });

    testWidgets('a forced rebuild really recomputes every feature',
        (tester) async {
      if (!OcctFfi.available) return;
      Perf.resetForTest();
      final s = buildAppScenarios()
          .firstWhere((sc) => sc.name == 'app.rebuildPart.3');
      Perf.scenario(s.name, s.run);
      // Three features x three forced passes. Without `force` the build
      // signature would skip the second and third, and the scenario would be
      // timing a hash comparison.
      expect(Perf.stats['kernel.feature']?.count, 9,
          reason: 'a skipped feature measures the signature check, not a build');
      expect(Perf.stats.containsKey('part.rebuildAll'), isTrue);
      expect(Perf.counters['kernel.feature.fail'] ?? 0, 0,
          reason: 'a feature that fails to build produces no solid, and every '
              'number after it describes an empty part');
    });
  });

  group('M219 — ramps and quality', () {
    test('the ramps are in the AUTOMATIC suite, not opt-in', () {
      // The whole point: the shape of every curve, on every ordinary capture.
      final names = buildScenarios().map((s) => s.name).toSet();
      expect(names, containsAll([
        'ramp.solve.entities', 'ramp.analyze.entities', 'ramp.drag.entities',
        'ramp.solve.density',
      ]));
    });

    test('a ramp records EVERY rung, not just the endpoints', () {
      Perf.resetForTest();
      final r = buildScenarios()
          .firstWhere((s) => s.name == 'ramp.analyze.entities');
      Perf.scenario(r.name, r.run);
      final rungs = Perf.stats.keys.where((k) => RegExp(r'^ramp\.analyze\.\d+$')
          .hasMatch(k)).toList();
      expect(rungs.length, greaterThanOrEqualTo(6),
          reason: 'three points cannot show a knee — that is why these exist');
    });

    test('a ramp publishes the LOCAL exponent between rungs', () {
      Perf.resetForTest();
      final r = buildScenarios()
          .firstWhere((s) => s.name == 'ramp.analyze.entities');
      Perf.scenario(r.name, r.run);
      final ks = Perf.gauges.keys.where((k) => k.startsWith('ramp.analyze.k.'));
      expect(ks, isNotEmpty,
          reason: 'the local exponent is the whole point: a constant one is a '
              'clean power law, a jump is a threshold');
    });

    test('the density ramp varies constraints at a FIXED entity count', () {
      Perf.resetForTest();
      final r = buildScenarios()
          .firstWhere((s) => s.name == 'ramp.solve.density');
      Perf.scenario(r.name, r.run);
      final cons = {
        for (final e in Perf.gauges.entries)
          if (e.key.startsWith('ramp.density.cons.')) e.key: e.value
      };
      expect(cons.length, greaterThanOrEqualTo(3));
      expect(cons.values.toSet().length, cons.length,
          reason: 'each rung must really carry a different constraint count, '
              'or the ramp measures the same thing repeatedly');
    });

    test('the noise floor is measured and published', () {
      Perf.resetForTest();
      final q = buildScenarios().firstWhere((s) => s.name == 'quality.variance');
      Perf.scenario(q.name, q.run);
      // Without this every diff is uninterpretable: a 20% change means nothing
      // until you know whether 20% is inside the run-to-run spread.
      expect(Perf.gauges.containsKey('quality.variance.solve.iqrPct'), isTrue);
      expect(Perf.gauges.containsKey('quality.variance.solve.medianUs'), isTrue);
      expect(Perf.gauges['quality.variance.solve.medianUs'], greaterThan(0));
    });

    test('the frame-budget limits come out as entity counts', () {
      Perf.resetForTest();
      final q = buildScenarios()
          .firstWhere((s) => s.name == 'quality.frameBudget');
      Perf.scenario(q.name, q.run);
      final at120 = Perf.gauges['quality.budget.entitiesAt120Hz'] ?? 0;
      final at60 = Perf.gauges['quality.budget.entitiesAt60Hz'] ?? 0;
      expect(at60, greaterThanOrEqualTo(at120),
          reason: 'a 60 Hz frame is twice as long, so it must fit at least as '
              'much as a 120 Hz one — if not, the ladder is misreading');
    });

    test('cache effectiveness is a RATIO, so it survives a chip change', () {
      Perf.resetForTest();
      final q = buildScenarios().firstWhere((s) => s.name == 'quality.caches');
      Perf.scenario(q.name, q.run);
      expect(Perf.gauges.containsKey('quality.cache.gearSpeedup'), isTrue);
      expect(Perf.gauges['quality.cache.gearSpeedup'], greaterThan(1),
          reason: 'a memo that is not faster than recomputing is not a memo');
    });
  });

  group('M218 — the stress tier', () {
    test('it is NOT part of the ordinary suites', () {
      // The whole point of the opt-in. Its ladders climb until they blow a
      // time budget, and one of them deliberately drives the operation that
      // already killed the app once. Firing that from an ordinary bug report
      // would make the app look broken while diagnosing it.
      final ordinary = [
        ...buildScenarios().map((s) => s.name),
        ...buildUiScenarios().map((s) => s.name),
      ];
      expect(ordinary.where((n) => n.startsWith('stress.')), isEmpty);
    });

    test('every stress scenario is named and explained', () {
      for (final s in buildStressScenarios()) {
        expect(s.name, startsWith('stress.'));
        expect(s.note.length, greaterThan(20));
      }
    });

    test('the 2D ladders exist even without a kernel', () {
      // The kernel ladders are skipped on a host with no OCCT, but the sketch
      // ones must not be — otherwise the tier reports nothing at all on CI and
      // a break in it would go unnoticed until a device run.
      final names = buildStressScenarios().map((s) => s.name).toSet();
      expect(names, containsAll(
          ['stress.sketch.analyze', 'stress.sketch.solve', 'stress.sketch.drag']));
    });

    test('a ladder reports the rung it reached, even when it stops early', () {
      Perf.resetForTest();
      final s = buildStressScenarios()
          .firstWhere((sc) => sc.name == 'stress.sketch.analyze');
      Perf.scenario(s.name, s.run);
      // maxSize is the RESULT of this tier, not a side effect: a ladder that
      // stopped early has measured the wall, and the wall is the answer.
      expect(Perf.gauges.containsKey('stress.analyze.maxSize'), isTrue);
      expect(Perf.gauges['stress.analyze.maxSize'], greaterThan(0),
          reason: 'a ladder that cleared no rung at all measured nothing');
    }, timeout: const Timeout(Duration(minutes: 5)));
  });

  group('the app fixtures are real', () {
    testWidgets('the pattern scenarios produce copies', (tester) async {
      Perf.resetForTest();
      resetAppFixturesForTest();
      final s = buildAppScenarios()
          .firstWhere((sc) => sc.name == 'app.pattern.rect.16');
      Perf.scenario(s.name, s.run);
      expect(Perf.gauges['app.patternCopies'] ?? 0, greaterThan(0),
          reason: 'a pattern preview producing no copies measured an early '
              'return, not a pattern');
    });

    testWidgets('the history scenario really snapshots', (tester) async {
      Perf.resetForTest();
      final s =
          buildAppScenarios().firstWhere((sc) => sc.name == 'app.history.24');
      Perf.scenario(s.name, s.run);
      expect(Perf.stats['app.checkpoint']?.count, 20);
      expect(Perf.stats['app.undoStep']?.count, 20,
          reason: 'undo must have something to step back through — a journal '
              'that collapsed every snapshot as identical measured the '
              'comparison instead');
    });

    testWidgets('the scene payload scenario runs on real geometry',
        (tester) async {
      if (!OcctFfi.available) return;
      Perf.resetForTest();
      resetAppFixturesForTest();
      final s =
          buildAppScenarios().firstWhere((sc) => sc.name == 'app.scene.3x48');
      Perf.scenario(s.name, s.run);
      expect(Perf.gauges['app.scene.tris'] ?? 0, greaterThan(100),
          reason: 'a stub mesh would make every scene number meaningless');
      expect(Perf.stats.containsKey('app.buildScenePayload'), isTrue);
      expect(Perf.stats['app.sceneSignature']?.count, 60);
    });
  });

  // M220 — the paths that arrived with M212/M213 and reached this branch
  // unmeasured. Same discipline as everything above: these tests do not look
  // at timings, they check that the scenario reached the thing it claims to
  // measure. Face provenance is especially prone to the silent-nothing
  // failure, because faceSurfaces returns an EMPTY LIST rather than throwing
  // when a mesh arrives without faceInfos — a fixture built against an older
  // shim would report every provenance scenario as instant and correct.
  group('M220 — provenance, part patterns and the new kernel entry', () {
    test('the new scenarios are wired into the suite at all', () {
      final names = buildAppScenarios().map((s) => s.name).toSet();
      expect(names.any((n) => n.startsWith('app.provenance.faceSurfaces')),
          isTrue);
      expect(
          names.any((n) => n.startsWith('app.provenance.newSurfaces')), isTrue);
      expect(names.any((n) => n.startsWith('app.provenance.attribute')), isTrue);
      expect(names.any((n) => n.startsWith('app.pattern.occurrences')), isTrue);
      expect(names, contains('app.pattern.occurrences.curve'));

      // The kernel list is empty by design on a host without OCCT (see
      // 'kernel coverage' above), so the sweep can only be asserted where a
      // kernel exists.
      if (!OcctFfi.available) return;
      final kernel = buildKernelScenarios().map((s) => s.name).toSet();
      expect(
          kernel.any((n) => n.startsWith('kernel.query.edgeInfoScale')), isTrue);
      expect(kernel.any((n) => n.startsWith('kernel.mirror')), isTrue);
    });

    testWidgets('faceSurfaces really decomposes a mesh', (tester) async {
      if (!OcctFfi.available) return;
      Perf.resetForTest();
      resetAppFixturesForTest();
      final s = buildAppScenarios()
          .firstWhere((sc) => sc.name == 'app.provenance.faceSurfaces.120');
      Perf.scenario(s.name, s.run);
      expect(Perf.gauges['provenance.faceSurfaces.out.120'] ?? 0, greaterThan(0),
          reason: 'faceSurfaces returned nothing — a mesh without faceInfos '
              'exits on its first line, so the whole provenance section would '
              'be timing an early return');
      expect(Perf.stats['provenance.faceSurfaces']?.count, 10);
    });

    testWidgets('newSurfacesOf compares two real surface sets', (tester) async {
      if (!OcctFfi.available) return;
      Perf.resetForTest();
      resetAppFixturesForTest();
      final s = buildAppScenarios()
          .firstWhere((sc) => sc.name == 'app.provenance.newSurfaces.120');
      Perf.scenario(s.name, s.run);
      // The INPUT is what matters here: newSurfacesOf legitimately returns an
      // empty list when every surface already exists in the base, so an empty
      // OUTPUT is not proof of failure — an empty input is.
      expect(Perf.gauges['provenance.newSurfaces.in.120'] ?? 0, greaterThan(0),
          reason: 'nothing to compare means the quadratic being hunted here '
              'never ran');
      expect(Perf.stats['provenance.newSurfaces']?.count, 10);
    });

    testWidgets('attributeFaces actually attributes', (tester) async {
      if (!OcctFfi.available) return;
      Perf.resetForTest();
      resetAppFixturesForTest();
      final s = buildAppScenarios()
          .firstWhere((sc) => sc.name == 'app.provenance.attribute.6');
      Perf.scenario(s.name, s.run);
      expect(Perf.gauges['provenance.attribute.out.6'] ?? 0, greaterThan(0),
          reason: 'the triple loop matched no face to any feature, so this '
              'measured the loop skipping rather than the loop working — the '
              'fixture must populate ownSurfaces');
      expect(Perf.gauges['provenance.attribute.features.6'], 6);
    });

    test('patternOccurrences produces the requested count', () {
      Perf.resetForTest();
      final s = buildAppScenarios()
          .firstWhere((sc) => sc.name == 'app.pattern.occurrences.16');
      Perf.scenario(s.name, s.run);
      // FIFTEEN, not sixteen. patternOccurrences drops the occurrence whose
      // placement is the identity (part_model.dart:3370) — that one IS the
      // original feature, and re-adding it would double the material. So a
      // count of n yields n-1 placements, and pinning the exact number is
      // what would catch the off-by-one if that rule ever changed.
      expect(Perf.gauges['pattern.occurrences.out.16'], 15,
          reason: 'a pattern that yields fewer placements than count-1 is '
              'measuring a refusal, not a pattern');
    });

    test('every pattern KIND has a scenario', () {
      // patternOccurrences switches on the kind, so each is separate code.
      // This is the list that fails when a fifth kind is added without a
      // measurement — the same job the kernel-op list does one group above.
      final names = buildAppScenarios().map((s) => s.name).toSet();
      for (final kind in const ['', 'circular.', 'points.', 'mirror']) {
        expect(
            names.any((n) => n.startsWith('app.pattern.occurrences.$kind')),
            isTrue,
            reason: 'no scenario covers the "$kind" pattern kind');
      }
    });

    test('the circular kind rotates rather than returning nothing', () {
      Perf.resetForTest();
      final s = buildAppScenarios()
          .firstWhere((sc) => sc.name == 'app.pattern.occurrences.circular.16');
      Perf.scenario(s.name, s.run);
      // Circular starts its loop at i=1, so a count of n gives n-1 — the same
      // "the original is not a copy" rule as the rectangular kind, reached by
      // different code. An invalid axis returns const [] instead of throwing,
      // which is the silent nothing this pins.
      expect(Perf.gauges['pattern.occurrences.circular.out.16'], 15);
    });

    test('the sketch-driven kind reads its points and places them', () {
      Perf.resetForTest();
      final s = buildAppScenarios()
          .firstWhere((sc) => sc.name == 'app.pattern.occurrences.points.16');
      Perf.scenario(s.name, s.run);
      // Both halves must be non-zero: sketchPatternPoints skips any geometry
      // that is not a pointTag-carrying circle, so a fixture built with plain
      // circles would hand an empty list to patternOccurrences and BOTH would
      // read as free.
      expect(Perf.gauges['pattern.sketchPoints.out.16'], 16,
          reason: 'the driving sketch produced no points — the fixture built '
              'geometry that sketchPatternPoints does not recognise');
      expect(Perf.gauges['pattern.occurrences.points.out.16'] ?? 0,
          greaterThan(0));
    });

    test('the mirror kind yields exactly one occurrence', () {
      Perf.resetForTest();
      final s = buildAppScenarios()
          .firstWhere((sc) => sc.name == 'app.pattern.occurrences.mirror');
      Perf.scenario(s.name, s.run);
      // Exactly one, by construction. Pinned because the scenario's whole
      // claim is that this kind is CONSTANT — if it ever starts scaling, the
      // note in the report ("the cost is entirely in the kernel") becomes a
      // lie and this test is what catches it.
      expect(Perf.gauges['pattern.occurrences.mirror.out'], 1);
    });

    test('the along-a-curve row walks the path', () {
      Perf.resetForTest();
      final s = buildAppScenarios()
          .firstWhere((sc) => sc.name == 'app.pattern.occurrences.curve');
      Perf.scenario(s.name, s.run);
      expect(Perf.gauges['pattern.occurrences.curve.pathPts'], 120);
      expect(Perf.gauges['pattern.occurrences.curve.out'] ?? 0, greaterThan(1),
          reason: 'the curve distribution fell back to a single occurrence, '
              'which is the straight case wearing a curve fixture');
    });

    testWidgets('the edgeInfo scale rungs really build their solids',
        (tester) async {
      if (!OcctFfi.available) return;
      Perf.resetForTest();
      final s = buildKernelScenarios()
          .firstWhere((sc) => sc.name == 'kernel.query.edgeInfoScale.120');
      Perf.scenario(s.name, s.run);
      expect(Perf.gauges['kernel.edgeInfoScale.edges.120'] ?? 0, greaterThan(0),
          reason: 'no solid means no traversal to measure, and the sweep that '
              'is supposed to prove the O(n^2) mechanism proves nothing');
      expect(Perf.stats['kernel.edgeInfoScale.120']?.count, 20);
    });

    testWidgets('the mirror scenario mirrors and does not silently fail',
        (tester) async {
      if (!OcctFfi.available) return;
      Perf.resetForTest();
      // The FFI spans are hooks that do NOTHING until main() installs them
      // (see ffi/perf_hook.dart), so asserting on ffi.occt.* without this
      // would be asserting on a no-op: the test would pass on a build where
      // the wrapper had been deleted. Installed here and torn down after, so
      // one test's recorder cannot leak into the next test's numbers.
      installFfiPerfHooks(span: Perf.span, count: Perf.count);
      try {
        final s = buildKernelScenarios()
            .firstWhere((sc) => sc.name == 'kernel.mirror.24');
        Perf.scenario(s.name, s.run);
        expect(Perf.stats['ffi.occt.mirror']?.count, 10,
            reason: 'occt_mirror arrived with M212 uninstrumented and was '
                'wrapped during the merge; a missing span means the wrapper '
                'was lost again');
        // Its control, measured in the same scenario on the same solid — the
        // comparison is the whole point, so a missing control is a broken
        // scenario even though the mirror numbers would look fine.
        expect(Perf.stats['ffi.occt.transform']?.count, 10);
        // The guard counter must be EMPTY. A shim older than v17 has no
        // occt_mirror, mirrored() returns null, and ten fast nulls would read
        // as the cheapest kernel operation in the whole report.
        expect(Perf.counters['kernel.mirror.fail'] ?? 0, 0,
            reason: 'the mirror returned null — its timing is meaningless');
      } finally {
        resetFfiPerfHooks();
      }
    });
  });
}
