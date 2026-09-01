/* M296 — the C surface of the Cycles renderer, for FFI.
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * Cycles is Apache-2.0 (intern/cycles), relicensed in 2013 precisely so it can
 * be linked into other applications. Only that tree is used here; nothing from
 * Blender proper, which is GPL, is touched.
 *
 * Deliberately narrow. Everything the app already has — triangle soup, vertex
 * normals, an orthographic camera — goes in; RGBA8 comes out. No shader graphs,
 * no lights, no scene format: see cycles_shim.cpp for why the first version is
 * a clay render under a uniform world.
 *
 * BLOCKING. One call renders one image and returns when it is done. The caller
 * runs it off the UI thread; a progressive display driver is a later question
 * and would change this file's shape, not the app's.
 */
#ifndef CYCLES_SHIM_H
#define CYCLES_SHIM_H

#ifdef __cplusplus
extern "C" {
#endif

/* One mesh, in the coordinates the app already keeps. */
typedef struct {
  const float *verts;   /* xyz per vertex, 3 * vert_count floats */
  int vert_count;
  const float *normals; /* xyz per vertex, or NULL for flat shading */
  const int *tris;      /* 3 indices per triangle */
  int tri_count;

  /* The body's appearance, or 0 for the renderer's default steel.
   *
   * A flag rather than a sentinel colour, because black is a colour a body may
   * legitimately be and "no material" has to stay distinguishable from it —
   * the same distinction materialArgb() draws on the Dart side by returning
   * null instead of a steel-coloured value. */
  int has_material;
  /* Base colour, LINEAR 0..1, not sRGB. The conversion happens in Dart, where
   * it can be tested; a renderer handed sRGB values renders everything too
   * bright and washed out in a way that looks like a lighting problem. */
  float color[3];
  float roughness; /* 0 mirror-smooth .. 1 fully rough */
  float metallic;  /* 0 dielectric .. 1 metal */
} CyMesh;

/* The view, and how hard to work on it. */
typedef struct {
  /* Camera-to-world, ROW-MAJOR 3x4 — the same twelve numbers PlaneFrame.mat34
   * hands the kernel. Cycles looks down -Z with +Y up (Blender's convention),
   * so the caller composes the basis; this file does not guess it. */
  float matrix[12];
  /* Orthographic half-extents in world units. The app's camera is
   * orthographic and always has been; a perspective mode would be a second
   * field here, not a second entry point. */
  float half_width;
  float half_height;
  int width;
  int height;
  int samples;
  /* Uniform world colour. The whole light rig, for now. */
  float world[3];
} CyView;

/* Is there a GPU to render on? 0 when no Metal device came up.
 *
 * METAL OR NOTHING. There is a CPU device in Cycles and this deliberately does
 * not use it: the same image that takes an iPad's GPU a few seconds takes its
 * CPU minutes, and a rendered mode that silently becomes a four-minute wait is
 * worse than one that says it cannot run. If there is no Metal device, there
 * is no renderer. */
int cy_available(void);

/* Human-readable device description, for the log and the bug report. Never
 * null; "none" when there is no device. */
const char *cy_device_name(void);

/* Where the Cycles KERNEL SOURCE lives.
 *
 * Not optional on Metal. The Metal device compiles its kernels at runtime from
 * `<path>/source/kernel/device/metal/kernel.metal` and everything that
 * includes — device_impl.mm does `path_source_replace_includes(source,
 * path_get("source"))` — so the kernel tree has to be inside the app bundle and
 * this has to point at it before the first render. Called once at startup.
 */
void cy_set_resource_path(const char *path);

/* Compiles the Metal kernels, and nothing else.
 *
 * The Metal backend has no precompiled kernels; it builds them from the source
 * above, on the device, and that is tens of seconds to minutes the first time.
 * Afterwards the result is in a binary archive on disk and a launch costs
 * nothing. So this exists to get that over with AT STARTUP, in the background,
 * rather than the first time somebody switches to rendered mode and watches a
 * spinner for two minutes.
 *
 * It is a real render — a single sample of a single triangle at 32x32 — because
 * that is what makes Cycles walk its own load_kernels path and populate the
 * archive. Anything less compiles a different set of kernels than the one the
 * app will use.
 *
 * BLOCKING, for minutes on a cold install. Call it off the UI thread. Returns 1
 * when the device is ready to render. */
int cy_preload(void);

/* 1 once cy_preload has succeeded in this process. Cheap; call it freely. */
int cy_kernels_ready(void);

/* What Cycles is doing right now, copied into [out] as a NUL-terminated string.
 *
 * Cycles' own progress status, which during a cold start is the sentence
 * "Loading render kernels (may take a few minutes the first time)" and during a
 * render is the sample count. Readable from any thread and from any isolate —
 * it is one process, and this is a mutex-guarded copy rather than a pointer
 * into a std::string that another thread is writing. */
void cy_status(char *out, int len);

/* How far along, 0..1, or -1 when nothing is running. */
float cy_progress(void);

/* Render [meshes] from [view] into [rgba_out], which must hold
 * width * height * 4 bytes. Returns 1 on success, 0 on failure; the reason is
 * in cy_last_error(). */
int cy_render(const CyMesh *meshes,
              int mesh_count,
              const CyView *view,
              unsigned char *rgba_out);

/* Why the last call failed. Never null. */
const char *cy_last_error(void);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* CYCLES_SHIM_H */
