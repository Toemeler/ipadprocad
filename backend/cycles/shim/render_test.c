/* M322 — a render that is actually checked, on a machine that is not an iPad.
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * WHY THIS EXISTS
 *
 * Every change to the shim so far has shipped untested. The Dart tests use a
 * fake renderer, the iOS probe proves only that the code compiles and links,
 * and the first machine ever to CALL cy_render was a user's iPad — where a
 * null dereference in the world setup (M321) took the app down at launch. That
 * bug was three lines of C++ and would have been caught in seconds by running
 * the thing once.
 *
 * So: a host build renders a known scene and checks the pixels. It does not
 * test iOS — it cannot — but the crash was in scene construction, camera
 * setup and the output driver, which are the same code on every platform.
 *
 * WHAT IT CHECKS, and why each one is a bug that has a name:
 *
 *   * the call returns at all, and reports success;
 *   * the image is not uniform. A black frame is what a scene with no world
 *     shader produces (M309), and a frame that is entirely background is what
 *     geometry silently dropped on the floor looks like;
 *   * the object lands in the RIGHT QUADRANT. The camera convention is four
 *     things that must agree at once — the basis columns, the viewplane, the
 *     eye offset, and the output driver's vertical flip — and getting any one
 *     wrong still produces a plausible picture. A part rendered mirrored or
 *     upside down is the failure most likely to be shrugged off as "close
 *     enough" by everything except a test that knows where the triangle was.
 *
 * Exit: 0 pass, 1 fail, 2 skipped (no GPU on this machine).
 */
#include "cycles_shim.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define TW 96
#define TH 96

static int failures = 0;

static void check(int ok, const char *what)
{
  printf("%s %s\n", ok ? "  ok  " : "  FAIL", what);
  if (!ok) {
    failures++;
  }
}

/* Mean value of one channel over a quadrant, 0..255. Sampled over an area
 * rather than at a point so a single stray sample cannot decide the result.
 * channel < 0 means luminance. */
static double quadrant_ch(const unsigned char *rgba, int left, int top, int channel)
{
  const int x0 = left ? TW / 8 : TW * 5 / 8;
  const int y0 = top ? TH / 8 : TH * 5 / 8;
  double sum = 0.0;
  int n = 0;
  for (int y = y0; y < y0 + TH / 4; y++) {
    for (int x = x0; x < x0 + TW / 4; x++) {
      const unsigned char *p = rgba + ((size_t)y * TW + x) * 4;
      sum += channel < 0 ? (p[0] + p[1] + p[2]) / 3.0 : p[channel];
      n++;
    }
  }
  return n ? sum / n : 0.0;
}

static double quadrant(const unsigned char *rgba, int left, int top)
{
  const int x0 = left ? TW / 8 : TW * 5 / 8;
  const int y0 = top ? TH / 8 : TH * 5 / 8;
  double sum = 0.0;
  int n = 0;
  for (int y = y0; y < y0 + TH / 4; y++) {
    for (int x = x0; x < x0 + TW / 4; x++) {
      const unsigned char *p = rgba + ((size_t)y * TW + x) * 4;
      sum += (p[0] + p[1] + p[2]) / 3.0;
      n++;
    }
  }
  return n ? sum / n : 0.0;
}

