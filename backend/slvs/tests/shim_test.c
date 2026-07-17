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

/* ---- scenario 7: dragging a CONSTRAINED point -----------------------------
 * The regression that made the app look broken. SH_DRAGGED must be a WISH, not
 * a command: it used to map to SLVS_C_WHERE_DRAGGED, which is a HARD constraint
 * and simply outvoted the real ones -- a "vertical" line went slanted under the
 * cursor and a locked point drifted off its anchor. It now maps to
 * Slvs_System.dragged[], which only favours the parameter.
 * Setup = the reported bug: vertical line, bottom end locked on the origin, the
 * user yanks the top end sideways to (25,55). The x must be REFUSED and the
 * point must slide along the line instead. */
static void test_dragged_constrained(void) {
    printf("[7] drag a constrained point: the constraint wins\n");
    double px[2] = {0, 25}, py[2] = {0, 55};  /* p1 already sits at the cursor */
    int fixed[2] = {1, 0};                    /* p0 grounded                   */
    int la[1] = {0}, lb[1] = {1};
    int ct[2]  = {SH_VERTICAL, SH_DRAGGED};
    int ca[2]  = {-1, 1};
    int cb[2]  = {-1, -1};
    int ce1[2] = {SH_ENT(1,0), 0};
    int ce2[2] = {0, 0};
    double cv[2] = {0, 0};
    int dof = -1, failed[8];
    int r = slvs_solve(2, px, py, fixed, 1, la, lb, 0,0,0, 0,0,0,0,0,
                       2, ct, ca, cb, ce1, ce2, cv, &dof, failed, 8);
    check("result OKAY", r == SH_RESULT_OKAY);
    check("vertical held (x refused)", near(px[1], 0.0));
    check("point slid along (y kept)", near(py[1], 55.0));
    check("locked end did not move",
          near(px[0], 0.0) && near(py[0], 0.0));
    check("one DOF left (length)", dof == 1);
}

/* ---- scenario 8: the app's actual case ------------------------------------
 * Rectangle (H/V on all four edges), bottom-left grounded on the origin, user
 * drags the top-left corner sideways+up. The shape must stay a rectangle, the
 * grounded corner must not budge, and the width must NOT collapse -- dragged[]
 * favours the dragged params, so everything else moves as little as possible. */
static void test_dragged_rectangle(void) {
    printf("[8] drag a rectangle corner: shape + anchor + width hold\n");
    double px[4] = {0, 60, 60, 25};   /* p3 already yanked to the cursor */
    double py[4] = {0,  0, 40, 55};
    int fixed[4] = {1, 0, 0, 0};
    int la[4] = {0,1,2,3}, lb[4] = {1,2,3,0};
    int ct[5]  = {SH_HORIZONTAL, SH_HORIZONTAL, SH_VERTICAL, SH_VERTICAL,
                  SH_DRAGGED};
    int ca[5]  = {-1,-1,-1,-1, 3};
    int cb[5]  = {-1,-1,-1,-1,-1};
    int ce1[5] = {SH_ENT(1,0), SH_ENT(1,2), SH_ENT(1,1), SH_ENT(1,3), 0};
    int ce2[5] = {0,0,0,0,0};
    double cv[5] = {0,0,0,0,0};
    int dof = -1, failed[8];
    int r = slvs_solve(4, px, py, fixed, 4, la, lb, 0,0,0, 0,0,0,0,0,
                       5, ct, ca, cb, ce1, ce2, cv, &dof, failed, 8);
    check("result OKAY", r == SH_RESULT_OKAY);
    check("anchor corner unmoved", near(px[0], 0.0) && near(py[0], 0.0));
    check("left edge still vertical", near(px[3], px[0]));
    check("bottom edge still horizontal", near(py[1], py[0]));
    check("top edge still horizontal", near(py[2], py[3]));
    check("drag reached in y", near(py[3], 55.0));
    check("width did not collapse", near(px[1], 60.0));
}

/* ---- scenario 9: SH_PT_LINE_DIST (shim v2) ---------------------------------
 * A locked horizontal line p0-p1 on y=0 and a free point p2 above it at
 * y=7. Driving the perpendicular distance to 12 must move the point to
 * y=12 -- on the SAME side (no mirroring through the line), with x free. */
