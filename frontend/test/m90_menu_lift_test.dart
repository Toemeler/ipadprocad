// M90 — the blank slab under the browser context menu.
//
// Long-pressing a model browser row lifted an EMPTY rounded rectangle the size
// of the row: buildPreview filled a container with the viewport colour and
// only then drew previewImagePath, so a target without an image produced a
// grey slab covering the tree. A browser row's pixels cannot be handed to
// UIKit at all — they live in Flutter's Metal layer, which is the very reason
// the gallery passes a PNG instead.
//
// Rows therefore opt out of lifting. The native half is device-only; what the
// host can pin is that the flag really travels, defaults safely, and that the
// gallery still asks for its picture.
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_menu/native_menu.dart';

NativeMenuTarget _t({bool? lift, String? image}) => NativeMenuTarget(
      id: 'row',
      title: 'Sketch2',
      rect: const Rect.fromLTWH(0, 0, 300, 26),
      groups: const [
        [NativeMenuItem(id: 'edit', title: 'Edit Sketch')]
      ],
      previewImagePath: image,
      lift: lift ?? true,
    );

void main() {
  test('lift defaults to true, so the gallery card is unaffected', () {
    expect(_t().toMap()['lift'], isTrue);
  });

  test('a row opts out and the flag reaches the platform channel', () {
    final m = _t(lift: false).toMap();
    expect(m['lift'], isFalse);
    // No image either — together these are what tells the native side there is
    // nothing to lift.
    expect(m.containsKey('previewImagePath'), isFalse);
  });

  test('a gallery card still carries its picture and lifts', () {
    final m = _t(image: '/tmp/Sketch2.png').toMap();
    expect(m['lift'], isTrue);
    expect(m['previewImagePath'], '/tmp/Sketch2.png');
  });

  test('the rest of the payload is unchanged by the new field', () {
    final m = _t(lift: false).toMap();
    expect(m['id'], 'row');
    expect(m['title'], 'Sketch2');
    expect((m['rect']! as Map)['width'], 300.0);
    expect((m['groups']! as List).first, hasLength(1));
  });
}
