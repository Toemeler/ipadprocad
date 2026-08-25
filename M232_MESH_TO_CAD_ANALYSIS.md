# M232 — "Mesh to CAD, like Fusion" — Research & Plan

Request: *"Is there any way I could have a mesh to CAD converter integrated. Is there
any open source tool which is extremely good that doesn't just convert vertexes
directly to CAD instead recognizes faces and stuff like this and easily handles also
very complex models. Similar to Fusion mesh to CAD organic or the other stuff."*

This is the research that decided the build. The answer to "is there a tool I can
drop in" is **no** — the evidence is below — so it was written instead, against the
kernel that was already here.

**What shipped with this document** (see the commits that follow it):

| | |
|---|---|
| `frontend/lib/mesh_io.dart` | STL (binary + ASCII), OBJ, 3MF readers. No new package: the 3MF container is unzipped with `dart:io`'s raw inflate, the same one `zip_writer.dart` writes with |
| `backend/occt/shim/mesh_recon.{h,cpp}` | the reconstruction pipeline — weld, orient, segment, fit plane/cylinder/cone/sphere/torus, merge, refine boundaries, regularise, build faces on exact intersection curves, sew |
| `occt_brep_from_mesh` (shim v21) | the flat C ABI over it, with a report the UI can explain a failure from |
| `PartKernel.meshToBrep` | the seam the app talks to, so `AppState` never touches the FFI directly and the test fakes can decline it in one line |
| `AppState.importMeshIntoPart` | Open accepts `.stl`, `.obj`, `.3mf`; the body lands in the feature tree and is filletable, booleanable and STEP-exportable like any other |
| 22 ARB keys, German + English | every sentence the feature can say. `mesh_io.dart` throws a `MeshFailure` code, never prose — a reader has no business holding UI text (M234) |
| `backend/occt/tests/mesh_recon_test.cpp` | 132 assertions: build a solid with OCCT, tessellate it, throw the B-Rep away, reconstruct from triangles alone, compare topology and volume. Run by CI |
| `frontend/test/m232_mesh_import_test.dart` | 28 tests over the readers, the limits, the Open decision and the import wiring |

### What it actually does

A drilled and bossed plate of 4 610 triangles comes back as **exactly its 28
original faces** — 10 planes and 18 cylinders, no faceted remainder — closed,
valid, volume within 0.0002%, in 70 ms. A block with 3 mm fillets recovers 6
planes and 4 cylinders of radius exactly 3.0000 on exactly the right axes.

Measured on synthetic meshes, the reconstruction is near-linear and holds its
accuracy at every size:

| triangles | time | per triangle | result |
|---|---|---|---|
| 51 120 | 97 ms | 1.9 µs | 2 planes + 1 cylinder, closed |
| 253 400 | 497 ms | 2.0 µs | 2 planes + 1 cylinder, closed |
| 882 200 | 2.5 s | 2.9 µs | 2 planes + 1 cylinder, closed |
| 2 243 200 | 7.5 s | 3.3 µs | 2 planes + 1 cylinder, closed |

### The two limits, and why they are where they are

Both are in `mesh_io.dart`, and both guard against a **crash**, not a wait.

- **`kMaxMeshFileBytes` = 256 MB.** Reading is `readAsBytesSync`, so a gigabyte
  file is a gigabyte of iPad memory before a triangle has been looked at, and
  the app is killed rather than told. Checked from `lengthSync()` *before* the
  read — the only moment at which it can be refused instead of crashed on.
- **`kMaxMeshTriangles` = 2 000 000.** The reconstruction runs on the **UI
  thread**, because the kernel is single-threaded by contract. Two million is
  about seven seconds of frozen app on a desktop and perhaps fifteen on a
  device: far past anything anyone prints (a typical MakerWorld model is fifty
  to five hundred thousand), near enough that one bad download cannot wedge the
  app for minutes. A notice goes up before the kernel takes the thread, so the
  freeze has an explanation on screen.

