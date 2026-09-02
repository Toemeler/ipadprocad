/* M344 — the C surface of the Cycles renderer.
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * ---------------------------------------------------------------------------
 * WHAT THIS RENDERS NOW
 * ---------------------------------------------------------------------------
 *
 * A resident path-traced viewport. One Session and one Scene stay alive for as
 * long as rendered mode is on; the camera can change every frame; a partially
 * converged frame can be pulled out at any moment and is denoised on the way
 * out; and sampling keeps going until the image is finished and then stops.
 *
 * The three things M344 added, and why each one is where the realism is:
 *
 *   THE SESSION IS RESIDENT. `background = false, headless = false` is what
 *   turns Cycles from a batch renderer into a viewport. The session thread
 *   blocks on a condition variable when there is no work rather than
 *   returning, so a camera change is a `reset()` and not a rebuild, and the
 *   OutputDriver's `update_render_tile` is called with in-progress results
 *   instead of only the finished frame. Everything about "keeps rendering
 *   while you orbit" follows from those two booleans.
 *
 *   THE ENVIRONMENT IS AN IMAGE. Four analytic lights can light a surface but
 *   they cannot be REFLECTED in one: a polished face under four directions
 *   shows four dots and black in between, which is why metal under any
 *   analytic rig looks like grey plastic. An HDRI gives the specular a room to
 *   reflect, and that single change is the difference between a picture that
 *   reads as a render and one that reads as a photograph of a part on a table.
 *
 *   SURFACES CARRY TEXTURES. Box-projected in object space, so a tessellation
 *   with no UVs — which is every mesh this app will ever have — can still take
 *   a brushed grain, a cast finish or machining marks, at a scale fixed in
 *   world units so a bracket and its base plate agree.
 *
 * All three degrade cleanly. No HDRI file: the M332 rig, unchanged. No texture
 * files: the flat Principled surfaces of M337, unchanged. That is deliberate —
 * the assets are large binaries that are not in this repository, and a build
 * without them has to be the app that shipped, not a broken one.
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
 * app that ships the nine static libraries and not the kernel TREE links,
 * launches, and fails at the first render with nothing that names the cause.
 */

#include "cycles_shim.h"

/* cycles_denoise.h is deliberately NOT included any more (M353). The filter it
 * declares is still built and still tested by render_test.c; nothing in the
 * live path calls it. See the note in cy_live_frame. */

#include <atomic>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <cstring>
#include <map>
#include <mutex>
#include <string>
#include <vector>

#include "device/device.h"
#include "scene/attribute.h"
#include "scene/background.h"
#include "scene/camera.h"
#include "scene/colorspace.h"
#include "scene/film.h"
#include "scene/image.h"
#include "scene/integrator.h"
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
#include "util/set.h"
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

/* ---------------------------------------------------------------------------
 * ERRORS AND PROGRESS
 * ------------------------------------------------------------------------- */

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

void set_status(const std::string &s, const float p)
{
  const std::lock_guard<std::mutex> lock(g_status_mutex);
  g_status = s;
  g_progress = p;
}

void set_error(const char *msg)
{
  g_error = msg ? msg : "";
}

/* Reports [session]'s progress into the globals above, for the life of the
 * session. Cycles calls this from its own threads. */
void watch_progress(ccl::Session *session)
{
  ccl::Session *s = session;
  session->progress.set_update_callback([s]() {
    ccl::string status;
    ccl::string substatus;
    s->progress.get_status(status, substatus);
    if (!substatus.empty()) {
      status += ", " + substatus;
    }
    set_status(std::string(status.c_str()), (float)s->progress.get_progress());
  });
}

/* ---------------------------------------------------------------------------
 * FILES
 * ------------------------------------------------------------------------- */

/* Is there a readable file at [path]?
 *
 * Asked HERE rather than left to Cycles' ImageManager, because a missing
 * texture is the NORMAL case and not an error: this app ships with an optional
 * asset set, and a build without it must render the flat surfaces it always
 * rendered rather than a scene full of black images and a log full of OIIO
 * complaints. A node that is never created cannot go wrong. */
bool file_readable(const char *path)
{
  if (path == nullptr || path[0] == '\0') {
    return false;
  }
  FILE *f = fopen(path, "rb");
  if (f == nullptr) {
    return false;
  }
  fclose(f);
  return true;
}

/* ---------------------------------------------------------------------------
 * THE SURFACE
 * ---------------------------------------------------------------------------
 *
 * M337 — THE RENDERER'S OWN STEEL, and why default_surface is not it.
 *
 * `scene->default_surface` is a bare PrincipledBsdfNode, and a bare one has a
 * base colour of 0.8 — near white. The app's steel is Colors.steel, 0x86898D,
 * which is linear 0.25: a mid grey, and a THIRD of the brightness. An
 * unpainted body is the default and the commonest case, so this was the first
 * thing anyone would see, and what they would see is a part in white clay next
 * to a working view showing it in grey metal.
 *
 * The numbers are Materials.rendered(Colors.steel) exactly — the material an
 * untinted body gets in the RealityKit rendered view. Written out linear
 * because that is what the shim takes everywhere; the sRGB bytes they came
 * from are in the comment so the two files can still be compared.
 */
const float kSteelLinear[3] = {0.238398f, 0.250158f, 0.266356f}; /* 0x86898D */
const float kSteelRoughness = 0.45f;
const float kSteelMetallic = 0.15f;

/* How much the three box projections overlap at a corner, 0..1.
 *
 * A hard switch between the three would draw a visible seam along every edge
 * of a machined part, which is the one place a CAD render is looked at
 * closely. A quarter is a wide enough cross-fade to hide the seam and narrow
 * enough that a face away from the corner is a single clean projection. */
const float kProjectionBlend = 0.25f;

/* The material a mesh with no material gets. */
CyMaterial steel_material()
{
  CyMaterial m;
  memset(&m, 0, sizeof(m));
  m.color[0] = kSteelLinear[0];
  m.color[1] = kSteelLinear[1];
  m.color[2] = kSteelLinear[2];
  m.roughness = kSteelRoughness;
  m.metallic = kSteelMetallic;
  m.specular = 0.5f;
  m.texture_scale = 1.0f;
  return m;
}

float clamp01(const float v)
{
  return v < 0.0f ? 0.0f : (v > 1.0f ? 1.0f : v);
}

/* A box-projected image node reading [path], or null when the file is not
 * there.
 *
 * [srgb] decides the transfer curve, and it is not a detail: a roughness map
 * read as sRGB is a roughness map with a gamma applied to it, which makes
 * every surface far smoother than the artist drew and is exactly the kind of
 * error that looks like "the renderer is too shiny" rather than like a bug.
 * Colour maps are sRGB; roughness, metallic, bump and occlusion are data.
 *
 * The colorspace is stated EXPLICITLY rather than left at "auto", which also
 * keeps this off OpenColorIO entirely: detect_known_colorspace returns
 * immediately for the two builtin names and only reaches for a config for
 * anything else. An iPad has no OCIO config and does not need one. */
ccl::ImageTextureNode *box_image(ccl::ShaderGraph *graph,
                                 const char *path,
                                 const bool srgb,
                                 ccl::ShaderOutput *uv)
{
  if (!file_readable(path)) {
    return nullptr;
  }
  ccl::ImageTextureNode *tex = graph->create_node<ccl::ImageTextureNode>();
  tex->set_filename(ccl::ustring(path));
  tex->set_colorspace(srgb ? ccl::u_colorspace_srgb : ccl::u_colorspace_raw);
  tex->set_projection(ccl::NODE_IMAGE_PROJ_BOX);
  tex->set_projection_blend(kProjectionBlend);
  tex->set_extension(ccl::EXTENSION_REPEAT);
  tex->set_interpolation(ccl::INTERPOLATION_LINEAR);
  /* Alpha is never wanted from any of these maps, and an image whose alpha
   * Cycles decides is "associated" would otherwise premultiply the colour. */
  tex->set_alpha_type(ccl::IMAGE_ALPHA_IGNORE);
  graph->connect(uv, tex->input("Vector"));
  return tex;
}

