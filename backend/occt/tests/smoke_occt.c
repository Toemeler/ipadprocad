/*
 * iPadProCAD — OCCT shim smoke test. Pure C, no Flutter, no Dart: calls the
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

int main(void)
{
    const double PI = 3.14159265358979323846;
    printf("%s (shim ABI v%d)\n", occt_version(), occt_shim_version());
    if (!check(strstr(occt_version(), "iPadProCAD OCCT shim") != NULL,
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
    snprintf(step_path, sizeof(step_path), "%s/ipadprocad_smoke.step",
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
    occt_shape *ghost = occt_import_step("/nonexistent/ipadprocad-nope.step");
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
            check(ne == 3, "[12] cylinder must expose 3 edges (2 rims+seam)");
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

    if (g_failures == 0) {
        printf("OCCT SMOKE: PASS\n");
        return 0;
    }
    printf("OCCT SMOKE: FAIL (%d failing checks)\n", g_failures);
    return 1;
}
