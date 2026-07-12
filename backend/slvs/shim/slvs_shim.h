/* slvs_shim.h — a flat, FFI-friendly surface over libslvs for iPadProCAD.
 *
 * The Dart side owns the sketch model (Geo entities + Constraint list). It
 * decomposes each entity into POINTS plus a typed entity that references
 * those points (a polyline rectangle becomes 4 points + 4 line segments),
 * packs everything into the flat arrays below, calls slvs_solve(), and reads
 * the updated point coordinates / radii back.
 *
 * One 2D workplane (XY). All indices are zero-based into the arrays passed in.
 * Entity references in constraints are encoded as (kind*100000000 + index):
 *   kind 1 = line, 2 = circle, 3 = arc. 0 / negative = "none".
 * Point references are plain point indices, or -1 for "none".
 */
#ifndef SLVS_SHIM_H
#define SLVS_SHIM_H

#ifdef __cplusplus
extern "C" {
#endif

/* constraint type codes (mirror the Dart CType enum meaning, not its index) */
#define SH_COINCIDENT     1   /* a,b points  (point-on-point)                */
#define SH_POINT_ON_LINE  2   /* point a on line e1                          */
#define SH_HORIZONTAL     3   /* line e1, OR points a,b                      */
#define SH_VERTICAL       4   /* line e1, OR points a,b                      */
#define SH_PARALLEL       5   /* lines e1,e2                                 */
#define SH_PERPENDICULAR  6   /* lines e1,e2                                 */
#define SH_COLLINEAR      7   /* lines e1,e2                                 */
#define SH_CONCENTRIC     8   /* circles/arcs e1,e2                          */
#define SH_EQUAL          9   /* e1,e2 (two lines or two circles/arcs)       */
#define SH_TANGENT        10  /* e1,e2 (arc/circle + line, or two curves)    */
#define SH_SYMMETRIC      11  /* points a,b about line e1                    */
#define SH_MIDPOINT       12  /* point a is midpoint of line e1              */
#define SH_DISTANCE       13  /* |a b| = val                                 */
#define SH_DIST_X         14  /* |a.x - b.x| = val                           */
#define SH_DIST_Y         15  /* |a.y - b.y| = val                           */
#define SH_DIAMETER       16  /* circle e1 diameter = val                    */
#define SH_RADIUS         17  /* circle/arc e1 radius = val                  */
#define SH_ANGLE          18  /* angle(line e1, line e2) = val degrees       */
#define SH_DRAGGED        19  /* soft-pin point a where it is (grip drag)    */

#define SH_RESULT_OKAY               0
#define SH_RESULT_INCONSISTENT       1
#define SH_RESULT_DIDNT_CONVERGE     2
#define SH_RESULT_TOO_MANY_UNKNOWNS  3

/* Encode/decode an entity reference. */
#define SH_ENT(kind, idx) ((kind) * 100000000 + (idx))

/*
 * Solve a sketch.
 *
 *  nPts, px[], py[]   : point coordinates (updated IN PLACE on success)
 *  fixed[]            : per-point; nonzero => point is locked in place
 *                       (Fix constraint / already-solved geometry)
 *  nLines, la[], lb[] : line k joins point la[k] to point lb[k]
 *  nCircles, cc[], cr[]: circle k centered at point cc[k], radius cr[k]
 *                       (radius updated in place)
 *  nArcs, ac[],as_[],ae[], ar[] : arc k center ac[k], start as_[k], end ae[k];
 *                       ar[] radius updated in place
 *  nCons, ct[], ca[], cb[], ce1[], ce2[], cval[] : constraint records
 *  dofOut            : receives remaining degrees of freedom (>=0)
 *  failed[], failedCap: on inconsistency, receives indices of the offending
 *                       constraints; return value = number written
 *
 * returns: solver result code (SH_RESULT_*). Points/radii are only meaningful
 *          when the result is OKAY.
 */
int slvs_solve(
    int nPts, double *px, double *py, const int *fixed,
    int nLines, const int *la, const int *lb,
    int nCircles, const int *cc, double *cr,
    int nArcs, const int *ac, const int *as_, const int *ae, double *ar,
    int nCons, const int *ct, const int *ca, const int *cb,
    const int *ce1, const int *ce2, const double *cval,
    int *dofOut, int *failed, int failedCap);

/* Library version probe, so the Dart side can confirm the symbol is linked. */
int slvs_shim_version(void);

#ifdef __cplusplus
}
#endif
#endif
