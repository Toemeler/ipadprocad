// M390 — "menu preview images dont work on windows".
//
// The gallery card falls back to its cube glyph when [readDocEntry] cannot
// find `preview.png` inside the document, and inside every document the
// Windows build has ever written that entry is called `\preview.png`.
//
// WHERE THE BACKSLASH COMES FROM. `packDir` derives each entry's name by
// slicing the staging folder's path off the front of the file's path:
//
//     var rel = f.path.substring(dir.path.length);
//     while (rel.startsWith('/')) rel = rel.substring(1);
//
// `Directory.list` joins a parent and a child with the PLATFORM separator —
// dart:io appends one itself before calling the native lister
// (FileSystemEntity._ensureTrailingPathSeparators, which on Windows appends
// `\`) — so a stage at `C:/…/docs/Bracket` produces
// `C:/…/docs/Bracket\preview.png` and the slice is `\preview.png`. The loop
// only ever looked for a forward slash, so it stayed.
//
// NO TEST HOST CAN PRODUCE THAT PATH, which is exactly why it shipped: the
// suite runs on Linux and macOS, where the same code is correct. So the slice
// is a pure function now ([docEntryNameFor]) and these hand it the path
// Windows would have handed it.
//
// The damage was not only cosmetic, and the rest of this file is the rest of
// it:
//
//   * `readDocMeta` was as blind as the preview reader;
//   * `unpackDoc` DROPPED such entries — `_safeRelative` rejects any name with
//     a backslash in it, and it is right to, because `..\..\x` from a document
//     someone sent you must not escape. So a document written on Windows
//     unpacked to an empty folder in any later session. It never bit only
//     because `_commitStage` marks a document staged as it saves.
//
// Both are read-side, so the fix repairs the documents already on disk rather
// than only the ones written from here on. That is what the "already written"
// group asserts.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/doc_file.dart';
import 'package:prototype/doc_store.dart';
import 'package:prototype/platform/app_dirs.dart';

