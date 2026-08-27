// M232 — reading a MESH file: STL, OBJ, 3MF.
//
// WHERE THE LINE IS
// -----------------
// This file turns a file on disk into a triangle soup and nothing more. It
// does NOT weld, orient, repair or reconstruct — that is geometry, it needs a
// spatial index over millions of vertices, and it lives in C++ next to the
// kernel (backend/occt/shim/mesh_recon.cpp). Parsing is I/O: it belongs here,
// where it is host-testable without a linked OCCT, exactly like every other
// Dart-side format concern in this app.
//
// The one exception is a CHEAP exact-bit dedup for STL. STL is the only one of
// the three that stores a triangle soup rather than an index, so an unwelded
// STL crosses the FFI boundary at three times the size it needs to. Slicers
// write bit-identical floats for a shared vertex, so a plain hash of the bits
// collapses most of it for one lookup per vertex. Vertices that are CLOSE but
// not identical are left alone deliberately — closing those is a tolerance
// decision, and tolerance decisions are made once, in C++, against the part's
// bounding box.
//
// No package for any of this, for the reason zip_writer.dart already gives:
// `archive` would read the 3MF container, and a model importer that only works
// when a pub fetch succeeded is an importer that is missing exactly when the
// build is in trouble. Raw inflate is ZLibCodec(raw: true) from dart:io, which
// is the same DEFLATE stream ZIP method 8 stores.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// The mesh formats Open accepts, lower-case, without the dot.
const List<String> kMeshExtensions = ['stl', 'obj', '3mf'];

/// Largest mesh file this will read, in bytes.
///
/// A guard against the crash rather than against slowness: reading is
/// `readAsBytesSync`, so a gigabyte file is a gigabyte of iPad memory before
/// a single triangle has been looked at, and the app is killed rather than
/// told. 256 MB is past any printable model — a binary STL of that size holds
/// five million triangles, well beyond [kMaxMeshTriangles] anyway, and the
/// wordier ASCII form still reaches about a million.
const int kMaxMeshFileBytes = 256 * 1024 * 1024;

/// Largest mesh this will hand to the converter.
///
/// The reconstruction runs at roughly 2–3 µs per triangle and it runs on the
/// UI THREAD, because the kernel is single-threaded by contract (see the
/// header of ffi/occt_engine.dart). Two million triangles is therefore about
/// seven seconds of frozen app on a desktop and perhaps fifteen on a device —
/// far enough out that nothing anyone prints comes close (a typical MakerWorld
/// model is fifty to five hundred thousand), and near enough that the app can
/// never be wedged for minutes by one bad download.
const int kMaxMeshTriangles = 2000000;

/// True when [path] ends in one of [kMeshExtensions].
bool isMeshPath(String path) {
  final lower = path.toLowerCase();
  for (final e in kMeshExtensions) {
    if (lower.endsWith('.$e')) return true;
  }
  return false;
}

/// Why a mesh file could not be read.
///
/// A CODE rather than a sentence, and deliberately so. M234 made the app
/// German with English as the second locale, and every user-visible string
/// lives in the ARB. A reader has no business holding UI prose in either
/// language: what crosses this boundary is the reason plus the one number or
/// name that belongs in it, and [AppState] turns that into a sentence in
/// whatever language the user is reading.
enum MeshFailure {
  /// The file is zero bytes.
  empty,

  /// Not one of [kMeshExtensions].
  unsupportedKind,

  /// It was there a moment ago and is not now.
  missing,

  /// The bytes could not be read at all (permissions, a dead iCloud stub).
  /// [MeshLoadException.detail] carries the OS reason where there was one.
  unreadable,

  /// Structurally fine, but there is no geometry in it: an STL whose facets
  /// are all degenerate, an OBJ with no `f` lines, a 3MF with no triangles.
  noGeometry,

  /// A record stops in the middle — a vertex with two coordinates, a triangle
  /// missing a corner.
  truncated,

  /// A face or triangle names a vertex that is not in the file.
  /// [MeshLoadException.detail] is the offending index.
  badIndex,

  /// A 3MF that is not a readable ZIP.
  notAnArchive,

  /// A ZIP with no `.model` part in it.
  noModel,

  /// A 3MF unit outside the spec's six. Refused rather than guessed: guessing
  /// a unit silently rescales somebody's part.
  /// [MeshLoadException.detail] is the unit as written.
  unknownUnit,

  /// Bigger than [kMaxMeshFileBytes]. [MeshLoadException.count] is its size in
  /// whole megabytes. Refused BEFORE reading, which is the only moment at
  /// which it can be refused rather than crashed on.
  fileTooLarge,

  /// More triangles than [kMaxMeshTriangles]. [MeshLoadException.count] is how
  /// many.
  tooManyTriangles,
}

/// Thrown by every reader in this file. Carries a [MeshFailure] and, where one
/// exists, the single value that belongs in the sentence.
class MeshLoadException implements Exception {
  MeshLoadException(this.reason, {this.detail, this.count});

  final MeshFailure reason;

  /// The offending text — an index, a unit name, an OS error. Never shown to
  /// the user on its own; it is a placeholder in a localised message.
  final String? detail;

  /// The offending number, where the reason has one. Kept apart from [detail]
  /// so the message can format it for the reader's language: a German user
  /// expects 2.000.000 where an English one expects 2,000,000.
  final int? count;

  /// For logs and test failures, not for the user.
  @override
  String toString() => 'MeshLoadException(${reason.name}'
      '${detail == null ? '' : ': $detail'}'
      '${count == null ? '' : ': $count'})';
}