The triangle limit is enforced **inside** each reader, not once on the finished
mesh. A 3MF names its geometry by reference — an object can be a list of
components pointing at other objects — so four levels of sixty turn one cube
into thirteen million triangles from a few kilobytes of XML. Checking only at
the end would mean allocating all of it first, which is the crash the limit
exists to prevent.

### What a real downloaded file then broke, and what fixed it

Every mesh the suite above was built from came out of OCCT's own tessellator:
closed, manifold, consistently wound, and in **double** precision. A downloaded
STL is none of those by default, and the difference that mattered most was the
last one — an STL stores `float32`, so nothing is ever exactly on the surface it
came from. The first real file killed the app.

The tool that found it is worth keeping in mind before the findings: build the
thing that downloads a model. Tessellate an OCCT solid **coarsely**, round every
coordinate to `float32`, dedup on exact float bits the way `mesh_io.dart` does,
reconstruct — one `fork` per case, so a segfault names its seed instead of
ending the run. Seed 103 died on 412 triangles. Fifteen hundred seeds then
produced three findings, two of them fatal.

**1. `ShapeFix_Face::FixPeriodicDegenerated` dereferences a null context.** It
fires on a conical face whose single wire wraps the full 2π — a countersink, a
chamfer, a tapered boss. Every other `Context()` use in that file is guarded by
`IsNull()`; its last two lines are not, and `ShapeFix_Face`, unlike
`ShapeFix_Shape` and `ShapeFix_Shell`, never makes a context of its own. Null
dereference, SIGSEGV, no exception to catch: the app simply gone, with no crash
report and a log stopping mid-import. Present in 7.6 and in the 7.9.3 we pin.
The fix is one line on our side — hand the tool a `ShapeBuild_ReShape`, which is
what `ShapeFix_Shape` does when it drives the same tool.

**2. `GeomAPI_IntSS` does not always terminate, and cannot be interrupted.** On
two parallel cylinders whose axes were a millimetre apart it had not returned
after ninety seconds on a 444-triangle mesh. On an iPad that is not a slow
conversion; it is a frozen app the watchdog kills, and from the outside it looks
exactly like the crash above. The only safe bound is on what goes in, so
`IntersectablePair` now admits a plane against anything (hole rims, cap edges,
box edges — closed form in OCCT) and two coaxial quadrics of different kinds
(the rim of a countersunk hole). Everything else meets in a degree-four curve
OCCT would approximate anyway, so the polyline fallback loses nothing that was
ever exact — every exact-edge count in the suite is unchanged.

**3. A countersink came back as a sphere.** Not a crash, but the thing the
feature exists to avoid. `FitPatch` took the simplest kind that fitted, which is
right on a whole face and wrong on a piece of one — and region growing works on
pieces. A plane fits three columns of a tessellated cylinder to well inside
tolerance; so does a sphere the size of a house. It now takes the kind whose
**normals** agree with the mesh, ties going to the simpler kind: on that strip a
plane agrees to 0.94 and the cylinder to 0.999, so there is nothing marginal
about the decision. Alongside it, `SplitAtCrease` cuts a patch at a crease too
shallow for the global sharp-edge threshold, read from the patch's own dihedral
distribution rather than any absolute angle, so it calibrates itself to the
tessellation.

Measured over 600 randomly generated models, before and after:

| | before | after |
|---|---|---|
| total faces for the same 600 models | 12 342 | **9 141** (−25.9%) |
| models that closed into a solid | 384 | **405** |
| models that stopped closing | — | **0** |

And on a plate with four countersunk holes, which is close to the file that
started this: four spheres and a volume 0.18% short became four **cones** and a
volume exact to five figures.

### And then the file turned out not to be prismatic at all

The model this milestone was built for is a curved shell — organic, not
prismatic, 1138 triangles across 54 mm. Surface fitting has nothing to
recognise on a shape that is analytic nowhere. It came back as **179 patches
for 1138 triangles** — one face per six — as an open shell rather than a solid,
and with faces that had lost their trimming: an untrimmed plane is INFINITE,
and in the viewport that is a shard across the model with edges running off
screen and a bounding box that grew every time the viewer re-tessellated. An
ellipsoid reproduced it exactly: faces reaching **285% of the model's own
diagonal** outside it.

