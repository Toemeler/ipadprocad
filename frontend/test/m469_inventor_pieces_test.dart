// M469 — the pieces of Inventor import that need no Inventor file and no
// native kernel, so they run on every host. The whole path, on a real part,
// is m468 (machine-local: it needs an .ipt and the kernel).
//
//   * the container: an OLE compound file with RSe segments, zstd inside,
//     segment names read from the meta stream;
//   * the B-rep reader: SAB tags, `{ ref n }` blocks;
//   * a sketch: Inventor's shared points become coincidences, every
//     constraint written holds on Inventor's own geometry, the DXF numbers
//     are written as the app's own writer writes them;
//   * the way back: an .ipt is only ever the untouched original;
//   * the app fixes this work turned up: a sketch point is not a profile, a
//     point keeps its tag through a reload, a stored result survives the
//     last-digit noise of a save.
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/inventor/acis.dart';
import 'package:prototype/inventor/cfb.dart';
import 'package:prototype/inventor/convert.dart';
import 'package:prototype/inventor/dc.dart';
import 'package:prototype/inventor/ipt_file.dart';
import 'package:prototype/inventor/sab.dart';
import 'package:prototype/inventor/sketch_out.dart';
import 'package:prototype/part_model.dart';

// ---------------------------------------------------------------- fixtures
/// A zstd frame holding [data] as one raw block (RFC 8878 3.1.1).
Uint8List zstdRaw(List<int> data) {
  assert(data.length < 256);
  final n = data.length;
  final bh = 1 | (n << 3);
  return Uint8List.fromList([
    0x28, 0xB5, 0x2F, 0xFD, // magic
    0x20, n, // single segment, 1-byte content size
    bh & 0xff, (bh >> 8) & 0xff, (bh >> 16) & 0xff,
    ...data,
  ]);
}

/// A minimal version-3 compound file: every stream below the mini cutoff,
/// so they all live in the mini stream. [streams] maps 'a/b' paths (one
/// storage level at most) to contents.
Uint8List buildCfb(Map<String, List<int>> streams) {
  const ss = 512, ms = 64;
  const free = 0xFFFFFFFF, end = 0xFFFFFFFE, fatSect = 0xFFFFFFFD;
  // directory: root, storages, streams
  final entries = <Map<String, Object>>[
    {'name': 'Root Entry', 'type': 5, 'kids': <int>[]}
  ];
  final storages = <String, int>{};
  final mini = BytesBuilder();
  final miniFat = <int>[];
  for (final e in streams.entries) {
    final parts = e.key.split('/');
    var parent = 0;
    if (parts.length == 2) {
      parent = storages.putIfAbsent(parts[0], () {
        entries.add({'name': parts[0], 'type': 1, 'kids': <int>[]});
        (entries[0]['kids'] as List<int>).add(entries.length - 1);
        return entries.length - 1;
      });
    }
    final start = mini.length ~/ ms;
    final data = e.value;
    final nSect = (data.length + ms - 1) ~/ ms;
    for (var i = 0; i < nSect; i++) {
      miniFat.add(i == nSect - 1 ? end : start + i + 1);
    }
    mini.add(data);
    mini.add(Uint8List(nSect * ms - data.length));
    entries.add({'name': parts.last, 'type': 2, 'start': start, 'size': data.length, 'kids': <int>[]});
    (entries[parent]['kids'] as List<int>).add(entries.length - 1);
  }
  final miniBytes = mini.toBytes();
  // sectors: 0 FAT, 1.. directory, then mini FAT, then the mini stream
  final dirSectors = (entries.length * 128 + ss - 1) ~/ ss;
  final miniFatSectors = (miniFat.length * 4 + ss - 1) ~/ ss;
  final miniStreamSectors = (miniBytes.length + ss - 1) ~/ ss;
  final firstDir = 1, firstMiniFat = 1 + dirSectors, firstMini = firstMiniFat + miniFatSectors;
  final total = firstMini + miniStreamSectors;
  final fat = List<int>.filled(ss ~/ 4, free)..[0] = fatSect;
  void chain(int first, int n) {
    for (var i = 0; i < n; i++) {
      fat[first + i] = i == n - 1 ? end : first + i + 1;
    }
  }

  chain(firstDir, dirSectors);
  chain(firstMiniFat, miniFatSectors);
  chain(firstMini, miniStreamSectors);
  final out = ByteData(ss * (total + 1));
  void u32(int o, int v) => out.setUint32(o, v, Endian.little);
  // header
  const sig = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1];
  for (var i = 0; i < 8; i++) {
    out.setUint8(i, sig[i]);
  }
  out.setUint16(24, 0x3E, Endian.little);
  out.setUint16(26, 3, Endian.little);
  out.setUint16(28, 0xFFFE, Endian.little);
  out.setUint16(30, 9, Endian.little);
  out.setUint16(32, 6, Endian.little);
  u32(44, 1);
  u32(48, firstDir);
  u32(56, 4096);
  u32(60, firstMiniFat);
  u32(64, miniFatSectors);
  u32(68, end);
  for (var i = 0; i < 109; i++) {
    u32(76 + 4 * i, i == 0 ? 0 : free);
  }
  int sector(int s) => ss * (s + 1);
  for (var i = 0; i < fat.length; i++) {
    u32(sector(0) + 4 * i, fat[i]);
  }
  // directory: siblings chained through `right`
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    final o = sector(firstDir) + 128 * i;
    final name = e['name'] as String;
    for (var k = 0; k < name.length; k++) {
      out.setUint16(o + 2 * k, name.codeUnitAt(k), Endian.little);
    }
    out.setUint16(o + 64, 2 * (name.length + 1), Endian.little);
    out.setUint8(o + 66, e['type'] as int);
    out.setUint8(o + 67, 1);
    u32(o + 68, free);
    u32(o + 72, free);
    final kids = e['kids'] as List<int>;
    u32(o + 76, kids.isEmpty ? free : kids.first);
    if (i == 0) {
      u32(o + 116, firstMini);
      u32(o + 120, miniBytes.length);
    } else {
      u32(o + 116, (e['start'] as int?) ?? 0);
      u32(o + 120, (e['size'] as int?) ?? 0);
    }
  }
  for (final e in entries) {
    final kids = e['kids'] as List<int>;
    for (var k = 0; k + 1 < kids.length; k++) {
      u32(sector(firstDir) + 128 * kids[k] + 72, kids[k + 1]);
    }
  }
  for (var i = 0; i < miniFat.length; i++) {
    u32(sector(firstMiniFat) + 4 * i, miniFat[i]);
  }
  final bytes = out.buffer.asUint8List();
  bytes.setRange(sector(firstMini), sector(firstMini) + miniBytes.length, miniBytes);
  return bytes;
}

