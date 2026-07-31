// M177 — packing a staging folder into one document and back again.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/doc_file.dart';
import 'package:prototype/doc_store.dart';

Directory _scratch(String tag) =>
    Directory.systemTemp.createTempSync('m177_$tag');

void _write(String path, String text) {
  final f = File(path);
  f.parent.createSync(recursive: true);
  f.writeAsStringSync(text);
}

void main() {
  group('M177 pack / unpack', () {
    test('a staging folder round trips, sub-folders and all', () {
      final src = _scratch('src');
      _write('${src.path}/meta.json', '{"name":"Bracket"}');
      _write('${src.path}/sketches/Sketch1.dxf', 'DXF BODY');
      _write('${src.path}/sketches/Sketch1.cons.json', '[]');
      _write('${src.path}/imports/flange.step', 'ISO-10303-21;');

      final doc = packDir(src, 'part');
      expect(doc.kind, 'part');
      expect(doc.entries.keys.toSet(), {
        'meta.json',
        'sketches/Sketch1.dxf',
        'sketches/Sketch1.cons.json',
        'imports/flange.step',
      });

      final out = _scratch('out');
      unpackDoc(doc, out);
      expect(File('${out.path}/meta.json').readAsStringSync(),
          '{"name":"Bracket"}');
      expect(File('${out.path}/sketches/Sketch1.dxf').readAsStringSync(),
          'DXF BODY');
      expect(File('${out.path}/imports/flange.step').readAsStringSync(),
          'ISO-10303-21;');

      src.deleteSync(recursive: true);
      out.deleteSync(recursive: true);
    });

    test('binary payloads survive byte for byte', () {
      final src = _scratch('bin');
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 255, 13, 10]);
      File('${src.path}/preview.png').writeAsBytesSync(png);
      final out = _scratch('binout');
      unpackDoc(packDir(src, 'part'), out);
      expect(File('${out.path}/preview.png').readAsBytesSync(), png);
      src.deleteSync(recursive: true);
      out.deleteSync(recursive: true);
    });

    test('packing an empty or missing folder yields an empty document', () {
      final src = _scratch('empty');
      expect(packDir(src, 'part').entries, isEmpty);
      src.deleteSync(recursive: true);
      expect(packDir(src, 'part').entries, isEmpty); // now gone
    });

    test('unpack empties the target first', () {
      final out = _scratch('stale');
      _write('${out.path}/sketches/Old.dxf', 'stale');
      unpackDoc(DocFile('part', {'meta.json': utf8.encode('{}')}), out);
      expect(File('${out.path}/sketches/Old.dxf').existsSync(), isFalse);
      expect(File('${out.path}/meta.json').existsSync(), isTrue);
      out.deleteSync(recursive: true);
    });

    test('an entry name that would escape the folder is dropped', () {
      // A document is a file people send each other; its index is untrusted.
      final out = _scratch('escape');
      unpackDoc(
          DocFile('part', {
            '../evil.json': utf8.encode('no'),
            '/etc/evil.json': utf8.encode('no'),
            'a/../../evil.json': utf8.encode('no'),
            'ok.json': utf8.encode('yes'),
          }),
          out);
      expect(File('${out.parent.path}/evil.json').existsSync(), isFalse);
      expect(out.listSync().map((e) => e.path.split('/').last), ['ok.json']);
      out.deleteSync(recursive: true);
    });

    test('packing is stable: the same folder gives the same bytes', () {
      final src = _scratch('stable');
      _write('${src.path}/b.json', '2');
      _write('${src.path}/a.json', '1');
      _write('${src.path}/z/c.json', '3');
      expect(packDir(src, 'part').encode(), packDir(src, 'part').encode());
      src.deleteSync(recursive: true);
    });
  });

  group('M177 writeDoc / readDoc', () {
    test('written document reads back', () {
      final dir = _scratch('write');
      final path = '${dir.path}/Bracket.$kPartExt';
      expect(
          writeDoc(path, DocFile('part', {'meta.json': utf8.encode('{"v":1}')})),
          isTrue);
      expect(readDoc(path)!.textOf('meta.json'), '{"v":1}');
      expect(File('$path.tmp').existsSync(), isFalse);
      dir.deleteSync(recursive: true);
    });

    test('overwriting replaces rather than appends', () {
      final dir = _scratch('over');
      final path = '${dir.path}/Bracket.$kPartExt';
      writeDoc(path, DocFile('part', {'meta.json': utf8.encode('{"v":1}')}));
      final firstLen = File(path).lengthSync();
      writeDoc(path, DocFile('part', {'meta.json': utf8.encode('{"v":2}')}));
      expect(File(path).lengthSync(), firstLen);
      expect(readDoc(path)!.textOf('meta.json'), '{"v":2}');
      dir.deleteSync(recursive: true);
    });

    test('reading a missing or foreign file gives null, never a throw', () {
      final dir = _scratch('bad');
      expect(readDoc('${dir.path}/nope.ptp'), isNull);
      File('${dir.path}/foreign.ptp').writeAsStringSync('not a document');
      expect(readDoc('${dir.path}/foreign.ptp'), isNull);
      expect(readDocHeader('${dir.path}/foreign.ptp'), isNull);
      expect(readDocMeta('${dir.path}/foreign.ptp'), isNull);
      dir.deleteSync(recursive: true);
    });
  });

  group('M177 header-only reads', () {
    test('the index is readable without the payload', () {
      final dir = _scratch('hdr');
      final path = '${dir.path}/Bracket.$kPartExt';
      final big = Uint8List(200000)..fillRange(0, 200000, 7);
      writeDoc(
          path,
          DocFile('part', {
            kMetaEntry: utf8.encode('{"name":"Bracket"}'),
            kPreviewEntry: big,
          }));
      final h = readDocHeader(path)!;
      expect(h.kind, 'part');
      expect(h.entries.map((e) => e.name).toSet(), {kMetaEntry, kPreviewEntry});
      expect(h.entry(kPreviewEntry)!.length, 200000);
      dir.deleteSync(recursive: true);
    });

    test('one entry can be read on its own', () {
      final dir = _scratch('one');
      final path = '${dir.path}/Bracket.$kPartExt';
      writeDoc(
          path,
          DocFile('part', {
            kMetaEntry: utf8.encode('{"name":"Bracket"}'),
            kPreviewEntry: Uint8List.fromList([1, 2, 3, 4]),
            'sketches/Sketch1.dxf': utf8.encode('DXF'),
          }));
      expect(readDocEntry(path, kPreviewEntry), [1, 2, 3, 4]);
      expect(utf8.decode(readDocEntry(path, 'sketches/Sketch1.dxf')!), 'DXF');
      expect(readDocMeta(path)!['name'], 'Bracket');
      expect(readDocEntry(path, 'absent.json'), isNull);
      dir.deleteSync(recursive: true);
    });

    test('a document with no preview reports none rather than empty bytes', () {
      final dir = _scratch('nopre');
      final path = '${dir.path}/Bracket.$kPartExt';
      writeDoc(path, DocFile('part', {kMetaEntry: utf8.encode('{}')}));
      expect(readDocEntry(path, kPreviewEntry), isNull);
      dir.deleteSync(recursive: true);
    });

    test('a truncated document reads as nothing rather than garbage', () {
      final dir = _scratch('trunc');
      final path = '${dir.path}/Bracket.$kPartExt';
      writeDoc(
          path,
          DocFile('part', {
            kMetaEntry: utf8.encode('{"name":"Bracket"}'),
            kPreviewEntry: Uint8List.fromList(List.filled(500, 9)),
          }));
      final all = File(path).readAsBytesSync();
      File(path).writeAsBytesSync(all.sublist(0, all.length - 400));
      // The header still parses — it is intact — but the clipped blob must not
      // come back as a short read pretending to be a PNG.
      expect(readDocEntry(path, kPreviewEntry), isNull);
      expect(readDocMeta(path)!['name'], 'Bracket');
      dir.deleteSync(recursive: true);
    });
  });
}