Three changes, in the order they matter:

**A face may not escape its own triangles.** The wires come from mesh vertices,
so a well-built face is within a facet's sagitta of its patch; one that is not
has lost its trimming and is refused, and its patch goes faceted. Measured with
the cheap pole-based box first — it never understates, so on a model that is
behaving it is the only box computed — and only the expensive exact one when
that fails, because a B-spline's control polygon stands outside the curve and
read as 1.7 mm of overshoot on a plate's end cap that was exactly right.

**A fitted shell that will not close is dropped for the faceted build.** One
face per triangle recognises nothing, but on a watertight mesh it cannot fail,
and a heavy solid the user can cut and fillet beats a light shell they cannot.
Decided by trying it rather than predicting it: if the faceted build closes
where the fitted one did not, it wins.

Closing is not the only reason to prefer it, and assuming it was left the shards
on screen for one more round. A downloaded mesh is often NOT watertight, and
then nothing closes — so the question becomes which OPEN shell is worth having.
A fitted one that read the model is: it is lighter and its faces are real
surfaces. One that SHATTERED is not, and shattering is plain in the numbers —
this file came back as 179 patches for 1138 triangles, one face per six, which
is not a reading of the shape but a failure to read it. Below ten triangles a
patch the faceted build wins whether or not either closes; the ratio is ignored
under 200 triangles, where it means nothing (a cube with a face missing is five
patches for ten triangles and exactly right).

**The faceted build is now sewn by construction.** It used to make each
triangle its own face and hand the pile to `BRepBuilderAPI_Sewing`, which asks
OCCT to rediscover by geometric search over every face the adjacency this code
computes exactly in `BuildAdjacency` — about a **millisecond per triangle**, 43
seconds for 40 000 triangles, which on an iPad is the app gone. Sharing one
vertex per welded mesh vertex and one edge per mesh edge makes the shell sewn
already, needs no healing after (the edges are identical, not merely close),
and costs 90–140 µs per triangle instead. One trap on the way: `MakeFace` picks
a plane by least squares and its normal is not bound to the wire's winding, so
half the faces came out facing inward — sewing used to hide that, and a shell
built directly has nothing to hide it. The triangle already knows which way it
faces.

That is still a hundred times the fitted path, so the automatic fallback stops
at **30 000 triangles** (`kMaxAutoFacetedTriangles`) — of the order of ten
seconds on a device, with a notice on screen. Past it the fitted result is kept
however poor: a model that is visibly wrong beats an app that is visibly dead,
and its faces are at least bounded now.

**The honest limit this leaves.** A large organic download — and MakerWorld is
full of 100 k-triangle organic models — still gets the fitted result, which on
such a model is not a good answer. Recovering real surfaces there is Stage D
below, and it is not built.

### The decision is per PATCH, not per model

Then the next report came back: *"radiuses are not recognized. Circles are not
recognized."* And that was right, because the fallback above is all-or-nothing
and a real model is not. The file is a curved shell **with holes drilled
through it**. The shell fits nothing; the holes are exactly what they look
like. Throwing away the whole fitted result because the shell shattered threw
away four perfectly recognised cylinders with it.

So a patch now keeps its surface only if the surface is EVIDENCE, and it is
asked of each patch on its own, on four counts. Three of them are cheap and
obvious in hindsight:

- **Residual.** A tessellation puts its vertices ON the surface they came from,
  so a real hole fits its cylinder with a residual of nothing at all, at any
  mesh density. A surface that merely passes nearby squeaks inside tolerance
  and no further. Measured on a curved shell with four drilled holes at a
  tolerance of 0.20 mm: the four real cylinders at 0.000, and the twenty
  "spheres" the fitter invented on the shell at 0.05 to 0.16. Nothing in
  between.
- **Coverage.** Twenty degrees of a cylinder is an arc a thousand radii pass
  through within tolerance. A radius is only knowable from a patch that goes
  far enough round it — an absolute geometric fact, so an absolute threshold.