/// An indexed triangle mesh, in millimetres, as read from a file.
///
/// [vertices] is 3 doubles per vertex; [triangles] is 3 vertex indices per
/// triangle, in the file's own winding order. Nothing here is guaranteed to be
/// manifold, oriented, or free of duplicates — a MakerWorld download regularly
/// is none of those. Cleaning is the reconstructor's job.
class MeshSoup {
  MeshSoup({
    required this.vertices,
    required this.triangles,
    required this.format,
    this.objectCount = 1,
    this.unitScale = 1.0,
    this.droppedTriangles = 0,
    this.uprightedFromZUp = false,
  });

  /// The same soup, marked as having been turned Z-up -> Y-up.
  ///
  /// The vertices are rotated IN PLACE (see [rotateZUpToYUp]), so this shares
  /// them rather than copying: the flag exists for the import log, and a log
  /// line is not worth a second copy of a large model.
  MeshSoup uprighted() => MeshSoup(
        vertices: vertices,
        triangles: triangles,
        format: format,
        objectCount: objectCount,
        unitScale: unitScale,
        droppedTriangles: droppedTriangles,
        uprightedFromZUp: true,
      );

  final Float64List vertices;
  final Int32List triangles;

  /// 'stl', 'obj' or '3mf' — what it was read from, for the log line.
  final String format;

  /// How many separate objects the file described (3MF build items, OBJ
  /// groups). They arrive merged; this is only ever reported, never acted on.
  final int objectCount;

  /// The factor the file's own unit needed to become millimetres. 3MF states
  /// its unit; STL and OBJ do not and are taken as mm, which is what every
  /// slicer and every MakerWorld model actually uses.
  final double unitScale;

  /// M276 — the file was Z-up and has been turned into the app's Y-up world.
  /// True for STL and 3MF, false for OBJ. Reported, never acted on.
  final bool uprightedFromZUp;

  /// Triangles the file listed that were dropped as degenerate or
  /// out-of-range. A non-zero count is worth saying out loud.
  final int droppedTriangles;

  int get vertexCount => vertices.length ~/ 3;
  int get triangleCount => triangles.length ~/ 3;
  bool get isEmpty => triangleCount == 0;

  /// (minX, minY, minZ, maxX, maxY, maxZ), or null when there are no vertices.
  Float64List? get bounds {
    if (vertices.isEmpty) return null;
    final b = Float64List(6);
    for (var k = 0; k < 3; k++) {
      b[k] = double.infinity;
      b[k + 3] = -double.infinity;
    }
    for (var i = 0; i < vertices.length; i += 3) {
      for (var k = 0; k < 3; k++) {
        final v = vertices[i + k];
        if (v < b[k]) b[k] = v;
        if (v > b[k + 3]) b[k + 3] = v;
      }
    }
    return b;
  }

  /// Length of the bounding-box diagonal — the scale every tolerance in the
  /// reconstructor is expressed as a fraction of.
  double get diagonal {
    final b = bounds;
    if (b == null) return 0;
    final dx = b[3] - b[0], dy = b[4] - b[1], dz = b[5] - b[2];
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }
}

/// Reads the mesh at [path], choosing the parser by extension.
///
/// Throws [MeshLoadException] carrying a [MeshFailure] the caller localises.
MeshSoup loadMeshFile(String path) {
  final f = File(path);
  if (!f.existsSync()) throw MeshLoadException(MeshFailure.missing);
  // Before reading, not after: the read is what would take the app down.
  final int size;
  try {
    size = f.lengthSync();
  } on FileSystemException catch (e) {
    throw MeshLoadException(MeshFailure.unreadable, detail: e.osError?.message);
  }
  if (size > kMaxMeshFileBytes) {
    throw MeshLoadException(MeshFailure.fileTooLarge,
        count: size ~/ (1024 * 1024));
  }
  final Uint8List bytes;
  try {
    bytes = f.readAsBytesSync();
  } on FileSystemException catch (e) {
    throw MeshLoadException(MeshFailure.unreadable,
        detail: e.osError?.message);
  }
  return loadMeshBytes(bytes, path: path);
}

// =========================================================================
// M276 — which way is up
// =========================================================================
//
// Reported as "bei einem stl import ist das modell falsch gedreht und wird
// immer seitlich importiert", and that is exactly what was happening: nothing
// on the import path touched the axes, so a file's own convention became the
// app's.
//
// The app is Y-UP. PartCamera.dir puts cos(pol) in Y, the renderer builds its
// basis by crossing with (0, 1, 0), and the ViewCube's TOP face is (0, 1, 0).
// The sketch planes look like evidence for Z and are not: XY is the FRONT
// plane (its normal is +Z, toward the viewer), which is the SolidWorks
// convention this app follows.
//
// The FILES are not all Y-up:
//
//   * STL has no header field for it, and every slicer, every printer and
//     every model site treats it as Z-UP, because the printer's bed is the
//     XY plane. A model exported to be printed stands up in Z.
//   * 3MF says so in its own specification: Z-up, same world.
//   * OBJ came out of graphics rather than manufacturing and is Y-UP by
//     convention — Maya, Blender's exporter default, and every game engine.
//
// So two of the three need a quarter turn and the third must not get one.
// Doing it per format rather than per file is the honest reading: none of the
// three states its up axis in the data, so the convention IS the information.

/// Which way is up in a file of this format.
enum MeshUpAxis { y, z }

/// STL and 3MF are Z-up, OBJ is Y-up. See the note above.
MeshUpAxis meshUpAxisOf(String format) =>
    format == 'obj' ? MeshUpAxis.y : MeshUpAxis.z;

