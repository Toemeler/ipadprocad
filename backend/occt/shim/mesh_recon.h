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
