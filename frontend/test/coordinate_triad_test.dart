// The coordinate triad must clear the model browser's OPAQUE footprint, not
// its whole widget width. When the browser retracts, the glass slab is gone
// (M199) and only the glyph column at the top of the card remains, so the
// bottom-left corner is clear and the triad belongs back against the border
// instead of hovering `collapsedWidth` points out in open space.
//
// This is Dart-only geometry (`NativeModelBrowser.triadInset`), so it is fully
// testable off-iOS, unlike the Swift glass slab itself.

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/widgets/native_browser_host.dart';

void main() {
  group('NativeModelBrowser.triadInset', () {
    test('is zero when the panel is retracted', () {
      expect(
        NativeModelBrowser.triadInset(NativeModelBrowser.collapsedWidth),
        0,
      );
    });

    test('is the full width when the panel is wide or morphing', () {
      // M262 keeps [occupied] at the wide figure for the whole morph, so one
      // value covers "expanded" and "mid-morph".
      expect(
        NativeModelBrowser.triadInset(NativeModelBrowser.occupiedWidth),
        NativeModelBrowser.occupiedWidth,
      );
    });
  });
}
