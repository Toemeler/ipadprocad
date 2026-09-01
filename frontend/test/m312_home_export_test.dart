import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/widgets/home_view.dart';

class _FakeAppState extends AppState {
  _FakeAppState();

  final List<String> calls = [];

  @override
  Future<String?> partExportStl(String name) async {
    calls.add('stl:$name');
    return '/tmp/test.stl';
  }

  @override
  Future<String?> partExportStep(String name) async {
    calls.add('step:$name');
    return '/tmp/test.step';
  }

  @override
  Future<String?> sketchExportPath(String name) async {
    calls.add('dxf:$name');
    return '/tmp/test.dxf';
  }
}

void main() {
  testWidgets('exporting a dotted part name offers STL and exports it',
      (tester) async {
    final app = _FakeAppState();
    await tester.pumpWidget(MaterialApp(home: HomeView(app: app)));

    final dynamic state = tester.state(find.byType(HomeView));
    final dynamic sent = state.sendFile('flange.ptp', share: false);
    await tester.pumpAndSettle();

    expect(find.text('STL'), findsOneWidget);
    expect(find.text('STEP'), findsOneWidget);

    await tester.tap(find.text('STL'));
    await tester.pumpAndSettle(); 
    await sent;

    expect(app.calls, ['stl:flange.ptp']);
  });
}
