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
#include <cstdint>
#include <map>
#include <cmath>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#include "device/device.h"
#include "scene/attribute.h"
#include "scene/background.h"
#include "scene/camera.h"
#include "scene/light.h"
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

/* THE BODY'S APPEARANCE, as a Cycles shader.
 *
 * Every mesh used to get scene->default_surface — one grey clay for the whole
 * model, ignoring the materials the app has stored per body since M272. A
 * render in which an aluminium bracket and a copper bus-bar come out the same
 * colour is not a render of the user's model.
 *
 * CACHED BY APPEARANCE, not per mesh. An assembly is routinely hundreds of
 * pieces drawn from a handful of materials, and a Shader per piece means a
 * ShaderGraph per piece for Cycles to compile and deduplicate. The key is the
 * quantised colour and finish, which is exactly as fine as the difference a
 * viewer could see.
 *
 * A mesh with no material still means STEEL — the absence of a material, not a
 * material that happens to be grey. What changed in M337 is what steel looks
 * like: it is now built here, from the app's own colour, rather than taken
 * from Cycles' default_surface, which is a bare Principled BSDF at 0.8 and
 * three times too bright. It shares the cache under a key no colour can
 * reach. */
using ShaderCache = std::map<uint64_t, ccl::Shader *>;

uint64_t appearance_key(const CyMesh &m)
{
  const auto q = [](float v) -> uint64_t {
    const float c = v < 0.0f ? 0.0f : (v > 1.0f ? 1.0f : v);
    return (uint64_t)(c * 1023.0f + 0.5f);
  };
  return (q(m.color[0]) << 40) | (q(m.color[1]) << 30) | (q(m.color[2]) << 20) |
         (q(m.roughness) << 10) | q(m.metallic);
}

/* M337 — THE RENDERER'S OWN STEEL, and why default_surface is not it.
 *
 * `scene->default_surface` is a bare PrincipledBsdfNode, and a bare one has a
 * base colour of 0.8 — near white. The app's steel is Colors.steel, 0x86898D,
 * which is linear 0.25: a mid grey, and a THIRD of the brightness. An
 * unpainted body is the default and the commonest case, so this was the first
 * thing anyone would see, and what they would see is a part in white clay next
 * to a working view showing it in grey metal.
 *
 * The numbers are Materials.rendered(Colors.steel) exactly — the material an
 * untinted body gets in the RealityKit rendered view, which is where the 0.45
 * roughness and the 0.15 metallic come from rather than from the working
 * view's matte 0.9. Written out linear because that is what the shim takes
 * everywhere; the sRGB bytes they came from are in the comment so the two
 * files can still be compared.
 *
 * Kept as "no material means the renderer's steel" rather than moving the
 * colour into Dart, because that is the contract cycles_shim.h states and
 * because render_test can check the tone that actually comes out, which no
 * Dart test can. */
const float kSteelLinear[3] = {0.238398f, 0.250158f, 0.266356f}; /* 0x86898D */
const float kSteelRoughness = 0.45f;
const float kSteelMetallic = 0.15f;

/* A key no real appearance can collide with: appearance_key packs five
 * 10-bit quantities into the low 50 bits. */
const uint64_t kSteelKey = (uint64_t)1 << 60;

ccl::Shader *build_surface(ccl::Scene *scene,
                           const float color[3],
                           const float roughness,
                           const float metallic)
{
  ccl::unique_ptr<ccl::ShaderGraph> graph = ccl::make_unique<ccl::ShaderGraph>();
  ccl::PrincipledBsdfNode *bsdf = graph->create_node<ccl::PrincipledBsdfNode>();
  bsdf->set_base_color(ccl::make_float3(color[0], color[1], color[2]));
  bsdf->set_roughness(roughness);
  bsdf->set_metallic(metallic);
  graph->connect(bsdf->output("BSDF"), graph->output()->input("Surface"));

  ccl::Shader *shader = scene->create_node<ccl::Shader>();
  shader->name = ccl::ustring("body");
  shader->set_graph(std::move(graph));
  shader->tag_update(scene);
  return shader;
}

