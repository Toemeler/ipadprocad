// M234 — the test that stops a German label from breaking the layout.
//
// This is the failure this session exists to prevent, and it is not
// hypothetical: German compounds run longer than their English source, and a
// label that grows past its box does not ellipsise — it WRAPS, which makes the
// whole ribbon taller, or it overflows and paints a yellow-and-black bar
// across the app. On a device. In front of the user.
//
// M235 UPDATE — this gate no longer stands alone. It DID ship the failure it
// was written to catch: German ribbon labels were reported wrapping onto a
// second line on the device, and every one of them was inside its x-maxChars
// budget. Reproduced in a rendering test, the offenders are "Rechteck",
// "Bemaßung", "Fertig", "Extrusion" and -- worst -- "Geometrie\nprojizieren",
// which came out on FOUR lines. A character count is too coarse a proxy for a
// real font's advance widths: an average character cannot bound a worst case.
//
// (Those pixel figures come from the host test font, which is wider per
// character than the iPad's SF Pro Text. They establish the ORDER of the
// problem and which labels are worst; they are not device measurements, and
// no SF Pro measurement is available on a Linux test runner.)
//
// The ribbon's buttons are therefore no longer fixed-width. `_Big`, `_BigWide`
// and the Dimension button now take their old width as a MINIMUM and grow to
// fit the label, with soft wrapping off (widgets/ribbon.dart), and
// m235_ribbon_one_line_test.dart asserts the layout property directly by
// measuring what the ribbon actually renders.
//
// This file is kept because the two gates still earn their place as a CHEAP
// upstream check on the ARBs — they fail on a text-editor diff, without
// pumping a widget, and Gate 2 catches ballooning in strings that never go
// near the ribbon. Read the budgets below as "this label is getting long",
// no longer as "this label will fit".
//
// Two gates, because the two failure modes are different.
//
// ---------------------------------------------------------------------------
// GATE 1 — the character budget, for labels that sit in a narrow button.
//
// The budget was derived from the geometry: the narrowest ribbon button was
// `SizedBox(width: 62)`, its label renders at `ts(11.5)`, and the app's font
// averages close to 0.52 em of advance per character at that size — about
// 6.0 px, so 62 px holds ten characters and a little. Each such key carries
// its own budget in the ARB as `x-maxChars`, next to the string it constrains.
//
// M235: that arithmetic assumed an AVERAGE character, and capitals and 'm' are
// nowhere near 0.52 em. An average cannot bound a worst case, which is why the
// real guard is now a rendering test -- one that measures what the widget tree
// actually lays out, in whatever font is in use -- and this one is an
// early-warning heuristic on the ARBs.
//
// The budget applies PER LINE. Two-line labels keep their `\n` — that line
// break is exactly the tool used to fit a wide command into a narrow column,
// and measuring the joined string would forbid the fix as well as the problem.
//
// ---------------------------------------------------------------------------
// GATE 2 — the growth ratio, for every key.
//
// Long messages wrap freely and need no character cap, but they still must not
// balloon: a toast that grows by half fills the screen, and a growth of 3x
// means somebody translated word by word instead of rewriting. The rule is
//
//     de.length <= en.length * 1.35 + 3
//
// 1.35 is the top of the range the industry's own guidance gives for German
// against English running text (Microsoft's and Apple's localisation guides
// both put the expansion at 30%-ish for prose, far more only for very short
// strings). The `+ 3` is what keeps that honest at the short end: "Done" (4)
// against "Fertig" (6) is a 1.5x ratio and is CORRECT — the right German word
// simply has two more letters — so a bare multiplier would fail good
// translations while a flat allowance would wave through bad long ones.
//
// The brief's own example is the check on the check: a label growing from 12
// to 34 characters gets 12 * 1.35 + 3 = 19.2 and fails, which is the point.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// How much longer a German string may be than its English counterpart.
///
/// One flat factor is the obvious rule and it is the wrong one, because text
/// expansion is not linear in length: a four-letter English verb like "Edit"
/// has no four-letter German equivalent — "Bearbeiten" is the word, and no
/// amount of rewriting shortens it — while a forty-character sentence that
/// grows by half was translated instead of written. The published guidance
/// says the same thing (IBM's and Microsoft's expansion tables both allow
/// 100-200% for strings under ten characters and taper to ~30% for prose), so
/// the allowance tapers with length here too.
///
/// The additive +3/+4 is what keeps the short tiers honest against rounding;
/// without it "Neu" (3) against "New" (3) would sit exactly on its limit and
/// any correct word one letter longer would fail.
int allowedFor(int englishLength) {
  if (englishLength <= 10) return (englishLength * 2.0).ceil() + 4;
  if (englishLength <= 20) return (englishLength * 1.7).ceil() + 3;
  if (englishLength <= 30) return (englishLength * 1.5).ceil() + 3;
  return (englishLength * 1.35).ceil() + 3;
}

