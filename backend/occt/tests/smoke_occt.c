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

    if (g_failures == 0) {
        printf("OCCT SMOKE: PASS\n");
        return 0;
    }
    printf("OCCT SMOKE: FAIL (%d failing checks)\n", g_failures);
    return 1;
}
