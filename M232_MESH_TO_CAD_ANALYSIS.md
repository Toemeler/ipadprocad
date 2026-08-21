# M232 — "Mesh to CAD, like Fusion" — Research & Plan

Request: *"Is there any way I could have a mesh to CAD converter integrated. Is there
any open source tool which is extremely good that doesn't just convert vertexes
directly to CAD instead recognizes faces and stuff like this and easily handles also
very complex models. Similar to Fusion mesh to CAD organic or the other stuff."*

This is the research pass. **No code was changed.** The answer to "is there a tool I
can drop in" is *no*, and the rest of this document is the evidence for that plus the
build that actually gets you there.

---

## 0. The short answer

There is **no open-source tool that does what Fusion's Mesh→BRep does**, at any
license, that you could integrate as a dependency. Everything that is good is either

- **research code** — Python + PyTorch + GPU, trained on small CAD parts, or
- **licensed so you cannot ship it** — non-commercial, AGPL, or commercial-only, or
- **a box of parts, not a machine** — excellent primitives (CGAL) with no pipeline
  on top.

The good news is narrower and more useful: **you already own the hardest half.** The
expensive part of mesh→CAD is not the fitting, it is having a B-Rep kernel that can
intersect analytic surfaces, trim faces to wires, sew a shell and heal it into a
valid solid. That is OCCT, it is already vendored at `V7_9_3`, and `occt_capi.cpp`
already drives it. Nobody else's mesh→CAD tool would give you that; it would have to
hand geometry *back* to OCCT anyway.

So the realistic project is not "integrate a converter". It is "write the front half
of a converter against the kernel we already have".

---

## 1. What Fusion actually does, decomposed

The three modes in Fusion's **Convert Mesh** are three different algorithms, and
conflating them is why this looks like one feature.

| Mode | What it really is | Fusion gating |
|---|---|---|
| **Faceted** | 1 triangle → 1 planar face, sewn into a shell. Coplanar merge within a tolerance. | Free tier |
| **Prismatic** | Segment → fit analytic primitives → regularize → intersect → trim → sew | Paid |
| **Organic** | Quad-remesh → T-Spline (SubD) → limit surface → NURBS patches | **Product Design Extension** only |

Two things follow immediately.

**Faceted is the thing you said you don't want.** "Doesn't just convert vertexes
directly to CAD" — that is Faceted, exactly. It is also ~60 lines against OCCT
(`BRepBuilderAPI_MakePolygon` → `MakeFace` → `Sewing` → `MakeSolid` → `ShapeFix_Shape`,
then `occt_unify` which you already have and which *is* the coplanar merge). Worth
having as plumbing, worthless as an answer.

**Organic is T-Splines**, which Autodesk bought in 2011 and keeps behind its most
expensive extension. There is no open-source T-Splines. There is, however, a
legitimate substitute — see §4.3.

**Prismatic is the 2001 literature.** Benkő, Martin & Várady, *"Algorithms for reverse
engineering boundary representation models"* (CAD 33(11), 2001) and Benkő, Kós,
Várady, Andor & Martin, *"Constrained fitting in reverse engineering"* (CAGD 19, 2002)
describe this pipeline in full: segment the data, fit surfaces with **constraints
between them**, build topology, then add blends. Fusion Prismatic is a good
engineering implementation of a 25-year-old, fully published method. This is
buildable. It is not research.

---

## 2. The survey — everything I checked, and why it's out

### 2.1 Kernels and toolkits

