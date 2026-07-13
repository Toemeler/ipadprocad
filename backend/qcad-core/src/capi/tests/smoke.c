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
#include <stdlib.h>
#include <string.h>

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

    /* --- M5: geometry query (qcad_entity_ids / qcad_entity_geometry) --- */
    {
        long long ids[16];
        const int total = qcad_entity_ids(doc, NULL, 0);
        CHECK(total == 4, "entity_ids total == 4");
        const int got = qcad_entity_ids(doc, ids, 16);
        CHECK(got == 4, "entity_ids fills buffer");
        int type = -1;
        double data[64];
        /* first entity added was the line (ids ascend with insertion order) */
        int need = qcad_entity_geometry(doc, ids[0], &type, data, 64);
        CHECK(need == 4 && type == 1, "geometry: entity[0] is a line (4 doubles)");
        CHECK(fabs(data[0] - 0.0) < 1e-9 && fabs(data[2] - 100.0) < 1e-9 &&
              fabs(data[3] - 50.0) < 1e-9, "geometry: line coordinates match");
        need = qcad_entity_geometry(doc, ids[1], &type, data, 64);
        CHECK(need == 3 && type == 2 && fabs(data[2] - 25.0) < 1e-9,
              "geometry: entity[1] is circle r=25");
        need = qcad_entity_geometry(doc, ids[2], &type, data, 64);
        CHECK(need == 6 && type == 3 && fabs(data[2] - 40.0) < 1e-9,
              "geometry: entity[2] is arc r=40");
        need = qcad_entity_geometry(doc, ids[3], &type, data, 64);
        CHECK(need == 2 + 8 && type == 4 && data[0] == 1.0 && data[1] == 4.0,
              "geometry: entity[3] is closed 4-vertex polyline");
        /* sizing call: max_doubles = 0 must not write but return the need */
        need = qcad_entity_geometry(doc, ids[3], &type, NULL, 0);
        CHECK(need == 10, "geometry: sizing call (max=0) returns need");
        CHECK(qcad_entity_geometry(doc, 999999, &type, data, 64) == -1,
              "geometry: unknown id returns -1");
    }

    /* Portable temp path: an iOS / simulator sandbox has no writable /tmp, so
     * honour TMPDIR (set by the OS and by `simctl spawn`) and fall back to /tmp
     * on hosts (Linux) where it is unset. Keeps the Linux smoke behaviour. */
    char path[1024];
    const char *tmpdir = getenv("TMPDIR");
    if (tmpdir == NULL || tmpdir[0] == '\0') {
        tmpdir = "/tmp";
    }
    if (tmpdir[strlen(tmpdir) - 1] == '/') {
        snprintf(path, sizeof(path), "%sipadprocad_smoke.dxf", tmpdir);
    } else {
        snprintf(path, sizeof(path), "%s/ipadprocad_smoke.dxf", tmpdir);
    }
    printf("dxf path: %s\n", path);
    CHECK(qcad_save_dxf(doc, path, NULL), "save DXF (default R2000)");

    qcad_document *reloaded = qcad_document_new();
    CHECK(reloaded != NULL, "create second document");
    CHECK(qcad_load_dxf(reloaded, path), "load DXF");
    const int n2 = qcad_entity_count(reloaded);
    printf("reloaded entity count: %d\n", n2);
    CHECK(n2 == 4, "DXF round-trip preserves entity count");

    qcad_document_free(reloaded);
    qcad_document_free(doc);

    /* --- layer binding: regression guard for "everything lands on layer 0" ---
     * qcad_set_current_layer must make NEW entities land on that layer, and the
     * binding must survive a DXF round-trip. This shipped broken once precisely
     * because the smoke test never exercised layers: the C-API set its own
     * current-layer string but not the document's current layer, so RTransaction
     * stamped every entity with layer "0". */
    {
        qcad_document *ld = qcad_document_new();
        CHECK(ld != NULL, "layer: create document");
        CHECK(qcad_set_current_layer(ld, "Walls"), "layer: set current layer");
        CHECK(qcad_add_line(ld, 0, 0, 5, 0), "layer: add line on current layer");
        long long lids[8];
        const int ln = qcad_entity_ids(ld, lids, 8);
        CHECK(ln == 1, "layer: exactly one entity present");
        char lname[128] = {0};
        CHECK(ln == 1 && qcad_entity_layer(ld, lids[0], lname, sizeof(lname)),
              "layer: read entity layer");
        CHECK(strcmp(lname, "Walls") == 0,
              "layer: new entity is on the current layer, not \"0\"");

        char lpath[1024];
        if (tmpdir[strlen(tmpdir) - 1] == '/') {
            snprintf(lpath, sizeof(lpath), "%sipadprocad_smoke_layer.dxf", tmpdir);
        } else {
            snprintf(lpath, sizeof(lpath), "%s/ipadprocad_smoke_layer.dxf", tmpdir);
        }
        CHECK(qcad_save_dxf(ld, lpath, NULL), "layer: save DXF");

        qcad_document *lr = qcad_document_new();
        CHECK(qcad_load_dxf(lr, lpath), "layer: reload DXF");
        long long rids[8];
        const int rn = qcad_entity_ids(lr, rids, 8);
        CHECK(rn == 1, "layer: one entity after reload");
        char rname[128] = {0};
        CHECK(rn == 1 && qcad_entity_layer(lr, rids[0], rname, sizeof(rname)),
              "layer: read entity layer after reload");
        CHECK(strcmp(rname, "Walls") == 0,
              "layer: entity layer survives the DXF round-trip");
        qcad_document_free(lr);
        qcad_document_free(ld);
    }

    if (g_failures == 0) {
        printf("\nSMOKE: PASS\n");
        return 0;
    }
    printf("\nSMOKE: FAIL (%d failing checks)\n", g_failures);
    return 1;
}
