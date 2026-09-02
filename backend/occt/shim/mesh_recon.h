/*
 * M232 — mesh -> B-Rep reconstruction.
 *
 * The front half of a mesh-to-CAD converter, written against OCCT because the
 * back half (intersect analytic surfaces, trim faces to wires, sew a shell,
 * heal it into a solid) already lives there and nothing else would do it any
 * better. See M232_MESH_TO_CAD_ANALYSIS.md for why this is written rather
 * than imported: there is no open-source library that does this job.
 *
 * The shape of the pipeline is the published one — Benko/Martin/Varady, CAD
 * 33(11) 2001 — and it runs in this order:
 *
 *   weld -> adjacency -> orient -> sharp edges -> smooth patches
 *        -> fit a primitive per patch (plane/cylinder/cone/sphere/torus)
 *        -> split patches that do not fit, by growing with a running fit
 *        -> regularise (snap axes parallel, merge coaxial, equalise radii)
 *        -> build faces on the ANALYTIC surfaces, edges on their exact
 *           intersection curves
 *        -> sew, heal, solidify
 *
 * EVERY stage degrades rather than fails. A patch that fits nothing becomes a
 * B-spline; a face that will not build becomes its own triangles; a shell that
 * will not close stays a shell. A converter that returns nothing on a hard
 * model is worth less than one that returns something honest and says what it
 * could not do — which is what Report is for.
 *
 * Internal to the shim. The C ABI over it is occt_brep_from_mesh().
 */
#ifndef MESH_RECON_H
#define MESH_RECON_H

#include <TopoDS_Shape.hxx>
#include <string>
#include <vector>