- **Agreement, against what the tessellation can deliver.** A twelve-sided
  cylinder has facet normals fifteen degrees off the surface at the corners;
  demanding better would reject every low-poly download there is. The bar is
  the patch's own facet step, not a fixed angle. (And *not* its median step —
  half the internal edges of a quad-meshed surface are the quad diagonals, at
  exactly zero, so a median reads zero on every cylinder. The same trap as the
  crease detector, found twice.)

The fourth is the one that took longest and is the most useful: **where the
patch came from.** On a squashed sphere a strip fits a cylinder to better than
a fiftieth of tolerance — the residual cannot separate that from a real hole.
But a feature of the DESIGN arrives as a whole smooth patch bounded by its own
sharp rim, and never needed splitting; a strip is one of many pieces a smooth
region was broken into. `Patch::origin` already recorded it.

The result, on that shell with four holes of radius 2, 3, 4 and 5:

| | before | after |
|---|---|---|
| cylinders recognised | 0 | **4**, at 2.0000 3.0000 4.0000 5.0000 |
| spheres invented on the shell | 20 | **0** |
| the shell itself | fitted, shattered | 45 faceted patches |

**Sharing the seam, and the thing that kept undoing it.** A fitted face and the
triangles beside it have to meet along the *same* edge or the shell will not
sew — the fitted side had a smooth approximation of the chain, the triangles
had the chords between the same vertices, and on a coarse mesh that gap is
wider than any sewing tolerance. Both sides now take the very same
`TopoDS_Edge` objects from one pool. What made that hard to land is that
`ShapeFix_Face::Perform` **heals a face by making a new one**, and the new one
has new edges: 719 of 3379 edges belonged to a single face after Perform, and
29 of 3030 without it. `ShapeFix_Edge::FixAddPCurve` adds the pcurve to the
edge that is already there.

**What is still open, and what has been ruled out.** A hybrid shell — fitted
faces beside triangles — comes out with 29 of its 3030 edges belonging to one
face only, and so is not a solid.

Most of that gap is already closed and it is worth recording how, because the
cause was not where it looked. Both sides of a seam now take the SAME
`TopoDS_Edge` objects from one pool, and what kept undoing it was
`ShapeFix_Face::Perform`: it heals a face by **making a new one**, and the new
one has new edges. 719 of 3379 edges belonged to a single face after Perform,
and 29 of 3030 without it. `ShapeFix_Edge::FixAddPCurve` adds the pcurve to the
edge that is already there.

The remaining 29 are NOT yet diagnosed, and one plausible theory has been tried
and disproved, which is worth writing down so it is not tried again:

> *Theory: a hole through a faceted region is a closed tube, a closed tube has
> no open boundary, so it takes the parametric path and its rims come out as
> exact circles against the triangles' rim polygon.*

Measured: **false.** Those holes never take the parametric path. Each rim
borders several faceted patches, so it arrives as several chains rather than
one closed chain, and the ordinary wire path builds it from real mesh edges.
Splitting such tubes in half was implemented anyway to test the theory — it
fires, produces eight half-cylinders instead of four cylinders, and the shell
*still* does not close. Reverted.

What is known: no edge is used more than twice (so nothing is duplicated); the
open ones are owned by single-triangle faces and by the hole cylinders,
clustered around the holes; sewing takes 29 to 26 and a five-times looser
sewing tolerance changes nothing.

Where the shell does not close the fitted result is kept anyway — recognition
is what was asked for — unless nothing at all was recognised, in which case the
faceted build takes over and closes.

### RANSAC, and why greedy growing could never have got there

The last recognition failure left was the one that mattered most, because it
hits ORDINARY prismatic parts rather than organic ones. A cylinder running into
a cone — a tapered post, a nozzle, a chamfered boss — was recovered perfectly at
some tapers and came apart at others:

| taper | patches, region growing |
|---|---|
| 5.7° | 7 |
| 9.1° | **24** |
| 14.9° | **26** |
| 21.8° | 3 |
| 26.6° and above | 3 |

Nothing about 9° is harder than 22°. The failure is not geometric, it is
procedural: **greedy region growing commits to whatever its first seed
suggested.** The first seed off a tessellated barrel is a PLANE that fits three
columns to well inside tolerance — and once the running fit is a plane, it
stops accepting at the fourth column, and the barrel becomes a fan of planar
strips. Every threshold tried moved which tapers failed, not whether they did.

