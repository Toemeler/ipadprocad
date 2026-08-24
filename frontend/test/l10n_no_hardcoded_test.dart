// M234 — the ratchet.
//
// The other two l10n tests protect the strings that ARE in the ARB. This one
// protects the ones that are not yet: it scans the widget layer for English
// text still written into the source, so the next feature cannot quietly add
// a hardcoded label and undo the work.
//
// The first version of this test looked only at NAMED arguments — `label:`,
// `title:`, `message:`, `tooltip:`, `hint:` — and at `Text(...)`. That missed
// about a hundred and eighty strings, because the feature dialogues pass their
// labels POSITIONALLY: `panelRow('Start A', …)`, `('coincident',
// 'Coincident')`. They were found by hand in the end, and the lesson is baked
// in here: this scans every prose-looking literal in the widget layer, not
// just the ones in a position it thought to look at.
//
// Prose-looking means: starts with a capital (or '(' or '+'), holds three
// letters, is not an identifier, a SCREAMING_CONST, an SF Symbol name, or SVG.
// Comments are masked out first — a comment full of English prose is
// documentation, and an apostrophe in one ("Inventor's") would otherwise open
// a string literal that swallows half the file.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Literals that stay English, by file, each group with its reason.
///
/// Every entry here is a decision, and the decision is never "not done yet":
/// it is either persisted to a document, a format keyword, a font name, or
/// punctuation. `the allow-list is not stale` below fails if one of them
/// leaves the tree, so the list cannot quietly outlive its reason.
const Map<String, Set<String>> kAllowed = {
  // Generated document, body and feature NAMES ('Sketch3', 'Solid1',
  // 'Fillet'), the `def` sentences of the work features, and the DXF layer
  // 'Defpoints'. Every one of them is written into the .ptp or the DXF —
  // translating one is a data-format change. S12-i18n.md §5.
  'lib/app_state.dart': {
    '(preview)',
    // M240 — the generated name of a new ASSEMBLY, on the same footing as
    // 'Part\$n' and 'Sketch\$n' below it: it is written into the document and
    // into its file name, so translating it would be a data change.
    'Assembly\$n',
    'Chamfer',
    'Coil',
    'Combine',
    'Defpoints',
    'Delete Face',
    'Direct',
    'Face',
    'Feature',
    'Fillet',
    'Hole',
    'Import\${p.features.length + 1}',
    'Imported',
    'Layer \$n',
    'Loft',
    'Midplane between \${_wpNames[0]} and \${_wpNames[1]}',
    'Offset \${d.toStringAsFixed(2)} mm from \$wpCreateLabel',
    'Offset \${workPlaneOffset.toStringAsFixed(2)} mm from \$label',
    'Part\$n',
    'Plane',
    // M242 — the LABEL of the reference vector a directed Angle captures when
    // it is created. It is an AsmRef.label, which is written into the .pas
    // beside the geometry it names, exactly like the 'Face' and 'Circular
    // Edge' labels the picker stores — translating one would make a
    // German-authored assembly read differently when opened in English.
    'Reference Vector',
    'Revolution',
    'Scale',
    'Sketch\$_newN',
    'Sketch\$n',
    'Solid\${p.solidN + 1}',
    'Solid1',
    'Split',
    'Sweep',
    'User_\$i',
    'Work Axis',
    'Work Plane',
    'Work Point',
  },
  // Fallback for a missing sketch name.
  'lib/widgets/extrude_dialog.dart': {
    'Sketch1',
  },
  // A font family, and the fallback for a missing document NAME.
  'lib/widgets/model_browser.dart': {
    'Menlo',
    'Sketch1',
  },
  // Fallback for a missing document name.
  'lib/widgets/native_browser.dart': {
    'Sketch1',
  },
  // A regular expression, not prose.
  'lib/widgets/scrub_field.dart': {
    '(mm|deg|°|ul)\\s*\$',
  },
  // Punctuation around an already-localised value: '(12,50 mm)'.
  'lib/widgets/viewport.dart': {
    '(\$label)',
  },
  // WorkRef.label values. They build the `def` that goes into the .ptp. §5.1.
  'lib/widgets/viewport3d.dart': {
    'Center Point',
    'Circular Edge',
    'Conical Face',
    'Curve',
    'Cylindrical Face',
    'Edge',
    'Edge Midpoint',
    'Elliptical Edge',
    'Face',
    'Sketch line',
    'Spherical Face',
    'Toroidal Face',
    'Work Plane',
  },
  // The `def` sentences and their WorkRef.label parts, plus the English
  // method vocabulary. `def` is persisted (part_model.dart:365). §5.1.
  'lib/work_features.dart': {
    'Angle to Plane around Edge',
    'Axis',
    'Center Point of Loop of Edges',
    'Center Point of Sphere',
    'Center Point of Torus',
    'Center of \${first.label}',
    'Center of \${r.label}',
    'Grounded Point',
    'Grounded at \${r.label}',
    'Intersection of \${a.label} and \${b.label}',
    'Intersection of \${a.label}, \${b.label} and \${c.label}',
    'Intersection of \${plane.label} and \${line.label}',
    'Intersection of Plane/Surface and Line',
    'Intersection of Three Planes',
    'Intersection of Two Lines',
    'Intersection of Two Planes',
    'Midplane of \${r.label}',
    'Midplane of Torus',
    'Midpoint of \${first.label}',
    'Normal to \${first.label} through \${second.label}',
    'Normal to \${line.label} through \${pt.label}',
    'Normal to \${plane.label} through \${pt.label}',
    'Normal to \${r.label}',
    'Normal to \${second.label} through \${first.label}',
    'Normal to Axis through Point',
    'Normal to Curve at Point',
    'Normal to Plane through Point',
    'On \${first.label}',
    'On \${r.label}',
    'On Line or Edge',
    'On Vertex, Sketch Point, or Midpoint',
    'Parallel to \${line.label} through \${point.label}',
    'Parallel to \${plane.label} through \${pt.label}',
    'Parallel to \${second.label} through \${first.label}',
    'Parallel to Line through Point',
    'Parallel to Plane through Point',
    'Point',
    'Revolution axis of \${first.label}',
    'Revolution axis of \${r.label}',
    'Tangent to \${cyl.label} through \${edge.label}',
    'Tangent to \${cyl.label} through \${pt.label}',
    'Tangent to \${cyl.label}, parallel to \${plane.label}',
    'Tangent to Surface and Parallel to Plane',
    'Tangent to Surface through Edge',
    'Tangent to Surface through Point',
    'Three Points',
    'Through \${a.label} and \${b.label}',
    'Through \${a.label}, \${b.label} and \${c.label}',
    'Through Center of Circular or Elliptical Edge',
    'Through Revolved Face or Feature',
    'Through Two Points',
    'Through center of \${first.label}',
    'Through center of \${r.label}',
    'Two Coplanar Edges',
  },
  // MaterialApp.title: the application's name in the task switcher.
  'lib/main.dart': {'Prototype'},
};