int main(int argc, char **argv)
{
  if (argc > 1) {
    cy_set_resource_path(argv[1]);
  }

  if (!cy_available()) {
    printf("SKIP: no GPU device available (%s)\n", cy_device_name());
    return 2;
  }
  printf("device: %s\n", cy_device_name());

  /* A quad occupying the +x/+y quadrant of world space, on z = 0.
   * With the camera below looking along +z, it must appear in the TOP-RIGHT
   * of the image and nowhere else. That single fact pins both axes and the
   * output driver's flip at once. */
  const float verts[12] = {
      1.0f, 1.0f, 0.0f, 9.0f, 1.0f, 0.0f, 9.0f, 9.0f, 0.0f, 1.0f, 9.0f, 0.0f,
  };
  const int tris[6] = {0, 1, 2, 0, 2, 3};

  CyMesh mesh;
  memset(&mesh, 0, sizeof(mesh));
  mesh.verts = verts;
  mesh.vert_count = 4;
  mesh.normals = NULL;
  mesh.tris = tris;
  mesh.tri_count = 2;

  CyView view;
  memset(&view, 0, sizeof(view));
  /* Row-major 3x4. Columns 0-2 are the basis (s, u, dir), column 3 the eye —
   * exactly what cyclesCameraMatrix builds in Dart, with dir = +z. */
  view.matrix[0] = 1.0f;  /* s.x */
  view.matrix[5] = 1.0f;  /* u.y */
  /* Third column is the FORWARD direction: the eye is at z=+40 and the quad is
   * at z=0, so the camera looks along -z. Getting this sign wrong renders a
   * frame of pure background — see cycles_view.dart. */
  view.matrix[10] = -1.0f; /* forward.z */
  view.matrix[11] = 40.0f; /* eye.z */
  view.half_width = 10.0f;
  view.half_height = 10.0f;
  view.width = TW;
  view.height = TH;
  view.samples = 16;
  /* A bright uniform world: it is both the light and the background, so the
   *background reads near 0.8 and a 0.8-albedo surface under it reads near
   * 0.64. Distinguishable without being a knife edge. */
  view.world[0] = view.world[1] = view.world[2] = 0.8f;

  unsigned char *rgba = (unsigned char *)calloc((size_t)TW * TH * 4, 1);
  if (rgba == NULL) {
    printf("FAIL: out of memory\n");
    return 1;
  }

  const int ok = cy_render(&mesh, 1, &view, rgba);
  check(ok == 1, "cy_render reports success");
  if (!ok) {
    printf("  error: %s\n", cy_last_error());
    free(rgba);
    return 1;
  }

  const double tr = quadrant(rgba, 0, 1);
  const double tl = quadrant(rgba, 1, 1);
  const double br = quadrant(rgba, 0, 0);
  const double bl = quadrant(rgba, 1, 0);
  printf("quadrants: TL=%.1f TR=%.1f BL=%.1f BR=%.1f\n", tl, tr, bl, br);

  /* Not black. A scene whose world shader was never built renders black on a
   * device that worked perfectly, with no error anywhere. */
  check(tl > 20.0, "the background is lit, not black");

  /* Not uniform. Geometry that never reached the scene leaves a frame that is
   * entirely background and otherwise looks fine. */
  check(tr < tl - 10.0, "the object is visibly darker than the background");

  /* And it is in the right corner. */
  check(tl > tr + 10.0, "top-left is background, not object");
  check(bl > tr + 10.0, "bottom-left is background (vertical flip is right)");
  check(br > tr + 10.0, "bottom-right is background (horizontal axis is right)");

  /* The kernels are compiled by now, by definition. */
  check(cy_kernels_ready() == 1, "cy_kernels_ready is set after a render");

  /* ---- and now the materials -------------------------------------------
   *
   * Two quads, one red and one blue, in the left and right halves. Before
   * M323 every body in the scene was handed scene->default_surface, so an
   * aluminium bracket and a copper bus-bar came out the same grey — a render
   * of somebody else's model. The check is per CHANNEL, because a bug that
   * makes both bodies the same colour still passes any luminance test. */
  /* Full height, so the sampled quadrants sit wholly inside one body or the
   * other and a partial-coverage average cannot soften the verdict. */
  const float lverts[12] = {
      -9.0f, -9.0f, 0.0f, -1.0f, -9.0f, 0.0f, -1.0f, 9.0f, 0.0f, -9.0f, 9.0f, 0.0f,
  };
  const float rverts[12] = {
      1.0f, -9.0f, 0.0f, 9.0f, -9.0f, 0.0f, 9.0f, 9.0f, 0.0f, 1.0f, 9.0f, 0.0f,
  };
  CyMesh two[2];
  memset(two, 0, sizeof(two));
  for (int i = 0; i < 2; i++) {
    two[i].verts = i ? rverts : lverts;
    two[i].vert_count = 4;
    two[i].tris = tris;
    two[i].tri_count = 2;
    two[i].has_material = 1;
    two[i].roughness = 0.5f;
    two[i].metallic = 0.0f;
  }
  two[0].color[0] = 0.6f; /* left: red */
  two[1].color[2] = 0.6f; /* right: blue */

  unsigned char *mat = (unsigned char *)calloc((size_t)TW * TH * 4, 1);
  if (mat == NULL) {
    printf("FAIL: out of memory\n");
    free(rgba);
    return 1;
  }
  const int ok2 = cy_render(two, 2, &view, mat);
  check(ok2 == 1, "a two-material scene renders");
  if (ok2) {
    const double lr = quadrant_ch(mat, 1, 1, 0), lb = quadrant_ch(mat, 1, 1, 2);
    const double rr = quadrant_ch(mat, 0, 1, 0), rb = quadrant_ch(mat, 0, 1, 2);
    printf("left R=%.1f B=%.1f | right R=%.1f B=%.1f\n", lr, lb, rr, rb);
    check(lr > lb + 10.0, "the red body is red");
    check(rb > rr + 10.0, "the blue body is blue");
    check(lr > rr + 10.0, "the two bodies are not the same colour");
  }
  free(mat);

  free(rgba);
  printf(failures ? "RENDER TEST: FAIL (%d)\n" : "RENDER TEST: PASS (%d failures)\n",
         failures);
  return failures ? 1 : 0;
}