/// Turns Z-up vertices into the app's Y-up world, in place.
///
/// A quarter turn about +X: (x, y, z) -> (x, z, -y). That takes the file's up
/// (0, 0, 1) onto the app's up (0, 1, 0), and the file's FRONT — which in the
/// printing world is -Y, the side facing the operator — onto +Z, which is the
/// ViewCube's FRONT. Both land where a person would expect them to.
///
/// In place, and on the Float64List the parser already allocated: an import is
/// already the one place in this app that holds a hundred megabytes of
/// vertices, and a second copy of them to rotate into is the difference
/// between a large model importing and the app being killed for memory.
void rotateZUpToYUp(Float64List v) {
  for (var i = 0; i + 2 < v.length; i += 3) {
    final y = v[i + 1];
    v[i + 1] = v[i + 2];
    v[i + 2] = -y;
  }
}

/// Reads a mesh already in memory. [path] is used only to pick the parser.
///
/// M276 — and this is where a file's up axis becomes the app's. The parsers
/// below stay faithful to their formats and return exactly what the file said;
/// the convention is applied once, here, on the app's own entry point.
MeshSoup loadMeshBytes(Uint8List bytes, {required String path}) {
  final lower = path.toLowerCase();
  if (bytes.isEmpty) throw MeshLoadException(MeshFailure.empty);
  final MeshSoup soup;
  if (lower.endsWith('.stl')) {
    soup = parseStl(bytes);
  } else if (lower.endsWith('.obj')) {
    soup = parseObj(bytes);
  } else if (lower.endsWith('.3mf')) {
    soup = parse3mf(bytes);
  } else {
    throw MeshLoadException(MeshFailure.unsupportedKind);
  }
  // Checked once here rather than in each reader: the limit is about what the
  // CONVERTER can do in a tolerable time, not about any one file format.
  if (soup.triangleCount > kMaxMeshTriangles) {
    throw MeshLoadException(MeshFailure.tooManyTriangles,
        count: soup.triangleCount);
  }
  // AFTER the size check, so a file that is about to be refused is not rotated
  // first — that is a full pass over vertices spent on a model nobody gets.
  if (meshUpAxisOf(soup.format) == MeshUpAxis.z) {
    rotateZUpToYUp(soup.vertices);
    return soup.uprighted();
  }
  return soup;
}

// =========================================================================
// STL
// =========================================================================

/// Binary or ASCII STL, decided by SIZE and not by the header.
///
/// The usual test — "does it start with the word solid" — is wrong, and wrong
/// on real files: plenty of binary writers put a product name in the 80-byte
/// header that begins with "solid". The size test is exact. A binary STL is
/// 84 + 50*n bytes for the n it declares at offset 80, and no ASCII file of a
/// meaningful mesh lands on that number by accident.
MeshSoup parseStl(Uint8List bytes) {
  if (bytes.length >= 84) {
    final bd = ByteData.sublistView(bytes);
    final n = bd.getUint32(80, Endian.little);
    // Guard the multiply: a corrupt count must not overflow into a plausible
    // length. 50 bytes per triangle, so anything past ~85M triangles is a
    // broken file whatever its size says.
    if (n <= 0x4000000 && bytes.length == 84 + 50 * n) {
      return _parseBinaryStl(bd, n);
    }
  }
  return _parseAsciiStl(bytes);
}

MeshSoup _parseBinaryStl(ByteData bd, int n) {
  // The count is in the header, so this costs nothing and is checked before
  // the arrays are sized from it rather than after they are filled.
  if (n > kMaxMeshTriangles) {
    throw MeshLoadException(MeshFailure.tooManyTriangles, count: n);
  }
  final w = _VertexWelder(n * 3);
  final tris = Int32List(n * 3);
  var kept = 0, dropped = 0;
  var off = 84;
  for (var t = 0; t < n; t++) {
    // 12 bytes of facet normal are skipped deliberately: STL normals are
    // routinely absent, zero, or simply wrong, and the reconstructor computes
    // them from the winding anyway. Trusting them would import the file's bugs.
    off += 12;
    double f(int k) => bd.getFloat32(off + k, Endian.little);
    final a = w.add(f(0), f(4), f(8));
    final b = w.add(f(12), f(16), f(20));
    final c = w.add(f(24), f(28), f(32));
    off += 36 + 2; // 3 vertices + the 2-byte attribute word
    if (a == b || b == c || a == c) {
      dropped++;
      continue;
    }
    tris[kept * 3] = a;
    tris[kept * 3 + 1] = b;
    tris[kept * 3 + 2] = c;
    kept++;
  }
  if (kept == 0) {
    throw MeshLoadException(MeshFailure.noGeometry);
  }
  return MeshSoup(
    vertices: w.finish(),
    triangles: Int32List.sublistView(tris, 0, kept * 3),
    format: 'stl',
    droppedTriangles: dropped,
  );
}

MeshSoup _parseAsciiStl(Uint8List bytes) {
  final s = _ByteScanner(bytes);
  final w = _VertexWelder(1024);
  final tris = <int>[];
  final xyz = Float64List(3);
  var dropped = 0;
  var pending = <int>[];
  while (true) {
    final word = s.word();
    if (word == null) break;
    if (word != 'vertex') continue;
    for (var k = 0; k < 3; k++) {
      final v = s.number();
      if (v == null) {
        throw MeshLoadException(MeshFailure.truncated);
      }
      xyz[k] = v;
    }
    pending.add(w.add(xyz[0], xyz[1], xyz[2]));
    if (pending.length == 3) {
      if (pending[0] != pending[1] &&
          pending[1] != pending[2] &&
          pending[0] != pending[2]) {
        tris.addAll(pending);
        if (tris.length > kMaxMeshTriangles * 3) {
          throw MeshLoadException(MeshFailure.tooManyTriangles,
              count: tris.length ~/ 3);
        }
      } else {
        dropped++;
      }
      pending = <int>[];
    }
  }
  if (tris.isEmpty) {
    throw MeshLoadException(MeshFailure.noGeometry);
  }
  return MeshSoup(
    vertices: w.finish(),
    triangles: Int32List.fromList(tris),
    format: 'stl',
    droppedTriangles: dropped,
  );
}

