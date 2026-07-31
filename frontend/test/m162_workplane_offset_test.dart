// M162 — a work plane's offset distance is a number you can change.
//
// `AppState.workPlaneOffset` is initialised to 10 and was never assigned from
// anywhere in the app, so EVERY offset work plane in every saved document sits
// exactly 10 mm from its base. The user's own Part4.part.json says so:
//   "kind":"offset","def":"Offset 10.00 mm from face"
//
// The distance was also baked into the resulting frame at creation and then
// discarded, so even with a way to type it, an existing plane could not be
// moved. WorkPlane now records the base frame and the distance, which makes
// re-offsetting possible and keeps the file honest about how the plane was
// built.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/part_model.dart';

WorkPlane _offsetFrom(PlaneFrame base, double d) => WorkPlane(
    'Work Plane1', 1, WorkPlaneKind.offset,
    'Offset ${d.toStringAsFixed(2)} mm from XY', offsetPlaneFrame(base, d),
    base: base, offset: d);

void main() {
  group('M162 — the offset is editable', () {
    test('re-offsetting moves the plane along its base normal', () {
      final base = planeFrame('xy');
      final wp = _offsetFrom(base, 10);
      expect(wp.offsetEditable, isTrue);

      expect(wp.setOffset(25), isTrue);
      expect(wp.offset, 25);
      final moved = wp.frame.origin - base.origin;
      expect(moved.x, closeTo(base.n.x * 25, 1e-9));
      expect(moved.y, closeTo(base.n.y * 25, 1e-9));
      expect(moved.z, closeTo(base.n.z * 25, 1e-9));
    });

    test('it measures from the BASE every time, never from itself', () {
      // The trap: offsetting the current frame again would compound, so
      // 10 -> 25 -> 10 would not come home.
      final base = planeFrame('xz');
      final wp = _offsetFrom(base, 10);
      wp.setOffset(25);
      wp.setOffset(10);
      final back = offsetPlaneFrame(base, 10);
      expect(wp.frame.origin.x, closeTo(back.origin.x, 1e-9));
      expect(wp.frame.origin.y, closeTo(back.origin.y, 1e-9));
      expect(wp.frame.origin.z, closeTo(back.origin.z, 1e-9));
    });

    test('a negative offset goes the other way', () {
      final base = planeFrame('xy');
      final wp = _offsetFrom(base, 10);
      wp.setOffset(-4);
      final moved = wp.frame.origin - base.origin;
      expect(moved.z, closeTo(base.n.z * -4, 1e-9));
    });

    test('the axes are inherited, so a sketch on it is not rotated', () {
      final base = planeFrame('yz');
      final wp = _offsetFrom(base, 3)..setOffset(12);
      expect(wp.frame.u.x, closeTo(base.u.x, 1e-12));
      expect(wp.frame.v.y, closeTo(base.v.y, 1e-12));
      expect(wp.frame.n.z, closeTo(base.n.z, 1e-12));
    });

    test('the description follows the value and keeps naming its source', () {
      final wp = _offsetFrom(planeFrame('xy'), 10);
      expect(wp.def, 'Offset 10.00 mm from XY');
      wp.setOffset(2.5);
      expect(wp.def, 'Offset 2.50 mm from XY');
    });

    test('a non-finite distance is refused, not applied', () {
      final wp = _offsetFrom(planeFrame('xy'), 10);
      expect(wp.setOffset(double.nan), isFalse);
      expect(wp.setOffset(double.infinity), isFalse);
      expect(wp.offset, 10, reason: 'unchanged');
    });

    test('a MIDPLANE has no base and is not re-offsettable', () {
      final wp = WorkPlane('Work Plane2', 2, WorkPlaneKind.midplane,
          'Midplane between face and face', planeFrame('xy'));
      expect(wp.offsetEditable, isFalse);
      expect(wp.setOffset(5), isFalse);
    });
  });

  group('M162 — persistence', () {
    test('base and distance round-trip', () {
      final wp = _offsetFrom(planeFrame('xz'), 7.5);
      final back = WorkPlane.fromJson(wp.toJson())!;
      expect(back.offset, 7.5);
      expect(back.offsetEditable, isTrue);
      expect(back.frame.origin.y, closeTo(wp.frame.origin.y, 1e-12));
      // and it is still editable after the round trip
      expect(back.setOffset(1), isTrue);
      expect(back.frame.origin.y, closeTo(planeFrame('xz').n.y * 1, 1e-9));
    });

    test('a midplane writes no base, so its file is unchanged', () {
      final wp = WorkPlane('Work Plane2', 2, WorkPlaneKind.midplane, 'Midplane',
          planeFrame('xy'));
      final j = wp.toJson();
      expect(j.containsKey('bo'), isFalse);
      expect(j.containsKey('d'), isFalse);
    });

    test('a pre-M162 document loads, keeps its frame, and is not editable', () {
      // Exactly the shape in the user's Part4.part.json.
      final back = WorkPlane.fromJson({
        'name': 'Work Plane1',
        'seq': 2,
        'kind': 'offset',
        'def': 'Offset 10.00 mm from face',
        'visible': true,
        'o': [15.0, 0.0, 0.0],
        'u': [0.0, 0.0, -1.0],
        'v': [0.0, 1.0, 0.0],
        'n': [1.0, 0.0, 0.0],
      })!;
      expect(back.frame.origin.x, 15.0, reason: 'the saved plane is honoured');
      expect(back.offsetEditable, isFalse,
          reason: 'no base was recorded, so there is nothing to re-offset '
              'from — better than inventing one');
      expect(back.toJson().containsKey('bo'), isFalse);
    });

    test('a corrupt entry still returns null rather than throwing', () {
      expect(WorkPlane.fromJson({'name': 'x'}), isNull);
    });
  });
}