List<int> utf16(String s) => [for (final c in s.codeUnits) ...[c & 0xff, c >> 8]];

/// SAB bytes, written with the tags of sab.dart.
class SabWriter {
  final b = BytesBuilder();
  void ident(String s) => b.add([0x0d, s.length, ...latin1.encode(s)]);
  void sub(String s) => b.add([0x0e, s.length, ...latin1.encode(s)]);
  void int32(int v) => b.add([0x04, ...(ByteData(4)..setInt32(0, v, Endian.little)).buffer.asUint8List()]);
  void real(double v) => b.add([0x06, ...(ByteData(8)..setFloat64(0, v, Endian.little)).buffer.asUint8List()]);
  void ptr(int v) => b.add([0x0c, ...(ByteData(4)..setInt32(0, v, Endian.little)).buffer.asUint8List()]);
  void str(String s) => b.add([0x07, s.length, ...latin1.encode(s)]);
  void open() => b.add([0x0f]);
  void close() => b.add([0x10]);
  void yes() => b.add([0x0a]);
  void endRecord() => b.add([0x11]);
}

AppSketch rectangleSketch() {
  // Inventor's shared points: four corners, each the end of two lines
  final s = InvSketch('Skizze1', 10)
    ..frame = const Frame(V3(0, 0, 0), V3(1, 0, 0), V3(0, 1, 0), V3(0, 0, 1));
  const corners = {1: (0.0, 0.0), 2: (40.0, 0.0), 3: (40.0, 20.0), 4: (0.0, 20.0)};
  corners.forEach((k, v) => s.points[k] = SkPoint(v.$1, v.$2, false));
  s.points[9] = SkPoint(20, 10, false); // a lone sketch point
  const lines = {5: [1, 2], 6: [2, 3], 7: [3, 4], 8: [4, 1]};
  lines.forEach((k, v) {
    final p0 = corners[v[0]]!, p1 = corners[v[1]]!;
    final l = SkCurve('line', v, const [], false, false, false);
    final len = Offset(p1.$1 - p0.$1, p1.$2 - p0.$2).distance;
    l
      ..origin = p0
      ..dir = ((p1.$1 - p0.$1) / len, (p1.$2 - p0.$2) / len);
    s.curves[k] = l;
  });
  s.constraints
    ..add(SkConstraint('horizontal', line: 5))
    ..add(SkConstraint('vertical', line: 6))
    ..add(SkConstraint('parallel', lines: [5, 7]))
    ..add(SkConstraint('perpendicular', lines: [5, 8]))
    ..add(SkConstraint('endpoint', point: 1, curve: 5));
  s.dimensions
    ..add(SkDimension('d0', [1, 2], 4.0, false)
      ..kind = 'point_point'
      ..value = 40)
    ..add(SkDimension('d1', [5, 7], 2.0, false)
      ..kind = 'line_line'
      ..value = 20);
  return convertSketch(s);
}