| Project | What it gives | License | Verdict |
|---|---|---|---|
| **OCCT 7.9.3** (vendored) | Sewing, healing, surface intersection, trimming, solid making, STEP | LGPL-2.1 + OCCT exception | **The sink for everything.** Forward meshing only — B-Rep→mesh. OCCT's own forum confirms it has no mesh→B-Rep with surface reconstruction beyond per-triangle. |
| **CGAL** | `Shape_detection` (Efficient RANSAC + Region Growing, 5 primitives: plane/sphere/cylinder/cone/torus), `Shape_regularization`, `Surface_mesh_approximation` (VSA), `Polygonal_surface_reconstruction` (PolyFit) | **GPLv3** for these packages | **Best classical building blocks that exist.** See §3 — the GPL is free for you. |
| **MeshLib** | Broad mesh processing | Commercial license required | Out. |
| **Gmsh** `classifySurfaces` | Splits an STL into patches by feature angle, then *reparametrizes* them | GPL | Wrong output. It builds **discrete** parametrizations for meshing, not analytic B-Rep faces. Right idea, wrong destination. |
| **openNURBS** | 3dm I/O; `ON_SubD` | Free SDK | **Path closed.** `ON_SubD::GetSurfaceBrep()` — the SubD→NURBS call that would have been the Organic answer — is *not in the free toolkit*. It's Rhino-only. |
| **PolyFit / Easy3D** | Hypothesis-and-selection planar reconstruction | GPLv3 | Piecewise-**planar** only (it's a buildings method). No cylinders. Wrong shape class for mechanical parts. Also now inside CGAL. |

### 2.2 Research code (the state of the art)

Sourced from [awesome-brep-reconstruction](https://github.com/Bigger-and-Stronger/awesome-brep-reconstruction), which is the live index for this field.

| Project | Year | Result | Why it can't ship |
|---|---|---|---|
| **Point2CAD** | CVPR 2024 | SOTA on ABC. Fits surfaces, then *extends and intersects them analytically so topology emerges* — the right idea | **CC-BY-NC 4.0 — non-commercial only.** Also needs pre-segmentation from ParSeNet/HPNet first; it only does steps 3–5. Python + PyTorch. |
| **DeFillet** | SIGGRAPH 2025 | Solves the single hardest sub-problem: detecting and removing fillet regions (rolling-ball centres via Voronoi, sharp-feature reconstruction as a QP) | **AGPL-3.0** + "contact us for commercial". Linking it would make the whole iPad app AGPL. **Read the paper; do not link the code.** |
| ComplexGen, SED-Net, HPNet, ParSeNet, SPFN, Split-and-Fit, CAD-Recode, HoLa, CADDreamer, SfmCAD | 2019–2025 | Various | PyTorch + GPU, trained on ABC/DeepCAD — i.e. **small mechanical parts**, typically thousands of points. This is the opposite of "easily handles also very complex models". None run on an iPad. |

The pattern is consistent: **the neural methods are trained on small parts and get
worse, not better, as complexity rises.** They are not the answer to your actual
requirement.

### 2.3 The one genuinely useful open-source pipeline

**[MeshToFeatures](https://github.com/MasoudMiM/MeshToFeatures)** (LGPL-2.1) — a FreeCAD
workbench that reverse-engineers STL meshes of prismatic parts into **editable
PartDesign bodies**. Its pipeline is exactly the one worth copying:

1. **Segmentation & recognition** — region growing + geometric fitting (planes, cylinders)
2. **Snapping** — *"unifying near-parallel directions, merging coaxial cylinders,
   equalizing radii, and rounding to grid-friendly numbers"*
3. **Feature detection** — holes, counterbores, pockets, steps, pads, patterns
4. **Rebuild** — native PartDesign body with sketches, pads, pockets, holes

It recognises counterbored/countersunk holes, conical pockets, tapered holes,
cross-axis holes, bosses, fillets and chamfers. Stated limits: prismatic only,
"dimensional fidelity is bounded by the mesh", snapping tolerance ~0.1% of part
diagonal, and **"large meshes (millions of faces) unoptimized"**.

This is Python and it is FreeCAD-bound, so it is **your reference implementation, not
your dependency**. But it is proof the prismatic pipeline is tractable by one person,
and step 2 is the part nobody talks about and everybody needs — see §5.

### 2.4 The organic front half (permissive!)

| Project | Role | License |
|---|---|---|
| **Instant Meshes** | Field-aligned quad remesh — the "retopology" step | **BSD 3-Clause** |
| **QuadriFlow** | Same job, scalable, robust | **MIT** |
| **OpenSubdiv** (Pixar) | Catmull–Clark limit surface evaluation | **modified Apache 2.0, patents granted for public use** |

The key fact: OpenSubdiv's `Far::PatchTable` returns **regular faces as bicubic
B-spline patches**. A bicubic B-spline patch *is* a `Geom_BSplineSurface`. That is a
direct, lossless hand-off into OCCT. Extraordinary vertices come out as Gregory
patches and need approximating, which is the same compromise T-Splines makes.

So: **quad-remesh (BSD/MIT) → SubD limit surface (Apache) → NURBS patches → OCCT sew**
is a fully permissive, entirely real path to an Organic mode. Nobody has assembled it,
but every piece is shipping-grade and license-clean.

---

## 3. The licensing finding that changes the calculus

`backend/qcad-core/VENDOR.md` — **GPLv3**.
`backend/slvs/VENDOR.md` — libslvs, from SolveSpace — **GPLv3**.
`backend/occt/VENDOR.md` — LGPL-2.1 with the OCCT static-linking exception.

The app is therefore **already a GPLv3 work**. Which means:

> **CGAL's GPL costs you nothing you have not already paid.**

The usual reason people reject CGAL for a commercial product does not apply here. You
can use `Shape_detection`, `Shape_regularization` and `Surface_mesh_approximation`
without a GeometryFactory commercial licence, because your combined work is GPLv3
already and CGAL's GPLv3 is compatible with it.

Two practical notes:

- **CGAL builds for iOS ARM64.** It is header-only for these packages, and the
  GMP/MPFR dependency — the classic cross-compile blocker — is avoidable: CGAL
  supports **Boost.Multiprecision** instead. With `Exact_predicates_inexact_constructions_kernel`
  you need Boost headers and nothing else native.
- **GPL and the App Store are in tension** (the VLC precedent: GPL §6/§10 vs. App
  Store terms). That is a pre-existing condition of shipping QCAD + SolveSpace, not
  something CGAL introduces, and it's your call — flagging it because it belongs in
  the same paragraph as the licence audit, not because it changes this decision.

---

## 4. What I recommend building

Four stages. Each is independently shippable and each one is worth something on its
own. Naming follows the shim conventions in `occt_capi.h` (flat C ABI, opaque handles,
`int` 1/0, `occt_last_error()`).

### Stage A — plumbing: get a mesh into the kernel at all

New shim entry points:

```c
/* Load a triangle soup. STL binary/ASCII, OBJ, PLY. */
occt_mesh_data *occt_mesh_load(const char *path);

/* Faceted conversion: 1 triangle -> 1 face, sew, heal, solidify. */
occt_shape *occt_brep_from_mesh_faceted(const occt_mesh_data *m, double tol);
```

`BRepBuilderAPI_Sewing` + `ShapeFix_Shape` + `BRepBuilderAPI_MakeSolid`, then
`occt_unify` (which is `ShapeUpgrade_UnifySameDomain` — you already have it) to merge
coplanar triangles into real planar faces.

**This is the thing you said you don't want, and it should still exist**, because it
is how STL import, mesh display and every later stage get their data in. Ship it, mark
it clearly as the dumb mode, and do not pretend it is the feature.

Cost: ~1 day.

### Stage B — Prismatic. The actual prize.

This is the Benkő/Martin/Várady pipeline, against your kernel.

1. **Pre-pass** — weld vertices, orient, drop degenerate triangles, estimate per-vertex
   normals and principal curvatures.
2. **Sharp-edge detection** — dihedral angle + curvature threshold. This is what Fusion
   means by "needs sharp edges so it can determine the surface boundary".
3. **Segmentation** — region growing over the triangle adjacency graph, seeded by
   curvature, bounded by sharp edges. Note the shim's existing `occt_mesh_*` family
   (`occt_mesh_triangle_faces`, `occt_mesh_normals`, `occt_mesh_face_ids`) tessellates
   an existing `TopoDS_Shape` for display and picking — it is the *forward* direction
   and gives you nothing for an imported STL. You need a real half-edge structure over
   the loaded mesh. That is the one new data structure this stage requires. Either
   CGAL's `Region_growing` on a `Surface_mesh`, or ~400 lines of your own.
4. **Fitting** — for each region, least-squares fit plane / cylinder / cone / sphere /
   torus, take the lowest residual that passes tolerance. Gauss–Newton; Eigen is enough,
   Ceres (BSD) if you want robustness.
5. **Regularization — the step that makes it feel like Fusion.** Snap near-parallel
   axes to parallel, near-perpendicular to perpendicular, merge coaxial cylinders,
   equalize near-equal radii, align to global axes, round dimensions to sane numbers.
   Without this you get 47 cylinders of radius 5.0013, 4.9987, 5.0004… and the result
   is unusable. CGAL's `Shape_regularization` does the geometric half; the
   round-to-grid half is yours (and `params.dart` already gives you the notion of a
   driving dimension to round *to*).
6. **Topology** — for each adjacent region pair, intersect the *analytic* surfaces
   (`GeomAPI_IntSS`) to get the **exact** edge curve — a real line/circle/ellipse, not
   a polyline through mesh vertices. This is the single biggest quality difference
   between a real converter and a fake one.
7. **Trim & sew** — build wires from the intersection curves, `BRepBuilderAPI_MakeFace`
   with them, `BRepBuilderAPI_Sewing`, `ShapeFix_Shell`, `BRepBuilderAPI_MakeSolid`.
8. **Fallback** — any region that fits nothing analytically goes to
   `GeomAPI_PointsToBSplineSurface` or `BRepOffsetAPI_MakeFilling`. Never fail the whole
   part because of one weird patch.

Cost: weeks, not days. This is the milestone.

### Stage C — Blend/fillet recovery, and the thing only *your* app can do

Fillets are what break naive converters: a filleted edge is a strip of triangles that
is neither of its neighbours, and if you fit it as a surface you get an unfilletable,
uneditable blob.

The method (DeFillet's paper, not its AGPL code): a rolling-ball blend has the property
that its osculating sphere centres lie on a curve. Detect constant-radius strips, delete
them, extend the two neighbour surfaces, re-intersect for the sharp edge, and record
"there was an r=2 fillet here".

**Then re-apply it as a feature.** You have `occt_fillet_edges_ex`. You have a feature
tree in `part_model.dart` whose recompute fold (`recomputeAllFeatures`) already
replays history. So the output of the converter should not be a dead solid — it should
be **Extrusion → Hole → Fillet(r=2)** in the feature list, editable, with the radius
scrubbable in `scrub.dart`.

That is a thing Fusion does not do well and that fits this codebase's architecture
exactly. It is the reason to build this yourself rather than wish for a library.

### Stage D — Organic

Instant Meshes (BSD) or QuadriFlow (MIT) → quad mesh → OpenSubdiv (Apache) →
`Far::PatchTable` → regular patches become `Geom_BSplineSurface` directly, Gregory
patches get approximated → sew. Per §2.4.

Cost: weeks. Lowest priority — a 2D-CAD-derived iPad app's users want prismatic parts
far more than they want organic surfaces.

---

## 5. Why this is worth doing here specifically

Three things make this a better fit for this app than for a generic CAD program:

1. **The kernel is already in-process.** No IPC, no file round-trip, no server. The
   converter writes straight into a `TopoDS_Shape` that the rest of the app already
   knows how to fillet, boolean and export to STEP.
2. **The feature tree can hold the recovered history.** §Stage C. A converter that
   outputs *features* rather than a solid is strictly better than Fusion Prismatic,
   and it costs nothing extra here because the fold already exists.
3. **`frontend/packages/reality_view` already links ARKit.** iPad Pro has LiDAR. The
   end state is *scan the part on the table → prismatic convert → edit the recovered
   fillet radius → export STEP*, entirely on device. That is a genuinely differentiated
   feature and nothing in the survey above can do it.

---

## 6. Honest costs and risks

- **Stage A**: ~1 day. **Stage B**: the real milestone, weeks. **Stage C**: weeks.
  **Stage D**: weeks. There is no shortcut and no library that collapses this.
- **Performance on iPad.** MeshToFeatures explicitly does not handle millions of faces.
  Segmentation and fitting are O(n) to O(n log n) and fine; the risk is memory on a
  large scan. Decimate before segmenting.
- **"Very complex models" is where all of these degrade.** Be honest in the UI: report
  how many regions fitted analytically vs. fell back to B-spline, and let the user see
  what the converter was unsure about. The failure mode to avoid is a silently wrong
  solid.
- **Tolerance is the whole game.** One global tolerance will not work across a 200 mm
  part with 0.5 mm fillets. Scale it to the part's bounding-box diagonal, as
  MeshToFeatures does (~0.1%).

---

## 7. The one decision that gates the build

**Use CGAL, or hand-roll the segmentation and fitting?**

- **CGAL** — best-in-class Efficient RANSAC (Schnabel et al. 2007) and region growing
  for all five primitive types, plus `Shape_regularization`. GPLv3, which per §3 is
  free for you. Adds Boost + CGAL headers to the iOS build.
- **Hand-rolled** — a half-edge structure plus ~400 lines of region growing, plus
  five least-squares fits. No new dependency, no new build risk, full control of
  tolerance behaviour, and it keeps the door open if the GPL situation ever needs to
  change.

**Recommendation: hand-roll Stage B's segmentation, keep CGAL in reserve for
regularization.** Not for licence reasons — because a half-edge build plus five
textbook least-squares fits is a known quantity, whereas adding CGAL + Boost to a
working iOS toolchain is a build-system risk taken at exactly the moment you can least
afford one. Revisit at Stage C, where `Shape_regularization` and VSA start earning
their keep and the fits are no longer the interesting part.

---

## 8. Sources

- [awesome-brep-reconstruction](https://github.com/Bigger-and-Stronger/awesome-brep-reconstruction) — the live index for this field
- [Point2CAD](https://github.com/prs-eth/point2cad) (CVPR 2024) — CC-BY-NC 4.0
- [DeFillet](https://github.com/xiaowuga/DeFillet) (SIGGRAPH 2025) — AGPL-3.0
- [MeshToFeatures](https://github.com/MasoudMiM/MeshToFeatures) — LGPL-2.1, the closest working prismatic pipeline
- [CGAL Shape Detection](https://doc.cgal.org/latest/Shape_detection/index.html) · [Polygonal Surface Reconstruction](https://doc.cgal.org/latest/Polygonal_surface_reconstruction/index.html)
- [Instant Meshes](https://github.com/wjakob/instant-meshes) (BSD-3) · [QuadriFlow](https://github.com/hjwdzh/QuadriFlow) (MIT)
- [OpenSubdiv Far overview](https://graphics.pixar.com/opensubdiv/docs/far_overview.html) · [licence](https://graphics.pixar.com/opensubdiv/license.html)
- [PolyFit](https://github.com/LiangliangNan/PolyFit) (GPLv3)
- [FreeCAD Reverse Engineering Workbench](https://wiki.freecadweb.org/Reverse_Engineering_Workbench)
- [Gmsh STL reparametrization preprint](https://gmsh.info/doc/preprints/gmsh_stl_preprint.pdf)
- Benkő, Martin, Várady, *Algorithms for reverse engineering boundary representation models*, CAD 33(11):839–851, 2001
- Benkő, Kós, Várady, Andor, Martin, *Constrained fitting in reverse engineering*, CAGD 19:173–205, 2002
- Schnabel, Wahl, Klein, *Efficient RANSAC for Point-Cloud Shape Detection*, CGF 26(2):214–226, 2007
