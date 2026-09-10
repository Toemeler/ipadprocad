// The document `tools/desktop/verify_linux.sh` opens.
//
// That script's checks 5 and 7 — a document crossing between two installs, and
// a document named on the command line opening — both hand the app a real
// `.ptp` from `tools/desktop/testdata/`. A `.ptp` is not JSON on disk: it is
// the packed container `doc_file.dart` writes, and a fixture that stops being
// one fails those checks with "the document was refused", which reads as a
// broken Linux build rather than a stale fixture.
//
// So the fixture is pinned here, against the app's own reader, on the host —
// where it is one cheap test rather than forty minutes of kernels and an X
// server away.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/doc_file.dart';
import 'package:prototype/doc_store.dart';

void main() {
  final path = '${Directory.current.parent.path}'
      '/tools/desktop/testdata/sample.ptp';

  test('the Linux verification fixture is a document this app can open', () {
    final f = File(path);
    expect(f.existsSync(), isTrue, reason: 'missing fixture: $path');

    // The gallery's reader — header only, which is the first thing `openPath`
    // asks and the one that returns null for anything foreign.
    final header = readDocHeader(path);
    expect(header, isNotNull,
        reason: 'readDocHeader refused it, so openPath would too');
    expect(header!.kind, 'part');
    expect(header.entry(kMetaEntry), isNotNull,
        reason: 'a document with no $kMetaEntry has nothing to open');

    // And the whole thing, as the open path itself decodes it.
    final doc = DocFile.decode(f.readAsBytesSync());
    expect(doc, isNotNull);
    final meta = doc!.meta;
    expect(meta, isNotNull, reason: '$kMetaEntry did not decode as JSON');
    expect(meta!['type'], 'part');
    expect(meta['sketches'], isA<List>());
    expect((meta['sketches'] as List), isNotEmpty,
        reason: 'a part with no sketch exercises nothing when it opens');
  });

  test('and it round-trips through the writer it claims to come from', () {
    final doc = DocFile.decode(File(path).readAsBytesSync())!;
    final again = DocFile.decode(doc.encode())!;
    expect(again.kind, doc.kind);
    expect(again.entries.keys.toList(), doc.entries.keys.toList());
    expect(jsonEncode(again.meta), jsonEncode(doc.meta));
  });
}
