import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ai/ai_store.dart';

void main() {
  late Directory directory;
  late AiStore store;
  File primary() => File('${directory.path}/${AiStore.fileName}');
  File backup() => File('${directory.path}/${AiStore.fileName}.bak');

  setUp(() {
    directory = Directory.systemTemp.createTempSync('prototype_ai_store_');
    store = AiStore(directory);
  });
  tearDown(() async {
    try {
      await store.flush();
    } on AiStoreException {
      // Individual cases assert the expected persistence error.
    }
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  test('no saved history is distinct from unreadable history', () async {
    expect(await store.load(), isNull);
    await primary().writeAsString('{broken');
    await expectLater(store.load(), throwsA(isA<AiStoreException>()));
    expect(await primary().readAsString(), '{broken');
  });

  test(
    'Unicode named sessions survive save and a new store instance',
    () async {
      final data = {
        'version': 1,
        'sessions': [
          {
            'id': 'one',
            'name': 'Gehäuse — 修订',
            'messages': ['A', 'B'],
          },
        ],
      };
      await store.save(data);
      expect(await AiStore(directory).load(), data);
      expect(store.recoveredFromBackup, isFalse);
    },
  );

  test(
    'queued saves capture input and retain the preceding accepted save',
    () async {
      final first = <String, dynamic>{
        'messages': <String>['first'],
      };
      final a = store.save(first);
      (first['messages'] as List<String>).add('mutated later');
      final b = store.save({
        'messages': ['second'],
      });
      final c = store.save({
        'messages': ['third'],
      });
      await Future.wait([a, b, c]);
      await store.flush();
      expect(await store.load(), {
        'messages': ['third'],
      });
      expect(jsonDecode(await backup().readAsString()), {
        'messages': ['second'],
      });
    },
  );

  test(
    'a pending save observes a snapshot rather than a later caller mutation',
    () async {
      final data = <String, dynamic>{
        'names': <String>['original'],
      };
      final save = store.save(data);
      (data['names'] as List<String>)[0] = 'changed';
      await save;
      expect(await store.load(), {
        'names': ['original'],
      });
    },
  );

  test(
    'corrupt primary recovers backup visibly and does not overwrite it',
    () async {
      await store.save({'name': 'last good'});
      await store.save({'name': 'newer'});
      await primary().writeAsString('{interrupted');
      expect(await store.load(), {'name': 'last good'});
      expect(store.recoveredFromBackup, isTrue);
      expect(store.recoveryReason, isNotEmpty);
      await store.save({'name': 'continued'});
      expect(jsonDecode(await backup().readAsString()), {'name': 'last good'});
      expect(await store.load(), {'name': 'continued'});
      expect(store.recoveredFromBackup, isFalse);
    },
  );

  test(
    'missing primary recovers backup while temporary candidate is ignored',
    () async {
      await store.save({'name': 'accepted'});
      await store.save({'name': 'newer'});
      await primary().delete();
      await File(
        '${primary().path}.tmp',
      ).writeAsString('{"name":"uncommitted"}');
      expect(await store.load(), {'name': 'accepted'});
      expect(store.recoveredFromBackup, isTrue);
    },
  );

  test(
    'two corrupt copies fail without replacing either with empty history',
    () async {
      await primary().writeAsString('[]');
      await backup().writeAsString('no JSON');
      await expectLater(store.load(), throwsA(isA<AiStoreException>()));
      expect(await primary().readAsString(), '[]');
      expect(await backup().readAsString(), 'no JSON');
    },
  );

  test(
    'size uses encoded UTF-8 bytes and a failed save remains observable',
    () async {
      store = AiStore(directory, maxBytes: 64);
      await store.save({'name': 'kept'});
      await expectLater(
        store.save({'name': List.filled(25, '😀').join()}),
        throwsA(isA<AiStoreException>()),
      );
      expect(await store.load(), {'name': 'kept'});
      await expectLater(store.flush(), throwsA(isA<AiStoreException>()));
      await store.save({'name': 'saved later'});
      await store.flush();
      expect(await store.load(), {'name': 'saved later'});
    },
  );

  test(
    'oversized on-disk primary falls back to a bounded valid backup',
    () async {
      store = AiStore(directory, maxBytes: 64);
      await backup().writeAsString('{"name":"backup"}');
      await primary().writeAsString(List.filled(65, 'x').join());
      expect(await store.load(), {'name': 'backup'});
      expect(store.recoveredFromBackup, isTrue);
    },
  );

  test(
    'credential fields are rejected at nested locations without disclosure',
    () async {
      await store.save({'name': 'safe'});
      for (final key in [
        'apiKey',
        'api_key',
        'Authorization',
        'access_token',
        'password',
      ]) {
        await expectLater(
          store.save({
            'sessions': [
              {
                'provider': {key: 'secret-value'},
              },
            ],
          }),
          throwsA(
            isA<AiStoreException>().having(
              (error) => error.toString(),
              'safe error',
              isNot(contains('secret-value')),
            ),
          ),
        );
      }
      expect(await store.load(), {'name': 'safe'});
      expect(await primary().readAsString(), isNot(contains('secret-value')));
    },
  );

  test('cyclic input fails safely and does not poison later saves', () async {
    final cycle = <String, dynamic>{};
    cycle['self'] = cycle;
    await expectLater(store.save(cycle), throwsA(isA<AiStoreException>()));
    await store.save({'name': 'recovered'});
    expect(await store.load(), {'name': 'recovered'});
  });

  test('custom JSON encoders cannot bypass credential validation', () async {
    await expectLater(
      store.save({'provider': _CredentialObject()}),
      throwsA(isA<AiStoreException>()),
    );
    expect(await store.load(), isNull);
  });

  test(
    'replacement failure retains the primary and surfaces an error',
    () async {
      await store.save({'name': 'retained'});
      // A directory cannot be atomically replaced by the backup file on either
      // Windows or Unix. This forces the real filesystem failure path.
      await Directory(backup().path).create();
      await expectLater(
        store.save({'name': 'not accepted'}),
        throwsA(isA<AiStoreException>()),
      );
      expect(jsonDecode(await primary().readAsString()), {'name': 'retained'});
      await expectLater(store.flush(), throwsA(isA<AiStoreException>()));
      await Directory(backup().path).delete();
      await store.save({'name': 'accepted now'});
      expect(await store.load(), {'name': 'accepted now'});
    },
  );
}

class _CredentialObject {
  Map<String, dynamic> toJson() => {'apiKey': 'must-not-persist'};
}
