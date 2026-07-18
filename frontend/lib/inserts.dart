// M44 — Insert content: parametric sketch TEXT and IMAGES, plus DXF import.
//
// Parametric text is Inventors sketch text with embedded parameters: the
// template may contain <ParamName> placeholders that render as the
// parameter's CURRENT value and follow every change (and every rename —
// _renameRefs sweeps templates too). Images are underlay entities (file
// copied into the sketch folder, centre + width, aspect preserved). Both
// are sketch state: own sidecars, full undo-journal round-trip.

import 'dart:convert';

/// One parametric text. [template] may embed parameters as <Name>;
/// unknown names stay literal (Inventor shows the raw token until the
/// parameter exists). [height] is the cap height in mm.
class SketchText {
  String template;
  double x, y;
  double height;
  SketchText(this.template, this.x, this.y, {this.height = 8});

  Map<String, dynamic> toJson() =>
      {'t': template, 'x': x, 'y': y, 'h': height};
  static SketchText fromJson(Map<String, dynamic> j) => SketchText(
      j['t'] as String, (j['x'] as num).toDouble(), (j['y'] as num).toDouble(),
      height: (j['h'] as num?)?.toDouble() ?? 8);
}

String encodeTexts(List<SketchText> ts) =>
    jsonEncode([for (final t in ts) t.toJson()]);
List<SketchText> decodeTexts(String s) => [
      for (final j in (jsonDecode(s) as List))
        SketchText.fromJson(j as Map<String, dynamic>)
    ];

final RegExp _phRe = RegExp(r'<\s*([A-Za-z_][A-Za-z0-9_]*)\s*>');

/// Substitutes every <Name> whose parameter exists with its current value
/// (trailing zeros trimmed, mm/deg-agnostic — the number is the number).
String renderTemplate(String template, Map<String, double> params) =>
    template.replaceAllMapped(_phRe, (m) {
      final v = params[m.group(1)!];
      if (v == null) return m.group(0)!; // unknown: keep the raw token
      var s = v.toStringAsFixed(3);
      s = s.replaceFirst(RegExp(r'\.?0+$'), '');
      return s.isEmpty ? '0' : s;
    });

/// The parameter names a template references.
Set<String> templateRefs(String template) =>
    {for (final m in _phRe.allMatches(template)) m.group(1)!};

/// Renames parameter references inside a template: <old> -> <new>.
String renameInTemplate(String template, String from, String to) =>
    template.replaceAllMapped(_phRe,
        (m) => m.group(1) == from ? '<$to>' : m.group(0)!);

/// One inserted image: [file] relative to the sketch folder, centre in
/// world mm, [w]/[h] in mm (aspect fixed at insert time).
class SketchImage {
  String file;
  double x, y;
  double w, h;
  SketchImage(this.file, this.x, this.y, this.w, this.h);

  Map<String, dynamic> toJson() =>
      {'f': file, 'x': x, 'y': y, 'w': w, 'h': h};
  static SketchImage fromJson(Map<String, dynamic> j) => SketchImage(
      j['f'] as String,
      (j['x'] as num).toDouble(),
      (j['y'] as num).toDouble(),
      (j['w'] as num).toDouble(),
      (j['h'] as num).toDouble());
}

String encodeImages(List<SketchImage> xs) =>
    jsonEncode([for (final x in xs) x.toJson()]);
List<SketchImage> decodeImages(String s) => [
      for (final j in (jsonDecode(s) as List))
        SketchImage.fromJson(j as Map<String, dynamic>)
    ];
