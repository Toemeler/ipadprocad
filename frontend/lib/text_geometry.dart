// M220 — a sketch text AS GEOMETRY.
//
// [vector_font.dart] turns a string into closed contours; this file is where
// those contours become part of the sketch: entities the DXF exporter writes,
// loops the profile finder hands the kernel, curves the viewports draw.
//
// The contours are NOT stored in `SketchModel.geometry`. A text is one object
// with one anchor — Inventor's is too — while its outline is hundreds of
// points, and every one of them would otherwise become a solver unknown, a
// grip under the finger and an entry in every undo snapshot. So the text
// stays what it is (template, anchor, height, font, layer; sidecar-persisted,
// M44) and its geometry is DERIVED here, cached per text, and injected at the
// three places that need real curves:
//
//   * the DXF export  (AppState._writeExportDxf)      -> it is in the file
//   * the profile finder (part_model.profileLoops)    -> it can be extruded
//   * the painters (viewport, viewport3d, reality_scene) -> it is lines
import 'dart:ui';

import 'app_state.dart' show SketchModel;
import 'constraints.dart' show CType;
import 'ffi/qcad_engine.dart' show Geo, kDefaultLayer;
import 'inserts.dart';
import 'vector_font.dart';

/// Every named value a text template can reference: the sketch's dimensions
/// (by parameter name) and its user parameters.
///
/// A plain function of the sketch, so anything that needs to RENDER a
/// template — including the geometry derivation below, which has no AppState
/// — can ask for it. `AppState.paramTable` forwards here.
Map<String, double> sketchParamTable(SketchModel s) => {
      for (final c in s.constraints)
        if (c.type == CType.dimension && c.paramName != null && c.value != null)
          c.paramName!: c.value!,
      for (final u in s.userParams) u.name: u.value,
    };

/// [t]'s template with its <Parameter> placeholders filled in.
String renderedText(SketchModel s, SketchText t) =>
    renderTemplate(t.template, sketchParamTable(s));

class _Bake {
  final String key;
  final TextLayout layout;
  _Bake(this.key, this.layout);
}

final Expando<_Bake> _bakes = Expando<_Bake>('text outlines');

/// The laid-out outline of [t]: contours in sketch mm, plus its box.
///
/// Cached on the text itself and re-derived only when something that changes
/// the shape changes — this runs on every paint and every profile query.
TextLayout textLayoutOf(SketchModel s, SketchText t) {
  final rendered = renderedText(s, t);
  final key = '$rendered|${t.height}|${t.font}|${t.x}|${t.y}';
  final hit = _bakes[t];
  if (hit != null && hit.key == key) return hit.layout;
  final l = layoutText(rendered, t.font, t.height, origin: Offset(t.x, t.y));
  _bakes[t] = _Bake(key, l);
  return l;
}

/// The closed contours of [t] in sketch mm (each one a loop; the inside of an
/// "o" is a contour of its own).
List<List<Offset>> textContours(SketchModel s, SketchText t) =>
    textLayoutOf(s, t).contours;

/// The box [t] occupies, for the bounding rectangle and its snap points.
/// Same measurement the outline is built from, so the dashed rect a user sees
/// in edit mode is exactly what the letters fill.
Size measureText2D(SketchModel s, SketchText t) => textLayoutOf(s, t).size;

/// The layer a text's geometry belongs to. A text inserted before layers were
/// bound (or loaded from an old sidecar) carries the empty string; that is
/// layer "0", the one every document has, not a layer of its own.
String textLayerOf(SketchText t) => t.layer.isEmpty ? kDefaultLayer : t.layer;

/// Every text of [s] as sketch entities: one CLOSED polyline per contour, on
/// the text's own layer.
///
/// This is what leaves the app — the DXF export pushes these through the
/// engine like any other entity, which is what makes a text "actually there"
/// in the exported file instead of a label that never existed outside the
/// screen.
List<Geo> textGeometry(SketchModel s) {
  final out = <Geo>[];
  for (final t in s.texts) {
    for (final c in textContours(s, t)) {
      if (c.length < 3) continue;
      out.add(Geo(
          Geo.polyline,
          [
            1, // closed
            c.length.toDouble(),
            for (final p in c) ...[p.dx, p.dy],
          ],
          layer: textLayerOf(t)));
    }
  }
  return out;
}
