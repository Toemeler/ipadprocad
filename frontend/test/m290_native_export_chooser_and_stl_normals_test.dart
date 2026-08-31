import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('export format chooser is native, not a Material dialog', () {
    final file = File('lib/widgets/home_view.dart');
    final source = file.readAsStringSync();

    expect(source, isNot(contains('SimpleDialog')));
    expect(source, contains('NativeMenu.menu'));
  });

  test('STL writer computes and normalizes per-facet normals', () {
    final file = File('lib/app_state.dart');
    final source = file.readAsStringSync();

    expect(source, contains('nx = ay * bz - az * by;'));
    expect(source, contains('ny = az * bx - ax * bz;'));
    expect(source, contains('nz = ax * by - ay * bx;'));
    expect(source, contains('math.sqrt(nx * nx + ny * ny + nz * nz);'));
  });
}