static void test_pt_line_dist(void) {
    printf("[9] pt-line distance: drive p2 to 12 above the line\n");
    double px[3] = {0, 100, 30}, py[3] = {0, 0, 7};
    int fixed[3] = {1, 1, 0};
    int la[1] = {0}, lb[1] = {1};
    int ct[1]  = {SH_PT_LINE_DIST};
    int ca[1]  = {2}, cb[1] = {-1};
    int ce1[1] = {0}, ce2[1] = {1};       /* RAW point indices of the line */
    double cv[1] = {12};
    int dof = -1, failed[8];
    int r = slvs_solve(3, px, py, fixed, 1, la, lb, 0,0,0, 0,0,0,0,0,
                       1, ct, ca, cb, ce1, ce2, cv, &dof, failed, 8);
    check("result OKAY", r == SH_RESULT_OKAY);
    check("distance reached (y=12)", near(py[2], 12.0));
    check("same side (y>0)", py[2] > 0);
    check("x stayed free (dof 1)", dof == 1);
}

/* ---- scenario 10: SH_PT_LINE_DIST below the line ----------------------- */
static void test_pt_line_dist_below(void) {
    printf("[10] pt-line distance: point below stays below\n");
    double px[3] = {0, 100, 30}, py[3] = {0, 0, -3};
    int fixed[3] = {1, 1, 0};
    int la[1] = {0}, lb[1] = {1};
    int ct[1]  = {SH_PT_LINE_DIST};
    int ca[1]  = {2}, cb[1] = {-1};
    int ce1[1] = {0}, ce2[1] = {1};
    double cv[1] = {5};
    int dof = -1, failed[8];
    int r = slvs_solve(3, px, py, fixed, 1, la, lb, 0,0,0, 0,0,0,0,0,
                       1, ct, ca, cb, ce1, ce2, cv, &dof, failed, 8);
    check("result OKAY", r == SH_RESULT_OKAY);
    check("distance reached (y=-5)", near(py[2], -5.0));
}

/* ---- scenario 11: linear SLOT solved natively (shim v3) --------------------
 * Two rails + two half-circle caps, coincidences folded (shared point
 * indices), 4 tangencies with the correct seam-end flags, equal radii.
 * The pre-v3 shim anchored every tangency at the arc START and could only
 * "solve" a slot by luck of symmetry; v3 must solve it as a slot and keep it
 * one when an end is dragged. Layout (y up):
 *   p2 (0,12) ---- p3 (40,12)      rail2 (top)
 *   p0 (0, 0) ---- p1 (40, 0)      rail1 (bottom)
 *   cap A: center p4 (0,6),  start p0, end p2   (left,  seam start+end)
 *   cap B: center p5 (40,6), start p3, end p1   (right)
 * tangent(rail1, capA): rail1 joins capA at capA's START -> e2 bit = 0
 * tangent(rail2, capA): joins at capA's END             -> e2 bit = 1 (val 2)
 * tangent(rail2, capB): capB START                      -> val 0
 * tangent(rail1, capB): capB END                        -> val 2
 */
