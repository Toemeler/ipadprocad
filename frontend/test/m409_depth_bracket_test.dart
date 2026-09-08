// M409 — #30: "if i zoom far in on windows part of the solid gets cut away
// from the view on windows."
//
// The shaded viewport off iOS is flutter_scene, and its projection is
// orthographic with a LINEAR depth buffer, so the near/far bracket is sized to
// the scene rather than left wide open (OrthographicProjection.near says why:
// a million-millimetre range is coarser than the edge ribbons and they
// speckle). The bracket is `max(sceneRadius, halfH) + 10`, four times back and
// two either side — and it is correct exactly as long as `sceneRadius` is.
//
// It was not. The radius was re-measured from every scene payload, but a scene
// push OMITS the geometry of a solid whose mesh has not changed, so the first
// push measured the part and every push after it measured nothing at all. The
// radius fell to its floor and `pad` then followed the ZOOM alone: wide open
// zoomed out, and a slab a few tens of millimetres thick zoomed in. The part in
// the report reaches 466 mm from the origin, so the near plane walked into it
// and cut it in half — which is the report, exactly, including why it only
// shows when you zoom far in.
//
// The numbers below are that part's: bbox 0,-8,-310 .. 50,344,0.
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_view/gpu_view.dart';

/// The reported part's reach from the world origin: the far corner of its box.
const double _partRadius = 465.8;

/// True when a point [d] mm from the origin along the view direction is inside
/// the slab. The eye sits `dist` back and looks at the origin plane, so a
/// world point at +d (toward the camera) is at view depth `dist - d`.
bool _visible(({double dist, double near, double far}) b, double d) {
  final z = b.dist - d;
  return z >= b.near && z <= b.far;
}

void main() {
  group('THE REPORT: the bracket has to hold the part at every zoom', () {
    for (final halfH in [0.5, 2.0, 10.0, 50.0, 200.0, 1000.0]) {
      test('halfH = $halfH', () {
        final b = orthoDepthBracket(radius: _partRadius, halfH: halfH);
        for (final d in [_partRadius, -_partRadius, 0.0]) {
          expect(_visible(b, d), isTrue,
              reason: 'a point $d mm along the view was clipped at halfH '
                  '$halfH: near ${b.near}, far ${b.far}, eye ${b.dist}');
        }
      });
    }

    test('and a radius that has collapsed does NOT hold it — the bug', () {
      // Kept as the counter-example, so the test above is known to be testing
      // something: with the radius lost, zooming in really does clip.
      final b = orthoDepthBracket(radius: 1, halfH: 10);
      expect(_visible(b, _partRadius), isFalse);
    });

    test('zoomed out, the collapsed radius still looked fine', () {
      // Which is why the report says "if i zoom far in" and not "always".
      final b = orthoDepthBracket(radius: 1, halfH: 1000);
      expect(_visible(b, _partRadius), isTrue);
    });
  });

  group('the reach survives a push that omits geometry', () {
    test('a solid measured once keeps its reach', () {
      final e = SceneExtent();
      e.measure('Solid1', _partRadius);
      expect(e.radius, closeTo(_partRadius, 1e-9));
      // The second scene push: same mesh, so no positions travel and nothing
      // is measured. This is the moment the radius used to collapse.
      e.placeAt('Solid1', 0);
      expect(e.radius, closeTo(_partRadius, 1e-9),
          reason: 'a payload that says nothing about geometry must say '
              'nothing about the depth bracket');
    });

    test('a solid that leaves the scene stops counting', () {
      final e = SceneExtent();
      e.measure('Solid1', _partRadius);
      e.measure('Solid2', 12);
      e.forget('Solid1');
      expect(e.radius, closeTo(12, 1e-9));
    });

    test('a re-measured solid shrinks as well as grows', () {
      // Rolling the End of Part marker back to one small feature has to give
      // the tight bracket back, or the edges speckle for the rest of the
      // session.
      final e = SceneExtent();
      e.measure('Solid1', _partRadius);
      e.measure('Solid1', 20);
      expect(e.radius, closeTo(20, 1e-9));
    });

    test('a placed component reaches its own radius plus its offset', () {
      // An assembly component's buffers are in its source part's frame, so the
      // world reach is the two added — otherwise a component 2 m out is
      // bracketed as though it sat on the origin.
      final e = SceneExtent();
      e.measure('Bracket:1', 30);
      e.placeAt('Bracket:1', 2000);
      expect(e.radius, closeTo(2030, 1e-9));
    });

    test('an empty scene keeps the 50 mm default, a small part its own', () {
      expect(SceneExtent().radius, 50);
      final e = SceneExtent()..measure('Solid1', 4);
      expect(e.radius, 4, reason: 'a small part keeps a tight bracket');
      final tiny = SceneExtent()..measure('Solid1', 0.2);
      expect(tiny.radius, 1, reason: 'and 1 mm is the floor under that');
    });
  });

  test('the slab is centred on the origin plane, four pads deep', () {
    // The shape the arithmetic promises, pinned so a future tightening cannot
    // quietly move the centre off the origin plane — the camera has no
    // component along the view direction, so that is where the scene is.
    final b = orthoDepthBracket(radius: 100, halfH: 10);
    expect(b.far - b.near, closeTo(4 * 110, 1e-9));
    expect(b.dist - b.near, closeTo(b.far - b.dist, 1e-9));
  });
}
