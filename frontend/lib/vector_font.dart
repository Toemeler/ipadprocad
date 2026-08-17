// M220 — OUTLINE FONTS, so a sketch text can be geometry.
//
// "schriften sollen tatsächlich linien sein wie in dxf üblich. in inventor
//  kann jede schrift auch exportiert werden als dxf und ist tatsächlich da
//  und jede schrift kann extrudiert werden"
//
// A text used to be a LABEL: a TextPainter drew glyphs onto the canvas and
// handed back nothing but a size. Nothing else in the app could see it — the
// DXF had no trace of it, the profile finder found no loop, the kernel had
// nothing to extrude. Inventor's sketch text is the opposite: it is sketch
// GEOMETRY, closed contours like any other, which is why it lands in the DXF
// and can be extruded.
//
// dart:ui has no glyph-outline API (and iOS-only CoreText would leave the
// host with nothing), so the outlines are extracted ahead of time by
// tool/make_vector_font.py and shipped as data in vector_font_data.dart:
// every glyph as move/line/quadratic commands in 1/1000 em, y up, the origin
// on the baseline. This file turns that back into contours and lays a string
// out into them. Everything here is pure Dart and deterministic — the same
// text produces the same curve on the iPad, on the host and in a test.
import 'dart:math' as math;
import 'dart:ui';

import 'log.dart';
import 'vector_font_data.dart';

/// The families the outline data ships. These are the names a [SketchText]
/// stores, and the names the text editor offers.
const List<String> kVectorFontNames = ['CAD Sans', 'CAD Mono', 'CAD Serif'];

/// The family a new text gets, and the one the text sidecar omits.
const String kDefaultTextFont = 'CAD Sans';

/// Maps whatever a text carries onto a family that exists. Texts written
/// before M220 hold the name of a SCREEN font ("Roboto", "Menlo", …) — those
/// were never geometry, so the closest vector family takes over rather than
/// the text losing its shape entirely.
String vectorFontName(String name) {
  if (kVectorFontNames.contains(name)) return name;
  switch (name.toLowerCase()) {
    case 'courier':
    case 'courier new':
    case 'menlo':
    case 'monaco':
    case 'consolas':
      return 'CAD Mono';
    case 'georgia':
    case 'times':
    case 'times new roman':
    case 'serif':
      return 'CAD Serif';
    default:
      return 'CAD Sans';
  }
}

/// One glyph: its advance width and its closed contours, both in EM units
/// (1.0 = the font size), y up, origin on the baseline.
class VectorGlyph {
  final double advance;
  final List<List<Offset>> contours;
  const VectorGlyph(this.advance, this.contours);
}

/// A parsed outline font. Metrics are in EM units like the glyphs.
class VectorFont {
  final String name;

  /// Distance from the baseline to the top of the line box (positive) and to
  /// its bottom ([descent] is NEGATIVE, as in the font's own tables).
  final double ascent, descent, lineGap, capHeight, xHeight;

  final Map<int, String> _raw; // codepoint -> path commands, lazily flattened
  final Map<int, double> _adv;
  final Map<int, VectorGlyph> _cache = {};

  VectorFont._(this.name, this.ascent, this.descent, this.lineGap,
      this.capHeight, this.xHeight, this._raw, this._adv);

  static final Map<String, VectorFont> _fonts = {};

  /// The family [name], mapped through [vectorFontName] so a caller can pass
  /// a legacy screen-font name. Parsed once, then cached.
  factory VectorFont.of(String name) {
    final fam = vectorFontName(name);
    return _fonts.putIfAbsent(fam, () => _parse(fam));
  }

  static VectorFont _parse(String fam) {
    final head = (kVectorFontHeads[fam] ?? '').split(RegExp(r'\s+'));
    double m(int i) =>
        i < head.length ? (double.tryParse(head[i]) ?? 0) / 1000.0 : 0;
    final raw = <int, String>{};
    final adv = <int, double>{};
    for (final line in (kVectorFontGlyphs[fam] ?? '').split('\n')) {
      if (line.isEmpty) continue;
      // "<codepoint> <advance> <path…>" — the path may be empty (space).
      final a = line.indexOf(' ');
      if (a < 0) continue;
      final b = line.indexOf(' ', a + 1);
      final cp = int.tryParse(line.substring(0, a));
      final w = double.tryParse(
          b < 0 ? line.substring(a + 1) : line.substring(a + 1, b));
      if (cp == null || w == null) continue;
      adv[cp] = w / 1000.0;
      raw[cp] = b < 0 ? '' : line.substring(b + 1).trim();
    }
    if (raw.isEmpty) {
      Log.w('font', 'vector font "$fam" has no glyphs');
    }
    return VectorFont._(fam, m(0), m(1), m(2), m(3), m(4), raw, adv);
  }

  /// Height of one line of text, in EM units: what the next line's baseline
  /// sits below this one, and the height of a single-line bounding box.
  double get lineHeight => ascent - descent;

  bool has(int codepoint) => _raw.containsKey(codepoint);

  /// The glyph for [codepoint], or null when the font does not carry it.
  VectorGlyph? glyph(int codepoint) {
    final hit = _cache[codepoint];
    if (hit != null) return hit;
    final path = _raw[codepoint];
    if (path == null) return null;
    final g = VectorGlyph(_adv[codepoint] ?? 0, _flatten(path));
    _cache[codepoint] = g;
    return g;
  }

  /// The advance of an unsupported codepoint: a blank of the width of a
  /// space, so the rest of the line keeps its place.
  double get _blank => _adv[0x20] ?? 0.5;
}

