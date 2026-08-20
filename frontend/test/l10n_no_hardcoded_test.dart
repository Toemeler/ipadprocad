// M234 — the ratchet.
//
// The other two l10n tests protect the strings that ARE in the ARB. This one
// protects the ones that are not yet: it scans the widget layer for English
// text still written into the source, so the next feature cannot quietly add
// a hardcoded label and undo the work.
//
// It is a source scan, which is a blunt instrument, so it is deliberately
// narrow: it looks only where user-visible text is PASSED — the first
// positional argument of `Text(...)`, and the `label:`/`title:`/`message:`/
// `tooltip:`/`hint:` named arguments — and only in `lib/widgets/**` plus the
// files that raise toasts. Everything else (SVG payloads, JSON keys, DXF
// keywords, log tags, symbol names) is out of its sight by construction.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files that legitimately still contain a literal in one of those positions.
///
/// Every entry needs a reason, and the reason is never "not done yet".
const Map<String, String> kAllowed = {
  // MaterialApp.title is the application's own name in the iPadOS task
  // switcher. A proper noun: it is 'Prototype' in every language.
  "lib/main.dart|Prototype": 'the application name, a proper noun',
};

final _text = RegExp(r"""\bText\(\s*'((?:\\.|[^'\\\n])*)'""");
final _named = RegExp(
    r"""\b(?:label|title|message|tooltip|hint|hintText|labelText|placeholder|confirmLabel|subtitle)\s*:\s*'((?:\\.|[^'\\\n])*)'""");

/// Anything that is not prose: ids, symbol names, single glyphs, SVG.
bool looksTechnical(String v) {
  if (v.trim().isEmpty) return true;
  if (!RegExp(r'[A-Za-z]').hasMatch(v)) return true; // '▼', '⌀', digits
  if (v.length <= 2) return true; // 'fx', 'OK' is in the ARB anyway
  if (RegExp(r'^[a-z][A-Za-z0-9_.]*$').hasMatch(v)) return true; // ids/symbols
  if (v.startsWith('<svg') || v.contains('xmlns=')) return true;
  return false;
}

void main() {
  test('no user-visible English is left hardcoded in the widget layer', () {
    final roots = [Directory('lib/widgets'), Directory('lib')];
    final files = <File>{};
    for (final d in roots) {
      if (!d.existsSync()) continue;
      for (final e in d.listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        final name = e.uri.pathSegments.last;
        // The measurement apparatus, the FFI bindings, the generated
        // localisations and the icon/font payloads are not the UI.
        if (name.startsWith('perf') ||
            name == 'svg_icons.dart' ||
            name == 'vector_font_data.dart' ||
            e.path.contains('/ffi/') ||
            e.path.contains('/l10n/')) {
          continue;
        }
        files.add(e);
      }
    }
    expect(files.length, greaterThan(20), reason: 'the scan found no sources');

    final found = <String>[];
    for (final f in files) {
      // Strip whole-line comments; prose in a comment is documentation.
      final src = f
          .readAsStringSync()
          .split('\n')
          .map((l) => l.trimLeft().startsWith('//') ? '' : l)
          .join('\n');
      for (final re in [_text, _named]) {
        for (final m in re.allMatches(src)) {
          final v = m.group(1)!;
          if (looksTechnical(v)) continue;
          final path = f.path.replaceFirst(RegExp(r'^.*?(?=lib/)'), '');
          if (kAllowed.containsKey('$path|$v')) continue;
          found.add('$path: "$v"');
        }
      }
    }
    expect(found, isEmpty,
        reason: 'these read out to the user but are not in the ARB, so they '
            'stay English in a German UI:\n  ${found.join("\n  ")}');
  });

  test('the allow-list is not stale', () {
    for (final entry in kAllowed.keys) {
      final path = entry.split('|').first;
      final literal = entry.split('|').last;
      final f = File(path);
      expect(f.existsSync(), isTrue, reason: '$path is gone from the tree');
      expect(f.readAsStringSync(), contains("'$literal'"),
          reason: '$path no longer contains "$literal" — drop the exemption');
    }
  });
}
