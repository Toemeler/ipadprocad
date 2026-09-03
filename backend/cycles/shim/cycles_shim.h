/* M344 — the C surface of the Cycles renderer, for FFI.
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * Cycles is Apache-2.0 (intern/cycles), relicensed in 2013 precisely so it can
 * be linked into other applications. Only that tree is used here; nothing from
 * Blender proper, which is GPL, is touched.
 *
 * ---------------------------------------------------------------------------
 * WHAT CHANGED IN M344, AND WHY THE FILE HAS TWO HALVES NOW
 * ---------------------------------------------------------------------------
 *
 * Until M343 this header described one thing: `cy_render`, which built a
 * scene, traced it to a fixed sample count, and returned. One call, one image,
 * seconds of block. That is a PHOTOGRAPH of the model, and rendered mode was
 * built around its shape — hold still for 450 ms, wait, get a picture, lose it
 * the instant you touch the camera.
 *
 * What the mode actually wants is a VIEWPORT: a path tracer that is always
 * running, that follows the camera through an orbit, and that keeps refining
 * whatever is on screen until it is clean. Cycles has been able to do that
 * since 2011 — it is what Blender's rendered viewport is — and the only reason
 * this shim could not was that its session was created and destroyed per call.
 *
 * So there are two halves:
 *
 *   THE LIVE SESSION (cy_live_*) — one resident Session, one resident Scene.
 *   Geometry is uploaded when it changes; the camera is twelve floats and can
 *   change every frame; frames are pulled out as they converge. This is what
 *   the app uses.
 *
 *   THE ONE-SHOT (cy_render) — unchanged in behaviour, now implemented over
 *   the same scene builder. It is what cy_preload warms the kernels with and
 *   what the host render test checks the pixels of, and keeping it means every
 *   material, light and camera change is still exercised by a test that runs
 *   on every push.
 *
 * Neither may run while the other does; both take the same lock, so a caller
 * that tries simply waits.
 *
 * ---------------------------------------------------------------------------
 * M367 — HOW THE IMAGE ARRIVES, AND HOW IT ENDS
 * ---------------------------------------------------------------------------
 *
 * EVERY SAMPLE IS A FRAME. Cycles' RenderScheduler sizes a work packet from
 * the measured sample rate times a display-update interval that climbs to two
 * seconds, so a render that has been going for a while traces a hundred
 * samples and then shows one frame — 24, then 50, then 100. The live session
 * asks it for one sample per work item instead, and for a display update after
 * each, so the picture builds continuously. That knob is added to Cycles by
 * backend/cycles/patches/progressive.py; a tree without the patch still
 * compiles and still renders, in Cycles' own steps.
 *
 * AND THEN IT IS DENOISED, ONCE. When sampling stops — at CyView.samples, or
 * wherever adaptive sampling decided the image was done — the frame is
 * denoised and CyFrame.denoised says so. Where the build has
 * OpenImageDenoise, that is Cycles' own denoiser doing it inside the render,
 * exactly as Blender does; where it does not, it is the a-trous filter in
 * cycles_denoise.cpp, run here, once. cy_denoiser_name says which.
 *
 * ---------------------------------------------------------------------------
 * THE ONE THING THAT IS NOT OPTIONAL
 * ---------------------------------------------------------------------------
 *
 * The Metal device compiles its kernels FROM SOURCE at runtime, so
 * intern/cycles/kernel has to be inside the app bundle and
 * cy_set_resource_path must point at its parent before the first render. An
 * app that ships the libraries and not the kernel tree links, launches, and
 * fails at the first render with nothing that names the cause.
 */
#ifndef CYCLES_SHIM_H
#define CYCLES_SHIM_H