final _anyLiteral = RegExp(r"""'((?:\\.|[^'\\\n])*)'""");

/// Comments — and the argument lists of `Log.*`, `assert` and `throw` —
/// replaced by spaces, offsets preserved.
///
/// Log output is diagnostics, not the interface: it is read in a bug bundle by
/// whoever is debugging, it is grepped, and it stays English on purpose (see
/// S12-i18n.md §5). Masking it here is what keeps this test's allow-list about
/// real exceptions instead of two hundred log lines.
String maskComments(String s) {
  final out = s.split('');
  var i = 0;
  final n = s.length;
  while (i < n) {
    final c = s[i];
    if (c == '/' && i + 1 < n && s[i + 1] == '/') {
      var j = s.indexOf('\n', i);
      if (j < 0) j = n;
      for (var k = i; k < j; k++) {
        out[k] = ' ';
      }
      i = j;
    } else if (c == '/' && i + 1 < n && s[i + 1] == '*') {
      var j = s.indexOf('*/', i + 2);
      j = j < 0 ? n : j + 2;
      for (var k = i; k < j; k++) {
        if (s[k] != '\n') out[k] = ' ';
      }
      i = j;
    } else if (c == "'" || c == '"') {
      final q = c;
      i++;
      while (i < n) {
        if (s[i] == r'\') {
          i += 2;
          continue;
        }
        if (s[i] == q) {
          i++;
          break;
        }
        i++;
      }
    } else {
      i++;
    }
  }
  var masked = out.join();
  // Log / assert / throw argument lists: balanced-paren scan over the masked
  // text, blanking what is inside.
  for (final head in [
    RegExp(r'\bLog\.[a-zA-Z]+\('),
    RegExp(r'\bassert\('),
    RegExp(r'\bdebugPrint\('),
  ]) {
    var from = 0;
    while (true) {
      final m = head.firstMatch(masked.substring(from));
      if (m == null) break;
      final start = from + m.end;
      var depth = 1;
      var i = start;
      while (i < masked.length && depth > 0) {
        if (masked[i] == '(') depth++;
        if (masked[i] == ')') depth--;
        i++;
      }
      final chars = masked.split('');
      for (var k = start; k < i - 1; k++) {
        if (chars[k] != '\n') chars[k] = ' ';
      }
      masked = chars.join();
      from = i;
    }
  }
  return masked;
}

