/* M296 — the C surface of the Cycles renderer.
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * ---------------------------------------------------------------------------
 * WHAT THE FIRST VERSION RENDERS, AND WHY IT IS SO SMALL
 * ---------------------------------------------------------------------------
 *
 * A clay render: every body in the scene's default grey surface, lit by a
 * uniform world colour, orthographic camera, path traced.
 *
 * That is not a placeholder for want of ambition — it is the smallest scene
 * that is a REAL Cycles render, and every piece left out is a piece of API
 * that could only be got wrong blind. There is no Swift and no C++ toolchain
 * in the environment this was written in: it compiles for the first time in
 * CI, on a machine nobody is watching, and every unfamiliar class name costs a
 * round trip. So this version uses:
 *
 *   * scene->default_surface for every mesh — no Shader, no ShaderGraph, no
 *     DiffuseBsdfNode, no node connections;
 *   * scene->default_background as it comes — no Light, no Object transform,
 *     no sun direction convention to get backwards;
 *   * one Pass, PASS_COMBINED, which is what the reference standalone app does.
 *
 * Per-body colour (the app already stores materials) and a sun are the next
 * two steps, and both are additive: they add nodes to a scene this file
 * already builds correctly.
 *
 * A uniform world is also not a bad CAD look. It is what a lightbox gives you
 * — soft, even, no hard key — and the shape reads from occlusion rather than
 * from a shadow that has to be aimed.
 *
 * ---------------------------------------------------------------------------
 * THE ONE THING THAT IS NOT OPTIONAL
 * ---------------------------------------------------------------------------
 *
 * The Metal device compiles its kernels FROM SOURCE at runtime:
 *
 *     source = "\n#include \"kernel/device/metal/kernel.metal\"\n";
 *     source = path_source_replace_includes(source, path_get("source"));
 *                                          — device/metal/device_impl.mm
 *
 * so intern/cycles/kernel has to be inside the app bundle and
 * cy_set_resource_path must point at its parent before the first render. An
 * app that ships the libraries and not the kernel tree links, launches, and
 * fails at the first render with nothing that names the cause.
 */

#include "cycles_shim.h"

#include <atomic>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#include "device/device.h"
#include "scene/attribute.h"
#include "scene/background.h"
#include "scene/camera.h"
#include "scene/mesh.h"
#include "scene/object.h"
#include "scene/pass.h"
#include "scene/scene.h"
#include "scene/shader.h"
#include "scene/shader_graph.h"
#include "scene/shader_nodes.h"
#include "session/buffers.h"
#include "session/output_driver.h"
#include "session/session.h"
#include "util/path.h"
#include "util/transform.h"
#include "util/types.h"
#include "util/unique_ptr.h"