void main() {
  group('the container', () {
    test('streams, segment names and zstd come out of a compound file', () {
      final payload = utf8.encode('design data, uncompressed');
      final data = [...List.filled(16, 7), 0x04, 0x02, ...zstdRaw(payload)];
      final meta = [
        ...ascii.encode('RSe Meta Stream Version 8 '),
        ...utf16('PmDCSegment'),
        0, 0,
        ...zstdRaw([1, 2, 3, 4]),
      ];
      final raw = buildCfb({
        'RSeStorage/B4a': data,
        'RSeStorage/M4a': meta,
        'Other': [9, 9, 9],
      });
      final cfb = CfbFile(raw);
      expect(cfb.readPath('Other'), [9, 9, 9]);
      expect(cfb.readPath('RSeStorage/B4a'), data);
      final ipt = IptFile(raw);
      final seg = ipt.segment('PmDCSegment');
      expect(utf8.decode(seg.data), 'design data, uncompressed');
      expect(seg.meta, [1, 2, 3, 4]);
      expect(() => ipt.segment('PmBRepSegment'), throwsA(isA<IptException>()));
    });

    test('a file that is not a compound file is refused, not misread', () {
      expect(() => IptFile(Uint8List(1024)), throwsA(isA<CfbException>()));
    });
  });

  group('the B-rep reader', () {
    test('records, tags and a { ref n } block', () {
      final w = SabWriter();
      w.b.add(ascii.encode('ASM BinaryFile4'));
      for (final v in [23100, 0, 1, 0]) {
        w.b.add((ByteData(4)..setInt32(0, v, Endian.little)).buffer.asUint8List());
      }
      w
        ..str('Inventor')
        ..str('ASM 231')
        ..str('today')
        ..real(10)
        ..real(1e-6)
        ..real(1e-10);
      // record 0: a block, and a reference to it
      w
        ..ident('thing')
        ..ptr(-1)
        ..int32(5)
        ..ptr(-1)
        ..open()
        ..ident('nubs')
        ..int32(3)
        ..close()
        ..open()
        ..ident('ref')
        ..int32(0)
        ..close()
        ..yes()
        ..endRecord();
      // record 1: a chained type name
      w
        ..sub('plane')
        ..ident('surface')
        ..ptr(-1)
        ..int32(6)
        ..ptr(0)
        ..endRecord();
      w.ident('End-of-ASM-data');
      final sab = parseSab(w.b.toBytes());
      expect(sab.unitMm, 10);
      expect(sab.header['product'], 'Inventor');
      expect(sab.records.length, 2);
      expect(sab[0].type, 'thing');
      expect(sab[0].id, 5);
      // the reference became a copy of the block it names
      final idents = [for (final v in sab[0].fields) if (v is SabIdent) v.s];
      expect(idents, ['nubs', 'nubs']);
      expect(sab[1].type, 'plane-surface');
      expect(sab[1].ptrs, [-1, 0]);
    });
  });

  group('a sketch', () {
    test('every constraint written holds on Inventor\'s own geometry', () {
      final a = rectangleSketch();
      expect(a.plane, 'xy');
      final (worst, bad) = checkSketch(a);
      expect(bad, isEmpty);
      expect(worst, lessThan(1e-9));
      // four lines and the lone point (a tagged circle)
      expect(a.geos.where((g) => g.type == kLine).length, 4);
      final pt = a.geos.singleWhere((g) => g.type == kCircle);
      expect(pt.tag, Geo.pointTag);
      // each shared corner is one coincidence between the two lines
      final co = a.cons.where((c) => c['t'] == kCT['coincident']).length;
      expect(co, 4);
      expect(a.cons.where((c) => c['t'] == kCT['dimension']).length, 2);
    });

    test('a broken constraint is caught, not written', () {
      final a = rectangleSketch();
      a.geos[1].data[2] += 0.5; // the right side leans
      final (_, bad) = checkSketch(a);
      expect(bad, isNotEmpty);
    });

    test('DXF numbers are written as the app writes them', () {
      final dxf = sketchDxf([AppGeo(kLine, [0.012284915195554524, -61.17936117936119, 1, 2.5], 0)]);
      expect(dxf, contains('\n0.0122849151955545\n'));
      expect(dxf, contains('\n1.0\n'));
      expect(dxf, contains('\n2.5\n'));
      final files = sketchFiles(rectangleSketch());
      expect(files.keys, contains('sketches/Skizze1.cons.json'));
      expect(jsonDecode(utf8.decode(files['sketches/Skizze1.splines.json']!)), {'4': Geo.pointTag});
    });
  });

  group('the way back to .ipt', () {
    Map<String, Uint8List> doc(List<List<String>> feats, List<String> cached) {
      final src = Uint8List.fromList([1, 2, 3]);
      return {
        kIptSourceEntry: src,
        kIptInfoEntry: utf8.encode(jsonEncode({
          'converter': kIptConverterFull,
          'source_sha256': crypto.sha256.convert(src).toString(),
          'features': feats,
          'cached': cached,
        })),
      };
    }

    Map<String, Object?> meta(List<List<String>> feats, Set<String> cached) => {
          'features': [
            for (final f in feats)
              {
                'name': f[0], 'kind': f[1], 'body': f[2],
                if (cached.contains(f[0])) 'cache': {'step': 's', 'index': 0, 'sig': 'x'},
              }
          ]
        };

    const tree = [
      ['Extrusion1', 'extrude', 'Solid1'],
      ['Rundung1', 'fillet', 'Solid1'],
    ];

    test('an untouched part goes back as its original', () {
      expect(iptExportBlocker(doc(tree, ['Rundung1']), meta(tree, {'Rundung1'})), isNull);
    });

    test('an edit that dropped the stored result is refused', () {
      expect(iptExportBlocker(doc(tree, ['Rundung1']), meta(tree, {})), 'edited');
    });

    test('a feature added or removed is refused', () {
      final more = [...tree, ['Extrusion2', 'extrude', 'Solid1']];
      expect(iptExportBlocker(doc(tree, ['Rundung1']), meta(more, {'Rundung1'})), 'edited');
    });

    test('a part that never came from Inventor has nothing to give back', () {
      expect(iptExportBlocker({}, const {}), 'not-from-inventor');
    });

    test('a damaged original is refused', () {
      final d = doc(tree, ['Rundung1']);
      d[kIptSourceEntry] = Uint8List.fromList([1, 2, 4]);
      expect(iptExportBlocker(d, meta(tree, {'Rundung1'})), 'damaged');
    });
  });

  group('app fixes', () {
    test('a sketch point is not a profile and cuts no hole', () {
      final geos = [
        const Geo(Geo.line, [0, 0, 40, 0]),
        const Geo(Geo.line, [40, 0, 40, 20]),
        const Geo(Geo.line, [40, 20, 0, 20]),
        const Geo(Geo.line, [0, 20, 0, 0]),
        const Geo(Geo.circle, [20, 10, 0.35], spline: Geo.pointTag),
      ];
      final regions = regionsFrom(profileLoopsOf(ProfileInput(geos, const ['0'], const {}, 1)));
      expect(regions.length, 1);
      expect(regions.single.holes, isEmpty);
      expect(regions.single.outer.area, closeTo(800, 1e-6));
    });

    test('a sketch point keeps its tag through a reload', () {
      const pointCarrier = Geo(Geo.circle, [1, 2, 0.35]);
      expect(AppState.takesSplineTag(pointCarrier, Geo.pointTag), isTrue);
      // an ordinary circle never turns into a spline
      expect(AppState.takesSplineTag(pointCarrier, Geo.splineFit), isFalse);
      expect(AppState.takesSplineTag(const Geo(Geo.polyline, [0, 0, 0]), Geo.splineFit), isTrue);
    });

    test('a stored result survives the last-digit noise of a save', () {
      final c = ResultCache(step: 's', index: 0, sig: 'ex|0.012284915195554524 -61.17936117936119|-1.2e-16');
      expect(c.matches('ex|0.0122849151955545 -61.17936117936119|0.0'), isTrue);
      expect(c.matches('ex|0.0122849151955545 -61.18|0.0'), isFalse, reason: 'a real change');
      expect(normalizeSigNumbers('a 2.5122849151955577 b -22.499999999999996 7'), 'a 2.512284915 b -22.5 7');
    });
  });
}