The classical answer is not a better threshold, it is not committing:
**Efficient RANSAC** (Schnabel, Wahl & Klein, 2007), which is what CGAL's
`Shape_detection` implements and what the commercial converters use. Candidates
are proposed from random seeds and each is then scored against the WHOLE patch
— how many triangles does this surface actually explain? The plane explains
three columns. The cylinder explains the barrel. The cylinder wins on evidence
instead of on being asked first.

Implemented directly against the existing fitter (`SplitByRansac`): grow a
small neighbourhood from a random seed, fit it, flood-fill its inliers across
the patch — connected, so a cylinder cannot claim the identical hole on the far
side of the part — keep the best of 48 proposals, take its triangles, repeat.
Deterministic, because the generator is seeded from the patch: a converter
whose output depends on the weather cannot be tested.

| taper | before | after |
|---|---|---|
| 5.7° | 7 patches | **3**, closed, rms 0.0000 |
| 9.1° | 24 patches, open | **3**, closed, rms 0.0000 |
| 14.9° | 26 patches, open | **3**, closed, rms 0.0000 |
| 21.8° | 3 | 3 |
| 63.4° | 3 | 3 |

Every taper from 6° to 63°: disc, barrel, cone. It costs nothing on models that
already fitted — it only runs on a patch that fitted nothing — and 2.24 M
triangles still convert in 4.1 s.

### Fillets, and the four ways a part loses them

The screenshots that came back next showed a rounded plate whose corners were
flat bands, whose holes were prisms with a wedge missing, and whose top face
was cracked. To have anything to measure, the part was rebuilt synthetically —
60×40×6 plate, r=5 corner fillets, a raised boss, five holes — and swept
through 216 tessellations: six deflections × six angular deflections × six
variants (plain, boss-base fillet, r=12 corners, thin plate, square corners,
countersunk holes), each one converted to a **float32 triangle soup** the way
an STL stores it. A row counts as bad if it does not close, leaves triangles,
fails a face, or moves the volume by more than half a percent.

**87 of 216 were bad. Four separate causes, each found by measurement, each
fixed; 27 remain.**

**1. RANSAC could not see a feature smaller than its own sample.** Candidates
were fitted to a fixed forty-triangle neighbourhood grown from the seed. On a
part whose corner fillets are twelve facets each, every one of the 48 trials on
the side band drew a sample spanning a fillet *and* the wall it is tangent to;
every fit failed; RANSAC returned **0 surfaces from 56 triangles** and the
fillets went to triangles. That is what "the radiuses are not radiuses" is.
Classical RANSAC samples *minimally* — three points for a plane — precisely so
a sample cannot straddle a boundary, but a minimal sample off a coarse mesh
also fits a sphere the size of a house. So the seed is now a **ladder**,
{4, 6, 10, 18, 30, 48}, twelve trials per rung: small seeds find small features,
large seeds are stable on large ones, and support decides. The side band went
from 0 surfaces to 4, and the plate from *31 planes, 6 cylinders and 8 faceted
patches* to **exactly its 17 faces — 7 planes and 10 cylinders, radii 5.0000,
5.0000, 5.0000, 5.0000, 2.2000 ×4, 4.5000, 9.0000, closed, volume 0.00% off.**

**2. Nothing anywhere asked whether a surface passes through the mesh's FACES.**
Every test — residual, normal agreement, sweep — is measured at vertices, and a
surface with enough parameters threads every vertex of a patch and then bulges
out through the middle of it. Measured: a 12 mm corner fillet plus two
triangles of its wall, fitted by a torus of major radius 25 mm about the part's
own axis, residual **0.00000 at every vertex** — and **11.2 mm** off at the
facet centroids, where the real fillets of the same model sit at 0.051 mm.
Trimmed, that face added **306%** to the model's volume. A facet is a chord of
the surface it came off, so the stand-off at its interior is the chord height —
quadratic in facet size, and two orders of magnitude below it. Sampling the
centroid and the three edge midpoints against a bar of a quarter of the facet
separates the two every time, and the test now runs in all three places a
surface is chosen: the RANSAC inlier test, the merge, and identifiability.

