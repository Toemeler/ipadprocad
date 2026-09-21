import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import '../app_state.dart';
import '../doc_ref.dart';
import '../doc_store.dart';
import 'ai_cad.dart';
import 'ai_controller.dart';

/// The document adapter: what the assistant may READ, and what it may CHANGE.
///
/// The two halves are deliberately different in kind. Reading is a bounded
/// SUMMARY of any document in the library — truncated, with omissions marked,
/// and never a file path or a B-Rep. Changing goes through [AiCad] and reaches
/// exactly one document, the part that is open, through the same feature and
/// sketch machinery the user's own tools use. A model reply is still never
/// executed as code: it can only name an operation from a fixed list.
class AiWorkspace {
  AiWorkspace(this.app) {
    app.ai.contextReader = readContext;
    app.ai.documentOpener = openDocument;
    app.ai.actionRunner = AiCad(app).run;
    app.addListener(sync);
    sync();
  }
  final AppState app;
  static String identity(DocRef ref) {
    final source = ref.source == DocSource.internal
        ? 'internal:${ref.kind}:${ref.name}'
        : 'external:${Platform.isWindows ? ref.path.toLowerCase().replaceAll('\\', '/') : ref.path}';
    return sha256.convert(utf8.encode(source)).toString();
  }

  AiDocument descriptor(DocRef ref) =>
      AiDocument(id: identity(ref), name: ref.name, kind: ref.kind);
  void sync() {
    final documents = app.library.values.map(descriptor).toList();
    AiDocument? current;
    final ref = app.library[app.curTab];
    if (ref != null) current = descriptor(ref);
    for (final entry in app.parts.entries) {
      final owner = app.library[entry.key];
      if (owner == null) continue;
      final parent = descriptor(owner);
      for (final child in entry.value.childSketches) {
        final childDoc = AiDocument(
            id: '${parent.id}#sketch:${Uri.encodeComponent(child.model.name)}',
            name: '${owner.name} / ${child.model.name}',
            kind: 'sketch');
        documents.add(childDoc);
        if (owner.name == app.curTab && identical(child.model, app.activeChild)) current = childDoc;
      }
    }
    app.ai.updateWorkspace(current: current, documents: documents);
  }

  DocRef? _ref(String id) {
    final owner = id.split('#sketch:').first;
    for (final ref in app.library.values) {
      if (identity(ref) == owner) return ref;
    }
    return null;
  }

  Future<void> openDocument(String id) async {
    final ref = _ref(id);
    if (ref == null) throw const AiException('document');
    await app.openDocument(ref.name);
    if (id.contains('#sketch:')) {
      final part = app.currentPart;
      final child =
          part?.sketchByName(Uri.decodeComponent(id.split('#sketch:').last));
      if (part == null || child == null) throw const AiException('document');
      app.openChildSketch(child.model.name);
    }
    sync();
  }

  Future<Map<String, dynamic>> readContext(String id) async {
    final ref = _ref(id);
    if (ref == null) throw const AiException('document');
    Object? content;
    var name = ref.name;
    var kind = ref.kind;
    var live = false;
    if (id.contains('#sketch:')) {
      final childName = Uri.decodeComponent(id.split('#sketch:').last);
      final sketch = app.parts[ref.name]?.sketchByName(childName)?.model;
      if (sketch == null) throw const AiException('document');
      content = _sketch(sketch);
      kind = 'sketch';
      name = '${ref.name} / $childName';
      live = true;
    } else if (app.parts.containsKey(ref.name)) {
      content = app.parts[ref.name]!.toJson();
      live = true;
    } else if (app.assemblies.containsKey(ref.name)) {
      content = app.assemblies[ref.name]!.toJson();
      live = true;
    } else if (app.sketches.containsKey(ref.name)) {
      content = _sketch(app.sketches[ref.name]!);
      live = true;
    } else {
      final header = readDocHeader(ref.path);
      final entry = header?.entry(kMetaEntry);
      if (entry == null || entry.length > 2 * 1024 * 1024)
        throw const AiException('context');
      content = readDocMeta(ref.path);
      if (content == null) throw const AiException('document');
    }
    return {
      'id': id,
      'name': name,
      'kind': kind,
      'source': live ? 'live authoring state' : 'saved metadata',
      'units': {'length': 'mm', 'angle': 'deg'},
      'coverage':
          'Bounded authoring summary only; omissions marked. No render, B-Rep, mass, '
              'strength, interference or manufacturing verification is included.',
      'content': _bounded(content)
    };
  }

  Map<String, dynamic> _sketch(SketchModel sketch) => {
        'geometryCount': sketch.geometry.length,
        'geometry': [
          for (var i = 0; i < sketch.geometry.length && i < 24; i++)
            {
              'indexAtCapture': i,
              'type': sketch.geometry[i].type,
              'data': sketch.geometry[i].data
            }
        ],
        'geometryOmitted':
            sketch.geometry.length > 24 ? sketch.geometry.length - 24 : 0,
        'constraintCount': sketch.constraints.length,
        'parameters': [
          for (final p in sketch.userParams)
            {'name': p.name, 'expression': p.expr, 'value': p.value}
        ],
      };
  Object? _bounded(Object? value, [int depth = 0]) {
    if (depth > 5) return {'omitted': 'depth limit'};
    if (value is Map) {
      const private = {
        'path',
        'file',
        'filePath',
        'bookmark',
        'brep',
        'mesh',
        'cam',
        'camera'
      };
      final entries =
          value.entries.where((e) => !private.contains(e.key)).toList();
      return {
        for (final e in entries.take(24))
          '${e.key}': _bounded(e.value, depth + 1),
        if (entries.length > 24) '_omittedFields': entries.length - 24
      };
    }
    if (value is Iterable)
      return [
        for (final item in value.take(24)) _bounded(item, depth + 1),
        if (value.length > 24) {'omittedItems': value.length - 24}
      ];
    if (value is String && value.length > 180)
      return {
        'prefix': value.substring(0, 180),
        'omittedCharacters': value.length - 180
      };
    if (value is num && !value.isFinite) return null;
    return value;
  }

  void dispose() => app.removeListener(sync);
}
