import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_menu/grabcad.dart';
import 'package:prototype/grabcad/grabcad_client.dart';
import 'package:prototype/grabcad/grabcad_native_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('prototype/native_menu');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('metadata POST and nested folder GET go through the native session',
      () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return {
        'status': 200,
        'body': '{"files":[],"folders":[]}',
        'contentType': 'application/json'
      };
    });
    final client = GrabCadNativeClient();
    addTearDown(client.close);
    final response = await client.post(
        Uri.parse('https://grabcad.com/community/api/v1/models'),
        body: jsonEncode({'query': 'bearing'}));
    await client.get(Uri.parse(
        'https://grabcad.com/community/api/v1/models/bearing/files?folder_id=2'));
    expect(response.statusCode, 200);
    expect(jsonDecode(response.body)['files'], isEmpty);
    expect(calls.map((c) => c.method), ['grabcadRequest', 'grabcadRequest']);
    expect(calls.first.arguments['path'], 'models');
    expect(jsonDecode(calls.first.arguments['body'])['query'], 'bearing');
    expect(calls.last.arguments['path'], 'models/bearing/files?folder_id=2');
    expect(calls.last.arguments['body'], isNull);
    expect(calls.first.arguments['id'], isNot(calls.last.arguments['id']));
    expect(calls.first.arguments.keys, isNot(contains('cookies')));
  });

  test('native timeouts retain their reason through the metadata adapter',
      () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'timeout');
    });
    final client = GrabCadClient(client: GrabCadNativeClient());
    addTearDown(client.close);
    await expectLater(
        client.search('bearing'),
        throwsA(
            isA<GrabCadException>().having((e) => e.code, 'code', 'timeout')));
  });

  test('closing a search cancels only its own native request IDs', () async {
    final waiting = Completer<Map<String, Object>>();
    final started = Completer<String>();
    final cancelled = Completer<List<dynamic>>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'grabcadRequest') {
        started.complete(call.arguments['id'] as String);
        return waiting.future;
      }
      if (call.method == 'grabcadCancelRequests') {
        cancelled.complete(call.arguments['ids'] as List<dynamic>);
        waiting.complete({'status': 200, 'body': '{}'});
      }
      return null;
    });
    final client = GrabCadNativeClient();
    final pending = client.get(
        Uri.parse('https://grabcad.com/community/api/v1/models/test/files'));
    final expectation = expectLater(pending, throwsException);
    final id = await started.future;
    client.close();
    expect(await cancelled.future, [id]);
    await expectation;
  });

  test('sign-in completion comes from the website bridge, not a Dart account',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'grabcadSignIn');
      expect(call.arguments.keys, isNot(contains('password')));
      return true;
    });
    expect(
        await NativeGrabCad.signIn(
            title: 'GrabCAD', done: 'Done', cancel: 'Cancel', help: 'Sign in'),
        isTrue);
  });
}
