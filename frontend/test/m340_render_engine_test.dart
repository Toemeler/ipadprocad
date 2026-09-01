// M340 — the renderer choice: a value, a store and a switch.
//
// Tested without a widget tree for the reason ribbon_dock.dart and
// backdrop.dart are: a preference is a value and a stored string, and neither
// half should need a device to check.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/render_engine.dart';

void main() {
  setUp(RenderEngines.resetForTest);
  tearDown(RenderEngines.resetForTest);

  group('the renderer setting', () {
    test('defaults to RealityKit, not to the better picture', () {
      // Rendered mode has to stay INSTANT by default. A first switch into it
      // that hangs for thirty seconds compiling Metal kernels is not a nicer
      // render, it is a broken mode. Cycles is something you ask for.
      expect(kRenderEngineDefault, RenderEngine.realityKit);
      expect(RenderEngines.current, RenderEngine.realityKit);
      expect(RenderEngines.isCycles, isFalse);
    });

    test('ids are spelled out, so renaming a value cannot silently reset it', () {
      expect(RenderEngine.realityKit.id, 'realitykit');
      expect(RenderEngine.cycles.id, 'cycles');
      for (final e in RenderEngine.values) {
        expect(RenderEngine.byId(e.id), e);
      }
      expect(RenderEngine.byId('nonsense'), isNull);
      expect(RenderEngine.byId(null), isNull);
      expect(RenderEngine.byId(7), isNull);
    });

    test('switching works before a store is attached', () {
      // A preference changed on a device whose disk is not ready yet still
      // takes effect; it simply is not remembered.
      RenderEngines.set(RenderEngine.cycles);
      expect(RenderEngines.isCycles, isTrue);
    });

    test('notifies, so the viewport can take a stale image down at once', () {
      var fired = 0;
      void listener() => fired++;
      RenderEngines.engine.addListener(listener);
      addTearDown(() => RenderEngines.engine.removeListener(listener));
      RenderEngines.set(RenderEngine.cycles);
      expect(fired, 1);
      // Setting the same value again is not a change.
      RenderEngines.set(RenderEngine.cycles);
      expect(fired, 1);
      RenderEngines.set(RenderEngine.realityKit);
      expect(fired, 2);
    });
  });

  group('the store', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('m340'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('survives a restart', () {
      final store = RenderEngineStore(dir);
      expect(store.load(), isNull, reason: 'nothing saved yet');
      store.save(RenderEngine.cycles);
      expect(store.load(), RenderEngine.cycles);
      RenderEngines.attachStore(store);
      expect(RenderEngines.current, RenderEngine.cycles);
    });

    test('MERGES into settings.json rather than owning it', () {
      // The ribbon position, the language and the appearance live in the same
      // file. A store that rewrote it wholesale would drop all three.
      final f = File('${dir.path}/${RenderEngineStore.fileName}');
      f.writeAsStringSync(jsonEncode({'ribbon': 'left', 'theme': 'dark'}));
      RenderEngineStore(dir).save(RenderEngine.cycles);
      final back = jsonDecode(f.readAsStringSync()) as Map;
      expect(back['ribbon'], 'left');
      expect(back['theme'], 'dark');
      expect(back['renderer'], 'cycles');
    });

    test('a corrupt settings file costs the preference and nothing else', () {
      File('${dir.path}/${RenderEngineStore.fileName}')
          .writeAsStringSync('{not json');
      expect(RenderEngineStore(dir).load(), isNull);
      // And it must not throw on the way out either.
      RenderEngineStore(dir).save(RenderEngine.cycles);
    });

    test('a settings file that is not a map is not a crash', () {
      File('${dir.path}/${RenderEngineStore.fileName}')
          .writeAsStringSync('[1,2,3]');
      expect(RenderEngineStore(dir).load(), isNull);
    });
  });
}