**3. A merge only had to stay within tolerance.** `MergeRegions` exists to
reunite one surface the splitter cut in two — and there the union fits exactly,
because both halves did. Joining two *different* surfaces fits only loosely,
and loosely is still inside tolerance: an r=5 fillet (32 triangles, cylinder,
residual zero) merged with the two triangles of the wall beside it (plane,
residual zero) and came back as a torus at 0.0102 bent round a 15 mm axis that
is nowhere in the part, **+42% volume**. A merge of two recognised surfaces now
has to be no worse than the worse of them.

**4. The torus fitter had never once worked.** No test in the suite had ever
asked for a torus. Given a *perfect, noise-free* torus of R=20 r=6 it returned
**R=16.1, r=16.1, residual 4.6 mm** — and a plain torus therefore came back as
**2473 planes**, a boss-base fillet ring as several hundred. The seed paired
each normal with one a stride away and intersected the lines, which is how you
find a *cylinder's* axis; on a torus a normal line meets the **spine**, the
circle of tube centres, and only for neighbours along a meridian — neighbours
around the spine meet near the axis instead, a long way off. Half the samples
were in the wrong place. What is reliable is that every point of a torus lies
its minor radius from the spine *along its own normal*, so for the true r the
points `p − r·n` collapse onto a circle and for any other r they do not. That
makes r a one-dimensional search with a sharp minimum: scan it, take the sign
that works (outward on a boss, inward in a blend), read the axis, centre and
major radius off the circle.

| | before | after |
|---|---|---|
| plain torus R=20 r=6 | 2473 planes, 0 tori | **1 torus, R=20.0000 r=6.0000**, closed, volume 0.000% |
| boss fillet ring r=1.5 | 486–3528 planes | **R=10.5000 r=1.5000**, 9 faces from 9 |
| boss fillet ring r=3.0 | 133–951 planes | **R=12.0000 r=3.0000**, at every tessellation |

Making tori findable then made them *too* findable — the sweep went briefly to
143 of 216 — which is the whole reason 2 and 3 above are written the way they
are. An eight-parameter surface will always reach a little further than a
seven-parameter one; what stops it is not a smaller tolerance but being asked
whether it describes the facets.

### And the mirror image: a smooth run is not a hundred little planes

The same sweep exposed the opposite failure. A quad of a quad-meshed surface is
*exactly* planar, so a plane through it has no residual at all and passes every
per-piece test there is — correctly, since two triangles really is a box's
face. On a 2676-triangle organic shell the splitter carved out **129 such
planes and 3 spheres**, none of which exists.

No local test separates them, because locally they are the same thing. What
separates them is the run they came from, so the question is now asked once per
smooth run rather than once per piece: a prismatic run is **accounted for** —
its pieces are faces and they cover it — while a freeform run is not, and what
does fit in it is facet-sized. When less than half a run is explained and the
explanations are facet-sized, the whole run goes to triangles together. A
plate's side band, four fillets and four walls, is covered to the last triangle
and is untouched. Two smaller rules fell out of the same measurement: a face
carved out of a bigger patch has no witness the way a whole smooth run does, so
it is held to the exact bar rather than the ordinary one; and a fitted face
whose neighbours are *all* triangles buys nothing — the plane IS the triangle —
while costing a seam, so it becomes the triangle.

| | before | after |
|---|---|---|
| ellipsoid, 1286 tri | 74 planes + 1 cone invented | **0**, one faceted shell, volume exact to 1e-6 |
| curved shell, 4 drilled holes | 129 planes + 3 spheres | **0 spheres**, the four holes still exactly 2, 3, 4, 5 |
| plate sweep, 216 tessellations | 87 bad | 27 bad, and then 17 — see below |

### The tangency a surface intersector cannot find, and the fit no normal can see

Three more, each found the same way, and all three about **fillets** — which is
not a coincidence, because a fillet is *defined* by touching its neighbours
rather than crossing them, and touching is the degenerate case of everything.