static void test_slot_native(void) {
    printf("[11] linear slot solves natively with seam-end flags (v3)\n");
    double px[6] = {0, 40, 0, 40, 0, 40};
    double py[6] = {0, 0, 12, 12, 6, 6};
    int fixed[6] = {1, 0, 0, 0, 0, 0};      /* ground one rail end */
    int la[2] = {0, 2}, lb[2] = {1, 3};     /* rail1 p0-p1, rail2 p2-p3 */
    int ac[2] = {4, 5};
    int as_[2] = {0, 3};                    /* capA starts at p0, capB at p3 */
    int ae[2] = {2, 1};                     /* capA ends at p2, capB at p1  */
    double ar[2] = {6, 6};
    /* SH_ENT kinds: 1 line, 3 arc */
    int L1 = SH_ENT(1, 0), L2 = SH_ENT(1, 1);
    int A  = SH_ENT(3, 0), B  = SH_ENT(3, 1);
    int ct[6]  = {SH_TANGENT, SH_TANGENT, SH_TANGENT, SH_TANGENT,
                  SH_EQUAL, SH_DISTANCE};
    int ca[6]  = {-1, -1, -1, -1, -1, 0};
    int cb[6]  = {-1, -1, -1, -1, -1, 1};
    int ce1[6] = {L1, L2, L2, L1, A, 0};
    int ce2[6] = {A,  A,  B,  B,  B, 0};
    /* seam flags in val: bit1 = the ARC (always e2 here) joins at its END */
    double cv[6] = {0, 2, 0, 2, 0, 40};     /* + rail length dim to pin dof */
    int dof = -1, failed[8];
    int r = slvs_solve(6, px, py, fixed, 2, la, lb, 0, 0, 0,
                       2, ac, as_, ae, ar,
                       6, ct, ca, cb, ce1, ce2, cv, &dof, failed, 8);
    check("result OKAY (no redundancy, no wrong anchor)", r == SH_RESULT_OKAY);
    check("caps stayed r=6 (A)", near(ar[0], 6.0));
    check("caps stayed r=6 (B)", near(ar[1], 6.0));
    check("rails still 12 apart", near(py[2] - py[0], 12.0));
    /* now DRAG the free rail end up in SMALL STEPS, exactly like real drag
     * frames (each step starts from the previous SOLVED state — the app's
     * display gate guarantees that): the slot must rotate, never collapse or
     * cross into the bowtie branch. A single huge jump could legitimately
     * land Newton on the crossed solution; frames never jump like that. */
    int ct2[7]  = {SH_TANGENT, SH_TANGENT, SH_TANGENT, SH_TANGENT,
                   SH_EQUAL, SH_DISTANCE, SH_DRAGGED};
    int ca2[7]  = {-1, -1, -1, -1, -1, 0, 1};
    int cb2[7]  = {-1, -1, -1, -1, -1, 1, -1};
    int ce12[7] = {L1, L2, L2, L1, A, 0, 0};
    int ce22[7] = {A,  A,  B,  B,  B, 0, 0};
    double cv2[7] = {0, 2, 0, 2, 0, 40, 0};
    for (int step = 1; step <= 8; step++) {
        px[1] = 40.0 - 0.125 * step;        /* -> 39.0 */
        py[1] = 0.0  + 1.0   * step;        /* -> +8.0 */
        r = slvs_solve(6, px, py, fixed, 2, la, lb, 0, 0, 0,
                       2, ac, as_, ae, ar,
                       7, ct2, ca2, cb2, ce12, ce22, cv2, &dof, failed, 8);
        if (r != SH_RESULT_OKAY) break;
    }
    check("drag result OKAY", r == SH_RESULT_OKAY);
    check("still equal caps after drag", near(ar[0], ar[1]));
    check("caps kept a sane radius", ar[0] > 1.0 && ar[0] < 20.0);
    {   /* rails parallel by implication: cross of directions ~ 0 */
        double d1x = px[1]-px[0], d1y = py[1]-py[0];
        double d2x = px[3]-px[2], d2y = py[3]-py[2];
        double cr  = d1x*d2y - d1y*d2x;
        double n   = sqrt((d1x*d1x+d1y*d1y)*(d2x*d2x+d2y*d2y));
        check("rails parallel after drag", fabs(cr / n) < 1e-6);
    }
}

/* ---- scenario 12: fillet arc tangent at its END (the v2 wrong-anchor bug) --
 * A 90-degree fillet between a horizontal and a vertical line:
 *   horizontal p0(0,0)-p1(16,0), vertical p2(20,4)-p3(20,20),
 *   arc center p4(16,4), START p1 (touch horizontal), END p2 (touch vertical).
 * tangent(vertical, arc) joins at the arc's END. The v2 shim anchored it at
 * the START: that demanded vertical  |  radius-at-start, i.e. vertical
 * parallel to the horizontal's normal -- satisfied here by accident of the
 * axis-aligned layout, so the discriminating check is the DRAG: rotate the
 * vertical line's far end; a correctly anchored tangency keeps the seam
 * tangent, the wrong one tears the fillet. */
