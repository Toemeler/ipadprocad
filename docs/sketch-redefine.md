# Redefine a sketch

Right-click a sketch in the model browser and choose **Redefine** (**Neu
definieren** in German), then select an origin plane, a visible work plane,
or a planar solid face. The same command is available in the sketch's 3D
context menu. Escape cancels the selection.

The command changes the existing sketch's support. It preserves its name,
timeline position, layers, dimensions, user constraints, and consuming
features. The ordinary drawing keeps its local sketch coordinates.

For parallel planes, including opposite normals, projected geometry keeps
its source links. Solid edges are resolved in the original frame and the
same edges are projected in the destination frame. If the projections move
in sketch coordinates, constrained drawing geometry is solved against their
new positions. An unsatisfiable constraint system leaves the original sketch
intact and allows another support selection.

For nonparallel planes, projected entities become ordinary editable curves
in their existing local coordinates. Their implicit projection pins are
removed; explicit user dimensions and constraints remain.

A work-plane support retains its plane identity and follows future plane
edits. A face support retains its face fingerprint and follows future face
movement. Selecting an origin plane clears both links. Supports downstream
of the sketch's consuming features are rejected to avoid circular references.
Dependent feature errors are reported through the existing feature-error UI.

Redefine records one part undo step. Undo and redo restore both sketch
geometry and support metadata, and the changed support and projection tags
are saved with the existing document format. Temporary origin-plane
visibility is restored when the command finishes, is cancelled, or is
replaced by another command.

## Verification

`frontend/test/sketch_redefine_test.dart` covers selection, cancellation,
parallel and nonparallel projections, constraint solving and rejection,
menu availability, support metadata, save/reopen, undo/redo and command
replacement.

`frontend/test/sketch_redefine_native_test.dart` reproduces the WC-Rolle
model from `bug-2026-10-10T112805.zip` using the real OCCT backend. Set
`PROTOTYPE_NATIVE_DIR` to the directory containing the native CAD library.
It verifies the two circular projections, nonparallel detachment, and the
position of a consumed sketch's real extrusion across redefine/undo/redo.

The fixture contains only model and sketch data. The diagnostic sketch
export omits projection source indices; the native test recovers the exact
circle sources from the reconstructed solid.