/* One image channel as a float, through the luminance node. */
ccl::ShaderOutput *image_as_float(ccl::ShaderGraph *graph, ccl::ImageTextureNode *tex)
{
  ccl::RGBToBWNode *bw = graph->create_node<ccl::RGBToBWNode>();
  graph->connect(tex->output("Color"), bw->input("Color"));
  return bw->output("Val");
}

/* [value] scaled by a greyscale map, or nothing when there is no map.
 *
 * MULTIPLIED rather than replaced. The map says how the finish VARIES across
 * the surface and the number says what the finish IS — an aluminium at 0.25
 * and a cast iron at 0.8 can share one brushed-grain map and still be two
 * different materials. Replacing would throw the appearance the user chose
 * away the moment a texture existed. */
ccl::ShaderOutput *scaled_by_map(ccl::ShaderGraph *graph,
                                 ccl::ImageTextureNode *tex,
                                 const float value)
{
  if (tex == nullptr) {
    return nullptr;
  }
  ccl::MathNode *mul = graph->create_node<ccl::MathNode>();
  mul->set_math_type(ccl::NODE_MATH_MULTIPLY);
  mul->set_value2(value);
  mul->set_use_clamp(true);
  graph->connect(image_as_float(graph, tex), mul->input("Value1"));
  return mul->output("Value");
}

