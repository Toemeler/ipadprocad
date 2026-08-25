/*
 * Prototype — OCCT shim smoke test. Pure C, no Flutter, no Dart: calls the
 * flat C ABI exactly the way the (future) Dart FFI will, and asserts REAL
 * geometry with hard numbers. This is the gate that decides whether OCCT
 * holds up as the 3D kernel — treat a red run as a real red.
 *
 * Scenarios (deliberately more than "a cube works"):
 *   [1] box            — exact topology counts (6/12/8) + exact volume
 *   [2] L-profile      — non-convex sketch extrude: 8 faces, 18 edges,
 *                        12 vertices, volume = area * height
 *   [3] cylinder       — curved geometry: 3 faces, analytic volume
 *   [4] fuse           — box ∪ half-embedded cylinder: analytic volume
 *                        (8000 + pi*r^2*h/2), valid, face count grows
 *   [5] STEP roundtrip — export the fused solid, re-import, counts equal,
 *                        volume within STEP tolerance, still valid
 *   [6] failure paths  — import of a missing file returns NULL (no crash),
 *                        free(NULL) tolerated, degenerate box rejected
 *
 * v2 scenarios (extrude with holes + taper, tessellation):
 *   [7]  extrude_profile, 1 loop — must match occt_extrude_polygon exactly
 *   [8]  extrude_profile, plate with a hole — exact topology + volume
 *   [9]  extrude_profile, tapered square — exact frustum volume, and the
 *        SIGN check: positive taper must flare OUTWARD (Inventor rule)
 *   [10] tapered plate WITH hole — outer grows, hole shrinks (analytic)
 *   [11] mesh of the box — 12 triangles, 12 edges, outward winding proven
 *        by the divergence-theorem volume (= +6000) and outward normals
 *   [12] mesh of a cylinder — curved-face triangulation + smooth edges,
 *        mesh volume within tessellation tolerance of the analytic value
 *   [13] transform — rigid placement: translation moves the bbox exactly,
 *        a 90-degree rotation swaps extents, volume is invariant, and a
 *        matrix with scale is REJECTED (rigid motions only)
 *   [14] v2 failure paths — NULL in, NULL out, free(NULL) tolerated
 *   [15] v3 TRUE-ARC extrude — a circle written as two bulge arcs makes an
 *        EXACT cylinder: 3 faces (a 96-gon prism would have 98), analytic
 *        volume, and its mesh shows exactly 2 rim edge polylines (no facet
 *        verticals, seam suppressed) — the "smooth cylinder" guarantee
 *   [16] v4 display metadata — per-triangle face ids, per-face surface
 *        records (plane/cylinder + frames), per-edge ANALYTIC curves
 *        (the rims report as exact circles r=10, sweep 2π), and occt_unify
 *        collapsing the split faces of a box|box fuse
 *   [17] v5 boolean CUT — block with a through-pocket (analytic volume,
 *        operands left intact, an all-erasing cut reported as failure)
 *   [18] v5 boolean COMMON — overlap of two offset cubes (analytic volume,
 *        disjoint inputs reported as failure)
 *   [19] v8 ASYMMETRIC arc — a circular segment (arc + its chord) keeps its
 *        bulge on the RIGHT of p0->p1: bbox proves the arc is not mirrored
 *        across the chord (volume cannot — a mirror preserves area), and
 *        the reverse traversal gives the identical solid
 *
 * v21 scenario:
 *   [35] bulk edge enumeration — occt_shape_edges_info against
 *        occt_shape_edge_info on four solids, all twelve doubles compared
 *        BITWISE (memcmp, not a tolerance), plus a coverage assertion that
 *        the fixtures really did produce a convex edge, a concave edge, a
 *        straight edge and a circular one. The bulk path is the fix for the
 *        Theta(n^2) of PERFORMANCE_PROFILE.md section 6.5; its only real risk
 *        is a silently different record, so that is what is pinned
 *
 * v22 scenario:
 *   [36] convexity, DIFFERENTIALLY — occt_shape_edges_info (the local wedge
 *        test v22 ships) against occt_shape_edges_info_ref (the pre-v22 solid
 *        classifier), both run HERE, on THIS machine, in THIS process. Not a
 *        recorded golden: a constant recorded on one machine pins that
 *        machine's digits and says nothing about whether two paths agree,
 *        which is what build 437 cost us (OPTIMIZATION_PLAN_2.md section 1.4).
 *        Fields 0..10 must match bitwise on every fixture, because the change
 *        cannot reach them. Field 11 must match bitwise on every fixture
 *        EXCEPT the deliberately thin-walled ones, where the two are KNOWN to
 *        differ and the classifier is the one that is wrong — a box is a
 *        convex solid, so the ground truth there needs no second opinion
 *
 * v27 scenarios — S15 (holed sweep) and S16 (the straight audit):
 *   [40] EVERY direction, axis and placement parameter in this shim, bent
 *        once on purpose. S14 fixed three defects in the sweep and closed
 *        with a question it could not answer: "I do not know what else in
 *        this shim is only ever exercised straight." The inventory in
 *        perf/findings/S16-straight-audit.md answers it by reading every
 *        call site above — EIGHT parameters had never been passed anything
 *        but their trivial value, and three of those are reachable from the
 *        UI. [40a] a real rotation through occt_transform (the only rotation
 *        this file had was {0,-1,0, 1,0,0, 0,0,1}, exact 0/±1 entries);
 *        [40b] revolve about an oblique, off-origin axis, against PAPPUS
 *        rather than a golden; [40c] a hole revolved about that same axis —
 *        the control for S14's item 2; [40d] the coil's `clockwise` flag,
 *        which nothing had ever set; [40e] the coil about an oblique axis;
 *        [40f] an oblique mirror plane; [40g] a boolean with a ROTATED
 *        operand; [40h] loft with rotated section placements; [40i] a face
 *        moved along an OBLIQUE delta; [40j] the chamfer's `angle >= 90`
 *        guard on a 60° edge; [40k] a fillet on a 135° edge; [40l] chamfer
 *        mode 1, which had no fixture anywhere in this file.
 *
 *        Where no closed form exists the instrument is RIGID EQUIVARIANCE:
 *        op(R·inputs) == R·op(inputs), and volume is invariant under R, so
 *        equality of the two volumes is a necessary condition needing no
 *        analytic formula and no recorded golden — and it fails exactly when
 *        the code has an axis baked in that the caller thinks is a parameter.
 *
 * Output contract for CI (read the log, not the checkmark — HANDOFF rule):
 *   prints "OCCT SMOKE: PASS" on success, "OCCT SMOKE: FAIL (...)" otherwise,
 *   and exits non-zero on any failure.
 */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "occt_capi.h"

static int g_failures = 0;

static void fail(const char *what)
{
    printf("OCCT SMOKE: FAIL (%s; last_error=%s)\n", what, occt_last_error());
    ++g_failures;
}

static int check(int cond, const char *what)
{
    if (!cond)
        fail(what);
    return cond;
}

static int near_rel(double got, double want, double rel)
{
    double denom = fabs(want) > 1e-12 ? fabs(want) : 1.0;
    return fabs(got - want) / denom <= rel;
}

static int counts(occt_shape *s, int *f, int *e, int *v, const char *what)
{
    if (!occt_shape_counts(s, f, e, v)) {
        fail(what);
        return 0;
    }
    return 1;
}

/* M214 — whole file as a NUL-terminated string, or NULL. Caller frees.
 * Used to search an exported STEP for names and units: reading line by line
 * would miss a match that the writer wrapped across a line boundary. */
static char *slurp(const char *path)
{
    FILE *fp = fopen(path, "rb");
    if (!fp) return NULL;
    if (fseek(fp, 0, SEEK_END) != 0) {
        fclose(fp);
        return NULL;
    }
    long sz = ftell(fp);
    if (sz < 0 || sz > (64L << 20)) { /* a smoke-test STEP is tiny */
        fclose(fp);
        return NULL;
    }
    rewind(fp);
    char *buf = (char *)malloc((size_t)sz + 1);
    if (!buf) {
        fclose(fp);
        return NULL;
    }
    size_t got = fread(buf, 1, (size_t)sz, fp);
    fclose(fp);
    buf[got] = '\0';
    return buf;
}

