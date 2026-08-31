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

/* Is there a device to render on? 0 when Cycles found none, which on iOS means
 * neither Metal nor the CPU fallback came up. */
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
