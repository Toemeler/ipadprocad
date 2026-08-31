// M293 — the stripes across every rendered surface.
//
// Reported with a screenshot: fine, evenly spaced parallel lines running
// across a filleted corner in RENDERED mode — over the curved fillet and the
// flat top alike, at a constant angle and a constant spacing that follows
// neither.
//
// That pattern is shadow-map acne. It follows the shadow map's own projection
// rather than the surface, which is how it is told apart from tessellation
// banding (which follows the surface parameterisation and would converge on a
// fillet).
//
// The cause is one expression in RealityPartView.applyLighting:
//
//     let depthBias = min(1.0, maximumDistance * 0.001)
//
// `DirectionalLightComponent.Shadow.depthBias` has NO UNIT. RealityKit's
// default is 1.0 for every scene at every scale — which is itself the proof
// that it is not metres and not millimetres. Two milestones have now scaled it
// by a distance anyway: M277 read the previous `max(1.0, reach * 0.02)` as
// "floors at 1 mm" and replaced it with "cap it under 1 mm". On the part in the
// report that arithmetic lands at 0.22, roughly a fifth of the default, and it
// shrinks further the closer you zoom.
//
// M277's own complaint was real and is kept: `max(1.0, reach * 0.02)` GROWS
// with the scene — 4.0 at reach 200, 10.0 at reach 500 — and a bias several
// times the default is what pushed the contact shadow out from under the
// model. The bug was the growth, not the floor. The fix is the constant both
// expressions were reaching for from opposite sides.
//
// WHY THIS TEST IS A GREP. The renderer is Swift, there is no Swift toolchain
// in this repository's test environment, and the artefact is a picture. What
// CAN be pinned from Dart is the property that was violated: the bias is not
// computed from a length. That is the whole class of bug — it has now happened
// twice, in opposite directions — so it is the thing worth guarding, and a
// grep guards it exactly.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The renderer, from the package the app depends on by path.
File get _renderer =>
    File('packages/reality_view/ios/Classes/RealityPartView.swift');

/// The body of `applyLighting`, which is where the shadow is configured.
String _applyLighting(String src) {
  final start = src.indexOf('private func applyLighting()');
  expect(start, greaterThan(0),
      reason: 'applyLighting was renamed; this test has to follow it');
  final end = src.indexOf('\n    }', start);
  expect(end, greaterThan(start));
  return src.substring(start, end);
}

void main() {
  test('the renderer is where this test thinks it is', () {
    expect(_renderer.existsSync(), isTrue,
        reason: 'the Swift renderer moved; ${_renderer.path} is gone');
  });

  test('the shadow depth bias is a constant, not a distance', () {
    final body = _applyLighting(_renderer.readAsStringSync());
    final line = body
        .split('\n')
        .firstWhere((l) => l.contains('depthBias') && l.contains('let'),
            orElse: () => '');
    expect(line, isNotEmpty, reason: 'no depthBias is set at all any more');

    // The specific defect, both times it has happened: the bias multiplied by
    // something measured in the scene's units.
    for (final length in const [
      'maximumDistance',
      'reach',
      'sceneRadius',
      'halfH',
      'dist',
      'renderedReach',
    ]) {
      expect(line.contains(length), isFalse,
          reason: 'depthBias has no unit — RealityKit\'s default is 1.0 for '
              'every scene at every scale — so scaling it by $length is the '
              'M293 bug in one direction or the M277 bug in the other:\n'
              '  $line');
    }
    // And it is at the default rather than merely constant: below it is acne,
    // above it the contact shadow lifts away from the model (M277).
    expect(line.contains('1.0'), isTrue,
        reason: 'the default is 1.0, and both failures were departures from '
            'it in opposite directions:\n  $line');
  });

  test('the shadow VOLUME is still measured from the camera (M277)', () {
    // The other half of applyLighting, and the one thing in it that SHOULD be
    // a distance. M277 fixed "the shadow often gets cut away" by measuring
    // maximumDistance from the camera rather than from the origin; a fix for
    // the bias must not quietly undo it.
    final body = _applyLighting(_renderer.readAsStringSync());
    expect(body.contains('cameraFit().dist'), isTrue,
        reason: 'the shadow volume has to span the camera, not the origin');
    expect(body.contains('maximumDistance'), isTrue);
  });
}