int main(void)
{
    const double PI = 3.14159265358979323846;
    printf("%s (shim ABI v%d)\n", occt_version(), occt_shim_version());
    if (!check(strstr(occt_version(), "Prototype OCCT shim") != NULL,
               "version marker string missing"))
        return 1; /* nothing else is trustworthy */

    /* [1] box --------------------------------------------------------- */
    occt_shape *box = occt_make_box(10.0, 20.0, 30.0);
    if (check(box != NULL, "[1] make_box returned NULL")) {
        int f = 0, e = 0, v = 0;
        if (counts(box, &f, &e, &v, "[1] shape_counts failed")) {
            check(f == 6 && e == 12 && v == 8,
                  "[1] box topology wrong (want 6/12/8)");
            printf("[1] box faces=%d edges=%d vertices=%d\n", f, e, v);
        }
        double vol = occt_shape_volume(box);
        printf("[1] box volume=%.6f (want 6000)\n", vol);
        check(near_rel(vol, 6000.0, 1e-9), "[1] box volume wrong");
        check(occt_shape_valid(box) == 1, "[1] box not valid");
        double bb[6];
        if (check(occt_bbox(box, bb), "[1] bbox failed")) {
            check(near_rel(bb[3] - bb[0], 10.0, 1e-6) &&
                      near_rel(bb[4] - bb[1], 20.0, 1e-6) &&
                      near_rel(bb[5] - bb[2], 30.0, 1e-6),
                  "[1] bbox extents wrong");
        }
    }
    occt_free_shape(box);

    /* [2] non-convex L profile, extruded ------------------------------- */
    /* Area = 40*10 + 10*20 = 600; height 5 -> volume 3000.
     * Prism over a 6-gon: 6+2 faces, 3*6 edges, 2*6 vertices. */
    const double L[] = {0, 0, 40, 0, 40, 10, 10, 10, 10, 30, 0, 30};
    occt_shape *lsolid = occt_extrude_polygon(L, 6, 5.0);
    if (check(lsolid != NULL, "[2] extrude_polygon returned NULL")) {
        int f = 0, e = 0, v = 0;
        if (counts(lsolid, &f, &e, &v, "[2] shape_counts failed")) {
            check(f == 8 && e == 18 && v == 12,
                  "[2] L-prism topology wrong (want 8/18/12)");
            printf("[2] L-prism faces=%d edges=%d vertices=%d\n", f, e, v);
        }
        double vol = occt_shape_volume(lsolid);
        printf("[2] L-prism volume=%.6f (want 3000)\n", vol);
        check(near_rel(vol, 3000.0, 1e-9), "[2] L-prism volume wrong");
        check(occt_shape_valid(lsolid) == 1, "[2] L-prism not valid");
    }
    occt_free_shape(lsolid);

    /* [3] cylinder ------------------------------------------------------ */
    occt_shape *cylA = occt_make_cylinder(0, 0, 0, 6.0, 10.0);
    if (check(cylA != NULL, "[3] make_cylinder returned NULL")) {
        int f = 0;
        if (counts(cylA, &f, NULL, NULL, "[3] shape_counts failed")) {
            check(f == 3, "[3] cylinder face count wrong (want 3)");
            printf("[3] cylinder faces=%d\n", f);
        }
        double vol = occt_shape_volume(cylA);
        double want = PI * 36.0 * 10.0;
        printf("[3] cylinder volume=%.6f (want %.6f)\n", vol, want);
        check(near_rel(vol, want, 1e-6), "[3] cylinder volume wrong");
        check(occt_shape_valid(cylA) == 1, "[3] cylinder not valid");
    }
    occt_free_shape(cylA);

    /* [4] boolean fuse: 20-cube + cylinder half sticking out of the top -- */
    /* Cylinder r=5 h=20 from (10,10,10): lower half inside the cube.
     * Fused volume = 8000 + pi*25*10. Curved/planar intersection — a
     * genuinely non-trivial B-Rep op, not just a cube. */
    occt_shape *cube = occt_make_box(20.0, 20.0, 20.0);
    occt_shape *cylB = occt_make_cylinder(10.0, 10.0, 10.0, 5.0, 20.0);
    occt_shape *fused = NULL;
    if (check(cube != NULL && cylB != NULL, "[4] operand construction failed")) {
        fused = occt_fuse(cube, cylB);
        if (check(fused != NULL, "[4] fuse returned NULL")) {
            double vol = occt_shape_volume(fused);
            double want = 8000.0 + PI * 25.0 * 10.0;
            printf("[4] fused volume=%.6f (want %.6f)\n", vol, want);
            check(near_rel(vol, want, 1e-6), "[4] fused volume wrong");
            check(occt_shape_valid(fused) == 1, "[4] fused shape not valid");
            int f = 0;
            if (counts(fused, &f, NULL, NULL, "[4] shape_counts failed")) {
                printf("[4] fused faces=%d\n", f);
                check(f > 6, "[4] fuse produced no new faces");
            }
        }
    }
    occt_free_shape(cube);
    occt_free_shape(cylB);

    /* [5] STEP roundtrip on the fused solid ------------------------------ */
    const char *tmpdir = getenv("TMPDIR");
    char step_path[1024];
    snprintf(step_path, sizeof(step_path), "%s/prototype_smoke.step",
             (tmpdir && *tmpdir) ? tmpdir : "/tmp");
    if (fused != NULL) {
        if (check(occt_export_step(fused, step_path) == 1,
                  "[5] STEP export failed")) {
            FILE *fp = fopen(step_path, "rb");
            long sz = 0;
            if (fp) {
                fseek(fp, 0, SEEK_END);
                sz = ftell(fp);
                fclose(fp);
            }
            printf("[5] STEP file %s size=%ld bytes\n", step_path, sz);
            check(sz > 5000, "[5] STEP file suspiciously small");

            occt_shape *re = occt_import_step(step_path);
            if (check(re != NULL, "[5] STEP import returned NULL")) {
                int f0 = 0, e0 = 0, v0 = 0, f1 = 0, e1 = 0, v1 = 0;
                if (counts(fused, &f0, &e0, &v0, "[5] counts (orig) failed") &&
                    counts(re, &f1, &e1, &v1, "[5] counts (reread) failed")) {
                    printf("[5] roundtrip faces %d->%d edges %d->%d "
                           "vertices %d->%d\n", f0, f1, e0, e1, v0, v1);
                    check(f0 == f1 && e0 == e1 && v0 == v1,
                          "[5] topology changed across STEP roundtrip");
                }
                double vol0 = occt_shape_volume(fused);
                double vol1 = occt_shape_volume(re);
                printf("[5] roundtrip volume %.6f -> %.6f\n", vol0, vol1);
                check(near_rel(vol1, vol0, 1e-4),
                      "[5] volume drifted across STEP roundtrip");
                check(occt_shape_valid(re) == 1,
                      "[5] re-imported shape not valid");
            }
            occt_free_shape(re);
        }
    } else {
        fail("[5] skipped: no fused shape from [4]");
    }
    occt_free_shape(fused);

    /* [6] failure paths must not crash ----------------------------------- */
    occt_shape *ghost = occt_import_step("/nonexistent/prototype-nope.step");
    check(ghost == NULL, "[6] import of missing file did not return NULL");
    printf("[6] missing-file import -> NULL, last_error=\"%s\"\n",
           occt_last_error());
    occt_free_shape(NULL); /* must be a no-op */
    check(occt_make_box(0.0, 1.0, 1.0) == NULL,
          "[6] degenerate box was not rejected");

    /* ==== v2 surface ==================================================== */

    /* [7] extrude_profile with ONE loop must equal extrude_polygon ------- */
    {
        const double L2[] = {0, 0, 40, 0, 40, 10, 10, 10, 10, 30, 0, 30};
        const int lc[] = {6};
        occt_shape *s = occt_extrude_profile(L2, lc, 1, 5.0, 0.0);
        if (check(s != NULL, "[7] extrude_profile(1 loop) returned NULL")) {
            int f = 0, e = 0, v = 0;
            if (counts(s, &f, &e, &v, "[7] shape_counts failed")) {
                check(f == 8 && e == 18 && v == 12,
                      "[7] single-loop topology differs from extrude_polygon");
                printf("[7] profile prism faces=%d edges=%d vertices=%d\n",
                       f, e, v);
            }
            double vol = occt_shape_volume(s);
            printf("[7] profile prism volume=%.6f (want 3000)\n", vol);
            check(near_rel(vol, 3000.0, 1e-9), "[7] volume wrong");
            check(occt_shape_valid(s) == 1, "[7] not valid");
        }
        occt_free_shape(s);
    }

    /* [8] plate with a hole: 20x10 outer, 4x4 hole, h=5 ------------------ */
    /* Volume = 5 * (200 - 16) = 920. Topology: 4 outer walls + 4 hole
     * walls + top + bottom = 10 faces; 8 verticals + 2*8 rim edges = 24;
     * 2*8 vertices = 16. Hole loop given deliberately in the SAME winding
     * as the outer loop — normalisation is the shim's job. */
    {
        const double P[] = {/* outer 20x10, CCW */
                            0, 0, 20, 0, 20, 10, 0, 10,
                            /* hole 4x4 centred at (10,5), ALSO CCW */
                            8, 3, 12, 3, 12, 7, 8, 7};
        const int lc[] = {4, 4};
        occt_shape *s = occt_extrude_profile(P, lc, 2, 5.0, 0.0);
        if (check(s != NULL, "[8] extrude_profile(hole) returned NULL")) {
            int f = 0, e = 0, v = 0;
            if (counts(s, &f, &e, &v, "[8] shape_counts failed")) {
                check(f == 10 && e == 24 && v == 16,
                      "[8] holed-plate topology wrong (want 10/24/16)");
                printf("[8] holed plate faces=%d edges=%d vertices=%d\n",
                       f, e, v);
            }
            double vol = occt_shape_volume(s);
            printf("[8] holed plate volume=%.6f (want 920)\n", vol);
            check(near_rel(vol, 920.0, 1e-9), "[8] volume wrong");
            check(occt_shape_valid(s) == 1, "[8] not valid");
        }
        occt_free_shape(s);
    }

    /* [9] tapered square prism: a=10, h=5, taper +10 deg (OUTWARD) ------- */
    /* Linear flare: side(z) = a + 2 z tan(t). Exact integral:
     * V = a^2 h + 2 a tan(t) h^2 + (4/3) tan(t)^2 h^3.
     * The volume being LARGER than the straight prism (500) is the sign
     * proof: positive taper must add material (Inventor convention). */
    {
        const double Q[] = {0, 0, 10, 0, 10, 10, 0, 10};
        const int lc[] = {4};
        const double t = tan(10.0 * PI / 180.0), a = 10.0, h = 5.0;
        const double want = a * a * h + 2.0 * a * t * h * h +
                            (4.0 / 3.0) * t * t * h * h * h;
        occt_shape *s = occt_extrude_profile(Q, lc, 1, h, 10.0);
        if (check(s != NULL, "[9] tapered extrude returned NULL")) {
            double vol = occt_shape_volume(s);
            printf("[9] tapered square volume=%.6f (want %.6f)\n", vol, want);
            check(near_rel(vol, want, 1e-6), "[9] frustum volume wrong");
            check(vol > 500.0,
                  "[9] SIGN ERROR: positive taper must flare outward");
            check(occt_shape_valid(s) == 1, "[9] not valid");
        }
        occt_free_shape(s);
        /* negative taper of the same prism must SHRINK it */
        occt_shape *sn = occt_extrude_profile(Q, lc, 1, h, -10.0);
        if (check(sn != NULL, "[9] negative-taper extrude returned NULL")) {
            const double wantn = a * a * h - 2.0 * a * t * h * h +
                                 (4.0 / 3.0) * t * t * h * h * h;
            double voln = occt_shape_volume(sn);
            printf("[9] neg-taper volume=%.6f (want %.6f)\n", voln, wantn);
            check(near_rel(voln, wantn, 1e-6), "[9] neg-taper volume wrong");
            check(voln < 500.0,
                  "[9] SIGN ERROR: negative taper must taper inward");
        }
        occt_free_shape(sn);
    }

    /* [10] tapered plate WITH hole: outer grows, hole SHRINKS ------------ */
    /* Outer 20x20, hole 8x8 centred, h=5, taper +5 deg.
     * V = [A^2 h + 2 A t h^2 + (4/3) t^2 h^3]      (outer, growing)
     *   - [B^2 h - 2 B t h^2 + (4/3) t^2 h^3]      (hole, shrinking)     */
    {
        const double P[] = {0,  0,  20, 0,  20, 20, 0,  20,
                            6,  6,  14, 6,  14, 14, 6,  14};
        const int lc[] = {4, 4};
        const double t = tan(5.0 * PI / 180.0), A = 20.0, B = 8.0, h = 5.0;
        const double wo = A * A * h + 2.0 * A * t * h * h +
                          (4.0 / 3.0) * t * t * h * h * h;
        const double wh = B * B * h - 2.0 * B * t * h * h +
                          (4.0 / 3.0) * t * t * h * h * h;
        occt_shape *s = occt_extrude_profile(P, lc, 2, h, 5.0);
        if (check(s != NULL, "[10] tapered holed extrude returned NULL")) {
            double vol = occt_shape_volume(s);
            printf("[10] tapered holed volume=%.6f (want %.6f)\n", vol,
                   wo - wh);
            check(near_rel(vol, wo - wh, 1e-6),
                  "[10] tapered-hole volume wrong (hole must shrink)");
            check(occt_shape_valid(s) == 1, "[10] not valid");
        }
        occt_free_shape(s);
    }

    /* [11] mesh of the 10x20x30 box -------------------------------------- */
    {
        occt_shape *b = occt_make_box(10.0, 20.0, 30.0);
        occt_mesh *m = b ? occt_mesh_create(b, 0.5, 0.5) : NULL;
        if (check(m != NULL, "[11] mesh_create(box) returned NULL")) {
            int nv = 0, nt = 0, ne = 0, nep = 0;
            if (check(occt_mesh_counts(m, &nv, &nt, &ne, &nep),
                      "[11] mesh_counts failed")) {
                printf("[11] box mesh: %d verts, %d tris, %d edges, "
                       "%d edge pts\n", nv, nt, ne, nep);
                check(nt == 12, "[11] box must mesh to 12 triangles");
                check(nv >= 8 && nv <= 36, "[11] vertex count implausible");
                check(ne == 12, "[11] box must expose 12 edge polylines");
                check(nep == 24, "[11] straight edges must have 2 pts each");
            }
            double *vv = (double *)malloc(sizeof(double) * 3 * nv);
            double *nn = (double *)malloc(sizeof(double) * 3 * nv);
            int *tt = (int *)malloc(sizeof(int) * 3 * nt);
            int *es = (int *)malloc(sizeof(int) * (ne + 1));
            double *ep = (double *)malloc(sizeof(double) * 3 * nep);
            if (check(vv && nn && tt && es && ep, "[11] out of memory") &&
                check(occt_mesh_vertices(m, vv), "[11] mesh_vertices") &&
                check(occt_mesh_normals(m, nn), "[11] mesh_normals") &&
                check(occt_mesh_triangles(m, tt), "[11] mesh_triangles") &&
                check(occt_mesh_edges(m, es, ep), "[11] mesh_edges")) {
                /* index range + divergence-theorem volume (winding proof) */
                int idx_ok = 1;
                double vol6 = 0.0;
                for (int i = 0; i < nt; ++i) {
                    const int i0 = tt[3 * i], i1 = tt[3 * i + 1],
                              i2 = tt[3 * i + 2];
                    if (i0 < 0 || i1 < 0 || i2 < 0 || i0 >= nv ||
                        i1 >= nv || i2 >= nv) {
                        idx_ok = 0;
                        break;
                    }
                    const double *p0 = vv + 3 * i0, *p1 = vv + 3 * i1,
                                 *p2 = vv + 3 * i2;
                    const double cx = p1[1] * p2[2] - p1[2] * p2[1];
                    const double cy = p1[2] * p2[0] - p1[0] * p2[2];
                    const double cz = p1[0] * p2[1] - p1[1] * p2[0];
                    vol6 += p0[0] * cx + p0[1] * cy + p0[2] * cz;
                }
                check(idx_ok, "[11] triangle index out of range");
                printf("[11] mesh signed volume=%.6f (want +6000)\n",
                       vol6 / 6.0);
                check(near_rel(vol6 / 6.0, 6000.0, 1e-6),
                      "[11] winding not consistently outward");
                /* normals: unit length AND pointing away from the centre */
                int norm_ok = 1;
                for (int i = 0; i < nv; ++i) {
                    const double *n = nn + 3 * i, *p = vv + 3 * i;
                    const double len =
                        sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]);
                    if (fabs(len - 1.0) > 1e-6) {
                        norm_ok = 0;
                        break;
                    }
                    const double d = n[0] * (p[0] - 5.0) +
                                     n[1] * (p[1] - 10.0) +
                                     n[2] * (p[2] - 15.0);
                    if (d < 1e-9) { /* convex box: outward means positive */
                        norm_ok = 0;
                        break;
                    }
                }
                check(norm_ok, "[11] normals not unit/outward");
                check(es[0] == 0 && es[ne] == nep,
                      "[11] edge offsets malformed");
            }
            free(vv);
            free(nn);
            free(tt);
            free(es);
            free(ep);
        }
        occt_free_mesh(m);
        occt_free_shape(b);
    }

    /* [12] mesh of a cylinder (curved faces + smooth edges) -------------- */
    {
        occt_shape *c = occt_make_cylinder(0, 0, 0, 6.0, 10.0);
        occt_mesh *m = c ? occt_mesh_create(c, 0.1, 0.3) : NULL;
        if (check(m != NULL, "[12] mesh_create(cylinder) returned NULL")) {
            int nv = 0, nt = 0, ne = 0, nep = 0;
            occt_mesh_counts(m, &nv, &nt, &ne, &nep);
            printf("[12] cylinder mesh: %d verts, %d tris, %d edges, "
                   "%d edge pts\n", nv, nt, ne, nep);
            check(nt > 12, "[12] curved faces must tessellate finer");
            check(ne == 2, "[12] cylinder must expose 2 edges (rims; seam suppressed)");
            double *vv = (double *)malloc(sizeof(double) * 3 * nv);
            int *tt = (int *)malloc(sizeof(int) * 3 * nt);
            int *es = (int *)malloc(sizeof(int) * (ne + 1));
            double *ep = (double *)malloc(sizeof(double) * 3 * nep);
            if (check(vv && tt && es && ep, "[12] out of memory") &&
                check(occt_mesh_vertices(m, vv), "[12] mesh_vertices") &&
                check(occt_mesh_triangles(m, tt), "[12] mesh_triangles") &&
                check(occt_mesh_edges(m, es, ep), "[12] mesh_edges")) {
                double vol6 = 0.0;
                for (int i = 0; i < nt; ++i) {
                    const double *p0 = vv + 3 * tt[3 * i],
                                 *p1 = vv + 3 * tt[3 * i + 1],
                                 *p2 = vv + 3 * tt[3 * i + 2];
                    vol6 += p0[0] * (p1[1] * p2[2] - p1[2] * p2[1]) +
                            p0[1] * (p1[2] * p2[0] - p1[0] * p2[2]) +
                            p0[2] * (p1[0] * p2[1] - p1[1] * p2[0]);
                }
                const double want = PI * 36.0 * 10.0;
                printf("[12] mesh volume=%.4f (analytic %.4f)\n",
                       vol6 / 6.0, want);
                /* inscribed facets: mesh volume slightly BELOW analytic */
                check(vol6 / 6.0 > 0.97 * want && vol6 / 6.0 <= want + 1.0,
                      "[12] cylinder mesh volume out of tolerance");
                /* both rim circles must be smooth polylines */
                int rims = 0;
                for (int e = 0; e < ne; ++e)
                    if (es[e + 1] - es[e] >= 8)
                        ++rims;
                check(rims >= 2, "[12] rim circles not discretised smoothly");
            }
            free(vv);
            free(tt);
            free(es);
            free(ep);
        }
        occt_free_mesh(m);
        occt_free_shape(c);
    }

    /* [13] rigid transform ------------------------------------------------ */
    {
        occt_shape *b = occt_make_box(10.0, 20.0, 30.0);
        /* translation by (1,2,3) */
        const double mt[12] = {1, 0, 0, 1, 0, 1, 0, 2, 0, 0, 1, 3};
        occt_shape *moved = b ? occt_transform(b, mt) : NULL;
        if (check(moved != NULL, "[13] translate returned NULL")) {
            double bb[6];
            if (check(occt_bbox(moved, bb), "[13] bbox(moved) failed")) {
                check(near_rel(bb[0], 1.0, 1e-6) &&
                          near_rel(bb[1], 2.0, 1e-6) &&
                          near_rel(bb[2], 3.0, 1e-6) &&
                          near_rel(bb[3], 11.0, 1e-6) &&
                          near_rel(bb[4], 22.0, 1e-6) &&
                          near_rel(bb[5], 33.0, 1e-6),
                      "[13] translation did not move the bbox exactly");
            }
            check(near_rel(occt_shape_volume(moved), 6000.0, 1e-9),
                  "[13] volume changed under translation");
        }
        occt_free_shape(moved);
        /* +90 deg about Z: x extent (10) and y extent (20) swap */
        const double mr[12] = {0, -1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0};
        occt_shape *rot = b ? occt_transform(b, mr) : NULL;
        if (check(rot != NULL, "[13] rotate returned NULL")) {
            double bb[6];
            if (check(occt_bbox(rot, bb), "[13] bbox(rot) failed")) {
                printf("[13] rotated bbox x[%.3f,%.3f] y[%.3f,%.3f]\n",
                       bb[0], bb[3], bb[1], bb[4]);
                check(near_rel(bb[3] - bb[0], 20.0, 1e-6) &&
                          near_rel(bb[4] - bb[1], 10.0, 1e-6),
                      "[13] rotation did not swap the x/y extents");
            }
            check(near_rel(occt_shape_volume(rot), 6000.0, 1e-9),
                  "[13] volume changed under rotation");
        }
        occt_free_shape(rot);
        /* NON-rigid matrices must be refused: a uniform scale (gp_Trsf
         * would happily accept it as rotation*scale), a mirror (det -1)
         * and a shear. Each must also SET the error message. */
        const double ms[12] = {2, 0, 0, 0, 0, 2, 0, 0, 0, 0, 2, 0};
        occt_shape *scaled = b ? occt_transform(b, ms) : NULL;
        check(scaled == NULL, "[13] scale matrix was not rejected");
        check(strstr(occt_last_error(), "rigid") != NULL,
              "[13] scale rejection did not report a rigidity error");
        occt_free_shape(scaled);
        const double mm[12] = {-1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0};
        occt_shape *mirrored = b ? occt_transform(b, mm) : NULL;
        check(mirrored == NULL, "[13] mirror (det -1) was not rejected");
        occt_free_shape(mirrored);
        const double msh[12] = {1, 0.4, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0};
        occt_shape *sheared = b ? occt_transform(b, msh) : NULL;
        check(sheared == NULL, "[13] shear matrix was not rejected");
        occt_free_shape(sheared);
        occt_free_shape(b);
    }

    /* [13b] v17 mirror ----------------------------------------------------- */
    {
        /* A box at x in [0,10] mirrored about the plane x = 0 must land at
         * x in [-10,0] with the same volume, and it must still FUSE — which
         * is the whole point of the orientation correction: an inside-out
         * mirrored solid makes the boolean produce nonsense (or nothing). */
        occt_shape *b = occt_make_box(10.0, 20.0, 30.0);
        const double plane[6] = {0, 0, 0, 1, 0, 0}; /* x = 0, normal +x */
        occt_shape *mir = b ? occt_mirror(b, plane) : NULL;
        if (check(mir != NULL, "[13b] mirror returned NULL")) {
            double bb[6];
            if (check(occt_bbox(mir, bb), "[13b] bbox(mirror) failed")) {
                printf("[13b] mirrored bbox x[%.3f,%.3f]\n", bb[0], bb[3]);
                check(near_rel(bb[0], -10.0, 1e-6) && fabs(bb[3]) < 1e-6,
                      "[13b] mirror did not reflect the box across x = 0");
            }
            check(near_rel(occt_shape_volume(mir), 6000.0, 1e-9),
                  "[13b] mirrored volume is not the original volume");
            check(occt_shape_valid(mir), "[13b] mirrored shape is not valid");
            occt_shape *both = b ? occt_fuse(b, mir) : NULL;
            if (check(both != NULL, "[13b] fuse(original, mirror) failed")) {
                check(near_rel(occt_shape_volume(both), 12000.0, 1e-6),
                      "[13b] mirrored half did not add its volume — the "
                      "reflection is probably inside out");
            }
            occt_free_shape(both);
        }
        occt_free_shape(mir);
        /* an offset plane mirrors about ITS location, not about the origin */
        const double p2[6] = {15, 0, 0, 1, 0, 0};
        occt_shape *mir2 = b ? occt_mirror(b, p2) : NULL;
        if (check(mir2 != NULL, "[13b] offset-plane mirror returned NULL")) {
            double bb[6];
            if (check(occt_bbox(mir2, bb), "[13b] bbox(mirror2) failed")) {
                check(near_rel(bb[0], 20.0, 1e-6) && near_rel(bb[3], 30.0, 1e-6),
                      "[13b] mirror about x = 15 landed in the wrong place");
            }
        }
        occt_free_shape(mir2);
        const double pbad[6] = {0, 0, 0, 0, 0, 0};
        check(occt_mirror(b, pbad) == NULL,
              "[13b] a zero-length normal was not rejected");
        check(occt_mirror(NULL, plane) == NULL,
              "[13b] mirror(NULL) did not return NULL");
        occt_free_shape(b);
    }

    /* [14] v2 failure paths must not crash -------------------------------- */
    check(occt_mesh_create(NULL, 0.5, 0.5) == NULL,
          "[14] mesh_create(NULL) did not return NULL");
    occt_free_mesh(NULL); /* must be a no-op */
    check(occt_mesh_counts(NULL, NULL, NULL, NULL, NULL) == 0,
          "[14] mesh_counts(NULL) did not fail");
    check(occt_transform(NULL, NULL) == NULL,
          "[14] transform(NULL) did not return NULL");
    {
        const double bad[] = {0, 0, 1, 0, 1, 1};
        const int lc[] = {3};
        check(occt_extrude_profile(NULL, lc, 1, 5, 0) == NULL,
              "[14] extrude_profile(NULL xy) accepted");
        check(occt_extrude_profile(bad, lc, 1, -5, 0) == NULL,
              "[14] extrude_profile(negative height) accepted");
        check(occt_extrude_profile(bad, lc, 1, 5, 95.0) == NULL,
              "[14] extrude_profile(taper >= 90 deg) accepted");
    }

    /* [15] v3 true-arc extrude: exact cylinder from two bulge arcs ------ */
    {
        /* r=10 circle: vertices (10,0) and (-10,0), each edge a half-turn
         * CCW arc -> bulge = tan(180deg/4) = 1. */
        const double C[] = {10, 0, 1, -10, 0, 1};
        const int lc[] = {2};
        occt_shape *s15 = occt_extrude_profile_arcs(C, lc, 1, 5.0, 0.0);
        if (check(s15 != NULL, "[15] extrude_profile_arcs returned NULL")) {
            int f = 0;
            if (counts(s15, &f, NULL, NULL, "[15] shape_counts failed")) {
                printf("[15] arc cylinder faces=%d\n", f);
                check(f == 3, "[15] not a true cylinder (expected 3 faces)");
            }
            const double vol = occt_shape_volume(s15);
            const double want = PI * 100.0 * 5.0;
            printf("[15] arc cylinder volume=%.6f (analytic %.6f)\n",
                   vol, want);
            check(vol > 0 && fabs(vol - want) < 1e-6 * want,
                  "[15] arc cylinder volume not analytic");
            occt_mesh *m = occt_mesh_create(s15, 0.1, 0.3);
            if (check(m != NULL, "[15] mesh_create(arc cylinder) NULL")) {
                int ne = 0;
                occt_mesh_counts(m, NULL, NULL, &ne, NULL);
                printf("[15] arc cylinder mesh edges=%d\n", ne);
                check(ne == 2,
                      "[15] expected exactly 2 rim edges (smooth barrel)");
                occt_free_mesh(m);
            }
            occt_free_shape(s15);
        }
        /* failure paths of the new entry */
        check(occt_extrude_profile_arcs(NULL, lc, 1, 5, 0) == NULL,
              "[15] extrude_profile_arcs(NULL) accepted");
        check(occt_extrude_profile_arcs(C, lc, 1, -1, 0) == NULL,
              "[15] extrude_profile_arcs(negative height) accepted");
    }

    /* [16] v4 mesh metadata + unify ------------------------------------ */
    {
        const double C[] = {10, 0, 1, -10, 0, 1};
        const int lc[] = {2};
        occt_shape *s16 = occt_extrude_profile_arcs(C, lc, 1, 5.0, 0.0);
        occt_mesh *m = s16 ? occt_mesh_create(s16, 0.1, 0.3) : NULL;
        if (check(m != NULL, "[16] mesh_create returned NULL")) {
            int nv = 0, nt = 0, ne = 0, nep = 0;
            occt_mesh_counts(m, &nv, &nt, &ne, &nep);
            const int nf = occt_mesh_face_count(m);
            printf("[16] faces=%d tris=%d edges=%d\n", nf, nt, ne);
            check(nf == 3, "[16] face_count != 3");
            int *tf = (int *)malloc(sizeof(int) * nt);
            double *fi = (double *)malloc(sizeof(double) * 15 * (nf > 0 ? nf : 1));
            double *ec = (double *)malloc(sizeof(double) * 16 * (ne > 0 ? ne : 1));
            if (check(tf && fi && ec, "[16] out of memory") &&
                check(occt_mesh_triangle_faces(m, tf), "[16] triangle_faces") &&
                check(occt_mesh_face_infos(m, fi), "[16] face_infos") &&
                check(occt_mesh_edge_curves(m, ec), "[16] edge_curves")) {
                int inRange = 1;
                for (int t = 0; t < nt; ++t)
                    if (tf[t] < 0 || tf[t] >= nf) inRange = 0;
                check(inRange, "[16] triangle face ids out of range");
                int planes = 0, cyls = 0;
                double cylR = 0;
                for (int f = 0; f < nf; ++f) {
                    const double *r = fi + 15 * f;
                    if (r[0] == 0) {
                        ++planes;
                        check(fabs(fabs(r[6]) - 1.0) < 1e-9,
                              "[16] cap normal not +-Z");
                    } else if (r[0] == 1) {
                        ++cyls;
                        cylR = r[10];
                    }
                }
                printf("[16] planes=%d cylinders=%d cylR=%.9f\n",
                       planes, cyls, cylR);
                check(planes == 2 && cyls == 1,
                      "[16] expected 2 planes + 1 cylinder");
                check(fabs(cylR - 10.0) < 1e-9, "[16] cylinder radius != 10");
                int circles = 0;
                for (int e = 0; e < ne; ++e) {
                    const double *r = ec + 16 * e;
                    if (r[0] == 2) {
                        ++circles;
                        check(fabs(r[10] - 10.0) < 1e-9,
                              "[16] rim circle radius != 10");
                        check(fabs(fabs(r[12] - r[11]) - 2 * PI) < 1e-6,
                              "[16] rim circle sweep != 2pi");
                    }
                }
                printf("[16] analytic circle edges=%d\n", circles);
                check(circles == 2, "[16] expected 2 analytic rim circles");
            }
            free(tf); free(fi); free(ec);
            occt_free_mesh(m);
        }
        occt_free_shape(s16);
        /* unify collapses the coplanar split faces of a fused pair */
        occt_shape *bA = occt_make_box(10, 10, 10);
        occt_shape *bB0 = occt_make_box(10, 10, 10);
        const double shift[12] = {1, 0, 0, 5, 0, 1, 0, 0, 0, 0, 1, 0};
        occt_shape *bB = bB0 ? occt_transform(bB0, shift) : NULL;
        occt_shape *fu = (bA && bB) ? occt_fuse(bA, bB) : NULL;
        occt_shape *un = fu ? occt_unify(fu) : NULL;
        if (check(un != NULL, "[16] unify returned NULL")) {
            int f0 = 0, f1 = 0;
            occt_shape_counts(fu, &f0, NULL, NULL);
            occt_shape_counts(un, &f1, NULL, NULL);
            const double v0 = occt_shape_volume(fu);
            const double v1 = occt_shape_volume(un);
            printf("[16] fuse faces %d -> unify %d, volume %.6f -> %.6f\n",
                   f0, f1, v0, v1);
            check(f1 == 6, "[16] unified box|box should be a plain box (6)");
            check(fabs(v0 - v1) < 1e-9 * fabs(v0), "[16] unify changed volume");
        }
        occt_free_shape(un); occt_free_shape(fu);
        occt_free_shape(bA); occt_free_shape(bB); occt_free_shape(bB0);
        /* failure paths */
        check(occt_mesh_face_count(NULL) == -1, "[16] face_count(NULL)");
        check(occt_mesh_triangle_faces(NULL, NULL) == 0,
              "[16] triangle_faces(NULL)");
        check(occt_mesh_face_infos(NULL, NULL) == 0, "[16] face_infos(NULL)");
        check(occt_mesh_edge_curves(NULL, NULL) == 0,
              "[16] edge_curves(NULL)");
        check(occt_unify(NULL) == NULL, "[16] unify(NULL)");
    }

    /* [17] v5 boolean CUT — a 20x20x20 block with a 10x10 through-pocket (a
     * 10x10x30 tool centred in x/y, taller than the block so it cuts clean
     * through) has volume 8000 - 10*10*20 = 6000, and more faces than the
     * plain block. */
    {
        occt_shape *blk = occt_make_box(20, 20, 20);
        occt_shape *tool0 = occt_make_box(10, 10, 30);
        /* place the tool at (5,5,-5): centred in x/y, poking out both ends */
        const double place[12] = {1, 0, 0, 5, 0, 1, 0, 5, 0, 0, 1, -5};
        occt_shape *tool = tool0 ? occt_transform(tool0, place) : NULL;
        occt_shape *cut = (blk && tool) ? occt_cut(blk, tool) : NULL;
        if (check(cut != NULL, "[17] cut returned NULL")) {
            const double v = occt_shape_volume(cut);
            int nf = 0;
            occt_shape_counts(cut, &nf, NULL, NULL);
            printf("[17] cut volume %.6f faces %d\n", v, nf);
            check(near_rel(v, 6000.0, 1e-6), "[17] cut volume != 6000");
            check(occt_shape_valid(cut), "[17] cut result invalid");
            check(nf >= 10, "[17] cut should add pocket walls");
            /* inputs untouched: the block still measures 8000 */
            check(near_rel(occt_shape_volume(blk), 8000.0, 1e-9),
                  "[17] cut mutated operand a");
        }
        /* empty result is a failure, not a null shape */
        occt_shape *bigger = occt_make_box(40, 40, 40);
        occt_shape *small = occt_make_box(10, 10, 10);
        const double c2[12] = {1, 0, 0, 5, 0, 1, 0, 5, 0, 0, 1, 5};
        occt_shape *smallP = small ? occt_transform(small, c2) : NULL;
        if (bigger && smallP)
            check(occt_cut(smallP, bigger) == NULL,
                  "[17] cut that erases everything must report failure");
        check(occt_cut(NULL, NULL) == NULL, "[17] cut(NULL)");
        occt_free_shape(cut); occt_free_shape(tool); occt_free_shape(tool0);
        occt_free_shape(blk); occt_free_shape(bigger);
        occt_free_shape(small); occt_free_shape(smallP);
    }

    /* [18] v5 boolean COMMON (intersect) — two 20-cubes offset by (10,10,10)
     * overlap in a 10x10x10 corner: volume 1000. Disjoint boxes give an empty
     * result (reported as failure). */
    {
        occt_shape *a = occt_make_box(20, 20, 20);
        occt_shape *b0 = occt_make_box(20, 20, 20);
        const double off[12] = {1, 0, 0, 10, 0, 1, 0, 10, 0, 0, 1, 10};
        occt_shape *b = b0 ? occt_transform(b0, off) : NULL;
        occt_shape *cm = (a && b) ? occt_common(a, b) : NULL;
        if (check(cm != NULL, "[18] common returned NULL")) {
            const double v = occt_shape_volume(cm);
            printf("[18] common volume %.6f\n", v);
            check(near_rel(v, 1000.0, 1e-6), "[18] common volume != 1000");
            check(occt_shape_valid(cm), "[18] common result invalid");
            check(near_rel(occt_shape_volume(a), 8000.0, 1e-9),
                  "[18] common mutated operand a");
        }
        occt_shape *far0 = occt_make_box(5, 5, 5);
        const double faraway[12] = {1, 0, 0, 100, 0, 1, 0, 0, 0, 0, 1, 0};
        occt_shape *far = far0 ? occt_transform(far0, faraway) : NULL;
        if (a && far)
            check(occt_common(a, far) == NULL,
                  "[18] disjoint common must report failure");
        check(occt_common(NULL, NULL) == NULL, "[18] common(NULL)");
        occt_free_shape(cm); occt_free_shape(b); occt_free_shape(b0);
        occt_free_shape(a); occt_free_shape(far); occt_free_shape(far0);
    }

    /* [19] v8 ASYMMETRIC arc: the bulge must bow to the RIGHT of p0->p1.
     * Device find (build a0f1c35): every arc came out mirrored across its
     * chord. A circle is written as two half-turns across a diameter, so the
     * mirror maps it onto itself and [15]/[16] stayed green — only a profile
     * that is NOT symmetric about its chord can catch it, and the volume
     * cannot (a mirror preserves area). The bounding box can.
     * Lens from the report: arc centre (1.888714,-0.506745) r=8.878410 swept
     * CCW 45.977189deg -> 158.593988deg, closed by its chord. Segment area
     * 41.085636 -> volume 205.428179 at height 5; the arc peaks at
     * y = cy + r = 8.371665. Mirrored, the peak would fall to y = 5.877393
     * (the higher chord end) and ymin would drop to 0.239375. */
    {
        const double L[] = {
            8.0587183242952332,  5.8773928201870458, 0.5351665491544619,
            -6.3772415162043483, 2.7336479404453176, 0.0,
        };
        const int lc[] = {2};
        occt_shape *s19 = occt_extrude_profile_arcs(L, lc, 1, 5.0, 0.0);
        if (check(s19 != NULL, "[19] lens extrude returned NULL")) {
            const double v = occt_shape_volume(s19);
            printf("[19] lens volume %.6f (analytic 205.428179)\n", v);
            check(near_rel(v, 205.42817888207543, 1e-6),
                  "[19] lens volume not analytic");
            double bb[6] = {0};
            if (check(occt_bbox(s19, bb), "[19] bbox failed")) {
                printf("[19] lens bbox y %.6f..%.6f (want 2.733648..8.371665)\n",
                       bb[1], bb[4]);
                check(fabs(bb[4] - 8.371665146120012) < 1e-6,
                      "[19] arc bows the wrong way (peak mirrored below chord)");
                check(fabs(bb[1] - 2.7336479404453176) < 1e-6,
                      "[19] arc bows the wrong way (bottom below the chord)");
                check(fabs(bb[0] + 6.3772415162043483) < 1e-6 &&
                          fabs(bb[3] - 8.0587183242952332) < 1e-6,
                      "[19] lens x extent wrong");
            }
            occt_free_shape(s19);
        }
        /* same lens traversed the other way round (vertices swapped, bulge
         * negated) must give the IDENTICAL solid — the shim reverses the wire
         * itself when the signed area comes out negative. */
        const double R[] = {
            -6.3772415162043483, 2.7336479404453176, -0.5351665491544619,
            8.0587183242952332,  5.8773928201870458, 0.0,
        };
        occt_shape *s19r = occt_extrude_profile_arcs(R, lc, 1, 5.0, 0.0);
        if (check(s19r != NULL, "[19] reversed lens returned NULL")) {
            double bb[6] = {0};
            if (occt_bbox(s19r, bb))
                check(fabs(bb[4] - 8.371665146120012) < 1e-6,
                      "[19] reversed lens bows the wrong way");
            check(near_rel(occt_shape_volume(s19r), 205.42817888207543, 1e-6),
                  "[19] reversed lens volume not analytic");
            occt_free_shape(s19r);
        }
    }


    /* [20] v12 REVOLVE: a rectangle x in [5,10], y in [0,3] revolved a full
     * turn about the Y axis is an annular tube, outer r=10, inner r=5,
     * height 3 -> V = pi*(100-25)*3 = 225*pi. Analytic, so a sign error in
     * the axis lift or a swapped inner/outer boundary cannot hide. */
    {
        const double P[] = {
            5.0, 0.0, 0.0,  10.0, 0.0, 0.0,  10.0, 3.0, 0.0,  5.0, 3.0, 0.0,
        };
        const int lc[] = {4};
        occt_shape *s = occt_revolve_profile(P, lc, 1, 0.0, 0.0, 0.0, 1.0,
                                             360.0);
        if (check(s != NULL, "[20] full revolve returned NULL")) {
            const double want = 225.0 * 3.14159265358979323846;
            const double v = occt_shape_volume(s);
            printf("[20] tube volume %.6f (analytic %.6f)\n", v, want);
            check(near_rel(v, want, 1e-6), "[20] tube volume not analytic");
            int nf = 0;
            occt_shape_counts(s, &nf, NULL, NULL);
            printf("[20] tube faces %d (want 4)\n", nf);
            check(nf == 4, "[20] tube should be 4 faces after unify");
            check(occt_shape_valid(s), "[20] tube is not a valid solid");
            occt_free_shape(s);
        }
        /* half a turn is exactly half the material */
        occt_shape *h = occt_revolve_profile(P, lc, 1, 0.0, 0.0, 0.0, 1.0,
                                             180.0);
        if (check(h != NULL, "[20] half revolve returned NULL")) {
            check(near_rel(occt_shape_volume(h),
                           112.5 * 3.14159265358979323846, 1e-6),
                  "[20] half revolve volume wrong");
            occt_free_shape(h);
        }
        /* a profile straddling the axis must be REFUSED, not swept through
         * itself: same rectangle moved to x in [-2,3]. */
        const double X[] = {
            -2.0, 0.0, 0.0,  3.0, 0.0, 0.0,  3.0, 3.0, 0.0,  -2.0, 3.0, 0.0,
        };
        check(occt_revolve_profile(X, lc, 1, 0.0, 0.0, 0.0, 1.0, 360.0) == NULL,
              "[20] profile crossing the axis must fail");
        check(occt_revolve_profile(P, lc, 1, 0.0, 0.0, 0.0, 1.0, 0.0) == NULL,
              "[20] zero angle must fail");
        check(occt_revolve_profile(P, lc, 1, 0.0, 0.0, 0.0, 0.0, 90.0) == NULL,
              "[20] degenerate axis must fail");
    }

    /* [21] v12 EDGE IDENTITY + FILLET. A 20-cube has 12 edges; find a
     * vertical one through occt_shape_edge_info (which is exactly how Dart
     * re-matches a stored fillet after a rebuild) and round it with r=5.
     * A 90-degree fillet removes r^2*(1 - pi/4) of cross-section over the
     * edge length: 25*(1-pi/4)*20 = 107.300918. */
    {
        occt_shape *box = occt_make_box(20, 20, 20);
        if (check(box != NULL, "[21] box returned NULL")) {
            const int ne = occt_shape_edge_count(box);
            printf("[21] cube topological edges %d (want 12)\n", ne);
            check(ne == 12, "[21] a cube must report 12 edges");
            int vertical = -1;
            for (int i = 1; i <= ne; ++i) {
                double info[12] = {0};
                if (!occt_shape_edge_info(box, i, info))
                    continue;
                if (info[0] != 1.0)
                    continue; /* must be a straight edge */
                if (fabs(fabs(info[6]) - 1.0) > 1e-9)
                    continue; /* tangent along Z */
                check(fabs(info[7] - 20.0) < 1e-9,
                      "[21] cube edge length must be 20");
                check(info[9] == 2.0,
                      "[21] cube edge must have 2 adjacent faces");
                /* v13: every edge of a plain box is an EXTERIOR corner */
                check(fabs(info[10] - 90.0) < 1e-6,
                      "[21] a cube edge is a 90 degree corner");
                check(info[11] == 1.0, "[21] a cube edge must be CONVEX");
                vertical = i;
                break;
            }
            if (check(vertical > 0, "[21] no vertical cube edge found")) {
                const int ids[] = {vertical};
                const double radii[] = {5.0};
                occt_shape *f = occt_fillet_edges(box, ids, radii, NULL, 1);
                if (check(f != NULL, "[21] fillet returned NULL")) {
                    const double want =
                        8000.0 - 25.0 * (1.0 - 3.14159265358979323846 / 4.0) *
                                     20.0;
                    const double v = occt_shape_volume(f);
                    printf("[21] filleted cube volume %.6f (analytic %.6f)\n",
                           v, want);
                    check(near_rel(v, want, 1e-6),
                          "[21] filleted volume not analytic");
                    int nf = 0;
                    occt_shape_counts(f, &nf, NULL, NULL);
                    check(nf == 7, "[21] filleted cube should have 7 faces");
                    check(occt_shape_valid(f), "[21] filleted cube invalid");
                    occt_free_shape(f);
                }
                /* A radius LARGER than the face it must lie on cannot fit:
                 * clean failure, no solid. (r=15 does fit on a 20 mm face —
                 * 15 < 20 — so it is a legal fillet, not an error case.) */
                const double huge[] = {25.0};
                check(occt_fillet_edges(box, ids, huge, NULL, 1) == NULL,
                      "[21] oversized fillet must fail cleanly");
                const int bad[] = {999};
                check(occt_fillet_edges(box, bad, radii, NULL, 1) == NULL,
                      "[21] out-of-range edge index must fail");

                /* [22] CHAMFER, equal distance d=4 removes d^2/2 * 20 = 160 */
                const int modes[] = {0};
                const double d1[] = {4.0};
                occt_shape *c = occt_chamfer_edges(box, ids, modes, d1, NULL,
                                                   NULL, 1);
                if (check(c != NULL, "[22] chamfer returned NULL")) {
                    const double v = occt_shape_volume(c);
                    printf("[22] chamfered cube volume %.6f (want 7840)\n", v);
                    check(near_rel(v, 7840.0, 1e-9),
                          "[22] chamfer volume wrong");
                    int nf = 0;
                    occt_shape_counts(c, &nf, NULL, NULL);
                    check(nf == 7, "[22] chamfered cube should have 7 faces");
                    occt_free_shape(c);
                }
                /* distance+angle: d=4 at 45 deg is the same wedge as above */
                const int modesDA[] = {2};
                const double ang[] = {45.0};
                occt_shape *ca = occt_chamfer_edges(box, ids, modesDA, d1, NULL,
                                                    ang, 1);
                if (check(ca != NULL, "[22] distance+angle returned NULL")) {
                    check(near_rel(occt_shape_volume(ca), 7840.0, 1e-6),
                          "[22] 45 deg chamfer must equal the d/d chamfer");
                    occt_free_shape(ca);
                }
                const double ang0[] = {95.0};
                check(occt_chamfer_edges(box, ids, modesDA, d1, NULL, ang0,
                                         1) == NULL,
                      "[22] angle >= 90 deg must fail");
            }

            /* [21c] v16 — THE FILLET THAT LANDS EXACTLY ON A TANGENCY.
             *
             * Round all four vertical edges of the 20-cube at r=10. Each face
             * is 20 wide and two neighbouring rounds eat 10 each, so they meet
             * at a tangent point with no flat left between them and the answer
             * is a plain cylinder. OCCT has never been able to build that —
             * open since 2010, GitHub issue #172 — and it is the same failure
             * as a 2 mm fillet on a 2 mm wall, which is what a user hit on the
             * device: 1.999 built, 2.0 did not.
             *
             * v16 retries a hair under and reports how far under it went. */
            {
                int vert[4];
                int nv = 0;
                for (int i = 1; i <= occt_shape_edge_count(box) && nv < 4; ++i) {
                    double info[12] = {0};
                    if (!occt_shape_edge_info(box, i, info))
                        continue;
                    if (info[0] != 1.0)
                        continue;
                    if (fabs(fabs(info[6]) - 1.0) > 1e-9)
                        continue; /* tangent along Z */
                    vert[nv++] = i;
                }
                check(nv == 4, "[21c] a cube has four vertical edges");
                if (nv == 4) {
                    const double r[4] = {10.0, 10.0, 10.0, 10.0};
                    int dropped[4] = {0};
                    double scale = 0.0;
                    occt_shape *cyl = occt_fillet_edges_ex(box, vert, r, NULL,
                                                           4, dropped, &scale);
                    printf("[21c] full-quarter-round fillet -> %s "
                           "(scale %.9f)\n",
                           cyl ? "built" : "NULL", scale);
                    if (check(cyl != NULL,
                              "[21c] a fillet meeting its neighbour tangentially"
                              " must still build")) {
                        /* A cylinder r=10 h=20: pi*100*20 = 6283.185307. The
                         * retry shaves at most one part in a thousand off the
                         * radius, so allow 0.5 % and check it is not something
                         * else entirely. */
                        const double v = occt_shape_volume(cyl);
                        printf("[21c] volume %.6f (cylinder 6283.185307)\n", v);
                        check(near_rel(v, 6283.185307, 5e-3),
                              "[21c] the result must be the cylinder");
                        check(occt_shape_valid(cyl), "[21c] result invalid");
                        check(dropped[0] == 0 && dropped[1] == 0 &&
                                  dropped[2] == 0 && dropped[3] == 0,
                              "[21c] no edge should have been skipped");
                        check(scale > 0.99 && scale <= 1.0,
                              "[21c] the retry must stay within one part in a "
                              "thousand of the asked-for radius");
                        occt_free_shape(cyl);
                    }
                }
            }

            /* [21d] v16 — ONE IMPOSSIBLE EDGE NO LONGER KILLS THE SET.
             * r=25 cannot sit on a 20 mm face at any size in the retry range;
             * r=5 on its neighbour is fine. Inventor keeps the round it can
             * build and says which it could not, and so do we. */
            {
                int vert[2];
                int nv = 0;
                for (int i = 1; i <= occt_shape_edge_count(box) && nv < 2; ++i) {
                    double info[12] = {0};
                    if (!occt_shape_edge_info(box, i, info))
                        continue;
                    if (info[0] != 1.0 || fabs(fabs(info[6]) - 1.0) > 1e-9)
                        continue;
                    vert[nv++] = i;
                }
                if (nv == 2) {
                    const double mixed[2] = {5.0, 25.0};
                    int dropped[2] = {0};
                    double scale = 0.0;
                    occt_shape *p = occt_fillet_edges_ex(box, vert, mixed, NULL,
                                                         2, dropped, &scale);
                    printf("[21d] mixed set -> %s (dropped %d,%d)\n",
                           p ? "built" : "NULL", dropped[0], dropped[1]);
                    if (check(p != NULL,
                              "[21d] one impossible radius must not lose the "
                              "whole feature")) {
                        check(dropped[0] == 0,
                              "[21d] the buildable round must survive");
                        check(dropped[1] == 1,
                              "[21d] the impossible one must be reported");
                        check(occt_shape_valid(p), "[21d] partial result invalid");
                        occt_free_shape(p);
                    }
                }
            }

            /* [23] RAY HITS — what "To Next" measures. A ray up the middle of
             * the cube from 10 below it crosses the bottom cap at 10 and the
             * top cap at 30, and reports each crossing ONCE. */
            {
                double hits[8] = {0};
                const int n = occt_ray_hits(box, 10, 10, -10, 0, 0, 1, hits, 8);
                printf("[23] ray hits %d at %.6f, %.6f (want 2: 10, 30)\n", n,
                       n > 0 ? hits[0] : -1.0, n > 1 ? hits[1] : -1.0);
                check(n == 2, "[23] a ray through a cube must hit twice");
                if (n == 2) {
                    check(fabs(hits[0] - 10.0) < 1e-6, "[23] near hit wrong");
                    check(fabs(hits[1] - 30.0) < 1e-6, "[23] far hit wrong");
                }
                double miss[4] = {0};
                check(occt_ray_hits(box, -50, -50, -50, 0, 0, 1, miss, 4) == 0,
                      "[23] a ray beside the cube must report no hits");
            }
            occt_free_shape(box);
        }
    }

    /* [24] v13 CONVEXITY. Cutting a bar out of the top of a block leaves a
     * channel: its two floor edges are INTERIOR corners (concave, what
     * Inventor calls a fillet), while the block's outer edges stay exterior
     * (convex, a round). Both must be reported, or "All Fillets" and "All
     * Rounds" would select the same set. */
    {
        occt_shape *block = occt_make_box(40, 40, 20);
        occt_shape *bar = occt_make_box(10, 60, 10);
        if (block && bar) {
            /* centre the bar across the block and sink it into the top */
            const double mv[12] = {1, 0, 0, 15, 0, 1, 0, -10, 0, 0, 1, 15};
            occt_shape *placed = occt_transform(bar, mv);
            occt_shape *notched = placed ? occt_cut(block, placed) : NULL;
            if (check(notched != NULL, "[24] notch cut returned NULL")) {
                const int ne = occt_shape_edge_count(notched);
                int convex = 0, concave = 0, tangent = 0;
                for (int i = 1; i <= ne; ++i) {
                    double d[12] = {0};
                    if (!occt_shape_edge_info(notched, i, d)) continue;
                    if (d[9] != 2.0) continue;
                    if (d[11] > 0.5) convex++;
                    else if (d[11] < -0.5) concave++;
                    else tangent++;
                }
                printf("[24] notched block: %d convex, %d concave, %d tangent "
                       "(of %d edges)\n", convex, concave, tangent, ne);
                check(concave == 2,
                      "[24] a rectangular channel has exactly 2 concave edges");
                check(convex > 0, "[24] the block's own edges stay convex");
                occt_free_shape(notched);
            }
            if (placed) occt_free_shape(placed);
        }
        if (bar) occt_free_shape(bar);
        if (block) occt_free_shape(block);
    }

    /* [25] v13 REVOLVE HITS — what a revolve's "To Next" measures. A box
     * x in [10,20], y in [-5,5] and a point at (15,0,0) circling the Z axis
     * at radius 15: the path leaves through y = +5 at asin(5/15... ) — exactly
     * where 15*cos = sqrt(225-25), i.e. atan2(5, sqrt(200)) = 19.4712 deg, and
     * symmetrically at 360 - 19.4712 = 340.5288. Analytic, so a wrong angle
     * origin or a radians/degrees slip cannot hide. */
    {
        occt_shape *b0 = occt_make_box(10, 10, 10);
        const double mv[12] = {1, 0, 0, 10, 0, 1, 0, -5, 0, 0, 1, -5};
        occt_shape *bx = b0 ? occt_transform(b0, mv) : NULL;
        if (check(bx != NULL, "[25] box placement returned NULL")) {
            double h[8] = {0};
            const int n = occt_revolve_hits(bx, 0, 0, 0, 0, 0, 1, 15, 0, 0, h, 8);
            printf("[25] revolve hits %d at %.4f, %.4f (want 2: 19.4712, "
                   "340.5288)\n", n, n > 0 ? h[0] : -1.0, n > 1 ? h[1] : -1.0);
            check(n == 2, "[25] the circular path must cross twice");
            if (n == 2) {
                check(fabs(h[0] - 19.471220634) < 1e-5, "[25] first angle wrong");
                check(fabs(h[1] - 340.528779366) < 1e-5,
                      "[25] second angle wrong");
            }
            /* a point ON the axis never moves */
            check(occt_revolve_hits(bx, 0, 0, 0, 0, 0, 1, 0, 0, 0, h, 8) == 0,
                  "[25] a point on the axis has no path");
            check(occt_revolve_hits(bx, 0, 0, 0, 0, 0, 0, 15, 0, 0, h, 8) == -1,
                  "[25] a degenerate axis must be an error");
            occt_free_shape(bx);
        }
        if (b0) occt_free_shape(b0);
    }

    /* [26] v13 VARIABLE RADIUS, 2 mm -> 6 mm along a 20 mm cube edge.
     *
     * NOT asserted against a closed form. Integrating the constant-radius
     * cross section along the edge,
     *   (1-pi/4) * L * (r1^2 + r1*r2 + r2^2)/3 = 74.395
     * predicts V = 7925.605, but the measured value is 7924.190 — the
     * approximation is wrong by 1.8e-4 because it assumes the fillet surface
     * stays perpendicular to the edge, and a varying radius tilts it. Rather
     * than loosen a tolerance until a wrong formula passes, the check asserts
     * what IS exactly true and is what the feature promises:
     *   - it removes MORE than a constant 2 mm fillet,
     *   - LESS than a constant 6 mm one,
     *   - and is NOT the mean of the two, which is what averaging the radii
     *     instead of varying them would give. */
    {
        occt_shape *box = occt_make_box(20, 20, 20);
        if (check(box != NULL, "[26] box returned NULL")) {
            const int ne = occt_shape_edge_count(box);
            int vertical = -1;
            for (int i = 1; i <= ne; ++i) {
                double d[12] = {0};
                if (!occt_shape_edge_info(box, i, d)) continue;
                if (d[0] != 1.0) continue;
                if (fabs(fabs(d[6]) - 1.0) > 1e-9) continue;
                vertical = i;
                break;
            }
            if (check(vertical > 0, "[26] no vertical edge")) {
                const int ids[] = {vertical};
                const double r1[] = {2.0}, r2[] = {6.0};
                const double rr2[] = {2.0}, rr6[] = {6.0};
                occt_shape *c2 = occt_fillet_edges(box, ids, rr2, NULL, 1);
                occt_shape *c6 = occt_fillet_edges(box, ids, rr6, NULL, 1);
                occt_shape *v = occt_fillet_edges(box, ids, r1, r2, 1);
                if (check(v != NULL && c2 != NULL && c6 != NULL,
                          "[26] fillets returned NULL")) {
                    const double got = occt_shape_volume(v);
                    const double lo = occt_shape_volume(c6); /* removes most */
                    const double hi = occt_shape_volume(c2); /* removes least */
                    const double mean = 0.5 * (lo + hi);
                    printf("[26] variable %.4f, const2 %.4f, const6 %.4f, "
                           "mean %.4f\n", got, hi, lo, mean);
                    check(got < hi - 1e-6,
                          "[26] must remove more than a constant 2 mm fillet");
                    check(got > lo + 1e-6,
                          "[26] must remove less than a constant 6 mm fillet");
                    check(fabs(got - mean) > 1.0,
                          "[26] must VARY, not average the two radii");
                }
                if (v) occt_free_shape(v);
                if (c2) occt_free_shape(c2);
                if (c6) occt_free_shape(c6);
            }
            occt_free_shape(box);
        }
    }

    /* [27] v13 REVOLVE HITS ON ONE FACE. Same box and circle as [25], but
     * asking only about the y = -5 face: its single crossing is at
     * 360 - 19.4712 = 340.5288, and the y = +5 crossing must NOT appear. */
    {
        occt_shape *b0 = occt_make_box(10, 10, 10);
        const double mv[12] = {1, 0, 0, 10, 0, 1, 0, -5, 0, 0, 1, -5};
        occt_shape *bx = b0 ? occt_transform(b0, mv) : NULL;
        if (check(bx != NULL, "[27] box placement returned NULL")) {
            double h[8] = {0};
            /* a point on the y = -5 face, mid-span */
            const int n = occt_revolve_hits_face(bx, 0, 0, 0, 0, 0, 1,
                                                 15, 0, 0, 15, -5, 0, h, 8);
            printf("[27] face hits %d at %.4f (want 1: 340.5288)\n", n,
                   n > 0 ? h[0] : -1.0);
            check(n == 1, "[27] one face is crossed once by this path");
            if (n == 1) {
                check(fabs(h[0] - 340.528779366) < 1e-4,
                      "[27] the picked face's angle is wrong");
            }
            occt_free_shape(bx);
        }
        if (b0) occt_free_shape(b0);
    }

    /* [28] v12 DISPLAY -> TOPOLOGICAL edge map. The one function in the v12/v13
     * surface with no coverage until now, and the one whose absence caused a
     * silent bug class: the mesh's display edge list SKIPS degenerate, seam and
     * tangent-continuous edges, so display index i and TopExp::MapShapes index
     * i are different numbers on anything with a cylinder in it. A fillet keyed
     * on the display index would round the WRONG edge.
     *
     * A cylinder is the case that proves it: it has a seam the display list
     * drops, so the map cannot be the identity.
     *
     * NOTE: this needs occt_mesh_create, which fails on OCCT 7.6 for reasons
     * unrelated to this shim (see [11]/[12]). It therefore SKIPS LOUDLY rather
     * than failing when meshing is unavailable, and is exercised for real only
     * on the 7.9 CI build. */
    {
        occt_shape *cyl = occt_make_cylinder(0, 0, 0, 5.0, 20.0);
        occt_mesh *m = cyl ? occt_mesh_create(cyl, 0.1, 0.5) : NULL;
        if (m == NULL) {
            printf("[28] SKIPPED (mesh_create unavailable on this OCCT) "
                   "- runs on CI\n");
        } else {
            int nv = 0, nt = 0, nedges = 0, np = 0;
            occt_mesh_counts(m, &nv, &nt, &nedges, &np);
            const int ntopo = occt_shape_edge_count(cyl);
            int *ids = (int *)malloc(sizeof(int) * (nedges > 0 ? nedges : 1));
            check(occt_mesh_edge_ids(m, ids) == 1, "[28] edge_ids failed");
            printf("[28] cylinder: %d display edges, %d topological\n", nedges,
                   ntopo);
            check(nedges > 0, "[28] a cylinder must draw some edges");
            check(nedges < ntopo,
                  "[28] the display list must DROP the seam, so it is shorter");
            int ok = 1, distinct = 1;
            for (int i = 0; i < nedges; ++i) {
                if (ids[i] < 1 || ids[i] > ntopo) ok = 0;
                for (int j = i + 1; j < nedges; ++j)
                    if (ids[i] == ids[j]) distinct = 0;
            }
            check(ok, "[28] every mapped id must be a real topological index");
            check(distinct, "[28] two display edges cannot share one id");
            /* the point of the whole function: it is NOT the identity */
            int identity = 1;
            for (int i = 0; i < nedges; ++i)
                if (ids[i] != i + 1) identity = 0;
            printf("[28] map is %s\n", identity ? "the identity" : "a REMAP");
            check(!identity,
                  "[28] on a cylinder the map must differ from the identity");
            /* and every mapped edge must actually be filletable */
            for (int i = 0; i < nedges; ++i) {
                double d[12] = {0};
                if (occt_shape_edge_info(cyl, ids[i], d))
                    check(d[7] > 0, "[28] a drawn edge must have length");
            }
            free(ids);
            occt_free_mesh(m);
        }
        if (cyl) occt_free_shape(cyl);
    }

    /* [29] v14 FILLET OUTLINES. A filleted cube must DRAW the line where the
     * round meets each flat face. Those joins are tangent-continuous by
     * construction, so the blanket smooth-edge suppression removed them and a
     * filleted box rendered as one seamless blob (reported from the device).
     *
     * A 20-cube filleted on one vertical edge: the round adds two tangent
     * boundaries (one onto each adjacent face). The unfilleted cube draws 12
     * edges; the filleted one loses the rounded edge itself but gains those
     * two, so it must draw MORE than 11 - and specifically the two
     * plane/cylinder joins must be present.
     *
     * Skips loudly where meshing is unavailable (OCCT 7.6), like [28]. */
    {
        occt_shape *box = occt_make_box(20, 20, 20);
        int vertical = -1;
        const int ne0 = box ? occt_shape_edge_count(box) : 0;
        for (int i = 1; i <= ne0; ++i) {
            double d[12] = {0};
            if (!occt_shape_edge_info(box, i, d)) continue;
            if (d[0] == 1.0 && fabs(fabs(d[6]) - 1.0) < 1e-9) { vertical = i; break; }
        }
        occt_shape *fil = NULL;
        if (vertical > 0) {
            const int ids[] = {vertical};
            const double r[] = {4.0};
            fil = occt_fillet_edges(box, ids, r, NULL, 1);
        }
        occt_mesh *mb = box ? occt_mesh_create(box, 0.1, 0.5) : NULL;
        occt_mesh *mf = fil ? occt_mesh_create(fil, 0.1, 0.5) : NULL;
        if (mb == NULL || mf == NULL) {
            printf("[29] SKIPPED (mesh_create unavailable on this OCCT)"
                   " - runs on CI\n");
        } else {
            int a1 = 0, a2 = 0, nb = 0, a4 = 0;
            occt_mesh_counts(mb, &a1, &a2, &nb, &a4);
            int b1 = 0, b2 = 0, nf = 0, b4 = 0;
            occt_mesh_counts(mf, &b1, &b2, &nf, &b4);
            printf("[29] display edges: plain cube %d, filleted %d\n", nb, nf);
            check(nb == 12, "[29] a plain cube draws 12 edges");
            check(nf > 12, "[29] the fillet must ADD its two tangent joins");
            /* and the joins must really be plane/cylinder pairs */
            int planeCyl = 0;
            const int nt = occt_shape_edge_count(fil);
            for (int i = 1; i <= nt; ++i) {
                double d[12] = {0};
                if (!occt_shape_edge_info(fil, i, d)) continue;
                /* a tangent join reads ~0 degrees between the faces */
                if (d[9] == 2.0 && d[10] < 1.0 && d[7] > 0) planeCyl++;
            }
            printf("[29] tangent-continuous edges on the filleted solid: %d\n",
                   planeCyl);
            check(planeCyl >= 2, "[29] expected the two fillet tangent joins");
            occt_free_mesh(mf);
            occt_free_mesh(mb);
        }
        if (fil) occt_free_shape(fil);
        if (box) occt_free_shape(box);
    }

    /* [30] v15 SWEEP. A 10x10 square swept 40 mm along a STRAIGHT path is a
     * prism: V = 100*40 = 4000, six faces. Comparing against the analytic
     * prism is the strongest check available — if the section rotated, scaled
     * or drifted, the volume moves. */
    {
        const double P[] = {0, 0, 0,  10, 0, 0,  10, 10, 0,  0, 10, 0};
        const int lc[] = {4};
        /* profile on the XY plane at the origin, path straight up +Z */
        const double I[12] = {1,0,0,0, 0,1,0,0, 0,0,1,0};
        const double path[] = {0, 0, 0,  0, 0, 40};
        occt_shape *sw = occt_sweep_profile(P, lc, 1, I, path, 2, 0, 0.0, 0.0);
        if (check(sw != NULL, "[30] sweep returned NULL")) {
            const double v = occt_shape_volume(sw);
            int nf = 0;
            occt_shape_counts(sw, &nf, NULL, NULL);
            printf("[30] swept prism volume %.6f (want 4000), faces %d\n", v, nf);
            check(near_rel(v, 4000.0, 1e-6), "[30] swept volume not analytic");
            check(nf == 6, "[30] a swept square prism has 6 faces");
            check(occt_shape_valid(sw), "[30] swept solid invalid");
            occt_free_shape(sw);
        }
        /* an L-shaped path is longer than its straight span, so it must remove
         * no material and produce MORE volume than the 40 mm run */
        const double lpath[] = {0, 0, 0,  0, 0, 40,  30, 0, 40};
        occt_shape *el = occt_sweep_profile(P, lc, 1, I, lpath, 3, 0, 0.0, 0.0);
        if (check(el != NULL, "[30] L-path sweep returned NULL")) {
            check(occt_shape_volume(el) > 4000.0,
                  "[30] a longer path must sweep more material");
            occt_free_shape(el);
        }
        check(occt_sweep_profile(P, lc, 1, I, path, 1, 0, 0.0, 0.0) == NULL,
              "[30] a single-point path must fail");
        check(occt_sweep_profile(P, lc, 1, I, path, 2, 0, 0.0, 15.0) == NULL,
              "[30] twist is refused, not silently ignored");
    }

    /* [31] v15 LOFT. Two IDENTICAL 10x10 squares 25 mm apart, lofted ruled,
     * is again a prism: V = 100*25 = 2500. A loft that mis-ordered or
     * mis-placed a section cannot hit that number. */
    {
        const double S[] = {
            0, 0, 0,  10, 0, 0,  10, 10, 0,  0, 10, 0,   /* section 1 */
            0, 0, 0,  10, 0, 0,  10, 10, 0,  0, 10, 0,   /* section 2 */
        };
        const int lc[] = {4, 4};
        const double mats[24] = {
            1,0,0,0, 0,1,0,0, 0,0,1,0,      /* at z = 0  */
            1,0,0,0, 0,1,0,0, 0,0,1,25,     /* at z = 25 */
        };
        occt_shape *lo = occt_loft_sections(S, lc, mats, 2, 1, 1, 0);
        if (check(lo != NULL, "[31] loft returned NULL")) {
            const double v = occt_shape_volume(lo);
            printf("[31] lofted prism volume %.6f (want 2500)\n", v);
            check(near_rel(v, 2500.0, 1e-6), "[31] lofted volume not analytic");
            check(occt_shape_valid(lo), "[31] lofted solid invalid");
            occt_free_shape(lo);
        }
        /* a 20x20 top section makes a frustum: V = h/3 * (A1 + A2 + sqrt(A1*A2))
         * = 25/3 * (100 + 400 + 200) = 5833.333... */
        const double S2[] = {
            0, 0, 0,  10, 0, 0,  10, 10, 0,  0, 10, 0,
            -5, -5, 0,  15, -5, 0,  15, 15, 0,  -5, 15, 0,
        };
        occt_shape *fr = occt_loft_sections(S2, lc, mats, 2, 1, 1, 0);
        if (check(fr != NULL, "[31] frustum loft returned NULL")) {
            const double want = 25.0 / 3.0 * (100.0 + 400.0 + 200.0);
            const double v = occt_shape_volume(fr);
            printf("[31] lofted frustum volume %.6f (analytic %.6f)\n", v, want);
            check(near_rel(v, want, 1e-4), "[31] frustum volume not analytic");
            occt_free_shape(fr);
        }
        check(occt_loft_sections(S, lc, mats, 1, 1, 1, 0) == NULL,
              "[31] one section is not a loft");
    }

    /* [32] v15 COIL. A 2x2 square centred 20 mm off the Z axis, 5 turns rising
     * 50 mm. The swept volume is the section area times the helix LENGTH:
     * one turn is sqrt((2*pi*r)^2 + pitch^2), pitch = 50/5 = 10, so
     * L = 5 * sqrt((2*pi*20)^2 + 100) = 628.71..., V = 4 * L.
     * A coil that got the radius, the pitch or the turn count wrong lands
     * nowhere near this. */
    {
        const double P[] = {19, -1, 0,  21, -1, 0,  21, 1, 0,  19, 1, 0};
        const int lc[] = {4};
        /* profile in the XZ plane so the square faces along the helix */
        const double m[12] = {1,0,0,0, 0,0,-1,0, 0,1,0,0};
        occt_shape *co = occt_coil_profile(P, lc, 1, m, 0,0,0, 0,0,1,
                                          5.0, 50.0, 0.0, 0, 0, 0);
        if (check(co != NULL, "[32] coil returned NULL")) {
            const double turn = sqrt(pow(2.0 * 3.14159265358979323846 * 20.0, 2)
                                     + 100.0);
            const double want = 4.0 * 5.0 * turn;
            const double v = occt_shape_volume(co);
            printf("[32] coil volume %.4f (helix-length estimate %.4f)\n", v,
                   want);
            /* 2% — a swept square on a curved path is not exactly area*length,
             * the inner and outer faces differ. Tight enough that a wrong
             * radius, pitch or turn count cannot pass. */
            check(near_rel(v, want, 2e-2), "[32] coil volume far off");
            check(occt_shape_valid(co), "[32] coil solid invalid");
            occt_free_shape(co);
        }
        check(occt_coil_profile(P, lc, 1, m, 0,0,0, 0,0,1, 0.0, 50, 0, 0,0,0)
                  == NULL, "[32] zero revolutions must fail");
        check(occt_coil_profile(P, lc, 1, m, 0,0,0, 0,0,0, 5, 50, 0, 0,0,0)
                  == NULL, "[32] a degenerate axis must fail");
        check(occt_coil_profile(P, lc, 1, m, 0,0,0, 0,0,1, 5, 50, 0, 0,1,0)
                  == NULL, "[32] unimplemented coil ends are refused");
    }

    /* [33] v17 (M214) MULTI-BODY NAMED STEP EXPORT.
     *
     * The bug this guards: the app used to hand the exporter every solid its
     * feature fold produced and let the kernel UNION them, which put back
     * exactly the material the later features had removed. The shim side of
     * the fix is that two bodies go in and TWO SOLIDS come out — never one
     * fused lump — and that each carries its own name.
     *
     * Two DISJOINT boxes: 10x10x10 at the origin and 5x5x5 far away. Volumes
     * 1000 and 125. A fused export would come back as one solid; a correct one
     * comes back as two, total volume 1125. */
    {
        occt_shape *b1 = occt_make_box(10, 10, 10);
        occt_shape *b2raw = occt_make_box(5, 5, 5);
        /* move the second box clear of the first */
        const double away[12] = {1,0,0,100, 0,1,0,0, 0,0,1,0};
        occt_shape *b2 = (b2raw != NULL) ? occt_transform(b2raw, away) : NULL;
        occt_free_shape(b2raw);

        if (check(b1 != NULL && b2 != NULL, "[33] setup boxes failed")) {
            const occt_shape *set[2] = {b1, b2};
            const char *names[2] = {"Solid1", "Solid2"};
            char multi_path[1024];
            snprintf(multi_path, sizeof(multi_path), "%s/prototype_multi.step",
                     (tmpdir && *tmpdir) ? tmpdir : "/tmp");

            if (check(occt_export_step_named(set, names, 2, multi_path,
                                             "SmokePart") == 1,
                      "[33] named multi-body export failed")) {
                occt_shape *back = occt_import_step(multi_path);
                if (check(back != NULL, "[33] re-import returned NULL")) {
                    occt_shape *solids[8];
                    int n = occt_split_solids(back, solids, 8);
                    printf("[33] re-imported solids=%d (want 2)\n", n);
                    check(n == 2, "[33] bodies were fused/merged on export");
                    double total = 0;
                    for (int i = 0; i < n; i++) {
                        total += occt_shape_volume(solids[i]);
                        occt_free_shape(solids[i]);
                    }
                    printf("[33] total volume %.4f (want 1125)\n", total);
                    check(near_rel(total, 1125.0, 1e-4),
                          "[33] volume changed across the roundtrip");
                }
                occt_free_shape(back);

                /* The names and the unit must actually be IN the file. A
                 * silent fallback to OCCT's generic product name, or a unit
                 * left over from an earlier import, would pass every geometric
                 * check above without being noticed.
                 *
                 * The whole file is slurped rather than read line by line: a
                 * STEP writer wraps long entities, and a match split across a
                 * line boundary would read as a missing name. */
                char *blob = slurp(multi_path);
                if (check(blob != NULL, "[33] could not read back the file")) {
                    const int saw1 = strstr(blob, "Solid1") != NULL;
                    const int saw2 = strstr(blob, "Solid2") != NULL;
                    const int sawdoc = strstr(blob, "SmokePart") != NULL;
                    const int saw_mm = strstr(blob, "MILLI") != NULL;
                    printf("[33] in file: Solid1=%d Solid2=%d SmokePart=%d "
                           "MILLI=%d\n", saw1, saw2, sawdoc, saw_mm);
                    check(saw1 && saw2,
                          "[33] per-body product names not written");
                    check(sawdoc,
                          "[33] document name not written to the header");
                    check(saw_mm,
                          "[33] exported STEP does not declare millimetres");
                }
                free(blob);
            }
        }

        /* Failure paths: refused, not crashed, and nothing half-written. */
        check(occt_export_step_named(NULL, NULL, 2, "/tmp/x.step", "P") == 0,
              "[33] null shape array was not refused");
        if (b1 != NULL) {
            const occt_shape *one[1] = {b1};
            check(occt_export_step_named(one, NULL, 0, "/tmp/x.step", "P") == 0,
                  "[33] n = 0 was not refused");
            check(occt_export_step_named(one, NULL, 1, "", "P") == 0,
                  "[33] empty path was not refused");
            const occt_shape *withnull[2] = {b1, NULL};
            check(occt_export_step_named(withnull, NULL, 2, "/tmp/x.step", "P")
                      == 0,
                  "[33] a null body in the set was not refused");
        }
        occt_free_shape(b1);
        occt_free_shape(b2);
    }

    /* [34] v20 (M217) DELETE FACE + DIRECT EDIT, against real geometry.
     *
     * A 20x20x20 box with a 5 mm-radius hole drilled through it. Deleting the
     * hole's cylindrical face with Heal must give the SOLID box back — that is
     * the whole promise of Inventor's Delete Face, and a volume check catches
     * every way of getting it wrong (nothing removed, too much removed, the
     * wrong face removed). Then a face move must change the volume by exactly
     * the swept slab. */
    {
        occt_shape *blk = occt_make_box(20, 20, 20);
        occt_shape *drill = occt_make_cylinder(10, 10, -1, 5, 22);
        occt_shape *holed = (blk && drill) ? occt_cut(blk, drill) : NULL;
        if (check(holed != NULL, "[34] setup (box minus cylinder) failed")) {
            const double v_box = 20.0 * 20.0 * 20.0;
            const double v_hole =
                3.14159265358979323846 * 5.0 * 5.0 * 20.0;
            const double v_holed = occt_shape_volume(holed);
            printf("[34] drilled volume %.4f (want %.4f)\n", v_holed,
                   v_box - v_hole);
            check(near_rel(v_holed, v_box - v_hole, 1e-3),
                  "[34] the drilled block is not the expected volume");

            /* Find the cylindrical face by its surface record. */
            occt_mesh *m = occt_mesh_create(holed, 0.2, 0.35);
            int cyl_topo = -1;
            if (check(m != NULL, "[34] mesh failed")) {
                const int fn = occt_mesh_face_count(m);
                const int fc = (fn > 0 ? fn : 1);
                double *fi = (double *)malloc(sizeof(double) * 15 * fc);
                int *fid = (int *)malloc(sizeof(int) * fc);
                if (fi && fid && occt_mesh_face_infos(m, fi) &&
                    occt_mesh_face_ids(m, fid)) {
                    for (int i = 0; i < fn; ++i) {
                        if ((int)(fi[15 * i] + 0.5) == 1) { /* cylinder */
                            cyl_topo = fid[i];
                            break;
                        }
                    }
                }
                printf("[34] cylindrical face topo index = %d (of %d faces)\n",
                       cyl_topo, fn);
                check(cyl_topo > 0, "[34] no cylindrical face found");
                free(fi);
                free(fid);
            }
            occt_free_mesh(m);

            if (cyl_topo > 0) {
                const int ids[1] = {cyl_topo};
                occt_shape *filled = occt_delete_faces(holed, ids, 1, 1);
                if (check(filled != NULL, "[34] delete face returned NULL")) {
                    const double v = occt_shape_volume(filled);
                    printf("[34] after Delete Face volume %.4f (want %.4f)\n",
                           v, v_box);
                    check(near_rel(v, v_box, 1e-4),
                          "[34] healing the hole did not restore the block");
                    check(occt_shape_valid(filled),
                          "[34] healed solid is not valid");
                }
                occt_free_shape(filled);
                /* heal = 0 is refused, not approximated. */
                check(occt_delete_faces(holed, ids, 1, 0) == NULL,
                      "[34] un-healed delete was not refused");
            }

            /* Direct > Move: push the top face (z = 20) up by 5 mm. The volume
             * must grow by exactly one 20x20x5 slab minus the hole it carries.
             */
            occt_mesh *m2 = occt_mesh_create(holed, 0.2, 0.35);
            int top_topo = -1;
            if (m2 != NULL) {
                const int fn = occt_mesh_face_count(m2);
                const int fc = (fn > 0 ? fn : 1);
                double *fi = (double *)malloc(sizeof(double) * 15 * fc);
                int *fid = (int *)malloc(sizeof(int) * fc);
                if (fi && fid && occt_mesh_face_infos(m2, fi) &&
                    occt_mesh_face_ids(m2, fid)) {
                    for (int i = 0; i < fn; ++i) {
                        /* planar, +Z normal, sitting at z = 20 */
                        if ((int)(fi[15 * i] + 0.5) == 0 &&
                            fi[15 * i + 6] > 0.9 && fi[15 * i + 3] > 19.5) {
                            top_topo = fid[i];
                            break;
                        }
                    }
                }
                free(fi);
                free(fid);
            }
            occt_free_mesh(m2);
            printf("[34] top face topo index = %d\n", top_topo);
            if (check(top_topo > 0, "[34] no top face found")) {
                const int ids[1] = {top_topo};
                occt_shape *taller =
                    occt_move_faces(holed, ids, 1, 0.0, 0.0, 5.0);
                if (check(taller != NULL, "[34] move faces returned NULL")) {
                    const double v = occt_shape_volume(taller);
                    const double want =
                        v_holed + (20.0 * 20.0 * 5.0) -
                        (3.14159265358979323846 * 25.0 * 5.0);
                    printf("[34] after Move Faces volume %.4f (want %.4f)\n",
                           v, want);
                    check(near_rel(v, want, 1e-3),
                          "[34] the moved face did not add the swept slab");
                    check(occt_shape_valid(taller),
                          "[34] moved solid is not valid");
                }
                occt_free_shape(taller);
            }

            /* Direct > Scale: x2 about the centre is 8x the volume. */
            occt_shape *big = occt_scale_shape(holed, 10, 10, 10, 2.0);
            if (check(big != NULL, "[34] scale returned NULL")) {
                const double v = occt_shape_volume(big);
                printf("[34] after Scale x2 volume %.4f (want %.4f)\n", v,
                       v_holed * 8.0);
                check(near_rel(v, v_holed * 8.0, 1e-4),
                      "[34] a x2 scale is not 8x the volume");
            }
            occt_free_shape(big);
            check(occt_scale_shape(holed, 0, 0, 0, 0.0) == NULL,
                  "[34] a zero scale factor was not refused");
        }
        occt_free_shape(blk);
        occt_free_shape(drill);
        occt_free_shape(holed);

        /* Refusals: never crash, always 0/NULL. */
        check(occt_delete_faces(NULL, NULL, 1, 1) == NULL,
              "[34] null shape was not refused");
        check(occt_move_faces(NULL, NULL, 1, 1, 0, 0) == NULL,
              "[34] null move was not refused");
        check(occt_scale_shape(NULL, 0, 0, 0, 2) == NULL,
              "[34] null scale was not refused");
    }

    /* [35] v21 BULK EDGE ENUMERATION — the identity pin.
     *
     * occt_shape_edges_info exists because occt_shape_edge_info rebuilt four
     * whole-shape structures per call and discarded them, making enumeration
     * n x Theta(n): PERFORMANCE_PROFILE.md section 6.5 measures k = 2.012
     * [1.910, 2.113], R^2 = 1.0000, ten seconds for one solid at 1440 edges.
     * The bulk path builds those four once.
     *
     * THE RISK IS NOT SPEED, IT IS SILENCE. Edge indices, adjacency counts,
     * dihedral angles and the convexity sign feed the fingerprint a fillet is
     * re-matched against after a rebuild. One field wrong and a part reattaches
     * its blends to the wrong edges on load, with no error anywhere. So this
     * compares BITWISE, with memcmp and not a tolerance: a tolerance would hide
     * exactly the kind of drift this test exists to catch, such as the ancestor
     * map handing back a different FIRST face and flipping a convexity sign.
     *
     * Five fixtures, chosen to reach every branch of the per-edge code:
     *   box        12 straight edges, all exterior corners -> convexity +1
     *   cylinder   circular edges and a SEAM, which appears twice in its face
     *              and is the case where "first occurrence wins" matters
     *   L-prism    a non-convex profile, so one INTERIOR corner -> the sign
     *              must come out -1 somewhere, or the test proves nothing
     *   filleted   the blend faces, and the most edges of the four
     *   24-gon     THE fixture the profile ladders over, in miniature: two end
     *              faces bounded by 24 edges each and 24 side faces bounded by
     *              four. It is the only one here with a face big enough for
     *              the bulk path's face-edge orientation INDEX to differ in
     *              cost from the per-edge path's linear SCAN — and since the
     *              two paths must still agree bitwise, it is what pins the
     *              index against the scan it replaces
     */
    {
        occt_shape *k35[5] = {NULL, NULL, NULL, NULL, NULL};
        const char *n35[5] = {"box", "cylinder", "L-prism", "filleted",
                              "24-gon"};
        int concave_seen = 0, convex_seen = 0, kinds_seen = 0;

        k35[0] = occt_make_box(20.0, 20.0, 20.0);
        k35[1] = occt_make_cylinder(0.0, 0.0, 0.0, 6.0, 10.0);
        {
            const double L35[] = {0, 0, 40, 0, 40, 10, 10, 10, 10, 30, 0, 30};
            k35[2] = occt_extrude_polygon(L35, 6, 5.0);
        }
        if (k35[0] != NULL) {
            /* Round one vertical edge of a fresh cube — the same construction
             * scenario [21] uses, so the fixture is one the suite already
             * trusts. */
            occt_shape *b = occt_make_box(20.0, 20.0, 20.0);
            if (b != NULL) {
                const int nb = occt_shape_edge_count(b);
                int vert = -1;
                for (int i = 1; i <= nb && vert < 0; ++i) {
                    double info[12] = {0};
                    if (!occt_shape_edge_info(b, i, info))
                        continue;
                    if (info[0] == 1.0 && fabs(fabs(info[6]) - 1.0) < 1e-9)
                        vert = i;
                }
                if (vert > 0) {
                    const int ids[1] = {vert};
                    const double rad[1] = {5.0};
                    k35[3] = occt_fillet_edges(b, ids, rad, NULL, 1);
                }
                occt_free_shape(b);
            }
        }

        {
            /* A regular 24-gon of circumradius 40, extruded 10 mm. */
            double poly[48];
            for (int i = 0; i < 24; ++i) {
                const double a = 2.0 * 3.14159265358979323846 * i / 24.0;
                poly[2 * i] = 40.0 * cos(a);
                poly[2 * i + 1] = 40.0 * sin(a);
            }
            k35[4] = occt_extrude_polygon(poly, 24, 10.0);
        }

        for (int ci = 0; ci < 5; ++ci) {
            occt_shape *s = k35[ci];
            char why[96];
            snprintf(why, sizeof(why), "[35] %s fixture is NULL",
                              n35[ci]);
            if (!check(s != NULL, why))
                continue;
            const int ne = occt_shape_edge_count(s);
            snprintf(why, sizeof(why), "[35] %s has no edges",
                              n35[ci]);
            if (!check(ne > 0, why))
                continue;
            double *bulk = (double *)malloc(sizeof(double) * 12 * (size_t)ne);
            if (!check(bulk != NULL, "[35] out of memory"))
                continue;
            /* Poison every slot. A field the bulk path forgets to write shows
             * up as a difference rather than as an accidental zero that
             * happens to match. */
            for (int i = 0; i < 12 * ne; ++i)
                bulk[i] = -12345.0;

            const int got = occt_shape_edges_info(s, bulk, ne);
            printf("[35] %s: %d edges, bulk wrote %d\n", n35[ci], ne, got);
            snprintf(why, sizeof(why),
                              "[35] %s: bulk did not write one record per edge",
                              n35[ci]);
            check(got == ne, why);

            int diffs = 0;
            for (int i = 1; i <= ne && i <= got; ++i) {
                double one[12];
                const double *bp = bulk + 12 * (i - 1);
                for (int k = 0; k < 12; ++k)
                    one[k] = -54321.0;
                if (!occt_shape_edge_info(s, i, one)) {
                    /* The per-edge path refused this edge. The bulk path must
                     * have said so too, with the type -1 marker, and must not
                     * have invented a record. */
                    if (bp[0] != -1.0) {
                        ++diffs;
                        printf("[35] %s edge %d: per-edge failed, bulk "
                               "reported type %.17g\n",
                               n35[ci], i, bp[0]);
                    }
                    continue;
                }
                if (memcmp(one, bp, sizeof(one)) != 0) {
                    ++diffs;
                    if (diffs <= 3) {
                        for (int k = 0; k < 12; ++k) {
                            if (memcmp(&one[k], &bp[k], sizeof(double)) == 0)
                                continue;
                            printf("[35] %s edge %d field %d: per-edge %.17g "
                                   "bulk %.17g\n",
                                   n35[ci], i, k, one[k], bp[k]);
                        }
                    }
                }
                if (one[11] > 0.0)
                    ++convex_seen;
                if (one[11] < 0.0)
                    ++concave_seen;
                kinds_seen |= 1 << ((int)(one[0] + 0.5) & 7);
            }
            printf("[35] %s: %d of %d records differ\n", n35[ci], diffs, ne);
            snprintf(why, sizeof(why),
                              "[35] %s: bulk and per-edge records differ",
                              n35[ci]);
            check(diffs == 0, why);
            free(bulk);
        }

        /* The fixtures must actually have exercised what they were chosen for.
         * Without this, a bulk path that returned all-zeros for every edge
         * would compare equal to a per-edge path that did the same, and the
         * test above would pass while proving nothing. */
        printf("[35] coverage: convex edges %d, concave edges %d, "
               "curve-kind mask 0x%x\n",
               convex_seen, concave_seen, kinds_seen);
        check(convex_seen > 0, "[35] no CONVEX edge in any fixture");
        check(concave_seen > 0,
              "[35] no CONCAVE edge — the L-prism's interior corner is the "
              "only place the sign can be refuted, and it did not appear");
        check((kinds_seen & (1 << 1)) != 0, "[35] no straight edge seen");
        check((kinds_seen & (1 << 2)) != 0, "[35] no circular edge seen");

        /* Refusals: never a partial fill, never a crash.
         *
         * The buffer is big enough for the WHOLE box even though cap says 1.
         * If the refusal were broken this test must fail an assertion, not
         * smash the stack — a crash here would be blamed on OCCT and the real
         * fault would never be read out of the log. */
        if (k35[0] != NULL) {
            double room[12 * 12];
            check(occt_shape_edges_info(k35[0], room, 1) == -1,
                  "[35] an undersized buffer was not refused");
            check(occt_shape_edges_info(k35[0], NULL, 12) == -1,
                  "[35] a null buffer was not refused");
        }
        check(occt_shape_edges_info(NULL, NULL, 0) == -1,
              "[35] a null shape was not refused");

        for (int ci = 0; ci < 5; ++ci)
            occt_free_shape(k35[ci]);
    }

    /* [36] v22 CONVEXITY, DIFFERENTIALLY — the shipping path against the one
     * it replaced, in one run on one machine.
     *
     * WHY NOT A GOLDEN. Round one's first IPA build failed on four tests that
     * pinned recorded digit strings; they passed on Linux and failed on macOS
     * arm64, and they had never proved the claim they were written for.
     * OPTIMIZATION_PLAN_2.md section 1.4 turned that into a standing rule:
     * keep the old implementation reachable and compare old against new in
     * the same run. occt_shape_edges_info_ref is that reference, and this is
     * that comparison.
     *
     * WHAT MUST MATCH, AND WHAT MUST NOT.
     *
     * Fields 0..10 come out of code both paths share, so a difference in any
     * of them is a defect however small — pinned bitwise, on every fixture.
     *
     * Field 11 is the one v22 changed. On ordinary shapes the two agree
     * bitwise and this test says so. On a shape carrying a feature thinner
     * than the classifier's probe they do NOT agree, and converting that into
     * a tolerance to get a green build is exactly what section 1.4 forbids —
     * so it is pinned as what it is. The probe steps ||bbox diagonal||/1000
     * along the bisector of the two into-face directions, which stands at 45
     * degrees to each face of a square corner, so it crosses any wall thinner
     * than ||diagonal||/(1000*sqrt(2)) = ||diagonal||/1414 and answers about
     * the far side of it:
     *
     *   200 x 0.10 x 20 : diagonal 201.0, probe clearance 0.1421 > 0.10  ->  crosses
     *    60 x 0.04 x 40 : diagonal  72.1, probe clearance 0.0510 > 0.04  ->  crosses
     *
     * A box is a convex solid. Every one of its twelve edges is an exterior
     * corner, so +1 twelve times is the only correct answer and needs no
     * appeal to either implementation. The shipping path must produce it at
     * every thickness; the reference is merely reported. If a future OCCT
     * makes the reference right too, this test still passes — it asserts the
     * ground truth, not the disagreement. */
    {
        struct fx36 {
            const char *name;
            occt_shape *s;
            int thin;      /* thinner than diag/1414 somewhere: field 11 may
                            * legitimately differ, and the reference is wrong */
            int convex_box; /* a box: ground truth is all-convex */
        };
        struct fx36 f36[9];
        int nf36 = 0;
        memset(f36, 0, sizeof(f36));

        f36[nf36].name = "box 20";
        f36[nf36].s = occt_make_box(20.0, 20.0, 20.0);
        f36[nf36].convex_box = 1;
        nf36++;
        f36[nf36].name = "cylinder r6 h10 (seam)";
        f36[nf36].s = occt_make_cylinder(0.0, 0.0, 0.0, 6.0, 10.0);
        nf36++;
        {
            const double L36[] = {0, 0, 40, 0, 40, 10, 10, 10, 10, 30, 0, 30};
            f36[nf36].name = "L-prism (one concave edge)";
            f36[nf36].s = occt_extrude_polygon(L36, 6, 5.0);
            nf36++;
        }
        {
            /* Ten-point star: 10 convex and 10 concave vertices in ONE loop,
             * so the sign has to alternate correctly around the profile
             * rather than merely be constant and lucky. */
            double star[40];
            int i;
            for (i = 0; i < 20; ++i) {
                const double a = 2.0 * 3.14159265358979323846 * i / 20.0;
                const double r = (i % 2 == 0) ? 40.0 : 16.0;
                star[2 * i] = r * cos(a);
                star[2 * i + 1] = r * sin(a);
            }
            f36[nf36].name = "10-point star (alternating)";
            f36[nf36].s = occt_extrude_polygon(star, 20, 8.0);
            nf36++;
        }
        {
            double poly[48];
            int i;
            for (i = 0; i < 24; ++i) {
                const double a = 2.0 * 3.14159265358979323846 * i / 24.0;
                poly[2 * i] = 40.0 * cos(a);
                poly[2 * i + 1] = 40.0 * sin(a);
            }
            f36[nf36].name = "24-gon prism";
            f36[nf36].s = occt_extrude_polygon(poly, 24, 10.0);
            nf36++;
        }
        {
            /* A through hole, so the enumeration meets an inner boundary. */
            occt_shape *a36 = occt_make_box(40.0, 40.0, 40.0);
            occt_shape *c36 = occt_make_cylinder(20.0, 20.0, -5.0, 8.0, 50.0);
            if (a36 != NULL && c36 != NULL) {
                f36[nf36].name = "box minus through-hole";
                f36[nf36].s = occt_cut(a36, c36);
                nf36++;
            }
            occt_free_shape(a36);
            occt_free_shape(c36);
        }
        {
            /* An INTERNAL void: twelve of its edges are genuinely concave and
             * they are the ones a classifier is supposed to be good at. */
            occt_shape *a36 = occt_make_box(40.0, 40.0, 40.0);
            occt_shape *b36 = occt_make_box(10.0, 10.0, 10.0);
            const double mv[12] = {1, 0, 0, 15, 0, 1, 0, 15, 0, 0, 1, 15};
            occt_shape *bt = (b36 != NULL) ? occt_transform(b36, mv) : NULL;
            if (a36 != NULL && bt != NULL) {
                f36[nf36].name = "box with an internal void";
                f36[nf36].s = occt_cut(a36, bt);
                nf36++;
            }
            occt_free_shape(a36);
            occt_free_shape(b36);
            occt_free_shape(bt);
        }
        f36[nf36].name = "box 200 x 0.1 x 20 (THIN)";
        f36[nf36].s = occt_make_box(200.0, 0.1, 20.0);
        f36[nf36].thin = 1;
        f36[nf36].convex_box = 1;
        nf36++;
        f36[nf36].name = "box 60 x 0.04 x 40 (THIN)";
        f36[nf36].s = occt_make_box(60.0, 0.04, 40.0);
        f36[nf36].thin = 1;
        f36[nf36].convex_box = 1;
        nf36++;

        int c36_convex = 0, c36_concave = 0, c36_kinds = 0;
        int thin_fixtures = 0, thin_repairs = 0;
        for (int ci = 0; ci < nf36; ++ci) {
            occt_shape *s = f36[ci].s;
            char why[192];
            snprintf(why, sizeof(why), "[36] %s fixture is NULL", f36[ci].name);
            if (!check(s != NULL, why))
                continue;
            const int ne = occt_shape_edge_count(s);
            snprintf(why, sizeof(why), "[36] %s has no edges", f36[ci].name);
            if (!check(ne > 0, why))
                continue;
            double *neu = (double *)malloc(sizeof(double) * 12 * (size_t)ne);
            double *ref = (double *)malloc(sizeof(double) * 12 * (size_t)ne);
            if (!check(neu != NULL && ref != NULL, "[36] out of memory")) {
                free(neu);
                free(ref);
                continue;
            }
            for (int i = 0; i < 12 * ne; ++i) {
                neu[i] = -12345.0;
                ref[i] = -54321.0;
            }
            const int gn = occt_shape_edges_info(s, neu, ne);
            const int gr = occt_shape_edges_info_ref(s, ref, ne);
            snprintf(why, sizeof(why),
                     "[36] %s: the two paths wrote different record counts",
                     f36[ci].name);
            check(gn == ne && gr == ne, why);

            int head_diff = 0, sign_diff = 0, box_wrong_new = 0,
                box_wrong_ref = 0;
            const int n = (gn < gr) ? gn : gr;
            for (int i = 0; i < n; ++i) {
                const double *a = neu + 12 * i;
                const double *b = ref + 12 * i;
                /* Fields 0..10: shared code, must be identical. */
                if (memcmp(a, b, sizeof(double) * 11) != 0) {
                    ++head_diff;
                    if (head_diff <= 3) {
                        for (int k = 0; k < 11; ++k)
                            if (memcmp(&a[k], &b[k], sizeof(double)) != 0)
                                printf("[36] %s edge %d field %d: new %.17g "
                                       "ref %.17g\n",
                                       f36[ci].name, i + 1, k, a[k], b[k]);
                    }
                }
                if (a[11] != b[11]) {
                    ++sign_diff;
                    if (f36[ci].thin && sign_diff <= 3)
                        printf("[36] %s edge %d: dihedral %.4f deg, "
                               "new %+.0f ref %+.0f (expected: the probe "
                               "crosses the wall)\n",
                               f36[ci].name, i + 1, a[10], a[11], b[11]);
                }
                if (f36[ci].convex_box) {
                    if (a[11] != 1.0)
                        ++box_wrong_new;
                    if (b[11] != 1.0)
                        ++box_wrong_ref;
                }
                if (a[11] > 0.0)
                    ++c36_convex;
                if (a[11] < 0.0)
                    ++c36_concave;
                c36_kinds |= 1 << ((int)(a[0] + 0.5) & 7);
            }
            printf("[36] %s: %d edges, fields 0..10 differ on %d, "
                   "convexity differs on %d\n",
                   f36[ci].name, n, head_diff, sign_diff);

            snprintf(why, sizeof(why),
                     "[36] %s: fields 0..10 differ between the two paths — "
                     "they share that code, so any difference is a defect",
                     f36[ci].name);
            check(head_diff == 0, why);

            if (!f36[ci].thin) {
                snprintf(why, sizeof(why),
                         "[36] %s: convexity differs from the reference on a "
                         "fixture with no feature below diagonal/1414",
                         f36[ci].name);
                check(sign_diff == 0, why);
            } else {
                ++thin_fixtures;
                /* The fixture must actually reach the regime it exists for,
                 * or it is proving nothing. */
                snprintf(why, sizeof(why),
                         "[36] %s: the thin-wall fixture produced NO "
                         "disagreement, so it no longer reaches the regime it "
                         "was built for — re-derive the threshold",
                         f36[ci].name);
                check(sign_diff > 0, why);
                thin_repairs += sign_diff;
                printf("[36] %s: reference got %d of %d box edges wrong, "
                       "shipping path %d\n",
                       f36[ci].name, box_wrong_ref, n, box_wrong_new);
            }
            if (f36[ci].convex_box) {
                /* GROUND TRUTH, independent of both implementations. */
                snprintf(why, sizeof(why),
                         "[36] %s: a box is a CONVEX solid and every one of "
                         "its edges is an exterior corner, but the shipping "
                         "path did not say so",
                         f36[ci].name);
                check(box_wrong_new == 0, why);
            }
            free(neu);
            free(ref);
        }

        printf("[36] coverage: convex %d, concave %d, curve-kind mask 0x%x, "
               "thin fixtures %d with %d repaired signs\n",
               c36_convex, c36_concave, c36_kinds, thin_fixtures,
               thin_repairs);
        check(c36_convex > 0, "[36] no CONVEX edge in any fixture");
        check(c36_concave > 0,
              "[36] no CONCAVE edge — the star and the internal void are "
              "there to produce them, and neither did");
        check((c36_kinds & (1 << 1)) != 0, "[36] no straight edge seen");
        check((c36_kinds & (1 << 2)) != 0, "[36] no circular edge seen");
        check(thin_fixtures == 2,
              "[36] the two thin-wall fixtures did not both build");

        /* The reference shares the shipping path's argument checking. */
        if (f36[0].s != NULL) {
            double room36[12 * 12];
            check(occt_shape_edges_info_ref(f36[0].s, room36, 1) == -1,
                  "[36] ref: an undersized buffer was not refused");
            check(occt_shape_edges_info_ref(f36[0].s, NULL, 12) == -1,
                  "[36] ref: a null buffer was not refused");
        }
        check(occt_shape_edges_info_ref(NULL, NULL, 0) == -1,
              "[36] ref: a null shape was not refused");

        for (int ci = 0; ci < nf36; ++ci)
            occt_free_shape(f36[ci].s);
    }

    /* [37] v24 SWEEP ALONG A SAMPLED CURVE — the regime that did not build.
     *
     * A device capture on 2026-08-24 ran a 1200-segment ring along a 16-span
     * sampled arc and got "BRep_API: command not done" after 231 085 ms. The
     * cause is in perf/findings/S14-sweep.md: every joint of the sampler's
     * polyline was mitered, and a miter is a BOPAlgo_PaveFiller between two
     * shells carrying one face per profile segment each.
     *
     * Five things are pinned here, and the first two matter most:
     *
     *  (a) A DRAWN corner is untouched — AUTO and POLY produce the same solid,
     *      compared in ONE run on THIS machine rather than against a recorded
     *      constant. If the fix ever starts rounding off geometry a user drew,
     *      this is what says so.
     *  (b) A SAMPLED path IS smoothed, and the face count says it: one spine
     *      edge means `segments + 2` faces, not `segments x spans + 2`.
     *  (c) The threshold is the app's own sampler ceiling, 360/64 = 5.625 deg:
     *      a joint just under it is smoothed, a joint just over it is not.
     *  (d) The rung that FAILED on the device builds, is valid, and encloses
     *      the analytic volume. THERE IS NO OLD BEHAVIOUR TO COMPARE IT TO —
     *      the old path produces nothing at all here — so this arm is an
     *      absolute check against arithmetic, not a differential one, and it
     *      is the only arm of [37] that is.
     *  (e) The rungs that were silently WRONG (10.6 % too large, invalid) and
     *      that ABORTED THE PROCESS with a corrupt heap are correct now. POLY
     *      is deliberately NOT run at those sizes: one of them kills the
     *      process and the other takes twelve minutes.
     */
    {
        /* The fixture is the perf tier's: frontend/lib/perf_scenarios_profile
         * .dart sweeps arcRing(segments, 6) along arcPath(spans + 1, 60). */
        const double I37[12] = {1,0,0,0, 0,1,0,0, 0,0,1,0};
        static double prof37[2048 * 3];
        static double path37[513 * 3];

        /* V = A(n) . L . cos(tilt) holds for this sweep to eight figures, with
         * L the TRUE arc length of the curve the polyline samples — see S14
         * §2.8, which also says plainly that I could not derive why the
         * polyline's own (shorter) length does not appear instead. */
        const double kL37 = 66.328259;      /* hypot(18, 120/pi) * pi/2 */
        const double kCos37 = 0.90459156;   /* (120/pi) / hypot(18, 120/pi) */

        int i37;

        /* ---- (a) a drawn 90-degree corner is untouched, AUTO vs POLY ---- */
        {
            const double P[] = {0,0,0,  10,0,0,  10,10,0,  0,10,0};
            const int lc[] = {4};
            const double lpath[] = {0,0,0,  0,0,40,  30,0,40};
            occt_shape *au = occt_sweep_profile_ex(P, lc, 1, I37, lpath, 3,
                                                   0, 0.0, 0.0,
                                                   OCCT_SWEEP_PATH_AUTO);
            occt_shape *po = occt_sweep_profile_ex(P, lc, 1, I37, lpath, 3,
                                                   0, 0.0, 0.0,
                                                   OCCT_SWEEP_PATH_POLY);
            if (check(au != NULL, "[37a] AUTO refused a 90-degree L path") &&
                check(po != NULL, "[37a] POLY refused a 90-degree L path")) {
                int fa = 0, ea = 0, va = 0, fp = 0, ep = 0, vp = 0;
                occt_shape_counts(au, &fa, &ea, &va);
                occt_shape_counts(po, &fp, &ep, &vp);
                const double vau = occt_shape_volume(au);
                const double vpo = occt_shape_volume(po);
                printf("[37a] L path 90 deg: AUTO vol=%.9f f=%d e=%d v=%d | "
                       "POLY vol=%.9f f=%d e=%d v=%d\n",
                       vau, fa, ea, va, vpo, fp, ep, vp);
                /* Not "close to": the same. 90 deg is far above the 5.625 deg
                 * threshold, so AUTO takes the polygon path and every later
                 * call sees identical arguments. */
                check(vau == vpo, "[37a] AUTO changed a DRAWN corner's volume");
                check(fa == fp && ea == ep && va == vp,
                      "[37a] AUTO changed a DRAWN corner's topology");
                check(near_rel(vau, 6000.0, 1e-9),
                      "[37a] the mitered L is not the analytic 6000");
                check(occt_shape_valid(au), "[37a] AUTO's L solid is invalid");
            }
            if (au) occt_free_shape(au);
            if (po) occt_free_shape(po);
        }

        /* ---- (b) a sampled arc path IS smoothed ---- */
        {
            const int seg = 64, spans = 16;
            const int lc[] = {64};
            for (i37 = 0; i37 < seg; ++i37) {
                const double a = 2.0 * M_PI * i37 / seg;
                prof37[3*i37+0] = 6.0 * cos(a);
                prof37[3*i37+1] = 6.0 * sin(a);
                prof37[3*i37+2] = 0.0;
            }
            for (i37 = 0; i37 <= spans; ++i37) {
                const double t = (double)i37 / spans, a = t * M_PI / 2.0;
                path37[3*i37+0] = 60.0 * sin(a) * 0.3;
                path37[3*i37+1] = 60.0 * (1.0 - cos(a)) * 0.3;
                path37[3*i37+2] = t * 60.0;
            }
            occt_shape *au = occt_sweep_profile_ex(prof37, lc, 1, I37, path37,
                                                   spans + 1, 0, 0.0, 0.0,
                                                   OCCT_SWEEP_PATH_AUTO);
            occt_shape *po = occt_sweep_profile_ex(prof37, lc, 1, I37, path37,
                                                   spans + 1, 0, 0.0, 0.0,
                                                   OCCT_SWEEP_PATH_POLY);
            if (check(au != NULL, "[37b] AUTO refused a sampled arc path") &&
                check(po != NULL, "[37b] POLY refused a sampled arc path")) {
                int fa = 0, fp = 0;
                occt_shape_counts(au, &fa, NULL, NULL);
                occt_shape_counts(po, &fp, NULL, NULL);
                const double want = 0.5 * seg * 36.0 * sin(2.0 * M_PI / seg)
                                    * kL37 * kCos37;
                printf("[37b] 64 seg x 16 spans: AUTO f=%d vol=%.6f | "
                       "POLY f=%d vol=%.6f | analytic %.6f\n",
                       fa, occt_shape_volume(au), fp, occt_shape_volume(po),
                       want);
                /* One spine edge: seg lateral faces plus two caps. */
                check(fa == seg + 2,
                      "[37b] AUTO did not smooth a sampled arc path");
                check(fp == seg * spans + 2,
                      "[37b] POLY is no longer the v23 polyline path");
                /* Both are right here; this is the size at which they agree,
                 * and saying so is what makes (e) mean something. */
                check(near_rel(occt_shape_volume(au), want, 1e-4),
                      "[37b] AUTO's volume is not the analytic one");
                check(near_rel(occt_shape_volume(po), want, 1e-4),
                      "[37b] POLY's volume is not the analytic one");
                check(occt_shape_valid(au), "[37b] AUTO's solid is invalid");
                /* S14 item 3, P17: an arc's joints are sweep/64 <= 5.625 deg
                 * by construction, so AUTO already smooths every arc and the
                 * Dart side DECLARING it smooth can only agree. If these two
                 * ever diverge, the threshold is wrong rather than merely
                 * unnecessary, and that is worth a test failure. */
                {
                    occt_shape *sm = occt_sweep_profile_ex(
                        prof37, lc, 1, I37, path37, spans + 1, 0, 0.0, 0.0,
                        OCCT_SWEEP_PATH_SMOOTH);
                    if (check(sm != NULL, "[37b] SMOOTH refused an arc path")) {
                        int fs = 0;
                        occt_shape_counts(sm, &fs, NULL, NULL);
                        printf("[37b] the same arc DECLARED smooth: f=%d "
                               "vol=%.6f (AUTO inferred the same)\n", fs,
                               occt_shape_volume(sm));
                        check(fs == fa && occt_shape_volume(sm)
                                              == occt_shape_volume(au),
                              "[37b] declaring an arc smooth differs from "
                              "inferring it");
                        occt_free_shape(sm);
                    }
                }
            }
            if (au) occt_free_shape(au);
            if (po) occt_free_shape(po);
        }

        /* ---- (c) the threshold, from both sides ---- */
        {
            const double P[] = {0,0,0,  10,0,0,  10,10,0,  0,10,0};
            const int lc[] = {4};
            /* straight 40 up, then 30 more at `deg` off it, in the XZ plane */
            const double under = 5.0, over = 6.5; /* 5.625 is the threshold */
            double pu[9], pv[9];
            double d;
            int k;
            for (k = 0; k < 2; ++k) {
                double *q = k ? pv : pu;
                d = (k ? over : under) * M_PI / 180.0;
                q[0]=0; q[1]=0; q[2]=0;
                q[3]=0; q[4]=0; q[5]=40;
                q[6]=30*sin(d); q[7]=0; q[8]=40+30*cos(d);
            }
            occt_shape *su = occt_sweep_profile_ex(P, lc, 1, I37, pu, 3, 0,
                                                   0.0, 0.0,
                                                   OCCT_SWEEP_PATH_AUTO);
            occt_shape *sv = occt_sweep_profile_ex(P, lc, 1, I37, pv, 3, 0,
                                                   0.0, 0.0,
                                                   OCCT_SWEEP_PATH_AUTO);
            if (check(su != NULL, "[37c] AUTO refused a 5.0-degree joint") &&
                check(sv != NULL, "[37c] AUTO refused a 6.5-degree joint")) {
                int fu = 0, fv = 0;
                occt_shape_counts(su, &fu, NULL, NULL);
                occt_shape_counts(sv, &fv, NULL, NULL);
                printf("[37c] joint 5.0 deg -> %d faces (smoothed), "
                       "6.5 deg -> %d faces (mitered); threshold 5.625\n",
                       fu, fv);
                /* 6 = one smooth run: 4 lateral faces + 2 caps.
                 * 8 = two runs: 8 lateral faces + 2 caps, less the two whose
                 *     planes survive the bend (it turns in XZ, so the +-Y
                 *     faces stay coplanar) and which finish_pipe's
                 *     UnifySameDomain therefore merges. Both counts are
                 *     exact; what the pin is really saying is that one path
                 *     has a joint in it and the other does not. */
                check(fu == 6, "[37c] a 5.0-degree joint was NOT smoothed");
                check(fv == 8, "[37c] a 6.5-degree joint WAS smoothed");
            }
            /* And the same 5.0-degree joint DECLARED as drawn: the caller
             * saying "these are my vertices" must override the threshold, or
             * item 3's whole point is lost. This is what a hand-drawn polyline
             * path now gets from the Dart side. */
            {
                occt_shape *sd = occt_sweep_profile_ex(P, lc, 1, I37, pu, 3, 0,
                                                       0.0, 0.0,
                                                       OCCT_SWEEP_PATH_POLY);
                if (check(sd != NULL, "[37c] POLY refused a 5.0-degree joint")) {
                    int fd = 0;
                    occt_shape_counts(sd, &fd, NULL, NULL);
                    printf("[37c] the SAME 5.0-degree joint declared POLY -> "
                           "%d faces (mitered, not smoothed)\n", fd);
                    check(fd == 8, "[37c] a DECLARED polyline joint was "
                                   "smoothed anyway");
                    occt_free_shape(sd);
                }
            }
            if (su) occt_free_shape(su);
            if (sv) occt_free_shape(sv);
        }

        /* ---- (d) the rung that FAILED on the device ---- */
        {
            const int seg = 1200, spans = 16;
            const int lc[] = {1200};
            for (i37 = 0; i37 < seg; ++i37) {
                const double a = 2.0 * M_PI * i37 / seg;
                prof37[3*i37+0] = 6.0 * cos(a);
                prof37[3*i37+1] = 6.0 * sin(a);
                prof37[3*i37+2] = 0.0;
            }
            for (i37 = 0; i37 <= spans; ++i37) {
                const double t = (double)i37 / spans, a = t * M_PI / 2.0;
                path37[3*i37+0] = 60.0 * sin(a) * 0.3;
                path37[3*i37+1] = 60.0 * (1.0 - cos(a)) * 0.3;
                path37[3*i37+2] = t * 60.0;
            }
            occt_shape *s = occt_sweep_profile_ex(prof37, lc, 1, I37, path37,
                                                  spans + 1, 0, 0.0, 0.0,
                                                  OCCT_SWEEP_PATH_AUTO);
            /* No POLY arm: it FAILS here, after 231 s on the device and 742 s
             * on the machine this was developed on. There is nothing to be
             * equivalent to. */
            if (check(s != NULL,
                      "[37d] 1200 segments x 16 spans STILL does not build")) {
                int f = 0;
                double v;
                occt_shape_counts(s, &f, NULL, NULL);
                v = occt_shape_volume(s);
                printf("[37d] 1200 seg x 16 spans: f=%d vol=%.6f "
                       "(analytic %.6f) — v23 FAILED here\n", f, v,
                       0.5 * seg * 36.0 * sin(2.0 * M_PI / seg) * kL37 * kCos37);
                check(f == seg + 2, "[37d] the 1200-segment sweep is not one "
                                    "smooth run");
                check(near_rel(v, 0.5 * seg * 36.0 * sin(2.0 * M_PI / seg)
                                      * kL37 * kCos37, 1e-4),
                      "[37d] the 1200-segment volume is not analytic");
                check(occt_shape_valid(s), "[37d] the 1200-segment solid is "
                                           "invalid");
                occt_free_shape(s);
            }
        }

        /* ---- (f) a HOLE is placed the way its own body is placed ----
         *
         * v26. finish_pipe had added every hole with
         * WithCorrection = Standard_True since v15 while occt_sweep_profile
         * added the outer wire with the CALLER'S setting, and it threw away the
         * `orientation` it was passed (`(void)orientation`) so the hole got a
         * Frenet trihedron even when the body got a fixed one. Two wires, two
         * frames, one solid: a holed sweep along a tilted path lost 3.2 % of
         * its volume, silently, on every path that was not straight.
         *
         * THE TEST THAT MATTERS IS THE DIFFERENTIAL, and it needs no analytic
         * model: a tube's volume must be the difference of the two single-loop
         * sweeps that make it, and all three of those are built here in one
         * run. It also holds for orientation 2, where the analytic annulus does
         * NOT — WithCorrection rotates the section, so orientation 2's tube is
         * legitimately a different solid. An analytic-only test would have had
         * to skip the orientation the defect's own control lived in.
         */
        {
            const int seg = 24, spans = 8;
            const int lc2[] = {24, 24};
            const int lc1[] = {24};
            double xyb[2 * 24 * 3];
            double outer[24 * 3], inner[24 * 3];
            const double ann = 0.5 * seg * 36.0 * sin(2.0 * M_PI / seg)
                               - 0.5 * seg * 9.0 * sin(2.0 * M_PI / seg);
            int orient;
            for (i37 = 0; i37 < seg; ++i37) {
                const double a = 2.0 * M_PI * i37 / seg;
                outer[3*i37+0] = xyb[3*i37+0] = 6.0 * cos(a);
                outer[3*i37+1] = xyb[3*i37+1] = 6.0 * sin(a);
                outer[3*i37+2] = xyb[3*i37+2] = 0.0;
                inner[3*i37+0] = xyb[3*(seg+i37)+0] = 3.0 * cos(a);
                inner[3*i37+1] = xyb[3*(seg+i37)+1] = 3.0 * sin(a);
                inner[3*i37+2] = xyb[3*(seg+i37)+2] = 0.0;
            }

            /* arm 1 — a straight path, where the answer is arithmetic */
            {
                const double sp[6] = {0,0,0, 0,0,40};
                occt_shape *t = occt_sweep_profile_ex(xyb, lc2, 2, I37, sp, 2,
                                                      0, 0.0, 0.0,
                                                      OCCT_SWEEP_PATH_AUTO);
                if (check(t != NULL, "[37f] a holed profile on a straight "
                                     "path refused")) {
                    const double v = occt_shape_volume(t);
                    printf("[37f] tube on a STRAIGHT path: vol=%.6f "
                           "(analytic %.6f) %s\n", v, ann * 40.0,
                           occt_shape_valid(t) ? "valid" : "INVALID");
                    check(near_rel(v, ann * 40.0, 1e-9),
                          "[37f] the straight tube is not analytic");
                    check(occt_shape_valid(t), "[37f] the straight tube is "
                                               "invalid");
                    occt_free_shape(t);
                }
            }

            for (i37 = 0; i37 <= spans; ++i37) {
                const double t = (double)i37 / spans, a = t * M_PI / 2.0;
                path37[3*i37+0] = 60.0 * sin(a) * 0.3;
                path37[3*i37+1] = 60.0 * (1.0 - cos(a)) * 0.3;
                path37[3*i37+2] = t * 60.0;
            }

            /* arm 2 — the differential, at all three orientations */
            for (orient = 0; orient <= 2; ++orient) {
                occt_shape *tu = occt_sweep_profile_ex(xyb, lc2, 2, I37, path37,
                                                       spans + 1, orient, 0.0,
                                                       0.0,
                                                       OCCT_SWEEP_PATH_POLY);
                occt_shape *bo = occt_sweep_profile_ex(outer, lc1, 1, I37,
                                                       path37, spans + 1,
                                                       orient, 0.0, 0.0,
                                                       OCCT_SWEEP_PATH_POLY);
                occt_shape *hi = occt_sweep_profile_ex(inner, lc1, 1, I37,
                                                       path37, spans + 1,
                                                       orient, 0.0, 0.0,
                                                       OCCT_SWEEP_PATH_POLY);
                if (check(tu != NULL && bo != NULL && hi != NULL,
                          "[37f] a sweep refused on the tilted arc path")) {
                    const double vt = occt_shape_volume(tu);
                    const double want = occt_shape_volume(bo)
                                        - occt_shape_volume(hi);
                    printf("[37f] tube on a tilted arc, orientation %d: "
                           "vol=%.6f  outer-hole=%.6f  (%+.4f %%) %s\n",
                           orient, vt, want, 100.0 * (vt - want) / want,
                           occt_shape_valid(tu) ? "valid" : "INVALID");
                    check(near_rel(vt, want, 1e-9),
                          "[37f] a hole is not placed the way its body is");
                    check(occt_shape_valid(tu), "[37f] the tube is invalid");
                    /* and for the two orientations that do not rotate the
                     * section, the analytic annulus agrees as well */
                    if (orient != 2)
                        check(near_rel(vt, ann * kL37 * kCos37, 1e-6),
                              "[37f] the tube is not the analytic annulus");
                }
                if (tu) occt_free_shape(tu);
                if (bo) occt_free_shape(bo);
                if (hi) occt_free_shape(hi);
            }

            /* arm 3 — v27: AUTO now DOES smooth a holed profile, and this
             * arm is inverted to say so.
             *
             * It read "AUTO and POLY must be the same object" because v24
             * forced a holed profile back onto the polyline spine — the hole
             * was removed with a boolean, and that boolean costs 21 653.6 ms
             * between two smooth-spine solids against 85.4 ms between two
             * polyline ones (S14 §4.1). v27 assembles instead of subtracting,
             * so the reason is gone and the restriction with it.
             *
             * THIS IS THE BEHAVIOUR CHANGE THIS SESSION MAKES, and it is the
             * same one v24 made for unholed profiles: a holed sweep along a
             * sampled arc comes back as one smooth run instead of a mitered
             * one. The check below is what a smooth run MEANS — 2 faces per
             * profile segment plus 2 caps — plus the analytic annulus, rather
             * than a recorded number. */
            {
                occt_shape *au = occt_sweep_profile_ex(xyb, lc2, 2, I37, path37,
                                                       spans + 1, 0, 0.0, 0.0,
                                                       OCCT_SWEEP_PATH_AUTO);
                occt_shape *po = occt_sweep_profile_ex(xyb, lc2, 2, I37, path37,
                                                       spans + 1, 0, 0.0, 0.0,
                                                       OCCT_SWEEP_PATH_POLY);
                if (check(au != NULL && po != NULL,
                          "[37f] AUTO or POLY refused a holed profile")) {
                    int fa = 0, fp = 0;
                    const double va = occt_shape_volume(au);
                    occt_shape_counts(au, &fa, NULL, NULL);
                    occt_shape_counts(po, &fp, NULL, NULL);
                    printf("[37f] holed AUTO f=%d vol=%.6f | POLY f=%d "
                           "vol=%.6f (analytic %.6f) %s\n", fa, va, fp,
                           occt_shape_volume(po), ann * kL37 * kCos37,
                           occt_shape_valid(au) ? "valid" : "INVALID");
                    check(fa == 2 * seg + 2,
                          "[37f] AUTO did not smooth a holed profile");
                    check(fp > fa,
                          "[37f] POLY is no longer the mitered polyline path");
                    check(near_rel(va, ann * kL37 * kCos37, 1e-4),
                          "[37f] the smoothed tube is not the analytic "
                          "annulus");
                    check(occt_shape_valid(au),
                          "[37f] the smoothed tube is invalid");
                }
                if (au) occt_free_shape(au);
                if (po) occt_free_shape(po);
            }
        }

        /* ---- (h) a STRAIGHT run stays straight ----
         *
         * Five collinear points have joints of 0 degrees, which is well under
         * the threshold, so a naive reading of "smooth the shallow runs" would
         * interpolate them. It must not: a B-spline through collinear points is
         * the same LINE, but the faces swept along it stop being PLANES — and
         * a plane is what makes the boolean that removes a hole cheap. Nothing
         * curved is given up by leaving it alone, so v23's edges stay.
         *
         * BE PRECISE ABOUT WHAT THIS PROVES. The face count does NOT
         * discriminate: an interpolated spine would give one spline edge and
         * 4 + 2 faces, and the polyline's 16 + 2 are merged down to the same 6
         * by finish_pipe's UnifySameDomain. What discriminates is the EXACT
         * equality below — a swept B-spline surface would not reproduce the
         * planar sweep's volume bit for bit — plus the analytic 4000. So this
         * arm is a differential with an arithmetic backstop, and it is not a
         * check on the surface type, which the C ABI cannot see.
         */
        {
            const double P[] = {0,0,0,  10,0,0,  10,10,0,  0,10,0};
            const int lc[] = {4};
            const double sp[15] = {0,0,0,  0,0,10,  0,0,20,  0,0,30,  0,0,40};
            occt_shape *au = occt_sweep_profile_ex(P, lc, 1, I37, sp, 5, 0,
                                                   0.0, 0.0,
                                                   OCCT_SWEEP_PATH_AUTO);
            occt_shape *po = occt_sweep_profile_ex(P, lc, 1, I37, sp, 5, 0,
                                                   0.0, 0.0,
                                                   OCCT_SWEEP_PATH_POLY);
            if (check(au != NULL, "[37h] AUTO refused a collinear path") &&
                check(po != NULL, "[37h] POLY refused a collinear path")) {
                int fa = 0, ea = 0, fp = 0, ep = 0;
                const double va = occt_shape_volume(au);
                const double vp = occt_shape_volume(po);
                occt_shape_counts(au, &fa, &ea, NULL);
                occt_shape_counts(po, &fp, &ep, NULL);
                printf("[37h] 5 collinear points: AUTO vol=%.9f f=%d e=%d | "
                       "POLY vol=%.9f f=%d e=%d\n", va, fa, ea, vp, fp, ep);
                check(va == vp && fa == fp && ea == ep,
                      "[37h] a straight run was not left alone");
                check(near_rel(va, 4000.0, 1e-9),
                      "[37h] the straight sweep is not the analytic 4000");
            }
            if (au) occt_free_shape(au);
            if (po) occt_free_shape(po);
        }

        /* ---- (e) the two rungs v23 got WRONG rather than slow ---- */
        {
            const int seg = 64;
            const int lc[] = {64};
            int spansv[2];
            int si;
            spansv[0] = 32; /* v23: 7490.04, 10.6 % too large, and INVALID */
            spansv[1] = 64; /* v23: heap corruption, SIGABRT, no result */
            for (i37 = 0; i37 < seg; ++i37) {
                const double a = 2.0 * M_PI * i37 / seg;
                prof37[3*i37+0] = 6.0 * cos(a);
                prof37[3*i37+1] = 6.0 * sin(a);
                prof37[3*i37+2] = 0.0;
            }
            for (si = 0; si < 2; ++si) {
                const int spans = spansv[si];
                const double want = 0.5 * seg * 36.0 * sin(2.0 * M_PI / seg)
                                    * kL37 * kCos37;
                occt_shape *s;
                for (i37 = 0; i37 <= spans; ++i37) {
                    const double t = (double)i37 / spans, a = t * M_PI / 2.0;
                    path37[3*i37+0] = 60.0 * sin(a) * 0.3;
                    path37[3*i37+1] = 60.0 * (1.0 - cos(a)) * 0.3;
                    path37[3*i37+2] = t * 60.0;
                }
                s = occt_sweep_profile_ex(prof37, lc, 1, I37, path37, spans + 1,
                                          0, 0.0, 0.0, OCCT_SWEEP_PATH_AUTO);
                if (check(s != NULL, "[37e] a short-span sampled arc refused")) {
                    int f = 0;
                    const double v = occt_shape_volume(s);
                    occt_shape_counts(s, &f, NULL, NULL);
                    printf("[37e] 64 seg x %d spans: f=%d vol=%.6f "
                           "(analytic %.6f) %s\n", spans, f, v, want,
                           occt_shape_valid(s) ? "valid" : "INVALID");
                    check(f == seg + 2, "[37e] not one smooth run");
                    check(near_rel(v, want, 1e-4),
                          "[37e] the volume is not analytic");
                    check(occt_shape_valid(s), "[37e] the solid is invalid");
                    occt_free_shape(s);
                }
            }
        }
    }

    /* [38] v25 ORIENTATION 1 ("Fixed") ON A PATH THAT BENDS.
     *
     * Broken since v15 and never caught, because a STRAIGHT path is exact in
     * both OCCT laws and nothing else was tried. `occt_sweep_profile` mapped
     * orientation 1 to BRepFill_PipeShell::Set(const gp_Dir&) —
     * GeomFill_ConstantBiNormal, which replaces the sweep frame's tangent with
     * the real tangent's projection perpendicular to the binormal. On a path
     * climbing at 25 deg from +Z that is 65 deg off, and the shell passes
     * through itself: 16 429 where the answer is 6 000, and INVALID.
     *
     * "Fixed" means every section stays parallel to the profile plane, so
     * Cavalieri gives the volume outright: section area x total rise in z,
     * whatever the path does in XY. A 10x10 square climbing to z = 60 is
     * 100 x 60 = 6000 EXACTLY, at every span count. That is what is asserted,
     * and it is arithmetic rather than a recorded number.
     *
     * The POLY arm is the one that matters to the integrator: it runs the v23
     * spine, so it says this fix does not depend on v24. Both are asserted
     * here so the independence is a test result and not a claim.
     */
    {
        const double S[] = {-5,-5,0,  5,-5,0,  5,5,0,  -5,5,0};
        const int lc[] = {4};
        const double I38[12] = {1,0,0,0, 0,1,0,0, 0,0,1,0};
        double p38[3 * 17];
        int spansv[3];
        int si, i38, mode;
        spansv[0] = 2; spansv[1] = 4; spansv[2] = 16;

        /* the straight arm first: the case that already worked must not move */
        {
            const double up[6] = {0,0,0, 0,0,40};
            occt_shape *a = occt_sweep_profile_ex(S, lc, 1, I38, up, 2, 1,
                                                  0.0, 0.0,
                                                  OCCT_SWEEP_PATH_POLY);
            if (check(a != NULL, "[38] orientation 1 refused a straight path")) {
                int f = 0;
                const double v = occt_shape_volume(a);
                occt_shape_counts(a, &f, NULL, NULL);
                printf("[38] straight +Z, orientation 1: vol=%.9f f=%d %s "
                       "(analytic 4000)\n", v, f,
                       occt_shape_valid(a) ? "valid" : "INVALID");
                check(near_rel(v, 4000.0, 1e-9),
                      "[38] the straight Fixed sweep is not analytic");
                check(occt_shape_valid(a), "[38] the straight Fixed sweep is "
                                           "invalid");
                occt_free_shape(a);
            }
        }

        /* and the bending arm, in BOTH path modes */
        for (mode = 0; mode < 2; ++mode) {
            const int pm = mode ? OCCT_SWEEP_PATH_AUTO : OCCT_SWEEP_PATH_POLY;
            for (si = 0; si < 3; ++si) {
                const int spans = spansv[si];
                occt_shape *a;
                for (i38 = 0; i38 <= spans; ++i38) {
                    const double t = (double)i38 / spans, ang = t * M_PI / 2.0;
                    p38[3*i38+0] = 60.0 * sin(ang) * 0.3;
                    p38[3*i38+1] = 60.0 * (1.0 - cos(ang)) * 0.3;
                    p38[3*i38+2] = t * 60.0;
                }
                a = occt_sweep_profile_ex(S, lc, 1, I38, p38, spans + 1, 1,
                                          0.0, 0.0, pm);
                if (check(a != NULL, "[38] orientation 1 refused an arc path")) {
                    const double v = occt_shape_volume(a);
                    /* label from `mode`, NOT from `pm`: AUTO is 0 and POLY
                     * is 1, so `pm ? "AUTO" : "POLY"` prints exactly the wrong
                     * one — which it did, until this line was read. */
                    printf("[38] arc %2d spans, orientation 1, %s: vol=%.9f %s "
                           "(analytic 6000; v23 gave 7448 / 8981 / 16429, all "
                           "INVALID)\n", spans, mode ? "AUTO" : "POLY", v,
                           occt_shape_valid(a) ? "valid" : "INVALID");
                    check(near_rel(v, 6000.0, 1e-9),
                          "[38] Fixed did not keep the sections parallel");
                    check(occt_shape_valid(a),
                          "[38] the Fixed sweep is invalid");
                    occt_free_shape(a);
                }
            }
        }
    }


    /* [39] v27 — A HOLED PROFILE IS ASSEMBLED, NOT SUBTRACTED.
     *
     * finish_pipe removed every hole with a BRepAlgoAPI_Cut from v15 to v26.
     * That boolean is what forced a holed profile back onto the v23 polyline
     * spine (its cost is 99.7 % of a smooth-spine holed sweep, S14 §4.1), and
     * therefore what kept a holed profile failing at 1200 segments long after
     * v24 fixed the unholed one. v27 sweeps each wire to its lateral shell,
     * caps both ends with a planar face carrying the holes as inner
     * boundaries, sews and makes a solid.
     *
     * The assembly is a SPECIAL operation where the boolean was a GENERAL one:
     * it assumes each hole is strictly inside the outer boundary and that the
     * holes are pairwise disjoint. Nothing checked that before, because
     * nothing needed it to. profile_holes_are_separate now does, and when it
     * says no the v26 boolean runs unchanged. Arms (c) and (d) below are that
     * guard, and they are the reason S14 handed this over rather than
     * committing it.
     *
     * Every pin here is ARITHMETIC or a DIFFERENTIAL taken in this run. A
     * regular n-gon of circumradius R has area 0.5*n*R^2*sin(2*pi/n), and a
     * straight sweep of a constant section is area x length; where the path
     * bends, the claim is against occt_cut of the same two sweeps, which is
     * the operation v26 used and is built here through a different entry
     * point.
     */
    {
        const double I39[12] = {1,0,0,0, 0,1,0,0, 0,0,1,0};
        const int seg = 24;
        const double s39 = sin(2.0 * M_PI / seg);
        const double L39 = 40.0;
        const double sp39[6] = {0,0,0, 0,0,40};
        double path39[3 * 17];
        int i, k;
        /* area of a regular 24-gon of circumradius R */
#define A39(R) (0.5 * seg * (R) * (R) * s39)
        for (i = 0; i <= 8; ++i) {
            const double t = (double)i / 8.0, a = t * M_PI / 2.0;
            path39[3*i+0] = 60.0 * sin(a) * 0.3;
            path39[3*i+1] = 60.0 * (1.0 - cos(a)) * 0.3;
            path39[3*i+2] = t * 60.0;
        }

        /* ---- (a) TWO and THREE holes: k inner wires per cap ----
         * S14 §12.3 risk 4, "mechanical, untested". */
        {
            double xyb[4 * 24 * 3];
            const int lc3[] = {24, 24, 24};
            const int lc4[] = {24, 24, 24, 24};
            double want;
            occt_shape *t;
            /* two r=1.5 holes at (+-3, 0) */
            for (i = 0; i < seg; ++i) {
                const double a = 2.0 * M_PI * i / seg;
                xyb[3*i+0] = 6.0 * cos(a);
                xyb[3*i+1] = 6.0 * sin(a);
                xyb[3*i+2] = 0.0;
                xyb[3*(seg+i)+0] = -3.0 + 1.5 * cos(a);
                xyb[3*(seg+i)+1] = 1.5 * sin(a);
                xyb[3*(seg+i)+2] = 0.0;
                xyb[3*(2*seg+i)+0] = 3.0 + 1.5 * cos(a);
                xyb[3*(2*seg+i)+1] = 1.5 * sin(a);
                xyb[3*(2*seg+i)+2] = 0.0;
            }
            want = (A39(6.0) - 2.0 * A39(1.5)) * L39;
            t = occt_sweep_profile_ex(xyb, lc3, 3, I39, sp39, 2, 0, 0.0, 0.0,
                                      OCCT_SWEEP_PATH_AUTO);
            if (check(t != NULL, "[39a] two holes refused")) {
                const double v = occt_shape_volume(t);
                printf("[39a] 2 holes, straight: vol=%.9f (analytic %.9f) %s\n",
                       v, want, occt_shape_valid(t) ? "valid" : "INVALID");
                check(near_rel(v, want, 1e-9),
                      "[39a] a two-holed sweep is not analytic");
                check(occt_shape_valid(t), "[39a] the two-holed sweep is "
                                           "invalid");
                occt_free_shape(t);
            }
            /* three r=1.2 holes at radius 3, 120 degrees apart */
            for (k = 0; k < 3; ++k) {
                const double cx = 3.0 * cos(2.0 * M_PI * k / 3.0);
                const double cy = 3.0 * sin(2.0 * M_PI * k / 3.0);
                for (i = 0; i < seg; ++i) {
                    const double a = 2.0 * M_PI * i / seg;
                    xyb[3*((k+1)*seg+i)+0] = cx + 1.2 * cos(a);
                    xyb[3*((k+1)*seg+i)+1] = cy + 1.2 * sin(a);
                    xyb[3*((k+1)*seg+i)+2] = 0.0;
                }
            }
            want = (A39(6.0) - 3.0 * A39(1.2)) * L39;
            t = occt_sweep_profile_ex(xyb, lc4, 4, I39, sp39, 2, 0, 0.0, 0.0,
                                      OCCT_SWEEP_PATH_AUTO);
            if (check(t != NULL, "[39a] three holes refused")) {
                const double v = occt_shape_volume(t);
                printf("[39a] 3 holes, straight: vol=%.9f (analytic %.9f) %s\n",
                       v, want, occt_shape_valid(t) ? "valid" : "INVALID");
                check(near_rel(v, want, 1e-9),
                      "[39a] a three-holed sweep is not analytic");
                check(occt_shape_valid(t), "[39a] the three-holed sweep is "
                                           "invalid");
                occt_free_shape(t);
            }
            /* and on the bending path, where the pin is the differential */
            t = occt_sweep_profile_ex(xyb, lc4, 4, I39, path39, 9, 0, 0.0, 0.0,
                                      OCCT_SWEEP_PATH_POLY);
            if (check(t != NULL, "[39a] three holes refused on an arc")) {
                const int lc1[] = {24};
                occt_shape *bo = occt_sweep_profile_ex(xyb, lc1, 1, I39,
                                                       path39, 9, 0, 0.0, 0.0,
                                                       OCCT_SWEEP_PATH_POLY);
                double w = bo ? occt_shape_volume(bo) : -1.0;
                for (k = 0; k < 3 && bo; ++k) {
                    occt_shape *hi = occt_sweep_profile_ex(
                        xyb + 3 * (k + 1) * seg, lc1, 1, I39, path39, 9, 0,
                        0.0, 0.0, OCCT_SWEEP_PATH_POLY);
                    if (!hi) { w = -1.0; break; }
                    w -= occt_shape_volume(hi);
                    occt_free_shape(hi);
                }
                if (bo) occt_free_shape(bo);
                if (check(w > 0.0, "[39a] a component sweep refused")) {
                    const double v = occt_shape_volume(t);
                    printf("[39a] 3 holes, tilted arc: vol=%.9f "
                           "outer-holes=%.9f (%+.3e) %s\n", v, w,
                           (v - w) / w,
                           occt_shape_valid(t) ? "valid" : "INVALID");
                    check(near_rel(v, w, 1e-9),
                          "[39a] three holes are not placed like their body");
                    check(occt_shape_valid(t), "[39a] the arc three-holed "
                                               "sweep is invalid");
                }
                occt_free_shape(t);
            }
        }

        /* ---- (b) TAPER: both end sections scale, and the caps still match ----
         * S14 §12.3 risk 3, "I believe the caps still match, and I did not
         * test it".
         *
         * finish_pipe gives the outer wire and every hole the SAME
         * Law_Linear(0 -> 1, 1 -> 1+k), applied about the section's own
         * location frame — one station on the spine, shared by both wires. So
         * at every station the two sections are ONE homothety of the profile
         * about a common centre, which is what keeps the hole inside the body
         * and the two end sections coplanar. The annular area at station t is
         * (A_out - A_in) * s(t)^2, so on a straight path
         *   V = (A_out - A_in) * L * integral[0,1] (1+kt)^2 dt
         *     = (A_out - A_in) * L * (1 + k + k^2/3).
         * Cross-check on the unholed law: [37g] measures 6766.447913 ->
         * 7375.699522, a ratio of 1.0900399 against the 1.0900401 below. */
        {
            const double tap = 5.0;
            const double kk = tan(tap * M_PI / 180.0);
            const double f = 1.0 + kk + kk * kk / 3.0;
            const double want = (A39(6.0) - A39(3.0)) * L39 * f;
            const int lc2[] = {24, 24};
            double xyb[2 * 24 * 3];
            int pm;
            occt_shape *t;
            for (i = 0; i < seg; ++i) {
                const double a = 2.0 * M_PI * i / seg;
                xyb[3*i+0] = 6.0 * cos(a);
                xyb[3*i+1] = 6.0 * sin(a);
                xyb[3*i+2] = 0.0;
                xyb[3*(seg+i)+0] = 3.0 * cos(a);
                xyb[3*(seg+i)+1] = 3.0 * sin(a);
                xyb[3*(seg+i)+2] = 0.0;
            }
            t = occt_sweep_profile_ex(xyb, lc2, 2, I39, sp39, 2, 0, tap, 0.0,
                                      OCCT_SWEEP_PATH_AUTO);
            if (check(t != NULL, "[39b] a tapered tube refused")) {
                const double v = occt_shape_volume(t);
                printf("[39b] tapered tube, straight: vol=%.9f "
                       "(analytic %.9f) %s\n", v, want,
                       occt_shape_valid(t) ? "valid" : "INVALID");
                check(near_rel(v, want, 1e-9),
                      "[39b] a tapered tube is not analytic");
                check(occt_shape_valid(t), "[39b] the tapered tube is invalid");
                occt_free_shape(t);
            }
            /* Both spines on the bending path, each against the BOOLEAN the
             * assembly replaced — occt_cut of the same two sweeps, the same
             * OCCT operation on the same operands, reached through a different
             * entry point in this run.
             *
             * NOT against vol(outer) - vol(hole), which is what [37f] uses and
             * what the first version of this arm used. That subtraction is a
             * valid pin only while both operands are valid solids, and ON THE
             * POLYLINE SPINE WITH A TAPER THEY ARE NOT — see the note below.
             *
             * A TAPERED SWEEP ALONG A SPINE OF MORE THAN ONE EDGE PRODUCES AN
             * INVALID SOLID, and it has nothing to do with holes. Measured
             * against the v26 shim, in the same run, on the SINGLE-LOOP sweep:
             * a 24-gon tapered 5 deg over the 8-span polyline arc gives
             * 10 476.381185581, INVALID, in BOTH v26 and v27, every digit the
             * same. A drawn 90-degree L corner does it too — 8 555.054342,
             * INVALID, under plain AUTO, which is a shape a user can draw. A
             * one-edge spine (straight, or a smoothed run) is valid. Recorded
             * in perf/findings/S15-holes.md §4.3 and CROSS-SESSION; NOT fixed
             * here, because it is a second defect and it gets its own
             * pre-registration.
             *
             * So this arm asserts what it can honestly assert: the tube is the
             * cut, exactly, and the tube is valid EXACTLY WHEN the unholed
             * sweep it is made from is. The assembly is not allowed to be
             * worse than its own ingredients; it is not asked to be better. */
            for (pm = 0; pm < 2; ++pm) {
                const int mode = pm ? OCCT_SWEEP_PATH_SMOOTH
                                    : OCCT_SWEEP_PATH_POLY;
                const int lc1[] = {24};
                occt_shape *tu = occt_sweep_profile_ex(xyb, lc2, 2, I39,
                                                       path39, 9, 0, tap, 0.0,
                                                       mode);
                occt_shape *bo = occt_sweep_profile_ex(xyb, lc1, 1, I39,
                                                       path39, 9, 0, tap, 0.0,
                                                       mode);
                occt_shape *hi = occt_sweep_profile_ex(xyb + 3 * seg, lc1, 1,
                                                       I39, path39, 9, 0, tap,
                                                       0.0, mode);
                occt_shape *ref = (bo && hi) ? occt_cut(bo, hi) : NULL;
                if (check(tu != NULL && ref != NULL,
                          "[39b] a tapered sweep refused on the arc path")) {
                    const double v = occt_shape_volume(tu);
                    const double w = occt_shape_volume(ref);
                    printf("[39b] tapered tube, tilted arc, %s: vol=%.9f "
                           "cut(outer,hole)=%.9f (%+.3e%s) tube %s / unholed "
                           "%s\n", pm ? "SMOOTH" : "POLY", v, w, (v - w) / w,
                           v == w ? ", EXACT" : "",
                           occt_shape_valid(tu) ? "valid" : "INVALID",
                           occt_shape_valid(bo) ? "valid" : "INVALID");
                    check(near_rel(v, w, 1e-9),
                          "[39b] a tapered hole is not placed like its body");
                    check(occt_shape_valid(tu) == occt_shape_valid(bo),
                          "[39b] the tapered tube is worse than its own "
                          "unholed sweep");
                }
                if (tu) occt_free_shape(tu);
                if (bo) occt_free_shape(bo);
                if (hi) occt_free_shape(hi);
                if (ref) occt_free_shape(ref);
            }
        }

        /* ---- (g) THE ASSEMBLY IS THE SUBTRACTION, on a contained hole ----
         *
         * [37f] already asserts that a tube equals its outer sweep MINUS its
         * hole sweep, by volume arithmetic. That is the right pin for v26's
         * defect and it is not quite the right pin for v27's claim: v27 says
         * the assembled solid IS the solid the boolean produced, so the
         * comparison should be against the boolean, not against a subtraction
         * of two numbers.
         *
         * Measured on the machine this was developed on, in one run, against
         * the v26 shim built from the parent commit: taper 0 / POLY gives
         * 5 031.442236788 and 386 faces in BOTH; taper 0 / SMOOTH gives
         * 5 031.037365496 and 50 faces in BOTH — the same doubles, not the
         * same ten figures. The assertion here is 1e-9 rather than == because
         * two different OCCT operations agreeing bit for bit is an observation
         * about one toolchain and not a property anyone promised; whether it
         * WAS exact is printed, so a platform where it stops being exact says
         * so instead of going quietly red. */
        {
            const int lc2[] = {24, 24};
            const int lc1[] = {24};
            double xyb[2 * 24 * 3];
            int pm;
            for (i = 0; i < seg; ++i) {
                const double a = 2.0 * M_PI * i / seg;
                xyb[3*i+0] = 6.0 * cos(a);
                xyb[3*i+1] = 6.0 * sin(a);
                xyb[3*i+2] = 0.0;
                xyb[3*(seg+i)+0] = 3.0 * cos(a);
                xyb[3*(seg+i)+1] = 3.0 * sin(a);
                xyb[3*(seg+i)+2] = 0.0;
            }
            for (pm = 0; pm < 2; ++pm) {
                const int mode = pm ? OCCT_SWEEP_PATH_SMOOTH
                                    : OCCT_SWEEP_PATH_POLY;
                occt_shape *tu = occt_sweep_profile_ex(xyb, lc2, 2, I39,
                                                       path39, 9, 0, 0.0, 0.0,
                                                       mode);
                occt_shape *bo = occt_sweep_profile_ex(xyb, lc1, 1, I39,
                                                       path39, 9, 0, 0.0, 0.0,
                                                       mode);
                occt_shape *hi = occt_sweep_profile_ex(xyb + 3 * seg, lc1, 1,
                                                       I39, path39, 9, 0, 0.0,
                                                       0.0, mode);
                occt_shape *ref = (bo && hi) ? occt_cut(bo, hi) : NULL;
                if (check(tu != NULL && ref != NULL,
                          "[39g] a contained hole refused")) {
                    int fa = 0, fr = 0;
                    const double v = occt_shape_volume(tu);
                    const double w = occt_shape_volume(ref);
                    occt_shape_counts(tu, &fa, NULL, NULL);
                    occt_shape_counts(ref, &fr, NULL, NULL);
                    printf("[39g] assembled vs boolean, %s: vol=%.9f vs "
                           "%.9f (%+.3e%s) f=%d vs %d %s\n",
                           pm ? "SMOOTH" : "POLY", v, w, (v - w) / w,
                           v == w ? ", EXACT" : "", fa, fr,
                           occt_shape_valid(tu) ? "valid" : "INVALID");
                    check(near_rel(v, w, 1e-9),
                          "[39g] the assembly is not the subtraction");
                    check(fa == fr,
                          "[39g] the assembly has a different topology from "
                          "the subtraction");
                    check(occt_shape_valid(tu),
                          "[39g] the assembled tube is invalid");
                }
                if (tu) occt_free_shape(tu);
                if (bo) occt_free_shape(bo);
                if (hi) occt_free_shape(hi);
                if (ref) occt_free_shape(ref);
            }
        }

        /* ---- (c) A HOLE THAT POKES OUT — the guard, and the fallback ----
         *
         * THIS IS THE ARM THE WHOLE GUARD EXISTS FOR. An r=2 hole centred at
         * (5.5, 0) reaches 7.5 from the origin against an outer circumradius
         * of 6, so it straddles the wall. The assembly would put an inner wire
         * on the cap that leaves the cap; the subtraction removes material
         * outside the body as well and is right. profile_holes_are_separate
         * must refuse, finish_pipe must run the v26 boolean, and the answer
         * must be the boolean's.
         *
         * The comparison operand is occt_cut of the same two sweeps — the same
         * OCCT operation on the same operands, reached through a different
         * entry point in the same run. It is a differential, not a recorded
         * number, and it is the one that would catch a guard that let this
         * through. */
        {
            const int lc2[] = {24, 24};
            const int lc1[] = {24};
            double xyb[2 * 24 * 3];
            int orient;
            for (i = 0; i < seg; ++i) {
                const double a = 2.0 * M_PI * i / seg;
                xyb[3*i+0] = 6.0 * cos(a);
                xyb[3*i+1] = 6.0 * sin(a);
                xyb[3*i+2] = 0.0;
                xyb[3*(seg+i)+0] = 5.5 + 2.0 * cos(a);
                xyb[3*(seg+i)+1] = 2.0 * sin(a);
                xyb[3*(seg+i)+2] = 0.0;
            }
            /* POLY on all three, and the reason is worth having in writing:
             * the TUBE is AUTO, but the guard refuses this profile, so AUTO
             * falls back to POLY for it — deliberately, so the boolean does
             * not land on the spine that makes it 80x slower. A single-loop
             * reference sweep asked for AUTO would be SMOOTHED, and the arm
             * would then compare two different spines. It did, on the first
             * run, and orientation 0 came out 1.1 % apart while orientation 1
             * agreed to 4e-10 — because "Fixed" gives A x rise whatever the
             * path does in XY, so it cannot see a spine change. Naming the
             * mode on all three is what makes this a differential. */
            for (orient = 0; orient <= 1; ++orient) {
                occt_shape *t = occt_sweep_profile_ex(xyb, lc2, 2, I39, path39,
                                                      9, orient, 0.0, 0.0,
                                                      OCCT_SWEEP_PATH_AUTO);
                occt_shape *bo = occt_sweep_profile_ex(xyb, lc1, 1, I39,
                                                       path39, 9, orient, 0.0,
                                                       0.0,
                                                       OCCT_SWEEP_PATH_POLY);
                occt_shape *hi = occt_sweep_profile_ex(xyb + 3 * seg, lc1, 1,
                                                       I39, path39, 9, orient,
                                                       0.0, 0.0,
                                                       OCCT_SWEEP_PATH_POLY);
                occt_shape *ref = (bo && hi) ? occt_cut(bo, hi) : NULL;
                if (check(t != NULL && ref != NULL,
                          "[39c] a poking hole refused")) {
                    const double v = occt_shape_volume(t);
                    const double w = occt_shape_volume(ref);
                    printf("[39c] hole poking outside, orientation %d: "
                           "vol=%.9f  cut(outer,hole)=%.9f (%+.3e) %s\n",
                           orient, v, w, (v - w) / w,
                           occt_shape_valid(t) ? "valid" : "INVALID");
                    check(near_rel(v, w, 1e-9),
                          "[39c] a poking hole did not fall back to the "
                          "boolean");
                    check(occt_shape_valid(t),
                          "[39c] the poking-hole sweep is invalid");
                }
                if (t) occt_free_shape(t);
                if (bo) occt_free_shape(bo);
                if (hi) occt_free_shape(hi);
                if (ref) occt_free_shape(ref);
            }
        }

        /* ---- (d) TWO HOLES THAT OVERLAP — the guard's other half ----
         *
         * Two r=2 holes 3 apart both sit inside the outer boundary, so the
         * containment half of the guard says yes to each of them. Their
         * boundaries cross each other, and an assembly would put two
         * overlapping inner wires on one cap. The pairwise half must refuse,
         * and the answer must be the two cuts. */
        {
            const int lc3[] = {24, 24, 24};
            const int lc1[] = {24};
            double xyb[3 * 24 * 3];
            occt_shape *t, *bo, *h1, *h2, *r1, *ref;
            for (i = 0; i < seg; ++i) {
                const double a = 2.0 * M_PI * i / seg;
                xyb[3*i+0] = 6.0 * cos(a);
                xyb[3*i+1] = 6.0 * sin(a);
                xyb[3*i+2] = 0.0;
                xyb[3*(seg+i)+0] = -1.5 + 2.0 * cos(a);
                xyb[3*(seg+i)+1] = 2.0 * sin(a);
                xyb[3*(seg+i)+2] = 0.0;
                xyb[3*(2*seg+i)+0] = 1.5 + 2.0 * cos(a);
                xyb[3*(2*seg+i)+1] = 2.0 * sin(a);
                xyb[3*(2*seg+i)+2] = 0.0;
            }
            t = occt_sweep_profile_ex(xyb, lc3, 3, I39, sp39, 2, 0, 0.0, 0.0,
                                      OCCT_SWEEP_PATH_AUTO);
            bo = occt_sweep_profile_ex(xyb, lc1, 1, I39, sp39, 2, 0, 0.0, 0.0,
                                       OCCT_SWEEP_PATH_AUTO);
            h1 = occt_sweep_profile_ex(xyb + 3 * seg, lc1, 1, I39, sp39, 2, 0,
                                       0.0, 0.0, OCCT_SWEEP_PATH_AUTO);
            h2 = occt_sweep_profile_ex(xyb + 6 * seg, lc1, 1, I39, sp39, 2, 0,
                                       0.0, 0.0, OCCT_SWEEP_PATH_AUTO);
            r1 = (bo && h1) ? occt_cut(bo, h1) : NULL;
            ref = (r1 && h2) ? occt_cut(r1, h2) : NULL;
            if (check(t != NULL && ref != NULL,
                      "[39d] two overlapping holes refused")) {
                const double v = occt_shape_volume(t);
                const double w = occt_shape_volume(ref);
                printf("[39d] two OVERLAPPING holes: vol=%.9f "
                       "cut(cut(outer,h1),h2)=%.9f (%+.3e) %s\n", v, w,
                       (v - w) / w, occt_shape_valid(t) ? "valid" : "INVALID");
                check(near_rel(v, w, 1e-9),
                      "[39d] overlapping holes did not fall back to the "
                      "boolean");
                check(occt_shape_valid(t),
                      "[39d] the overlapping-hole sweep is invalid");
            }
            if (t) occt_free_shape(t);
            if (bo) occt_free_shape(bo);
            if (h1) occt_free_shape(h1);
            if (h2) occt_free_shape(h2);
            if (r1) occt_free_shape(r1);
            if (ref) occt_free_shape(ref);
        }

        /* ---- (e) A HOLED COIL — finish_pipe's OTHER caller ----
         *
         * occt_coil_profile shares finish_pipe, so it takes the assembly for
         * free. S14's P16 pinned this at 5562.133035056 with 50 faces; that
         * constant is NOT what is checked here, because a recorded double pins
         * a machine. What is checked is what P16 actually claimed: the holed
         * coil equals its own outer-minus-hole, which the boolean already
         * satisfied exactly and the assembly must too. */
        {
            const int lc2[] = {24, 24};
            const int lc1[] = {24};
            double xyb[2 * 24 * 3];
            occt_shape *cu, *bo, *hi;
            for (i = 0; i < seg; ++i) {
                const double a = 2.0 * M_PI * i / seg;
                xyb[3*i+0] = 18.0 + 6.0 * cos(a);
                xyb[3*i+1] = 6.0 * sin(a);
                xyb[3*i+2] = 0.0;
                xyb[3*(seg+i)+0] = 18.0 + 3.0 * cos(a);
                xyb[3*(seg+i)+1] = 3.0 * sin(a);
                xyb[3*(seg+i)+2] = 0.0;
            }
            cu = occt_coil_profile(xyb, lc2, 2, I39, 0,0,0, 0,1,0, 0.25, 60.0,
                                   0.0, 0, 0, 0);
            bo = occt_coil_profile(xyb, lc1, 1, I39, 0,0,0, 0,1,0, 0.25, 60.0,
                                   0.0, 0, 0, 0);
            hi = occt_coil_profile(xyb + 3 * seg, lc1, 1, I39, 0,0,0, 0,1,0,
                                   0.25, 60.0, 0.0, 0, 0, 0);
            if (check(cu != NULL && bo != NULL && hi != NULL,
                      "[39e] a holed coil refused")) {
                int f = 0;
                const double v = occt_shape_volume(cu);
                const double w = occt_shape_volume(bo) - occt_shape_volume(hi);
                occt_shape_counts(cu, &f, NULL, NULL);
                printf("[39e] holed coil: vol=%.9f outer-hole=%.9f (%+.3e) "
                       "f=%d %s\n", v, w, (v - w) / w, f,
                       occt_shape_valid(cu) ? "valid" : "INVALID");
                check(near_rel(v, w, 1e-9),
                      "[39e] a coil's hole is not placed like its body");
                check(f == 2 * seg + 2, "[39e] the holed coil is not one "
                                        "smooth run");
                check(occt_shape_valid(cu), "[39e] the holed coil is invalid");
            }
            if (cu) occt_free_shape(cu);
            if (bo) occt_free_shape(bo);
            if (hi) occt_free_shape(hi);
        }

        /* ---- (h) A PROFILE MADE OF ARCS — the guard's flattening ----
         *
         * Every fixture above is a polygon, and for a polygon the containment
         * test is exact. A bulge is not: profile_holes_are_separate flattens
         * each loop at 2 degrees per sub-chord and carries the largest sagitta
         * it discarded, because a polygon through points ON an arc can sit up
         * to that sagitta on the WRONG SIDE of it. Both arms below are about
         * the arcs and neither would notice a chord-only guard being wrong —
         * except that a chord-only guard cannot even represent the outer loop
         * here, which is the point of using a TWO-POINT loop.
         *
         * A 2-point loop with bulge 1 at both vertices is two semicircles: a
         * TRUE circle of radius 5, whose area is exactly 25*pi. That makes the
         * first arm analytic on a profile the flattening has to get right.
         *
         * THE SIGN OF THAT FLATTENING WAS WRONG WHEN FIRST WRITTEN and a
         * fixture like this is what found it — the guard called a hole OUTSIDE
         * the profile "safely inside", which is the exact failure the guard
         * exists to prevent. See flatten_loop's comment for the arithmetic.
         */
        {
            const int lcA[] = {2, 24};
            const int lcB[] = {2, 4};
            const int lc1[] = {2};
            const int lcs[] = {4};
            double A[2 * 3 + 24 * 3];
            double B[2 * 3 + 4 * 3];
            double want;
            occt_shape *t, *bo, *hi, *ref;
            A[0] = -5.0; A[1] = 0.0; A[2] = 1.0;
            A[3] =  5.0; A[4] = 0.0; A[5] = 1.0;
            for (i = 0; i < seg; ++i) {
                const double a = 2.0 * M_PI * i / seg;
                A[6 + 3*i] = cos(a);
                A[7 + 3*i] = sin(a);
                A[8 + 3*i] = 0.0;
            }
            want = (M_PI * 25.0 - A39(1.0)) * L39;
            t = occt_sweep_profile_ex(A, lcA, 2, I39, sp39, 2, 0, 0.0, 0.0,
                                      OCCT_SWEEP_PATH_AUTO);
            if (check(t != NULL, "[39h] an arc profile with a hole refused")) {
                const double v = occt_shape_volume(t);
                printf("[39h] TRUE circle r=5 with a 24-gon r=1 hole: "
                       "vol=%.9f (analytic %.9f, %+.2e) %s\n", v, want,
                       (v - want) / want,
                       occt_shape_valid(t) ? "valid" : "INVALID");
                check(near_rel(v, want, 1e-9),
                      "[39h] an arc profile's tube is not analytic");
                check(occt_shape_valid(t), "[39h] the arc tube is invalid");
                occt_free_shape(t);
            }

            /* and a hole STRADDLING that circle: 4.5 to 5.5 in x, so half of
             * it is outside a boundary that exists only as an arc. The guard
             * must refuse and the boolean must answer. `o - h` is printed
             * beside it because it does NOT agree — which is what proves the
             * hole really straddles rather than merely sitting near the wall. */
            B[0] = -5.0; B[1] = 0.0; B[2] = 1.0;
            B[3] =  5.0; B[4] = 0.0; B[5] = 1.0;
            B[6]  = 4.5; B[7]  = -0.5; B[8]  = 0.0;
            B[9]  = 5.5; B[10] = -0.5; B[11] = 0.0;
            B[12] = 5.5; B[13] =  0.5; B[14] = 0.0;
            B[15] = 4.5; B[16] =  0.5; B[17] = 0.0;
            t  = occt_sweep_profile_ex(B, lcB, 2, I39, sp39, 2, 0, 0.0, 0.0,
                                       OCCT_SWEEP_PATH_AUTO);
            bo = occt_sweep_profile_ex(B, lc1, 1, I39, sp39, 2, 0, 0.0, 0.0,
                                       OCCT_SWEEP_PATH_AUTO);
            hi = occt_sweep_profile_ex(B + 6, lcs, 1, I39, sp39, 2, 0, 0.0,
                                       0.0, OCCT_SWEEP_PATH_AUTO);
            ref = (bo && hi) ? occt_cut(bo, hi) : NULL;
            if (check(t != NULL && ref != NULL,
                      "[39h] a straddling hole refused")) {
                const double v = occt_shape_volume(t);
                const double w = occt_shape_volume(ref);
                const double d = occt_shape_volume(bo) - occt_shape_volume(hi);
                printf("[39h] hole STRADDLING an arc wall: vol=%.9f "
                       "cut(outer,hole)=%.9f (%+.3e)  outer-hole=%.9f %s\n",
                       v, w, (v - w) / w, d,
                       occt_shape_valid(t) ? "valid" : "INVALID");
                check(near_rel(v, w, 1e-9),
                      "[39h] a hole straddling an ARC wall was not refused");
                check(!near_rel(d, w, 1e-6),
                      "[39h] the straddling fixture does not actually "
                      "straddle");
                check(occt_shape_valid(t),
                      "[39h] the straddled tube is invalid");
            }
            if (t) occt_free_shape(t);
            if (bo) occt_free_shape(bo);
            if (hi) occt_free_shape(hi);
            if (ref) occt_free_shape(ref);
        }

        /* ---- (f) THE BAR: 1200 segments, with a hole, on the sampled arc ----
         *
         * This is the rung the whole session exists for. The device capture of
         * 2026-08-24 failed at 1200 segments WITHOUT a hole after 231 s; v24
         * fixed that one and [37d] pins it. A holed profile got none of it,
         * because AUTO was forced back to POLY. Measured on the machine this
         * was developed on (perf/findings/S15-holes.md §2.2 and §2.4): the v26
         * route FAILS after 490 407 ms with "BRep_API: command not done", and
         * the v27 assembly builds in 7 952.7 ms and is valid.
         *
         * There is NO differential arm here and there cannot be: v26 produces
         * nothing at this size, so there is nothing to be equivalent to. The
         * check is arithmetic instead, exactly as [37d]'s comment says for the
         * same reason. The tolerance is 1e-4 rather than 1e-9 because an
         * interpolated spine is not the sampled polyline: [37d] measures that
         * gap as 4.1e-6 unholed and §2.2 measures it as 4.24e-6 holed.
         *
         * IT IS THE MOST EXPENSIVE ARM IN THIS FILE, and most of that is the
         * two lines at the bottom rather than the sweep: 8.0 s to build,
         * 16.8 s for occt_shape_volume and 8.8 s for occt_shape_valid over
         * 2 402 B-spline faces. §2.4 has the split. Both are kept — a solid
         * that builds and is not valid would be the worst outcome available
         * here, and the volume is the only thing that says it is the right
         * solid. */
        {
            const int n = 1200, spans = 16;
            const int lcb[] = {1200, 1200};
            static double xyb[2 * 1200 * 3];
            double pathb[3 * 17];
            double ann, want;
            occt_shape *t;
            for (i = 0; i < n; ++i) {
                const double a = 2.0 * M_PI * i / n;
                xyb[3*i+0] = 6.0 * cos(a);
                xyb[3*i+1] = 6.0 * sin(a);
                xyb[3*i+2] = 0.0;
                xyb[3*(n+i)+0] = 3.0 * cos(a);
                xyb[3*(n+i)+1] = 3.0 * sin(a);
                xyb[3*(n+i)+2] = 0.0;
            }
            for (i = 0; i <= spans; ++i) {
                const double t2 = (double)i / spans, a = t2 * M_PI / 2.0;
                pathb[3*i+0] = 60.0 * sin(a) * 0.3;
                pathb[3*i+1] = 60.0 * (1.0 - cos(a)) * 0.3;
                pathb[3*i+2] = t2 * 60.0;
            }
            /* (A_out - A_in) x 60: the 60 is exact, because
             * hypot(18, 120/pi) * pi/2 * (120/pi) / hypot(18, 120/pi) = 60. */
            ann = 0.5 * n * (36.0 - 9.0) * sin(2.0 * M_PI / n);
            want = ann * 60.0;
            t = occt_sweep_profile_ex(xyb, lcb, 2, I39, pathb, spans + 1, 0,
                                      0.0, 0.0, OCCT_SWEEP_PATH_AUTO);
            if (check(t != NULL, "[39f] 1200 segments WITH A HOLE still does "
                                 "not build")) {
                int f = 0;
                const double v = occt_shape_volume(t);
                occt_shape_counts(t, &f, NULL, NULL);
                printf("[39f] 1200 seg x 16 spans, HOLED: f=%d vol=%.6f "
                       "(analytic %.6f) %s — v26 FAILED here after 490 s\n",
                       f, v, want, occt_shape_valid(t) ? "valid" : "INVALID");
                check(f == 2 * n + 2,
                      "[39f] the 1200-segment holed sweep is not one smooth "
                      "run");
                check(near_rel(v, want, 1e-4),
                      "[39f] the 1200-segment holed volume is not analytic");
                check(occt_shape_valid(t),
                      "[39f] the 1200-segment holed solid is invalid");
                occt_free_shape(t);
            }
        }
#undef A39
    }

    /* ====================================================================
     * [40] S16 — THE STRAIGHT AUDIT.
     *
     * S14 fixed three defects in the sweep and closed with a question it
     * could not answer: "I do not know what else in this shim is only ever
     * exercised straight." The inventory in perf/findings/S16-straight-audit.md
     * answers it by reading every call site above: EIGHT direction / axis /
     * placement parameters have never been passed anything but their trivial
     * value, and three of those are reachable from the UI.
     *
     * These scenarios bend each one, once, on purpose.
     *
     * The instrument, where no closed form exists, is RIGID EQUIVARIANCE:
     * for any op taking a direction, an axis or a placement,
     *
     *     op(R . inputs)  ==  R . op(inputs)
     *
     * and volume is invariant under R, so equality of the two volumes is a
     * necessary condition that needs no analytic formula for the shape and no
     * recorded golden (OPTIMIZATION_PLAN_2.md section 1.4). It fails exactly
     * when the code has an axis baked in that the caller thinks is a
     * parameter — which is the defect class S14 found.
     *
     * Where a closed form DOES exist it is preferred, and for a revolve there
     * is a good one: PAPPUS's second theorem, V = 2*pi*d*A, with d the
     * distance from the profile's centroid to the axis. It stays exact as the
     * axis is bent, which is precisely what a revolve audit needs.
     * ==================================================================== */
    {
        /* One rigid motion, used by every equivariance check below: 37 degrees
         * about the normalised axis (1,2,3)/sqrt(14), then a translation.
         * Rodrigues, composed in plain double arithmetic on purpose — the
         * suite's ONLY rotation until now was {0,-1,0, 1,0,0, 0,0,1}, whose
         * entries are exactly 0 and +-1, so trsf_from_mat34's orthonormality
         * guard has never seen a matrix that is merely NEARLY orthonormal.
         * That is the whole population the app actually sends. */
        const double aL = sqrt(14.0);
        const double ux = 1.0 / aL, uy = 2.0 / aL, uz = 3.0 / aL;
        const double th = 37.0 * M_PI / 180.0;
        const double ct = cos(th), st = sin(th), vt = 1.0 - ct;
        double R[12];
        R[0] = ct + ux*ux*vt;      R[1] = ux*uy*vt - uz*st;  R[2]  = ux*uz*vt + uy*st;
        R[4] = uy*ux*vt + uz*st;   R[5] = ct + uy*uy*vt;     R[6]  = uy*uz*vt - ux*st;
        R[8] = uz*ux*vt - uy*st;   R[9] = uz*uy*vt + ux*st;  R[10] = ct + uz*uz*vt;
        R[3] = 11.0; R[7] = -7.0; R[11] = 3.0;

        /* ---- [40a] P5 — occt_transform ACCEPTS a real rotation ---------- */
        {
            /* The guard is an ABSOLUTE tol of 1e-9 on the column dot products
             * and on det-1. Measure the residual here rather than assuming it:
             * if a hand-composed Rodrigues matrix already eats a decade of
             * that budget, a longer composition chain in Dart would trip it,
             * and the guard would be a latent refusal of legal input. */
            double worst = 0.0;
            int i, j;
            double det;
            for (i = 0; i < 3; ++i) {
                for (j = i; j < 3; ++j) {
                    const double d = R[0+i]*R[0+j] + R[4+i]*R[4+j] + R[8+i]*R[8+j];
                    const double e = fabs(d - (i == j ? 1.0 : 0.0));
                    if (e > worst) worst = e;
                }
            }
            det = R[0]*(R[5]*R[10] - R[6]*R[9])
                - R[1]*(R[4]*R[10] - R[6]*R[8])
                + R[2]*(R[4]*R[9]  - R[5]*R[8]);
            printf("[40a] Rodrigues residual: orthonormality %.3e, |det-1| "
                   "%.3e (guard is 1e-9)\n", worst, fabs(det - 1.0));
            check(worst < 1e-12 && fabs(det - 1.0) < 1e-12,
                  "[40a] a hand-composed rotation is not orthonormal to 1e-12 "
                  "— the 1e-9 guard has less headroom than it looks");

            occt_shape *b = occt_make_box(10, 20, 30);
            occt_shape *rb = b ? occt_transform(b, R) : NULL;
            if (check(rb != NULL,
                      "[40a] occt_transform REFUSED a genuine rotation")) {
                check(near_rel(occt_shape_volume(rb), 6000.0, 1e-12),
                      "[40a] a rotation changed the volume");
                check(occt_shape_valid(rb), "[40a] rotated box invalid");
                /* Round trip: R inverse is R transposed, translation undone. */
                double Ri[12];
                Ri[0]=R[0]; Ri[1]=R[4]; Ri[2]=R[8];
                Ri[4]=R[1]; Ri[5]=R[5]; Ri[6]=R[9];
                Ri[8]=R[2]; Ri[9]=R[6]; Ri[10]=R[10];
                Ri[3]  = -(Ri[0]*R[3] + Ri[1]*R[7] + Ri[2]*R[11]);
                Ri[7]  = -(Ri[4]*R[3] + Ri[5]*R[7] + Ri[6]*R[11]);
                Ri[11] = -(Ri[8]*R[3] + Ri[9]*R[7] + Ri[10]*R[11]);
                occt_shape *back = occt_transform(rb, Ri);
                if (check(back != NULL, "[40a] inverse transform failed")) {
                    double bb[6];
                    if (occt_bbox(back, bb)) {
                        /* 1e-6 absolute, NOT 1e-9: occt_bbox is
                         * BRepBndLib::Add, which inflates the box by the
                         * shape's own tolerance. Every box this file measures
                         * comes back about 1e-7 too big in each direction, and
                         * the existing fixtures only hide it because they
                         * compare RELATIVELY against values of order 10. At
                         * 1e-9 absolute the round trip "fails" by exactly that
                         * gap, which is OCCT reporting a bound, not a
                         * transform losing precision — the residual measured
                         * one line above is 4e-17. */
                        printf("[40a] round trip bbox [%.9f %.9f %.9f]-"
                               "[%.9f %.9f %.9f] (occt_bbox carries the shape "
                               "tolerance, ~1e-7, as a gap)\n",
                               bb[0], bb[1], bb[2], bb[3], bb[4], bb[5]);
                        check(fabs(bb[0]) < 1e-6 && fabs(bb[1]) < 1e-6 &&
                              fabs(bb[2]) < 1e-6 &&
                              fabs(bb[3] - 10.0) < 1e-6 &&
                              fabs(bb[4] - 20.0) < 1e-6 &&
                              fabs(bb[5] - 30.0) < 1e-6,
                              "[40a] R-inverse(R(box)) is not the box");
                    }
                }
                occt_free_shape(back);
            }
            occt_free_shape(rb);
            occt_free_shape(b);
        }

        /* ---- [40b] P3 — REVOLVE about an oblique, off-origin axis ------- */
        {
            /* [20]'s rectangle, x in [5,10], y in [0,3]: A = 15, centroid
             * (7.5, 1.5). Every one of [20]'s five calls passes the axis
             * through (0,0) along (0,1). Bend it: through (-4,1) along
             * (3,4)/5. Signed side of every vertex is negative (-7.8, -11.8,
             * -10.0, -6.0) so the profile does not straddle the axis.
             *
             * Pappus: d = |dhat x (c - p)| = |0.6*0.5 - 0.8*11.5| = 8.9,
             * V = 2*pi*8.9*15. */
            const double P[] = {
                5.0, 0.0, 0.0,  10.0, 0.0, 0.0,  10.0, 3.0, 0.0,  5.0, 3.0, 0.0,
            };
            const int lc[] = {4};
            const double want = 2.0 * M_PI * 8.9 * 15.0;
            occt_shape *s = occt_revolve_profile(P, lc, 1, -4.0, 1.0,
                                                 0.6, 0.8, 360.0);
            if (check(s != NULL,
                      "[40b] revolve about an oblique axis returned NULL")) {
                const double v = occt_shape_volume(s);
                printf("[40b] oblique-axis revolve %.6f (Pappus %.6f)\n",
                       v, want);
                check(near_rel(v, want, 1e-6),
                      "[40b] oblique revolve misses Pappus");
                check(occt_shape_valid(s), "[40b] oblique revolve invalid");
                occt_free_shape(s);
            }
            /* Same axis line, direction REVERSED. A full turn about a line is
             * the same solid whichever way the line points; if MakeRevol's
             * orientation followed the axis sense, one of the two would come
             * back inside out and nothing in this shim would notice — the
             * mirror path measures its volume and repairs it, the revolve path
             * does not. */
            occt_shape *r2 = occt_revolve_profile(P, lc, 1, -4.0, 1.0,
                                                  -0.6, -0.8, 360.0);
            if (check(r2 != NULL, "[40b] reversed-axis revolve returned NULL")) {
                const double v = occt_shape_volume(r2);
                printf("[40b] reversed-axis revolve %.6f (want %.6f)\n",
                       v, want);
                check(near_rel(v, want, 1e-6),
                      "[40b] reversing the axis direction changed the solid");
                check(occt_shape_valid(r2),
                      "[40b] reversed-axis revolve invalid");
                occt_free_shape(r2);
            }
            /* A PARTIAL turn about an oblique axis: still exactly the
             * fraction, because a revolve of angle a is a*A*r/(2*pi) ... i.e.
             * Pappus scaled. 90 degrees is a quarter. */
            occt_shape *q = occt_revolve_profile(P, lc, 1, -4.0, 1.0,
                                                 0.6, 0.8, 90.0);
            if (check(q != NULL, "[40b] partial oblique revolve NULL")) {
                check(near_rel(occt_shape_volume(q), want / 4.0, 1e-6),
                      "[40b] a quarter turn is not a quarter of the material");
                occt_free_shape(q);
            }
        }

        /* ---- [40c] P4 — a HOLE revolved about the SAME oblique axis ----- */
        {
            /* S14 item 2 was "a hole placed against a different frame from its
             * body". The revolve is the shim's other hole-cutting op, so it is
             * where the same defect would hide. Pappus applied twice:
             * outer x in [5,15], y in [0,6]  -> A=60, centroid (10,3)
             * hole  x in [8,12], y in [2,4]  -> A=8,  centroid (10,3)
             * about the SAME oblique axis through (-4,1) along (3,4)/5.
             * d_outer: |0.6*(3-1) - 0.8*(10+4)| = |1.2 - 11.2| = 10.0
             * d_hole : identical, 10.0 (same centroid)
             * V = 2*pi*10*(60 - 8) = 2*pi*520.
             * The two centroids coincide deliberately: if the hole were
             * revolved about a DIFFERENT axis its Pappus radius would change
             * and the volume would miss, which is the whole point. */
            const double P[] = {
                5.0, 0.0, 0.0,  15.0, 0.0, 0.0,  15.0, 6.0, 0.0,  5.0, 6.0, 0.0,
                8.0, 2.0, 0.0,  12.0, 2.0, 0.0,  12.0, 4.0, 0.0,  8.0, 4.0, 0.0,
            };
            const int lc[] = {4, 4};
            const double want = 2.0 * M_PI * 10.0 * (60.0 - 8.0);
            occt_shape *s = occt_revolve_profile(P, lc, 2, -4.0, 1.0,
                                                 0.6, 0.8, 360.0);
            if (check(s != NULL, "[40c] holed oblique revolve returned NULL")) {
                const double v = occt_shape_volume(s);
                printf("[40c] holed oblique revolve %.6f (Pappus %.6f)\n",
                       v, want);
                check(near_rel(v, want, 1e-6),
                      "[40c] the hole is not on the body's own axis");
                check(occt_shape_valid(s), "[40c] holed oblique revolve invalid");
                occt_free_shape(s);
            }
        }

        /* ---- [40d] R1 — the COIL's `clockwise` flag (S17: FIXED) -------- */
        {
            /* [32]'s fixture verbatim, which is the ONLY coil fixture in the
             * suite and passes clockwise = 0 in all four of its calls. The
             * flag is a checkbox in the app (app_state.dart:7277) and no test
             * had ever set it, which is how it stayed wrong for nine months.
             *
             * S16 recorded the defect here and pinned it; S17 (shim v28)
             * repaired it and this scenario now asserts the GROUND TRUTH.
             *
             * The helix is a straight line in the cylinder's (u,v) space.
             * ElSLib::CylinderD0 fixes what (u,v) mean —
             *     P(u,v) = Loc + R cos u . XDir + R sin u . YDir + v . ZDir
             * — and gp_Ax3(P,N,Vx) makes YDir = N x XDir, so the frame is
             * right-handed: u turns counterclockwise about the axis and v
             * advances along it. (du>0, dv>0) is right-handed; the LEFT-handed
             * helix is (du<0, dv>0). The flag used to negate BOTH components,
             * which is antiparallel to (1, slope) — the same line in (u,v),
             * the same point set, the SAME right-handed helix run backwards
             * and hanging below the profile.
             *
             * Volume can see none of this: the helix length, and so the
             * material, is identical for all four sign pairs. Two things can.
             *
             * 1. THE RISE. The fixed clockwise coil is the exact mirror image
             *    of the counterclockwise one through the plane y = 0 (u -> -u
             *    negates y and fixes z, and the starting section lies in the
             *    XZ plane, which that mirror fixes). A mirror is an isometry,
             *    so the two coils must share their z extent to the last bit —
             *    not merely "land near 0 and 50".
             *
             * 2. THE HANDEDNESS, which needs a ray. Cast +Z up the line
             *    x = 0, y = 20, which passes through the helix point at
             *    azimuth u = pi/2. Material crosses wherever u = pi/2 mod 2pi:
             *      ccw, u in [0, 10pi]:   u = pi/2 + 2pi k  -> z = 2.5 + 10k
             *      cw,  u in [-10pi, 0]:  u = pi/2 - 2pi m  -> z = 7.5 + 10m'
             *    Five 2 mm passes each, interleaved at HALF A TURN — 5 mm —
             *    which is what "opposite handedness, same rise" means and what
             *    no bounding box and no volume can report. Before the fix the
             *    clockwise crossings were at z = -7.5, -17.5, ... */
            const double P[] = {19, -1, 0,  21, -1, 0,  21, 1, 0,  19, 1, 0};
            const int lc[] = {4};
            const double m[12] = {1,0,0,0, 0,0,-1,0, 0,1,0,0};
            const double turn = sqrt(pow(2.0 * M_PI * 20.0, 2) + 100.0);
            const double want = 4.0 * 5.0 * turn;
            occt_shape *ccw = occt_coil_profile(P, lc, 1, m, 0,0,0, 0,0,1,
                                                5.0, 50.0, 0.0, 0, 0, 0);
            occt_shape *cw  = occt_coil_profile(P, lc, 1, m, 0,0,0, 0,0,1,
                                                5.0, 50.0, 0.0, 1, 0, 0);
            if (check(ccw != NULL && cw != NULL,
                      "[40d] a coil returned NULL")) {
                double b0[6], b1[6];
                const double v0 = occt_shape_volume(ccw);
                const double v1 = occt_shape_volume(cw);
                occt_bbox(ccw, b0);
                occt_bbox(cw, b1);
                printf("[40d] ccw vol %.4f z[%.4f,%.4f] | cw vol %.4f "
                       "z[%.4f,%.4f] (rise asked for: 50)\n",
                       v0, b0[2], b0[5], v1, b1[2], b1[5]);
                check(near_rel(v0, want, 2e-2), "[40d] ccw coil volume far off");
                check(near_rel(v1, want, 2e-2), "[40d] cw coil volume far off");
                check(near_rel(v1, v0, 1e-9),
                      "[40d] handedness must not change how much material "
                      "there is");
                check(occt_shape_valid(cw), "[40d] clockwise coil invalid");

                /* GROUND TRUTH 1 — THE RISE. The clockwise coil is the mirror
                 * image of the counterclockwise one, so its z extent is the
                 * SAME, both ends, to the last bit. Before the fix these were
                 * negated: z[-50.9969, 0.9968] against z[-0.9968, 50.9969]. */
                check(near_rel(b1[2], b0[2], 1e-9) &&
                      near_rel(b1[5], b0[5], 1e-9),
                      "[40d] the clockwise coil does not RISE like the "
                      "counterclockwise one — if its z range is negated, "
                      "`clockwise` is negating the climb as well as the "
                      "winding (S16 P1, repaired in v28)");
                check(b1[5] > 45.0 && b1[2] < 5.0,
                      "[40d] the clockwise coil must span roughly z[0,50]");

                /* GROUND TRUTH 2 — THE HANDEDNESS, by ray. See the header
                 * comment: the two coils cross the azimuth-90 line half a turn
                 * apart. This is the check that says the winding reversed, and
                 * it is the only instrument in the suite that can. */
                {
                    double h0[16], h1[16];
                    const int n0 = occt_ray_hits(ccw, 0.0, 20.0, -10.0,
                                                 0.0, 0.0, 1.0, h0, 16);
                    const int n1 = occt_ray_hits(cw, 0.0, 20.0, -10.0,
                                                 0.0, 0.0, 1.0, h1, 16);
                    printf("[40d] azimuth-90 ray: ccw %d hits, cw %d hits\n",
                           n0, n1);
                    if (check(n0 == 10 && n1 == 10,
                              "[40d] the azimuth-90 ray must cross five 2 mm "
                              "passes of each coil")) {
                        int k;
                        int ok = 1;
                        for (k = 0; k < 5; ++k) {
                            /* Midpoint of each entry/exit pair. The ray runs
                             * through the section's centre and the section is
                             * centrally symmetric, so the midpoint IS the
                             * helix crossing; the 5e-2 is for the tube's
                             * curvature across a 2 mm chord and nothing
                             * else. */
                            const double m0 =
                                0.5 * (h0[2 * k] + h0[2 * k + 1]) - 10.0;
                            const double m1 =
                                0.5 * (h1[2 * k] + h1[2 * k + 1]) - 10.0;
                            printf("[40d]   pass %d: ccw z %.4f (want %.1f) | "
                                   "cw z %.4f (want %.1f)\n",
                                   k, m0, 2.5 + 10.0 * k, m1,
                                   7.5 + 10.0 * k);
                            if (fabs(m0 - (2.5 + 10.0 * k)) > 5e-2) ok = 0;
                            if (fabs(m1 - (7.5 + 10.0 * k)) > 5e-2) ok = 0;
                        }
                        check(ok,
                              "[40d] the two coils do not interleave half a "
                              "turn apart — the clockwise coil has the same "
                              "handedness as the counterclockwise one");
                    }
                }
            }
            occt_free_shape(ccw);
            occt_free_shape(cw);
        }

        /* ---- [40e] P2 — the COIL about an oblique axis (equivariance) --- */
        {
            /* Rotate the axis AND the profile frame by the same R. The coil is
             * then the rigid image of the +Z coil, so its volume must be
             * identical to the last bit. If the helix frame were built against
             * a baked-in +Z the two would part company. */
            const double P[] = {19, -1, 0,  21, -1, 0,  21, 1, 0,  19, 1, 0};
            const int lc[] = {4};
            const double m[12] = {1,0,0,0, 0,0,-1,0, 0,1,0,0};
            /* R * m, as 3x4 row-major composition. */
            double rm[12];
            int r, c;
            for (r = 0; r < 3; ++r) {
                for (c = 0; c < 3; ++c)
                    rm[4*r+c] = R[4*r+0]*m[c] + R[4*r+1]*m[4+c]
                              + R[4*r+2]*m[8+c];
                rm[4*r+3] = R[4*r+0]*m[3] + R[4*r+1]*m[7] + R[4*r+2]*m[11]
                          + R[4*r+3];
            }
            /* R applied to the axis point (0,0,0) and direction (0,0,1). */
            const double apx = R[3], apy = R[7], apz = R[11];
            const double adx = R[2], ady = R[6], adz = R[10];
            occt_shape *base = occt_coil_profile(P, lc, 1, m, 0,0,0, 0,0,1,
                                                 5.0, 50.0, 0.0, 0, 0, 0);
            occt_shape *rot  = occt_coil_profile(P, lc, 1, rm,
                                                 apx, apy, apz,
                                                 adx, ady, adz,
                                                 5.0, 50.0, 0.0, 0, 0, 0);
            if (check(base != NULL && rot != NULL,
                      "[40e] the coil refused an oblique axis")) {
                const double v0 = occt_shape_volume(base);
                const double v1 = occt_shape_volume(rot);
                printf("[40e] coil equivariance: +Z %.9f, oblique %.9f, "
                       "rel diff %.3e\n", v0, v1, fabs(v1 - v0) / v0);
                check(near_rel(v1, v0, 1e-9),
                      "[40e] the coil is not equivariant — an axis is baked in");
                check(occt_shape_valid(rot), "[40e] oblique coil invalid");
            }
            occt_free_shape(base);
            occt_free_shape(rot);
        }

        /* ---- [40f] P6 — MIRROR about an oblique plane ------------------- */
        {
            /* [13b] varies the plane's POINT and never its NORMAL: (1,0,0) in
             * all four calls. Bend the normal to (1,1,0)/sqrt(2).
             *
             * The fuse is the real test, not the volume. A reflection turns a
             * solid inside out and OCCT's booleans read orientation, so a
             * silently un-repaired mirror passes a volume check and then CUTS
             * where it should ADD. That is what the repair exists for. */
            occt_shape *b = occt_make_box(10, 20, 30);
            const double pl[6] = {0, 0, 0, 0.70710678118654752440, 0.70710678118654752440, 0};
            occt_shape *mir = b ? occt_mirror(b, pl) : NULL;
            if (check(mir != NULL, "[40f] oblique mirror returned NULL")) {
                check(near_rel(occt_shape_volume(mir), 6000.0, 1e-9),
                      "[40f] an oblique mirror changed the volume");
                check(occt_shape_valid(mir), "[40f] oblique mirror invalid");
                occt_shape *both = occt_fuse(b, mir);
                if (check(both != NULL,
                          "[40f] fuse(original, oblique mirror) failed")) {
                    const double v = occt_shape_volume(both);
                    printf("[40f] oblique mirror fuse volume %.6f (two "
                           "DISJOINT halves of 6000 — see the overlapping "
                           "pair below for the test with teeth)\n", v);
                    check(v > 6000.0 + 1e-6,
                          "[40f] the mirrored half added nothing — the "
                          "reflection is probably inside out");
                    occt_free_shape(both);
                }
                occt_free_shape(mir);
            }
            /* The fuse above is weaker than it looks: reflecting [0,10]x
             * [0,20] about the plane through the ORIGIN with normal
             * (1,1,0)/sqrt(2) sends (x,y) to (-y,-x), so the image is
             * DISJOINT from the original and touches it only at a corner —
             * 6000 + 6000 with nothing to subtract. [13b] has the same
             * weakness. Move the plane so the halves genuinely OVERLAP and the
             * booleans acquire teeth.
             *
             * Plane through (7,0,0), same normal: (x,y) -> (7-y, 7-x), so the
             * image is the box x in [-13,7], y in [-3,7], z in [0,30]. The
             * overlap is 7 x 7 x 30 = 1470, hence
             *   fuse = 6000 + 6000 - 1470 = 10530
             *   cut  = 6000 - 1470         =  4530
             * and the CUT is the sharp one: an inside-out tool removes the
             * complement of what it should, which no volume near 4530 can
             * survive. */
            {
                const double po[6] = {7, 0, 0,
                                      0.70710678118654752440,
                                      0.70710678118654752440, 0};
                occt_shape *mo = b ? occt_mirror(b, po) : NULL;
                if (check(mo != NULL, "[40f] overlapping oblique mirror NULL")) {
                    occt_shape *fu = occt_fuse(b, mo);
                    occt_shape *cu = occt_cut(b, mo);
                    if (check(fu != NULL && cu != NULL,
                              "[40f] boolean against an oblique mirror failed")) {
                        printf("[40f] overlapping oblique mirror: fuse %.6f "
                               "(want 10530), cut %.6f (want 4530)\n",
                               occt_shape_volume(fu), occt_shape_volume(cu));
                        check(near_rel(occt_shape_volume(fu), 10530.0, 1e-9),
                              "[40f] the fused halves are not 12000 minus the "
                              "1470 they share");
                        check(near_rel(occt_shape_volume(cu), 4530.0, 1e-9),
                              "[40f] cutting with the mirrored half removed the "
                              "wrong material — the reflection is inside out");
                        check(occt_shape_valid(fu) && occt_shape_valid(cu),
                              "[40f] a boolean against the oblique mirror is "
                              "invalid");
                    }
                    occt_free_shape(fu);
                    occt_free_shape(cu);
                    occt_free_shape(mo);
                }
            }
            /* The normal is documented as normalised here. Nothing has ever
             * passed one that was not already unit. */
            const double pl3[6] = {0, 0, 0, 3.0, 3.0, 0};
            occt_shape *m3 = b ? occt_mirror(b, pl3) : NULL;
            if (check(m3 != NULL, "[40f] un-normalised normal was refused")) {
                double b1[6], b2[6];
                occt_shape *m1 = occt_mirror(b, pl);
                if (m1 != NULL && occt_bbox(m1, b1) && occt_bbox(m3, b2)) {
                    int k, same = 1;
                    for (k = 0; k < 6; ++k)
                        if (!near_rel(b1[k], b2[k], 1e-9) &&
                            fabs(b1[k] - b2[k]) > 1e-9)
                            same = 0;
                    check(same,
                          "[40f] scaling the plane normal changed the mirror");
                }
                occt_free_shape(m1);
                occt_free_shape(m3);
            }
            occt_free_shape(b);
        }

        /* ---- [40g] P7 — a BOOLEAN with a ROTATED operand ---------------- */
        {
            /* Every boolean in this suite separates its operands by an
             * axis-aligned TRANSLATION. Not one has ever had a rotated
             * operand. These are thin wrappers over BRepAlgoAPI_* and compose
             * no frame of their own, so this is expected to be the honest
             * "checked and it is fine" entry — which is worth having, because
             * the next person should not have to re-check it.
             *
             * Equivariance: cut a rotated bar out of a cube, then do the same
             * with everything rotated bodily by R. The volumes must agree. */
            occt_shape *cube = occt_make_box(20, 20, 20);
            occt_shape *bar0 = occt_make_box(6, 6, 60);
            /* 30 deg about Z, then place it leaning through the cube. */
            const double c30 = cos(30.0 * M_PI / 180.0);
            const double s30 = sin(30.0 * M_PI / 180.0);
            const double T[12] = { c30, -s30, 0, 7.0,
                                   s30,  c30, 0, 6.0,
                                   0,    0,   1, -20.0 };
            occt_shape *bar = bar0 ? occt_transform(bar0, T) : NULL;
            occt_shape *cut = (cube && bar) ? occt_cut(cube, bar) : NULL;
            if (check(cut != NULL, "[40g] cut with a rotated tool returned NULL")) {
                const double v0 = occt_shape_volume(cut);
                /* the same operation, everything premultiplied by R */
                double RT[12], Rc[12];
                int r, c;
                for (r = 0; r < 3; ++r) {
                    for (c = 0; c < 3; ++c)
                        RT[4*r+c] = R[4*r+0]*T[c] + R[4*r+1]*T[4+c]
                                  + R[4*r+2]*T[8+c];
                    RT[4*r+3] = R[4*r+0]*T[3] + R[4*r+1]*T[7] + R[4*r+2]*T[11]
                              + R[4*r+3];
                }
                memcpy(Rc, R, sizeof(Rc));
                occt_shape *cubeR = occt_transform(cube, Rc);
                occt_shape *barR = bar0 ? occt_transform(bar0, RT) : NULL;
                occt_shape *cutR = (cubeR && barR) ? occt_cut(cubeR, barR) : NULL;
                if (check(cutR != NULL, "[40g] the rotated-frame cut failed")) {
                    const double v1 = occt_shape_volume(cutR);
                    printf("[40g] boolean equivariance: %.9f vs %.9f, rel diff "
                           "%.3e\n", v0, v1, fabs(v1 - v0) / v0);
                    check(near_rel(v1, v0, 1e-6),
                          "[40g] the boolean is not equivariant under a rigid "
                          "motion");
                    check(occt_shape_valid(cutR), "[40g] rotated-frame cut invalid");
                }
                check(occt_shape_valid(cut), "[40g] rotated-tool cut invalid");
                occt_free_shape(cutR);
                occt_free_shape(barR);
                occt_free_shape(cubeR);
            }
            occt_free_shape(cut);
            occt_free_shape(bar);
            occt_free_shape(bar0);
            occt_free_shape(cube);
        }

        /* ---- [40h] P8 — LOFT with ROTATED section placements ------------ */
        {
            /* [31]'s three calls pass IDENTITY rotation in every section
             * matrix; only the translation moves. In the app a section matrix
             * is frame.mat34(0), which is a real rotation the moment two
             * sections sit on different work planes.
             *
             * Equivariance first (exact), then a genuinely tilted section
             * (no closed form, so a bracket rather than a number). */
            const double S[] = {
                0, 0, 0,  10, 0, 0,  10, 10, 0,  0, 10, 0,
                0, 0, 0,  10, 0, 0,  10, 10, 0,  0, 10, 0,
            };
            const int lc[] = {4, 4};
            const double mats[24] = {
                1,0,0,0, 0,1,0,0, 0,0,1,0,
                1,0,0,0, 0,1,0,0, 0,0,1,25,
            };
            double rmats[24];
            int s, r, c;
            for (s = 0; s < 2; ++s) {
                const double *m = mats + 12 * s;
                double *o = rmats + 12 * s;
                for (r = 0; r < 3; ++r) {
                    for (c = 0; c < 3; ++c)
                        o[4*r+c] = R[4*r+0]*m[c] + R[4*r+1]*m[4+c]
                                 + R[4*r+2]*m[8+c];
                    o[4*r+3] = R[4*r+0]*m[3] + R[4*r+1]*m[7] + R[4*r+2]*m[11]
                             + R[4*r+3];
                }
            }
            occt_shape *lo = occt_loft_sections(S, lc, rmats, 2, 1, 1, 0);
            if (check(lo != NULL,
                      "[40h] loft with rotated section matrices returned NULL")) {
                const double v = occt_shape_volume(lo);
                printf("[40h] rotated-frame loft %.9f (want 2500)\n", v);
                check(near_rel(v, 2500.0, 1e-9),
                      "[40h] the loft is not equivariant — a section frame is "
                      "composed against a baked-in axis");
                check(occt_shape_valid(lo), "[40h] rotated-frame loft invalid");
                occt_free_shape(lo);
            }
            /* A section TILTED relative to its neighbour: 20 degrees about X
             * on the top section only. No closed form, so the claim is a
             * bracket — it must build, be valid, and hold more material than
             * the prism whose height is the closest approach of the two
             * sections. Registered as a weak claim on purpose (S16 P8). */
            {
                const double c20 = cos(20.0 * M_PI / 180.0);
                const double s20 = sin(20.0 * M_PI / 180.0);
                double tm[24];
                memcpy(tm, mats, sizeof(tm));
                tm[12+0]=1; tm[12+1]=0;    tm[12+2]=0;     tm[12+3]=0;
                tm[16+0]=0; tm[16+1]=c20;  tm[16+2]=-s20;  tm[16+3]=0;
                tm[20+0]=0; tm[20+1]=s20;  tm[20+2]=c20;   tm[20+3]=25;
                occt_shape *tl = occt_loft_sections(S, lc, tm, 2, 1, 1, 0);
                if (check(tl != NULL, "[40h] tilted-section loft returned NULL")) {
                    const double v = occt_shape_volume(tl);
                    /* closest approach of the tilted top section to z=0 is
                     * 25 - 10*sin(20deg) = 21.580, so V > 100 * 21.580 */
                    const double lo_b = 100.0 * (25.0 - 10.0 * s20);
                    const double hi_b = 100.0 * (25.0 + 10.0 * s20);
                    printf("[40h] tilted-section loft %.6f (bracket %.6f .. "
                           "%.6f)\n", v, lo_b, hi_b);
                    check(v > lo_b && v < hi_b,
                          "[40h] the tilted loft is outside its bracket");
                    check(occt_shape_valid(tl), "[40h] tilted loft invalid");
                    occt_free_shape(tl);
                }
            }
        }

        /* ---- [40i] P9 — MOVE FACES with an OBLIQUE delta ---------------- */
        {
            /* [34] moves the top face by (0,0,5): exactly along its own
             * outward normal, which is the ONE case the header claims to be
             * exact. Bend the delta to (5,0,5).
             *
             * The implementation sweeps the face along the WHOLE delta and
             * fuses the prism. Perpendicular, that prism is the slab between
             * the old face and the new one. Oblique, it LEANS: the union
             * carries an unsupported overhang on one side and a re-entrant
             * notch on the other, instead of the neighbouring walls following
             * the face.
             *
             * Volume cannot see this. A leaning prism has volume
             * A*|delta.n| = 400*5 = 2000, exactly the perpendicular answer,
             * and shearing the top face is Cavalieri-neutral, so BOTH
             * readings give 10000. BRepCheck_Analyzer cannot see it either:
             * the union is a perfectly valid solid. The discriminator is a
             * RAY: up the line x=2, y=10,
             *   walls-follow  -> the top at x=2 is z = 25*(2/5) = 10
             *   leaning prism -> material to z = 20 + 5*(2/5) = 22 */
            occt_shape *box = occt_make_box(20, 20, 20);
            int top = -1;
            if (box != NULL) {
                occt_mesh *m = occt_mesh_create(box, 0.5, 0.5);
                if (m != NULL) {
                    const int nf = occt_mesh_face_count(m);
                    const int fc = (nf > 0 ? nf : 1);
                    int *fids = (int *)malloc(sizeof(int) * fc);
                    double *fi = (double *)malloc(sizeof(double) * 15 * fc);
                    if (fids && fi && occt_mesh_face_ids(m, fids) &&
                        occt_mesh_face_infos(m, fi)) {
                        int i;
                        for (i = 0; i < nf; ++i) {
                            /* planar, +Z outward normal, sitting at z = 20 —
                             * the same three tests [34] uses, and the same
                             * 15-double stride (the record is 15 wide; the
                             * header's list ends at [14]). */
                            if ((int)(fi[15 * i] + 0.5) == 0 &&
                                fi[15 * i + 6] > 0.9 &&
                                fi[15 * i + 3] > 19.5) {
                                top = fids[i];
                                break;
                            }
                        }
                    }
                    free(fids);
                    free(fi);
                    occt_free_mesh(m);
                }
            }
            if (check(top > 0, "[40i] could not find the top face")) {
                const int ids[1] = {top};
                occt_shape *ob = occt_move_faces(box, ids, 1, 5.0, 0.0, 5.0);
                if (check(ob != NULL,
                          "[40i] an oblique move was neither refused nor built")) {
                    double hits[8];
                    const double v = occt_shape_volume(ob);
                    const int n = occt_ray_hits(ob, 2.0, 10.0, -10.0,
                                                0.0, 0.0, 1.0, hits, 8);
                    printf("[40i] oblique move volume %.6f (perpendicular move "
                           "gives 10000 too), valid=%d, ray x=2 hits=%d",
                           v, occt_shape_valid(ob), n);
                    if (n > 0) {
                        int k;
                        for (k = 0; k < n; ++k)
                            printf(" %.4f", hits[k] - 10.0);
                    }
                    printf(" (walls-follow says the top is at 10, a leaning "
                           "prism says 22)\n");
                    check(near_rel(v, 10000.0, 1e-6),
                          "[40i] volume is not the swept-slab answer");
                    check(occt_shape_valid(ob),
                          "[40i] the oblique move is invalid");
                    /* The finding, pinned. If this check ever starts failing
                     * because the exit moved to ~10, the op was fixed and this
                     * scenario should be rewritten to assert the fix. */
                    if (check(n >= 2, "[40i] the ray missed the moved body")) {
                        const double exit_z = hits[n - 1] - 10.0;
                        check(fabs(exit_z - 22.0) < 1e-6,
                              "[40i] the oblique move no longer leans — if the "
                              "exit is now ~10 the op was FIXED and this "
                              "scenario must be rewritten");
                    }
                    occt_free_shape(ob);
                }
            }
            occt_free_shape(box);
        }

        /* ---- [40j] P10 — the chamfer's `angle >= 90` guard -------------- */
        {
            /* THE TRAP THIS SCENARIO WALKED INTO FIRST, recorded because the
             * next person will walk into it too: occt_shape_edge_info's
             * field [10] is acos(n1 . n2), the angle between the two OUTWARD
             * NORMALS, not the interior dihedral. They coincide at a cube
             * edge — 90 either way — which is why every fixture above reads
             * naturally and why the distinction has never mattered. Away from
             * 90 they are supplements: interior theta = 180 - info[10].
             *
             * The guard is
             *     modes[i] == 2 && angle_deg[i] >= 90.0   ->  refused
             * and the angle is measured FROM THE REFERENCE FACE. In the
             * cross-section triangle (edge apex O, tangent point A on the
             * reference face, tangent point B on the other), the angles sum
             * to 180, so the admissible range is
             *     alpha < 180 - theta
             * which is alpha < 90 ONLY when theta = 90. The guard is a
             * hardcoded 90-degree edge.
             *
             * An EQUILATERAL triangular prism has theta = 60 at every vertical
             * edge, so alpha may legally reach 120. Ask for 100. */
            const double P[] = {0.0, 0.0, 0.0,  30.0, 0.0, 0.0,
                                15.0, 25.9807621135331594, 0.0};
            const int lc[] = {3};
            /* _arcs, not the plain form: occt_extrude_profile takes TWO
             * doubles per vertex and occt_extrude_profile_arcs takes THREE
             * (x, y, bulge). Feeding the triples to the plain form makes it
             * read every third number as the next x, which came back as
             * "outer loop is degenerate" rather than as a wrong solid — the
             * one good thing about that mistake. */
            occt_shape *wedge = occt_extrude_profile_arcs(P, lc, 1, 20.0, 0.0);
            int e60 = -1;
            if (check(wedge != NULL, "[40j] wedge prism returned NULL")) {
                const int ne = occt_shape_edge_count(wedge);
                int i;
                for (i = 1; i <= ne && e60 < 0; ++i) {
                    double info[12] = {0};
                    if (!occt_shape_edge_info(wedge, i, info)) continue;
                    if (info[0] != 1.0) continue;
                    if (fabs(fabs(info[6]) - 1.0) > 1e-9) continue;
                    if (fabs(info[10] - 120.0) > 1e-6) continue; /* theta = 60 */
                    e60 = i;
                }
                printf("[40j] wedge volume %.6f (want %.6f), 60-degree edge "
                       "index %d\n", occt_shape_volume(wedge),
                       25.9807621135331594 * 30.0 / 2.0 * 20.0, e60);
                check(near_rel(occt_shape_volume(wedge),
                               25.9807621135331594 * 30.0 / 2.0 * 20.0, 1e-9),
                      "[40j] the wedge prism is not area x height");
                check(e60 > 0,
                      "[40j] an equilateral prism must have a 60-degree "
                      "dihedral edge (info[10] = 120)");
            }
            if (e60 > 0) {
                const int ids[1] = {e60};
                const int m2[1] = {2};
                const int m1[1] = {1};
                const double d[1] = {2.0};
                /* alpha = 80: inside the guard AND geometrically legal here,
                 * so it is the control that says mode 2 works on this edge at
                 * all and the refusal below is the guard, not the geometry. */
                const double a80[1] = {80.0};
                const double a100[1] = {100.0};
                occt_shape *ok80 =
                    occt_chamfer_edges(wedge, ids, m2, d, NULL, a80, 1);
                occt_shape *ref100 =
                    occt_chamfer_edges(wedge, ids, m2, d, NULL, a100, 1);
                /* The SAME chamfer as alpha = 100, spelled as two distances.
                 * Sine rule in triangle OAB: OA = d1 opposite angle B,
                 * OB = d2 opposite angle A, so d2 = d1 sin(100) / sin(20). */
                const double d2v[1] = {2.0 * sin(100.0 * M_PI / 180.0) /
                                             sin(20.0 * M_PI / 180.0)};
                occt_shape *eq =
                    occt_chamfer_edges(wedge, ids, m1, d, d2v, NULL, 1);
                printf("[40j] theta=60 edge: mode2 alpha=80 -> %s | mode2 "
                       "alpha=100 -> %s | the SAME chamfer as mode1 "
                       "(d1=2, d2=%.6f) -> %s\n",
                       ok80 ? "built" : "refused",
                       ref100 ? "built" : "REFUSED",
                       d2v[0], eq ? "built" : "refused");
                check(ok80 != NULL,
                      "[40j] mode 2 must work on a 60-degree edge at all");
                check(ref100 == NULL,
                      "[40j] the >= 90 guard did not fire — if this starts "
                      "failing the guard was relaxed and this scenario should "
                      "assert the new range instead");
                if (check(eq != NULL,
                          "[40j] the two-distance spelling of the SAME chamfer "
                          "was also refused — then the guard is defensible and "
                          "P10 is falsified")) {
                    /* Removed cross-section is triangle OAB:
                     * 1/2 * d1 * d2 * sin(theta), times the 20 mm length. */
                    const double base = 25.9807621135331594 * 30.0 / 2.0 * 20.0;
                    const double cut = 0.5 * 2.0 * d2v[0] *
                                       sin(60.0 * M_PI / 180.0) * 20.0;
                    const double got = base - occt_shape_volume(eq);
                    printf("[40j] mode1 removed %.6f (analytic %.6f) — a "
                           "chamfer the mode2 spelling REFUSES\n", cut, got);
                    check(near_rel(got, cut, 1e-6),
                          "[40j] the two-distance chamfer is not the triangle "
                          "1/2 d1 d2 sin(theta)");
                    check(occt_shape_valid(eq), "[40j] that chamfer is invalid");
                }
                occt_free_shape(ok80);
                occt_free_shape(ref100);
                occt_free_shape(eq);
            }
            occt_free_shape(wedge);
        }

        /* ---- [40k] P11 — FILLET a 135-degree edge ----------------------- */
        {
            /* Every fillet fixture above is on a 20-cube's vertical edge:
             * dihedral exactly 90, tangent exactly +-Z, both faces
             * axis-aligned planes. Chamfer the cube first to make a
             * 135-degree edge, then round THAT.
             *
             * For an interior dihedral theta, a constant round of radius r
             * removes r^2 * (cot(theta/2) - (pi - theta)/2) per unit length.
             * At theta = 90 that is r^2 (1 - pi/4), which is exactly what [21]
             * asserts. At theta = 135 with r = 2 it is
             * 4 (cot 67.5 - pi/8) = 0.08605805 per mm, and the edge runs the
             * full 20 mm height with no run-out at either end, so the removal
             * is a genuine prism: 1.72116. Same 1e-6 as [21] — there is no
             * reason a 135-degree edge should be looser, and a slack
             * tolerance would make the prediction unfalsifiable. */
            occt_shape *box = occt_make_box(20, 20, 20);
            int vertical = -1;
            int i;
            const int ne = box ? occt_shape_edge_count(box) : 0;
            for (i = 1; i <= ne && vertical < 0; ++i) {
                double info[12] = {0};
                if (!occt_shape_edge_info(box, i, info)) continue;
                if (info[0] != 1.0) continue;
                if (fabs(fabs(info[6]) - 1.0) > 1e-9) continue;
                vertical = i;
            }
            occt_shape *ch = NULL;
            if (vertical > 0) {
                const int ids[1] = {vertical};
                const int modes[1] = {0};
                const double d1[1] = {4.0};
                ch = occt_chamfer_edges(box, ids, modes, d1, NULL, NULL, 1);
            }
            if (check(ch != NULL, "[40k] setup chamfer failed")) {
                const double chv = occt_shape_volume(ch);
                int e135 = -1;
                const int nc = occt_shape_edge_count(ch);
                int n135 = 0;
                for (i = 1; i <= nc; ++i) {
                    double info[12] = {0};
                    if (!occt_shape_edge_info(ch, i, info)) continue;
                    if (info[0] != 1.0) continue;
                    if (fabs(fabs(info[6]) - 1.0) > 1e-9) continue;
                    /* interior theta = 180 - info[10]; 135 <-> info[10] = 45 */
                    if (fabs(info[10] - 45.0) > 1e-6) continue;
                    if (e135 < 0) e135 = i;
                    ++n135;
                }
                printf("[40k] 135-degree edges on the chamfered cube: %d\n",
                       n135);
                check(n135 == 2,
                      "[40k] a 45-degree chamfer must leave two 135-degree "
                      "edges");
                if (e135 > 0) {
                    const int ids[1] = {e135};
                    const double r[1] = {2.0};
                    occt_shape *f = occt_fillet_edges(ch, ids, r, NULL, 1);
                    if (check(f != NULL,
                              "[40k] fillet REFUSED a 135-degree edge")) {
                        const double removed = chv - occt_shape_volume(f);
                        const double want =
                            4.0 * (1.0 / tan(67.5 * M_PI / 180.0) - M_PI / 8.0)
                            * 20.0;
                        printf("[40k] 135-degree fillet removed %.9f "
                               "(analytic %.9f)\n", removed, want);
                        check(near_rel(removed, want, 1e-6),
                              "[40k] a fillet on a non-90-degree edge does not "
                              "remove the analytic corner");
                        check(occt_shape_valid(f),
                              "[40k] 135-degree fillet invalid");
                        occt_free_shape(f);
                    }
                }
                occt_free_shape(ch);
            }

            /* ---- [40l] P12 — CHAMFER MODE 1, which nothing has ever called */
            if (vertical > 0) {
                /* modes[i] == 1 has NO fixture anywhere in this file and `d2`
                 * is NULL at every call site. */
                const int ids0[1] = {vertical};
                const int m1[1] = {1};
                const double dA[1] = {4.0}, dB[1] = {2.0};
                const double dC[1] = {2.0}, dD[1] = {4.0};
                occt_shape *c42 =
                    occt_chamfer_edges(box, ids0, m1, dA, dB, NULL, 1);
                occt_shape *c24 =
                    occt_chamfer_edges(box, ids0, m1, dC, dD, NULL, 1);
                if (check(c42 != NULL && c24 != NULL,
                          "[40l] two-distance chamfer (mode 1) failed — it has "
                          "never had a fixture")) {
                    check(near_rel(occt_shape_volume(c42), 7920.0, 1e-9),
                          "[40l] mode 1 does not remove d1*d2/2 * length");
                    check(near_rel(occt_shape_volume(c24), 7920.0, 1e-9),
                          "[40l] the swapped pair removes a different amount");
                    check(occt_shape_valid(c42) && occt_shape_valid(c24),
                          "[40l] a two-distance chamfer is invalid");
                    /* Neither the volume nor the RESULT's bbox can tell the two
                     * orderings apart — a chamfer cuts a corner off, so the
                     * solid still spans [0,20]^3 either way. The bbox of the
                     * CUT-AWAY WEDGE can, and it needs no knowledge of which
                     * face OCCT's ancestor map picked as the reference:
                     * swapping the distances TRANSPOSES two of its extents.
                     * A test that had to name the reference face would be
                     * pinning OCCT's map order, not the shim's behaviour. */
                    occt_shape *w42 = occt_cut(box, c42);
                    occt_shape *w24 = occt_cut(box, c24);
                    double b42[6], b24[6];
                    if (check(w42 && w24 && occt_bbox(w42, b42) &&
                              occt_bbox(w24, b24),
                              "[40l] could not isolate the wedges")) {
                        double e42[3], e24[3];
                        int k, differ = 0;
                        double sorted[3];
                        for (k = 0; k < 3; ++k) {
                            e42[k] = b42[3+k] - b42[k];
                            e24[k] = b24[3+k] - b24[k];
                            if (fabs(e42[k] - e24[k]) > 1e-6)
                                differ = 1;
                        }
                        for (k = 0; k < 3; ++k) sorted[k] = e42[k];
                        for (k = 0; k < 2; ++k) {
                            int j2;
                            for (j2 = k + 1; j2 < 3; ++j2)
                                if (sorted[j2] < sorted[k]) {
                                    const double t2 = sorted[k];
                                    sorted[k] = sorted[j2];
                                    sorted[j2] = t2;
                                }
                        }
                        printf("[40l] wedge extents 4/2 (%.4f %.4f %.4f) vs "
                               "2/4 (%.4f %.4f %.4f)\n",
                               e42[0], e42[1], e42[2],
                               e24[0], e24[1], e24[2]);
                        check(near_rel(sorted[0], 2.0, 1e-6) &&
                              near_rel(sorted[1], 4.0, 1e-6) &&
                              near_rel(sorted[2], 20.0, 1e-6),
                              "[40l] the wedge is not d1 x d2 x length");
                        check(differ,
                              "[40l] swapping d1 and d2 changed nothing — the "
                              "two distances are not landing on the two "
                              "different faces");
                    }
                    occt_free_shape(w42);
                    occt_free_shape(w24);
                }
                occt_free_shape(c42);
                occt_free_shape(c24);
            }
            occt_free_shape(box);
        }
    }

    if (g_failures == 0) {
        printf("OCCT SMOKE: PASS\n");
        return 0;
    }
    printf("OCCT SMOKE: FAIL (%d failing checks)\n", g_failures);
    return 1;
}
