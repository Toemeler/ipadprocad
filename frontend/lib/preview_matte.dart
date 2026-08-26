// M269 — taking the palette back out of a gallery still.
//
// A card in the gallery paints its own surface (T.galleryThumb) and draws the
// document's preview PNG over it. That only works if the PNG carries the PART
// and nothing else: the moment a still has a ground baked into it, it is a
// picture of one colour scheme, and it stays that picture after the scheme
// changes, after the app is relaunched, forever. One cream card among nine
// charcoal ones is exactly what that looks like.
//
// M237 asked for a transparent ground and the app has requested one ever
// since. The request is not always honoured: the off-screen RealityKit
// renderer is a real ARView in the real window, and a viewport-colour push
// that lands during the two-to-eight frames it takes to capture repaints it
// opaque underneath the capture (fixed at the source in RealityPartView, but
// a still already on disk is already wrong, and a renderer that ignores an
// alpha it does not like would put us straight back here).
//
// So the app stops TRUSTING the ground and starts CHECKING it. These two
// functions are the check and the repair, and they are pure — raw RGBA in,
// raw RGBA out — so the whole thing is testable on the host without an image
// codec, a device or a colour scheme.
//
// WHY A FLOOD FILL AND NOT "REPLACE EVERY PIXEL OF THAT COLOUR". The ground is
// a flat colour, and a flat grey is also a perfectly ordinary colour for a
// shaded face to be. Keying globally would punch holes through the middle of
// the part. Filling inward from the border only ever clears what is CONNECTED
// to the outside, which is the actual definition of "the background".
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'log.dart';

/// How far a pixel may drift from the ground and still count as ground.
///
/// Per channel, out of 255. Generous on purpose: RealityKit's own capture is
/// not bit-exact across frames (MSAA resolve, sRGB round-trip), and the cost
/// of being generous is that the outermost antialiased pixel of the silhouette
/// goes with the ground — a silhouette one pixel leaner. The cost of being
/// strict is a bright halo tracing the part on a dark card, which is the more
/// visible of the two by a wide margin.
const int kGroundTolerance = 24;

/// The flat opaque ground [rgba] was rendered on, as 0xRRGGBB — or null when
/// there is nothing to repair.
///
/// Null means one of two things, and neither is a problem: the still already
/// has the transparent ground the app asks for, or its border is not one flat
/// colour at all (a part drawn edge to edge), in which case there is no ground
/// to identify and guessing at one would eat the drawing.
int? detectGround(Uint8List rgba, int w, int h) {
  if (w < 3 || h < 3 || rgba.length < w * h * 4) return null;
  final counts = <int, int>{};
  var opaque = 0, total = 0;
  void sample(int x, int y) {
    final i = (y * w + x) * 4;
    total++;
    if (rgba[i + 3] < 250) return;
    opaque++;
    final key = (rgba[i] << 16) | (rgba[i + 1] << 8) | rgba[i + 2];
    counts[key] = (counts[key] ?? 0) + 1;
  }

  for (var x = 0; x < w; x++) {
    sample(x, 0);
    sample(x, h - 1);
  }
  for (var y = 1; y < h - 1; y++) {
    sample(0, y);
    sample(w - 1, y);
  }
  // A few opaque pixels on the border are a part that runs off the edge, not a
  // ground. A ground is the border.
  if (opaque * 10 < total * 8) return null;

  var best = 0, bestN = 0;
  for (final e in counts.entries) {
    if (e.value > bestN) {
      bestN = e.value;
      best = e.key;
    }
  }
  // ...and it has to actually be FLAT. A gradient produces a thousand colours
  // with a handful of pixels each, and clearing "the commonest of them" would
  // leave the rest behind as a torn fringe.
  //
  // A clear MAJORITY rather than near-unanimity, because a part is allowed to
  // run off the edge of its own thumbnail: a body that leaves the frame down
  // the right-hand side takes a third of the border with it and the ground is
  // still plainly the ground. Below a majority there is no ground to speak of,
  // and the commonest border colour is as likely to be the drawing.
  var near = 0;
  for (final e in counts.entries) {
    if (_close(e.key, best, kGroundTolerance)) near += e.value;
  }
  if (near * 5 < opaque * 3) return null;
  return best;
}

