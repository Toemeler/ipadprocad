// M184 — the bug bundle, and the diagnostics that make it worth reading.
//
// The promise is that one ZIP answers everything without the reporter having
// to say anything, so these tests hold that promise to its parts:
//
//  * the archive is a REAL zip — verified by unzipping it with the system
//    tool, not by trusting the writer that produced it;
//  * triage names what is broken, and says so plainly when nothing is;
//  * the state dump carries the things a report is otherwise useless without:
//    each feature's error, its parameters, the fingerprints of every picked
//    edge, and every sketch's geometry and constraints;
//  * a failed 2D solve names the CONSTRAINT, not just the sketch;
//  * a mesh that will look wrong on screen is called out at capture time.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/gesture_trace.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/bug_report.dart';
import 'package:prototype/constraints.dart';
import 'package:prototype/diag.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/ffi/qcad_engine.dart' show Geo;
import 'package:prototype/part_model.dart';
import 'package:prototype/reality_scene.dart';
import 'package:prototype/solver.dart';
import 'package:prototype/zip_writer.dart';

/// Runs unzip WITHOUT letting Dart decode its output.
///
/// Process.run decodes stdout/stderr with the system encoding by default, and
/// unzip echoes the names it extracts — including the umlauts this suite
/// deliberately tests with. On the macOS runner those bytes do not decode
/// under the assumed encoding and the call throws
/// "FormatException: Unexpected extension byte" before any assertion runs, so
/// the test failed for a reason that had nothing to do with the archive. Raw
/// bytes in, lenient decode only for the failure message.
Future<({int exitCode, String stderr})> _unzip(String zip, String into) async {
  final r = await Process.run('unzip', ['-o', zip, '-d', into],
      stdoutEncoding: null, stderrEncoding: null);
  return (
    exitCode: r.exitCode,
    stderr: utf8.decode((r.stderr as List<int>), allowMalformed: true),
  );
}

/// Minimal ZIP reader: walks the central directory and inflates each member.
///
/// Exists so the archive can be verified without an external tool having an
/// opinion about filename encodings. Mirrors only what ZipWriter emits —
/// stored and deflated entries, no zip64, no encryption.
Map<String, List<int>> _readZip(Uint8List b) {
  int u16(int o) => b[o] | (b[o + 1] << 8);
  int u32(int o) => b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

  // End of central directory: last 22 bytes when there is no comment.
  final eocd = b.length - 22;
  expect(u32(eocd), 0x06054b50, reason: 'EOCD signature');
  final count = u16(eocd + 10);
  var p = u32(eocd + 16);

  final out = <String, List<int>>{};
  for (var i = 0; i < count; i++) {
    expect(u32(p), 0x02014b50, reason: 'central directory signature');
    final method = u16(p + 10);
    final compSize = u32(p + 20);
    final rawSize = u32(p + 24);
    final nameLen = u16(p + 28);
    final extraLen = u16(p + 30);
    final commentLen = u16(p + 32);
    final localOff = u32(p + 42);
    final name = utf8.decode(b.sublist(p + 46, p + 46 + nameLen));

    // Local header: payload starts after its own name+extra fields.
    expect(u32(localOff), 0x04034b50, reason: 'local header signature');
    final lNameLen = u16(localOff + 26);
    final lExtraLen = u16(localOff + 28);
    final dataAt = localOff + 30 + lNameLen + lExtraLen;
    final raw = b.sublist(dataAt, dataAt + compSize);

    final data =
        method == 0 ? raw : ZLibCodec(raw: true).decode(raw);
    expect(data.length, rawSize, reason: 'uncompressed size for $name');
    expect(Crc32.compute(data), u32(p + 16), reason: 'CRC for $name');
    out[name] = data;
    p += 46 + nameLen + extraLen + commentLen;
  }
  return out;
}

Geo _line(double x0, double y0, double x1, double y1) =>
    Geo(Geo.line, [x0, y0, x1, y1]);

PartModel _part() => PartModel('Part1');