ccl::Shader *surface_for(ccl::Scene *scene, ShaderCache &cache, const CyMesh &m)
{
  if (!m.has_material) {
    const ShaderCache::const_iterator steel = cache.find(kSteelKey);
    if (steel != cache.end()) {
      return steel->second;
    }
    ccl::Shader *shader = build_surface(
        scene, kSteelLinear, kSteelRoughness, kSteelMetallic);
    cache[kSteelKey] = shader;
    return shader;
  }
  const uint64_t key = appearance_key(m);
  const ShaderCache::const_iterator it = cache.find(key);
  if (it != cache.end()) {
    return it->second;
  }

  ccl::Shader *shader = build_surface(scene, m.color, m.roughness, m.metallic);
  cache[key] = shader;
  return shader;
}

/* ---------------------------------------------------------------------------
 * M332 — THE LIGHT RIG, AND WHY A UNIFORM WORLD COULD NEVER HAVE WORKED
 * ---------------------------------------------------------------------------
 *
 * The first version lit the scene with a constant-colour world and argued it
 * was a lightbox. A lightbox is a real thing and that argument is half right:
 * a uniform environment does read shape out of OCCLUSION, so pockets, bores
 * and inside corners darken.
 *
 * What it cannot do is the other half. Under a uniform environment the
 * radiance leaving an unoccluded diffuse surface is the same NO MATTER WHICH
 * WAY IT FACES — the integral over the hemisphere does not depend on the
 * normal. So every outer face of a part comes out at one identical tone: a
 * boss and the plate it stands on are the same grey, a cylinder is a flat
 * rectangle, a chamfer is invisible. The picture is a silhouette with some
 * dirt in the corners, and it is the thing the user saw and called grey.
 *
 * THE RIG IS RealityKit's, deliberately. The app already has a rendered mode
 * and this is meant to be a better photograph of the same scene, not a
 * different scene. RealityPartView.applyLighting() has been tuned against
 * real parts for several milestones, so its four directions and its ratios
 * are copied here rather than invented again:
 *
 *     headlight  620 lux, camera-locked   key
 *     sun        950 lux, from ( 7, 14,  9)   casts the shadow
 *     fill       380 lux, from (-3,  6, -4)
 *     rim        380 lux, from (-9,  7,-12)
 *
 * The world is Y-UP; those vectors are in that frame, unchanged from the
 * Swift.
 *
 * FROM LUX TO STRENGTH. A Cycles distant light with `normalize` on — the
 * default — has a `strength` that IS irradiance in W/m^2: the eval_fac of
 * 1/(pi sin^2(A/2)) and the cone solid angle of 4 pi sin^2(A/4) cancel to 1
 * for any angle, so the number means the same thing whether the sun is a
 * point or a disk. RealityKit's lux are on a different scale entirely, so
 * what carries over is the RATIO; kSunStrength fixes the one absolute value.
 *
 * 1.7 puts a face square to the sun at 0.8 * 1.7 / pi = 0.43 linear on its
 * own, and a top face taking sun, fill and rim together at about 0.7 — bright
 * without clipping, and with the dark side landing near 0.19, which is the
 * contrast a solid needs to read as solid.
 *
 * SHADOWS FROM TWO OF THE FOUR. The sun casts, because that is the shadow the
 * floor is there to catch. The headlight casts, and costs nothing to: it sits
 * at the camera, so every shadow it throws is behind the geometry that threw
 * it. Fill and rim do not, which is both what a RealityKit directional
 * without a shadow component does and what makes them fills — their entire
 * job is to lift a face the key cannot reach, and a fill that is itself
 * occluded lifts nothing. */
const float kRigHead = 620.0f;
const float kRigSun = 950.0f;
const float kRigFill = 380.0f;
const float kRigRim = 380.0f;

const float kSunStrength = 1.7f;
const float kRigScale = kSunStrength / kRigSun;

/* A soft-ish sun: ~2.9 degrees against the real one's 0.53. A CAD render wants
 * the contact shadow to say "resting on" rather than to be a crisp cutout, and
 * at this width the penumbra is a few pixels and costs almost no noise at the
 * sample counts this app renders at. */
const float kSunAngle = 0.05f;