#ifdef __cplusplus
extern "C" {
#endif

/* ---------------------------------------------------------------------------
 * A SURFACE
 * ---------------------------------------------------------------------------
 *
 * M344 — a TABLE, indexed by the meshes, rather than a copy per mesh.
 *
 * It used to be five numbers carried inside CyMesh and deduplicated on the way
 * in by hashing them. That worked while an appearance WAS five numbers. It
 * stops working the moment one carries texture paths: an assembly of four
 * hundred pieces drawn from six appearances would push four hundred copies of
 * six strings across the boundary, and the shim would hash them to find out
 * what the caller already knew.
 *
 * So the caller sends its material list once and each mesh names an index.
 * One Shader per entry, built once, shared by every mesh that points at it.
 *
 * COLOUR IS LINEAR, 0..1, NEVER sRGB. The conversion happens in Dart, where it
 * can be tested; a renderer handed sRGB values renders everything too bright
 * and washed out in a way that looks like a lighting problem.
 *
 * TEXTURE PATHS ARE ABSOLUTE, or NULL, or empty. The caller resolves them —
 * it is the half that knows the bundle layout and can check a file exists
 * before promising it. A path that does not resolve is not an error here: the
 * image simply does not load, and the surface falls back to its flat numbers,
 * which is exactly the behaviour a build shipped without the optional texture
 * set needs.
 */
typedef struct {
  /* Base colour, LINEAR 0..1. Multiplied by base_map when there is one. */
  float color[3];
  float roughness; /* 0 mirror-smooth .. 1 fully rough */
  float metallic;  /* 0 dielectric .. 1 metal */

  /* M344 — the four parameters that separate a rendered part from a coloured
   * one, all of them Principled BSDF inputs the shim was leaving at default.
   *
   * specular      IOR level. 0.5 is an ordinary dielectric (IOR 1.45); higher
   *               tightens and brightens the specular, which is what makes a
   *               polished surface read as polished rather than as pale.
   * coat          Clear-coat weight. A painted or anodised part is a pigment
   *               under a thin smooth layer, and that second, sharper
   *               highlight sitting on top of the diffuse one is most of what
   *               makes paint look like paint instead of like plastic.
   * coat_roughness  How soft that second highlight is.
   * anisotropy    -1..1. Brushed and turned metal reflect along the grain, not
   *               in a circle. Cycles takes the tangent from the mesh, so this
   *               is only meaningful where the caller supplied one; left at 0
   *               it costs nothing.
   * sheen         The soft rim a fabric or a bead-blasted finish has.
   */
  float specular;
  float coat;
  float coat_roughness;
  float anisotropy;
  float sheen;

  /* Emission, LINEAR. Zero for everything the app currently paints; here
   * because a lit indicator or a screen is a body like any other and adding it
   * later would be another struct revision on both sides. */
  float emission[3];
  float emission_strength;

  /* The texture set. NULL or "" for none.
   *
   * BOX PROJECTED IN OBJECT SPACE, not UV mapped, because a CAD tessellation
   * has no UVs and never will — it is regenerated from the B-rep every time
   * the model changes, and there is nowhere for a UV layout to live between
   * one tessellation and the next. Box projection needs no layout at all: the
   * texture is projected down whichever axis a face most nearly faces, and the
   * three projections are cross-faded over the corner. On a machined part,
   * whose faces are overwhelmingly axis-aligned planes and cylinders, the
   * result is indistinguishable from a proper unwrap.
   *
   * WHY bump_map AND NOT normal_map. A tangent-space normal map needs a
   * tangent frame, and a tangent frame needs UVs — the very thing box
   * projection exists to avoid. There is no single correct tangent for a
   * triplanar projection: each of the three projections has its own. A HEIGHT
   * map has no such problem. Cycles' BumpNode differentiates the height field
   * numerically, in world space, by evaluating the same shader at two offset
   * positions, so it inherits whatever projection the height came through and
   * is correct for all three at once.
   *
   * That is not a lesser feature. Machining marks, knurling, cast texture,
   * bead blasting and brushed grain are all height fields, and a height field
   * is what a PBR set's `height`/`displacement` map already is. */
  const char *base_map;
  const char *roughness_map;
  const char *metallic_map;
  const char *bump_map;
  const char *ao_map;

  /* How many WORLD UNITS one tile of the texture covers.
   *
   * In world units rather than as a repeat count, because the bodies are real
   * objects at real sizes: a brushed finish is a fixed physical scale, and a
   * bracket and the plate it bolts to must show the same grain. A repeat count
   * would make the small part's grain coarse and the big part's fine, which is
   * the single most common way a triplanar setup announces itself as fake. */
  float texture_scale;

  /* Bump strength 0..1 and the relief in WORLD UNITS, i.e. how far the white
   * end of the height map stands above the black end. Both ignored when there
   * is no bump_map. */
  float bump_strength;
  float bump_distance;
} CyMaterial;

/* One mesh, in the coordinates the app already keeps. */
typedef struct {
  const float *verts;   /* xyz per vertex, 3 * vert_count floats */
  int vert_count;
  const float *normals; /* xyz per vertex, or NULL for flat shading */
  const int *tris;      /* 3 indices per triangle */
  int tri_count;

  /* Index into the material table, or -1 for the renderer's own steel.
   *
   * A negative index rather than a sentinel material, because the ABSENCE of a
   * material has to stay distinguishable from a material that happens to be
   * steel-coloured — the same distinction materialArgb() draws on the Dart
   * side by returning null. An index past the end of the table is treated as
   * -1 rather than read. */
  int material;
} CyMesh;

/* The world the model sits in.
 *
 * ---------------------------------------------------------------------------
 * M344 — WHY AN HDRI IS THE SINGLE BIGGEST THING IN THIS FILE
 * ---------------------------------------------------------------------------
 *
 * Four directional lights and a dim ambient (M332) is a rig, and a rig is what
 * a rasteriser has to use because it cannot integrate an environment. A path
 * tracer can. What separates a render that looks rendered from one that looks
 * PHOTOGRAPHED is almost entirely what the specular reflects: under four point
 * directions a polished surface shows four hard dots and black everywhere
 * else, which is why metal under an analytic rig always looks like grey
 * plastic. Under a real captured environment it shows a room — a softbox, a
 * window, a horizon — and the eye reads that instantly as a real object on a
 * real table.
 *
 * So when an HDRI is present it becomes the light, and the rig drops to a
 * fraction of itself: enough key to keep the contact shadow crisp and
 * directional, since a pure environment gives soft shadows only and a CAD part
 * wants to look like it is RESTING on something.
 *
 * THE BACKGROUND AND THE LIGHT STAY SEPARATE, which is the trick that lets
 * this ship. `world` is the app's own viewport colour, and by default that is
 * still what the camera sees — so a path-traced image lands on exactly the
 * ground the rest of the app is drawing, while being lit by a studio. Set
 * hdri_visible to show the environment itself instead, which is what a
 * presentation shot wants and a working viewport does not.
 */
typedef struct {
  /* An equirectangular .hdr or .exr, absolute path, or NULL for none. */
  const char *hdri;
  /* Multiplier on the environment's own values. 1 is the map as captured. */
  float hdri_strength;
  /* Turn the environment about the world's up axis, radians. The one control
   * that matters on a studio HDRI: it aims the softbox. */
  float hdri_rotation;
  /* 1 to show the environment behind the model, 0 to light with it only and
   * leave `world` as the visible background. */
  int hdri_visible;

  /* The viewport's own background, LINEAR 0..1. */
  float world[3];
  /* What fraction of `world` the SURFACES see, when there is no HDRI. A
   * uniform environment at full strength swamps any rig and flattens the
   * model; see the note in cycles_shim.cpp. Ignored once an HDRI is loaded,
   * which lights the scene properly. */
  float ambient;
  /* 0..1 on the four analytic lights. 1 with no HDRI, a fraction with one. */
  float rig;
} CyEnv;

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
  /* Where sampling STOPS, and what the denoiser waits for.
   *
   * Not how long one call takes — the live session converges towards this and
   * then idles, and the caller reads frames out of it the whole way. Since
   * M367 it arrives one sample at a time: every sample is a frame the caller
   * can pull out, rather than the 24 -> 50 -> 100 jumps Cycles' own display
   * cadence produces.
   *
   * It is also the denoiser's start sample, so the finished frame — this
   * count, or wherever adaptive sampling decided it had converged, whichever
   * comes first — is the one that gets filtered. Everything before it is the
   * raw path trace. */
  int samples;
} CyView;