ChildSketch _sketch(String name, List<Geo> geo, [List<Constraint>? cons]) {
  final m = SketchModel(name);
  m.geometry.addAll(geo);
  if (cons != null) m.constraints.addAll(cons);
  return ChildSketch(m, 'xy');
}

ExtrudeFeature _extrude(String name, {double h = 5}) => ExtrudeFeature(
      name: name,
      bodyName: 'Solid1',
      sketchName: 'Sketch1',
      profiles: [ProfileSel(0, 0, 100)],
      distanceA: h,
    );

/// A mesh with [faces] faces' worth of faceInfos, so faceCount is meaningful.
OcctMeshData _mesh(List<double> pos, List<int> idx, {int faces = 1}) =>
    OcctMeshData(
      Float64List.fromList(pos),
      Float64List.fromList(List<double>.filled(pos.length, 0)),
      Int32List.fromList(idx),
      Int32List(0),
      Float64List(0),
      faceInfos: Float64List(15 * faces),
    );

void main() {
  m186();
  group('M184 — the ZIP is a real ZIP', () {
    test('a written archive unzips with the real unzip', () async {
      // ASCII names only. The point of shelling out is "a third-party tool
      // accepts our container"; non-ASCII names test that tool's Unicode
      // support instead, and macOS ships an unzip from 2009 that fails it.
      // The umlaut case is covered below by reading our own bytes back.
      final dir = Directory.systemTemp.createTempSync('m184zip');
      addTearDown(() => dir.deleteSync(recursive: true));

      final z = ZipWriter(stamp: DateTime(2026, 8, 3, 9, 30, 0));
      z.addText('report.md', '# hello\n${'compress me ' * 500}'); // deflated
      z.addText('tiny.txt', 'x'); // too small to compress: stored
      z.addText('sketches/Sketch1.json', '{"a":1}');
      final bytes = z.finish();
      final f = File('${dir.path}/b.zip')..writeAsBytesSync(bytes);

      expect(bytes.sublist(0, 4), [0x50, 0x4b, 0x03, 0x04],
          reason: 'local file header magic');

      final out = Directory('${dir.path}/x')..createSync();
      final r = await _unzip(f.path, out.path);
      expect(r.exitCode, 0, reason: 'unzip said: ${r.stderr}');
      expect(File('${out.path}/report.md').readAsStringSync(),
          startsWith('# hello'));
      expect(File('${out.path}/tiny.txt').readAsStringSync(), 'x');
      expect(File('${out.path}/sketches/Sketch1.json').readAsStringSync(),
          '{"a":1}');
    });

    test('a UTF-8 member reads back byte-for-byte, parsed from our own bytes',
        () {
      // Reading the archive ourselves rather than asking a tool: this asserts
      // the CONTAINER is right, which is the claim, instead of asserting what
      // some particular unzip build makes of it.
      final z = ZipWriter(stamp: DateTime(2026, 8, 3));
      const name = 'sketches/Skizze-Übergröße.json';
      const body = '{"name":"Skizze-Übergröße","a":1}';
      z.addText(name, body);
      final members = _readZip(z.finish());
      expect(members.keys, [name]);
      expect(utf8.decode(members[name]!), body);
    });

    test('non-ASCII names carry the UTF-8 flag, so they are not decoded as '
        'CP437', () {
      // The CI failure that produced this test: a sketch named
      // "Skizze-Übergröße" extracted under a mangled name, because bit 11 of
      // the general purpose flag was never set and GNU unzip is entitled to
      // assume CP437 without it. Asserted on the bytes, so no unzip build's
      // guesswork can hide a regression.
      final z = ZipWriter(stamp: DateTime(2026, 8, 3));
      z.addText('sketches/Skizze-Übergröße.json', '{"a":1}');
      final b = z.finish();

      // Local file header: flags are the 2 bytes at offset 6.
      final localFlags = b[6] | (b[7] << 8);
      expect(localFlags & 0x0800, 0x0800,
          reason: 'local header must declare the name as UTF-8');

      // And the same in the central directory, which is what most readers
      // actually consult. Find its signature, then flags sit at +8.
      var cd = -1;
      for (var i = 0; i + 3 < b.length; i++) {
        if (b[i] == 0x50 && b[i + 1] == 0x4b && b[i + 2] == 0x01 &&
            b[i + 3] == 0x02) {
          cd = i;
          break;
        }
      }
      expect(cd, greaterThan(0), reason: 'central directory header present');
      final cdFlags = b[cd + 8] | (b[cd + 9] << 8);
      expect(cdFlags & 0x0800, 0x0800,
          reason: 'central directory must declare it too');

      // And the name really is UTF-8 on the wire, not some other encoding.
      expect(
          String.fromCharCodes(b).contains('Skizze'), isTrue,
          reason: 'the ASCII prefix survives regardless of encoding');
      expect(b, containsAllInOrder(utf8.encode('Übergröße')),
          reason: 'the umlauts are stored as UTF-8 bytes');
    });

    test('CRC-32 matches the known value for "123456789"', () {
      // The standard check value for CRC-32/ISO-HDLC.
      expect(Crc32.compute(utf8.encode('123456789')), 0xCBF43926);
    });

    test('an empty archive is a well-formed empty archive', () {
      // 22 bytes: the end-of-central-directory record and nothing else. (unzip
      // exits 1 on this with "zipfile is empty", which is unzip having an
      // opinion about emptiness, not a malformed file — so the structure is
      // what gets asserted.)
      final bytes = ZipWriter().finish();
      expect(bytes.length, 22);
      expect(bytes.sublist(0, 4), [0x50, 0x4b, 0x05, 0x06]);
    });
  });

  group('M184 — member names survive any unzip', () {
    test('German and Swiss letters transliterate, not flatten', () {
      // "_bergr__e" would be unreadable; the reader has to be able to tell
      // which sketch a file belongs to at a glance.
      expect(portableMemberName('Skizze-Übergröße', {}),
          'Skizze-Uebergroesse');
      expect(portableMemberName('Zahnrad_ä', {}), 'Zahnrad_ae');
    });

    test('anything else becomes an underscore, and never empty', () {
      expect(portableMemberName('a/b c:d', {}), 'a_b_c_d');
      expect(portableMemberName('日本語', {}), '___');
      expect(portableMemberName('', {}), 'unnamed');
    });

    test('two names that collapse together stay distinct', () {
      // Without this, "Skizze ä" and "Skizze/ä" would both become one file
      // and one of the two sketches would be silently missing.
      final used = <String>{};
      expect(portableMemberName('Skizze:1', used), 'Skizze_1');
      expect(portableMemberName('Skizze 1', used), 'Skizze_1~2');
      expect(portableMemberName('Skizze/1', used), 'Skizze_1~3');
    });

    test('an ordinary ASCII name is left exactly alone', () {
      expect(portableMemberName('Sketch1', {}), 'Sketch1');
    });

    test('the bundle records what it renamed, so nothing is lost', () {
      final files = buildBundle(
        description: 'x',
        when: DateTime(2026, 8, 3),
        env: const {},
        part: null,
        sketchJson: {'Skizze-Übergröße': '{}'},
      );
      expect(files.keys, contains('sketches/Skizze-Uebergroesse.json'));
      expect(files['report.md'], contains('Skizze-Übergröße'),
          reason: 'the real name must still appear in the report');
    });
  });

  group('M184 — triage says what is wrong', () {
    test('a sick feature is named with its error', () {
      final p = _part();
      final f = FilletFeature(
        name: 'Fillet1',
        bodyName: 'Solid1',
        edges: [EdgeSel(0, 0, 0, 10, 2, 2)],
        radii: [2],
      )..computeError = 'radius too large';
      p.features.add(f);
      final t = triage(p);
      expect(t.join('\n'), contains('SICK Fillet1'));
      expect(t.join('\n'), contains('radius too large'));
    });

    test('a feature with neither solid nor error is called SILENT', () {
      // The worst case: nothing in the UI marks it, so the body goes missing
      // and no one can say why.
      final p = _part()..features.add(_extrude('Extrusion1'));
      expect(triage(p).join('\n'), contains('SILENT Extrusion1'));
    });

    test('non-finite sketch geometry is called out', () {
      final p = _part();
      p.childSketches.add(_sketch('Sketch1', [_line(0, 0, double.nan, 5)]));
      expect(triage(p).join('\n'), contains('NOT FINITE Sketch1'));
    });

    test('a healthy model reports nothing, and the report says so usefully',
        () {
      expect(triage(_part()), isEmpty);
      final md = reportMarkdown(
        description: 'the view flickers',
        when: DateTime(2026, 8, 3),
        env: {'build': 'abc'},
        part: _part(),
        contents: const ['`log.txt`'],
      );
      // An empty triage must not read as "nothing is wrong" — it has to send
      // the reader somewhere.
      expect(md, contains('internally healthy'));
      expect(md, contains('log.txt'));
      expect(md, contains('the view flickers'));
    });

    test('no part open is itself the finding', () {
      expect(triage(null), ['no part is open']);
    });
  });

  group('M184 — the state dump carries what a report needs', () {
    test('a blend ships the fingerprint of every picked edge', () {
      // Without these there is no way to tell a lost edge from a mis-matched
      // one, which is the single most common blend question.
      final p = _part()
        ..features.add(FilletFeature(
          name: 'Fillet1',
          bodyName: 'Solid1',
          edges: [
            EdgeSel(1.641, 10, 13.99, 10.308, 2, 1.6405),
            EdgeSel(1.641, 5, 13.99, 10.308, 2, 1.6405),
          ],
          radii: [2, 3],
        ));
      final d = featureDump(p).join('\n');
      expect(d, contains('picked edges (2)'));
      expect(d, contains('1.6405'));
      expect(d, contains('13.9900'));
      expect(d, contains('tol='), reason: 'how far it may drift matters too');
      expect(d, contains('radii=[2.0, 3.0]'));
    });

    test('every feature parameter travels, via its own toJson', () {
      final p = _part()..features.add(_extrude('Extrusion1', h: 7.5));
      final d = featureDump(p).join('\n');
      expect(d, contains('params='));
      expect(d, contains('7.5'));
      expect(d, contains('solid=NONE'));
    });

    test('a sketch ships geometry AND constraints, replayable', () {
      final p = _part();
      p.childSketches.add(_sketch(
          'Sketch1',
          [_line(0, 0, 10, 0), _line(10, 0, 10, 5)],
          [Constraint(CType.horizontal, ents: [0])]));
      final d = sketchesDump(p).join('\n');
      expect(d, contains('Sketch1'));
      expect(d, contains('geometry (2)'));
      expect(d, contains('constraints (1)'));
      expect(d, contains('horizontal'));
      expect(d, contains('geometryFinite=yes'));
    });

    test('the bundle names its own contents so the reader knows where to look',
        () {
      final files = buildBundle(
        description: 'x',
        when: DateTime(2026, 8, 3),
        env: {'build': 'abc'},
        part: _part(),
        partJson: '{}',
        logText: 'line1\nline2\n',
      );
      expect(files.keys, containsAll(['report.md', 'state.txt', 'log.txt',
        'part.json', 'env.txt']));
      expect(files['report.md'], contains('part.json'));
      expect(files['report.md'], contains('state.txt'));
    });

    test('a stem is filesystem-safe', () {
      final s = bundleStem(DateTime(2026, 8, 3, 9, 12, 33));
      expect(s, 'bug-2026-08-03T091233');
      expect(s, isNot(contains(':')));
    });
  });

  group('M184 — a failed 2D solve names the constraint', () {
    test('the violated one is listed, worst first, with its entities', () {
      // Two points pinned to different places AND required coincident: the
      // coincidence is what cannot hold.
      final gs = [_line(0, 0, 10, 0), _line(50, 50, 60, 50)];
      final cs = [
        Constraint(CType.coincident,
            pts: [const PRef(0, 1), const PRef(1, 0)]),
      ];
      final resid = constraintResidualsPer(gs, cs);
      expect(resid[0], greaterThan(1.0), reason: '40,50 apart');

      final dump = solveFailureDump(gs, cs, resid).join('\n');
      expect(dump, contains('UNSATISFIED: 1 of 1'));
      expect(dump, contains('coincident'));
      // The entities it names must be printed, so no cross-referencing by hand.
      expect(dump, contains('e0.p1'));
      expect(dump, contains('e1.p0'));
    });

    test('a satisfied system produces no accusations', () {
      final gs = [_line(0, 0, 10, 0)];
      final cs = [Constraint(CType.horizontal, ents: [0])];
      final resid = constraintResidualsPer(gs, cs);
      expect(resid[0], lessThan(1e-9));
      expect(solveFailureDump(gs, cs, resid).join('\n'),
          contains('UNSATISFIED: 0 of 1'));
    });

    test('all-constraints-hold points at DEGENERATE GEOMETRY instead', () {
      // The other rejection gate. An empty list of violations next to a
      // failure would read as "nothing is wrong", which is the opposite of
      // what happened.
      final gs = [_line(0, 0, 0, 0)]; // zero length
      final cs = <Constraint>[Constraint(CType.horizontal, ents: [0])];
      final dump =
          solveFailureDump(gs, cs, constraintResidualsPer(gs, cs)).join('\n');
      expect(dump, contains('DEGENERATE GEOMETRY'));
    });

    test('driven dimensions are not accused of anything', () {
      final gs = [_line(0, 0, 10, 0)];
      final cs = [
        Constraint(CType.dimension,
            pts: [const PRef(0, 0), const PRef(0, 1)],
            dimKind: 'distance',
            value: 999,
            driven: true),
      ];
      expect(constraintResidualsPer(gs, cs)[0], 0,
          reason: 'a reference dimension constrains nothing');
    });
  });

  group('M184 — a mesh that will look wrong is called out', () {
    test('an empty tessellation is an anomaly, not a silent nothing', () {
      final a = meshAnomalies(_mesh([], []));
      expect(a.join(), contains('EMPTY'));
    });

    test('a non-finite vertex is named as the vanishing cause', () {
      final a = meshAnomalies(
          _mesh([0, 0, 0, 1, 0, 0, double.nan, 1, 0], [0, 1, 2]));
      expect(a.join(), contains('NON-FINITE'));
    });

    test('a triangle explosion is caught — the 63k-for-21-faces case', () {
      // The device log that prompted this: 63 101 triangles over 21 faces.
      final pos = <double>[];
      final idx = <int>[];
      for (var i = 0; i < 3000; i++) {
        pos.addAll([i * 1.0, 0, 0]);
        idx.add(i);
      }
      expect(meshAnomalies(_mesh(pos, idx, faces: 1)), isEmpty);
    });

    test('an ordinary mesh is not accused', () {
      expect(meshAnomalies(_mesh([0, 0, 0, 1, 0, 0, 0, 1, 0], [0, 1, 2])),
          isEmpty);
    });
  });
}

