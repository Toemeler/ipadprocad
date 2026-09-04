// M382 — a per-move push updates what a plane is DOING, never what it IS.
//
// The bug this pins: `setOverlays` handed the light payload straight to
// `_rebuildDecor`, which clears the decor and rebuilds it. The light payload
// carries `key`, `visible` and `hot` and no geometry, so every plane came back
// null for want of a `frame`, every axis for want of a `dir`, and `sketches`
// was not in the payload at all. On a touch screen it never showed; on a
// desktop the first mouse movement erased the origin planes, the axes and
// every sketch, and only a full scene push brought them back.
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_view/gpu_view.dart';

Map<String, dynamic> _full() => <String, dynamic>{
      'planes': [
        {
          'key': 'xy',
          'frame': [1, 0, 0, 0, 1, 0, 0, 0, 1],
          'origin': [0, 0, 0],
          'ext': 25.0,
          'visible': true,
          'hot': false,
        },
        {
          'key': 'yz',
          'frame': [0, 1, 0, 0, 0, 1, 1, 0, 0],
          'origin': [0, 0, 0],
          'ext': 25.0,
          'visible': false,
          'hot': false,
        },
      ],
      'axes': [
        {'key': 'x', 'dir': [1, 0, 0], 'lo': -25, 'hi': 25, 'visible': true},
      ],
      'sketches': [
        {'id': 'S1', 'lines': [], 'frame': [1, 0, 0, 0, 1, 0, 0, 0, 1]},
      ],
    };

/// The shape buildOverlaysPayload really sends: state, and nothing else.
Map<String, dynamic> _light({bool xyVisible = true, String? hot}) =>
    <String, dynamic>{
      'planes': [
        {'key': 'xy', 'visible': xyVisible, 'hot': hot == 'xy'},
        {'key': 'yz', 'visible': false, 'hot': hot == 'yz'},
      ],
      'axes': [
        {'key': 'x', 'visible': true, 'hot': hot == 'x'},
      ],
      'cp': {'visible': false, 'hot': false},
    };

void main() {
  group('a per-move push keeps the geometry', () {
    test('the frame and the origin survive a light push', () {
      final m = mergeDecorPayload(_full(), _light());
      final xy = (m['planes'] as List).first as Map;
      // Without this the plane is not drawn at all — _plane returns null the
      // moment `frame` is missing, which is exactly what used to happen.
      expect(xy['frame'], [1, 0, 0, 0, 1, 0, 0, 0, 1]);
      expect(xy['origin'], [0, 0, 0]);
      expect(xy['ext'], 25.0);
    });

    test('the light push wins on visible and hot', () {
      final m = mergeDecorPayload(_full(), _light(xyVisible: false, hot: 'yz'));
      final planes = (m['planes'] as List).cast<Map>();
      expect(planes.firstWhere((p) => p['key'] == 'xy')['visible'], isFalse);
      expect(planes.firstWhere((p) => p['key'] == 'yz')['hot'], isTrue);
      expect(planes.firstWhere((p) => p['key'] == 'xy')['hot'], isFalse);
    });

    test('an axis keeps its direction', () {
      final m = mergeDecorPayload(_full(), _light(hot: 'x'));
      final x = (m['axes'] as List).first as Map;
      expect(x['dir'], [1, 0, 0]);
      expect(x['hot'], isTrue);
    });

    test('a list the light push does not mention is kept whole', () {
      // buildOverlaysPayload sends no `sketches` at all. Rebuilding from it
      // used to empty them.
      final m = mergeDecorPayload(_full(), _light());
      expect((m['sketches'] as List), hasLength(1));
      expect(((m['sketches'] as List).first as Map)['id'], 'S1');
    });

    test('an entry only the light push names is dropped', () {
      // It has no frame, so there is nothing to draw; inventing one would be
      // worse than leaving it out.
      final light = _light();
      (light['planes'] as List).add({'key': 'ghost', 'visible': true});
      final m = mergeDecorPayload(_full(), light);
      expect((m['planes'] as List).map((p) => (p as Map)['key']),
          ['xy', 'yz']);
    });

    test('merging twice is the same as merging once', () {
      // The light push arrives on every pointer move; it must not accumulate.
      final once = mergeDecorPayload(_full(), _light(hot: 'xy'));
      final twice = mergeDecorPayload(once, _light(hot: 'xy'));
      expect(twice.toString(), once.toString());
    });

    test('nothing remembered yet is not a crash', () {
      // setOverlays can arrive before the first scene push.
      final m = mergeDecorPayload(const <String, dynamic>{}, _light());
      expect((m['planes'] as List), isEmpty);
      expect((m['axes'] as List), isEmpty);
      expect((m['sketches'] as List), isEmpty);
    });
  });
}