/* How much of the visible background the SURFACES see, against the 1.0 the
 * camera sees.
 *
 * A FRACTION, so what it is actually worth depends entirely on the palette,
 * and the two schemes are nowhere near each other: Chalk's viewport is
 * 0xFCFBF8, linear 0.96, and this puts about 0.036 on a steel face — a real if
 * modest lift. The dark scheme's is 0x201D19, linear 0.012, and this puts
 * 0.0005 on the same face, which is nothing at all.
 *
 * That is the right behaviour and not a gap to close. The number the camera
 * sees has to be the viewport's colour exactly, or the render does not sit on
 * the ground the app draws; and a room whose walls are that dark really does
 * bounce nothing. What keeps the model from having black faces under the dark
 * scheme is not this at all, it is the other two things the rig has:
 *
 *   * the HEADLIGHT is camera-locked, so every surface facing the viewer is
 *     lit by the key whichever way the model is turned. There is no such thing
 *     as a black face pointing at you;
 *   * the FLOOR bounces. RealityKit's directional rig has no equivalent — it
 *     has no global illumination at all — so an underside in shadow there is
 *     as dark as this ambient would leave it, and here the sun's light comes
 *     back up off the ground. On this one point the path tracer is not at
 *     parity with the working view, it is better than it. */
const float kWorldAmbient = 0.15f;

/* One Emission shader for the whole rig.
 *
 * NOT OPTIONAL. `scene->default_light` — what a Light with no shader of its
 * own falls back to in LightManager::device_update — is an EmissionNode with
 * its strength set to 0.0f (scene/shader.cpp, "default light"). It is a
 * placeholder that emits nothing, so a light left holding it is a light that
 * is off, and the whole rig would have rendered exactly the flat frame it
 * replaced. */
ccl::Shader *rig_shader(ccl::Scene *scene)
{
  ccl::unique_ptr<ccl::ShaderGraph> graph = ccl::make_unique<ccl::ShaderGraph>();
  ccl::EmissionNode *emission = graph->create_node<ccl::EmissionNode>();
  emission->set_color(ccl::make_float3(1.0f, 1.0f, 1.0f));
  emission->set_strength(1.0f);
  graph->connect(emission->output("Emission"), graph->output()->input("Surface"));

  ccl::Shader *shader = scene->create_node<ccl::Shader>();
  shader->name = ccl::ustring("rig_light");
  shader->set_graph(std::move(graph));
  shader->tag_update(scene);
  return shader;
}

/* Add one distant light shining FROM [from] towards the origin.
 *
 * A Light is a Geometry in this tree and carries no direction of its own:
 * LightManager walks scene->objects, skips anything whose geometry is not a
 * light, and takes the direction the light TRAVELS as -column2 of the object's
 * transform. So a light with no Object is a light that does not exist, and the
 * basis below puts +Z back along [from] — the Blender convention, where a lamp
 * shines down its local -Z.
 *
 * Columns 0 and 1 are an arbitrary orthonormal completion. They are read only
 * for AREA lights (Light::area) and for portals, so any pair will do; they are
 * built properly anyway rather than left as garbage that a later light type
 * would silently inherit. */