// =========================================================================
// OBJ
// =========================================================================

/// Wavefront OBJ — the `v` and `f` lines, and nothing else.
///
/// Materials, texture coordinates, normals, smoothing groups and object names
/// are all skipped: none of them survives into a B-Rep, and a reader that
/// parses them can fail on them. Faces with more than three corners are fan-
/// triangulated, which is right for the convex faces OBJ exporters emit and is
/// no worse than the alternative for the rest.
MeshSoup parseObj(Uint8List bytes) {
  final s = _ByteScanner(bytes);
  final verts = <double>[];
  final tris = <int>[];
  final face = <int>[];
  var dropped = 0, groups = 0;
  while (true) {
    final key = s.word();
    if (key == null) break;
    if (key == 'v') {
      final x = s.number(), y = s.number(), z = s.number();
      if (x == null || y == null || z == null) {
        throw MeshLoadException(MeshFailure.truncated);
      }
      verts.addAll([x, y, z]);
      // A `v` line may carry r,g,b after z. skipLine drops them with the rest.
      s.skipLine();
    } else if (key == 'f') {
      face.clear();
      while (true) {
        final ref = s.faceRef();
        if (ref == null) break;
        // OBJ is 1-based, and NEGATIVE indices count back from the newest
        // vertex — which is why this resolves against the current length
        // rather than the final one.
        final n = verts.length ~/ 3;
        final idx = ref < 0 ? n + ref : ref - 1;
        if (idx < 0 || idx >= n) {
          throw MeshLoadException(MeshFailure.badIndex, detail: '$ref');
        }
        face.add(idx);
      }
      for (var i = 2; i < face.length; i++) {
        final a = face[0], b = face[i - 1], c = face[i];
        if (a == b || b == c || a == c) {
          dropped++;
          continue;
        }
        tris.addAll([a, b, c]);
      }
      if (tris.length > kMaxMeshTriangles * 3) {
        throw MeshLoadException(MeshFailure.tooManyTriangles,
            count: tris.length ~/ 3);
      }
    } else if (key == 'o' || key == 'g') {
      groups++;
      s.skipLine();
    } else {
      s.skipLine();
    }
  }
  if (tris.isEmpty) {
    throw MeshLoadException(MeshFailure.noGeometry);
  }
  return MeshSoup(
    vertices: Float64List.fromList(verts),
    triangles: Int32List.fromList(tris),
    format: 'obj',
    objectCount: groups < 1 ? 1 : groups,
    droppedTriangles: dropped,
  );
}

// =========================================================================
// 3MF
// =========================================================================

/// Millimetres per 3MF unit. The spec's six names; anything else is refused
/// rather than guessed, because guessing a unit silently scales a part.
const Map<String, double> _k3mfUnits = {
  'micron': 0.001,
  'millimeter': 1.0,
  'centimeter': 10.0,
  'inch': 25.4,
  'foot': 304.8,
  'meter': 1000.0,
};

/// 3MF — a ZIP holding an XML model.
///
/// Handles what MakerWorld actually ships: several `<object>`s, objects built
/// out of `<components>` referencing other objects, and a `<build>` placing
/// items with a 3x4 transform. All of it is flattened into one soup in
/// millimetres, because a part is what arrives, not a scene graph.
MeshSoup parse3mf(Uint8List bytes) {
  final entries = _readZip(bytes);
  // The spec says find the model through _rels/.rels; every writer in
  // existence also puts it at the conventional path. Try the convention, then
  // fall back to "the only .model in the container", which covers the rest.
  var xml = entries['3D/3dmodel.model'];
  if (xml == null) {
    for (final e in entries.entries) {
      if (e.key.toLowerCase().endsWith('.model')) {
        xml = e.value;
        break;
      }
    }
  }
  if (xml == null) {
    throw MeshLoadException(MeshFailure.noModel);
  }
  return _parse3mfModel(utf8.decode(xml, allowMalformed: true));
}

class _3mfObject {
  final verts = <double>[]; // local coordinates
  final tris = <int>[];
  /// (objectId, transform-or-null) for a components object.
  final components = <MapEntry<String, Float64List?>>[];
}

