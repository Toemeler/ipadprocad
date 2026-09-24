import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ai/ai_cad.dart';
import 'package:prototype/ai/ai_controller.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final kernel = OcctPartKernel();
  test('coaster', () async {
    final app = AppState(ai: AiController())..partKernel = kernel;
    app.docsDirForTest = Directory.systemTemp.createTempSync('prog_');
    await app.createNamedPart('P');
    final cad = AiCad(app);
    for (final n in [3, 4, 5]) {
      final steps = [{"cylinder": {"base": [0, 0, 0], "d": "D", "h": "t"}}, {"chamfer": {"d": 0.6, "edges": "bottom"}}, {"box": {"size": ["D*0.8", "t*2", "D*0.8"], "center": [0, "t*2+hexT/2", 0], "mode": "cut"}}, {"cylinder": {"base": [0, "hexT/2", 0], "axis": "y", "d": "hexD", "h": "t", "mode": "cut", "repeat": {"count": "rows", "step": ["cell", 0, 0]}}}, {"cylinder": {"base": ["cell/2", "hexT/2", 0], "axis": "y", "d": "hexD", "h": "t", "mode": "cut", "repeat": {"count": "cols", "step": ["cell", 0, 0]}}}];
      final r = await cad.run([
        AiAction('vars', {"D": 90, "t": 4, "cell": 9, "hexD": 5.2, "hexT": 1.6, "cols": 7, "rows": 7}),
        AiAction('program', {'part': 'c$n', 'steps': steps.sublist(0, n)}),
      ]);
      print('RESULT $n ${r.encode()}');
    }
  });
}