/* Build the Shader for [m]. */
ccl::Shader *build_surface(ccl::Scene *scene, const CyMaterial &m)
{
  ccl::unique_ptr<ccl::ShaderGraph> graph = ccl::make_unique<ccl::ShaderGraph>();
  ccl::PrincipledBsdfNode *bsdf = graph->create_node<ccl::PrincipledBsdfNode>();

  bsdf->set_base_color(ccl::make_float3(m.color[0], m.color[1], m.color[2]));
  bsdf->set_roughness(clamp01(m.roughness));
  bsdf->set_metallic(clamp01(m.metallic));
  bsdf->set_specular_ior_level(clamp01(m.specular));
  bsdf->set_coat_weight(clamp01(m.coat));
  bsdf->set_coat_roughness(clamp01(m.coat_roughness));
  bsdf->set_anisotropic(m.anisotropy < -1.0f ? -1.0f : (m.anisotropy > 1.0f ? 1.0f : m.anisotropy));
  bsdf->set_sheen_weight(clamp01(m.sheen));
  if (m.emission_strength > 0.0f) {
    bsdf->set_emission_color(
        ccl::make_float3(m.emission[0], m.emission[1], m.emission[2]));
    bsdf->set_emission_strength(m.emission_strength);
  }

  /* ---- the texture coordinate ------------------------------------------
   *
   * OBJECT space, not Generated. Generated is normalised to the object's own
   * bounding box, so a bolt and the plate it goes through would get wildly
   * different texture densities from the same map — the classic tell of a
   * triplanar setup done in a hurry. Object space is world millimetres (every
   * object in this scene carries the identity transform, because the app bakes
   * placements into the vertices), so `texture_scale` means what it says: how
   * far across the part one tile of the texture covers.
   *
   * Only built when something actually samples a texture; a graph with an
   * unused coordinate chain in it is a graph Cycles has to walk. */
  const bool wants_textures = file_readable(m.base_map) ||
                              file_readable(m.roughness_map) ||
                              file_readable(m.metallic_map) ||
                              file_readable(m.bump_map) || file_readable(m.ao_map);

  ccl::ShaderOutput *uv = nullptr;
  if (wants_textures) {
    ccl::TextureCoordinateNode *co = graph->create_node<ccl::TextureCoordinateNode>();
    ccl::MappingNode *map = graph->create_node<ccl::MappingNode>();
    map->set_mapping_type(ccl::NODE_MAPPING_TYPE_POINT);
    const float s = (m.texture_scale > 1e-6f) ? 1.0f / m.texture_scale : 1.0f;
    map->set_scale(ccl::make_float3(s, s, s));
    graph->connect(co->output("Object"), map->input("Vector"));
    uv = map->output("Vector");
  }

  if (uv != nullptr) {
    /* ---- base colour ---------------------------------------------------
     *
     * The map MULTIPLIES the chosen colour rather than replacing it, so one
     * grey brushed-metal texture serves aluminium, brass and copper and the
     * user's appearance still decides which. A texture that is already the
     * colour it wants to be is authored near white and the multiply is a
     * no-op, which is the ordinary convention. */
    ccl::ImageTextureNode *base = box_image(graph.get(), m.base_map, true, uv);
    ccl::ImageTextureNode *ao = box_image(graph.get(), m.ao_map, false, uv);
    ccl::ShaderOutput *color = nullptr;
    if (base != nullptr) {
      ccl::MixColorNode *tint = graph->create_node<ccl::MixColorNode>();
      tint->set_blend_type(ccl::NODE_MIX_MUL);
      tint->set_fac(1.0f);
      tint->set_b(ccl::make_float3(m.color[0], m.color[1], m.color[2]));
      graph->connect(base->output("Color"), tint->input("A"));
      color = tint->output("Result");
    }
    if (ao != nullptr) {
      /* AMBIENT OCCLUSION IS A CHEAT AND IT IS USED AS ONE. A path tracer
       * computes real occlusion, so baking more of it into the albedo is
       * double counting. What the map is here for is the sub-millimetre
       * crevices the tessellation does not have — the bottom of a knurl, the
       * pores of a casting — which no amount of tracing can find in geometry
       * that is smooth. Half strength, for that reason. */
      ccl::MixColorNode *mix = graph->create_node<ccl::MixColorNode>();
      mix->set_blend_type(ccl::NODE_MIX_MUL);
      mix->set_fac(0.5f);
      if (color != nullptr) {
        graph->connect(color, mix->input("A"));
      }
      else {
        mix->set_a(ccl::make_float3(m.color[0], m.color[1], m.color[2]));
      }
      graph->connect(ao->output("Color"), mix->input("B"));
      color = mix->output("Result");
    }
    if (color != nullptr) {
      graph->connect(color, bsdf->input("Base Color"));
    }

    /* ---- finish --------------------------------------------------------- */
    ccl::ShaderOutput *rough = scaled_by_map(
        graph.get(), box_image(graph.get(), m.roughness_map, false, uv), clamp01(m.roughness));
    if (rough != nullptr) {
      graph->connect(rough, bsdf->input("Roughness"));
    }
    ccl::ShaderOutput *metal = scaled_by_map(
        graph.get(), box_image(graph.get(), m.metallic_map, false, uv), clamp01(m.metallic));
    if (metal != nullptr) {
      graph->connect(metal, bsdf->input("Metallic"));
    }

    /* ---- relief ----------------------------------------------------------
     *
     * A BumpNode with only its Height linked is the whole setup: ShaderGraph::
     * refine_bump_nodes() copies the subgraph feeding Height into the
     * SampleX/SampleY inputs at offset positions and differentiates it there,
     * in world space. That is what makes a height map work under a box
     * projection at all — there is no tangent frame anywhere in this, and
     * there could not be one, because each of the three projections would want
     * a different one. */
    ccl::ImageTextureNode *height = box_image(graph.get(), m.bump_map, false, uv);
    if (height != nullptr && m.bump_strength > 0.0f) {
      ccl::BumpNode *bump = graph->create_node<ccl::BumpNode>();
      bump->set_strength(clamp01(m.bump_strength));
      bump->set_distance(m.bump_distance > 0.0f ? m.bump_distance : 0.001f);
      graph->connect(image_as_float(graph.get(), height), bump->input("Height"));
      graph->connect(bump->output("Normal"), bsdf->input("Normal"));
    }
  }

  graph->connect(bsdf->output("BSDF"), graph->output()->input("Surface"));

  ccl::Shader *shader = scene->create_node<ccl::Shader>();
  shader->name = ccl::ustring("body");
  shader->set_graph(std::move(graph));
  shader->tag_update(scene);
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
 * THE RIG IS RealityKit's, deliberately. RealityPartView.applyLighting() has
 * been tuned against real parts for several milestones, so its four directions
 * and its ratios are copied here rather than invented again:
 *
 *     headlight  620 lux, camera-locked   key
 *     sun        950 lux, from ( 7, 14,  9)   casts the shadow
 *     fill       380 lux, from (-3,  6, -4)
 *     rim        380 lux, from (-9,  7,-12)
 *
 * The world is Y-UP; those vectors are in that frame, unchanged from the Swift.
 *
 * FROM LUX TO STRENGTH. A Cycles distant light with `normalize` on — the
 * default — has a `strength` that IS irradiance in W/m^2, so what carries over
 * from RealityKit is the RATIO; kSunStrength fixes the one absolute value.
 *
 * M344 — AND WHY IT SURVIVES THE HDRI. An environment map lights beautifully
 * and casts nothing sharp: every shadow it throws is the soft average of a
 * whole room. A part rendered under an HDRI alone floats, because the one cue
 * that says "resting on the table" is a contact shadow with a direction. So
 * with an HDRI loaded the rig stays, at a fraction of its strength (CyEnv.rig)
 * — enough to keep the sun's shadow and the headlight's read, far too little
 * to compete with the environment for what the specular reflects. */
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
ccl::Transform light_basis(const ccl::float3 &from)
{
  const ccl::float3 z = ccl::normalize(from);
  const float zy = z.y < 0.0f ? -z.y : z.y;
  const ccl::float3 up = zy < 0.99f ? ccl::make_float3(0.0f, 1.0f, 0.0f) :
                                      ccl::make_float3(1.0f, 0.0f, 0.0f);
  const ccl::float3 x = ccl::normalize(ccl::cross(up, z));
  const ccl::float3 y = ccl::cross(z, x);
  return ccl::make_transform(x.x, y.x, z.x, 0.0f,
                             x.y, y.y, z.y, 0.0f,
                             x.z, y.z, z.z, 0.0f);
}

/* One light and its object, or nulls when there was nothing to add. */
struct Lamp {
  ccl::Light *light = nullptr;
  ccl::Object *object = nullptr;
};

Lamp add_distant_light(ccl::Scene *scene,
                       ccl::Shader *shader,
                       const ccl::float3 &from,
                       const float strength,
                       const bool cast_shadow,
                       const float angle)
{
  Lamp lamp;
  if (strength <= 0.0f || ccl::len(from) <= 0.0f) {
    return lamp;
  }
  lamp.light = scene->create_node<ccl::Light>();
  lamp.light->set_light_type(ccl::LIGHT_DISTANT);
  lamp.light->set_strength(ccl::make_float3(strength, strength, strength));
  lamp.light->set_angle(angle);
  lamp.light->set_cast_shadow(cast_shadow);
  ccl::array<ccl::Node *> used_shaders;
  used_shaders.push_back_slow(shader);
  lamp.light->set_used_shaders(used_shaders);
  lamp.light->tag_update(scene);

  lamp.object = scene->create_node<ccl::Object>();
  lamp.object->set_geometry(lamp.light);
  lamp.object->set_tfm(light_basis(from));
  return lamp;
}

/* Build the four lights, scaled by [rig], with the headlight aimed along the
 * camera's forward direction [forward].
 *
 * Returns the HEADLIGHT, because it is the one that has to move again. */
Lamp build_rig(ccl::Scene *scene, const ccl::float3 &forward, const float rig)
{
  if (rig <= 0.0f) {
    return Lamp();
  }
  ccl::Shader *shader = rig_shader(scene);
  const float k = kRigScale * rig;
  /* The headlight sits at the camera and shines along its view direction.
   * Column 2 of the camera-to-world basis IS that direction — Cycles'
   * Camera::matrix is (right, up, FORWARD, eye) — so the light that follows
   * the camera needs no separate input and cannot fall out of step with it. */
  const Lamp head = add_distant_light(scene, shader, -forward, kRigHead * k, true, 0.0f);
  add_distant_light(
      scene, shader, ccl::make_float3(7.0f, 14.0f, 9.0f), kRigSun * k, true, kSunAngle);
  add_distant_light(
      scene, shader, ccl::make_float3(-3.0f, 6.0f, -4.0f), kRigFill * k, false, 0.0f);
  add_distant_light(
      scene, shader, ccl::make_float3(-9.0f, 7.0f, -12.0f), kRigRim * k, false, 0.0f);
  return head;
}

/* Re-aim the camera-locked headlight, without touching anything else.
 *
 * WHY THIS IS NOT "delete the lights and call build_rig again", which is what
 * the first version did and what looks equivalent. Scene::delete_nodes on a
 * set of Geometry tags the GEOMETRY MANAGER, and a tagged geometry manager
 * rebuilds the BVH — of the whole model, on every frame of an orbit, for four
 * lights that have no geometry in it. Moving one object's transform tags the
 * light manager and nothing else. */
void aim_headlight(ccl::Scene *scene, const Lamp &head, const ccl::float3 &forward)
{
  if (head.object == nullptr || head.light == nullptr) {
    return;
  }
  head.object->set_tfm(light_basis(-forward));
  /* The transform is read by LightManager, not by ObjectManager — a distant
   * light's direction is baked into the kernel light record from the object's
   * third column — so it is the light manager that has to be told. */
  head.light->tag_update(scene);
}

/* ---------------------------------------------------------------------------
 * THE WORLD
 * ---------------------------------------------------------------------------
 *
 * M332 — THE BACKGROUND YOU SEE AND THE LIGHT IT CASTS ARE NOT THE SAME
 * NUMBER, and that separation is what makes the HDRI shippable.
 *
 * Cycles can tell which ray is asking. A CAMERA ray gets the app's own
 * viewport colour at full strength, so the path-traced image sits on exactly
 * the ground the rest of the app is drawing rather than as a bright rectangle
 * in the middle of a charcoal viewport. Every OTHER ray — the ones that carry
 * light onto surfaces — gets the environment.
 *
 * Without an HDRI that other half is a small fraction of the same viewport
 * colour: enough to keep a cavity from going pure black, far too little to
 * flatten the rig. With one it is the environment map, at full strength, and
 * it is the light. Either way the picture keeps the app's background unless
 * the caller asks for the environment to be visible.
 *
 * A FRACTION, not a constant, and it is worth saying why. Chalk's viewport is
 * 0xFCFBF8, linear 0.96, so 0.15 of it puts about 0.036 on a steel face — a
 * real if modest lift. The dark scheme's is 0x201D19, linear 0.012, and the
 * same fraction puts 0.0005 there, which is nothing. That is correct: a room
 * whose walls are that dark really does bounce nothing, and what keeps the
 * model from having black faces is the camera-locked headlight and the floor
 * bounce, not this.
 */
void build_world(ccl::Scene *scene, const CyEnv &env)
{
  if (scene->default_background == nullptr) {
    return;
  }
  const ccl::float3 world = ccl::make_float3(env.world[0], env.world[1], env.world[2]);
  const bool hdri = file_readable(env.hdri);

  ccl::unique_ptr<ccl::ShaderGraph> graph = ccl::make_unique<ccl::ShaderGraph>();

  /* What lights the scene. */
  ccl::BackgroundNode *light = graph->create_node<ccl::BackgroundNode>();
  if (hdri) {
    ccl::EnvironmentTextureNode *tex = graph->create_node<ccl::EnvironmentTextureNode>();
    tex->set_filename(ccl::ustring(env.hdri));
    /* An HDR or an EXR is already scene-linear. Saying so explicitly is what
     * keeps this off OpenColorIO — see box_image. */
    tex->set_colorspace(ccl::u_colorspace_raw);
    tex->set_projection(ccl::NODE_ENVIRONMENT_EQUIRECTANGULAR);
    tex->set_interpolation(ccl::INTERPOLATION_LINEAR);
    tex->set_alpha_type(ccl::IMAGE_ALPHA_IGNORE);

    /* ---- Y-UP TO Z-UP, WHICH IS NOT OPTIONAL --------------------------
     *
     * Cycles' equirectangular projection is Blender's, and Blender is Z-up:
     * direction_to_equirectangular takes the POLE along +Z. This app's world
     * is Y-up (RealityPartView.commonInit, PartCamera.dir, the ViewCube's top
     * face — the sketch planes make it look otherwise and they are the
     * exception). Handing the ray direction straight to the node therefore
     * wraps the sky around the horizon and lays the floor of the studio up one
     * side of the model. It does not look like a convention error; it looks
     * like a bad HDRI.
     *
     * A quarter turn about X maps +Y to +Z. Cycles composes a Mapping node's
     * Euler as Rz * Ry * Rx, so putting the user's rotation in Z spins the
     * environment about what is, after that quarter turn, the world's own up
     * axis. Which is what "turn the studio to aim the softbox" has to mean. */
    ccl::GeometryNode *geo = graph->create_node<ccl::GeometryNode>();
    ccl::MappingNode *map = graph->create_node<ccl::MappingNode>();
    map->set_mapping_type(ccl::NODE_MAPPING_TYPE_POINT);
    map->set_rotation(ccl::make_float3(1.57079632679f, 0.0f, env.hdri_rotation));
    graph->connect(geo->output("Position"), map->input("Vector"));
    graph->connect(map->output("Vector"), tex->input("Vector"));

    graph->connect(tex->output("Color"), light->input("Color"));
    light->set_strength(env.hdri_strength > 0.0f ? env.hdri_strength : 1.0f);
  }
  else {
    light->set_color(world);
    light->set_strength(env.ambient > 0.0f ? env.ambient : 0.0f);
  }

  /* What the camera sees. */
  if (hdri && env.hdri_visible != 0) {
    graph->connect(light->output("Background"), graph->output()->input("Surface"));
  }
  else {
    ccl::BackgroundNode *seen = graph->create_node<ccl::BackgroundNode>();
    seen->set_color(world);
    seen->set_strength(1.0f);

    /* MixClosureNode takes Closure1 at Fac 0 and Closure2 at Fac 1 — its own
     * constant_fold is the statement of that, bypassing to Closure1 when the
     * factor is <= 0. "Is Camera Ray" is 1 for the rays that draw the picture,
     * so the visible background is Closure2 and the light is Closure1. */
    ccl::LightPathNode *path = graph->create_node<ccl::LightPathNode>();
    ccl::MixClosureNode *mix = graph->create_node<ccl::MixClosureNode>();
    graph->connect(path->output("Is Camera Ray"), mix->input("Fac"));
    graph->connect(light->output("Background"), mix->input("Closure1"));
    graph->connect(seen->output("Background"), mix->input("Closure2"));
    graph->connect(mix->output("Closure"), graph->output()->input("Surface"));
  }

  /* WHAT IS NOT DONE HERE, and what it cost. The obvious-looking pair
   *
   *     scene->background->set_shader(world);
   *     scene->background->tag_update(scene);
   *
   * segfaulted on device, in Background::tag_update, and took build 619 down
   * at launch. They are also unnecessary: Background::get_shader returns
   * `(use_shader) ? (shader ? shader : scene->default_background) : ...`, and
   * use_shader defaults to true with shader null, so the world IS
   * default_background already. Setting the graph on it is the whole job. */
  ccl::Shader *shader = scene->default_background;
  shader->set_graph(std::move(graph));
  shader->tag_update(scene);
}

/* ---------------------------------------------------------------------------
 * GEOMETRY
 * ------------------------------------------------------------------------- */

void build_mesh(ccl::Scene *scene, const CyMesh &src, ccl::Shader *shader)
{
  ccl::Mesh *mesh = scene->create_node<ccl::Mesh>();

  ccl::array<ccl::Node *> used_shaders;
  used_shaders.push_back_slow(shader);
  mesh->set_used_shaders(used_shaders);

  mesh->resize_mesh(src.vert_count, src.tri_count);
  auto *P = mesh_positions(mesh, 0);
  for (int v = 0; v < src.vert_count; v++) {
    P[v] = ccl::make_float3(
        src.verts[v * 3 + 0], src.verts[v * 3 + 1], src.verts[v * 3 + 2]);
  }
  mesh_tag_positions(mesh, 0);

  /* The caller's normals, as the vertex-normal attribute Cycles shades with.
   * Without this, `smooth` below would make Cycles average the face normals it
   * computed itself, and on a CAD body that rounds off every edge that is
   * supposed to be sharp — the tessellator already knows which edges are which
   * and has told us in `normals`. */
  if (src.normals != nullptr) {
    ccl::Attribute *attr = mesh->attributes.add(ccl::ATTR_STD_VERTEX_NORMAL);
    ccl::float3 *N = attr->data_float3();
    for (int v = 0; v < src.vert_count; v++) {
      N[v] = ccl::normalize(ccl::make_float3(
          src.normals[v * 3 + 0], src.normals[v * 3 + 1], src.normals[v * 3 + 2]));
    }
  }

  ccl::array<int> &tris = mesh->get_triangles();
  ccl::array<int> &shader_index = mesh->get_shader();
  ccl::array<bool> &smooth = mesh->get_smooth();
  for (int t = 0; t < src.tri_count; t++) {
    tris[t * 3 + 0] = src.tris[t * 3 + 0];
    tris[t * 3 + 1] = src.tris[t * 3 + 1];
    tris[t * 3 + 2] = src.tris[t * 3 + 2];
    shader_index[t] = 0;
    smooth[t] = src.normals != nullptr;
  }
  mesh->tag_triangles_modified();
  mesh->tag_shader_modified();
  mesh->tag_smooth_modified();

  ccl::Object *object = scene->create_node<ccl::Object>();
  object->set_geometry(mesh);
  object->set_tfm(ccl::transform_identity());
}

/* Put [meshes] and their materials into [scene], and the world with them.
 *
 * ONE SHADER PER MATERIAL, built once and shared. An assembly is routinely
 * hundreds of pieces drawn from a handful of appearances, and a Shader per
 * piece means a ShaderGraph per piece for Cycles to compile and deduplicate —
 * with textures in it, that is also one ImageHandle per piece for the same
 * file. */
Lamp build_scene(ccl::Scene *scene,
                 const CyMesh *meshes,
                 const int mesh_count,
                 const CyMaterial *materials,
                 const int material_count,
                 const CyEnv &env,
                 const ccl::float3 &forward)
{
  build_world(scene, env);
  const Lamp head = build_rig(scene, forward, env.rig);

  std::vector<ccl::Shader *> shaders((size_t)(material_count > 0 ? material_count : 0), nullptr);
  ccl::Shader *steel = nullptr;

  for (int i = 0; i < mesh_count; i++) {
    const CyMesh &src = meshes[i];
    if (src.vert_count <= 0 || src.tri_count <= 0 || src.verts == nullptr ||
        src.tris == nullptr)
    {
      continue;
    }
    ccl::Shader *shader = nullptr;
    if (materials != nullptr && src.material >= 0 && src.material < material_count) {
      if (shaders[(size_t)src.material] == nullptr) {
        shaders[(size_t)src.material] = build_surface(scene, materials[src.material]);
      }
      shader = shaders[(size_t)src.material];
    }
    else {
      if (steel == nullptr) {
        steel = build_surface(scene, steel_material());
      }
      shader = steel;
    }
    build_mesh(scene, src, shader);
  }
  return head;
}

/* Everything this shim put in [scene], removed.
 *
 * ORDER MATTERS: an Object that outlives its Geometry is a dangling pointer
 * the object manager will walk. Objects, then geometry (which is where the
 * lights live too — a Light is a Geometry in this tree), then the shaders
 * nothing references any more.
 *
 * `scene->default_background` is deliberately not in the list. It is Cycles'
 * own node, the world's graph is simply replaced on it, and deleting it would
 * take the fallback every later scene relies on with it. */
void clear_scene(ccl::Scene *scene)
{
  ccl::set<ccl::Object *> objects;
  for (ccl::Object *o : scene->objects) {
    objects.insert(o);
  }
  scene->delete_nodes(objects);

  ccl::set<ccl::Geometry *> geometry;
  for (ccl::Geometry *g : scene->geometry) {
    geometry.insert(g);
  }
  scene->delete_nodes(geometry);

  ccl::set<ccl::Shader *> shaders;
  for (ccl::Shader *s : scene->shaders) {
    if (s != scene->default_surface && s != scene->default_volume &&
        s != scene->default_light && s != scene->default_background &&
        s != scene->default_empty)
    {
      shaders.insert(s);
    }
  }
  scene->delete_nodes(shaders);
}

/* ---------------------------------------------------------------------------
 * THE CAMERA
 * ------------------------------------------------------------------------- */

/* The camera's forward direction: column 2 of the row-major 3x4. */
ccl::float3 view_forward(const CyView &view)
{
  return ccl::make_float3(view.matrix[2], view.matrix[6], view.matrix[10]);
}

void apply_view(ccl::Scene *scene, const CyView &view)
{
  ccl::Camera *cam = scene->camera;
  const float *m = view.matrix;
  cam->set_matrix(ccl::make_transform(m[0], m[1], m[2], m[3],
                                      m[4], m[5], m[6], m[7],
                                      m[8], m[9], m[10], m[11]));
  cam->set_camera_type(ccl::CAMERA_ORTHOGRAPHIC);
  cam->set_full_width(view.width);
  cam->set_full_height(view.height);
  cam->set_screen_size(view.width, view.height);
  /* For an orthographic camera the viewplane IS the extent in world units, so
   * it is set rather than computed — compute_auto_viewplane would derive it
   * from the aspect ratio alone and lose the scale the caller asked for. */
  cam->set_viewplane_left(-view.half_width);
  cam->set_viewplane_right(view.half_width);
  cam->set_viewplane_bottom(-view.half_height);
  cam->set_viewplane_top(view.half_height);
  cam->need_flags_update = true;
  cam->update(scene);
}

/* ---------------------------------------------------------------------------
 * PASSES AND THE INTEGRATOR
 * ------------------------------------------------------------------------- */

void add_pass(ccl::Scene *scene, const char *name, const ccl::PassType type)
{
  ccl::Pass *pass = scene->create_node<ccl::Pass>();
  pass->set_name(ccl::ustring(name));
  pass->set_type(type);
}

/* The one pass the frame is built from.
 *
 * M353 — THE GUIDE PASSES ARE GONE WITH THE DENOISER THEY GUIDED.
 *
 * PASS_DENOISING_ALBEDO and PASS_DENOISING_NORMAL exist to tell a denoiser
 * what a pixel is made of and which way it faces. Nothing denoises here any
 * more, so they are two passes nobody reads — and they were never free, which
 * is the part the old comment had wrong:
 *
 *   * asking for either turns on KERNEL_FEATURE_DENOISING
 *     (Film::get_kernel_features), so every surface hit does the extra work of
 *     recording both, on the GPU, for every sample;
 *   * they widen Cycles' render buffer by six floats per pixel, which at a
 *     full-resolution iPad frame is around 130 MB of GPU memory;
 *   * and every capture pulled both across with get_pass_pixels — two more
 *     full-frame reads per displayed frame, on the render thread.
 *
 * Restoring them is one line each; see the note in cy_live_frame for the rest
 * of what turning the filter back on takes. */
void add_passes(ccl::Scene *scene)
{
  add_pass(scene, "combined", ccl::PASS_COMBINED);
}

/* M344 — ADAPTIVE SAMPLING, which is what "until a perfect image is there"
 * actually means.
 *
 * Without it every pixel gets the same number of samples: the flat lit face
 * that was clean at sample eight goes on being sampled three hundred times
 * while the contact shadow that needs them is still noisy. With it Cycles
 * measures each pixel's own error and stops sampling the ones that are done,
 * spending what is left where the noise is. On a CAD scene — large smooth
 * areas, noise concentrated in a few soft shadows and glossy reflections —
 * that is most of the render time.
 *
 * It is also what lets the session KNOW it is finished rather than merely
 * having counted to a number, which is what the badge reports and what turns
 * the GPU off when there is nothing left to improve.
 *
 * The two clamps are the standard firefly control. A single path that finds a
 * bright specular through a rough bounce lands one pixel at a hundred times
 * its neighbours; the eye reads that as a white dot, the average takes
 * thousands of samples to forget it, and no denoiser guided by albedo and
 * normal can remove it because it is not a discontinuity in either. Clamping
 * indirect light is a small, well-understood bias in exchange for that, and it
 * is what Blender's own defaults do for a viewport. Direct light is left
 * alone: that is where the real highlights are. */
void configure_integrator(ccl::Scene *scene, const int samples)
{
  ccl::Integrator *ig = scene->integrator;
  ig->set_use_adaptive_sampling(true);
  /* 0 means "work it out from the threshold", which is what Blender does. */
  ig->set_adaptive_min_samples(0);
  ig->set_adaptive_threshold(0.01f);
  ig->set_aa_samples(samples);

  ig->set_sample_clamp_indirect(10.0f);
  ig->set_filter_glossy(1.0f);

  /* Bounce depths. Cycles' defaults are tuned for film; a CAD scene of opaque
   * solids on a floor gets everything it is going to get from four diffuse
   * bounces, and each one past that is time spent on light that is already
   * below the noise floor. Transmission is left generous because a machined
   * part in acrylic is a thing people render. */
  ig->set_max_bounce(8);
  ig->set_max_diffuse_bounce(4);
  ig->set_max_glossy_bounce(4);
  ig->set_max_transmission_bounce(8);
  ig->set_max_volume_bounce(0);

  ig->tag_update(scene, ccl::Integrator::UPDATE_ALL);
}

/* ---------------------------------------------------------------------------
 * OUT
 * ------------------------------------------------------------------------- */

/* M332 — LINEAR IN, sRGB OUT.
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

/* The most recent frame Cycles produced, in floats, waiting to be asked for.
 *
 * WHY IT IS A COPY AND NOT A POINTER INTO CYCLES. `update_render_tile` is
 * called on the render thread, between path-tracing iterations, and the buffer
 * it reads from is device memory that the next iteration will overwrite. The
 * frame has to be taken out of Cycles' hands right there, under a lock, and
 * handed to the reader later. One vector and a memcpy per display update is a
 * few hundred microseconds on a viewport-sized image and it is the price of
 * not having a torn frame.
 *
 * The RGBA channel count on `color` is Cycles' own for PASS_COMBINED. M353
 * removed the albedo and normal companions with the denoiser that read them. */
struct FrameStore {
  std::mutex mutex;
  std::vector<float> color;
  int width = 0;
  int height = 0;
  int samples = 0;
  /* Sampling for this view is finished and the picture will not improve.
   *
   * TAKEN FROM CYCLES RATHER THAN COUNTED HERE, because counting gets it
   * wrong: `progress_update_if_needed` runs AFTER the display update in
   * PathTrace::render_pipeline, so the sample count visible when a frame is
   * captured is always one work item behind and never reaches the target. The
   * scheduler's own answer is exact — `render_work.tile.write = done()` — and
   * it arrives as a call to write_render_tile.
   *
   * STICKY within a view, because that same final work item calls
   * write_render_tile and THEN update_render_tile with the same pixels, and a
   * plain assignment would have the second call clear what the first set. */
  bool finished = false;
  /* Bumped by every capture. The reader remembers the last one it saw, so a
   * poll that is faster than the render costs nothing. */
  uint64_t serial = 0;
  /* Which view the frame belongs to. A capture whose generation is not the
   * current one is dropped: it is a picture of where the camera USED to be,
   * and during an orbit that is a frame behind rather than a frame late. */
  uint64_t generation = 0;

  void clear()
  {
    const std::lock_guard<std::mutex> lock(mutex);
    clear_locked();
  }

  /* The same, for a caller that is already holding [mutex] because it has
   * something else to do atomically with the clear — see restart(). */
  void clear_locked()
  {
    width = 0;
    height = 0;
    samples = 0;
    finished = false;
  }
};

FrameStore g_frame;
/* Set by the output driver when the combined pass could not be read, which
 * means the scene has no such pass and no render will ever produce a frame. */
std::atomic<bool> g_pass_failed{false};
/* Which view is current. Written under the shim's own lock, read on the render
 * thread inside the output driver. */
std::atomic<uint64_t> g_generation{1};
/* The image size the current view asked for.
 *
 * NEEDED BECAUSE A RESET IS NOT INSTANT. Session::reset queues a delayed reset
 * and the render thread applies it at the next safe point, so between a call
 * to cy_live_view that changes the size and the frame that honours it there
 * are one or two frames STILL AT THE OLD SIZE — and they carry the new
 * generation, because the driver stamps that when it captures. The caller has
 * by then sized its buffer for the new one. Without this check the first frame
 * of every resize is either refused as too large (which is how an ordinary
 * zoom would have looked like a renderer failure) or shown at the wrong scale. */
std::atomic<int> g_want_width{0};
std::atomic<int> g_want_height{0};

/* Copies frames out of Cycles, finished or not.
 *
 * `write_render_tile` is the finished frame and `update_render_tile` is an
 * in-progress one; they are the same job here, because a viewport shows
 * whatever it has. The distinction Cycles draws between them matters to a file
 * writer, which must not emit a half-finished EXR, and not to a display. */
class LiveOutput : public ccl::OutputDriver {
 public:
  explicit LiveOutput(ccl::Session *session) : session_(session) {}

  void write_render_tile(const Tile &tile) override
  {
    capture(tile, true);
  }

  bool update_render_tile(const Tile &tile) override
  {
    capture(tile, false);
    return true;
  }

 private:
  void capture(const Tile &tile, const bool finished)
  {
    /* Auto-tiling is off, so the only tile is the whole frame. Written as the
     * reference driver writes it (`!(a == b)`), because int2's operator!= is
     * not something to assume. */
    if (!(tile.size == tile.full_size)) {
      return;
    }
    const int w = tile.size.x;
    const int h = tile.size.y;
    if (w <= 0 || h <= 0) {
      return;
    }
    /* A frame from before the last resize took effect. See g_want_width. */
    if (w != g_want_width.load() || h != g_want_height.load()) {
      return;
    }
    const size_t n = (size_t)w * (size_t)h;

    color_.resize(n * 4);
    if (!tile.get_pass_pixels("combined", 4, color_.data())) {
      /* REPORTED THROUGH A FLAG, not through set_error. This runs on Cycles'
       * render thread; g_error is a std::string that cy_last_error hands out a
       * pointer into, and writing it from here while the caller reads it is
       * the one data race in this file that would be a real one. The caller
       * turns the flag into a sentence on its own thread. */
      g_pass_failed.store(true);
      return;
    }
    /* Cycles' own count, which is the number get_pass_pixels has already
     * divided by. Read after the pixels so it can only ever under-report,
     * never claim more convergence than the image has. */
    const int samples = session_ != nullptr ? session_->progress.get_current_sample() : 0;

    const std::lock_guard<std::mutex> lock(g_frame.mutex);
    g_frame.color.swap(color_);
    g_frame.width = w;
    g_frame.height = h;
    g_frame.samples = samples > 0 ? samples : 1;
    g_frame.finished = g_frame.finished || finished;
    g_frame.generation = g_generation.load();
    g_frame.serial++;
  }

  ccl::Session *session_;
  /* Kept between captures so an orbit does not allocate a buffer thirty times
   * a second. Swapped with the store's, so both sides keep a buffer of the
   * right size and neither reallocates after the first frame. */
  std::vector<float> color_;
};

/* ---------------------------------------------------------------------------
 * THE DEVICE
 * ---------------------------------------------------------------------------
 *
 * METAL IS REQUIRED, not preferred. Cycles has a CPU device and falling back to
 * it is the wrong behaviour here: the same image an iPad's GPU produces in a
 * few seconds takes its CPU minutes, on battery, while the app appears hung.
 *
 * M342 — CYCLES_SHIM_CPU_FOR_TESTS IS NOT A FALLBACK. It is never set by the
 * app — an iOS app launched normally has no such variable in its environment,
 * and nothing in this repository writes one — and it exists for exactly one
 * caller: the host render test in .github/workflows/cycles-render-test.yml.
 *
 * WHY THAT TEST NEEDS IT. The GitHub macOS runner does have a Metal device; it
 * reports itself as "Apple Paravirtual device (GPU)". What it cannot do in any
 * usable time is COMPILE Cycles' Metal kernels from source — run 13 sat on it
 * for 116 minutes and hit the job timeout having printed the device name and
 * nothing else. Nothing the test exists for was in that 116 minutes: scene
 * construction, the camera basis, materials, the light rig and the output
 * driver are device-independent code that runs identically on both backends. */
bool pick_device(ccl::DeviceInfo &out)
{
  const bool cpu_for_tests = getenv("CYCLES_SHIM_CPU_FOR_TESTS") != nullptr;
  const ccl::DeviceType wanted = cpu_for_tests ? ccl::DEVICE_CPU : ccl::DEVICE_METAL;
  const ccl::vector<ccl::DeviceInfo> devices = ccl::Device::available_devices();
  for (const ccl::DeviceInfo &info : devices) {
    if (info.type == wanted) {
      out = info;
      return true;
    }
  }
  return false;
}

const char *no_device_reason()
{
  return getenv("CYCLES_SHIM_CPU_FOR_TESTS") != nullptr ?
             "no CPU device — the host render test cannot run" :
             "no Metal device — this build renders on the GPU only";
}

/* ---------------------------------------------------------------------------
 * THE LIVE SESSION
 * ------------------------------------------------------------------------- */

/* One lock over everything. The app drives all of this from a single worker
 * isolate, so it is uncontended in practice; what it is for is the one case
 * that would otherwise be a race — cy_preload's one-shot render running while
 * the viewport's session is being opened. */
std::recursive_mutex g_lock;

struct Live {
  ccl::unique_ptr<ccl::Session> session;
  ccl::SessionParams session_params;
  ccl::BufferParams buffer_params;
  bool open = false;
  bool has_view = false;
  bool has_scene = false;
  int target = 0;
  /* The last frame handed to the caller, so a poll can answer "nothing new"
   * without copying anything. */
  uint64_t seen = 0;
  /* The frame being converted to bytes.
   *
   * A MEMBER RATHER THAN A LOCAL, and it matters: a full-resolution iPad frame
   * is over twenty megabytes of floats, and an orbit asks for a frame thirty
   * times a second. Allocating and touching that much memory per frame is the
   * kind of allocator pressure that shows up as a stutter rather than as a
   * slowdown. It grows once to the largest image asked for and never again.
   *
   * M353 removed `albedo`, `normal` and the denoiser's `ping` ping-pong space
   * from beside it — together four times this buffer's size. */
  std::vector<float> work;
  /* The camera-locked light, so a view change can re-aim it without the caller
   * re-sending the geometry. Null when the scene has not been set, or when the
   * caller asked for no analytic rig at all. */
  Lamp headlight;
};

Live g_live;

ccl::SessionParams make_session_params(const ccl::DeviceInfo &device,
                                       const int samples,
                                       const bool interactive)
{
  ccl::SessionParams p;
  p.device = device;
  /* SET EXPLICITLY, and it is not cosmetic: Session's constructor compares
   * `params.device == params.denoise_device` and, when they differ, brings up
   * a SECOND device for denoising. A default-constructed DeviceInfo is not the
   * Metal one, so leaving this alone creates a whole CPU device — threads,
   * memory, and a TaskScheduler — for a denoiser this build does not have. */
  p.denoise_device = device;
  p.background = !interactive;
  p.headless = !interactive;
  p.samples = samples > 0 ? samples : 32;
  /* Auto-tiling writes in-progress EXRs to a temp directory. A viewport-sized
   * image does not need tiling and an iOS app has no business writing scratch
   * files it never reads. */
  p.use_auto_tile = false;
  /* Cycles' own viewport trick is to render the first samples at half or
   * quarter resolution and scale them up. It is OFF here because this app does
   * the same thing one level higher and better: cyclesImageSize picks a
   * smaller image while the camera is moving, so the pixels that are skipped
   * are never allocated, transferred over the FFI boundary or denoised. Two
   * resolution ladders would fight, and Cycles' one would arrive at the output
   * driver as a tile smaller than the frame it claims to be. */
  p.use_resolution_divider = false;
  return p;
}

ccl::BufferParams make_buffer_params(const int width, const int height)
{
  /* The output driver's filter, set here rather than at the two call sites so
   * a third one cannot forget it. */
  g_want_width.store(width);
  g_want_height.store(height);
  ccl::BufferParams p;
  p.width = width;
  p.height = height;
  p.full_width = width;
  p.full_height = height;
  return p;
}

void close_live()
{
  if (g_live.session) {
    /* cancel() sets progress' cancel flag, which is terminal for the session
     * thread — it is the shutdown path, not a pause. */
    g_live.session->cancel(true);
    g_live.session.reset();
  }
  g_live.open = false;
  g_live.has_view = false;
  g_live.has_scene = false;
  g_live.seen = 0;
  g_live.headlight = Lamp();
  g_frame.clear();
}

bool open_live()
{
  if (g_live.open && g_live.session) {
    return true;
  }
  close_live();

  ccl::DeviceInfo device;
  if (!pick_device(device)) {
    set_error(no_device_reason());
    return false;
  }

  g_live.session_params = make_session_params(device, 64, true);
  ccl::SceneParams scene_params;
  g_live.session = ccl::make_unique<ccl::Session>(g_live.session_params, scene_params);

  ccl::Scene *scene = g_live.session->scene.get();
  watch_progress(g_live.session.get());
  add_passes(scene);
  configure_integrator(scene, g_live.session_params.samples);

  g_live.session->set_output_driver(
      ccl::make_unique<LiveOutput>(g_live.session.get()));

  g_live.buffer_params = make_buffer_params(64, 64);
  g_pass_failed.store(false);
  g_live.open = true;
  g_live.target = g_live.session_params.samples;
  return true;
}

/* Hand Cycles the current parameters and restart sampling.
 *
 * EVERY change goes through here — camera, size, geometry, world — because
 * every one of them invalidates the accumulated buffer.
 *
 * ---------------------------------------------------------------------------
 * M347 — THE ORDER OF THESE THREE STEPS IS THE WHOLE POINT
 * ---------------------------------------------------------------------------
 *
 * It used to bump the generation FIRST and reset afterwards, and that was a
 * race with a very bad prize.
 *
 * The output driver stamps every capture with `g_generation.load()` — the
 * generation as of the moment it copies the pixels, not the one the pixels
 * were rendered for. So a capture belonging to the PREVIOUS view that lands
 * after the bump is stamped with the NEW one, and the reader, whose only test
 * is that stamp, adopts it as a frame of the new camera. That alone would be
 * a frame of the wrong camera, which during an orbit is survivable.
 *
 * What is not survivable is the flag it brings with it. `write_render_tile`
 * fires when the previous view FINISHED, so the frame carries `finished` —
 * and that is sticky, and it is what the app reads as "sampling is over".
 * One mis-stamped capture and the viewport latches: the worker stops polling,
 * the badge reports the target sample count for an image that never reached
 * it, and the picture on screen — a low-resolution frame from the middle of
 * an orbit — is the last one that will ever be shown. That is the "it never
 * gets better than this" report this milestone came from.
 *
 * RESETTING FIRST CLOSES IT, and Cycles guarantees this rather than merely
 * making it likely. `Session::reset` calls `PathTrace::cancel`, which sets the
 * cancel flag and then blocks on a condition variable until the in-flight
 * `PathTrace::render` has returned (intern/cycles/integrator/path_trace.cpp).
 * Every call into an OutputDriver — `write_tile_buffer` and `update_display`
 * alike — happens inside that `render`. So by the time `reset` returns, no
 * capture from the old view can still be in flight, and bumping the
 * generation here means any capture that already landed is stamped with the
 * OLD one and is dropped, which is what it deserves.
 *
 * The remaining window runs the other way and is harmless: between `reset`
 * returning and the lock below, the render thread may already have applied
 * the delayed reset and captured a frame of the NEW view, which will be
 * stamped old and dropped. That costs one frame out of the ten or so a second
 * the session produces, and it self-corrects on the next one. Adopting a
 * stale frame does not self-correct — it ends the render.
 *
 * The bump and the clear are taken together under the frame lock so a capture
 * cannot interleave between them and leave a frame of the old view carrying
 * the new generation. */
void restart()
{
  g_live.session->reset(g_live.session_params, g_live.buffer_params);
  {
    const std::lock_guard<std::mutex> flock(g_frame.mutex);
    g_generation.fetch_add(1);
    g_frame.clear_locked();
  }
  g_live.session->start();
}

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
              const CyMaterial *materials,
              const int material_count,
              const CyEnv *env,
              const CyView *view,
              unsigned char *rgba_out)
{
  const std::lock_guard<std::recursive_mutex> lock(g_lock);
  set_error("");
  if (view == nullptr || rgba_out == nullptr || view->width <= 0 || view->height <= 0) {
    set_error("no view, no output buffer, or a zero-sized image");
    return 0;
  }

  ccl::DeviceInfo device;
  if (!pick_device(device)) {
    set_error(no_device_reason());
    return 0;
  }

  g_pass_failed.store(false);
  const ccl::SessionParams session_params = make_session_params(
      device, view->samples, false);
  ccl::SceneParams scene_params;

  ccl::unique_ptr<ccl::Session> session = ccl::make_unique<ccl::Session>(session_params,
                                                                        scene_params);
  ccl::Scene *scene = session->scene.get();
  watch_progress(session.get());

  apply_view(scene, *view);
  add_passes(scene);
  configure_integrator(scene, session_params.samples);

  CyEnv fallback;
  memset(&fallback, 0, sizeof(fallback));
  fallback.ambient = 0.15f;
  fallback.rig = 1.0f;
  fallback.hdri_strength = 1.0f;
  const CyEnv &e = env != nullptr ? *env : fallback;
  build_scene(scene, meshes, mesh_count, materials, material_count, e, view_forward(*view));

  session->set_output_driver(ccl::make_unique<LiveOutput>(session.get()));

  const ccl::BufferParams buffer_params = make_buffer_params(view->width, view->height);
  g_generation.fetch_add(1);
  g_frame.clear();
  session->reset(session_params, buffer_params);
  session->start();
  session->wait();

  /* The session is a background one, so `wait` returns only when every sample
   * is in and the driver has been handed the finished frame. */
  const std::lock_guard<std::mutex> flock(g_frame.mutex);
  if (g_frame.width != view->width || g_frame.height != view->height ||
      g_frame.color.size() < (size_t)view->width * view->height * 4)
  {
    if (g_error.empty()) {
      set_error("the render finished without producing a frame");
    }
    return 0;
  }
  /* Vertical flip: Cycles' buffer is bottom-up and every image surface the app
   * has is top-down. */
  const int w = view->width;
  const int h = view->height;
  for (int y = 0; y < h; y++) {
    const float *src = g_frame.color.data() + (size_t)(h - 1 - y) * (size_t)w * 4;
    unsigned char *dst = rgba_out + (size_t)y * (size_t)w * 4;
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

  /* A frame came back, so the kernels are compiled and in the archive. Any
   * render proves this, not just cy_preload's. */
  g_kernels_ready.store(true);
  set_status("", -1.0f);
  return 1;
}

int cy_live_open(void)
{
  const std::lock_guard<std::recursive_mutex> lock(g_lock);
  set_error("");
  return open_live() ? 1 : 0;
}

void cy_live_close(void)
{
  const std::lock_guard<std::recursive_mutex> lock(g_lock);
  close_live();
  set_status("", -1.0f);
}

int cy_live_is_open(void)
{
  const std::lock_guard<std::recursive_mutex> lock(g_lock);
  return (g_live.open && g_live.session) ? 1 : 0;
}

int cy_live_scene(const CyMesh *meshes,
                  const int mesh_count,
                  const CyMaterial *materials,
                  const int material_count,
                  const CyEnv *env)
{
  const std::lock_guard<std::recursive_mutex> lock(g_lock);
  set_error("");
  if (!open_live()) {
    return 0;
  }
  if (env == nullptr) {
    set_error("no world");
    return 0;
  }
  ccl::Scene *scene = g_live.session->scene.get();

  /* THE SCENE MUTEX IS THE CONTRACT. Session::run_update_for_next_iteration
   * holds it for the whole of its scene update, so anything editing the scene
   * from outside has to hold it too — this is exactly what
   * BlenderSession::synchronize does, down to calling reset() while still
   * inside it. There is no deadlock in that: reset() waits only for a render
   * that is IN PROGRESS, and a render thread blocked on this mutex is by
   * definition not rendering. */
  {
    const ccl::thread_scoped_lock scene_lock(scene->mutex);
    clear_scene(scene);
    g_live.headlight = Lamp();
    /* The camera is not touched here, but its forward direction aims the
     * headlight, so the rig is rebuilt from whatever the camera currently is.
     * Column 2 of Camera::matrix is that direction. */
    const ccl::Transform tfm = scene->camera->get_matrix();
    const ccl::float3 forward = ccl::make_float3(tfm.x.z, tfm.y.z, tfm.z.z);
    g_live.headlight = build_scene(
        scene, meshes, mesh_count, materials, material_count, *env, forward);
    g_live.has_scene = true;
    if (g_live.has_view) {
      restart();
    }
  }
  return 1;
}

int cy_live_view(const CyView *view)
{
  const std::lock_guard<std::recursive_mutex> lock(g_lock);
  set_error("");
  if (view == nullptr || view->width <= 0 || view->height <= 0) {
    set_error("no view, or a zero-sized image");
    return 0;
  }
  if (!open_live()) {
    return 0;
  }
  ccl::Scene *scene = g_live.session->scene.get();
  {
    const ccl::thread_scoped_lock scene_lock(scene->mutex);
    apply_view(scene, *view);

    /* THE HEADLIGHT FOLLOWS THE CAMERA, so it is the one part of the scene a
     * camera move touches at all. One transform and one tag; no geometry, no
     * shaders, no BVH. */
    aim_headlight(scene, g_live.headlight, view_forward(*view));

    g_live.session_params.samples = view->samples > 0 ? view->samples : 64;
    g_live.target = g_live.session_params.samples;
    scene->integrator->set_aa_samples(g_live.session_params.samples);
    g_live.buffer_params = make_buffer_params(view->width, view->height);
    g_live.has_view = true;
    restart();
  }
  return 1;
}

int cy_live_frame(unsigned char *rgba_out, const int capacity, CyFrame *info)
{
  const std::lock_guard<std::recursive_mutex> lock(g_lock);
  if (rgba_out == nullptr || info == nullptr) {
    set_error("no output buffer");
    return -1;
  }
  memset(info, 0, sizeof(*info));
  if (!g_live.open || !g_live.session) {
    return 0;
  }
  if (g_pass_failed.load()) {
    set_error("the renderer produced no combined pass");
    return -1;
  }

  int w = 0;
  int h = 0;
  int samples = 0;
  bool finished = false;
  {
    const std::lock_guard<std::mutex> flock(g_frame.mutex);
    if (g_frame.width <= 0 || g_frame.height <= 0 || g_frame.serial == g_live.seen ||
        g_frame.generation != g_generation.load())
    {
      /* Nothing newer than what the caller already has. Still report where
       * sampling has got to, so a caller polling for convergence — the badge,
       * or a decision about whether to keep polling at all — does not have to
       * wait for a frame it does not need. */
      info->samples = g_frame.samples;
      info->target = g_live.target;
      info->done = g_frame.finished ? 1 : 0;
      return 0;
    }
    w = g_frame.width;
    h = g_frame.height;
    samples = g_frame.samples;
    finished = g_frame.finished;
    const size_t n = (size_t)w * (size_t)h;
    if (capacity < (int)(n * 4) || g_frame.color.size() < n * 4) {
      /* NOT an error. The size filter in the driver makes this very nearly
       * unreachable, and if it is reached the honest answer is "nothing you
       * can use yet" — the next frame will be the right size. Reporting a
       * failure here would turn an ordinary zoom into a renderer that had
       * stopped. Marked seen so the caller does not spin on it. */
      g_live.seen = g_frame.serial;
      return 0;
    }
    /* Copied out from under the lock so the sRGB conversion below runs with
     * the render thread free to keep producing frames. */
    g_live.work.resize(n * 4);
    memcpy(g_live.work.data(), g_frame.color.data(), n * 4 * sizeof(float));
    g_live.seen = g_frame.serial;
  }

  /* M353 — NOTHING IS FILTERED. THE FRAME IS THE PATH TRACE.
   *
   * WHY IT CAME OUT. The a-trous filter was measured at 51 ms per frame at
   * 480x320, single-threaded, and it ran on EVERY frame handed to the display.
   * That is not a quality cost, it is a FRAME RATE cost, and it landed in the
   * two places a user actually looks:
   *
   *   * during an orbit the worker polls every 14 ms and each frame cost about
   *     51 ms of CPU, so it could never keep up — frames arrived late and in
   *     bursts rather than at the rate they were produced;
   *   * standing still at 1440x1080 the same filter is around 450 ms a frame,
   *     which is fewer than three updates a second, each a large visible jump.
   *
   * Both read as "it only goes in steps", which is what came back from the
   * device. The strength ramp made it worse than a constant cost would have:
   * the filter faded out as samples climbed, so consecutive frames differed in
   * CHARACTER and not merely in noise level — visible even where the change in
   * noise is not.
   *
   * Convergence is the path tracer's alone now, which is the honest reading of
   * "render until the image is perfect": every pixel on screen is light that
   * was actually traced, and it only ever gets better.
   *
   * TURNING IT BACK ON is four things, all still present and still tested:
   * re-add the two passes in add_passes, carry albedo and normal through
   * FrameStore and Live, restore the ping-pong buffer, and call cyshim::denoise
   * here. cycles_denoise.cpp is still compiled and render_test.c still covers
   * its edge preservation and the monotonicity of its strength curve, so none
   * of it has rotted. It should come back as an option with its cost measured
   * on a device, and most likely only for moving frames, where 51 ms of CPU
   * buys more than it costs. */
  const bool denoised = false;

  /* Vertical flip: Cycles' buffer is bottom-up and every image surface the app
   * has is top-down. */
  for (int y = 0; y < h; y++) {
    const float *src = g_live.work.data() + (size_t)(h - 1 - y) * (size_t)w * 4;
    unsigned char *dst = rgba_out + (size_t)y * (size_t)w * 4;
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

  info->width = w;
  info->height = h;
  /* M347 — THE COUNT IT ACTUALLY RENDERED.
   *
   * This used to report the TARGET whenever the frame was finished, on the
   * theory that a finished frame has nothing left to say. What it actually did
   * was put "256 spp" under an image that had ninety — and when a mis-stamped
   * capture latched the finish flag early (see restart()), under one that had
   * a dozen. The one number in the badge that could have said the renderer had
   * stopped early was the number that had been taught not to. */
  info->samples = samples;
  info->target = g_live.target;
  info->done = finished ? 1 : 0;
  info->denoised = denoised ? 1 : 0;
  g_kernels_ready.store(true);
  return 1;
}

int cy_kernels_ready(void)
{
  return g_kernels_ready.load() ? 1 : 0;
}

void cy_status(char *out, const int len)
{
  if (out == nullptr || len <= 0) {
    return;
  }
  const std::lock_guard<std::mutex> lock(g_status_mutex);
  const size_t n = g_status.size() < (size_t)(len - 1) ? g_status.size() : (size_t)(len - 1);
  memcpy(out, g_status.data(), n);
  out[n] = '\0';
}

float cy_progress(void)
{
  const std::lock_guard<std::mutex> lock(g_status_mutex);
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
  memset(&mesh, 0, sizeof(mesh));
  mesh.verts = verts;
  mesh.vert_count = 3;
  mesh.normals = nullptr;
  mesh.tris = tris;
  mesh.tri_count = 1;
  mesh.material = -1;

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

  CyEnv env;
  memset(&env, 0, sizeof(env));
  env.world[0] = env.world[1] = env.world[2] = 0.8f;
  env.ambient = 0.15f;
  env.rig = 1.0f;
  env.hdri_strength = 1.0f;

  std::vector<unsigned char> scratch((size_t)view.width * view.height * 4);
  set_status("Preparing the renderer", 0.0f);

  const int ok = cy_render(&mesh, 1, nullptr, 0, &env, &view, scratch.data());
  if (!ok) {
    set_status("", -1.0f);
  }
  return ok;
}

}  /* extern "C" */
