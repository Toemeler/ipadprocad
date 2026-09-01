import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/widgets/home_view.dart';

void main() {
  group('exportFormatsFor', () {
    test('part file names offer STL and STEP', () {
      expect(exportFormatsFor('flange.ptp'), ['stl', 'step']);
      expect(exportFormatsFor('.ptp'), ['stl', 'step']);
    });

    test('sketch file names offer DXF only', () {
      expect(exportFormatsFor('bracket.pts'), ['dxf']);
      expect(exportFormatsFor('.pts'), ['dxf']);
    });

    test('bare legacy tokens still map to their formats', () {
      expect(exportFormatsFor('part'), ['stl', 'step']);
      expect(exportFormatsFor('ptp'), ['stl', 'step']);
      expect(exportFormatsFor('sketch'), ['dxf']);
      expect(exportFormatsFor('pts'), ['dxf']);
    });
  });
}