/* What came out of cy_live_frame. */
typedef struct {
  int width;
  int height;
  /* How many samples the frame averages, and the target it is heading for. */
  int samples;
  int target;
  /* 1 once sampling has reached the target and the picture will not improve. */
  int done;
  /* M367 — 1 when this frame HAS BEEN DENOISED, which is the finished frame
   * and no other.
   *
   * The sense is the opposite of what it was. Until M353 the filter ran on
   * every frame and faded OUT as samples climbed, so this flag meant "still
   * being smoothed, not yet the real thing". It now means the render is over
   * and this is the finished picture: sampling stopped, and the noise left in
   * it was removed in one pass. Which denoiser did it is cy_denoiser_name. */
  int denoised;
} CyFrame;

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

/* Which denoiser finishes a render in THIS build. Never null.
 *
 * "OpenImageDenoise" — Cycles' own, and the one Blender uses. Enabled by
 * Integrator::set_use_denoise and run by Cycles as the last work item of the
 * render, so what comes out of cy_live_frame on a finished frame is already
 * the denoised image.
 *
 * "a-trous" — the edge-avoiding wavelet filter in cycles_denoise.cpp, run by
 * the shim on the finished frame. It is what a build gets when its dependency
 * set has no OIDN, which is every iOS build so far: `lib/ios_arm64` does not
 * ship the library, so `-DWITH_OPENIMAGEDENOISE=OFF` is in every iOS Cycles
 * build here. See the note in cycles_denoise.h.
 *
 * Worth showing next to the device name for the same reason the device name is
 * worth showing: a render that looks different on two machines should not need
 * a build inspection to find out why. */
