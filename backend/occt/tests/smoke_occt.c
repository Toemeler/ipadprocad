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

    if (g_failures == 0) {
        printf("OCCT SMOKE: PASS\n");
        return 0;
    }
    printf("OCCT SMOKE: FAIL (%d failing checks)\n", g_failures);
    return 1;
}
