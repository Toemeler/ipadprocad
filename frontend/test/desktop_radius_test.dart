import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/desktop_radius.dart';

void main() {
  tearDown(() => debugDesktopCornersOverride = null);

  test('the suite keeps the iPad corners', () {
    expect(desktopCorners, isFalse);
    expect(desktopRadius(20), 20);
  });

  test('Linux and Windows draw every corner a little tighter', () {
    debugDesktopCornersOverride = true;
    expect(desktopRadius(20), 20 * kDesktopRadiusScale);
    expect(desktopRadius(20), lessThan(20));
    expect(desktopRadius(0), 0);
  });
}