/// Clears every pixel CONNECTED TO THE BORDER that matches [ground] to fully
/// transparent, in place. Returns how many pixels went.
///
/// Four-connected, deliberately: an eight-connected fill leaks through the
/// single-pixel diagonal gaps antialiasing leaves along a near-45° edge, and
/// what leaks through is the inside of the part.
int keyOutGround(Uint8List rgba, int w, int h, int ground,
    {int tolerance = kGroundTolerance}) {
  if (w <= 0 || h <= 0 || rgba.length < w * h * 4) return 0;
  final seen = Uint8List(w * h);
  // An explicit stack rather than recursion: a 380x240 still is 91 200 pixels
  // and a near-empty one would recurse most of that deep.
  final stack = <int>[];
  void push(int x, int y) {
    if (x < 0 || y < 0 || x >= w || y >= h) return;
    final p = y * w + x;
    if (seen[p] != 0) return;
    seen[p] = 1;
    final i = p * 4;
    if (rgba[i + 3] < 250) return; // already transparent — nothing to clear
    final c = (rgba[i] << 16) | (rgba[i + 1] << 8) | rgba[i + 2];
    if (!_close(c, ground, tolerance)) return;
    stack.add(p);
  }

  for (var x = 0; x < w; x++) {
    push(x, 0);
    push(x, h - 1);
  }
  for (var y = 0; y < h; y++) {
    push(0, y);
    push(w - 1, y);
  }
  var cleared = 0;
  while (stack.isNotEmpty) {
    final p = stack.removeLast();
    final i = p * 4;
    // All four bytes, not just alpha. dart:ui hands out PREMULTIPLIED RGBA, in
    // which a transparent pixel's colour channels are zero; leaving the old
    // colour behind with alpha 0 is a valid straight-alpha pixel and a
    // malformed premultiplied one, and some encoders keep the colour.
    rgba[i] = 0;
    rgba[i + 1] = 0;
    rgba[i + 2] = 0;
    rgba[i + 3] = 0;
    cleared++;
    final x = p % w, y = p ~/ w;
    push(x - 1, y);
    push(x + 1, y);
    push(x, y - 1);
    push(x, y + 1);
  }
  return cleared;
}

bool _close(int a, int b, int tol) =>
    ((a >> 16 & 0xFF) - (b >> 16 & 0xFF)).abs() <= tol &&
    ((a >> 8 & 0xFF) - (b >> 8 & 0xFF)).abs() <= tol &&
    ((a & 0xFF) - (b & 0xFF)).abs() <= tol;

/// Re-encodes [png] with a baked-in flat ground removed, or null when there
/// was nothing to remove.
///
/// The seam between the pure matte above and the image codec. Null covers both
/// "already transparent" and "could not tell", and both mean the same thing to
/// every caller: keep the bytes you have.
Future<Uint8List?> demattePng(Uint8List png) async {
  ui.Image? decoded;
  try {
    final codec = await ui.instantiateImageCodec(png);
    final frame = await codec.getNextFrame();
    decoded = frame.image;
    final w = decoded.width, h = decoded.height;
    final data = await decoded.toByteData(format: ui.ImageByteFormat.rawRgba);
    codec.dispose();
    if (data == null) return null;
    final rgba = data.buffer.asUint8List();
    final ground = detectGround(rgba, w, h);
    if (ground == null) return null;
    if (keyOutGround(rgba, w, h, ground) == 0) return null;
    Log.i('doc',
        'preview ground 0x${ground.toRadixString(16).padLeft(6, '0')} keyed out');
    final buf = await ui.ImmutableBuffer.fromUint8List(rgba);
    final desc = ui.ImageDescriptor.raw(buf,
        width: w, height: h, pixelFormat: ui.PixelFormat.rgba8888);
    final out = await desc.instantiateCodec();
    final f2 = await out.getNextFrame();
    final bytes = await f2.image.toByteData(format: ui.ImageByteFormat.png);
    f2.image.dispose();
    out.dispose();
    desc.dispose();
    buf.dispose();
    return bytes?.buffer.asUint8List();
  } catch (e) {
    Log.w('doc', 'preview de-matte failed: $e');
    return null;
  } finally {
    decoded?.dispose();
  }
}