**A grazing contact has no intersection to compute.** A boss's blend ring is a
torus that touches the plate top and the boss side tangentially; the surfaces
do not cross, so the system is singular exactly along the answer and
`GeomAPI_IntSS` returns nothing. The edge then fell back to the polyline
through the mesh vertices, while the torus's own face kept the true circle:
measured, one boundary of circumference 65.973 against another of 64.529, half
a millimetre apart at the middle of every segment, and the shell stayed open
along that seam — **2 free edges of 45**. But a fillet's contacts are not
general intersections at all, they are known in closed form: a torus is touched
by the plane perpendicular to its axis at exactly its minor radius, in the
circle of its *major* radius, and by the coaxial cylinder of radius R±r in the
circle of that radius. Both are checked against the chain before being
believed. The plate closed, at 18 faces of 18, volume +0.001%.

**Normal agreement cannot see a fit that is right.** Two adjacent rows of that
same blend ring: the sphere fitted them at 0.0377, the cone at 0.0350, the
torus at **0.0000030** — the true R=10.5, r=1.5 to seven figures. Their normal
agreements were 0.985, 0.987 and 0.987. At three decimal places the normals
cannot separate a surface that is *right* from one that is merely near, so the
sphere kept it by being asked first. The residual separates them by a factor of
twelve thousand, and on a tessellation of a CAD model it is not a matter of
degree — the vertices lie **on** the surface they came from or they do not. So
an exact fit now outranks agreement outright, and agreement decides only among
equals. On a noisy mesh nothing is exact, every candidate lands in the same
tier, and this is the old rule again.

**One row of a surface of revolution lies exactly on a sphere — and on a cone.**
That is a real degeneracy, not a bug: every constant-latitude circle of a torus
is also a circle of some sphere centred on its axis, and of some cone about it.
So a fillet ring came back as a stack of concentric bands, each with residual
zero, each passing every test. What no ring can pass is a test of its own
*width*: the sphere's coverage was measured as a cap angle, which on a ring
reads its **latitude** — wide — where its actual extent is a few degrees. Take
the range of colatitude rather than its maximum and a genuine cap is unchanged
(its mean direction is inside it, so the range runs from zero) while a ring
collapses to its true thinness. The rows then merge back into the torus they
came from — once the merge is also allowed to believe an exact residual over a
normal gate that coarse facets can never satisfy.

| | before | after |
|---|---|---|
| plate with a filleted boss | 31 planes, 6 cylinders, 4 faceted, shell open | **9 faces of 9**, R=10.5000 r=1.5000, closed, +0.000% |
| the same at a coarser mesh | 324 planes, blend in triangles | **18 faces of 18**, closed, +0.001% |
| plate sweep, 216 tessellations | 87 bad | **17 bad** — and every one of the 17 is now a closed solid within 0.25% of the mesh, 12 of them at an angular deflection of 51°, which is a seven-sided circle |

One more, small and worth stating because it is the difference between a
blend ring and a pile of triangles: a face whose *boundary* will not close used
to lose its **surface** as well. On a coarse mesh a neighbouring patch leaves a
nick in a rim and one loop of three fails to build; the recognised torus then
went back to triangles along with it. A periodic surface does not need its
boundary to be trimmed — the mesh's own uv extent does it — so that is the
fallback now, and `FaceWithinPatch` still sends anything that overreaches to
triangles as before. Dropping the failed loop instead is *not* an option and
was measured: an inner rim left out is a hole not cut, the face covers it, and
the volume came back 194% high. That one change took a coarse filleted plate
from 324 planes to its 18 real faces.

The suite is 132 assertions and covers all of it: a plain torus at two
tessellations; the coarse plate — the shape of the file that started this —
which must come back as exactly 7 planes and 10 cylinders with every radius
right to four decimals; and the same plate with a blend ring at its boss, which
must come back as 9 faces of 9 with the torus at R=10.5000 and r=1.5000. 600
fuzzed STL round-trips, 0 failures; 2.24 M triangles still convert in 3.5 s at
1.6 µs each.

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

> Stages A and B below were built. C and D were not; they are still the plan.

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
