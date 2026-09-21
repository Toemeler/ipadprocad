// M452 — moving to the one DeepSeek model that can see, and telling it to
// think less.
//
// I told the user DeepSeek could not receive images. What I had checked was
// this app's own `supportsImages: provider != deepseek`, not DeepSeek's API:
// V4.1-Flash is natively multimodal. So the render in issue #72 was never
// refused by the provider — it was never offered to it.
//
// Two consequences, both tested here.
//
//   CAPABILITY BELONGS TO THE MODEL. A provider-wide boolean was wrong the
//   day the provider shipped a vision model, and would be wrong again next
//   time. Changing the DEFAULT only helps a fresh install, so an existing
//   install is moved off a blind model once — and never a second time, or a
//   deliberate later choice would be overridden on the next launch.
//
//   THINKING IS A DIAL. 8,906 of 9,662 output tokens in that session were
//   reasoning: 424 of them, and eleven seconds, to emit one fillet. The first
//   round of a turn is where the judgement is; the rest is execution.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ai/ai_backend.dart';
import 'package:prototype/ai/ai_controller.dart';
import 'package:prototype/ai/ai_store.dart';

void main() {
  final dirs = <Directory>[];
  AiStore storeWith(Map<String, dynamic> value) {
    final dir = Directory.systemTemp.createTempSync('prototype_m452_');
    dirs.add(dir);
    final store = AiStore(dir);
    File('${dir.path}/${AiStore.fileName}').writeAsStringSync(jsonEncode(value));
    return store;
  }

  Map<String, dynamic> storeFor(String model,
          {String provider = 'deepseek', List<String>? migrations}) =>
      {
        'version': 1,
        if (migrations != null) 'migrations': migrations,
        'preferences': {
          'provider': provider,
          'model': model,
          'allowEdits': true
        },
        'selected': <String, String>{},
        'sessions': <Map<String, dynamic>>[],
      };

  Future<AiController> load(Map<String, dynamic> value) async {
    final controller = AiController(backend: _Backend());
    addTearDown(controller.dispose);
    await controller.initialize(storeWith(value));
    return controller;
  }

  tearDown(() => dirs.clear());

  group('the id', () {
    test('the default is the model that can see', () {
      expect(kDeepSeekDefaultModel, 'deepseek-flash');
      expect(deepSeekTakesImages(kDeepSeekDefaultModel), isTrue);
      expect(deepSeekTakesThinking(kDeepSeekDefaultModel), isTrue);
    });
  });

  group('an existing install is moved off a blind model, once', () {
    test('the model the user was actually left on', () async {
      final controller = await load(storeFor('deepseek-v4-pro'));
      expect(controller.preferences.model, kDeepSeekDefaultModel);
      expect(controller.preferences.provider, AiProvider.deepseek);
    });

    test('and this app\'s own older defaults', () async {
      for (final old in ['deepseek-chat', 'deepseek-reasoner']) {
        final controller = await load(storeFor(old));
        expect(controller.preferences.model, kDeepSeekDefaultModel,
            reason: old);
      }
    });

    test('a switch the user made themselves is never undone', () async {
      // The migration already ran, and they then chose a text-only model.
      // That is a choice, and this must not fight it on every launch.
      final controller = await load(
          storeFor('deepseek-chat', migrations: const ['deepseekFlash']));
      expect(controller.preferences.model, 'deepseek-chat');
    });

    test('a model outside the superseded set is left alone', () async {
      final controller = await load(storeFor('deepseek-v4-flash-vision-exp'));
      expect(controller.preferences.model, 'deepseek-v4-flash-vision-exp');
    });

    test('another provider is not touched', () async {
      final controller = await load(
          storeFor('claude-opus-5', provider: 'anthropic'));
      expect(controller.preferences.model, 'claude-opus-5');
    });

    test('everything else in the store survives the migration', () async {
      final value = storeFor('deepseek-v4-pro');
      value['preferences']['allowEdits'] = false;
      final controller = await load(value);
      expect(controller.preferences.allowEdits, isFalse);
      expect(controller.preferences.provider, AiProvider.deepseek);
    });
  });

  group('thinking is a dial, not a constant', () {
    test('full effort on the round where the judgement is', () {
      expect(deepSeekReasoningEffort(0), 'high');
    });

    test('low effort on every execution round after it', () {
      expect(deepSeekReasoningEffort(1), 'low');
      expect(deepSeekReasoningEffort(7), 'low');
      // A closing answer carries no round and needs no deliberation.
      expect(deepSeekReasoningEffort(null), 'low');
    });

    test('only a model that takes the controls is sent them', () {
      expect(deepSeekTakesThinking('deepseek-flash'), isTrue);
      expect(deepSeekTakesThinking('deepseek-v4-pro'), isFalse);
      expect(deepSeekTakesThinking('deepseek-chat'), isFalse);
    });
  });
}

class _Backend implements AiBackend {
  @override
  Future<AiCapabilities> capabilities(AiPreferences preferences) async =>
      AiCapabilities(
          provider: preferences.provider, label: 'Test', available: true);
  @override
  Future<AiReply> respond(AiPreferences preferences, AiRequest request) async =>
      const AiReply('ok', 'test');
  @override
  Future<void> cancel(String requestId) async {}
  @override
  Future<bool> hasKey(AiProvider provider) async => true;
  @override
  Future<void> saveKey(AiProvider provider, String key) async {}
  @override
  Future<void> removeKey(AiProvider provider) async {}
  @override
  Future<AiAttachment?> pasteImage() async => null;
  @override
  void dispose() {}
}