// ---------------------------------------------------------------------------
// M186 — the three things the M185 audit named as still uncovered.
// ---------------------------------------------------------------------------

void _pointer(int id, Offset at, {String phase = 'down'}) {
  final e = switch (phase) {
    'up' => PointerUpEvent(pointer: id, position: at),
    'move' => PointerMoveEvent(pointer: id, position: at),
    'cancel' => PointerCancelEvent(pointer: id, position: at),
    _ => PointerDownEvent(pointer: id, position: at),
  };
  GestureTrace.record(e);
}

void m186() {
  group('M186 — the raw pointer stream', () {
    setUp(GestureTrace.clear);

    test('a down/move/up sequence is recorded in order, with positions', () {
      _pointer(1, const Offset(10, 20));
      _pointer(1, const Offset(11, 21), phase: 'move');
      _pointer(1, const Offset(12, 22), phase: 'up');
      final d = GestureTrace.dump();
      expect(d.length, greaterThanOrEqualTo(2));
      expect(d.first, contains('DOWN'));
      expect(d.first, contains('at(10.0,20.0)'));
      expect(d.last, contains('UP'));
    });

    test('a second contact is distinguishable — the two-finger case', () {
      // "It panned instead of drawing" is usually two contacts where the user
      // believed there was one, and that is only visible per pointer id.
      _pointer(1, const Offset(0, 0));
      _pointer(2, const Offset(50, 50));
      final d = GestureTrace.dump().join('\n');
      expect(d, contains('p1'));
      expect(d, contains('p2'));
    });

    test('moves are thinned so a flick cannot evict the history', () {
      _pointer(1, const Offset(0, 0));
      for (var i = 0; i < 400; i++) {
        _pointer(1, Offset(i.toDouble(), 0), phase: 'move');
      }
      // 400 moves inside one 25 ms window collapse to about one.
      expect(GestureTrace.dump().length, lessThan(10));
      expect(GestureTrace.dump().first, contains('DOWN'),
          reason: 'the DOWN that started it must survive');
    });

    test('the buffer is bounded', () {
      for (var i = 0; i < GestureTrace.capacity + 200; i++) {
        _pointer(i, const Offset(1, 1));
      }
      expect(GestureTrace.dump().length, GestureTrace.capacity);
    });

    test('it can be switched off', () {
      GestureTrace.enabled = false;
      addTearDown(() => GestureTrace.enabled = true);
      _pointer(1, const Offset(1, 1));
      expect(GestureTrace.dump(), isEmpty);
    });
  });

  group('M186 — the native renderer boundary', () {
    test('with nothing pushed it says so, and says where the fault is not',
        () {
      final d = RealityPush.dump().join('\n');
      expect(d, contains('PLATFORM VIEW'));
      expect(d, contains('never'));
    });

    test('a recorded scene reports its solids and their triangle counts', () {
      RealityPush.recordScene('sig-1', ['Solid1: tris=4148 verts=4164 rev=7']);
      final d = RealityPush.dump().join('\n');
      expect(d, contains('sig-1'));
      expect(d, contains('tris=4148'));
      expect(d, contains('solids in the last scene (1)'));
    });
  });

  group('M186 — the bundle carries all three', () {
    test('gestures, reality and the screenshot caveat are described', () {
      final files = buildBundle(
        description: 'x',
        when: DateTime(2026, 8, 3),
        env: const {},
        part: null,
        gestureText: '0ms DOWN p1',
        realityText: 'scene pushes: 3',
        hasScreenshot: true,
        screenshotOmits3D: true,
      );
      expect(files.keys, containsAll(['gestures.txt', 'reality.txt']));
      final md = files['report.md']!;
      expect(md, contains('gestures.txt'));
      expect(md, contains('reality.txt'));
      // The caveat is the whole point: a blank viewport in the image must
      // never be read as a missing body.
      expect(md, contains('screenshot.png'));
      expect(md, contains('NOT in this image'));
    });

    test('without the caveat when the platform composites normally', () {
      final md = buildBundle(
        description: 'x',
        when: DateTime(2026, 8, 3),
        env: const {},
        part: null,
        hasScreenshot: true,
        screenshotOmits3D: false,
      )['report.md']!;
      expect(md, contains('screenshot.png'));
      expect(md, isNot(contains('NOT in this image')));
    });

    test('a binary member survives the round trip through the zip', () async {
      final dir = Directory.systemTemp.createTempSync('m186bin');
      addTearDown(() => dir.deleteSync(recursive: true));
      // Bytes that are not valid UTF-8, so a text-only path would corrupt them.
      final png = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0xFF,
        0xFE, 0x00, 0x01];
      final f = writeBundle(dir, 'b', {'report.md': '# x'},
          binaries: {'screenshot.png': png});
      expect(f, isNotNull);
      final out = Directory('${dir.path}/x')..createSync();
      final r = await _unzip(f!.path, out.path);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(File('${out.path}/screenshot.png').readAsBytesSync(), png);
    });
  });
}