namespace meshrecon {

/* How the caller wants it converted. Zero-initialising this struct gives
 * Defaults() values only if you call Defaults(); the fields have no implicit
 * sane value, so always start from Defaults(). */
struct Params
{
    /* 0 = faceted (one face per triangle, coplanar-merged afterwards)
     * 1 = prismatic (fit surfaces; fall back to faceted per patch) */
    int mode;
    /* Surface fit tolerance, as a FRACTION of the bounding-box diagonal. One
     * absolute tolerance cannot serve a 200 mm bracket and a 4 mm pin in the
     * same app; every length in here is relative for that reason. */
    double tol_frac;
    /* Dihedral angle, in degrees, past which an edge is a sharp feature and a
     * patch boundary. */
    double sharp_deg;
    /* Vertex weld tolerance, as a fraction of the diagonal. */
    double weld_frac;
    /* Angle, in degrees, within which two axes are snapped parallel and an
     * axis is snapped to a global one. 0 disables regularisation. */
    double snap_deg;
    /* Relative tolerance within which two radii are made equal. 0 disables. */
    double snap_radius_frac;
    /* Refuse to build a faceted B-Rep with more triangles than this. A
     * half-million-face B-Rep is not a CAD model, it is a way to hang an
     * iPad — see the comment on the check itself. */
    int max_faceted_triangles;
    /* Smallest patch, in triangles, still worth fitting a surface to. */
    int min_patch_triangles;
};

Params Defaults();

/* ---- what the converter is doing, while it is doing it ------------------
 *
 * M333. The kernel call blocks the Dart isolate, so nothing on that side can
 * report anything until it returns — which is the whole reason the busy card
 * is drawn by UIKit on the platform thread. That thread is idle and can read
 * these, so this is where honest progress has to come from.
 *
 * Only countable things are published. A weighted percentage across stages
 * would need weights nobody has measured, and a bar filling at a guessed rate
 * is caught out by the first model that does not match the guess. Instead:
 * which stage, and where within it, when the stage has something to count.
 * `total` of 0 means this stage cannot be counted and the bar should sweep. */
enum Stage
{
    kStageIdle = 0,
    kStageWelding,   /* reading the mesh, welding vertices */
    kStageSegmenting,/* finding the smooth patches */
    kStageFitting,   /* fitting a surface per patch — counts patches */
    kStageFreeform,  /* covering what fits no primitive — counts runs */
    kStageBuilding,  /* building the B-Rep faces — counts patches */
    kStageSewing,    /* sewing, healing, solidifying */
    kStageFaceted,   /* the 1:1 path — counts triangles */
    kStageMerging,   /* merging coplanar faces after the 1:1 path */
    kStageCount
};

/* Reads the current stage and its counters. Safe to call from any thread at
 * any time, including when no conversion is running (stage comes back
 * kStageIdle). Never blocks. */
void Progress(int &stage, int &done, int &total);

/* The stage's name, in English, for a caller with no message catalogue. Never
 * null; returns "" for kStageIdle. */
const char *StageName(int stage);

/* Where the bar is over the WHOLE conversion, in thousandths (0..1000).
 *
 * M335. One bar, not one per stage: a bar that empties and refills four times
 * cannot be read. Each stage owns a span of this, and the spans were measured
 * across four models spanning 1,138 to 83,178 triangles — see SpanOf. It never
 * goes backwards and never reaches 1000 before the conversion returns.
 *
 * Safe from any thread at any time; 0 when nothing is running. */
int Overall();

/* The furthest the CURRENT stage could take the bar — the top of its span.
 *
 * A stage that can count itself makes Overall() exact and this is only a
 * bound. A stage that cannot (merging coplanar faces is a third of a 1:1
 * conversion and OCCT offers no way in) leaves Overall() at the bottom of its
 * span, and whoever draws the bar should ease it towards this on elapsed time
 * without passing it — so the estimate lives in the drawing, where being wrong
 * costs a bar that moves at the wrong speed, and not in the measurement, where
 * it would be a lie about the work. 0 when nothing is running. */
int Ceiling();

/* Asks the running conversion to stop.
 *
 * Safe from any thread, including while nothing is running. The conversion
 * abandons its work at the next point where doing so is cheap and safe —
 * between patches, between regions, and inside OCCT's sewing, which is the
 * longest single call and cannot be interrupted any other way — and returns a
 * null shape with `err` set, exactly as a refusal does. Nothing is left half
 * built, and the request is consumed by the run it stops, so it can never
 * cancel the next one. */
void RequestCancel();

/* The exact `err` a cancelled conversion reports, so a caller can tell a
 * cancellation from a failure: one deserves a message and the other does not. */
extern const char *const kCancelledMessage;

/* Whether a cancellation is still pending. Only a test has any use for this:
 * the request is consumed by the run it stops, and this is how that is
 * checked rather than assumed. */
bool Cancelled_ForTest();

/* ---- tessellating a reconstructed body so it has no holes ---------------
 *
 * M333. BRepMesh gives up on some trimmed B-splines and says nothing: no
 * triangulation for that face, or a few triangles covering a fraction of it,
 * and success reported either way. The failure is erratic in the deflection —
 * measured over a 20-step sweep of the whale, the count of empty faces went
 * 1, 4, 3, 2, 2, 1, 1, 2, 1, 0, 1, 2, 2, 3, 2, ... — so it is a bug to search
 * around, not a function to solve.
 *
 * Asking again for the offending FACE recovers it and splits the edges it
 * shares: two faces polygonising one edge at two deflections do not agree, and
 * on the whale that was 442 mm of edge split by more than a millimetre. Asking
 * again for the WHOLE SHAPE cannot do that — every edge is discretised once,
 * by the pass that meshed both its faces.
 *
 * Meshes `s` in place. `factor` carries the DEFLECTION that last covered this
 * shape, in and out: pass 0 the first time and the same variable afterwards.
 * An absolute length, not a multiple of `lin` — a multiplier carried into a
 * zoomed-in request means a tessellation nobody asked for, and on the whale
 * that was 107,975 triangles and 127 seconds for one re-draw. The shape is
 * meshed at `lin` or at that remembered deflection, whichever is finer, so a
 * request already past the size BRepMesh was failing at costs exactly what a
 * plain tessellation costs.
 *
 * The search for a working deflection therefore happens ONCE per shape, at the
 * first (coarsest) draw, and is bounded by a time budget on top of that. Every
 * later zoom is a single tessellation. Returns the number of faces left with
 * no triangles at all. Never throws. */
int TessellateCovered(const TopoDS_Shape &s, double lin, double ang,
                      std::vector<double> &faceArea, double &factor);

/* Let two faces that meet smoothly share one normal where they touch.
 *
 * `verts` and `norms` are the renderer's buffers, three doubles each, one entry
 * per vertex, with vertices emitted PER FACE — so a node on a shared edge
 * appears once for each face and carries that face's own surface normal. Where
 * the two agree to within the crease angle they are the same surface cut up,
 * not an edge, and are given one averaged normal; where they do not, both are
 * left alone. Changes no geometry: `verts` is read, only `norms` is written.
 *
 * `freeform` is one byte per vertex, non-zero when that vertex's face is a
 * freeform patch, and may be empty — then every pair gets the narrow rule.
 * Never throws. */
void ShareNormalsAcrossSeams(const std::vector<double> &verts,
                             const std::vector<unsigned char> &freeform,
                             std::vector<double> &norms);

/* How far two faces may disagree at a shared node and still be shaded as one
 * surface: the wide angle between two freeform patches, which are one surface
 * cut up, and mere tangency between anything else, whose edges are designed.
 * Exposed for the tests, which check both. */
extern const double kCreaseAngleDeg;
extern const double kTangentAngleDeg;

/* What actually happened. Filled in even when the conversion fails, because
 * "it produced 4000 faceted patches" is the explanation for a slow, useless
 * result and the user is entitled to it. */
struct Report
{
    int triangles_in, vertices_in;
    int triangles_used, vertices_welded;
    int non_manifold_edges, boundary_edges;
    int flipped_triangles;
    int patches;
    int planes, cylinders, cones, spheres, tori, freeform, faceted_patches;
    int faces_built, faces_failed;
    int analytic_edges, approximated_edges;
    int shells, solids;
    int closed;      /* 1 when the result is a closed solid */
    double fit_rms;  /* area-weighted, in model units */
    double diagonal; /* bounding-box diagonal of the input */
};

void ClearReport(Report &r);

/* Reconstructs a B-Rep from an indexed triangle mesh.
 *
 * xyz holds nv*3 doubles, tri holds nt*3 zero-based vertex indices. Winding is
 * taken as the file gave it and corrected internally, so a mesh whose normals
 * all point inward still comes out a solid.
 *
 * Returns a null shape on failure, with `err` set. Never throws. */
TopoDS_Shape Reconstruct(const double *xyz, int nv, const int *tri, int nt,
                         const Params &p, Report &rep, std::string &err);

} // namespace meshrecon

#endif /* MESH_RECON_H */
