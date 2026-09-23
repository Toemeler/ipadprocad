// #95 — "hier ist wieder viel falsch gelaufen". Build 5b90367.
//
// "mach eine mini rolle auf die D achse des motors". faces_where handed the
// model each face's AREA centroid as `at`: the Ø0.8 D-shaft (flat at
// x = -0.1) came back at x = 0.21, the motor can at x = 0.505, and the model
// centred the spool's bore on 0.505 — off the shaft it was meant to fit.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ai/ai_actions.dart';
import 'package:prototype/ai/ai_cad.dart';
import 'package:prototype/ai/shape_digest.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/part_render.dart' show kFaceCylinder;

void main() {
  test('a D-shaft reports its axis, not where its area lies', () {
    // The F8 of the report: axis along +Y through x = 0, z = 0; the flat
    // pulls the area centroid to x = 0.21.
    final f = DigestFace(
        id: 8,
        topoId: -1,
        type: kFaceCylinder,
        at: const Vec3(0, 8.7, 0),
        dir: const Vec3(0, 1, 0),
        radius: 0.4,
        area: 1.4588,
        centroid: const Vec3(0.2124, 9.2, 0),
        concave: false,
        tangent: false);
    expect(aiAxisAt(f), [0.0, 9.2, 0.0]);
  });

  test('the instructions say to centre on axisAt', () {
    expect(kAiActionInstructions, contains('`axisAt`'));
  });
}
