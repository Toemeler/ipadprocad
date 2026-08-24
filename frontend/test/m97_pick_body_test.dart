// M97 — pick the extrude target body by clicking it.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/reality_scene.dart';

ExtrudeFeature _feat(PartModel p, String name, String body) {
  final f = ExtrudeFeature(
      name: name, bodyName: body, sketchName: 'Sketch1', profiles: const [])
    ..seq = p.nextSeq();
  p.features.add(f);
  return f;
}

void main() {
  group('M98 3D highlight', _highlightTests);
  group('M242 browser body selection', _selectionTests);

  test('hover is ignored unless a pick is actually armed', () {
    final app = AppState();
    expect(app.pickingBody, isFalse);
    app.setHoverBody('Solid1');
    expect(app.hoverBody, isNull,
        reason: 'no stray highlight when nothing is being picked');
  });

  test('arming needs an extrude session', () {
    final app = AppState();
    app.beginPickBody();
    expect(app.pickingBody, isFalse);
  });

  test('cancelling clears both flags', () {
    final app = AppState()..pickingBody = true;
    app.setHoverBody('Solid1');
    expect(app.hoverBody, 'Solid1');
    app.cancelPickBody();
    expect(app.pickingBody, isFalse);
    expect(app.hoverBody, isNull);
  });

  test('renaming a body renames it on every feature that builds it', () {
    final p = PartModel('P');
    _feat(p, 'Extrusion1', 'Solid1');
    _feat(p, 'Extrusion2', 'Solid1');
    _feat(p, 'Extrusion3', 'Solid2');
    for (final f in p.features) {
      if (f.bodyName == 'Solid1') f.bodyName = 'Housing';
    }
    expect(p.features.map((f) => f.bodyName).toList(),
        ['Housing', 'Housing', 'Solid2']);
  });

  test('deleting a body takes exactly its features', () {
    final p = PartModel('P');
    _feat(p, 'Extrusion1', 'Solid1');
    _feat(p, 'Extrusion2', 'Solid2');
    p.features.removeWhere((f) => f.bodyName == 'Solid1');
    expect(p.features, hasLength(1));
    expect(p.features.first.bodyName, 'Solid2');
  });
}

// ---------------------------------------------------------------------------
// M98 — the hovered body lights up in 3D too.
void _highlightTests() {
  test('the hover only moves the signature while a pick is armed', () {
    final app = AppState();
    final p = PartModel('P');
    final base = sceneSignature(app, p);
    expect(base, contains('hb:;'), reason: 'not picking -> empty field');
    app.pickingBody = true;
    app.setHoverBody('Solid1');
    expect(sceneSignature(app, p), isNot(base),
        reason: 'a hover must force a rebuild or nothing lights up');
    app.cancelPickBody();
    expect(sceneSignature(app, p), base,
        reason: 'and cost nothing once the pick is over');
  });
}

// ---------------------------------------------------------------------------
// M242 — clicking a Solid Bodies row selects the body; clicking it again
// clears it. The row highlight and the 3D tint both read AppState.selectedBody,
// so this is the one state that has to hold.
void _selectionTests() {
  test('a second click on the selected body clears it', () {
    final app = AppState();
    app.toggleBodySelected('Solid1');
    expect(app.selectedBody, 'Solid1');
    app.toggleBodySelected('Solid1');
    expect(app.selectedBody, isNull, reason: 'click again -> dehighlight');
    app.toggleBodySelected('Solid1');
    app.toggleBodySelected('Solid2');
    expect(app.selectedBody, 'Solid2', reason: 'one body at a time');
  });

  test('the selection moves the scene signature', () {
    final app = AppState();
    final p = PartModel('P');
    final base = sceneSignature(app, p);
    expect(base, contains('selb:;'), reason: 'nothing selected -> empty field');
    app.toggleBodySelected('Solid1');
    expect(sceneSignature(app, p), isNot(base),
        reason: 'a tint must force a rebuild or nothing lights up in 3D');
    app.toggleBodySelected('Solid1');
    expect(sceneSignature(app, p), base);
  });

  test('hovering a row lights the body without selecting it', () {
    final app = AppState();
    final p = PartModel('P');
    final base = sceneSignature(app, p);
    app.setBrowserHoverBody('Solid1');
    expect(app.browserHoverBody, 'Solid1');
    expect(app.selectedBody, isNull, reason: 'a hover is not a choice');
    expect(sceneSignature(app, p), isNot(base),
        reason: 'the hover tint must force a rebuild, like the selection');
    app.setBrowserHoverBody(null);
    expect(sceneSignature(app, p), base);
  });

  test('Esc clears the selection once nothing else is running', () {
    final app = AppState()..toggleBodySelected('Solid1');
    app.escape3D();
    expect(app.selectedBody, isNull);
  });
}
