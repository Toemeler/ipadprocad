// M176 — one document, one file.
//
// A part was a FOLDER: a .part.json beside a sketches/ directory, a preview
// and an imports/ tree. On an iPad a document is something you move, rename
// and AirDrop, and you can do none of that with a directory only this app
// knows how to reassemble.
//
// The container has to survive being treated as a file by a file manager,
// which means every failure mode here is "someone handed us bytes": a foreign
// file, a truncated one, a lying index. None of them may throw — a gallery
// listing a folder must not crash on a stray PDF.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/doc_file.dart';

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  group('M176 — round trip', () {
    test('a part with a sketch, a preview and metadata comes back whole', () {
      final doc = DocFile('part', {
        'meta.json': _b('{"name":"Bracket","features":2}'),
        'sketches/Sketch1.dxf': _b('0\nSECTION\n'),
        'preview.png': Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]),
      });
      final back = DocFile.decode(doc.encode())!;
      expect(back.kind, 'part');
      expect(back.entries.keys.toSet(), doc.entries.keys.toSet());
      expect(back.textOf('sketches/Sketch1.dxf'), '0\nSECTION\n');
      expect(back.entries['preview.png']!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47],
          reason: 'binary is stored RAW — no base64, which is what keeps it fast');
      expect(back.meta!['name'], 'Bracket');
    });

    test('a sketch document round-trips too', () {
      final doc = DocFile('sketch', {'meta.json': _b('{"name":"Plate"}')});
      expect(DocFile.decode(doc.encode())!.kind, 'sketch');
    });

    test('an empty document is still a valid one', () {
      final back = DocFile.decode(const DocFile('part', {}).encode())!;
      expect(back.entries, isEmpty);
      expect(back.meta, isNull);
    });

    test('entry order does not matter — the index carries the offsets', () {
      final a = DocFile('part', {'z': _b('one'), 'a': _b('two')}).encode();
      final back = DocFile.decode(a)!;
      expect(back.textOf('z'), 'one');
      expect(back.textOf('a'), 'two');
    });

    test('a large binary entry is byte-exact', () {
      final big = Uint8List.fromList(List.generate(50000, (i) => i % 256));
      final back = DocFile.decode(DocFile('part', {'p.png': big}).encode())!;
      expect(back.entries['p.png'], big);
    });
  });

  group('M176 — bad input is reported, never thrown', () {
    test('a foreign file is simply not ours', () {
      expect(DocFile.decode(_b('%PDF-1.4 ...')), isNull);
      expect(DocFile.decode(Uint8List(0)), isNull);
      expect(DocFile.decode(Uint8List(4)), isNull);
    });

    test('a truncated document does not throw', () {
      final full = DocFile('part', {'a': _b('hello there')}).encode();
      for (final cut in [9, 12, 20, full.length - 3]) {
        expect(() => DocFile.decode(full.sublist(0, cut)), returnsNormally);
      }
    });

    test('an index pointing past the end drops that entry, keeps the rest', () {
      final doc = DocFile('part', {'good': _b('abc'), 'bad': _b('defgh')});
      final bytes = doc.encode();
      // Corrupt the LAST entry's length by extending the file's own claim:
      // rebuild the header with a bogus length for 'good'.
      final head = jsonEncode({
        'v': 1,
        'kind': 'part',
        'entries': [
          {'n': 'good', 'o': 0, 'l': 3},
          {'n': 'bad', 'o': 3, 'l': 999999},
        ],
      });
      final hb = utf8.encode(head);
      final out = BytesBuilder()
        ..add(bytes.sublist(0, 8))
        ..add((ByteData(4)..setUint32(0, hb.length, Endian.little))
            .buffer
            .asUint8List())
        ..add(hb)
        ..add(_b('abcdefgh'));
      final back = DocFile.decode(out.takeBytes())!;
      expect(back.textOf('good'), 'abc', reason: 'the sound entry survives');
      expect(back.entries.containsKey('bad'), isFalse,
          reason: 'the lying one is dropped, not read past the buffer');
    });

    test('a corrupt meta.json reads as absent rather than exploding', () {
      final back =
          DocFile.decode(DocFile('part', {'meta.json': _b('{oh dear')}).encode())!;
      expect(back.meta, isNull);
    });
  });

  group('M176 — the extensions', () {
    test('they mirror Inventor: three letters, part and sketch', () {
      expect(kPartExt, 'ptp');
      expect(kSketchExt, 'pts');
    });

    test('a name is recovered from a path', () {
      expect(docNameOf('/a/b/Bracket.ptp'), 'Bracket');
      expect(docNameOf('Plate.pts'), 'Plate');
      expect(docNameOf('/a/My Part.PTP'), 'My Part',
          reason: 'a file manager may hand back any case');
    });

    test('a name containing a dot survives', () {
      expect(docNameOf('/a/v1.2 bracket.ptp'), 'v1.2 bracket');
    });

    test('anything else is not one of ours', () {
      expect(docNameOf('/a/b/notes.txt'), isNull);
      expect(docNameOf('/a/b/drawing.dxf'), isNull);
      expect(docNameOf('ptp'), isNull);
    });

    test('part and sketch paths are told apart', () {
      expect(isPartPath('/x/A.ptp'), isTrue);
      expect(isPartPath('/x/A.pts'), isFalse);
    });
  });
}
