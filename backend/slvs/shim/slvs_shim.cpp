/* slvs_shim.cpp — implementation. See slvs_shim.h. */
#include "slvs_shim.h"

#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "slvs.h"

/* entity-ref decode (must match SH_ENT in the header) */
static int refKind(int e) { return e <= 0 ? 0 : e / 100000000; }
static int refIdx(int e)  { return e <= 0 ? -1 : e % 100000000; }

/* read a solved parameter value back out of the system by handle */
static double paramVal(const Slvs_System *s, Slvs_hParam h) {
    for (int i = 0; i < s->params; i++)
        if (s->param[i].h == h) return s->param[i].val;
    return 0.0;
}

/* v2: SH_PT_LINE_DIST (perpendicular point-to-line distance dimension). The
 * Dart side gates on this: a binary older than 2 sends those sketches to the
 * Dart LM solver instead, so the dimension is never silently dropped. */
int slvs_shim_version(void) { return 3; }

const char* slvs_shim_id(void) { return "iPadProCAD SLVS shim v2"; }

int slvs_solve(
    int nPts, double *px, double *py, const int *fixed,
    int nLines, const int *la, const int *lb,
    int nCircles, const int *cc, double *cr,
    int nArcs, const int *ac, const int *as_, const int *ae, double *ar,
    int nCons, const int *ct, const int *ca, const int *cb,
    const int *ce1, const int *ce2, const double *cval,
    int *dofOut, int *failed, int failedCap)
{
    Slvs_System sys;
    memset(&sys, 0, sizeof(sys));

    /* generous upper bounds: each point 2 params; each circle 1 (radius);
     * plus workplane (7) and axis helpers. Entities: points + lines +
     * 2*circles + arcs + fixed scaffolding. Constraints may double (collinear
     * expands to parallel + point-on-line). */
    int maxParam = 7 + 2 * nPts + nCircles + 8 + 16;
    /* + nCons: SH_PT_LINE_DIST may add one ad-hoc line entity per record */
    int maxEnt   = 3 + nPts + nLines + 2 * nCircles + nArcs + nCons + 16;
    int maxCon   = 2 * nCons + 8;

    sys.param      = (Slvs_Param *)      calloc(maxParam, sizeof(Slvs_Param));
    sys.entity     = (Slvs_Entity *)     calloc(maxEnt,   sizeof(Slvs_Entity));
    sys.constraint = (Slvs_Constraint *) calloc(maxCon,   sizeof(Slvs_Constraint));
    sys.failed     = (Slvs_hConstraint *)calloc(maxCon,   sizeof(Slvs_hConstraint));
    sys.faileds    = maxCon;
    if (!sys.param || !sys.entity || !sys.constraint || !sys.failed) {
        free(sys.param); free(sys.entity); free(sys.constraint); free(sys.failed);
        if (dofOut) *dofOut = 0;
        return SH_RESULT_INCONSISTENT;
    }

    Slvs_hParam  hp = 1;
    Slvs_hEntity he = 1;
    Slvs_hConstraint hc = 1;

    const Slvs_hGroup GLOCK = 1;  /* locked geometry (workplane, fixed pts) */
    const Slvs_hGroup GFREE = 2;  /* solved geometry                        */

    /* ---- workplane on the XY plane (locked) ---- */
    Slvs_hParam p_ox = hp++, p_oy = hp++, p_oz = hp++;
    sys.param[sys.params++] = Slvs_MakeParam(p_ox, GLOCK, 0.0);
    sys.param[sys.params++] = Slvs_MakeParam(p_oy, GLOCK, 0.0);
    sys.param[sys.params++] = Slvs_MakeParam(p_oz, GLOCK, 0.0);
    Slvs_hEntity e_origin3d = he++;
    sys.entity[sys.entities++] = Slvs_MakePoint3d(e_origin3d, GLOCK, p_ox, p_oy, p_oz);

    double qw, qx, qy, qz;
    Slvs_MakeQuaternion(1, 0, 0, 0, 1, 0, &qw, &qx, &qy, &qz);
    Slvs_hParam p_qw = hp++, p_qx = hp++, p_qy = hp++, p_qz = hp++;
    sys.param[sys.params++] = Slvs_MakeParam(p_qw, GLOCK, qw);
    sys.param[sys.params++] = Slvs_MakeParam(p_qx, GLOCK, qx);
    sys.param[sys.params++] = Slvs_MakeParam(p_qy, GLOCK, qy);
    sys.param[sys.params++] = Slvs_MakeParam(p_qz, GLOCK, qz);
    Slvs_hEntity e_normal = he++;
    sys.entity[sys.entities++] = Slvs_MakeNormal3d(e_normal, GLOCK, p_qw, p_qx, p_qy, p_qz);

    Slvs_hEntity WP = he++;
    sys.entity[sys.entities++] = Slvs_MakeWorkplane(WP, GLOCK, e_origin3d, e_normal);

    /* ---- reference axes (locked) for horizontal/vertical distance dims ---- */
    #define LOCKPT2D(u, v, out) do {                                        \
        Slvs_hParam _pu = hp++, _pv = hp++;                                 \
        sys.param[sys.params++] = Slvs_MakeParam(_pu, GLOCK, (u));          \
        sys.param[sys.params++] = Slvs_MakeParam(_pv, GLOCK, (v));          \
        (out) = he++;                                                       \
        sys.entity[sys.entities++] = Slvs_MakePoint2d((out), GLOCK, WP, _pu, _pv); \
    } while (0)
    Slvs_hEntity axO, axX, axY;
    LOCKPT2D(0.0, 0.0, axO);
    LOCKPT2D(1.0, 0.0, axX);
    LOCKPT2D(0.0, 1.0, axY);
    Slvs_hEntity uAxis = he++, vAxis = he++;
    sys.entity[sys.entities++] = Slvs_MakeLineSegment(uAxis, GLOCK, WP, axO, axX);
    sys.entity[sys.entities++] = Slvs_MakeLineSegment(vAxis, GLOCK, WP, axO, axY);

    /* ---- points ---- */
    Slvs_hEntity *ptH = (Slvs_hEntity *)calloc(nPts > 0 ? nPts : 1, sizeof(Slvs_hEntity));
    Slvs_hParam  *ptU = (Slvs_hParam *) calloc(nPts > 0 ? nPts : 1, sizeof(Slvs_hParam));
    Slvs_hParam  *ptV = (Slvs_hParam *) calloc(nPts > 0 ? nPts : 1, sizeof(Slvs_hParam));
    for (int i = 0; i < nPts; i++) {
        Slvs_hGroup g = (fixed && fixed[i]) ? GLOCK : GFREE;
        ptU[i] = hp++; ptV[i] = hp++;
        sys.param[sys.params++] = Slvs_MakeParam(ptU[i], g, px[i]);
        sys.param[sys.params++] = Slvs_MakeParam(ptV[i], g, py[i]);
        ptH[i] = he++;
        sys.entity[sys.entities++] = Slvs_MakePoint2d(ptH[i], GFREE, WP, ptU[i], ptV[i]);
    }

    /* ---- lines ---- */
    Slvs_hEntity *lnH = (Slvs_hEntity *)calloc(nLines > 0 ? nLines : 1, sizeof(Slvs_hEntity));
    for (int k = 0; k < nLines; k++) {
        lnH[k] = he++;
        sys.entity[sys.entities++] =
            Slvs_MakeLineSegment(lnH[k], GFREE, WP, ptH[la[k]], ptH[lb[k]]);
    }

    /* ---- circles (center point + radius distance entity) ---- */
    Slvs_hEntity *ciH = (Slvs_hEntity *)calloc(nCircles > 0 ? nCircles : 1, sizeof(Slvs_hEntity));
    Slvs_hParam  *ciR = (Slvs_hParam *) calloc(nCircles > 0 ? nCircles : 1, sizeof(Slvs_hParam));
    for (int k = 0; k < nCircles; k++) {
        ciR[k] = hp++;
        sys.param[sys.params++] = Slvs_MakeParam(ciR[k], GFREE, cr[k]);
        Slvs_hEntity dist = he++;
        sys.entity[sys.entities++] = Slvs_MakeDistance(dist, GFREE, WP, ciR[k]);
        ciH[k] = he++;
        sys.entity[sys.entities++] =
            Slvs_MakeCircle(ciH[k], GFREE, WP, ptH[cc[k]], e_normal, dist);
    }

    /* ---- arcs ---- */
    Slvs_hEntity *arH = (Slvs_hEntity *)calloc(nArcs > 0 ? nArcs : 1, sizeof(Slvs_hEntity));
    for (int k = 0; k < nArcs; k++) {
        arH[k] = he++;
        sys.entity[sys.entities++] = Slvs_MakeArcOfCircle(
            arH[k], GFREE, WP, e_normal, ptH[ac[k]], ptH[as_[k]], ptH[ae[k]]);
    }

    /* resolve an encoded entity ref to a slvs handle */
    #define ENT(ref) ( refKind(ref)==1 ? lnH[refIdx(ref)] :                 \
                       refKind(ref)==2 ? ciH[refIdx(ref)] :                 \
                       refKind(ref)==3 ? arH[refIdx(ref)] : 0 )
    #define ENT_IS_CURVE(ref) (refKind(ref)==2 || refKind(ref)==3)
    /* first point index of a line entity ref (for collinear expansion) */
    #define LINE_PTA(ref) ( refKind(ref)==1 ? ptH[la[refIdx(ref)]] : 0 )

    #define ADDC(t,va,pa,pb,e1,e2) \
        sys.constraint[sys.constraints++] = \
            Slvs_MakeConstraint(hc++, GFREE, (t), WP, (va), (pa), (pb), (e1), (e2))

    Slvs_hParam draggedP[4];
    int nDragged = 0;

    for (int i = 0; i < nCons; i++) {
        int t = ct[i];
        int a = ca ? ca[i] : -1, b = cb ? cb[i] : -1;
        int e1 = ce1 ? ce1[i] : 0, e2 = ce2 ? ce2[i] : 0;
        double v = cval ? cval[i] : 0.0;
        Slvs_hEntity pa = (a >= 0 && a < nPts) ? ptH[a] : 0;
        Slvs_hEntity pb = (b >= 0 && b < nPts) ? ptH[b] : 0;

        switch (t) {
        case SH_COINCIDENT:
            ADDC(SLVS_C_POINTS_COINCIDENT, 0, pa, pb, 0, 0); break;
        case SH_POINT_ON_LINE:
            ADDC(SLVS_C_PT_ON_LINE, 0, pa, 0, ENT(e1), 0); break;
        case SH_HORIZONTAL:
            if (pa && pb) ADDC(SLVS_C_HORIZONTAL, 0, pa, pb, 0, 0);
            else          ADDC(SLVS_C_HORIZONTAL, 0, 0, 0, ENT(e1), 0);
            break;
        case SH_VERTICAL:
            if (pa && pb) ADDC(SLVS_C_VERTICAL, 0, pa, pb, 0, 0);
            else          ADDC(SLVS_C_VERTICAL, 0, 0, 0, ENT(e1), 0);
            break;
        case SH_PARALLEL:
            ADDC(SLVS_C_PARALLEL, 0, 0, 0, ENT(e1), ENT(e2)); break;
        case SH_PERPENDICULAR:
            ADDC(SLVS_C_PERPENDICULAR, 0, 0, 0, ENT(e1), ENT(e2)); break;
        case SH_COLLINEAR:
            /* slvs has no direct collinear: parallel + endpoint-on-line */
            ADDC(SLVS_C_PARALLEL, 0, 0, 0, ENT(e1), ENT(e2));
            ADDC(SLVS_C_PT_ON_LINE, 0, LINE_PTA(e2), 0, ENT(e1), 0);
            break;
        case SH_CONCENTRIC:
            /* concentric = coincident centers; use the entities' center pts */
            ADDC(SLVS_C_POINTS_COINCIDENT, 0,
                 (refKind(e1)==2 ? ptH[cc[refIdx(e1)]] : ptH[ac[refIdx(e1)]]),
                 (refKind(e2)==2 ? ptH[cc[refIdx(e2)]] : ptH[ac[refIdx(e2)]]),
                 0, 0);
            break;
        case SH_EQUAL:
            if (ENT_IS_CURVE(e1) && ENT_IS_CURVE(e2))
                ADDC(SLVS_C_EQUAL_RADIUS, 0, 0, 0, ENT(e1), ENT(e2));
            else
                ADDC(SLVS_C_EQUAL_LENGTH_LINES, 0, 0, 0, ENT(e1), ENT(e2));
            break;
        case SH_TANGENT: {
            /* SolveSpace's tangencies are ENDPOINT-ANCHORED: ARC_LINE_TANGENT
             * makes the line perpendicular to the arc's radius at point[other
             * ? 2 : 1]; CURVE_CURVE_TANGENT does the same per curve via
             * other/other2 (constrainteq.cpp). The caller inspected the real
             * geometry and tells us which end each arc's seam is on (val bit 0
             * for e1's arc, bit 1 for e2's arc). The old shim hardcoded
             * other = 0 (START) — a wrong equation whenever the seam sits at
             * the END, which is every second slot-cap seam and half of all
             * fillet arcs. Circles never reach this code (no endpoints; the
             * Dart side keeps circle tangency on its own solver).
             */
            int flags = (int)v;
            int e1IsArc = (refKind(e1) == 3);
            int e2IsArc = (refKind(e2) == 3);
            if (e1IsArc && e2IsArc) {
                ADDC(SLVS_C_CURVE_CURVE_TANGENT, 0, 0, 0, ENT(e1), ENT(e2));
                sys.constraint[sys.constraints - 1].other  = (flags & 1) != 0;
                sys.constraint[sys.constraints - 1].other2 = (flags & 2) != 0;
            } else {
                /* order as (arc, line) for ARC_LINE_TANGENT; carry the arc's
                 * seam-end flag along with it */
                int ce   = e1IsArc ? e1 : e2;
                int le   = e1IsArc ? e2 : e1;
                int aEnd = e1IsArc ? (flags & 1) : ((flags & 2) >> 1);
                ADDC(SLVS_C_ARC_LINE_TANGENT, 0, 0, 0, ENT(ce), ENT(le));
                sys.constraint[sys.constraints - 1].other = aEnd != 0;
            }
            break;
        }
        case SH_SYMMETRIC:
            ADDC(SLVS_C_SYMMETRIC_LINE, 0, pa, pb, ENT(e1), 0); break;
        case SH_MIDPOINT:
            ADDC(SLVS_C_AT_MIDPOINT, 0, pa, 0, ENT(e1), 0); break;
        case SH_DISTANCE:
            ADDC(SLVS_C_PT_PT_DISTANCE, v, pa, pb, 0, 0); break;
        case SH_DIST_X: {
            /* PROJ_PT_DISTANCE is signed; keep the point on the side it is
             * on now (Inventor preserves the dimension's placement side). */
            double cur = (a >= 0 && b >= 0) ? px[b] - px[a] : 1.0;
            ADDC(SLVS_C_PROJ_PT_DISTANCE, cur < 0 ? v : -v, pa, pb, uAxis, 0);
            break; }
        case SH_DIST_Y: {
            double cur = (a >= 0 && b >= 0) ? py[b] - py[a] : 1.0;
            ADDC(SLVS_C_PROJ_PT_DISTANCE, cur < 0 ? v : -v, pa, pb, vAxis, 0);
            break; }
        case SH_DIAMETER:
            ADDC(SLVS_C_DIAMETER, v, 0, 0, ENT(e1), 0); break;
        case SH_RADIUS:
            ADDC(SLVS_C_DIAMETER, 2.0 * v, 0, 0, ENT(e1), 0); break;
        case SH_ANGLE:
            ADDC(SLVS_C_ANGLE, v, 0, 0, ENT(e1), ENT(e2)); break;
        case SH_PT_LINE_DIST: {
            /* Perpendicular distance from point a to the (infinite) line
             * through points ce1,ce2 — here e1/e2 are RAW point indices, not
             * SH_ENT refs, so the line may be a polyline segment or any pair
             * of sketch points that never became a shim line entity. A line
             * segment entity over existing points adds no parameters, so an
             * ad-hoc one costs nothing.
             *
             * SLVS_C_PT_LINE_DISTANCE is SIGNED in a workplane; sign the
             * target to keep the point on the side it is on now (same policy
             * as PROJ_PT_DISTANCE above — Inventor keeps the placement side,
             * it never mirrors geometry through the line). */
            if (a < 0 || a >= nPts) break;
            int ia = e1, ib = e2;
            if (ia < 0 || ia >= nPts || ib < 0 || ib >= nPts || ia == ib) break;
            Slvs_hEntity ln = he++;
            sys.entity[sys.entities++] =
                Slvs_MakeLineSegment(ln, GFREE, WP, ptH[ia], ptH[ib]);
            /* SolveSpace's residual is proj/|d| with
             *   proj = (a.y-b.y)(a.x-p.x) - (a.x-b.x)(a.y-p.y)
             * (constrainteq.cpp, PointLineDistance, in-workplane branch).
             * Evaluate exactly that to pick the sign of the target. */
            double proj = (py[ia] - py[ib]) * (px[ia] - px[a])
                        - (px[ia] - px[ib]) * (py[ia] - py[a]);
            ADDC(SLVS_C_PT_LINE_DISTANCE, proj < 0 ? -v : v, pa, 0, ln, 0);
            break; }
        case SH_DRAGGED:
            /* NOT SLVS_C_WHERE_DRAGGED. That one is a HARD constraint ("the
             * point is exactly here"), so it fights the real constraints and
             * wins: a vertical line goes slanted under the cursor and a locked
             * point drifts off its anchor.
             *
             * The soft mechanism is Slvs_System.dragged[] (slvs.h): "causes the
             * solver to favor that parameter, and attempt to change it as little
             * as possible even if that requires it to change other parameters
             * more". The constraints stay hard; the dragged point simply keeps
             * as much of the cursor position as its remaining freedom allows.
             * Collected here, written into sys.dragged before the solve. */
            if (a >= 0 && a < nPts && nDragged + 1 < 4) {
                draggedP[nDragged++] = ptU[a];
                draggedP[nDragged++] = ptV[a];
            }
            break;
        default: break;
        }
    }

    /* sys.dragged holds up to 4 PARAMS = 2 points; we only ever drag one. */
    for (int i = 0; i < nDragged && i < 4; i++) sys.dragged[i] = draggedP[i];

    Slvs_Solve(&sys, GFREE);

    /* libslvs folds SolveResult::REDUNDANT_OKAY -- a solve that CONVERGED and
     * whose system merely contains redundant equations -- into
     * SLVS_RESULT_INCONSISTENT (see lib.cpp, the switch over SolveResult).
     * SH_DRAGGED deliberately makes the system redundant whenever the dragged
     * point has fewer than 2 DOF left, which is the NORMAL case while dragging
     * a constrained sketch. Slvs_Solve writes the solved parameters back either
     * way, so hand them to the caller instead of throwing a perfectly good
     * solution away. The caller verifies every result against the constraint
     * residuals and falls back to its own solver if it does not hold, so a
     * genuinely contradictory system is still rejected. */
    int nFailed = 0;
    if (sys.result == SLVS_RESULT_OKAY ||
        sys.result == SLVS_RESULT_INCONSISTENT) {
        for (int i = 0; i < nPts; i++) {
            px[i] = paramVal(&sys, ptU[i]);
            py[i] = paramVal(&sys, ptV[i]);
        }
        for (int k = 0; k < nCircles; k++) cr[k] = paramVal(&sys, ciR[k]);
        /* arc radius is derived: distance(center, start) */
        for (int k = 0; k < nArcs; k++) {
            double dx = px[as_[k]] - px[ac[k]], dy = py[as_[k]] - py[ac[k]];
            ar[k] = sqrt(dx * dx + dy * dy);
        }
    }
    if (sys.result != SLVS_RESULT_OKAY) {
        int n = sys.faileds;
        for (int i = 0; i < n && nFailed < failedCap; i++)
            if (failed) failed[nFailed++] = (int)sys.failed[i];
    }
    if (dofOut) *dofOut = sys.dof;

    int result = sys.result;
    free(ptH); free(ptU); free(ptV);
    free(lnH); free(ciH); free(ciR); free(arH);
    free(sys.param); free(sys.entity); free(sys.constraint); free(sys.failed);
    return result;
}
