// M344 — the render assets, and the rule that the app works without them.
//
// ---------------------------------------------------------------------------
// WHAT IS IN HERE
// ---------------------------------------------------------------------------
//
// Two kinds of file, both optional, both large, both looked up once at launch:
//
//   * an equirectangular HDRI, which is what a metal surface reflects and
//     therefore most of what makes a render look photographed rather than
//     shaded;
//   * per-appearance PBR texture sets — base colour, roughness, metallic,
//     height, occlusion — which is what makes a surface look machined rather
//     than moulded.
//
// ---------------------------------------------------------------------------
// WHY THEY ARE NOT FLUTTER ASSETS
// ---------------------------------------------------------------------------
//
// Because Cycles loads images through OpenImageIO, from a PATH, on a
// background thread, and a Flutter asset is a byte range inside a bundle that
// only the Dart side can address. Handing the renderer a path into
// `flutter_assets` would work today and break the first time Flutter changes
// how it lays that directory out.
//
// They go where the KERNEL TREE goes instead: beside it, under the resource
// root that cycles_boot already computes and already hands to the shim. That
// directory is Cycles' own — it is the one thing in the bundle the renderer is
// entitled to assume the layout of — and the CI step that copies the kernel
// source into it copies these at the same time, from the same place, under the
// same cache key.
//
// ---------------------------------------------------------------------------
// AND WHY EVERY ONE OF THEM IS OPTIONAL
// ---------------------------------------------------------------------------
//
// They are binaries measured in tens of megabytes and they are not in this
// repository. A build made from a fresh clone has none of them, and that build
// has to be the app that shipped — the M332 light rig and the M337 flat
// Principled surfaces, exactly as before — and not a broken one. So nothing
// here throws, nothing here is required, and every lookup answers null.
//
// The shim agrees from the other side: it checks each path with fopen before
// it builds a node, so a file that goes missing between this scan and the
// render is a surface without a texture rather than a black image.
import 'dart:io';

import 'log.dart';

/// Where the optional render assets live inside the bundle, relative to the
/// resource root the shim is given.
const String kCyclesAssetDir = 'assets';

/// The environment map's directory and the base name of the one that is used.
///
/// ONE FILE, NOT A LIST. A studio HDRI is a lighting decision, not a
/// preference: two of them are two different products, and a picker for it
/// would be the first control in this app that changes what a render MEANS
/// rather than how it is computed. If a second is ever wanted it arrives as a
/// named choice with a reason, not as whatever the directory happens to hold.
const String kCyclesHdriDir = 'hdri';
const String kCyclesHdriName = 'studio';

/// The extensions an environment map may have, in the order they are tried.
///
/// Radiance first because it is a third the size of the equivalent EXR at a
/// quality difference nobody can see in a reflection, and size is the whole
/// argument on an iPad: the file is decoded into memory in full and lives
/// there for as long as rendered mode is on.
const List<String> kCyclesHdriExtensions = ['hdr', 'exr'];

/// Where a texture set for appearance `id` lives, and what its maps are called.
///
/// The names are the ones every PBR library on earth uses, so a set downloaded
/// from Poly Haven or ambientCG can be dropped in with nothing renamed but the
/// directory. Extensions are tried in order per map.
const String kCyclesTextureDir = 'materials';
const List<String> kCyclesTextureExtensions = ['jpg', 'png'];

/// The five maps a set may contain. Every one is optional on its own.
enum CyclesMap {
  /// sRGB. Multiplies the appearance's own colour, so a neutral grain map
  /// serves aluminium, brass and copper alike.
  base('basecolor'),

  /// Non-colour. Multiplies the appearance's roughness.
  roughness('roughness'),

  /// Non-colour. Multiplies the appearance's metallic.
  metallic('metallic'),

  /// Non-colour. A HEIGHT field, not a tangent-space normal map — see
  /// cycles_shim.h for why a box projection can use one and cannot use the
  /// other.
  height('height'),

  /// Non-colour. Multiplied into the base colour at half strength.
  occlusion('ao');

  const CyclesMap(this.fileName);
  final String fileName;
}

/// What one appearance's textures resolved to. Absolute paths, or null.
class CyclesTextureSet {
  const CyclesTextureSet({
    this.base,
    this.roughness,
    this.metallic,
    this.height,
    this.occlusion,
  });

