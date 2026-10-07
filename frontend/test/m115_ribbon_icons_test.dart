// M115 — every icon key the ribbon looks up must exist in the map it looks it
// up in.
//
// This shipped a build with NO RIBBON AT ALL: `IC['acad']!` was written for an
// icon that lives in `IN`, so the null-check operator threw during build,
// Flutter replaced the whole ribbon with its red error widget, and every tool
// — including the Import button that change was adding — disappeared. The
// analyzer cannot see it: the maps are `Map<String, String>`, so a missing key
// is a runtime null, not a type error.
//
// The maps are plain top-level constants, so checking every key the ribbon
// asks for is cheap and catches the whole class before it reaches a device.
//
// Icon v2: svg_icons.dart is generated (tools/icon_redesign/export_dart.py),
// so the same check now runs over EVERY literal lookup in lib/, plus the
// flyout rows, whose ids are resolved by flyIconOf rather than written out.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/l10n/l.dart';
import 'package:prototype/svg_icons.dart';
import 'package:prototype/widgets/ribbon.dart';

const Map<String, Map<String, String>> _maps = {
  'IC': IC, 'CN': CN, 'IN': IN, 'MD': MD, 'PD': PD, 'VW': VW, 'MS': MS,
  'CR': CR, 'MO': MO, 'WF': WF, 'PT': PT, 'PL': PL, 'AX': AX, 'PN': PN,
  'AS': AS, 'AC': AC, 'DE': DE, //
};

Iterable<File> _libFiles() =>
    Directory('lib').listSync(recursive: true).whereType<File>().where(
        (f) => f.path.endsWith('.dart') && !f.path.endsWith('svg_icons.dart'));

void main() {
  test('every literal icon lookup in lib/ resolves', () {
    final re =
        RegExp(r"\b(" + _maps.keys.join('|') + r")\['([A-Za-z0-9_]+)'\]");
    final missing = <String>[];
    var n = 0;
    for (final f in _libFiles()) {
      for (final m in re.allMatches(f.readAsStringSync())) {
        n++;
        if (!_maps[m.group(1)]!.containsKey(m.group(2))) {
          missing.add("${f.path}: ${m.group(1)}['${m.group(2)}']");
        }
      }
    }
    expect(n, greaterThan(80), reason: 'the scan found no lookups at all');
    expect(missing, isEmpty,
        reason: 'these lookups return null; a `!` on them kills the whole '
            'ribbon at build time');
  });

  test('every constraint cell of the ribbon has its CN icon', () {
    final src = File('lib/widgets/ribbon.dart').readAsStringSync();
    final ids = RegExp(r"\('(\w+)', t\.con\w+\)")
        .allMatches(src)
        .map((m) => m.group(1)!)
        .toList();
    expect(ids, hasLength(11));
    for (final id in ids) {
      expect(CN.containsKey(id), isTrue, reason: "CN['$id']");
    }
  });

  test('every flyout row resolves its own icon, never the Line fallback', () {
    // The bug this pins: axis, point and Direct rows were looked up in IC / PL
    // only, found nothing and drew the Line icon.
    final t = lookupAppL10n(kEn);
    resetFlyoutCacheForTest();
    final bad = <String>[];
    var n = 0;
    flyoutsOf(t).forEach((group, items) {
      for (final it in items) {
        n++;
        final icon = flyIconOf(it.icon);
        if (icon == null) {
          bad.add('$group/${it.icon}: no icon');
        } else if (icon == IC['line34'] && group != 'line') {
          bad.add('$group/${it.icon}: the Line icon');
        }
      }
    });
    expect(n, greaterThan(60));
    expect(bad, isEmpty, reason: bad.join('\n'));
    // and they are the intended drawings (tools/ribbon_icon_mockup INTENDED)
    expect(flyIconOf('waAuto'), AX['axis']);
    expect(flyIconOf('waRev'), AX['revolved']);
    expect(flyIconOf('wptAuto'), PN['point']);
    expect(flyIconOf('wptSphere'), PN['centersphere']);
    expect(flyIconOf('deMove'), DE['deMove']);
    expect(flyIconOf('deDelete'), DE['deDelete']);
    expect(flyIconOf('midplane2'), PL['midplane2']);
    expect(flyIconOf('fslotcc'), IC['fslotcc']);
  });

  test('every in-scope ribbon key is a v2 drawing', () {
    // Only PD, AC and the model-browser / tab singles are carried over from
    // the pre-v2 set; everything the ribbon draws is v2: either lit material
    // (data-lit="2") or v2 line art on the 28 u grid.
    for (final e in _maps.entries) {
      if (e.key == 'PD' || e.key == 'AC') continue;
      e.value.forEach((k, svg) {
        final ref = '${e.key}.$k';
        expect(legacyIconKeys.contains(ref), isFalse, reason: '$ref is v1');
        expect(svg, contains('viewBox="0 0 28 28"'), reason: ref);
        expect(svg, isNot(contains('<text')), reason: '$ref draws type');
      });
    }
    expect(IN['params'], isNotNull, reason: 'the Parameters button icon');
    expect(DE.keys,
        containsAll(['deMove', 'deSize', 'deScale', 'deRotate', 'deDelete']));
  });

  test('a small master exists only for a real icon, and is v2 too', () {
    final all = {for (final m in _maps.values) ...m.values};
    expect(smallIcons, isNotEmpty);
    smallIcons.forEach((master, sm) {
      expect(all.contains(master) || master == assemblyMenuIcon, isTrue);
      expect(sm, contains('viewBox="0 0 28 28"'));
      expect(sm, isNot(contains('<text')));
    });
  });

  test('gradient ids are unique app-wide (SPEC §12)', () {
    final owner = <String, String>{};
    final clash = <String>[];
    final every = <String>{
      for (final m in _maps.values) ...m.values,
      ...smallIcons.values,
    };
    for (final svg in every) {
      final ids = RegExp(r'id="([^"]+)"')
          .allMatches(svg)
          .map((m) => m.group(1)!)
          .toSet();
      for (final id in ids) {
        expect(id, startsWith('g-'), reason: 'only gradients carry an id');
        final prev = owner[id];
        if (prev != null && prev != svg) clash.add(id);
        owner[id] = svg;
      }
    }
    expect(clash, isEmpty, reason: 'two icons share a gradient id');
  });

  test('the icon maps are not accidentally empty', () {
    for (final m in _maps.values) {
      expect(m, isNotEmpty);
    }
  });
}
