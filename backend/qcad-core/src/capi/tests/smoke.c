/*
 * iPadProCAD — C-ABI smoke test (pure C).
 *
 * Verifies that:
 *   1. qcad_capi.h is valid C and the symbols have C linkage,
 *   2. the wrapper links against the whole static QCAD core,
 *   3. entities can be created, counted and bounded,
 *   4. a DXF round-trip (save -> load) preserves the entity count.
 *
 * Deliberately does NOT touch spline geometry (R_NO_OPENNURBS) or snap (M5).
 */
#include "qcad_capi.h"

#include <math.h>
#include <stdio.h>

static int g_failures = 0;

#define CHECK(cond, msg)                                                       \
    do {                                                                       \
        if (cond) {                                                            \
            printf("ok:   %s\n", (msg));                                       \
        } else {                                                               \
            printf("FAIL: %s\n", (msg));                                       \
            g_failures++;                                                      \
        }                                                                      \
    } while (0)

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    qcad_init();
    printf("version: %s\n", qcad_version());

    qcad_document *doc = qcad_document_new();
    CHECK(doc != NULL, "create document");
    if (doc == NULL) {
        return 1;
    }

    CHECK(qcad_add_line(doc, 0.0, 0.0, 100.0, 50.0), "add line");
    CHECK(qcad_add_circle(doc, 50.0, 50.0, 25.0), "add circle");
    CHECK(qcad_add_arc(doc, 0.0, 0.0, 40.0, 0.0, M_PI / 2.0, 0), "add arc");

    const double pts[] = {0.0, 0.0, 10.0, 0.0, 10.0, 10.0, 0.0, 10.0};
    CHECK(qcad_add_polyline(doc, pts, 4, 1), "add closed polyline");

    const int n = qcad_entity_count(doc);
    printf("entity count: %d\n", n);
    CHECK(n == 4, "entity count == 4");

    double minx = 0, miny = 0, maxx = 0, maxy = 0;
    const int has_box = qcad_bounding_box(doc, &minx, &miny, &maxx, &maxy);
    CHECK(has_box, "bounding box valid");
    if (has_box) {
        printf("bbox: [%.3f, %.3f] .. [%.3f, %.3f]\n", minx, miny, maxx, maxy);
    }

    const char *path = "/tmp/ipadprocad_smoke.dxf";
    CHECK(qcad_save_dxf(doc, path, NULL), "save DXF (default R2000)");

    qcad_document *reloaded = qcad_document_new();
    CHECK(reloaded != NULL, "create second document");
    CHECK(qcad_load_dxf(reloaded, path), "load DXF");
    const int n2 = qcad_entity_count(reloaded);
    printf("reloaded entity count: %d\n", n2);
    CHECK(n2 == 4, "DXF round-trip preserves entity count");

    qcad_document_free(reloaded);
    qcad_document_free(doc);

    if (g_failures == 0) {
        printf("\nSMOKE: PASS\n");
        return 0;
    }
    printf("\nSMOKE: FAIL (%d failing checks)\n", g_failures);
    return 1;
}
