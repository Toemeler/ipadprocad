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
 *   * the background comes out sRGB-ENCODED. Writing linear radiance into a
 *     byte that is then drawn as sRGB (M332) is invisible to every check that
 *     compares one region against another, because it darkens both;
 *   * SHADING DEPENDS ON THE NORMAL. This is the one that would have caught
 *     the version of this renderer that had no lights at all: under a uniform
 *     world every unoccluded diffuse surface has the same radiance whichever
 *     way it faces, so a part renders as a flat silhouette. Two surfaces that
 *     differ ONLY in their normal must not come out the same tone;
 *   * the object lands in the RIGHT QUADRANT. The camera convention is four
 *     things that must agree at once — the basis columns, the viewplane, the
 *     eye offset, and the output driver's vertical flip — and getting any one
 *     wrong still produces a plausible picture. A part rendered mirrored or
 *     upside down is the failure most likely to be shrugged off as "close
 *     enough" by everything except a test that knows where the triangle was.
 *
 *   * M344: THE DENOISER DOES NOT BLUR AN EDGE. It is the property the whole
 *     filter turns on and the one nobody can eyeball on a device: a filter
 *     that removes noise and also removes the chamfer is worse than no filter.
 *     Checked here on hand-made buffers, with no GPU involved at all, which is
 *     why cycles_denoise.cpp names no Cycles type;
 *   * M344: THE LIVE SESSION PRODUCES FRAMES. cy_live_* is the path the app
 *     actually uses, and until this it had never been called by anything.
 *
 * Exit: 0 pass, 1 fail, 2 skipped (no GPU on this machine).
 */
#include "cycles_shim.h"
#include "cycles_denoise.h"