/// Chord tolerance for flattening a quadratic, in EM units. 0.002 em is
/// 16 µm on an 8 mm text — below what any cutter or printer resolves, and
/// scale-independent because the flattening happens in em space.
const double _flatTolEm = 0.002;

List<List<Offset>> _flatten(String path) {
  final out = <List<Offset>>[];
  if (path.isEmpty) return out;
  final t = path.split(' ');
  var cur = Offset.zero;
  List<Offset>? c;
  double n(int i) => (double.tryParse(t[i]) ?? 0) / 1000.0;
  for (var i = 0; i < t.length;) {
    switch (t[i]) {
      case 'M':
        c = [Offset(n(i + 1), n(i + 2))];
        cur = c.first;
        i += 3;
        break;
      case 'L':
        cur = Offset(n(i + 1), n(i + 2));
        c?.add(cur);
        i += 3;
        break;
      case 'Q':
        final ctrl = Offset(n(i + 1), n(i + 2));
        final end = Offset(n(i + 3), n(i + 4));
        if (c != null) _quad(c, cur, ctrl, end);
        cur = end;
        i += 5;
        break;
      case 'Z':
        // The generator always closes the contour by returning to its first
        // point, so drop that repeat: a profile loop must not carry a
        // zero-length closing edge (the kernel rejects those wires).
        if (c != null) {
          while (c.length > 1 && (c.first - c.last).distance < 1e-9) {
            c.removeLast();
          }
          if (c.length >= 3) out.add(c);
        }
        c = null;
        i += 1;
        break;
      default:
        i += 1; // unknown token: skip rather than lose the whole glyph
    }
  }
  return out;
}

/// Appends the quadratic (cur -> ctrl -> end) to [into], subdivided so the
/// chord never departs from the curve by more than [_flatTolEm].
void _quad(List<Offset> into, Offset p0, Offset p1, Offset p2) {
  // Maximum distance of the curve from the chord is a quarter of the control
  // point's distance from the chord midpoint — exact for a quadratic.
  final dev = (p1 - (p0 + p2) / 2).distance / 2;
  final steps =
      dev <= _flatTolEm ? 1 : math.sqrt(dev / _flatTolEm).ceil().clamp(2, 24);
  for (var k = 1; k <= steps; k++) {
    final u = k / steps, v = 1 - u;
    into.add(Offset(v * v * p0.dx + 2 * v * u * p1.dx + u * u * p2.dx,
        v * v * p0.dy + 2 * v * u * p1.dy + u * u * p2.dy));
  }
}

/// A laid-out string: the closed contours it consists of, in the SAME units
/// as [height] (mm), plus the box they occupy.
///
/// The anchor is the LOWER-LEFT of the box — the contract [SketchText] has
/// always had, so a text keeps its place across M220.
class TextLayout {
  /// Every closed contour, in sketch mm. A hole (the inside of an "o") is a
  /// contour of its own; the profile finder nests it into its outer loop.
  final List<List<Offset>> contours;

  /// Width x height of the box the text occupies, in mm.
  final Size size;

  const TextLayout(this.contours, this.size);

  static const empty = TextLayout([], Size.zero);
}

/// Lays [text] out at [height] mm (the EM size, i.e. what a font dialog calls
/// the point size — the same number the pre-M220 TextPainter got), with the
/// box's lower-left corner at [origin].
///
/// Newlines start a new line; there is no kerning (DejaVu's kern pairs move
/// letters by a few thousandths of an em, far below anything that matters on
/// a drawing, and leaving it out keeps the layout something a test can state
/// exactly).
TextLayout layoutText(String text, String fontName, double height,
    {Offset origin = Offset.zero}) {
  if (height <= 0) return TextLayout.empty;
  final f = VectorFont.of(fontName);
  final lines = text.split('\n');
  final widths = <double>[];
  for (final ln in lines) {
    var w = 0.0;
    for (final cp in ln.runes) {
      final g = f.glyph(cp);
      w += g?.advance ?? f._blank;
    }
    widths.add(w);
  }
  final maxW = widths.fold(0.0, math.max) * height;
  final lineH = f.lineHeight * height;
  final total = lineH * lines.length;
  final out = <List<Offset>>[];
  for (var i = 0; i < lines.length; i++) {
    // The line's own box top, then down to its baseline. For a single line
    // this puts the baseline |descent| above the anchor, so descenders end
    // exactly on the box's bottom edge.
    final baseY = origin.dy + total - i * lineH - f.ascent * height;
    var penX = origin.dx;
    for (final cp in lines[i].runes) {
      final g = f.glyph(cp);
      if (g == null) {
        penX += f._blank * height;
        continue;
      }
      for (final c in g.contours) {
        out.add([
          for (final p in c) Offset(penX + p.dx * height, baseY + p.dy * height)
        ]);
      }
      penX += g.advance * height;
    }
  }
  return TextLayout(out, Size(maxW, total));
}

/// The box [text] occupies at [height] mm, without building its contours.
Size measureText(String text, String fontName, double height) {
  if (height <= 0) return Size.zero;
  final f = VectorFont.of(fontName);
  var maxW = 0.0;
  final lines = text.split('\n');
  for (final ln in lines) {
    var w = 0.0;
    for (final cp in ln.runes) {
      w += f.glyph(cp)?.advance ?? f._blank;
    }
    maxW = math.max(maxW, w);
  }
  return Size(maxW * height, f.lineHeight * height * lines.length);
}