MeshSoup _parse3mfModel(String xml) {
  final scan = _XmlScanner(xml);
  final objects = <String, _3mfObject>{};
  final items = <MapEntry<String, Float64List?>>[];
  var unit = 1.0;

  _3mfObject? cur;
  var inVertices = false, inTriangles = false;
  var sawModel = false;

  while (true) {
    final tag = scan.next();
    if (tag == null) break;
    switch (tag.name) {
      case 'model':
        if (!tag.isEnd) {
          sawModel = true;
          final u = tag.attrs['unit'];
          if (u != null) {
            final f = _k3mfUnits[u.toLowerCase()];
            if (f == null) {
              throw MeshLoadException(MeshFailure.unknownUnit, detail: u);
            }
            unit = f;
          }
        }
        break;
      case 'object':
        if (tag.isEnd) {
          cur = null;
        } else {
          final id = tag.attrs['id'];
          if (id != null) objects[id] = cur = _3mfObject();
          if (tag.selfClosing) cur = null;
        }
        break;
      case 'vertices':
        inVertices = !tag.isEnd && !tag.selfClosing;
        break;
      case 'triangles':
        inTriangles = !tag.isEnd && !tag.selfClosing;
        break;
      case 'vertex':
        if (inVertices && cur != null && !tag.isEnd) {
          cur.verts.addAll([
            _attrNum(tag.attrs, 'x'),
            _attrNum(tag.attrs, 'y'),
            _attrNum(tag.attrs, 'z'),
          ]);
        }
        break;
      case 'triangle':
        if (inTriangles && cur != null && !tag.isEnd) {
          cur.tris.addAll([
            _attrInt(tag.attrs, 'v1'),
            _attrInt(tag.attrs, 'v2'),
            _attrInt(tag.attrs, 'v3'),
          ]);
        }
        break;
      case 'component':
        if (cur != null && !tag.isEnd) {
          final id = tag.attrs['objectid'];
          if (id != null) {
            cur.components
                .add(MapEntry(id, _parse3mfMatrix(tag.attrs['transform'])));
          }
        }
        break;
      case 'item':
        if (!tag.isEnd) {
          final id = tag.attrs['objectid'];
          if (id != null) {
            items.add(MapEntry(id, _parse3mfMatrix(tag.attrs['transform'])));
          }
        }
        break;
    }
  }

  if (!sawModel) {
    throw MeshLoadException(MeshFailure.noModel);
  }
  // A 3MF with no <build> is legal and common enough — treat every object that
  // nothing references as a root, so the geometry is not silently dropped.
  var roots = items;
  if (roots.isEmpty) {
    final referenced = <String>{};
    for (final o in objects.values) {
      for (final c in o.components) {
        referenced.add(c.key);
      }
    }
    roots = [
      for (final id in objects.keys)
        if (!referenced.contains(id)) MapEntry(id, null)
    ];
  }

  final verts = <double>[];
  final tris = <int>[];
  var dropped = 0;

  // Depth-first flatten. `stack` guards against a components cycle, which a
  // malformed file can contain and which would otherwise not terminate.
  void emit(String id, Float64List? m, Set<String> stack, int depth) {
    if (depth > 64 || !stack.add(id)) return;
    final o = objects[id];
    if (o != null) {
      final base = verts.length ~/ 3;
      final n = o.verts.length ~/ 3;
      for (var i = 0; i < n; i++) {
        final x = o.verts[i * 3];
        final y = o.verts[i * 3 + 1];
        final z = o.verts[i * 3 + 2];
        if (m == null) {
          verts.addAll([x * unit, y * unit, z * unit]);
        } else {
          verts.addAll([
            (m[0] * x + m[3] * y + m[6] * z + m[9]) * unit,
            (m[1] * x + m[4] * y + m[7] * z + m[10]) * unit,
            (m[2] * x + m[5] * y + m[8] * z + m[11]) * unit,
          ]);
        }
      }
      for (var i = 0; i + 2 < o.tris.length; i += 3) {
        final a = o.tris[i], b = o.tris[i + 1], c = o.tris[i + 2];
        if (a < 0 || b < 0 || c < 0 || a >= n || b >= n || c >= n ||
            a == b || b == c || a == c) {
          dropped++;
          continue;
        }
        tris.addAll([base + a, base + b, base + c]);
      }
      // Checked HERE, inside the flatten, not once at the end.
      //
      // A 3MF names its geometry by reference: an object can be a list of
      // components, each pointing at another object, and four levels of sixty
      // turn one cube into thirteen million triangles from a file of a few
      // kilobytes. Waiting until the flatten finished would mean allocating
      // all of it first — which is the crash this limit exists to prevent, not
      // the wait.
      if (tris.length > kMaxMeshTriangles * 3) {
        throw MeshLoadException(MeshFailure.tooManyTriangles,
            count: tris.length ~/ 3);
      }
      for (final comp in o.components) {
        emit(comp.key, _mul3mf(m, comp.value), stack, depth + 1);
      }
    }
    stack.remove(id);
  }

  for (final it in roots) {
    emit(it.key, it.value, <String>{}, 0);
  }

  if (tris.isEmpty) {
    throw MeshLoadException(MeshFailure.noGeometry);
  }
  return MeshSoup(
    vertices: Float64List.fromList(verts),
    triangles: Int32List.fromList(tris),
    format: '3mf',
    objectCount: roots.length,
    unitScale: unit,
    droppedTriangles: dropped,
  );
}

double _attrNum(Map<String, String> a, String k) {
  final v = a[k];
  final d = v == null ? null : double.tryParse(v);
  if (d == null || !d.isFinite) {
    throw MeshLoadException(MeshFailure.truncated, detail: k);
  }
  return d;
}

int _attrInt(Map<String, String> a, String k) {
  final v = a[k];
  final i = v == null ? null : int.tryParse(v);
  if (i == null) {
    throw MeshLoadException(MeshFailure.truncated, detail: k);
  }
  return i;
}

/// 3MF writes a transform as twelve numbers: the 3x3 basis in ROW-major order
/// followed by the translation. Stored here in that same order, so index 9..11
/// is the translation and [0,3,6] is the first basis column.
Float64List? _parse3mfMatrix(String? s) {
  if (s == null) return null;
  final parts = s.trim().split(RegExp(r'\s+'));
  if (parts.length != 12) return null;
  final m = Float64List(12);
  for (var i = 0; i < 12; i++) {
    final d = double.tryParse(parts[i]);
    if (d == null || !d.isFinite) return null;
    m[i] = d;
  }
  return m;
}

/// Composes outer∘inner, both in the 12-number 3MF layout.
Float64List? _mul3mf(Float64List? outer, Float64List? inner) {
  if (outer == null) return inner;
  if (inner == null) return outer;
  final r = Float64List(12);
  for (var c = 0; c < 3; c++) {
    for (var k = 0; k < 3; k++) {
      var acc = 0.0;
      for (var j = 0; j < 3; j++) {
        acc += inner[c * 3 + j] * outer[j * 3 + k];
      }
      r[c * 3 + k] = acc;
    }
  }
  for (var k = 0; k < 3; k++) {
    r[9 + k] = inner[9] * outer[k] +
        inner[10] * outer[3 + k] +
        inner[11] * outer[6 + k] +
        outer[9 + k];
  }
  return r;
}

