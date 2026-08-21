// M234 — numbers as the current language writes them.
//
// DISPLAY ONLY. Nothing here ever reaches a file, a rebuild signature or the
// kernel: `PartFeature.ownSig()` and the DXF/STEP writers build their strings
// with `toStringAsFixed` directly and are deliberately left alone, because a
// comma in a rebuild key would invalidate every cached solid in every existing
// document — a data change wearing a formatting change's clothes.
//
// Parsing goes the other way and is deliberately WIDER than the display: [num]
// accepts both conventions whatever the UI language, so a user who types
// "12.5" into a German field still gets 12.5 and a document typed in one
// language opens in the other. Most of this app already did that
// (`replaceAll(',', '.')` appears at a dozen call sites, and params.dart even
// uses ';' as its argument separator so that ',' can be a decimal mark); this
// only gives it one name.
import 'l.dart';

class Fmt {
  Fmt._();

  /// ',' in German, '.' in English.
  static String get decimalSeparator =>
      L.locale.value.languageCode == kDe.languageCode ? ',' : '.';

  /// [v] with [decimals] places, in the current language's convention.
  static String fixed(double v, int decimals) {
    final s = v.toStringAsFixed(decimals);
    return decimalSeparator == '.' ? s : s.replaceAll('.', decimalSeparator);
  }

  /// A millimetre reading: `12,50 mm` / `12.50 mm`.
  ///
  /// The unit stays "mm" in both languages — it is the SI symbol, not a word,
  /// and DIN 1301 spells it exactly as the English does.
  static String mm(double v, {int decimals = 2}) => '${fixed(v, decimals)} mm';

  /// An angle: `45,0°`. No space before the degree sign in either language.
  static String deg(double v, {int decimals = 1}) => '${fixed(v, decimals)}°';

  /// A number the user typed, in either convention. Null when it is not one.
  static double? num(String s) =>
      double.tryParse(s.trim().replaceAll(',', '.'));
}
