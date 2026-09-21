import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ai/ai_backend.dart';
import 'package:prototype/ai/ai_controller.dart';
import 'package:prototype/ai/ai_store.dart';

const _part =
    AiDocument(id: '/parts/bracket.ptp', name: 'Bracket', kind: 'part');
const _drawing =
    AiDocument(id: '/drawings/layout.ptd', name: 'Layout', kind: 'drawing');
const _documents = [_part, _drawing];

void main() {
  final controllers = <AiController>[];
  final directories = <Directory>[];

  AiController makeController(_FakeBackend backend, {bool ready = true}) {
    final controller = AiController(backend: backend);
    controllers.add(controller);
    if (ready) controller.initializeInMemory();
    controller.contextReader = (id) async => {
          'id': id,
          'name': _documents.firstWhere((document) => document.id == id).name,
          'coverage': 'document summary only',
        };
    controller.updateWorkspace(current: _part, documents: _documents);
    return controller;
  }

  Directory tempDirectory() {
    final directory =
        Directory.systemTemp.createTempSync('prototype_ai_controller_');
    directories.add(directory);
    return directory;
  }

  tearDown(() {
    for (final controller in controllers) {
      controller.dispose();
    }
    controllers.clear();
    for (final directory in directories) {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    }
    directories.clear();
  });

  test('manual document switches restore independent named sessions and drafts',
      () {
    final controller = makeController(_FakeBackend());
    final partSession = controller.currentSession;
    controller.renameSession(partSession.id, 'Engineering review');
    controller.updateDraft('Check bracket wall thickness');
    controller.newSession();
    final secondPartSession = controller.currentSession;
    controller.renameSession(secondPartSession.id, 'Appearance review');
    controller.updateDraft('Make the silhouette lighter');

    controller.updateWorkspace(current: _drawing, documents: _documents);
    final drawingSession = controller.currentSession;
    controller.updateDraft('Review the layout');
    expect(drawingSession.id, isNot(partSession.id));
    expect(controller.sessions, [drawingSession]);

    controller.updateWorkspace(current: _part, documents: _documents);
    expect(controller.currentSession.id, secondPartSession.id);
    expect(controller.currentSession.name, 'Appearance review');
    expect(controller.currentSession.draft, 'Make the silhouette lighter');
    controller.selectSession(partSession.id);
    expect(controller.currentSession.draft, 'Check bracket wall thickness');
    expect(controller.currentSession.name, 'Engineering review');
    expect(() => controller.selectSession(drawingSession.id),
        throwsA(isA<AiException>()));
  });

  test(
      'explicit continuation preserves ownership and adds selected document context',
      () async {
    final backend = _FakeBackend();
    final controller = makeController(backend);
    final original = controller.currentSession;
    controller.updateWorkspace(current: _drawing, documents: _documents);
    final drawingSession = controller.currentSession;
    controller.updateDraft('Independent layout draft');
    controller.updateWorkspace(current: _part, documents: _documents);
    controller.documentOpener = (id) async {
      controller.updateWorkspace(
        current: _documents.firstWhere((document) => document.id == id),
        documents: _documents,
      );
    };

    await controller.continueInDocument(_drawing.id);
    expect(controller.currentSession.id, original.id);
    expect(controller.currentSession.documentId, _part.id);
    controller.updateDraft('Check how this part fits the drawing');
    await controller.send();
    final context = jsonDecode(backend.requests.single.context) as Map;
    expect((context['activeDocument'] as Map)['id'], _drawing.id);
    expect((context['documents'] as List).map((value) => value['id']),
        unorderedEquals([_part.id, _drawing.id]));

    controller.updateWorkspace(current: _part, documents: _documents);
    controller.updateWorkspace(current: _drawing, documents: _documents);
    expect(controller.currentSession.id, drawingSession.id);
    expect(controller.currentSession.draft, 'Independent layout draft');
    expect(controller.currentSession.messages, isEmpty);
  });

  test('failed continuation does not silently include the unopened document',
      () async {
    final backend = _FakeBackend();
    final controller = makeController(backend);
    final session = controller.currentSession;
    controller.documentOpener =
        (_) async => throw const AiException('document');
    await expectLater(controller.continueInDocument(_drawing.id),
        throwsA(isA<AiException>()));
    expect(controller.currentSession.id, session.id);
    expect(session.contextDocumentIds, isEmpty);
    controller.updateDraft('Inspect this part only');
    await controller.send();
    final context = jsonDecode(backend.requests.single.context) as Map;
    expect(
        (context['documents'] as List).map((value) => value['id']), [_part.id]);
  });

  test('reply completing on another tab stays in the originating session',
      () async {
    final backend = _FakeBackend();
    final reply = Completer<AiReply>();
    backend.respondWith = (_) => reply.future;
    final controller = makeController(backend);
    final origin = controller.currentSession;
    controller.updateDraft('Review the bracket');
    final sending = controller.send();
    await backend.firstRequest.future;
    controller.updateWorkspace(current: _drawing, documents: _documents);
    final other = controller.currentSession;
    controller.updateDraft('Unsent layout question');
    expect(controller.isBusy, isFalse);
    expect(controller.anyRequestBusy, isTrue);

    reply.complete(const AiReply('Bracket review only', 'test'));
    await sending;
    expect(other.messages, isEmpty);
    expect(other.draft, 'Unsent layout question');
    expect(origin.messages.map((message) => message.text),
        ['Review the bracket', 'Bracket review only']);
    final context = jsonDecode(backend.requests.single.context) as Map;
    expect((context['activeDocument'] as Map)['id'], _part.id);
    expect(controller.currentSession.id, other.id);
  });

  test('context capture completing after a tab switch keeps the captured owner',
      () async {
    final backend = _FakeBackend();
    final controller = makeController(backend);
    final contextStarted = Completer<void>();
    final contextResult = Completer<Map<String, dynamic>>();
    controller.contextReader = (id) {
      expect(id, _part.id);
      contextStarted.complete();
      return contextResult.future;
    };
    final original = controller.currentSession;
    controller.updateDraft('Original question');
    final sending = controller.send();
    await contextStarted.future;
    controller.updateWorkspace(current: _drawing, documents: _documents);
    final other = controller.currentSession;
    contextResult.complete({'id': _part.id, 'name': _part.name});
    await sending;
    expect(original.messages.last.text, 'Test reply');
    expect(other.messages, isEmpty);
    expect(backend.requests.single.messages.single.text, 'Original question');
  });

  test('cancelled request cannot append a late reply', () async {
    final backend = _FakeBackend();
    final reply = Completer<AiReply>();
    backend.respondWith = (_) => reply.future;
    final controller = makeController(backend);
    controller.updateDraft('Cancel this review');
    final sending = controller.send();
    final request = await backend.firstRequest.future;
    controller.cancel();
    expect(backend.cancelled, [request.id]);
    expect(controller.anyRequestBusy, isFalse);
    reply.complete(const AiReply('Late reply must be discarded', 'test'));
    await sending;
    expect(
        controller.currentSession.messages
            .where((message) => message.role == 'assistant'),
        isEmpty);
  });

  test('late completion of cancelled send cannot clear a newer send busy state',
      () async {
    final backend = _FakeBackend();
    final oldReply = Completer<AiReply>();
    final newReply = Completer<AiReply>();
    final secondStarted = Completer<void>();
    backend.respondWith = (_) {
      if (backend.requests.length == 1) return oldReply.future;
      secondStarted.complete();
      return newReply.future;
    };
    final controller = makeController(backend);
    controller.updateDraft('First question');
    final firstSend = controller.send();
    await backend.firstRequest.future;
    controller.cancel();
    controller.updateDraft('Replacement question');
    final secondSend = controller.send();
    await secondStarted.future;
    oldReply.complete(const AiReply('Discard this old answer', 'test'));
    await firstSend;
    expect(controller.isBusy, isTrue);
    expect(controller.anyRequestBusy, isTrue);
    newReply.complete(const AiReply('Replacement answer', 'test'));
    await secondSend;
    expect(
        controller.currentSession.messages
            .where((message) => message.role == 'assistant')
            .map((message) => message.text),
        ['Replacement answer']);
    expect(controller.isBusy, isFalse);
  });

  test(
      'deleting an active session cancels it and a late reply cannot resurrect it',
      () async {
    final backend = _FakeBackend();
    final reply = Completer<AiReply>();
    backend.respondWith = (_) => reply.future;
    final controller = makeController(backend);
    final deletedId = controller.currentSession.id;
    controller.updateDraft('Delete this conversation');
    final sending = controller.send();
    final request = await backend.firstRequest.future;
    controller.deleteSession(deletedId);
    reply.complete(const AiReply('Should not return', 'test'));
    await sending;
    expect(backend.cancelled, [request.id]);
    expect(
        controller.sessions.any((session) => session.id == deletedId), isFalse);
    expect(controller.currentSession.messages, isEmpty);
  });

  test('provider is called only after outbound history has been saved',
      () async {
    final backend = _FakeBackend();
    final controller = makeController(backend, ready: false);
    final store = _ControlledStore(tempDirectory());
    await controller.initialize(store);
    final saveStarted = Completer<void>();
    final saveAllowed = Completer<void>();
    store.beforeSave = (_) {
      if (!saveStarted.isCompleted) saveStarted.complete();
      return saveAllowed.future;
    };
    controller.updateDraft('Persist before sending');
    final sending = controller.send();
    await saveStarted.future;
    expect(backend.requests, isEmpty);
    saveAllowed.complete();
    await sending;
    expect(backend.requests, hasLength(1));
    expect(
        (store.saved.first['sessions'] as List)
            .single['messages']
            .single['text'],
        'Persist before sending');
  });

  test('failed persistence preserves the draft and attachments without billing',
      () async {
    final backend = _FakeBackend();
    final controller = makeController(backend, ready: false);
    final store = _ControlledStore(tempDirectory());
    await controller.initialize(store);
    store.beforeSave =
        (_) async => throw const AiStoreException('Disk unavailable');
    final attachment = AiAttachment.fromBytes(
        name: 'dimensions.txt',
        bytes: Uint8List.fromList(utf8.encode('wall: 3 mm')));
    controller.updateDraft('Check these dimensions');
    controller.addAttachment(attachment);
    await controller.send();
    expect(backend.requests, isEmpty);
    expect(controller.currentSession.messages, isEmpty);
    expect(controller.currentSession.draft, 'Check these dimensions');
    expect(controller.currentSession.attachments.map((value) => value.id),
        [attachment.id]);
    expect(controller.currentSession.errorCode, 'storage');
    expect(controller.isBusy, isFalse);
  });

  test('provider failure can retry the same turn without duplicating history',
      () async {
    final backend = _FakeBackend();
    // M455 — the app now retries a dropped connection by itself (issue #81),
    // so a turn only reaches the user as a failure once the automatic tries
    // are spent. What this test is about is unchanged and still matters: the
    // MANUAL retry after that must not put the user's turn in twice.
    final persistent = kAiMaxNetworkRetries + 1;
    backend.respondWith = (_) async {
      if (backend.requests.length <= persistent) {
        throw const AiException('network');
      }
      return const AiReply('Successful retry', 'test');
    };
    final controller = makeController(backend);
    final attachment = AiAttachment.fromBytes(
        name: 'brief.txt',
        bytes: Uint8List.fromList(utf8.encode('A light mounting bracket.')));
    controller.updateDraft('Review my brief');
    controller.addAttachment(attachment);
    await controller.send();
    expect(controller.currentSession.errorCode, 'network');
    expect(controller.currentSession.draft, 'Review my brief');
    expect(controller.currentSession.attachments.map((value) => value.id),
        [attachment.id]);
    await controller.send();
    expect(backend.requests, hasLength(persistent + 1));
    expect(
        backend.requests.last.messages
            .where((message) => message.role == 'user'),
        hasLength(1));
    expect(backend.requests.last.messages.single.attachments.single.id,
        attachment.id);
    expect(controller.currentSession.messages.map((message) => message.role),
        ['user', 'assistant']);
    expect(controller.currentSession.messages.last.text, 'Successful retry');
    expect(controller.currentSession.draft, isEmpty);
  });

  test('multiline first prompt safely generates a readable title', () async {
    final backend = _FakeBackend();
    final controller = makeController(backend);
    controller.updateDraft('Check\n\n  the    bracket');
    await controller.send();
    expect(backend.requests, hasLength(1));
    expect(controller.currentSession.name, 'Check the bracket');
    expect(controller.currentSession.messages.last.role, 'assistant');
  });

  test(
      'rename migrates document and child sketch identity without merging copies',
      () {
    final controller = makeController(_FakeBackend());
    final partSession = controller.currentSession;
    controller.updateDraft('Part history');
    const sketch = AiDocument(
        id: '${_partId}#sketch:face-1', name: 'Profile', kind: 'sketch');
    const copy =
        AiDocument(id: '/parts/bracket.ptp-copy', name: 'Copy', kind: 'part');
    controller.updateWorkspace(
        current: sketch, documents: [..._documents, sketch, copy]);
    final sketchSession = controller.currentSession;
    controller.updateDraft('Sketch history');
    controller.setContextDocument(_part.id, true);
    controller.updateWorkspace(
        current: copy, documents: [..._documents, sketch, copy]);
    final copySession = controller.currentSession;
    controller.updateDraft('Copy history');

    const renamed =
        AiDocument(id: '/parts/new-name.ptp', name: 'New name', kind: 'part');
    const renamedSketch = AiDocument(
        id: '/parts/new-name.ptp#sketch:face-1',
        name: 'Profile',
        kind: 'sketch');
    controller.migrateDocument(_part.id, renamed.id);
    controller.updateWorkspace(
        current: renamed, documents: [renamed, renamedSketch, copy, _drawing]);
    expect(controller.currentSession.id, partSession.id);
    expect(controller.currentSession.draft, 'Part history');
    controller.updateWorkspace(
        current: renamedSketch,
        documents: [renamed, renamedSketch, copy, _drawing]);
    expect(controller.currentSession.id, sketchSession.id);
    expect(controller.currentSession.contextDocumentIds, {renamed.id});
    controller.updateWorkspace(
        current: copy, documents: [renamed, renamedSketch, copy, _drawing]);
    expect(controller.currentSession.id, copySession.id);
    expect(controller.currentSession.documentId, copy.id);
  });

  test('malformed saved selection cannot expose another document conversation',
      () async {
    final private = AiSession(documentId: _drawing.id, name: 'Drawing only');
    private.messages
        .add(AiMessage(role: 'user', text: 'Private drawing question'));
    final store = _ControlledStore(tempDirectory())
      ..initial = {
        'version': 1,
        'preferences': const AiPreferences().toJson(),
        'selected': {_part.id: private.id},
        'sessions': [private.toJson()],
      };
    final controller = makeController(_FakeBackend(), ready: false);
    await controller.initialize(store);
    expect(controller.currentSession.documentId, _part.id);
    expect(controller.currentSession.messages, isEmpty);
    expect(controller.currentSession.id, isNot(private.id));
  });

  test(
      'saved independent sessions restore names, attachments and document selection',
      () async {
    final store = AiStore(tempDirectory());
    final first = makeController(_FakeBackend(), ready: false);
    await first.initialize(store);
    first.renameSession(first.currentSession.id, 'Bracket engineering');
    first.updateDraft('Unsaved design question');
    final partId = first.currentSession.id;
    final attachment = AiAttachment.fromBytes(
        name: 'brief.txt',
        bytes: Uint8List.fromList(utf8.encode('Keep the external size.')));
    first.addAttachment(attachment);
    first.updateWorkspace(current: _drawing, documents: _documents);
    first.renameSession(first.currentSession.id, 'Drawing conversation');
    final drawingId = first.currentSession.id;
    await first.flush();

    final restored = makeController(_FakeBackend(), ready: false);
    await restored.initialize(AiStore(store.directory));
    expect(restored.currentSession.id, partId);
    expect(restored.currentSession.name, 'Bracket engineering');
    expect(restored.currentSession.draft, 'Unsaved design question');
    expect(restored.currentSession.attachments.single.id, attachment.id);
    restored.updateWorkspace(current: _drawing, documents: _documents);
    expect(restored.currentSession.id, drawingId);
    expect(restored.currentSession.name, 'Drawing conversation');
  });

  test('delete all removes conversation content from primary and recovery copy',
      () async {
    final directory = tempDirectory();
    final controller = makeController(_FakeBackend(), ready: false);
    await controller.initialize(AiStore(directory));
    controller.updateDraft('DELETE_THIS_PRIVATE_CONVERSATION');
    await controller.send();
    await controller.flush();
    await controller.deleteAllConversations();
    for (final suffix in ['', '.bak']) {
      final contents =
          await File('${directory.path}/${AiStore.fileName}$suffix')
              .readAsString();
      expect(contents, isNot(contains('DELETE_THIS_PRIVATE_CONVERSATION')));
    }
    final restored = makeController(_FakeBackend(), ready: false);
    await restored.initialize(AiStore(directory));
    expect(restored.currentSession.messages, isEmpty);
    expect(restored.currentSession.draft, isEmpty);
  });

  test('delayed clipboard image never attaches to a different document',
      () async {
    final backend = _FakeBackend();
    final image = Completer<AiAttachment?>();
    backend.clipboardResult = image.future;
    final controller = makeController(backend);
    final original = controller.currentSession;
    final pasting = controller.pasteImage();
    controller.updateWorkspace(current: _drawing, documents: _documents);
    final result = expectLater(pasting, throwsA(isA<AiException>()));
    image.complete(AiAttachment.fromBytes(
        name: 'image.png',
        bytes: Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10])));
    await result;
    expect(controller.currentSession.attachments, isEmpty);
    expect(original.attachments, isEmpty);
  });
}