// =========================================================================
// A ZIP reader — the mirror of zip_writer.dart, and just as small
// =========================================================================

/// Every entry's bytes, by name. Stored (method 0) and deflated (method 8),
/// which is all 3MF ever uses.
///
/// Reads the CENTRAL DIRECTORY rather than walking local headers: a local
/// header may declare zero sizes and defer them to a trailing data descriptor,
/// and the central directory always carries the real numbers.
/// The 32-bit sentinel a ZIP64 container puts in a field whose real value is
/// out in the extra data.
const int _kZip64Sentinel = 0xFFFFFFFF;

/// M278 — the real (compressedSize, localHeaderOffset) for a central-directory
/// entry whose fixed record holds sentinels.
///
/// The ZIP64 extended-information field (header id 0x0001) is a POSITIONAL
/// record, and that is the whole subtlety: it carries only the fields that
/// were replaced by a sentinel, in the spec's order — uncompressed size,
/// compressed size, local header offset, disk number. Reading it as a fixed
/// layout works on the common case (all three replaced) and silently returns
/// the wrong number on a file where only one of them was, which is exactly the
/// kind of bug that shows up as a corrupt model months later.
(int, int) _zip64Sizes(ByteData bd, int extraAt, int extraLen, int uncompSize,
    int compSize, int local) {
  var comp = compSize, off = local;
  var q = extraAt;
  final end = extraAt + extraLen;
  while (q + 4 <= end && q + 4 <= bd.lengthInBytes) {
    final id = bd.getUint16(q, Endian.little);
    final size = bd.getUint16(q + 2, Endian.little);
    if (q + 4 + size > bd.lengthInBytes) break;
    if (id == 0x0001) {
      var f = q + 4;
      final stop = q + 4 + size;
      // EACH slot is present only if ITS OWN field was the one replaced. The
      // uncompressed size is not wanted here and is still read past, because
      // it occupies eight bytes whenever it was a sentinel — and whether it
      // was is a question about the uncompressed size, not about the
      // compressed one. Getting that wrong reads the compressed size out of
      // the uncompressed slot on any file where only one of the two overflowed.
      if (uncompSize == _kZip64Sentinel && f + 8 <= stop) f += 8;
      if (compSize == _kZip64Sentinel && f + 8 <= stop) {
        comp = bd.getUint64(f, Endian.little);
        f += 8;
      }
      if (local == _kZip64Sentinel && f + 8 <= stop) {
        off = bd.getUint64(f, Endian.little);
      }
      break;
    }
    q += 4 + size;
  }
  return (comp, off);
}

Map<String, Uint8List> _readZip(Uint8List bytes) {
  final bd = ByteData.sublistView(bytes);
  final eocd = _findEocd(bytes);
  if (eocd < 0) {
    throw MeshLoadException(MeshFailure.notAnArchive);
  }
  var count = bd.getUint16(eocd + 10, Endian.little);
  var p = bd.getUint32(eocd + 16, Endian.little);
  // M278 — ZIP64.
  //
  // Reported as "the mesh to cad converter doesn't handle 3mf files", and the
  // converter never saw one: this container's classic end-of-central-directory
  // record holds 0xFFFFFFFF where the directory offset should be, so the walk
  // below started past the end of the file, found nothing, and the 3MF reader
  // said "no model".
  //
  // A quarter of a megabyte does not need ZIP64 — and that is the point. The
  // format is not only for archives past 4 GB: several writers (this file came
  // from a slicer) emit the records unconditionally, so treating ZIP64 as the
  // exotic case is treating a large share of real 3MF files as broken.
  if (count == 0xFFFF || p == _kZip64Sentinel) {
    final z = _findZip64Eocd(bd, bytes, eocd);
    if (z < 0) throw MeshLoadException(MeshFailure.notAnArchive);
    count = bd.getUint64(z + 32, Endian.little);
    p = bd.getUint64(z + 48, Endian.little);
  }
  final out = <String, Uint8List>{};
  for (var i = 0; i < count; i++) {
    if (p + 46 > bytes.length || bd.getUint32(p, Endian.little) != 0x02014b50) {
      break;
    }
    final method = bd.getUint16(p + 10, Endian.little);
    var compSize = bd.getUint32(p + 20, Endian.little);
    final nameLen = bd.getUint16(p + 28, Endian.little);
    final extraLen = bd.getUint16(p + 30, Endian.little);
    final commentLen = bd.getUint16(p + 32, Endian.little);
    var local = bd.getUint32(p + 42, Endian.little);
    final name = utf8.decode(
        bytes.sublist(p + 46, math.min(p + 46 + nameLen, bytes.length)),
        allowMalformed: true);
    if (compSize == _kZip64Sentinel || local == _kZip64Sentinel) {
      (compSize, local) = _zip64Sizes(bd, p + 46 + nameLen, extraLen,
          bd.getUint32(p + 24, Endian.little), compSize, local);
    }
    p += 46 + nameLen + extraLen + commentLen;

    if (local + 30 > bytes.length ||
        bd.getUint32(local, Endian.little) != 0x04034b50) {
      continue;
    }
    final lNameLen = bd.getUint16(local + 26, Endian.little);
    final lExtraLen = bd.getUint16(local + 28, Endian.little);
    final start = local + 30 + lNameLen + lExtraLen;
    final end = start + compSize;
    if (start > bytes.length || end > bytes.length) continue;
    final raw = Uint8List.sublistView(bytes, start, end);
    if (method == 0) {
      out[name] = raw;
    } else if (method == 8) {
      try {
        out[name] = Uint8List.fromList(ZLibCodec(raw: true).decode(raw));
      } on FormatException {
        // One unreadable entry is not a broken container — the model may well
        // be another one. Only "no model at all" is fatal, upstream.
        continue;
      }
    }
  }
  return out;
}

