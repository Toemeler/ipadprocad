/* shim_test.c — drives slvs_solve() (the FFI surface) through the exact
 * scenarios the app needs, and asserts the numeric results. Prints
 * "ALL SHIM TESTS PASS" only if every check holds (CI greps for it). */
#include <stdio.h>
#include <math.h>
#include "slvs_shim.h"

static int failures = 0;
static void check(const char *name, int ok) {
    printf("  %-34s %s\n", name, ok ? "ok" : "FAIL");
    if (!ok) failures++;
}
static int near(double a, double b) { return fabs(a - b) < 1e-3; }

/* ---- scenario 1: rectangle forced square + driving width -------------- */
static void test_rectangle(void) {
    printf("[1] rectangle: H/V on 4 edges + driving width = 50\n");
    double px[4] = {0, 52, 49, 1};
    double py[4] = {0,  3, 41, 38};
    int fixed[4] = {1, 0, 0, 0};              /* corner A locked at origin */
    int la[4] = {0, 1, 2, 3}, lb[4] = {1, 2, 3, 0};
    int ct[5]  = {SH_HORIZONTAL, SH_HORIZONTAL, SH_VERTICAL, SH_VERTICAL, SH_DISTANCE};
    int ca[5]  = {-1, -1, -1, -1, 0};
    int cb[5]  = {-1, -1, -1, -1, 1};
    int ce1[5] = {SH_ENT(1,0), SH_ENT(1,2), SH_ENT(1,1), SH_ENT(1,3), 0};
    int ce2[5] = {0,0,0,0,0};
    double cv[5] = {0,0,0,0,50};
    int dof = -1, failed[8];
    int r = slvs_solve(4, px, py, fixed, 4, la, lb, 0,0,0, 0,0,0,0,0,
                       5, ct, ca, cb, ce1, ce2, cv, &dof, failed, 8);
    check("result OKAY", r == SH_RESULT_OKAY);
    check("A at origin", near(px[0],0) && near(py[0],0));
    check("B = (50,0)", near(px[1],50) && near(py[1],0));
    check("top edge horizontal", near(py[2], py[3]));
    check("right edge vertical", near(px[1], px[2]));
    check("dof == 1 (height free)", dof == 1);
}

/* ---- scenario 2: circle diameter -------------------------------------- */
static void test_diameter(void) {
    printf("[2] circle: diameter = 30 -> radius 15\n");
    double px[1] = {10}, py[1] = {10};
    int fixed[1] = {1};
    int cc[1] = {0}; double cr[1] = {8};
    int ct[1] = {SH_DIAMETER}, ca[1] = {-1}, cb[1] = {-1};
    int ce1[1] = {SH_ENT(2,0)}, ce2[1] = {0}; double cv[1] = {30};
    int dof = -1, failed[8];
    int r = slvs_solve(1, px, py, fixed, 0,0,0, 1, cc, cr, 0,0,0,0,0,
                       1, ct, ca, cb, ce1, ce2, cv, &dof, failed, 8);
    check("result OKAY", r == SH_RESULT_OKAY);
    check("radius == 15", near(cr[0], 15));
}

/* ---- scenario 3: point-on-line ---------------------------------------- */
static void test_point_on_line(void) {
    printf("[3] point-on-line: p2 pulled onto edge p0-p1\n");
    double px[3] = {0, 10, 5}, py[3] = {0, 0, 4};
    int fixed[3] = {1, 1, 0};
    int la[1] = {0}, lb[1] = {1};
    int ct[1] = {SH_POINT_ON_LINE}, ca[1] = {2}, cb[1] = {-1};
    int ce1[1] = {SH_ENT(1,0)}, ce2[1] = {0}; double cv[1] = {0};
    int dof = -1, failed[8];
    int r = slvs_solve(3, px, py, fixed, 1, la, lb, 0,0,0, 0,0,0,0,0,
                       1, ct, ca, cb, ce1, ce2, cv, &dof, failed, 8);
    check("result OKAY", r == SH_RESULT_OKAY);
    check("p2 on the line (y=0)", near(py[2], 0));
}

/* ---- scenario 4: horizontal + vertical distance dims (X and Y) --------- */
static void test_xy_dims(void) {
    printf("[4] X/Y dims: dx = 10, dy = 6\n");
    double px[2] = {0, 7}, py[2] = {0, 4};
    int fixed[2] = {1, 0};
    int ct[2] = {SH_DIST_X, SH_DIST_Y};
    int ca[2] = {0, 0}, cb[2] = {1, 1};
    int ce1[2] = {0,0}, ce2[2] = {0,0};
    double cv[2] = {10, 6};
    int dof = -1, failed[8];
    int r = slvs_solve(2, px, py, fixed, 0,0,0, 0,0,0, 0,0,0,0,0,
                       2, ct, ca, cb, ce1, ce2, cv, &dof, failed, 8);
    check("result OKAY", r == SH_RESULT_OKAY);
    check("p1 = (10,6)", near(px[1], 10) && near(py[1], 6));
    check("fully constrained (dof 0)", dof == 0);
}

/* ---- scenario 5: over-constraint is detected -------------------------- */
static void test_overconstrained(void) {
    printf("[5] over-constraint: two conflicting distances on one segment\n");
    double px[2] = {0, 10}, py[2] = {0, 0};
    int fixed[2] = {1, 0};
    int ct[2] = {SH_DISTANCE, SH_DISTANCE};
    int ca[2] = {0, 0}, cb[2] = {1, 1};
    int ce1[2] = {0,0}, ce2[2] = {0,0};
    double cv[2] = {10, 20};              /* impossible together */
    int dof = -1, failed[8];
    int r = slvs_solve(2, px, py, fixed, 0,0,0, 0,0,0, 0,0,0,0,0,
                       2, ct, ca, cb, ce1, ce2, cv, &dof, failed, 8);
    check("result NOT OKAY", r != SH_RESULT_OKAY);
}

/* ---- scenario 6: dragged point solves cleanly ------------------------- */
static void test_dragged(void) {
    printf("[6] dragged point (grip pin) solves OKAY\n");
    double px[2] = {0, 10}, py[2] = {0, 0};
    int fixed[2] = {0, 0};
    int ct[1] = {SH_DRAGGED}, ca[1] = {1}, cb[1] = {-1};
    int ce1[1] = {0}, ce2[1] = {0}; double cv[1] = {0};
    int dof = -1, failed[8];
    int r = slvs_solve(2, px, py, fixed, 0,0,0, 0,0,0, 0,0,0,0,0,
                       1, ct, ca, cb, ce1, ce2, cv, &dof, failed, 8);
    check("result OKAY", r == SH_RESULT_OKAY);
}

int main(void) {
    printf("slvs_shim version = %d\n\n", slvs_shim_version());
    test_rectangle();
    test_diameter();
    test_point_on_line();
    test_xy_dims();
    test_overconstrained();
    test_dragged();
    printf("\n%d failures\n", failures);
    if (failures == 0) printf("ALL SHIM TESTS PASS\n");
    return failures == 0 ? 0 : 1;
}