/// The staging folder path shape the Windows build actually has: built with
/// forward slashes by AppState._stage, on a drive-letter root.
const String _winStage = r'C:/Users/t/AppData/Roaming/prototype/cache/docs/Bracket';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  group('the name an entry gets when the platform joins with a backslash', () {
    test('a file at the top of the stage', () {
      expect(docEntryNameFor(_winStage, '$_winStage\\preview.png'),
          'preview.png');
    });

    test('a file in a subfolder — every separator, not just the first', () {
      expect(docEntryNameFor(_winStage, '$_winStage\\sketches\\Sketch1.dxf'),
          'sketches/Sketch1.dxf');
      expect(docEntryNameFor(_winStage, '$_winStage\\imports\\flange.step'),
          'imports/flange.step');
    });

    test('and POSIX is untouched', () {
      const stage = '/home/u/.cache/prototype/docs/Bracket';
      expect(docEntryNameFor(stage, '$stage/preview.png'), 'preview.png');
      expect(docEntryNameFor(stage, '$stage/sketches/Sketch1.dxf'),
          'sketches/Sketch1.dxf');
    });

    test('a name that is already right is left alone', () {
      for (final n in ['preview.png', 'meta.json', 'sketches/Sketch1.dxf']) {
        expect(docEntryName(n), n);
      }
    });
  });

  group('a document already written on Windows becomes readable', () {
    // Built by hand rather than by packDir, because packDir cannot be made to
    // produce these names on this host — this IS the file sitting in the
    // user's app folder.
    DocFile windowsWritten() => DocFile('part', {
          '\\meta.json': _bytes('{"name":"Bracket"}'),
          '\\preview.png': _bytes('PNG-ish'),
          '\\sketches\\Sketch1.dxf': _bytes('0\nSECTION\n'),
        });

    test('decode gives the names every reader in the app asks for', () {
      final doc = DocFile.decode(windowsWritten().encode())!;
      expect(doc.entries.keys.toSet(),
          {'meta.json', 'preview.png', 'sketches/Sketch1.dxf'});
      // The report, at the layer underneath it.
      expect(doc.entries['preview.png'], isNotNull);
      expect(doc.meta?['name'], 'Bracket');
    });

    test('the header reader — what the GALLERY uses — finds the preview',
        () async {
      final dir = Directory.systemTemp.createTempSync('m390');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/Bracket.ptp';
      expect(writeDoc(path, windowsWritten()), isTrue);

      // readDocHeader parses the index alone; listing a gallery of parts must
      // never read a payload. This is the call _thumbFor makes.
      expect(readDocEntry(path, kPreviewEntry), _bytes('PNG-ish'));
      expect(readDocMeta(path)?['name'], 'Bracket');
      expect(readDocHeader(path)!.entry(kMetaEntry), isNotNull);
    });

    test('unpacking puts every entry back instead of dropping them all', () {
      final dir = Directory.systemTemp.createTempSync('m390u');
      addTearDown(() => dir.deleteSync(recursive: true));
      // Through encode/decode, which is the only way the app ever gets here:
      // _ensureStaged unpacks what readDoc handed it. The normalisation lives
      // in decode, so unpackDoc's own guard stays exactly as strict as it was.
      unpackDoc(DocFile.decode(windowsWritten().encode())!, dir);

      expect(File('${dir.path}/meta.json').existsSync(), isTrue,
          reason: 'without meta.json the document opens as an empty part');
      expect(File('${dir.path}/preview.png').existsSync(), isTrue);
      expect(File('${dir.path}/sketches/Sketch1.dxf').readAsStringSync(),
          '0\nSECTION\n');
    });
  });

  group('and a hostile document still cannot escape the folder', () {
    // The backslash rejection was doing real work; normalising it away without
    // keeping the traversal check would have turned a cosmetic fix into a
    // write-anywhere primitive. `..` is caught whichever separator wrote it.
    test('traversal is refused in both spellings', () {
      final dir = Directory.systemTemp.createTempSync('m390x');
      addTearDown(() => dir.deleteSync(recursive: true));
      final outside = File('${dir.parent.path}/m390-escaped.txt');
      if (outside.existsSync()) outside.deleteSync();

      unpackDoc(
          DocFile('part', {
            '../m390-escaped.txt': _bytes('no'),
            r'..\m390-escaped.txt': _bytes('no'),
            r'sketches\..\..\m390-escaped.txt': _bytes('no'),
            '/etc/m390-escaped.txt': _bytes('no'),
            'meta.json': _bytes('{}'),
          }),
          dir);

      expect(outside.existsSync(), isFalse,
          reason: 'a document is a file people send each other');
      // The legitimate entry beside them still lands.
      expect(File('${dir.path}/meta.json').existsSync(), isTrue);
      // And NOTHING else lands: an absolute name is refused outright rather
      // than relativised into the folder, which is what it was before M390
      // and what it stays.
      expect(dir.listSync().length, 1);
    });
  });

  // THE ONE TEST THAT HAS TO RUN ON WINDOWS TO MEAN ANYTHING.
  //
  // Everything above hands [docEntryNameFor] a path with backslashes in it,
  // because a Linux host cannot make `Directory.list` produce one. This packs
  // a REAL directory through the REAL listing, so on the Windows runner it
  // exercises the join that caused all of this — and it is why
  // windows-build.yml runs this one file, which it otherwise runs no tests
  // from at all.
  group('packDir names entries the same way on every platform', () {
    test('a stage with a preview and a subfolder', () {
      final dir = Directory.systemTemp.createTempSync('m390p');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/meta.json').writeAsStringSync('{"name":"Bracket"}');
      File('${dir.path}/preview.png').writeAsBytesSync(_bytes('PNG-ish'));
      Directory('${dir.path}/sketches').createSync();
      File('${dir.path}/sketches/Sketch1.dxf').writeAsStringSync('0\nSECTION\n');

      final doc = packDir(dir, 'part');
      expect(doc.entries.keys.toSet(),
          {'meta.json', 'preview.png', 'sketches/Sketch1.dxf'},
          reason: 'on Windows these came back as \\meta.json, \\preview.png '
              'and \\sketches\\Sketch1.dxf, and the gallery lost every '
              'thumbnail as a result');
      for (final k in doc.entries.keys) {
        expect(k.contains('\\'), isFalse, reason: k);
        expect(k.startsWith('/'), isFalse, reason: k);
      }
    });

    test('what was packed is what unpacks, byte for byte', () {
      final src = Directory.systemTemp.createTempSync('m390r');
      final dst = Directory.systemTemp.createTempSync('m390r2');
      addTearDown(() {
        src.deleteSync(recursive: true);
        dst.deleteSync(recursive: true);
      });
      File('${src.path}/meta.json').writeAsStringSync('{"name":"Bracket"}');
      Directory('${src.path}/imports').createSync();
      File('${src.path}/imports/flange.step').writeAsStringSync('ISO-10303');

      // The full round trip a save and a later open make.
      final path = '${dst.path}/Bracket.ptp';
      expect(writeDoc(path, packDir(src, 'part')), isTrue);
      final stage = Directory('${dst.path}/stage');
      unpackDoc(readDoc(path)!, stage);

      expect(File('${stage.path}/meta.json').readAsStringSync(),
          '{"name":"Bracket"}');
      expect(File('${stage.path}/imports/flange.step').readAsStringSync(),
          'ISO-10303');
      // And the preview reader the gallery uses finds what the packer wrote.
      expect(readDocMeta(path)?['name'], 'Bracket');
    });
  });

  // ---- the same defect, everywhere else it lives ------------------------
  //
  // `lastIndexOf('/')` and `split('/').last` are correct on iOS, on Linux and
  // on this host, and wrong on Windows for the same reason the packer was.
  // What each site did with the WHOLE PATH instead of the file name differed
  // and none of it was good — see [pathBaseName].
  group('reading a path the platform wrote', () {
    test('pathBaseName takes the last segment, either separator', () {
      expect(pathBaseName(r'C:\Users\t\Desktop\flange.step'), 'flange.step');
      expect(pathBaseName('/home/u/Documents/flange.step'), 'flange.step');
      expect(pathBaseName(r'C:\Users\t/Desktop\mixed.step'), 'mixed.step');
      expect(pathBaseName('flange.step'), 'flange.step');
      // A trailing separator names a folder, not a file in one.
      expect(pathBaseName('/home/u/'), '');
      expect(pathBaseName(r'C:\Users\t\'), '');
    });

    test('pathParent gives the folder, and keeps a usable root', () {
      expect(pathParent(r'C:\Users\t\Desktop\Bracket.ptp'),
          r'C:\Users\t\Desktop');
      expect(pathParent('/home/u/Documents/Bracket.ptp'), '/home/u/Documents');
      // A rename of an external document writes into this. '' would have sent
      // it to the process's working directory, which is what it did.
      expect(pathParent('Bracket.ptp'), '');
      expect(pathParent('/Bracket.ptp'), '/');
      expect(pathParent(r'C:\Bracket.ptp'), r'C:\',
          reason: r'C: alone means "the current directory on C:"');
    });
  });

  group('a path from the Windows file picker names one document', () {
    // docNameOf split on '/' alone, and a picked Windows path has none — so
    // the "document name" was the whole path, which the gallery would have
    // shown and adoptDocument would have tried to use as a file name.
    test('docNameOf takes the last segment either way', () {
      expect(docNameOf(r'C:\Users\t\Desktop\Bracket.ptp'), 'Bracket');
      expect(docNameOf(r'C:\Users\t\Desktop\Sub Folder\A Part.pts'), 'A Part');
      expect(docNameOf('/home/u/Documents/Bracket.ptp'), 'Bracket');
      expect(docNameOf('Bracket.pas'), 'Bracket');
      expect(docNameOf(r'C:\Users\t\Desktop\notes.txt'), isNull);
    });
  });
}