namespace {

/* WHERE THE VERTEX POSITIONS LIVE, IN TWO CYCLES TREES AT ONCE.
 *
 * Cycles moved the vertex-position storage out of Mesh and into Geometry
 * partway through Blender 5.x development:
 *
 *   old (4.x, and the `ios` branch this ships against)
 *       Mesh::verts, an `array<float3>` node socket
 *       -> mesh->get_verts().data(), tagged with tag_verts_modified()
 *   new (Cycles main)
 *       Geometry::position, a packed_float3 buffer
 *       -> mesh->get_position_for_write(), which tags for you
 *
 * NOTE ON THE OLD NAME: it is `get_verts()`, NOT `get_verts_for_write()`.
 * NODE_SOCKET_API_ARRAY generates exactly two accessors — a const one from
 * NODE_SOCKET_API_BASE_METHODS and a non-const `type_ &get_##name()` — and no
 * `_for_write` variant at all; that spelling arrived with the packed buffers.
 * Run 7 was spent on that guess. The tagging is therefore explicit here, since
 * the plain accessor does not do it.
 *
 * Run 6 of the probe found out the hard way: one error, on this one line,
 * with the other 320 lines of this file compiling clean. Pinning the shim to
 * either name buys a build that breaks the next time the branch is rebased,
 * and every attempt costs an eight-minute macOS runner. So ask the compiler
 * which one the tree has. The `int`/`long` tag is the ordinary trick: the
 * `int` overload is the better match and wins wherever its return type
 * substitutes, and only the overload actually chosen is instantiated, so the
 * other one naming a member that does not exist is not an error.
 *
 * Both element types accept a float3 by assignment (packed_float3 has an
 * implicit converting constructor), so the caller does not have to care which
 * one it got back. */
template<typename M>
auto mesh_positions(M *m, int) -> decltype(m->get_position_for_write())
{
  return m->get_position_for_write();
}

template<typename M> auto mesh_positions(M *m, long) -> decltype(m->get_verts().data())
{
  return m->get_verts().data();
}

/* Same two trees, same trick, for marking the positions dirty. The new API's
 * `_for_write` accessor tags on the way out; the old one's plain reference
 * does not, and geometry that is never tagged is geometry the scene manager
 * does not upload. */
template<typename M> auto mesh_tag_positions(M *m, int) -> decltype(m->tag_position_modified())
{
  return m->tag_position_modified();
}

template<typename M> auto mesh_tag_positions(M *m, long) -> decltype(m->tag_verts_modified())
{
  return m->tag_verts_modified();
}

std::string g_error;
std::string g_device = "none";
bool g_probed = false;
/* Read from the UI isolate while a render writes it from another. One process,
 * so this is an ordinary data race and an atomic is the ordinary fix. */
std::atomic<bool> g_kernels_ready{false};

/* The step Cycles is on, for the UI.
 *
 * Written from Cycles' own threads through the progress callback and read from
 * the UI isolate, so it is a mutex-guarded copy rather than a std::string
 * somebody else is reassigning underneath the reader. */
std::mutex g_status_mutex;
std::string g_status;
float g_progress = -1.0f;

void set_status(const std::string &s, float p)
{
  std::lock_guard<std::mutex> lock(g_status_mutex);
  g_status = s;
  g_progress = p;
}

/* Reports [session]'s progress into the globals above, for the life of the
 * session. Cycles calls this from its own threads. */
void watch_progress(ccl::Session *session)
{
  ccl::Session *s = session;
  session->progress.set_update_callback([s]() {
    ccl::string status, substatus;
    s->progress.get_status(status, substatus);
    if (!substatus.empty()) {
      status += ", " + substatus;
    }
    set_status(std::string(status.c_str()), (float)s->progress.get_progress());
  });
}

void set_error(const char *msg)
{
  g_error = msg ? msg : "";
}

/* The device to render on: Metal, or nothing.
 *
 * METAL IS REQUIRED, not preferred. Cycles has a CPU device and falling back to
 * it is the wrong behaviour here: the same image an iPad's GPU produces in a
 * few seconds takes its CPU minutes, on battery, while the app appears hung.
 * A rendered mode that silently becomes a four-minute wait is worse than one
 * that says it cannot run — and on the machines this app ships to, there is
 * always a Metal device, so the fallback only ever fires when something is
 * already wrong.
 */
bool pick_device(ccl::DeviceInfo &out)
{
  const ccl::vector<ccl::DeviceInfo> devices = ccl::Device::available_devices();
  for (const ccl::DeviceInfo &info : devices) {
    if (info.type == ccl::DEVICE_METAL) {
      out = info;
      return true;
    }
  }
  return false;
}

/* Copies the finished frame out of Cycles and into the caller's buffer.
 *
 * Float pixels, converted here rather than by Cycles: the app wants RGBA8 for
 * a texture and the conversion is three multiplies. The vertical flip is the
 * same one the reference OIIO driver does — Cycles' buffer is bottom-up and
 * every image surface the app has is top-down.
 */
class BufferOutput : public ccl::OutputDriver {
 public:
  BufferOutput(unsigned char *dst, const int width, const int height)
      : dst_(dst), width_(width), height_(height)
  {
  }

  void write_render_tile(const Tile &tile) override
  {
    /* Only the finished full frame; intermediate tiles are not the result.
     * Written as the reference driver writes it (`!(a == b)`), because int2's
     * operator!= is not something to assume. */
    if (!(tile.size == tile.full_size)) {
      return;
    }
    const int w = tile.size.x;
    const int h = tile.size.y;
    if (w != width_ || h != height_) {
      set_error("render tile is not the size that was asked for");
      return;
    }
    std::vector<float> px(size_t(w) * size_t(h) * 4);
    if (!tile.get_pass_pixels("combined", 4, px.data())) {
      set_error("could not read the combined pass");
      return;
    }
    for (int y = 0; y < h; y++) {
      const float *src = px.data() + size_t(h - 1 - y) * size_t(w) * 4;
      unsigned char *dst = dst_ + size_t(y) * size_t(w) * 4;
      for (int x = 0; x < w * 4; x++) {
        const float v = src[x];
        const float c = v <= 0.0f ? 0.0f : (v >= 1.0f ? 1.0f : v);
        dst[x] = (unsigned char)(c * 255.0f + 0.5f);
      }
    }
    wrote_ = true;
  }