void add_distant_light(ccl::Scene *scene,
                       ccl::Shader *shader,
                       const ccl::float3 &from,
                       const float strength,
                       const bool cast_shadow,
                       const float angle)
{
  if (strength <= 0.0f || ccl::len(from) <= 0.0f) {
    return;
  }
  const ccl::float3 z = ccl::normalize(from);
  const float zy = z.y < 0.0f ? -z.y : z.y;
  const ccl::float3 up = zy < 0.99f ? ccl::make_float3(0.0f, 1.0f, 0.0f) :
                                      ccl::make_float3(1.0f, 0.0f, 0.0f);
  const ccl::float3 x = ccl::normalize(ccl::cross(up, z));
  const ccl::float3 y = ccl::cross(z, x);

  ccl::Light *light = scene->create_node<ccl::Light>();
  light->set_light_type(ccl::LIGHT_DISTANT);
  light->set_strength(ccl::make_float3(strength, strength, strength));
  light->set_angle(angle);
  light->set_cast_shadow(cast_shadow);
  ccl::array<ccl::Node *> used_shaders;
  used_shaders.push_back_slow(shader);
  light->set_used_shaders(used_shaders);
  light->tag_update(scene);

  ccl::Object *object = scene->create_node<ccl::Object>();
  object->set_geometry(light);
  object->set_tfm(ccl::make_transform(x.x, y.x, z.x, 0.0f,
                                      x.y, y.y, z.y, 0.0f,
                                      x.z, y.z, z.z, 0.0f));
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
/* M342 — THE APP IS GPU-ONLY, and this does not change that.
 *
 * Metal or nothing, as asked. There is no CPU fallback in the product and
 * there must not be one: a path tracer on an iPad's CPU is not a slower
 * rendered mode, it is a frozen app, and a fallback that quietly produced one
 * would be worse than the mode simply saying it cannot run.
 *
 * CYCLES_SHIM_CPU_FOR_TESTS is not that fallback. It is never set by the app —
 * an iOS app launched normally has no such variable in its environment, and
 * nothing in this repository writes one — and it exists for exactly one
 * caller: the host render test in .github/workflows/cycles-render-test.yml.
 *
 * WHY THAT TEST NEEDS IT. The GitHub macOS runner does have a Metal device; it
 * reports itself as "Apple Paravirtual device (GPU)". What it cannot do in any
 * usable time is COMPILE Cycles' Metal kernels from source, which is the work
 * ios_metal.py exists to make survivable on an iPad and which on three
 * paravirtualised cores simply does not finish — run 13 sat on it for 116
 * minutes and hit the job timeout having printed the device name and nothing
 * else.
 *
 * That cost buys nothing the test was ever for. It exists to check scene
 * construction, the camera basis, materials, the light rig and the output
 * driver, every one of which is device-independent code that runs identically
 * on both backends. It could never have tested the iOS Metal path anyway —
 * iOS binaries do not execute on a Mac, which is why the probe and the
 * WITH_APPLE_CROSSPLATFORM guards exist and why this workflow's own header
 * says the kernel loading is the probe's business.
 *
 * So the test asks for the CPU device explicitly and gets a render in
 * milliseconds, and the shipping app never reads this at all. */
bool pick_device(ccl::DeviceInfo &out)
{
  const bool cpu_for_tests = getenv("CYCLES_SHIM_CPU_FOR_TESTS") != nullptr;
  const ccl::DeviceType wanted = cpu_for_tests ? ccl::DEVICE_CPU :
                                                 ccl::DEVICE_METAL;
  const ccl::vector<ccl::DeviceInfo> devices = ccl::Device::available_devices();
  for (const ccl::DeviceInfo &info : devices) {
    if (info.type == wanted) {
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
/* M332 — LINEAR IN, sRGB OUT, and the second half of that was missing.
 *
 * `get_pass_pixels("combined", ...)` hands back SCENE-REFERRED LINEAR
 * radiance: sample-averaged and exposure-applied, but with no display
 * transform — that is Blender's job, through OCIO, and Cycles standalone's own
 * driver leaves it to OIIO's file format. This driver had neither, so a linear
 * value went straight into a byte that Flutter then draws as sRGB.
 *
 * That is not a subtle error. A surface at half the world's brightness is
 * linear 0.5, which sRGB writes as 188; writing 128 instead renders it at
 * about a fifth of the light it reflects. Every midtone came out crushed and
 * the whole image muddy — and it was ASYMMETRIC, because cyclesLinear() in
 * Dart has been decoding every material colour sRGB -> linear on the way in
 * since M304. Colour went in through a curve and came out through none.
 *
 * The constants are the sRGB standard's, and they are exactly the inverse of
 * the ones in cyclesLinear. */
float srgb_encode(const float v)
{
  if (v <= 0.0f) {
    return 0.0f;
  }
  if (v >= 1.0f) {
    return 1.0f;
  }
  return (v <= 0.0031308f) ? v * 12.92f : 1.055f * powf(v, 1.0f / 2.4f) - 0.055f;
}

unsigned char quantise(const float v)
{
  const float c = v <= 0.0f ? 0.0f : (v >= 1.0f ? 1.0f : v);
  return (unsigned char)(c * 255.0f + 0.5f);
}

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
      for (int x = 0; x < w; x++) {
        /* COLOUR IS ENCODED, ALPHA IS NOT. Alpha is a coverage fraction, not a
         * light measurement, and running it through a transfer curve turns a
         * half-covered edge pixel into a 3/4-covered one. */
        dst[x * 4 + 0] = quantise(srgb_encode(src[x * 4 + 0]));
        dst[x * 4 + 1] = quantise(srgb_encode(src[x * 4 + 1]));
        dst[x * 4 + 2] = quantise(srgb_encode(src[x * 4 + 2]));
        dst[x * 4 + 3] = quantise(src[x * 4 + 3]);
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
    set_error(getenv("CYCLES_SHIM_CPU_FOR_TESTS") != nullptr ?
                  "no CPU device — the host render test cannot run" :
                  "no Metal device — this build renders on the GPU only");
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
  /* ---- M332: THE BACKGROUND YOU SEE AND THE LIGHT IT CASTS ARE NOT THE
   * SAME NUMBER ----------------------------------------------------------
   *
   * They were, and that is the second half of why the render came out flat. A
   * world set to the viewport's own grey is a mid-brightness environment
   * lighting every surface from every direction at once, and at that strength
   * it does not merely coexist with the rig below — it SWAMPS it, adding the
   * same value to every face and washing the modelling back out. Turning it
   * down instead would have fixed the light and left the render sitting on a
   * near-black background that looks nothing like the viewport it replaces.
   *
   * The two jobs separate cleanly, because Cycles can tell which ray is
   * asking. A camera ray gets the viewport's grey at full strength, so the
   * image sits on the background the rest of the app is drawing. Every other
   * ray — the ones that carry light onto surfaces — gets a small fraction of
   * it, enough to keep a cavity from going pure black and to tint the shadows
   * with the room, and far too little to flatten anything. */
  if (scene->default_background != nullptr) {
    const ccl::float3 world_color = ccl::make_float3(
        view->world[0], view->world[1], view->world[2]);

    ccl::unique_ptr<ccl::ShaderGraph> graph = ccl::make_unique<ccl::ShaderGraph>();

    ccl::BackgroundNode *seen = graph->create_node<ccl::BackgroundNode>();
    seen->set_color(world_color);
    seen->set_strength(1.0f);

    ccl::BackgroundNode *ambient = graph->create_node<ccl::BackgroundNode>();
    ambient->set_color(world_color);
    ambient->set_strength(kWorldAmbient);

    /* MixClosureNode takes Closure1 at Fac 0 and Closure2 at Fac 1 — its own
     * constant_fold is the statement of that, bypassing to Closure1 when the
     * factor is <= 0. "Is Camera Ray" is 1 for the rays that draw the picture,
     * so the visible background is Closure2 and the ambient is Closure1. */
    ccl::LightPathNode *path = graph->create_node<ccl::LightPathNode>();
    ccl::MixClosureNode *mix = graph->create_node<ccl::MixClosureNode>();
    graph->connect(path->output("Is Camera Ray"), mix->input("Fac"));
    graph->connect(ambient->output("Background"), mix->input("Closure1"));
    graph->connect(seen->output("Background"), mix->input("Closure2"));
    graph->connect(mix->output("Closure"), graph->output()->input("Surface"));

    ccl::Shader *world = scene->default_background;
    world->set_graph(std::move(graph));
    world->tag_update(scene);
  }

  /* ---- the light rig --------------------------------------------------- */
  {
    ccl::Shader *rig = rig_shader(scene);
    /* The headlight sits at the camera and shines along its view direction.
     * Column 2 of the camera-to-world basis IS that direction — Cycles'
     * Camera::matrix is (right, up, FORWARD, eye) — so the light that follows
     * the camera needs no separate input and cannot fall out of step with it. */
    const ccl::float3 head_from = -ccl::make_float3(m[2], m[6], m[10]);
    add_distant_light(scene, rig, head_from, kRigHead * kRigScale, true, 0.0f);
    add_distant_light(scene, rig, ccl::make_float3(7.0f, 14.0f, 9.0f),
                      kRigSun * kRigScale, true, kSunAngle);
    add_distant_light(scene, rig, ccl::make_float3(-3.0f, 6.0f, -4.0f),
                      kRigFill * kRigScale, false, 0.0f);
    add_distant_light(scene, rig, ccl::make_float3(-9.0f, 7.0f, -12.0f),
                      kRigRim * kRigScale, false, 0.0f);
  }

  /* ---- geometry -------------------------------------------------------- */
  ShaderCache shaders;
  for (int i = 0; i < mesh_count; i++) {
    const CyMesh &src = meshes[i];
    if (src.vert_count <= 0 || src.tri_count <= 0 || src.verts == nullptr ||
        src.tris == nullptr)
    {
      continue;
    }
    ccl::Mesh *mesh = scene->create_node<ccl::Mesh>();

    ccl::array<ccl::Node *> used_shaders;
    used_shaders.push_back_slow(surface_for(scene, shaders, src));
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