Map<String, dynamic> readArb(String locale) => jsonDecode(
    File('lib/l10n/app_$locale.arb').readAsStringSync()) as Map<String, dynamic>;

/// The visible text of an ICU message, with the plural/select machinery
/// removed: `{count, plural, =1{Ein Element} other{{count} Elemente}}` is
/// never all shown at once, so measuring it whole would measure a string no
/// user ever sees. Each branch is measured separately instead.
List<String> renderedForms(String msg) {
  final head = RegExp(r'\{\s*\w+\s*,\s*(plural|select)\s*,');
  if (!head.hasMatch(msg)) return [msg];
  final out = <String>[];
  for (final m in RegExp(r'(?:=\d+|zero|one|two|few|many|other)\s*\{').allMatches(msg)) {
    var depth = 1;
    var i = m.end;
    final buf = StringBuffer();
    while (i < msg.length && depth > 0) {
      final c = msg[i];
      if (c == '{') depth++;
      if (c == '}') {
        depth--;
        if (depth == 0) break;
      }
      buf.write(c);
      i++;
    }
    out.add(buf.toString());
  }
  return out.isEmpty ? [msg] : out;
}

/// A placeholder contributes the value's width, not its name's: `{count}` is
/// usually one or two digits whatever it is called. Both languages are
/// measured the same way, so the comparison stays fair.
String withoutPlaceholders(String s) =>
    s.replaceAll(RegExp(r'\{[A-Za-z_][A-Za-z0-9_]*\}'), '');

void main() {
  final de = readArb('de');
  final en = readArb('en');
  final keys = de.keys.where((k) => !k.startsWith('@')).toList()..sort();

  group('German fits where English fit', () {
    test('no key exceeds its declared character budget, per line', () {
      final over = <String>[];
      var budgeted = 0;
      for (final k in keys) {
        final meta = de['@$k'];
        if (meta is! Map || meta['x-maxChars'] == null) continue;
        budgeted++;
        final max = meta['x-maxChars'] as int;
        for (final lang in ['de', 'en']) {
          final v = (lang == 'de' ? de[k] : en[k]) as String;
          for (final line in v.split('\n')) {
            final n = withoutPlaceholders(line).trim().length;
            if (n > max) {
              over.add('$lang.$k line "$line" is $n chars, budget $max');
            }
          }
        }
      }
      expect(budgeted, greaterThan(40),
          reason: 'the fixed-width labels lost their x-maxChars budgets; '
              'this gate would then be measuring nothing');
      expect(over, isEmpty,
          reason: 'these labels are wider than the box they are drawn in, so '
              'they wrap and make the ribbon taller:\n  ${over.join("\n  ")}');
    });

    test('no German string outgrows its English by more than the factor', () {
      final over = <String>[];
      for (final k in keys) {
        final dForms = renderedForms(de[k] as String);
        final eForms = renderedForms(en[k] as String);
        // Compare the LONGEST rendered form of each. Plural branches do not
        // correspond one to one between languages (German and English happen
        // to agree here, but the rule must not depend on that).
        int longest(List<String> forms) => forms
            .map((f) => withoutPlaceholders(f).trim().length)
            .reduce((a, b) => a > b ? a : b);
        final d = longest(dForms), e = longest(eForms);
        final allowed = allowedFor(e);
        if (d > allowed) {
          over.add('$k: de $d chars vs en $e (allowed $allowed)\n'
              '      de: ${de[k]}\n'
              '      en: ${en[k]}');
        }
      }
      expect(over, isEmpty,
          reason: 'rewrite these, do not translate them — a German label this '
              'much longer than its English will not fit where the English '
              'did:\n  ${over.join("\n  ")}');
    });

    test('the gate would reject the failure it exists for', () {
      // The failure this gate exists for: a 12-character label translated
      // into 34.
      expect(34 > allowedFor(12), isTrue,
          reason: 'a 12 -> 34 character blowup must fail this gate');
      // The same blowup one tier up, so the taper cannot be used to smuggle it
      // through: a 40-character message must not be allowed to reach 90.
      expect(90 > allowedFor(40), isTrue);
      // And it must not reject correct short translations, which is the other
      // half of a useful gate.
      expect('Fertig'.length <= allowedFor('Done'.length), isTrue);
      expect('Abbrechen'.length <= allowedFor('Cancel'.length), isTrue);
      expect('Neu'.length <= allowedFor('New'.length), isTrue);
      expect('Bearbeiten'.length <= allowedFor('Edit'.length), isTrue);
      expect('Verschieben'.length <= allowedFor('Move'.length), isTrue);
    });
  });
}