  final String? base;
  final String? roughness;
  final String? metallic;
  final String? height;
  final String? occlusion;

  /// Nothing was found for this appearance, so it renders flat.
  bool get isEmpty =>
      base == null &&
      roughness == null &&
      metallic == null &&
      height == null &&
      occlusion == null;

  static const CyclesTextureSet none = CyclesTextureSet();

  @override
  bool operator ==(Object other) =>
      other is CyclesTextureSet &&
      other.base == base &&
      other.roughness == roughness &&
      other.metallic == metallic &&
      other.height == height &&
      other.occlusion == occlusion;

  @override
  int get hashCode => Object.hash(base, roughness, metallic, height, occlusion);
}

/// The render assets this install actually has.
///
/// Scanned ONCE, at launch, on the isolate that can do file I/O without
/// blocking a frame. A directory listing per render — and there are thirty a
/// second during an orbit — would be thirty syscalls for an answer that cannot
/// change while the app is running.
class CyclesAssets {
  CyclesAssets._();
  static final CyclesAssets instance = CyclesAssets._();

  String? _hdri;
  Map<String, CyclesTextureSet> _textures = const {};
  bool _scanned = false;

  /// The environment map, or null when this build has none.
  String? get hdri => _hdri;

  /// True once [scan] has run, whatever it found.
  bool get scanned => _scanned;

  /// The textures for appearance [id], never null and possibly empty.
  CyclesTextureSet texturesFor(String? id) =>
      _textures[id ?? _steelKey] ?? CyclesTextureSet.none;

  /// The key an unpainted body's textures are filed under.
  ///
  /// A real directory name, so a set can be supplied for plain steel — which
  /// is the commonest appearance in any assembly and therefore the one most
  /// worth texturing — without inventing a material id for it.
  static const String _steelKey = 'steel';

  /// Look for the assets under [root], the same directory the shim is given
  /// as its resource path. Safe to call more than once; the second call does
  /// nothing. Never throws.
  ///
  /// The root is PASSED IN rather than computed here, so this file imports
  /// nothing but dart:io and the log. Reaching for cycles_boot's answer would
  /// close a loop — boot to the FFI to the view to here and back to boot —
  /// for a string the one caller already has in a local.
  void scan(String? root, {List<String>? materialIds}) {
    if (_scanned) return;
    _scanned = true;
    if (root == null || root.isEmpty) return;
    final dir = '$root/$kCyclesAssetDir';
    try {
      if (!Directory(dir).existsSync()) {
        // Not a warning. This is the shape of every build made from a clean
        // clone, and the renderer is fully functional without it.
        Log.i('cycles', 'no render assets in this build ($dir)');
        return;
      }
      _hdri = _firstThatExists(
          '$dir/$kCyclesHdriDir/$kCyclesHdriName', kCyclesHdriExtensions);
      final ids = <String>[_steelKey, ...?materialIds];
      final found = <String, CyclesTextureSet>{};
      for (final id in ids) {
        final set = _scanSet('$dir/$kCyclesTextureDir/$id');
        if (!set.isEmpty) found[id] = set;
      }
      _textures = found;
      Log.i(
          'cycles',
          'render assets: hdri ${_hdri == null ? 'none' : 'yes'}, '
              '${found.length} texture set${found.length == 1 ? '' : 's'}');
    } catch (e) {
      // A missing or unreadable asset directory costs texture detail and
      // nothing else. It must not cost the launch.
      Log.w('cycles', 'could not scan the render assets: $e');
    }
  }

  CyclesTextureSet _scanSet(String dir) {
    String? at(CyclesMap m) =>
        _firstThatExists('$dir/${m.fileName}', kCyclesTextureExtensions);
    return CyclesTextureSet(
      base: at(CyclesMap.base),
      roughness: at(CyclesMap.roughness),
      metallic: at(CyclesMap.metallic),
      height: at(CyclesMap.height),
      occlusion: at(CyclesMap.occlusion),
    );
  }

  String? _firstThatExists(String stem, List<String> extensions) {
    for (final ext in extensions) {
      final p = '$stem.$ext';
      if (File(p).existsSync()) return p;
    }
    return null;
  }

  /// For tests, which must not inherit another case's answer.
  void resetForTest({String? hdri, Map<String, CyclesTextureSet>? textures}) {
    _scanned = hdri != null || textures != null;
    _hdri = hdri;
    _textures = textures ?? const {};
  }
}