#include <math.h>
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
    /* Either backend: the workflow renders on the CPU device (see its Render
     * step for why), a developer running this by hand gets Metal. */
    printf("SKIP: no render device available (%s)\n", cy_device_name());
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
  mesh.material = -1; /* the renderer's own steel */

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

  /* The world, LINEAR. Since M332 this is the background the CAMERA sees and
   * only a small ambient on the surfaces; the light comes from the fixed rig
   * in the shim. 0.8 linear is a bright background at sRGB 231, which is what
   * the encode check below is written against.
   *
   * M344 moved it out of CyView and into CyEnv, with no HDRI, which is the
   * configuration a build without the optional asset set renders in — so this
   * test covers exactly what ships by default. */
  CyEnv env;
  memset(&env, 0, sizeof(env));
  env.world[0] = env.world[1] = env.world[2] = 0.8f;
  env.ambient = 0.15f;
  env.rig = 1.0f;
  env.hdri_strength = 1.0f;

  unsigned char *rgba = (unsigned char *)calloc((size_t)TW * TH * 4, 1);
  if (rgba == NULL) {
    printf("FAIL: out of memory\n");
    return 1;
  }

  const int ok = cy_render(&mesh, 1, NULL, 0, &env, &view, rgba);
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

  /* The background is a world of LINEAR 0.8, and 0.8 linear is 231 in sRGB,
   * not 204. Writing the linear value straight into the byte — which is what
   * the driver did until M332 — is a whole-image error that no region-against-
   * region check can see, because it darkens the object by the same curve.
   * 215 sits between the two answers with room either side. */
  check(tl > 215.0, "the background is sRGB-encoded, not raw linear");

  /* Not uniform. Geometry that never reached the scene leaves a frame that is
   * entirely background and otherwise looks fine.
   *
   * DIFFERENT, not darker. Which way round it goes is a fact about the rig —
   * a face square to the key light can easily be brighter than the background
   * — and pinning the sign here would make a lighting change look like a
   * geometry failure. What the check is for is that the quad is THERE. */
  check(fabs(tr - tl) > 10.0, "the object is visibly distinct from the background");

  /* M337 — an unpainted body is STEEL, not white clay.
   *
   * The quad above has no material, so it takes the renderer's default. That
   * used to be Cycles' own default_surface: a bare Principled BSDF, base
   * colour 0.8, near white. The app's steel is 0x86898D — linear 0.25, a
   * third of the brightness — and an unpainted body is the commonest thing
   * there is, so this was what a user would see first and it did not match the
   * working view at all.
   *
   * The window is wide because the exact number depends on the rig, and narrow
   * enough to exclude both a 0.8 clay (which lands near 205 here) and a body
   * that came out black. */
  check(tr > 60.0 && tr < 175.0,
        "an unpainted body renders as the app's steel, not as white clay");

  /* And it is in the right corner.
   *
   * Stated as "the other three agree with each other and the fourth does not",
   * which pins the position without pinning whether the object is lighter or
   * darker than the background. If the quad landed in any other corner, one of
   * the three would be the object and they would stop agreeing. */
  check(fabs(tl - bl) < 6.0 && fabs(tl - br) < 6.0,
        "the three background quadrants agree with each other");
  check(fabs(tr - bl) > 10.0, "bottom-left is background (vertical flip is right)");
  check(fabs(tr - br) > 10.0, "bottom-right is background (horizontal axis is right)");

  /* The kernels are compiled by now, by definition. */
  check(cy_kernels_ready() == 1, "cy_kernels_ready is set after a render");

  /* ---- M332: does the light depend on which way a surface faces? --------
   *
   * THE TEST THIS FILE WAS MISSING. Everything above passes perfectly on a
   * renderer with no lights at all: a uniform world lights an unoccluded
   * diffuse surface to the same radiance whichever way its normal points, so
   * a part comes out as one flat tone with occlusion in the corners, and the
   * quadrant checks — which only ever ask "is this region different from that
   * one" — see nothing wrong at all.
   *
   * Two quads that are GEOMETRICALLY IDENTICAL apart from their position, and
   * differ only in the vertex normals handed to the shim: the left one tilted
   * towards the sky, the right one towards the ground. Both still face the
   * camera (positive z in the normal), so neither is back-facing and the
   * difference cannot come from one of them being culled.
   *
   * Under the rig the left quad catches the sun almost square on and the right
   * one is entirely in its own shade, lit by the headlight and the ambient
   * alone. Under a uniform world they are the same number to within noise. */
  {
    const float up_n[12] = {
        0.0f, 0.707f, 0.707f, 0.0f, 0.707f, 0.707f,
        0.0f, 0.707f, 0.707f, 0.0f, 0.707f, 0.707f,
    };
    const float down_n[12] = {
        0.0f, -0.707f, 0.707f, 0.0f, -0.707f, 0.707f,
        0.0f, -0.707f, 0.707f, 0.0f, -0.707f, 0.707f,
    };
    const float left_q[12] = {
        -9.0f, -9.0f, 0.0f, -1.0f, -9.0f, 0.0f, -1.0f, 9.0f, 0.0f, -9.0f, 9.0f, 0.0f,
    };
    const float right_q[12] = {
        1.0f, -9.0f, 0.0f, 9.0f, -9.0f, 0.0f, 9.0f, 9.0f, 0.0f, 1.0f, 9.0f, 0.0f,
    };
    CyMesh faces[2];
    memset(faces, 0, sizeof(faces));
    for (int i = 0; i < 2; i++) {
      faces[i].verts = i ? right_q : left_q;
      faces[i].vert_count = 4;
      faces[i].normals = i ? down_n : up_n;
      faces[i].tris = tris;
      faces[i].tri_count = 2;
      faces[i].material = -1;
    }

    unsigned char *lit = (unsigned char *)calloc((size_t)TW * TH * 4, 1);
    if (lit == NULL) {
      printf("FAIL: out of memory\n");
      free(rgba);
      return 1;
    }
    const int ok_lit = cy_render(faces, 2, NULL, 0, &env, &view, lit);
    check(ok_lit == 1, "a scene with per-vertex normals renders");
    if (ok_lit) {
      const double up = quadrant(lit, 1, 1);
      const double down = quadrant(lit, 0, 1);
      printf("facing up=%.1f facing down=%.1f\n", up, down);
      /* Around 223 against 149 as the rig stands. 25 is loose enough that the
       * strengths can be retuned without rewriting the test, and far tighter
       * than the zero difference a world-only renderer produces. */
      check(up > down + 25.0,
            "a surface facing the sky is brighter than one facing the ground");
    }
    free(lit);
  }

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
  CyMaterial paint[2];
  memset(two, 0, sizeof(two));
  memset(paint, 0, sizeof(paint));
  for (int i = 0; i < 2; i++) {
    two[i].verts = i ? rverts : lverts;
    two[i].vert_count = 4;
    two[i].tris = tris;
    two[i].tri_count = 2;
    /* M344: an INDEX into the material table, not a copy of the material.
     * A table entry no mesh names is a shader that is never built, and an
     * index past the end falls back to steel rather than being read. */
    two[i].material = i;
    paint[i].roughness = 0.5f;
    paint[i].metallic = 0.0f;
    paint[i].specular = 0.5f;
    paint[i].texture_scale = 1.0f;
  }
  paint[0].color[0] = 0.6f; /* left: red */
  paint[1].color[2] = 0.6f; /* right: blue */

  unsigned char *mat = (unsigned char *)calloc((size_t)TW * TH * 4, 1);
  if (mat == NULL) {
    printf("FAIL: out of memory\n");
    free(rgba);
    return 1;
  }
  const int ok2 = cy_render(two, 2, paint, 2, &env, &view, mat);
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

  /* ---- M344: the live session ------------------------------------------
   *
   * cy_live_* is the path the app uses for every frame it draws, and before
   * this test nothing had ever called it. What is checked is the contract, not
   * the picture — the picture is the same scene builder the checks above have
   * already been through:
   *
   *   * a frame comes out at all, at the size that was asked for;
   *   * polling again without waiting reports "nothing new" rather than
   *     handing back the same frame twice, which is what lets the app poll at
   *     whatever rate it likes;
   *   * it converges: sampling reaches the target and says so, rather than
   *     counting forever. `done` is Cycles' own answer and not a comparison
   *     here, because the sample count visible when a frame is captured always
   *     lags the scheduler by one work item — see FrameStore::finished.
   */
  {
    CyEnv live_env = env;
    CyView live_view = view;
    live_view.samples = 8;

    check(cy_live_open() == 1, "the live session opens");
    if (cy_live_is_open()) {
      check(cy_live_scene(&mesh, 1, NULL, 0, &live_env) == 1, "the live scene uploads");
      check(cy_live_view(&live_view) == 1, "the live camera is accepted");

      unsigned char *live = (unsigned char *)calloc((size_t)TW * TH * 4, 1);
      CyFrame info;
      memset(&info, 0, sizeof(info));
      int got = 0;
      int done = 0;
      /* Bounded: a spin that never ends is a hung CI job, and eight samples of
       * a 96x96 image is milliseconds even on a paravirtualised CPU. */
      for (int i = 0; i < 20000 && !done; i++) {
        const int r = cy_live_frame(live, TW * TH * 4, &info);
        if (r < 0) {
          printf("  live frame error: %s\n", cy_last_error());
          break;
        }
        if (r == 1) {
          got++;
        }
        done = info.done;
      }
      printf("live: %d frames, %d/%d samples, done=%d denoised=%d\n",
             got, info.samples, info.target, info.done, info.denoised);
      check(got > 0, "the live session produced at least one frame");
      check(info.width == TW && info.height == TH,
            "the live frame is the size that was asked for");
      check(done == 1, "the live session converges and says so");

      memset(&info, 0, sizeof(info));
      check(cy_live_frame(live, TW * TH * 4, &info) == 0,
            "polling again with nothing new returns no frame");

      /* The same quadrant test as the one-shot: same scene, same camera, so
       * the quad has to land in the same corner. A live session that framed
       * the model differently from cy_render would be two renderers. */
      const double ltr = quadrant(live, 0, 1);
      const double ltl = quadrant(live, 1, 1);
      check(fabs(ltr - ltl) > 10.0, "the live frame has the object in it");
      check(fabs(ltl - tl) < 25.0,
            "the live background matches the one-shot's");

      free(live);
      cy_live_close();
      check(cy_live_is_open() == 0, "the live session closes");
    }
  }

  /* ---- M344: does the denoiser keep an edge? ---------------------------
   *
   * THE ONE PROPERTY THAT DECIDES WHETHER IT MAY SHIP. Every Cycles build in
   * this repo carries a comment saying a denoiser "smears exactly the crisp
   * machined edges the render exists to show", and that objection is answered
   * by construction (albedo demodulation) rather than by hope — so it is
   * checked, on buffers built here, with no renderer involved.
   *
   * The image is two flat halves of different albedo under identical lighting,
   * with noise on top. A blur would pull the halves towards each other across
   * the seam; the filter must leave the step exactly where it was while
   * removing the noise inside each half.
   */
  {
    const int W = 64, H = 64;
    float *color = (float *)malloc((size_t)W * H * 4 * sizeof(float));
    float *albedo = (float *)malloc((size_t)W * H * 3 * sizeof(float));
    float *normal = (float *)malloc((size_t)W * H * 3 * sizeof(float));
    /* A cheap deterministic hash, so the test is the same on every machine. */
    unsigned int seed = 12345u;
    for (int y = 0; y < H; y++) {
      for (int x = 0; x < W; x++) {
        const size_t i = (size_t)y * W + x;
        const float base = x < W / 2 ? 0.8f : 0.2f;
        seed = seed * 1664525u + 1013904223u;
        const float n = ((float)((seed >> 8) & 0xFFFF) / 65535.0f - 0.5f) * 0.30f;
        for (int k = 0; k < 3; k++) {
          color[i * 4 + k] = base * 0.5f + n;
          albedo[i * 3 + k] = base;
          normal[i * 3 + k] = k == 2 ? 1.0f : 0.0f;
        }
        color[i * 4 + 3] = 1.0f;
      }
    }
    /* What the two halves should come out at, and what the seam step is. */
    const double want_left = 0.8 * 0.5, want_right = 0.2 * 0.5;

    double noise_before = 0.0;
    for (int y = 8; y < H - 8; y++) {
      for (int x = 8; x < W / 2 - 8; x++) {
        const double d = color[((size_t)y * W + x) * 4] - want_left;
        noise_before += d * d;
      }
    }

    cyshim::denoise(color, albedo, normal, W, H, 8, 1.0f, NULL);

    double noise_after = 0.0;
    for (int y = 8; y < H - 8; y++) {
      for (int x = 8; x < W / 2 - 8; x++) {
        const double d = color[((size_t)y * W + x) * 4] - want_left;
        noise_after += d * d;
      }
    }
    /* The two pixels either side of the seam. A blur would have brought them
     * together; the demodulation means the filter never saw the difference. */
    const size_t mid = (size_t)(H / 2) * W + (W / 2);
    const double left = color[(mid - 1) * 4];
    const double right = color[mid * 4];
    printf("denoise: noise %.5f -> %.5f, seam %.3f | %.3f (want %.3f | %.3f)\n",
           noise_before, noise_after, left, right, want_left, want_right);

    check(noise_after < noise_before * 0.35, "the denoiser removes most of the noise");
    check(left > want_left - 0.06 && left < want_left + 0.06,
          "the bright side keeps its own value");
    check(right > want_right - 0.06 && right < want_right + 0.06,
          "the dark side keeps its own value");
    check(left - right > 0.25, "the edge across the seam survives");

    /* And it must be OFF once the render has converged, or the picture the
     * user finally looks at would depend on a constant in cycles_denoise.cpp. */
    check(cyshim::denoise_strength_for(1, 64) == 1.0f,
          "a nearly-unsampled frame is fully denoised");
    check(cyshim::denoise_strength_for(64, 64) == 0.0f,
          "a converged frame is not denoised at all");
    check(cyshim::denoise_strength_for(48, 64) == 0.0f,
          "the fade is over well before the target");

    free(color);
    free(albedo);
    free(normal);
  }

  free(rgba);
  printf(failures ? "RENDER TEST: FAIL (%d)\n" : "RENDER TEST: PASS (%d failures)\n",
         failures);
  return failures ? 1 : 0;
}
