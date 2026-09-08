// M409 — how far the scene reaches from the world origin, and who owns that
// number.
//
// #30: "if i zoom far in on windows part of the solid gets cut away from the
// view on windows."
//
// An orthographic depth buffer is LINEAR, so the near/far bracket has to be
// sized to the scene or the edge ribbons speckle against the faces they lie
// on — [OrthographicProjection] says so at length, and the bracket is built
// from the number this class holds. It used to be re-measured from each scene
// payload, and that is the bug: a scene push OMITS the geometry of a solid
// whose mesh has not changed (see `includeGeometry` in reality_payload), so
// the first push measured the part and every push after it measured nothing.
// The radius fell to its floor, the bracket then followed the ZOOM alone —
// wide open zoomed out, a slab tens of millimetres thick zoomed in — and a
// part sitting 400 mm from the origin was cut in half by the near plane.
//
// So the reach is kept PER SOLID, for as long as the renderer holds that
// solid, and a payload that says nothing about a solid's geometry says nothing
// about its reach. That is the whole rule, and it is here rather than inline
// so it can be tested without a GPU.
library;

/// The reach of every solid a viewport holds, and the radius that brackets
/// them all.
class SceneExtent {
  final Map<String, _Reach> _by = {};

  /// New geometry arrived for [id]: [local] is the farthest any of its
  /// vertices lies from the origin of ITS OWN buffers.
  void measure(String id, double local) =>
      (_by[id] ??= _Reach()).local = local;

  /// [id]'s node was placed [distance] from the world origin. A part's solids
  /// are already in world coordinates and this is zero; an assembly
  /// component's buffers are in its source part's frame, so its reach is the
  /// two added.
  void placeAt(String id, double distance) =>
      (_by[id] ??= _Reach()).placed = distance;

  /// [id] has left the scene.
  void forget(String id) => _by.remove(id);

  /// Everything, for a viewport being torn down or reloaded.
  void clear() => _by.clear();

  /// Ids currently accounted for. Test seam and a cheap debug read.
  Iterable<String> get ids => _by.keys;

  /// The farthest any solid reaches from the world origin.
  ///
  /// The two floors are the ones the per-payload measurement had, so nothing
  /// but the #30 case changes: 50 before any solid has arrived — a scene of
  /// nothing but origin planes still needs a usable range — and 1 under a
  /// solid that measures smaller, so a small part keeps its tight bracket.
  double get radius {
    if (_by.isEmpty) return 50;
    var r = 1.0;
    for (final e in _by.values) {
      final d = e.local + e.placed;
      if (d > r) r = d;
    }
    return r;
  }
}

class _Reach {
  double local = 0;
  double placed = 0;
}

/// The orthographic depth bracket for a scene of [radius] viewed at [halfH].
///
/// [dist] is how far the eye is pulled back along the view direction; near and
/// far are view-space depths, so the visible slab is the 4 * pad centred on the
/// plane through the world origin. Bracketing tightly is the point — see
/// [OrthographicProjection.near] — but never more tightly than the scene.
({double dist, double near, double far}) orthoDepthBracket({
  required double radius,
  required double halfH,
}) {
  final pad = (radius > halfH ? radius : halfH) + 10;
  final dist = pad * 4;
  final near = (dist - pad * 2) < 0.001 ? 0.001 : dist - pad * 2;
  return (dist: dist, near: near, far: dist + pad * 2);
}