/// Anything that is not prose the user reads: ids, symbol names, glyphs, SVG,
/// SCREAMING_CONSTS, file and format keywords.
bool looksTechnical(String v) {
  if (v.trim().length < 3 || v.length > 120) return true;
  if (!RegExp(r'[A-Za-z]{3}').hasMatch(v)) return true; // '▼', '⌀', digits
  if (!RegExp(r'^[A-Z(+]').hasMatch(v)) return true; // prose starts capital
  if (RegExp(r'^[a-z][A-Za-z0-9_.]*$').hasMatch(v)) return true; // ids
  if (RegExp(r'^[A-Z][A-Z0-9_.]*$').hasMatch(v)) return true; // CONSTS, DXF
  if (RegExp(r'^[a-z]+(\.[a-z0-9]+)+$').hasMatch(v)) return true; // SF symbols
  if (v.startsWith('<') || v.contains('xmlns=')) return true;
  return false;
}

void main() {
  test('no user-visible English is left hardcoded in the widget layer', () {
    // Where user-visible text lives: every widget, plus the two files that
    // raise it from business logic. `part_model.dart` is deliberately NOT
    // here — its English strings are the domain vocabulary and the .ptp file
    // format, and they stay English by design (S12-i18n.md §4.7, §5).
    final files = <File>{
      for (final e in Directory('lib/widgets').listSync(recursive: true))
        if (e is File &&
            e.path.endsWith('.dart') &&
            !e.uri.pathSegments.last.startsWith('perf') &&
            e.uri.pathSegments.last != 'svg_icons.dart')
          e,
      File('lib/app_state.dart'),
      File('lib/work_features.dart'),
    };
    expect(files.length, greaterThan(20), reason: 'the scan found no sources');

    final found = <String>[];
    for (final f in files) {
      final raw = f.readAsStringSync();
      final masked = maskComments(raw);
      for (final m in _anyLiteral.allMatches(masked)) {
        // The literal comes from the ORIGINAL; the mask only says where.
        final v = raw.substring(m.start + 1, m.end - 1);
        if (looksTechnical(v)) continue;
        final path = f.path.replaceFirst(RegExp(r'^.*?(?=lib/)'), '');
        if (kAllowed[path]?.contains(v) ?? false) continue;
        found.add('$path: "$v"');
      }
    }
    expect(found, isEmpty,
        reason: 'these read out to the user but are not in the ARB, so they '
            'stay English in a German UI:\n  ${found.join("\n  ")}');
  });

  test('the allow-list is not stale', () {
    // An exemption that outlives the literal it exempts is an exemption
    // nobody is looking at any more.
    for (final entry in kAllowed.entries) {
      final f = File(entry.key);
      expect(f.existsSync(), isTrue, reason: '${entry.key} is gone from the tree');
      final src = f.readAsStringSync();
      for (final literal in entry.value) {
        expect(src, contains("'$literal'"),
            reason: '${entry.key} no longer contains "$literal" — drop it '
                'from kAllowed');
      }
    }
  });
}