const _partId = '/parts/bracket.ptp';

class _FakeBackend implements AiBackend {
  final requests = <AiRequest>[];
  final cancelled = <String>[];
  final firstRequest = Completer<AiRequest>();
  Future<AiReply> Function(AiRequest request)? respondWith;
  Future<AiAttachment?>? clipboardResult;

  @override
  Future<AiCapabilities> capabilities(AiPreferences preferences) async =>
      AiCapabilities(
          provider: preferences.provider,
          label: 'Test provider',
          available: true);
  @override
  Future<AiReply> respond(AiPreferences preferences, AiRequest request) {
    requests.add(request);
    if (!firstRequest.isCompleted) firstRequest.complete(request);
    return respondWith?.call(request) ??
        Future.value(const AiReply('Test reply', 'test'));
  }

  @override
  Future<void> cancel(String requestId) async {
    cancelled.add(requestId);
  }

  @override
  Future<bool> hasKey(AiProvider provider) async => false;
  @override
  Future<void> saveKey(AiProvider provider, String key) async {}
  @override
  Future<void> removeKey(AiProvider provider) async {}
  @override
  Future<AiAttachment?> pasteImage() async => await clipboardResult;
  @override
  void dispose() {}
}

class _ControlledStore extends AiStore {
  _ControlledStore(super.directory);
  Map<String, dynamic>? initial;
  final saved = <Map<String, dynamic>>[];
  Future<void> Function(Map<String, dynamic> value)? beforeSave;

  @override
  Future<Map<String, dynamic>?> load() async => initial;
  @override
  Future<void> save(Map<String, dynamic> value) async {
    final captured = jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
    await beforeSave?.call(captured);
    saved.add(captured);
  }

  @override
  Future<void> flush() async {}
}
