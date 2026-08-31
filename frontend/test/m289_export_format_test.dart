import 'package:flutter_test/flutter_test.dart';

import '../lib/widgets/home_view.dart';

void main() {
  test('part cards offer STL and STEP before a location', () {
    expect(exportFormatsFor('part'), ['stl', 'step']);
  });

  test('sketch and assembly cards keep the DXF/STEP-only export', () {
    expect(exportFormatsFor('sketch'), ['dxf']);
    expect(exportFormatsFor('assembly'), ['step']);
  });
}
