/*
 * iPadProCAD — C-ABI wrapper around the (headless) QCAD core.
 *
 * Milestone M2. Pure C interface (extern "C"), opaque handles, no C++ types at
 * the ABI boundary. Designed to be consumed from Dart FFI on iOS and from a
 * plain C smoke test on Linux.
 *
 * Conventions:
 *   - Functions returning `int` use 1 = success, 0 = failure (unless noted).
 *   - Angles are in radians.
 *   - Coordinates / lengths are doubles in drawing units.
 *   - Returned `const char*` point to storage owned by the library; the caller
 *     must not free them and must copy if they need to outlive the next call.
 */
#ifndef QCAD_CAPI_H
#define QCAD_CAPI_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Opaque document handle. */
typedef struct qcad_document qcad_document;

/*
 * One-time process initialisation: registers the QCAD property-type system and
 * ensures a QCoreApplication exists (created if the host has none, so the
 * wrapper is self-contained for headless use). Idempotent and thread-safe;
 * call it once before anything else.
 */
void qcad_init(void);

/* Human-readable version string, e.g. "iPadProCAD C-API 0.1.0 (Qt 6.4.2)". */
const char *qcad_version(void);

/* ---- Document lifecycle ---- */

/* Create a new, empty document (with default layer "0"). NULL on failure. */
qcad_document *qcad_document_new(void);

/* Release a document created by qcad_document_new(). NULL is ignored. */
void qcad_document_free(qcad_document *doc);

/* ---- Entity creation ---- */

int qcad_add_line(qcad_document *doc,
                  double x1, double y1,
                  double x2, double y2);

int qcad_add_circle(qcad_document *doc,
                    double cx, double cy, double radius);

int qcad_add_arc(qcad_document *doc,
                 double cx, double cy, double radius,
                 double start_angle, double end_angle,
                 int reversed);

/*
 * Add a polyline. `pts` is a flat array of `count` (x, y) pairs, i.e. it has
 * 2 * count doubles. `closed` != 0 closes the polyline.
 */
int qcad_add_polyline(qcad_document *doc,
                      const double *pts, size_t count,
                      int closed);

/* ---- Queries ---- */

/* Number of entities in model space. Returns -1 on error. */
int qcad_entity_count(const qcad_document *doc);

/*
 * Bounding box of all entities. Writes minx/miny/maxx/maxy on success.
 * Returns 1 if a valid box was produced (document non-empty), else 0.
 * Any out-pointer may be NULL if that component is not needed.
 */
int qcad_bounding_box(const qcad_document *doc,
                      double *out_minx, double *out_miny,
                      double *out_maxx, double *out_maxy);

/*
 * List entity ids. Writes up to `max` ids (ascending) into `out_ids` (may be
 * NULL if max is 0). Returns the TOTAL number of entities (call once with
 * max=0 to size the buffer), or -1 on error.
 */
int qcad_entity_ids(const qcad_document *doc, long long *out_ids, int max);

/*
 * Geometry of one entity for rendering (M5).
 *
 * Entity type is written to *out_type:
 *   1 = line      data: x1, y1, x2, y2                       (4 doubles)
 *   2 = circle    data: cx, cy, r                            (3 doubles)
 *   3 = arc       data: cx, cy, r, start, end, reversed(0/1) (6 doubles)
 *   4 = polyline  data: closed(0/1), n, x1, y1, ... xn, yn   (2 + 2n doubles)
 *   0 = other/unsupported (no data written)
 *
 * Writes at most `max_doubles` into `out_data` and returns the number of
 * doubles the full geometry requires (call with max_doubles=0 to size the
 * buffer). Returns -1 on error (unknown id, NULL doc/out_type).
 */
int qcad_entity_geometry(const qcad_document *doc, long long id,
                         int *out_type, double *out_data, int max_doubles);

/* ---- DXF I/O ---- */

/* Load a DXF file from `path` into `doc` (adds to existing content). */
int qcad_load_dxf(qcad_document *doc, const char *path);

/*
 * Save `doc` to a DXF file at `path`.
 * `version` may be NULL/"" (defaults to R2000/AC1015), "R12", or "min".
 */
int qcad_save_dxf(qcad_document *doc, const char *path, const char *version);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* QCAD_CAPI_H */
