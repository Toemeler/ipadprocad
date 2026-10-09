import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../part_model.dart';

/// Programs travel with the editable document, not just the chat transcript.
/// The fingerprint prevents a later AI edit from replaying stale source over
/// changes the user made with the ordinary CAD tools.
String aiProgramFingerprint(PartModel p, String part) {
  final prefix = 'p_${part}_';
  return sha256
      .convert(utf8.encode(jsonEncode({
        'features': [
          for (final f in p.features)
            if (f.name.startsWith(prefix)) f.toJson(),
        ],
        'sketches': [
          for (final s in p.childSketches)
            if (s.model.name.startsWith(prefix))
              {
                'name': s.model.name,
                'plane': s.plane,
                if (s.face != null) 'frame': s.face!.frameJson(),
                'geometry': [
                  for (final g in s.model.geometry)
                    {'type': g.type, 'data': g.data}
                ],
                'constraints': [
                  for (final c in s.model.constraints) c.toJson()
                ],
              },
        ],
      })))
      .toString();
}

bool aiProgramSourceMatches(PartModel p, String part, Map record) =>
    record['fingerprint'] == aiProgramFingerprint(p, part);

/// Full source is useful context; truncating individual formulas makes it
/// unusable. Bound whole programs and explicitly name anything omitted.
Map<String, dynamic> aiProgramContext(PartModel p, {int maxChars = 24000}) {
  final programs = <Map<String, dynamic>>[];
  final omitted = <String>[];
  var budget = maxChars;
  for (final e in p.aiPrograms.entries) {
    final r = e.value;
    if (!p.features.any((f) => f.name.startsWith('p_${e.key}_'))) continue;
    final entry = <String, dynamic>{
      'part': e.key,
      'body': r['body'],
      'source': r['source'],
      'matchesTimeline': aiProgramSourceMatches(p, e.key, r),
      if (!aiProgramSourceMatches(p, e.key, r))
        'note': 'Manually edited since this program was built. Inspect the '
            'current body and edit its features; replaying this source would '
            'lose those edits.',
    };
    final chars = jsonEncode(entry).length;
    if (chars > budget) {
      omitted.add(e.key);
    } else {
      programs.add(entry);
      budget -= chars;
    }
  }
  return {
    'programs': programs,
    if (omitted.isNotEmpty) 'sourceOmittedForSize': omitted,
  };
}
