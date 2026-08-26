// M268 — the shape of the OPEN DOCUMENT, as perf gauges.
//
// Five numbers — how many features, how many of them contribute a solid, how
// many triangles that adds up to, and how much sketch geometry there is —
// which together answer the first question anyone asks of a slow frame: was
// the app slow, or was the model big? A frame time without them is a number
// with no denominator.
//
// WHY IT IS ITS OWN FILE, AND NOT A WIDGET. These lived in the bottom-right
// performance overlay (M77) and were computed as a side effect of drawing it:
// the counts existed only while a 9 pt debug readout was on screen, and the
// walk ran on the readout's cadence rather than on the reporting one. With the
// overlay gone the numbers stay, pulled by Perf.report() when a snapshot is
// actually written — which is both cheaper and, for a bug bundle from a device
// nobody was watching, the first time they are reliably there at all.
//
// Pure but for the AppState it is handed, so a test can pin the counts on a
// built part without a frame, a timer or a widget tree.
import 'app_state.dart';
import 'perf.dart';

/// Gauge names. Constants because ci/perf_gate.py names the same five in its
/// skip list — they describe what the person had open, not what the suite
/// did, so they are reported and never gated — and a silent rename here would
/// turn that exemption off.
const String kGaugeFeatures = 'features';
const String kGaugeSolids = 'solids';
const String kGaugeTriangles = 'triangles';
const String kGaugeSketchEntities = 'sketchEntities';
const String kGaugeSketchProjections = 'sketchProjections';

/// The counts for whatever [app] currently has open.
///
/// A key is ABSENT rather than zero when there is nothing of that kind open:
/// on the gallery, with no part and no sketch, "0 triangles" and "no model" are
/// different facts, and a reader of a bug bundle has to be able to tell them
/// apart.
Map<String, int> documentGauges(AppState app) {
  final out = <String, int>{};
  final p = app.currentPart;
  if (p != null) {
    var tris = 0, solids = 0, feats = 0;
    for (final f in p.features) {
      feats++;
      final s = f.solid;
      // The same three exclusions the renderer applies, so this counts what is
      // actually on screen: a feature with no solid built nothing, a hidden one
      // is not drawn, and one consumed by a join was absorbed into another
      // body and its triangles are already counted there.
      if (s == null || !f.visible || f.consumedByJoin) continue;
      solids++;
      tris += s.mesh.indices.length ~/ 3;
    }
    out[kGaugeFeatures] = feats;
    out[kGaugeSolids] = solids;
    out[kGaugeTriangles] = tris;
  }
  final s = app.current;
  if (s != null) {
    var proj = 0;
    for (final g in s.geometry) {
      if (g.isProjection) proj++;
    }
    out[kGaugeSketchEntities] = s.geometry.length;
    out[kGaugeSketchProjections] = proj;
  }
  return out;
}

/// The registered closure, so a second install REPLACES the first.
///
/// It closes over an AppState, and a hot restart or a test that builds a second
/// shell makes a new one. Left stacked, the older closure would keep answering
/// from an app nobody is using and the two would overwrite each other's numbers
/// in registration order — the kind of defect that only ever shows up in a
/// bundle from a device, as counts that belong to no visible document.
Map<String, int> Function()? _source;

/// Registers [documentGauges] with [Perf] for the life of the app.
///
/// Called from main() rather than from a widget's initState for the reason the
/// whole file exists: the numbers must not depend on anything being displayed.
void installDocumentGauges(AppState app) {
  final prev = _source;
  if (prev != null) Perf.removeGaugeSource(prev);
  final next = () => documentGauges(app);
  _source = next;
  Perf.addGaugeSource(next);
}
