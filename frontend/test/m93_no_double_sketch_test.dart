// M93 — the sketch being edited is drawn ONCE.
//
// Reported with a screenshot: while editing, the same rectangle appeared twice
// — the live 2D one under the finger and a frozen copy where it started. The
// drag log confirms the 2D geometry followed the finger exactly, so the second
// rectangle was the 3D rendering of the same sketch, rebuilt only when the
// scene payload is rebuilt. Construction geometry leaked into 3D through the
// same door, because the `editing` flag was what switched construction ON in
// the payload builder.
//
// Rule now: whoever renders live owns it alone. Viewport2D draws the open
// sketch; neither the RealityKit payload nor the 3D CPU painter touches it.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/qcad_engine.dart' show Geo;
import 'package:prototype/part_model.dart';
import 'package:prototype/reality_scene.dart';

ChildSketch _sketchWithGeometry(PartModel p, String name) {
  final m = SketchModel(name);
  m.geometry.addAll([
    Geo(Geo.line, [0, 0, 10, 0]),
    Geo(Geo.line, [10, 0, 10, 10]),
    // a construction diagonal, as the centre rectangles now emit (M92)
    Geo(Geo.line, [0, 0, 10, 10]).withStyle(Geo.styleConstruction),
  ]);
  final cs = ChildSketch(m, 'xy', null, true, false, p.nextSeq());
  p.childSketches.add(cs);
  return cs;
}

void main() {
  group('M95 scene signature', _signatureTests);

  test('a visible, NOT-edited sketch is sent to 3D', () {
    final app = AppState();
    final p = PartModel('P');
    _sketchWithGeometry(p, 'Sketch1');
    final scene = buildScenePayload(app, p);
    final sketches = scene['sketches'] as List?;
    expect(sketches, isNotNull);
    expect(sketches, hasLength(1));
  });

  test('construction geometry never reaches 3D', () {
    final app = AppState();
    final p = PartModel('P');
    _sketchWithGeometry(p, 'Sketch1');
    final s0 = (buildScenePayload(app, p)['sketches'] as List).first as Map;
    // Two solid edges went, the construction diagonal did not.
    expect((s0['polylines'] as List), hasLength(2));
  });

  test('an EMPTY sketch contributes no payload at all', () {
    final app = AppState();
    final p = PartModel('P');
    p.childSketches.add(ChildSketch(SketchModel('Sketch1'), 'xy'));
    // The key is always present; what matters is that nothing is in it.
    expect((buildScenePayload(app, p)['sketches'] as List?) ?? const [],
        isEmpty);
  });

  test('a hidden sketch is not sent', () {
    final app = AppState();
    final p = PartModel('P');
    _sketchWithGeometry(p, 'Sketch1').visible = false;
    expect((buildScenePayload(app, p)['sketches'] as List?) ?? const [],
        isEmpty);
  });
}

// ---------------------------------------------------------------------------
// M95 — leaving the sketch must PUSH a rebuild.
//
// Since M93 the open sketch is deliberately absent from the payload, so
// opening and closing one changes what the scene contains. The signature had
// no idea which sketch was open, so closing it changed nothing, no rebuild was
// pushed, and the finished sketch stayed invisible in 3D until an unrelated
// change forced one — the reported "sketch is gone until I open and cancel
// Extrude".
void _signatureTests() {
  test('the open sketch is part of the scene signature', () {
    final app = AppState();
    final p = PartModel('P');
    _sketchWithGeometry(p, 'Sketch1');
    final closed = sceneSignature(app, p);
    expect(closed.contains('edit:;'), isTrue,
        reason: 'nothing open -> empty edit field');
    // The field is what makes open != closed, so a close forces a rebuild.
    expect(closed, isNot(contains('edit:Sketch1')));
  });

  test('the signature still tracks the things it already tracked', () {
    final app = AppState();
    final p = PartModel('P');
    final cs = _sketchWithGeometry(p, 'Sketch1');
    final before = sceneSignature(app, p);
    cs.visible = false;
    expect(sceneSignature(app, p), isNot(before));
  });
}