/// M278 — offset of the ZIP64 end-of-central-directory RECORD, or -1.
///
/// Reached through the LOCATOR, which sits in the twenty bytes immediately
/// before the classic EOCD and holds the record's absolute offset. Going
/// through the locator rather than scanning for the record's own signature is
/// what keeps this correct on a container that happens to contain those four
/// bytes as data — which a compressed mesh very well might.
int _findZip64Eocd(ByteData bd, Uint8List bytes, int eocd) {
  final loc = eocd - 20;
  if (loc < 0 || bd.getUint32(loc, Endian.little) != 0x07064b50) return -1;
  final at = bd.getUint64(loc + 8, Endian.little);
  if (at < 0 || at + 56 > bytes.length) return -1;
  if (bd.getUint32(at, Endian.little) != 0x06064b50) return -1;
  return at;
}

/// Offset of the end-of-central-directory record, or -1.
int _findEocd(Uint8List b) {
  // It is at most 22 + 65535 bytes from the end (the trailing comment), so a
  // bounded backwards scan finds it without reading the whole file again.
  final lowest = math.max(0, b.length - 22 - 65535);
  for (var i = b.length - 22; i >= lowest; i--) {
    if (b[i] == 0x50 &&
        b[i + 1] == 0x4b &&
        b[i + 2] == 0x05 &&
        b[i + 3] == 0x06) {
      return i;
    }
  }
  return -1;
}

// =========================================================================
// Scanners
// =========================================================================

/// Collapses vertices with BIT-IDENTICAL coordinates. See the file header for
/// why this stops short of a tolerance weld.
class _VertexWelder {
  _VertexWelder(int hint) : _xyz = Float64List(math.max(48, hint * 3));
  Float64List _xyz;
  int _n = 0;
  final Map<int, List<int>> _byHash = {};

  int add(double x, double y, double z) {
    final h = _hash(x, y, z);
    final bucket = _byHash[h];
    if (bucket != null) {
      for (final i in bucket) {
        if (_xyz[i * 3] == x && _xyz[i * 3 + 1] == y && _xyz[i * 3 + 2] == z) {
          return i;
        }
      }
    }
    if ((_n + 1) * 3 > _xyz.length) {
      final grown = Float64List(_xyz.length * 2);
      grown.setRange(0, _n * 3, _xyz);
      _xyz = grown;
    }
    _xyz[_n * 3] = x;
    _xyz[_n * 3 + 1] = y;
    _xyz[_n * 3 + 2] = z;
    (_byHash[h] ??= <int>[]).add(_n);
    return _n++;
  }

  Float64List finish() => Float64List.sublistView(_xyz, 0, _n * 3);

  static final Float64List _one = Float64List(1);
  static final Int32List _asInts = Int32List.sublistView(_one);

  /// Hashes the exact bits. -0.0 is folded onto 0.0 first: they compare equal
  /// with ==, so leaving them apart would put an equal pair in two buckets and
  /// defeat the lookup.
  static int _hash(double x, double y, double z) {
    var h = 0x811c9dc5;
    for (final v in [x, y, z]) {
      _one[0] = v == 0 ? 0.0 : v;
      h = (h ^ _asInts[0]) * 0x01000193 & 0x3fffffff;
      h = (h ^ _asInts[1]) * 0x01000193 & 0x3fffffff;
    }
    return h;
  }
}

/// A byte-level tokenizer for the two text formats.
///
/// Deliberately not `split('\n')`: an ASCII STL of a million triangles is a
/// quarter of a gigabyte of text, and cutting it into seven million String
/// objects to read numbers out of them is how an importer runs an iPad out of
/// memory.
class _ByteScanner {
  _ByteScanner(this._b);
  final Uint8List _b;
  int _i = 0;

  static const int _nl = 0x0a, _cr = 0x0d, _sp = 0x20, _tab = 0x09;
  static const int _slash = 0x2f, _minus = 0x2d, _plus = 0x2b, _dot = 0x2e;
  static const int _zero = 0x30, _nine = 0x39;
  static const int _hash = 0x23;

  bool _isSpace(int c) => c == _sp || c == _tab || c == _cr || c == _nl;

  void skipLine() {
    while (_i < _b.length && _b[_i] != _nl) {
      _i++;
    }
  }

  void _skipSpace() {
    while (_i < _b.length) {
      final c = _b[_i];
      if (c == _hash) {
        skipLine();
      } else if (_isSpace(c)) {
        _i++;
      } else {
        return;
      }
    }
  }

  /// The next whitespace-delimited token as a String, or null at end of input.
  String? word() {
    _skipSpace();
    if (_i >= _b.length) return null;
    final start = _i;
    while (_i < _b.length && !_isSpace(_b[_i])) {
      _i++;
    }
    return String.fromCharCodes(_b, start, _i);
  }

  /// The next token parsed as a number, or null if there is not one there.
  /// Does NOT consume the token when it is not numeric, so the caller can
  /// treat that as end-of-record.
  double? number() {
    _skipSpace();
    if (_i >= _b.length) return null;
    final start = _i;
    final c = _b[_i];
    if (c != _minus && c != _plus && c != _dot && (c < _zero || c > _nine)) {
      return null;
    }
    while (_i < _b.length && !_isSpace(_b[_i])) {
      _i++;
    }
    final v = double.tryParse(String.fromCharCodes(_b, start, _i));
    if (v == null || !v.isFinite) {
      _i = start;
      return null;
    }
    return v;
  }

