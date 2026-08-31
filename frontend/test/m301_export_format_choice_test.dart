import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/widgets/home_view.dart';

void main() {
  test('part gallery cards offer STL and STEP, sketches only DXF', () {
    expect(exportFormatsFor('ptp'), containsAll(['stl', 'step']));
    expect(exportFormatsFor('ptp').length, 2);
    expect(exportFormatsFor('pts'), ['dxf']);
  });
}
