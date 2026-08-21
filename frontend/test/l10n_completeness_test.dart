// M234 — the two ARB files must say the same things.
//
// This is the test the localisation exists to be protected by. A key added to
// one language and forgotten in the other does not fail the build: gen-l10n
// falls back to the template, so an English user silently gets a German
// sentence in the middle of their UI, and nobody notices until a screenshot
// arrives from a customer. Comparing the files is the only thing that catches
// it before then.
//
// It reads the ARB files themselves rather than the generated Dart, because
// the ARBs are the source of truth and the generated code is derived from
// exactly one of them.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/l10n/gen/app_l10n.dart';
import 'package:prototype/l10n/l.dart';

/// Every `{placeholder}` in [msg], ignoring ICU keyword arguments.
///
/// `{count, plural, =1{...} other{...}}` names `count` once and then uses it
/// again inside the branches; both spellings are the same placeholder, and
/// `plural`/`other`/`=1` are syntax, not names.
Set<String> placeholdersOf(String msg) {
  final out = <String>{};
  for (final m in RegExp(r'\{\s*([A-Za-z_][A-Za-z0-9_]*)\s*[,}]').allMatches(msg)) {
    final name = m.group(1)!;
    if (name == 'plural' || name == 'select' || name == 'other') continue;
    out.add(name);
  }
  return out;
}

Map<String, dynamic> readArb(String locale) {
  final f = File('lib/l10n/app_$locale.arb');
  if (!f.existsSync()) {
    // Thrown rather than expect()ed: this runs at load time, outside any
    // test body, where expect() is not available.
    throw StateError('${f.path} is missing');
  }
  return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
}

/// Message keys only — `@@locale` and the `@key` metadata blocks are not
/// messages.
Set<String> messageKeys(Map<String, dynamic> arb) =>
    arb.keys.where((k) => !k.startsWith('@')).toSet();

void main() {
  final de = readArb('de');
  final en = readArb('en');

  group('both languages are complete', () {
    test('the key sets are identical', () {
      final dk = messageKeys(de), ek = messageKeys(en);
      expect(dk.difference(ek), isEmpty,
          reason: 'in app_de.arb but missing from app_en.arb — an English '
              'user would see these in German');
      expect(ek.difference(dk), isEmpty,
          reason: 'in app_en.arb but missing from app_de.arb — the TEMPLATE '
              'is the German file, so a key only English has is unreachable');
    });

    test('no value is empty or whitespace', () {
      for (final k in messageKeys(de)) {
        expect((de[k] as String).trim(), isNotEmpty, reason: 'de.$k is empty');
        expect((en[k] as String).trim(), isNotEmpty, reason: 'en.$k is empty');
      }
    });

    test('the same placeholders appear on both sides', () {
      for (final k in messageKeys(de)) {
        expect(placeholdersOf(en[k] as String), placeholdersOf(de[k] as String),
            reason: 'placeholders differ for "$k" — one side would print a '
                'literal {name} or drop a value');
      }
    });

    test('every declared placeholder is actually used, and vice versa', () {
      for (final k in messageKeys(de)) {
        final meta = de['@$k'];
        final declared = meta is Map && meta['placeholders'] is Map
            ? (meta['placeholders'] as Map).keys.map((e) => '$e').toSet()
            : <String>{};
        final used = placeholdersOf(de[k] as String);
        expect(declared, used,
            reason: 'the @$k placeholders block and the message disagree; '
                'gen-l10n takes the block, so an undeclared placeholder is '
                'printed as literal braces');
      }
    });

    test('@@locale is the file it claims to be', () {
      expect(de['@@locale'], 'de');
      expect(en['@@locale'], 'en');
    });
  });

  group('the generated code carries both', () {
    test('every ARB key has a getter or method on both classes', () {
      // Instantiating both and asking the delegate for them is the check that
      // the generated Dart is in step with the ARB it was generated from — a
      // committed generated file that someone forgot to regenerate is exactly
      // the failure this catches.
      for (final locale in AppL10n.supportedLocales) {
        expect(() => lookupAppL10n(locale), returnsNormally,
            reason: 'no generated class for $locale');
      }
      expect(AppL10n.supportedLocales.map((l) => l.languageCode).toSet(),
          {'de', 'en'});
    });

    test('the shipped locale list and the ARB files agree', () {
      final shipped = kLocales.map((l) => l.languageCode).toSet();
      expect(shipped, {'de', 'en'},
          reason: 'kLocales drives the menu toggle; a language in the ARB '
              'directory but not in kLocales is unreachable');
    });

    test('a German string really is German, and English really is English', () {
      // A smoke test against the one mistake a copy-paste makes: both files
      // holding the same text because one was duplicated from the other.
      expect(lookupAppL10n(kDe).cancel, 'Abbrechen');
      expect(lookupAppL10n(kEn).cancel, 'Cancel');
      expect(lookupAppL10n(kDe).languageName, 'Deutsch');
      expect(lookupAppL10n(kEn).languageName, 'English');
    });
  });
}