  /// One corner of an OBJ `f` line: the vertex index of `v`, `v/vt`, `v//vn`
  /// or `v/vt/vn`. Null at the end of the line.
  int? faceRef() {
    // Stop at the newline: the next line's leading token is not a corner.
    var j = _i;
    while (j < _b.length && (_b[j] == _sp || _b[j] == _tab)) {
      j++;
    }
    if (j >= _b.length || _b[j] == _nl || _b[j] == _cr || _b[j] == _hash) {
      return null;
    }
    _i = j;
    final start = _i;
    var neg = false;
    if (_b[_i] == _minus) {
      neg = true;
      _i++;
    } else if (_b[_i] == _plus) {
      _i++;
    }
    var v = 0, digits = 0;
    while (_i < _b.length && _b[_i] >= _zero && _b[_i] <= _nine) {
      v = v * 10 + (_b[_i] - _zero);
      _i++;
      digits++;
    }
    if (digits == 0) {
      _i = start;
      return null;
    }
    // Swallow the /vt/vn remainder so the next call starts on a corner.
    while (_i < _b.length && !_isSpace(_b[_i])) {
      if (_b[_i] != _slash && (_b[_i] < _zero || _b[_i] > _nine) &&
          _b[_i] != _minus) {
        break;
      }
      _i++;
    }
    return neg ? -v : v;
  }
}

class _XmlTag {
  _XmlTag(this.name, this.attrs, this.isEnd, this.selfClosing);
  final String name;
  final Map<String, String> attrs;
  final bool isEnd;
  final bool selfClosing;
}

/// A pull scanner over the subset of XML that 3MF is written in.
///
/// Not a general XML parser and not trying to be: it reads element names and
/// attributes, skips comments, CDATA, processing instructions and the DOCTYPE,
/// and ignores namespace prefixes (3MF namespaces the core elements but the
/// local name is unambiguous). Text content is skipped entirely — every number
/// in a 3MF model lives in an attribute.
class _XmlScanner {
  _XmlScanner(this._s);
  final String _s;
  int _i = 0;

  _XmlTag? next() {
    while (true) {
      final lt = _s.indexOf('<', _i);
      if (lt < 0) return null;
      if (_s.startsWith('<!--', lt)) {
        final end = _s.indexOf('-->', lt + 4);
        _i = end < 0 ? _s.length : end + 3;
        continue;
      }
      if (_s.startsWith('<![CDATA[', lt)) {
        final end = _s.indexOf(']]>', lt + 9);
        _i = end < 0 ? _s.length : end + 3;
        continue;
      }
      if (_s.startsWith('<?', lt) || _s.startsWith('<!', lt)) {
        final end = _s.indexOf('>', lt);
        _i = end < 0 ? _s.length : end + 1;
        continue;
      }
      // Find the closing '>' that is not inside an attribute value.
      var j = lt + 1;
      String? quote;
      while (j < _s.length) {
        final c = _s[j];
        if (quote != null) {
          if (c == quote) quote = null;
        } else if (c == '"' || c == "'") {
          quote = c;
        } else if (c == '>') {
          break;
        }
        j++;
      }
      if (j >= _s.length) return null;
      final body = _s.substring(lt + 1, j);
      _i = j + 1;
      return _tagOf(body);
    }
  }

  static _XmlTag _tagOf(String body) {
    var b = body;
    final isEnd = b.startsWith('/');
    if (isEnd) b = b.substring(1);
    final selfClosing = b.endsWith('/');
    if (selfClosing) b = b.substring(0, b.length - 1);
    var k = 0;
    while (k < b.length && !_isXmlSpace(b.codeUnitAt(k))) {
      k++;
    }
    var name = b.substring(0, k);
    final colon = name.indexOf(':');
    if (colon >= 0) name = name.substring(colon + 1);
    return _XmlTag(name.toLowerCase(), _attrsOf(b, k), isEnd, selfClosing);
  }

  static bool _isXmlSpace(int c) =>
      c == 0x20 || c == 0x09 || c == 0x0a || c == 0x0d;

  static Map<String, String> _attrsOf(String b, int from) {
    final out = <String, String>{};
    var i = from;
    while (i < b.length) {
      while (i < b.length && _isXmlSpace(b.codeUnitAt(i))) {
        i++;
      }
      final ns = i;
      while (i < b.length && b[i] != '=' && !_isXmlSpace(b.codeUnitAt(i))) {
        i++;
      }
      if (i >= b.length || ns == i) break;
      var key = b.substring(ns, i);
      final colon = key.indexOf(':');
      if (colon >= 0) key = key.substring(colon + 1);
      while (i < b.length && _isXmlSpace(b.codeUnitAt(i))) {
        i++;
      }
      if (i >= b.length || b[i] != '=') continue;
      i++;
      while (i < b.length && _isXmlSpace(b.codeUnitAt(i))) {
        i++;
      }
      if (i >= b.length) break;
      final q = b[i];
      String value;
      if (q == '"' || q == "'") {
        final end = b.indexOf(q, i + 1);
        if (end < 0) break;
        value = b.substring(i + 1, end);
        i = end + 1;
      } else {
        final vs = i;
        while (i < b.length && !_isXmlSpace(b.codeUnitAt(i))) {
          i++;
        }
        value = b.substring(vs, i);
      }
      out[key.toLowerCase()] = _unescape(value);
    }
    return out;
  }

  static String _unescape(String v) => v.contains('&')
      ? v
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&quot;', '"')
          .replaceAll('&apos;', "'")
          .replaceAll('&amp;', '&')
      : v;
}
