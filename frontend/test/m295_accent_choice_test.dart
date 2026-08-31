// Bug report #11 — "make the accent color ... a color which is changable in
// the settings".
//
// WHAT IS PINNED HERE, AND WHY IT IS NOT A SCREENSHOT
// ---------------------------------------------------
// The accent is read by roughly 450 call sites through one getter, so the
// claim worth pinning is not "the settings screen has a row". It is that a tap
// on that row changes what `T.accent` answers, that the answer survives a
// restart, and that choosing the same accent under the other palette gives a
// DIFFERENT colour — because an accent that reads on cream is not the one that
// reads on charcoal, and one value for both would fail the contrast bar in
// m236_theme_test on one of them.
//
// The row itself is checked through `buildSettings`, which is what BOTH
// surfaces render: the UIKit sheet gets it as maps over the channel, and the
// Flutter fallback builds the same spec into a widget tree. Testing the spec
// tests both, and it is the only half of the pair a Linux host can run.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/l10n/l.dart';
import 'package:prototype/settings.dart';
import 'package:prototype/theme.dart';

void main() {
  tearDown(T.resetForTest);

  test('the accent section offers every choice, ticked at the current one', () {
    T.setAccent(Accent.amber);
    final spec = buildSettings(L.current,
        mode: T.mode,
        accent: T.accentChoice.value,
        palette: kEmber,
        locale: const Locale('de'),
        info: const SettingsInfo(
            build: 'x', kernel3d: '—', kernel2d: '—', system: '—'));

    final section = spec.firstWhere((s) => s.id == kSecAccent);
    expect(section.rows.map((r) => r.id).toList(),
        Accent.values.map((a) => a.id).toList(),
        reason: 'every accent is offered, in the order the enum declares');
    expect(section.rows.where((r) => r.selected).map((r) => r.id),
        ['amber'], reason: 'exactly one tick, on the chosen one');

    // The swatch is the value. A colour named "Indigo" and not shown is a
    // colour you have to pick to find out.
    final indigo = section.rows.firstWhere((r) => r.id == 'indigo');
    expect(indigo.tint, Accent.indigo.dark!.toARGB32());
  });

  test('the swatch follows the palette, not the other way round', () {
    SettingsSection accentSection(Palette p) => buildSettings(L.current,
        mode: T.mode,
        accent: Accent.scheme,
        palette: p,
        locale: const Locale('de'),
        info: const SettingsInfo(
            build: 'x',
            kernel3d: '—',
            kernel2d: '—',
            system: '—')).firstWhere((s) => s.id == kSecAccent);

    final onDark = accentSection(kEmber);
    final onLight = accentSection(kChalk);
    for (final a in Accent.values) {
      final d = onDark.rows.firstWhere((r) => r.id == a.id).tint;
      final l = onLight.rows.firstWhere((r) => r.id == a.id).tint;
      expect(d, isNot(l),
          reason: '${a.id} must differ between the palettes — the whole '
              'reason each entry carries two colours');
    }
    // And "Scheme" shows what it will actually give you.
    expect(onDark.rows.first.tint, kEmber.accent.toARGB32());
    expect(onLight.rows.first.tint, kChalk.accent.toARGB32());
  });

  test('choosing an accent changes what T.accent answers', () {
    T.palette = kEmber;
    expect(T.accent, kEmber.accent, reason: 'the default is the palette\'s own');

    T.setAccent(Accent.magenta);
    expect(T.accent, Accent.magenta.dark);

    // The same choice under the other palette is a different colour.
    T.palette = kChalk;
    expect(T.accent, Accent.magenta.light);

    T.setAccent(Accent.scheme);
    expect(T.accent, kChalk.accent, reason: 'back to the palette\'s own');
  });

  test('the tree is told, because the palette object never changes', () {
    T.palette = kEmber;
    var notified = 0;
    void bump() => notified++;
    T.accentChoice.addListener(bump);
    addTearDown(() => T.accentChoice.removeListener(bump));

    T.setAccent(Accent.green);
    expect(notified, 1,
        reason: 'nothing else can tell the tree to repaint — `T.scheme` holds '
            'the same Palette instance before and after, so it never fires');
    T.setAccent(Accent.green);
    expect(notified, 1, reason: 'choosing what is already chosen is no change');
  });

  test('the choice survives a restart', () async {
    final dir = await Directory.systemTemp.createTemp('m294');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = ThemeStore(dir);

    T.attachStore(store);
    T.set(AppThemeMode.light);
    T.setAccent(Accent.blue);

    // The language and the appearance share this file; neither may be lost.
    final raw = jsonDecode(store.file.readAsStringSync()) as Map;
    expect(raw[ThemeStore.accentKey], 'blue');
    expect(raw[ThemeStore.key], 'light');

    T.resetForTest();
    expect(T.accentChoice.value, Accent.scheme, reason: 'a cold start knows nothing');

    T.attachStore(store);
    expect(T.accentChoice.value, Accent.blue);
    expect(T.mode, AppThemeMode.light,
        reason: 'the appearance it was stored beside is still there');
  });

  test('an unknown or missing accent falls back rather than throwing', () {
    expect(Accent.byId('chartreuse'), isNull);
    expect(Accent.byId(null), isNull);
    expect(Accent.byId('teal'), Accent.teal);
  });
}
