// M272 — a colour on a body, and the smallest honest version of it.
//
// Inventor separates MATERIAL (density, yield, what the part is made of) from
// APPEARANCE (what it looks like). This is the appearance half, under the name
// the user asked for, and it is deliberately only that: a flat list of tones
// you assign to a body or a component so an assembly stops being eight
// identical grey lumps. No physical properties, no mass, no library — those
// are a different feature and pretending otherwise with a half-filled dialog
// would be worse than not having it.
//
// WHY IT COSTS ALMOST NOTHING TO RENDER. The wire format has carried a per-
// solid `tint` since M241, because a selected assembly component has to
// recolour without re-uploading its mesh. A material is exactly that, minus
// the "temporary": the same field, the same renderer, no Swift. What it needs
// is somewhere to be REMEMBERED (the body in a part, the occurrence in an
// assembly) and a rule for what wins when a body is both selected and painted.
//
// THAT RULE: selection beats material. A selected body is blue whatever it is
// made of, because selection is a question the user just asked and the colour
// is a fact they set once. The same rule the hover tone already follows, and
// the same reason: two tints compound into a third that means nothing.
import 'dart:ui' show Color;

import 'l10n/l.dart';

/// The default: no colour of its own, so the body renders in the palette's
/// steel exactly as it always has. Stored as the ABSENCE of an entry, never as
/// the string — see [materialArgb].
const String kMaterialSteel = 'steel';

/// One assignable appearance.
class PartMaterial {
  final String id;

  /// The body's base colour, opaque. The renderer's tint replaces the steel
  /// base wholesale, so this is the colour the solid actually comes out.
  final int argb;
  const PartMaterial(this.id, this.argb);
  Color get color => Color(argb);
}

/// The list, in the order it is offered.
///
/// Four metals then four colours, and every one of them MUTED. A saturated
/// primary on a shaded solid loses its modelling — the lit face and the shadow
/// converge on the same screaming hue and the body reads flat. These sit
/// around 30-45% saturation, which is where a solid still looks lit.
///
/// Steel is not in the list: it is the absence of a material, and it is added
/// as the first row of the menu by the caller so "back to plain" is one tap
/// rather than a separate command.
const List<PartMaterial> kMaterials = [
  PartMaterial('aluminium', 0xFFC9CDD2),
  PartMaterial('graphite', 0xFF565B61),
  PartMaterial('brass', 0xFFC2A462),
  PartMaterial('copper', 0xFFB87A5A),
  PartMaterial('red', 0xFFC05B54),
  PartMaterial('green', 0xFF6E9B71),
  PartMaterial('blue', 0xFF5D82AF),
  PartMaterial('violet', 0xFF8B7BA8),
];

/// Every id this build offers, steel included. The order of the menu.
List<String> get materialIds => [kMaterialSteel, for (final m in kMaterials) m.id];

/// The colour [id] paints, or null for steel and for anything this build does
/// not offer.
///
/// Null rather than a fallback colour, because "no tint" and "a tint that
/// happens to be steel-coloured" are different on the wire: the first leaves
/// the renderer's own steel material alone, shading and all.
int? materialArgb(String? id) {
  if (id == null || id == kMaterialSteel) return null;
  for (final m in kMaterials) {
    if (m.id == id) return m.argb;
  }
  return null;
}

/// Normalises what a document remembered: null for steel, for an unknown id,
/// and for the empty string.
///
/// An id this build does not offer becomes steel rather than being kept,
/// because unlike a settings preference (which the user can re-choose) a body
/// carrying an unrenderable material would simply look wrong with no way to
/// find out why.
String? sanitiseMaterial(Object? raw) {
  if (raw is! String || raw.isEmpty || raw == kMaterialSteel) return null;
  return materialArgb(raw) == null ? null : raw;
}

/// The user-visible name of an appearance. In the ARB, like every other
/// string — the ids above are storage keys and are never shown.
String materialName(AppL10n t, String? id) => switch (id) {
      'aluminium' => t.matAluminium,
      'graphite' => t.matGraphite,
      'brass' => t.matBrass,
      'copper' => t.matCopper,
      'red' => t.matRed,
      'green' => t.matGreen,
      'blue' => t.matBlue,
      'violet' => t.matViolet,
      _ => t.matSteel,
    };