  bool wrote() const
  {
    return wrote_;
  }

 private:
  unsigned char *dst_;
  int width_;
  int height_;
  bool wrote_ = false;
};

}  // namespace

extern "C" {

int cy_available(void)
{
  ccl::DeviceInfo info;
  if (!pick_device(info)) {
    g_device = "none";
    g_probed = true;
    return 0;
  }
  g_device = info.description.c_str();
  g_probed = true;
  return 1;
}

const char *cy_device_name(void)
{
  if (!g_probed) {
    cy_available();
  }
  return g_device.c_str();
}

void cy_set_resource_path(const char *path)
{
  if (path == nullptr) {
    return;
  }
  ccl::path_init(path, path);

  /* AND THE KERNEL CACHE, which is a separate directory and the one that
   * decides whether the minutes-long first compile is paid once or on every
   * single launch.
   *
   * Cycles writes its compiled Metal binary archives under
   * path_cache_get("kernels"), which resolves to $XDG_CACHE_HOME or, failing
   * that, $HOME/.cache — see util/path.cpp, path_xdg_cache_get. On iOS $HOME
   * is the app container ROOT, which the sandbox forbids writing to, so the
   * directory can never be created and every archive save fails. Metal reports
   * that as "Invalid URL", which is why it reads like a Metal bug and is not
   * one. Library/Caches is the sanctioned writable location.
   *
   * Discovered the hard way by Toemeler/blender-iOS-ipa (build-30). Their fix
   * patches Cycles; this needs no patch, because the environment variable is
   * checked first. */
  const char *home = getenv("HOME");
  if (home != nullptr && getenv("XDG_CACHE_HOME") == nullptr) {
    const std::string caches = std::string(home) + "/Library/Caches";
    setenv("XDG_CACHE_HOME", caches.c_str(), 1);
  }
}

const char *cy_last_error(void)
{
  return g_error.c_str();
}

int cy_render(const CyMesh *meshes,
              const int mesh_count,
              const CyView *view,
              unsigned char *rgba_out)
{
  set_error("");
  if (view == nullptr || rgba_out == nullptr || view->width <= 0 || view->height <= 0) {
    set_error("no view, no output buffer, or a zero-sized image");
    return 0;
  }

  ccl::DeviceInfo device;
  if (!pick_device(device)) {
    set_error("no Metal device — this build renders on the GPU only");
    return 0;
  }

  ccl::SessionParams session_params;
  session_params.device = device;
  session_params.background = true;
  session_params.headless = true;
  session_params.samples = view->samples > 0 ? view->samples : 32;
  /* Auto-tiling writes in-progress EXRs to a temp directory. A viewport-sized
   * image does not need tiling and an iOS app has no business writing scratch
   * files it never reads. */
  session_params.use_auto_tile = false;

  ccl::SceneParams scene_params;

  ccl::unique_ptr<ccl::Session> session = ccl::make_unique<ccl::Session>(session_params,
                                                                        scene_params);
  ccl::Scene *scene = session->scene.get();
  watch_progress(session.get());

  /* ---- camera ---------------------------------------------------------- */
  ccl::Camera *cam = scene->camera;
  const float *m = view->matrix;
  cam->set_matrix(ccl::make_transform(m[0], m[1], m[2], m[3],
                                      m[4], m[5], m[6], m[7],
                                      m[8], m[9], m[10], m[11]));
  cam->set_camera_type(ccl::CAMERA_ORTHOGRAPHIC);
  cam->set_full_width(view->width);
  cam->set_full_height(view->height);
  /* For an orthographic camera the viewplane IS the extent in world units, so
   * it is set rather than computed — compute_auto_viewplane would derive it
   * from the aspect ratio alone and lose the scale the caller asked for. */
  cam->set_viewplane_left(-view->half_width);
  cam->set_viewplane_right(view->half_width);
  cam->set_viewplane_bottom(-view->half_height);
  cam->set_viewplane_top(view->half_height);
  cam->need_flags_update = true;
  cam->update(scene);

  /* ---- the world, which is also the only light -------------------------
   *
   * NOT OPTIONAL, and the reason is worth stating: Cycles' `default_background`
   * ships with an EMPTY graph —
   *
   *     unique_ptr<ShaderGraph> graph = make_unique<ShaderGraph>();
   *     Shader *shader = scene->create_node<Shader>();
   *     shader->name = "default_background";
   *     shader->set_graph(std::move(graph));
   *                                        — intern/cycles/scene/shader.cpp
   *
   * so a scene that does not build one renders black, with no error, on a
   * device that worked perfectly. Every geometry bug would have been debugged
   * through that.
   *
   * A uniform background is the whole lighting rig, and deliberately so. It is
   * a lightbox: the shape reads from occlusion rather than from a key light
   * that has to be aimed, which suits a CAD body being inspected from
   * arbitrary directions far better than a fixed sun does — and there is no
   * direction from which the part goes dark. A sun and a fill are the obvious
   * next step and are additive on this. */
  /* WHAT IS NOT DONE HERE, and what it cost. The obvious-looking pair
   *
   *     scene->background->set_shader(world);
   *     scene->background->tag_update(scene);
   *
   * segfaulted on device, in Background::tag_update, and took build 619 down
   * at launch (EXC_BAD_ACCESS at 0x29, thread DartWorker, cy_preload ->
   * cy_render -> Background::tag_update). They are also unnecessary:
   *
   *     Shader *Background::get_shader(const Scene *scene)
   *     {
   *       return (use_shader) ? ((shader) ? shader : scene->default_background)
   *                           : scene->default_empty;
   *     }
   *
   * use_shader defaults to true and shader defaults to null, so the world IS
   * default_background already. Setting the graph on it is the whole job; the
   * Background node needs no telling. Cycles' own standalone scene reader does
   * exactly this and no more.
   *
   * The bug shipped in build 616 as well. Nothing had ever called cy_render on
   * a device until the warm-up did, so it had simply never run. */
  if (scene->default_background != nullptr) {
    ccl::unique_ptr<ccl::ShaderGraph> graph = ccl::make_unique<ccl::ShaderGraph>();
    ccl::BackgroundNode *bg = graph->create_node<ccl::BackgroundNode>();
    bg->set_color(ccl::make_float3(view->world[0], view->world[1], view->world[2]));
    bg->set_strength(1.0f);
    graph->connect(bg->output("Background"), graph->output()->input("Surface"));
    ccl::Shader *world = scene->default_background;
    world->set_graph(std::move(graph));
    world->tag_update(scene);
  }

  /* ---- geometry -------------------------------------------------------- */
  for (int i = 0; i < mesh_count; i++) {
    const CyMesh &src = meshes[i];
    if (src.vert_count <= 0 || src.tri_count <= 0 || src.verts == nullptr ||
        src.tris == nullptr)
    {
      continue;
    }
    ccl::Mesh *mesh = scene->create_node<ccl::Mesh>();

    ccl::array<ccl::Node *> used_shaders;
    used_shaders.push_back_slow(scene->default_surface);
    mesh->set_used_shaders(used_shaders);

    mesh->resize_mesh(src.vert_count, src.tri_count);
    auto *P = mesh_positions(mesh, 0);
    for (int v = 0; v < src.vert_count; v++) {
      P[v] = ccl::make_float3(
          src.verts[v * 3 + 0], src.verts[v * 3 + 1], src.verts[v * 3 + 2]);
    }

    mesh_tag_positions(mesh, 0);

    /* The caller's normals, as the vertex-normal attribute Cycles shades
     * with. Without this, `smooth` below would make Cycles average the face
     * normals it computed itself, and on a CAD body that rounds off every
     * edge that is supposed to be sharp — the tessellator already knows which
     * edges are which and has told us in `normals`. */
    if (src.normals != nullptr) {
      ccl::Attribute *attr = mesh->attributes.add(ccl::ATTR_STD_VERTEX_NORMAL);
      ccl::float3 *N = attr->data_float3();
      for (int v = 0; v < src.vert_count; v++) {
        N[v] = ccl::normalize(ccl::make_float3(
            src.normals[v * 3 + 0], src.normals[v * 3 + 1], src.normals[v * 3 + 2]));
      }
    }

    ccl::array<int> &tris = mesh->get_triangles();
    ccl::array<int> &shader = mesh->get_shader();
    ccl::array<bool> &smooth = mesh->get_smooth();
    for (int t = 0; t < src.tri_count; t++) {
      tris[t * 3 + 0] = src.tris[t * 3 + 0];
      tris[t * 3 + 1] = src.tris[t * 3 + 1];
      tris[t * 3 + 2] = src.tris[t * 3 + 2];
      shader[t] = 0;
      /* Smooth only when the caller supplied normals. Cycles reads them from
       * the vertex-normal attribute; without one, smooth shading would
       * interpolate normals Cycles computed itself, which on a CAD body means
       * rounding off every edge that should be sharp. */
      smooth[t] = src.normals != nullptr;
    }
    mesh->tag_triangles_modified();
    mesh->tag_shader_modified();
    mesh->tag_smooth_modified();

    ccl::Object *object = scene->create_node<ccl::Object>();
    object->set_geometry(mesh);
    object->set_tfm(ccl::transform_identity());
  }

  /* ---- output ---------------------------------------------------------- */
  ccl::Pass *pass = scene->create_node<ccl::Pass>();
  pass->set_name(ccl::ustring("combined"));
  pass->set_type(ccl::PASS_COMBINED);

  ccl::unique_ptr<BufferOutput> driver = ccl::make_unique<BufferOutput>(
      rgba_out, view->width, view->height);
  BufferOutput *driver_ptr = driver.get();
  session->set_output_driver(std::move(driver));

  ccl::BufferParams buffer_params;
  buffer_params.width = view->width;
  buffer_params.height = view->height;
  buffer_params.full_width = view->width;
  buffer_params.full_height = view->height;

  session->reset(session_params, buffer_params);
  session->start();
  session->wait();

  if (!driver_ptr->wrote()) {
    if (g_error.empty()) {
      set_error("the render finished without producing a frame");
    }
    return 0;
  }
  /* A frame came back, so the kernels are compiled and in the archive. Any
   * render proves this, not just cy_preload's. */
  g_kernels_ready.store(true);
  set_status("", -1.0f);
  return 1;
}

int cy_kernels_ready(void)
{
  return g_kernels_ready.load() ? 1 : 0;
}

void cy_status(char *out, int len)
{
  if (out == nullptr || len <= 0) {
    return;
  }
  std::lock_guard<std::mutex> lock(g_status_mutex);
  const size_t n = g_status.size() < (size_t)(len - 1) ? g_status.size() : (size_t)(len - 1);
  memcpy(out, g_status.data(), n);
  out[n] = '\0';
}

float cy_progress(void)
{
  std::lock_guard<std::mutex> lock(g_status_mutex);
  return g_progress;
}

int cy_preload(void)
{
  if (g_kernels_ready.load()) {
    return 1;
  }
  /* One triangle, one sample, 32x32. Small enough to be over the moment the
   * kernels exist, and a REAL render rather than a device probe, because it is
   * the render path that walks load_kernels, compiles the pipelines and writes
   * the binary archive. A cheaper warm-up would compile a different set of
   * kernels than the app then asks for, and the wait would simply move. */
  const float verts[9] = {0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f, 1.0f, 0.0f};
  const int tris[3] = {0, 1, 2};
  CyMesh mesh;
  mesh.verts = verts;
  mesh.vert_count = 3;
  mesh.normals = nullptr;
  mesh.tris = tris;
  mesh.tri_count = 1;

  CyView view;
  memset(&view, 0, sizeof(view));
  /* Identity basis, eye pulled back along +Z, matching cyclesCameraMatrix. */
  view.matrix[0] = 1.0f;
  view.matrix[5] = 1.0f;
  view.matrix[10] = 1.0f;
  view.matrix[11] = 4.0f;
  view.half_width = 2.0f;
  view.half_height = 2.0f;
  view.width = 32;
  view.height = 32;
  view.samples = 1;
  view.world[0] = view.world[1] = view.world[2] = 0.8f;

  std::vector<unsigned char> scratch((size_t)view.width * view.height * 4);
  set_status("Preparing the renderer", 0.0f);

  const int ok = cy_render(&mesh, 1, &view, scratch.data());
  if (!ok) {
    set_status("", -1.0f);
  }
  return ok;
}

}  /* extern "C" */