static void test_fillet_end_anchor(void) {
    printf("[12] fillet arc tangency anchored at the END seam (v3)\n");
    double px[5] = {0, 16, 20, 26, 16};
    double py[5] = {0, 0, 4, 20, 4};
    int fixed[5] = {1, 0, 0, 1, 0};         /* ground the two far ends */
    int la[2] = {0, 2}, lb[2] = {1, 3};
    int ac[1] = {4}, as_[1] = {1}, ae[1] = {2};
    double ar[1] = {4};
    int H = SH_ENT(1, 0), V = SH_ENT(1, 1), A = SH_ENT(3, 0);
    /* radius dim pins the fillet size, like the app's 'rad' dimension */
    int ct[3]  = {SH_TANGENT, SH_TANGENT, SH_RADIUS};
    int ca[3]  = {-1, -1, -1};
    int cb[3]  = {-1, -1, -1};
    int ce1[3] = {H, V, A};
    int ce2[3] = {A, A, 0};
    double cv[3] = {0 /* seam at arc START */,
                    2 /* seam at arc END   */,
                    4};
    int dof = -1, failed[8];
    int r = slvs_solve(5, px, py, fixed, 2, la, lb, 0, 0, 0,
                       1, ac, as_, ae, ar,
                       3, ct, ca, cb, ce1, ce2, cv, &dof, failed, 8);
    check("result OKAY", r == SH_RESULT_OKAY);
    /* tangency truth at BOTH seams: radius vector perpendicular to line */
    {
        double rx = px[1]-px[4], ry = py[1]-py[4];      /* center->start */
        double hx = px[1]-px[0], hy = py[1]-py[0];
        check("start seam tangent to horizontal",
              fabs(rx*hx + ry*hy) / (4.0*sqrt(hx*hx+hy*hy)) < 1e-6);
        rx = px[2]-px[4]; ry = py[2]-py[4];             /* center->end */
        double vx = px[3]-px[2], vy = py[3]-py[2];
        check("END seam tangent to the second line",
              fabs(rx*vx + ry*vy) / (4.0*sqrt(vx*vx+vy*vy)) < 1e-6);
        check("fillet radius held at 4", near(ar[0], 4.0));
    }
}

/* ---- scenario 13: point on circle (shim v4, Inventor trim coincidence) ----
 * A free point bound onto a circle (SLVS_C_PT_ON_CIRCLE): growing the circle
 * via a diameter dimension must carry the point outward with it — exactly the
 * behaviour trim's cut-point binding needs. */
static void test_point_on_circle(void) {
    printf("[13] point on circle follows the radius (v4)\n");
    double px[2] = {0, 20};      /* p0 circle center, p1 the bound point */
    double py[2] = {0, 0};
    int fixed[2] = {1, 0};
    int cc[1] = {0};
    double cr[1] = {20};
    int C = SH_ENT(2, 0);
    int ct[2]  = {SH_POINT_ON_CIRCLE, SH_DIAMETER};
    int ca[2]  = {1, -1};
    int cb[2]  = {-1, -1};
    int ce1[2] = {C, C};
    int ce2[2] = {0, 0};
    double cv[2] = {0, 60};      /* diameter 60 -> radius 30 */
    int dof = -1, failed[8];
    int r = slvs_solve(2, px, py, fixed, 0, 0, 0, 1, cc, cr, 0, 0, 0, 0, 0,
                       2, ct, ca, cb, ce1, ce2, cv, &dof, failed, 8);
    check("result OKAY", r == SH_RESULT_OKAY);
    check("radius grew to 30", near(cr[0], 30.0));
    {
        double d = sqrt(px[1]*px[1] + py[1]*py[1]);
        check("point rode outward to r=30", near(d, 30.0));
    }
}

int main(void) {
    printf("slvs_shim version = %d\n\n", slvs_shim_version());
    test_rectangle();
    test_diameter();
    test_point_on_line();
    test_xy_dims();
    test_overconstrained();
    test_dragged();
    test_dragged_constrained();
    test_dragged_rectangle();
    test_pt_line_dist();
    test_pt_line_dist_below();
    test_slot_native();
    test_fillet_end_anchor();
    test_point_on_circle();
    printf("\n%d failures\n", failures);
    if (failures == 0) printf("ALL SHIM TESTS PASS\n");
    return failures == 0 ? 0 : 1;
}
