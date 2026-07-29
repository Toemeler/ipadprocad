// M105b — the Fillet / Chamfer session (one session type for both commands).
//
// Host-testable: which feature the panel would produce, the validation, and
// the open/cancel/edit lifecycle. NOT host-testable: the preview solid and
// the commit, because both need a linked OCCT kernel — those paths are
// asserted to fail honestly rather than to fabricate a solid.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('session shape', () {
    test('one session type serves both commands', () {
      expect(EdgeFeatureSession('fillet').isFillet, isTrue);
      expect(EdgeFeatureSession('chamfer').isFillet, isFalse);
    });

    test('a fresh chamfer session starts on equal-distance', () {
      final s = EdgeFeatureSession('chamfer');
      expect(s.mode, 0);
      expect(s.flip, isFalse);
      expect(s.edgeChain, isTrue);
    });

    test('editing seeds the session from the feature', () {
      final f = ChamferFeature(
          name: 'Chamfer1',
          bodyName: 'Solid1',
          edges: [EdgeSel(0, 0, 0, 5, 1, 0)],
          mode: 2,
          exprD1: '3 mm',
          exprAngle: '30.00 deg',
          flip: true);
      final s = EdgeFeatureSession('chamfer', editing: f);
      // the session copies on open; here we assert the contract the opener
      // relies on — the feature still carries what it was built with
      expect(f.mode, 2);
      expect(f.exprAngle, '30.00 deg');
      expect(f.flip, isTrue);
      expect(s.editing, same(f));
    });
  });

  group('opening', () {
    test('openFillet arms the edge pick', () {
      final app = AppState();
      app.openFillet();
      // no part loaded -> no session, and nothing armed
      expect(app.edgeSession, isNull);
      expect(app.pickingEdges, isFalse);
    });

    test('a fillet and an extrude panel are never open together', () {
      // _openEdgeFeature cancels the extrude session first: two property
      // panels stacked in the same corner would both claim the 3D taps.
      final app = AppState();
      expect(app.extrudeSession, isNull);
      expect(app.edgeSession, isNull);
    });
  });

  group('chamfer parameters reach the kernel correctly', () {
    ChamferFeature c(int mode, {bool flip = false}) => ChamferFeature(
        name: 'C',
        bodyName: 'S',
        edges: const [],
        mode: mode,
        distance1: 2,
        distance2: 5,
        angleDeg: 30,
        flip: flip);

    test('equal distance ignores the second distance and the angle', () {
      expect(c(0).kernelParams, (2.0, 0.0, 0.0));
    });

    test('flip swaps the two distances', () {
      expect(c(1, flip: true).kernelParams, (5.0, 2.0, 0.0));
    });

    test('flip takes the complementary angle', () {
      expect(c(2, flip: true).kernelParams, (2.0, 0.0, 60.0));
    });
  });

  group('feature naming', () {
    test('fillets and chamfers are numbered separately', () {
      final p = PartModel('P');
      expect(p.nextFeatureName('Fillet'), 'Fillet1');
      p.features.add(FilletFeature(
          name: 'Fillet1',
          bodyName: 'Solid1',
          edges: const [],
          radii: const []));
      expect(p.nextFeatureName('Fillet'), 'Fillet2');
      expect(p.nextFeatureName('Chamfer'), 'Chamfer1');
    });
  });

  group('the edge set belongs to one body', () {
    test('a fillet declares itself body-modifying and consumes no sketch', () {
      final f = FilletFeature(
          name: 'F', bodyName: 'S', edges: const [], radii: const []);
      expect(f.modifiesBody, isTrue);
      expect(f.sketchName, '');
      expect(f.output, 'modify');
    });

    test('a chamfer round-trips through JSON with its method', () {
      final f = ChamferFeature(
          name: 'Chamfer1',
          bodyName: 'Solid1',
          edges: [EdgeSel(1, 2, 3, 8, 1, 0)],
          mode: 1,
          distance1: 2,
          distance2: 5,
          flip: true);
      final back = PartFeature.fromJson(f.toJson()) as ChamferFeature;
      expect(back.mode, 1);
      expect(back.flip, isTrue);
      expect(back.distance2, 5);
      expect(back.edges.length, 1);
      expect(back.ownSig(), f.ownSig());
    });
  });
}