const char *cy_denoiser_name(void);

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
 * width * height * 4 bytes. BLOCKING until the sample count is reached.
 *
 * The one-shot path. Same picture the live session converges to, produced in
 * one call, for the warm-up and for the host render test.
 *
 * Returns 1 on success, 0 on failure; the reason is in cy_last_error(). */
int cy_render(const CyMesh *meshes,
              int mesh_count,
              const CyMaterial *materials,
              int material_count,
              const CyEnv *env,
              const CyView *view,
              unsigned char *rgba_out);

/* ---------------------------------------------------------------------------
 * THE LIVE SESSION
 * ---------------------------------------------------------------------------
 *
 * Thread affinity: every cy_live_* call may come from any thread, but they are
 * serialised against each other and against cy_render by one lock. The app
 * calls them all from one worker isolate, which is the arrangement they are
 * written for.
 *
 * The usual order is open, scene, view, then frame in a loop, with a fresh
 * view whenever the camera moves and a fresh scene whenever the model does.
 */

/* Bring up the resident session. Idempotent; returns 1 when it is up.
 *
 * Cheap on a warm process and minutes on a cold one, for the same reason
 * cy_preload is: the first session on a device compiles the Metal kernels.
 * Call it where cy_preload is called, or after it. */
int cy_live_open(void);

/* Tear it down and give the GPU memory back. Safe to call when not open. */
void cy_live_close(void);

/* 1 when the live session is up. */
int cy_live_is_open(void);

/* Replace the geometry, the materials and the world.
 *
 * EXPENSIVE — it rebuilds every mesh and re-uploads it, which is the cost the
 * caller is avoiding by not calling this when only the camera moved. Sampling
 * restarts from zero. */
int cy_live_scene(const CyMesh *meshes,
                  int mesh_count,
                  const CyMaterial *materials,
                  int material_count,
                  const CyEnv *env);

/* Point the camera somewhere else, or change the image size or the target
 * sample count. Cheap; sampling restarts from zero. */
int cy_live_view(const CyView *view);

/* Copy the most recent frame into [rgba_out], which must hold at least
 * [capacity] bytes, and describe it in [info].
 *
 * Returns 1 when a NEW frame was written, 0 when there is nothing newer than
 * the last one this returned (so a caller can poll at whatever rate it likes
 * and only pay for the copy when there is something to show), and -1 on error.
 *
 * The a-trous filter runs HERE, on the calling thread, so it competes with
 * nothing: the path tracing is on the GPU and the render thread is feeding it.
 */
int cy_live_frame(unsigned char *rgba_out, int capacity, CyFrame *info);

/* Suspend or resume sampling WITHOUT losing what has been sampled.
 *
 * M355 — THE OTHER HALF OF NOT FIGHTING THE COMPOSITOR.
 *
 * M354 stopped the tracer during a camera move by pushing it a view it could
 * finish at once. That works there because the view is about to change anyway,
 * and it cannot be used for anything else: pushing a view calls Session::reset,
 * which throws away every sample accumulated so far. Doing that whenever the
 * user touched the screen would reset a converging image to noise on every
 * tap.
 *
 * A standstill render is minutes of GPU at full resolution, and for all of it
 * Flutter's compositor is queued behind a path tracer for the slice it needs
 * every eight milliseconds. So the tracer has to be able to stand down and
 * come back to the SAME image, which is what Session::set_pause does and what
 * Blender's own viewport uses it for.
 *
 * Idempotent, cheap, and safe to call before the session exists (it does
 * nothing). Returns 1 when there was a session to tell. */
int cy_live_pause(int paused);

/* Why the last call failed. Never null. */
const char *cy_last_error(void);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* CYCLES_SHIM_H */
