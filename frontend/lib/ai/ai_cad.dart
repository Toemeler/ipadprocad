import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../app_state.dart';
import '../ffi/occt_engine.dart' show OcctEdgeInfo, OcctMeshData;
import '../ffi/qcad_engine.dart';
import '../constraints.dart';
import '../log.dart';
import '../gear.dart' show GearParams, buildGearGeo;
import '../inserts.dart' show SketchText;
import '../modify.dart'
    show
        arcThrough,
        stretchGeo,
        extendEntity,
        offsetEntity,
        transformGeo,
        trimCutAway,
        trimEntity;
import '../part_model.dart';
import '../snap.dart' show sampleEntity;
import '../solver.dart' show hasDegenerateGeometry;
import '../tools.dart'
    show
        buildToolGeometry,
        chamferInventor,
        filletInventor,
        kSketchPointRadius,
        toolMeta;
import '../part_render.dart'
    show Cam3, kFacePlane, kFaceCylinder, kFaceCone, kFaceSphere, kFaceTorus;
import 'ai_actions.dart';
import 'ai_knowledge.dart';
import 'ai_brief.dart';
import 'ai_models.dart';
import 'ai_trace.dart';
import 'ai_expr.dart';
import 'ai_view.dart';
import 'ai_view_marks.dart';
import 'mesh_topology.dart';
import 'printability.dart';
import 'shape_digest.dart';

part 'ai_cad_solids.dart';
part 'ai_cad_sketch.dart';
part 'ai_cad_constrain.dart';
part 'ai_cad_path.dart';
part 'ai_cad_enclose.dart';

/// Four decimals is a micron on a millimetre part — past what any of this
/// geometry is accurate to, and short enough that a report stays readable.
double _r(double v) => v.isFinite ? (v * 10000).roundToDouble() / 10000 : 0;

/// A length as the reports print it.
String _mm(double v) =>
    v.isFinite ? v.toStringAsFixed(v.abs() >= 100 ? 1 : 2) : '?';

/// M441 — where an assistant's intention becomes geometry.
///
/// Everything this file builds is an ORDINARY document object: a `ChildSketch`
/// with real entities on a real layer, an `ExtrudeFeature`/`RevolveFeature`/
/// `FilletFeature`/`ChamferFeature` in the same timeline, rebuilt through the
/// same `recomputeAllFeatures`. There is no agent-only representation and no
/// path around the kernel. The consequence is the point: what the model makes,
/// the user can open, edit, re-dimension, roll back and delete, and what the
/// user made, the model can edit.
///
/// THREE RULES THIS FILE EXISTS TO ENFORCE.
///
/// 1. **A block is one transaction.** The part is snapshotted before the first
///    action. If any action fails, the snapshot goes back and the report says
///    `reverted`. A half-applied design change is worse than none: the model
///    would reason about a document that does not exist.
/// 2. **A refusal is not a failure to mention.** Every outcome carries either
///    what it did (with the numbers) or why it did not. Nothing is silently
///    skipped, because the model's next answer is written from this report.
/// 3. **The report is measured, not assumed.** Distances come back from the
///    feature that was actually built and bounds from the rebuilt body — never
///    from the arguments that were asked for. An extrusion that failed in the
///    kernel reports its `computeError`, not the distance that was requested.
class AiCad {
  AiCad(this.app, [ShapeDigestCache? digests])
      : digests = digests ?? ShapeDigestCache();
  final AppState app;

  /// Shared with [AiWorkspace] so the digest in the turn's context and the one
  /// an op reads are the same object, computed once.
  final ShapeDigestCache digests;

  /// Views rendered by `look` during the current block.
  final List<AiAttachment> _views = [];

  /// #89 — the faces the last labelled view named, largest first, as the
  /// report prints them ("F12 -X (Extrusion1)"), and whether the picture
  /// itself carries the labels or only this list does.
  List<String> _seen = const [];
  bool _seenDrawn = false;

  /// The same, for the view the app took itself after the block — never a
  /// `look` from earlier in the block, which showed the part before it changed.
  List<String> _autoSeen = const [];
  bool _autoDrawn = false;

  /// Whether the model on the other end can actually receive a picture.
  ///
  /// Set by [AiWorkspace] from the live provider capabilities. It only decides
  /// whether the PNG is worth rendering — the text silhouette costs nothing to
  /// produce and goes to every provider either way.
  bool wantsImages = true;

  /// The bundled reference corpus, for the `knowledge` op. Set by
  /// [AiWorkspace] once it is loaded; null until then, and the op says so
  /// rather than pretending the shelf is empty (#82).
  AiKnowledge? knowledge;

  /// ISSUE #83 — WATCHING THE ASSISTANT UNBUILD ITS OWN WORK.
  ///
  /// The instructions already say it: "delete_feature is for a feature that
  /// should not exist at all — a wrong approach, not a wrong number", and "if
  /// you find yourself rebuilding what you just built, stop". In the reported
  /// session the model built a wall flange, looked at it, deleted it, and
  /// built another — four times, Extrusion4 through Extrusion7 — and called
  /// edit_feature exactly zero times. Every cycle was a provider round trip.
  ///
  /// A paragraph in the prompt is not a grip. Noticing is: the app knows which
  /// features this conversation created and when, so when one of them is
  /// deleted a few blocks later it can say so, with the count, in the report
  /// the model reads before writing its next block. That is the same mechanism
  /// the open-requirements push-back already uses, applied to the other way a
  /// turn goes in circles.
  int _blockNo = 0;
  final Map<String, int> _madeAt = {};

  /// The blocks at which this conversation deleted something it had just
  /// built. A LIST rather than a counter, so the escalation is scoped to a
  /// run of rebuilding and not to the whole life of the app: three deletions
  /// spread over an afternoon's work are three considered removals, and only
  /// three inside a handful of blocks are a loop.
  final List<int> _churnAt = [];

  /// ISSUE #82 — LOOK AFTER EVERY STEP, WITHOUT BEING ASKED.
  ///
  /// The instructions told the model to run `look` before calling a part
  /// finished. It called it ZERO times in the reported session, and so never
  /// saw that its countersink had landed on the plate's edge, that its cable
  /// clamp was hanging in mid-air, or that the part it finally handed over was
  /// a bare slab. It had a vision model on the other end the whole time.
  ///
  /// Asking the model to remember is the wrong mechanism. A view is only
  /// useful if it arrives with the report it describes, and the app already
  /// knows the exact moment one is worth taking: a block just changed the
  /// geometry. So the app takes it. No round trip, no op to remember, no
  /// judgement call about whether this step deserves one.
  ///
  /// It is also the cheapest possible correction loop. The whole point of
  /// building rather than deliberating is that the result comes back as fact
  /// — and for shape, the fact is a picture.
  Future<void> _autoView(PartModel p) async {
    // The model asked for its own view in this block: that is the one it
    // wanted, framed how it wanted. Don't second-guess it or double the cost.
    if (_views.isNotEmpty) return;
    if (p.bodyNames.isEmpty) return;
    const az = 45.0, pol = 55.0, size = 512;
    _autoSeen = const [];
    _autoDrawn = false;
    try {
      final png = wantsImages
          ? await app.aiRenderView(
              azRad: az * math.pi / 180,
              polRad: pol * math.pi / 180,
              rollRad: 0,
              width: size,
              height: size,
              annotate: _labeller(p, const AiAction('look', {})),
            )
          : null;
      if (png != null && png.isNotEmpty) {
        _views.add(AiAttachment.fromBytes(name: 'after-block.png', bytes: png));
        _autoSeen = _seen;
        _autoDrawn = _seenDrawn;
      }
    } on AiException {
      // A view is an extra, never a reason for a good block to report badly.
    } catch (_) {}
  }

  /// The same view as a grid of characters, for the report text. Free, and the
  /// only thing a text-only provider can read (#82).
  String? _autoSilhouette(PartModel p) {
    if (p.bodyNames.isEmpty) return null;
    try {
      final solid = _solidFor(p, const AiAction('look', {}));
      if (solid == null) return null;
      final view = renderTextView(solid.mesh.positions, solid.mesh.indices,
          azRad: 45 * math.pi / 180, polRad: 55 * math.pi / 180);
      return view?.toText();
    } catch (_) {
      return null;
    }
  }

  /// Executes one block. Never throws: an unexpected error becomes a failed
  /// outcome and a rollback, because an exception escaping here would leave
  /// the document mid-edit with nobody to say so.
  Future<AiActionReport> run(List<AiAction> given,
      {AiProgress? onStep}) async {
    final p = app.currentPart;
    if (p == null) {
      AiTrace.record('cad.blocked', data: {'blocked': 'noPart'});
      return AiActionReport(outcomes: const [], blocked: 'noPart');
    }
    if (given.isEmpty) return AiActionReport(outcomes: const []);
    final batch = deletesLastFirst(p, given);
    final before = app.aiSnapshot(p);
    _blockNo++;
    _views.clear();
    _autoSeen = const [];
    _autoDrawn = false;
    final outcomes = <AiActionOutcome>[];
    var mutated = false;
    var failed = false;
    // PARTIAL COMMIT. The last point in this block where the document was
    // whole — every feature in it built, no sketch drawn for a step that did
    // not happen yet — and how many outcomes lead up to it. See
    // [AiActionReport.kept].
    PartSnap? lastGood;
    var kept = 0;
    for (var i = 0; i < batch.length; i++) {
      final raw = batch[i];
      // Reported BEFORE the action runs, so the panel names what is happening
      // rather than what just finished.
      onStep?.call(raw.op, i + 1, batch.length);
      AiActionOutcome outcome;
      var action = raw;
      // PER OP, WITH ITS OWN CLOCK. The block report says what a block did;
      // this says which op inside it was the slow one and which one turned a
      // batch into a rollback. A fillet that takes eleven seconds in the
      // kernel and an extrude that fails on a profile look identical in the
      // report the model is handed.
      final clock = Stopwatch()..start();
      try {
        // Arithmetic and anchors are resolved against the document AS IT IS
        // NOW, one action at a time, so `sk.cx` on the third action of a
        // block sees the body the second action built.
        final (resolved, why) = _resolve(p, raw);
        if (resolved == null) {
          outcome = AiActionOutcome.failed(raw.op, why!);
        } else {
          action = resolved;
          outcome = await _one(p, action);
        }
      } catch (e, st) {
        Log.e('ai', 'action ${action.op} threw', e, st);
        AiTrace.record('cad.threw', data: {
          'op': action.op,
          'args': action.args,
          'error': '${e.runtimeType}: $e',
          'stack': '$st',
          'elapsedMs': clock.elapsedMilliseconds,
        });
        outcome = AiActionOutcome.failed(action.op, 'internal error: $e');
      }
      AiTrace.record('cad.action', data: {
        'op': action.op,
        'ok': outcome.ok,
        'elapsedMs': clock.elapsedMilliseconds,
        'args': action.args,
        if (outcome.error != null) 'error': outcome.error,
        if (outcome.detail != null) 'detail': outcome.detail,
      });
      outcomes.add(outcome);
      if (!kAiReadOnlyOps.contains(action.op) &&
          !kAiBriefOps.contains(action.op)) {
        mutated = true;
      }
      if (!outcome.ok) {
        failed = true;
        break;
      }
      if (kAiCommitOps.contains(action.op)) {
        kept = outcomes.length;
        // Only worth a snapshot if something could still fail after it.
        lastGood = i < batch.length - 1 ? app.aiSnapshot(p) : null;
      }
    }
    if (failed && mutated) {
      final partial = kept > 0 && lastGood != null;
      await app.aiRestore(p, partial ? lastGood : before);
      // The restore swaps whole sketches in; a cached region list keyed by a
      // sketch NAME would otherwise survive the sketch it describes.
      app.aiForgetRegions();
      Log.i(
          'ai',
          partial
              ? 'action block failed at step ${outcomes.length}; kept '
                  'steps 1-$kept'
              : 'action block rolled back after ${outcomes.length} step(s)');
      AiTrace.record('cad.reverted', data: {
        'steps': outcomes.length,
        'kept': partial ? kept : 0,
        'failedOn': outcomes.isEmpty ? null : outcomes.last.op,
        'error': outcomes.isEmpty ? null : outcomes.last.error,
      });
      if (partial) {
        app.aiJournal(before); // one Ctrl+Z still undoes what the block kept
        p.dirty = true;
        final tab = app.curTab;
        if (tab != null) await app.savePart(tab);
        app.aiNotify();
        await _autoView(p);
      }
      final state = _stateBrief(p);
      if (partial) _attachView(p, state);
      return AiActionReport(
          outcomes: outcomes,
          reverted: true,
          kept: partial ? kept : 0,
          state: state,
          problems: partial ? _problems(p) : const [],
          images: List.of(_views));
    }
    if (mutated && !failed) {
      app.aiJournal(before); // ONE Ctrl+Z for the whole block
      p.dirty = true;
      final tab = app.curTab;
      if (tab != null) await app.savePart(tab);
      app.aiNotify();
      // #82 — the geometry changed, so the model gets to see it.
      await _autoView(p);
    }
    final state = _stateBrief(p);
    if (mutated && !failed) _attachView(p, state);
    return AiActionReport(
        outcomes: outcomes,
        reverted: false,
        state: state,
        problems: mutated ? _problems(p) : const [],
        images: List.of(_views));
  }

  /// The text view and the note that goes with the rendered one.
  void _attachView(PartModel p, Map<String, dynamic> state) {
    final sil = _autoSilhouette(p);
    if (sil != null) state['silhouette'] = sil;
    if (_views.isNotEmpty && _autoSeen.isNotEmpty) {
      state['facesInView'] = _autoSeen.join(' · ');
    }
    state['viewNote'] = _views.isEmpty
        ? 'This is the part after the block, seen from az 45, pol 55. '
            "'#' is material, 'o' is an opening you can see straight "
            'through. Check it against what you meant to build.'
        : 'The attached image and the silhouette are this part AFTER the '
            'block, from az 45, pol 55. Look at them: if the shape is not '
            'what you intended, fix it in the next block rather than '
            'carrying on.${_autoDrawn ? " $_kLabelNote" : ""}';
  }

  static const _kLabelNote = 'The yellow labels on the picture are face ids — '
      'the same F-numbers faces_where returns, with the direction each face '
      'looks — and the triad shows X, Y (up) and Z. Read which face is which '
      'off the labels; read every size from the numbers, never off this '
      'image.';

  String _seenLine() => _seen.join(' · ');

  /// #89 — draws face ids and an axis triad onto a view, through the camera
  /// it was rendered with, and remembers which faces it named for the report.
  /// The body labelled is the one faces_where answers about by default, so a
  /// label and a faces_where row always mean the same face.
  Future<Uint8List?> Function(Uint8List, Cam3) _labeller(
      PartModel p, AiAction a) {
    _seen = const [];
    _seenDrawn = false;
    return (png, cam) async {
      final d = _digestOf(p, a);
      final solid = d == null ? null : currentBodySolid(p, d.body);
      if (d == null || solid == null) return null;
      final others = [
        for (final name in p.bodyNames)
          if (name != d.body) currentBodySolid(p, name)
      ];
      final marks = faceMarks(solid.mesh, cam, occluders: [
        for (final o in others)
          if (o != null) o.mesh
      ]);
      if (marks.isEmpty) return null;
      final maker = attributeFaces(p, d.body, solid);
      _seen = [
        for (final m in marks)
          maker[m.face] == null ? m.text : '${m.text} (${maker[m.face]})'
      ];
      final drawn = await drawFaceMarks(png, cam, marks);
      _seenDrawn = drawn != null;
      return drawn;
    };
  }

  // ---- arithmetic, named numbers and anchors -----------------------------

  /// Named numbers per part, from the `vars` op and a block's "vars". They
  /// outlive the block, so a later block can say "wall" instead of retyping
  /// 2.4 and getting it wrong once.
  final Map<String, Map<String, double>> _vars = {};

  static const int _kMaxVars = 64;

  /// Arguments whose STRING value is a name or a word, never arithmetic —
  /// "F3" and "Extrusion1" contain digits and would otherwise be read as
  /// sums. Lists under these keys are walked normally, so
  /// `{"to": ["r*cos(30)", 0]}` in a path is still evaluated.
  static const Set<String> _textKeys = {
    'sketch', 'feature', 'name', 'text', 'source', 'body', 'id', 'expr',
    'plane', 'edges', 'operation', 'direction', 'type', 'kind', 'where',
    'axis', 'method', 'mode', 'tool', 'action', 'orientation', 'face',
    'from', 'to', 'detail', 'profile_sketch', 'path_sketch', 'on', 'regions',
    'title', 'say', 'open',
  };

  /// Arguments whose list elements are names: pattern's features, loft's
  /// sketches, combine's tools, a shell's open faces.
  static const Set<String> _nameListKeys = {
    'features', 'sketches', 'tools', 'bodies', 'faces', 'open_faces',
  };

  /// [a] with every arithmetic argument evaluated, or why one would not.
  (AiAction?, String?) _resolve(PartModel p, AiAction a) {
    // `vars` evaluates its own values in order, so a later one can use an
    // earlier one — it is resolved by the op, not here.
    if (a.op == 'vars') return (a, null);
    final lookup = _lookupFor(p, a);
    bool known(String n) {
      try {
        return lookup(n) != null;
      } catch (_) {
        return false;
      }
    }

    String? error;
    Object? walk(String key, Object? v, {bool names = false}) {
      if (error != null) return v;
      if (v is String) {
        if (names) return v;
        if (!aiLooksLikeExpression(v, isName: known)) return v;
        try {
          return aiEvalExpression(v, lookup);
        } on AiExprError catch (e) {
          error = '"$key": ${e.message}';
          return v;
        }
      }
      if (v is List) {
        return [
          for (final e in v) walk(key, e, names: _nameListKeys.contains(key))
        ];
      }
      if (v is Map) {
        return {
          for (final e in v.entries)
            '${e.key}': _textKeys.contains('${e.key}') && e.value is String
                ? e.value
                : walk('${e.key}', e.value)
        };
      }
      return v;
    }

    final args = <String, dynamic>{
      for (final e in a.args.entries)
        e.key: _textKeys.contains(e.key) && e.value is String
            ? e.value
            : walk(e.key, e.value)
    };
    if (error != null) return (null, 'could not evaluate $error');
    return (AiAction(a.op, args), null);
  }

  /// Names an expression can use in [a]: the part's own `vars`, then the
  /// anchors — `part.*` in world millimetres and `sk.*` in the coordinates
  /// of the sketch [a] draws on — computed only when asked for.
  AiExprLookup _lookupFor(PartModel p, AiAction a) {
    final vars = _vars[p.name] ?? const <String, double>{};
    Map<String, double>? partVals, skVals;
    return (name) {
      final v = vars[name];
      if (v != null) return v;
      if (name.startsWith('part.')) {
        partVals ??= _partAnchors(p);
        return partVals![name.substring(5)];
      }
      if (name.startsWith('sk.')) {
        skVals ??= _sketchAnchors(p, a);
        return skVals![name.substring(3)];
      }
      return null;
    };
  }

  /// The world box of the part's SOLIDS — never of its sketches.
  ///
  /// `partContentBounds` is the viewport's box and includes every visible
  /// sketch, which is right for framing a camera and wrong for placing a
  /// feature: an unconsumed construction sketch off to one side moved the
  /// "centre" the #82 report line gave the model. Placement is about
  /// material, so this is.
  (Vec3, Vec3)? _solidBounds(PartModel p) {
    var lo = const Vec3(double.infinity, double.infinity, double.infinity);
    var hi = const Vec3(
        double.negativeInfinity, double.negativeInfinity, double.negativeInfinity);
    var any = false;
    for (final (name, _) in p.solidBodies()) {
      final solid = currentBodySolid(p, name);
      if (solid == null) continue;
      // #89 — the SAME box describe_shape prints. Every block's report and
      // the part.* anchors read the mesh, and a degenerate chamfer left mesh
      // vertices far outside the body: the report said x -52.99..224.07 and
      // "put a centred feature at x=85.54" while describe_shape said
      // x 0..50, centre 25. The model was handed both and trusted neither.
      final bb = solid.shape?.bbox();
      if (bb != null && bb.length == 6 && bb.every((v) => v.isFinite)) {
        any = true;
        lo = Vec3(math.min(lo.x, bb[0]), math.min(lo.y, bb[1]), math.min(lo.z, bb[2]));
        hi = Vec3(math.max(hi.x, bb[3]), math.max(hi.y, bb[4]), math.max(hi.z, bb[5]));
        continue;
      }
      final pos = solid.mesh.positions;
      for (var i = 0; i + 2 < pos.length; i += 3) {
        final x = pos[i], y = pos[i + 1], z = pos[i + 2];
        if (!x.isFinite || !y.isFinite || !z.isFinite) continue;
        any = true;
        lo = Vec3(math.min(lo.x, x), math.min(lo.y, y), math.min(lo.z, z));
        hi = Vec3(math.max(hi.x, x), math.max(hi.y, y), math.max(hi.z, z));
      }
    }
    return any ? (lo, hi) : null;
  }

  Map<String, double> _partAnchors(PartModel p) {
    final b = _solidBounds(p);
    if (b == null) return const {};
    final (lo, hi) = b;
    return {
      'xmin': lo.x, 'xmax': hi.x, 'ymin': lo.y, 'ymax': hi.y, //
      'zmin': lo.z, 'zmax': hi.z,
      'cx': (lo.x + hi.x) / 2, 'cy': (lo.y + hi.y) / 2, 'cz': (lo.z + hi.z) / 2,
      'w': hi.x - lo.x, 'h': hi.y - lo.y, 'd': hi.z - lo.z,
    };
  }

  /// The part's box as seen IN the sketch [a] draws on: left, right, bottom,
  /// top, cx, cy, w, h in that sketch's own x/y.
  ///
  /// This is the anchor that retires the frame table. On XZ, sketch +y is
  /// world −Z, and a model that knew the part ran from z = −22 to 0 still had
  /// to flip a sign to find its middle — and got it wrong on the block after
  /// the first one, twice in #82. `sk.cx, sk.cy` is the middle, on whatever
  /// plane or face the sketch sits, with the sign already applied.
  Map<String, double> _sketchAnchors(PartModel p, AiAction a) {
    final b = _solidBounds(p);
    final named = a.text('sketch');
    final cs = named != null
        ? p.sketchByName(named)
        : (p.childSketches.isEmpty ? null : p.childSketches.last);
    if (b == null || cs == null) return const {};
    final f = sketchFrameOf(cs);
    final (lo, hi) = b;
    var u0 = double.infinity, u1 = double.negativeInfinity;
    var v0 = double.infinity, v1 = double.negativeInfinity;
    for (final x in [lo.x, hi.x]) {
      for (final y in [lo.y, hi.y]) {
        for (final z in [lo.z, hi.z]) {
          final q = f.toSketch(Vec3(x, y, z));
          u0 = math.min(u0, q.dx);
          u1 = math.max(u1, q.dx);
          v0 = math.min(v0, q.dy);
          v1 = math.max(v1, q.dy);
        }
      }
    }
    return {
      'left': u0, 'right': u1, 'bottom': v0, 'top': v1, //
      'cx': (u0 + u1) / 2, 'cy': (v0 + v1) / 2, 'w': u1 - u0, 'h': v1 - v0,
    };
  }

  /// Defines named numbers for this part. All or nothing: a block whose
  /// third name does not evaluate leaves the first two undefined too.
  AiActionOutcome _defineVars(PartModel p, AiAction a) {
    final store = _vars.putIfAbsent(p.name, () => {});
    final staged = Map<String, double>.of(store);
    final lookupBase = _lookupFor(p, a);
    double? lookup(String n) => staged[n] ?? lookupBase(n);
    final defined = <String, double>{};
    for (final e in a.args.entries) {
      final name = e.key;
      if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,31}$').hasMatch(name) ||
          name == 'pi' ||
          kAiExprFunctions.contains(name)) {
        return AiActionOutcome.failed(a.op,
            '"$name" is not a usable name — letters, digits and _, starting '
            'with a letter, and not pi or a function name');
      }
      final raw = e.value;
      double value;
      if (raw is num && raw.isFinite) {
        value = raw.toDouble();
      } else if (raw is String) {
        try {
          value = aiEvalExpression(raw, lookup);
        } on AiExprError catch (err) {
          return AiActionOutcome.failed(a.op, '"$name": ${err.message}');
        }
      } else {
        return AiActionOutcome.failed(
            a.op, '"$name" must be a number or an expression');
      }
      staged[name] = value;
      defined[name] = value;
    }
    if (staged.length > _kMaxVars) {
      return AiActionOutcome.failed(
          a.op, 'at most $_kMaxVars named numbers per part');
    }
    store
      ..clear()
      ..addAll(staged);
    return AiActionOutcome(a.op, detail: {
      'defined': {for (final e in defined.entries) e.key: _r(e.value)},
      'known': store.length,
    });
  }

  // ---- design rules: what is wrong with the part, measured --------------

  /// Facts about the finished block that mean the part is not done.
  ///
  /// Kept to what the app can MEASURE and what is wrong in every design, so
  /// a check can hold back a "Fertig" without second-guessing intent: a body
  /// in pieces, and a feature that does not build.
  List<String> _problems(PartModel p) {
    final out = <String>[];
    for (final (name, _) in p.solidBodies()) {
      final solid = currentBodySolid(p, name);
      if (solid == null) continue;
      final pieces = meshComponentCount(solid.mesh);
      if (pieces > 1) {
        out.add('Body "$name" is $pieces separate pieces of material, not '
            'one. Something is floating or was cut free — join it to the '
            'rest, or delete the stray piece.');
      }
    }
    for (final f in p.features) {
      if (f.rolledBack || f.computeError == null) continue;
      out.add('${f.typeLabel} "${f.name}" does not build: ${f.computeError}');
    }
    // #87 — "it is not fdm printable". Only for a part that is meant to be
    // printed: an overhang is a fault in FDM and a non-issue for a turned or
    // cast part, and saying it about every part would teach the model to
    // skim this list.
    if (_fdmIntended()) {
      for (final (name, _) in p.solidBodies()) {
        final solid = currentBodySolid(p, name);
        if (solid == null) continue;
        for (final line in overhangReport(solid.mesh,
            body: p.solidBodies().length > 1 ? name : '')) {
          out.add('Not printable without support: $line. Reshape it so '
              'every downward face rises at least 30° from horizontal (a '
              'sloped underside instead of a flat one, a pointed top on a '
              'horizontal hole), or make it a bridge held up on both sides. '
              '(Judged standing as modelled, on its lowest face — if it will '
              'be printed another way up, say which in one sentence.)');
        }
      }
    }
    return out;
  }

  /// Whether this part is meant for a filament printer: said in a recorded
  /// requirement, or in what the user wrote in this conversation.
  bool _fdmIntended() {
    final fdm = RegExp(
        r'\b(fdm|fff|3d[ -]?(print|druck)|filament|druckbar|printable|'
        r'gedruckt|drucken|printed|pla|petg)\b',
        caseSensitive: false);
    try {
      final ai = app.ai;
      for (final r in ai.briefs.of(ai.document.id)) {
        if (fdm.hasMatch(r.text) || fdm.hasMatch(r.source ?? '')) return true;
      }
      for (final m in ai.currentSession.messages) {
        if (m.role == 'user' && fdm.hasMatch(m.text)) return true;
      }
    } catch (_) {}
    return false;
  }

  Future<AiActionOutcome> _one(PartModel p, AiAction a) async {
    switch (a.op) {
      case 'sketch_tool':
        return this._sketchTool(p, a);
      case 'sketch_modify':
        return this._sketchModify(p, a);
      case 'sketch_project':
        return this._sketchProject(p, a);
      case 'sketch_pattern':
        return this._sketchPattern(p, a);
      case 'sketch_gear':
        return this._sketchGear(p, a);
      case 'sketch_text':
        return this._sketchText(p, a);
      case 'sketch_constrain':
        return this._sketchConstrain(p, a);
      case 'sketch_dimension':
        return this._sketchDimension(p, a);
      case 'hole':
        return this._hole(p, a);
      case 'sweep':
        return this._sweep(p, a);
      case 'loft':
        return this._loft(p, a);
      case 'coil':
        return this._coil(p, a);
      case 'split_body':
        return this._split(p, a);
      case 'combine':
        return this._combine(p, a);
      case 'pattern':
        return this._pattern(p, a);
      case 'shell':
        return this._shell(p, a);
      case 'enclose':
        return this._enclose(p, a);
      case 'describe_part':
        return AiActionOutcome('describe_part', detail: {'part': _state(p)});
      case 'describe_shape':
        return _describeShape(p, a);
      case 'faces_where':
        return _facesWhere(p, a);
      case 'measure':
        return _measure(p, a);
      case 'section':
        return _section(p, a);
      case 'delete_face':
      case 'move_face':
      case 'size_face':
      case 'scale_body':
        return _faceEdit(p, a);
      case 'sketch_on_face':
        return _sketchOnFace(p, a);
      case 'look':
        return _look(p, a);
      case 'knowledge':
        return _knowledge(a);
      case 'brief_note':
      case 'brief_done':
        return _brief(a);
      case 'vars':
        return _defineVars(p, a);
      case 'create_sketch':
        return _createSketch(p, a);
      case 'sketch_rect':
      case 'sketch_circle':
      case 'sketch_polygon':
      case 'sketch_line':
      case 'sketch_arc':
      case 'sketch_slot':
      case 'sketch_rounded_rect':
      case 'sketch_point':
      case 'sketch_path':
      case 'sketch_ring':
        return _draw(p, a);
      case 'extrude':
        return _extrude(p, a);
      case 'revolve':
        return _revolve(p, a);
      case 'fillet':
      case 'chamfer':
        return _blend(p, a);
      case 'edit_feature':
        return _editFeature(p, a);
      case 'delete_feature':
        return _deleteFeature(p, a);
      case 'rename_feature':
        return _renameFeature(p, a);
      case 'set_visible':
        return _setVisible(p, a);
    }
    return AiActionOutcome.failed(a.op, 'unknown op');
  }

  // ---- sketches ---------------------------------------------------------

  static const _planes = {'xy', 'xz', 'yz'};

  /// `on` — a side of the part's box, as the plane that side lies in and the
  /// offset that puts a sketch on it, and whether that plane's normal points
  /// out of the material.
  static const Map<String, (String, bool)> _sides = {
    'top': ('xz', true),
    'bottom': ('xz', false),
    'front': ('xy', true),
    'back': ('xy', false),
    'right': ('yz', true),
    'left': ('yz', false),
  };

  AiActionOutcome _createSketch(PartModel p, AiAction a) {
    // "On top of the part" without a face id, a normal or a frame of its own:
    // the ORIGIN plane that side is parallel to, moved out to the side. The
    // axes are exactly the table's, so nothing new has to be learned, and the
    // sketch's (0,0) stays over the world origin — use sk.cx/sk.cy for the
    // middle of the part.
    final on = a.text('on')?.toLowerCase();
    if (on != null) {
      final side = _sides[on];
      if (side == null) {
        return AiActionOutcome.failed(a.op,
            'on must be one of ${_sides.keys.join(", ")}');
      }
      final b = _solidBounds(p);
      if (b == null) {
        return AiActionOutcome.failed(
            a.op, 'there is no body yet to put a sketch on');
      }
      final (plane, outward) = side;
      final (lo, hi) = b;
      final at = switch (on) {
        'top' => hi.y,
        'bottom' => lo.y,
        'front' => hi.z,
        'back' => lo.z,
        'right' => hi.x,
        _ => lo.x,
      };
      final made = _createSketch(
          p,
          AiAction(a.op, {
            for (final e in a.args.entries)
              if (e.key != 'on') e.key: e.value,
            'plane': plane,
            'offset': at,
          }));
      if (!made.ok) return made;
      return AiActionOutcome(a.op, detail: {
        ...?made.detail,
        'on': on,
        'note': outward
            ? 'This sketch lies on the $on of the part. Extrude with the '
                'default direction to build outward from it, or cut into the '
                'part with direction "flipped".'
            : 'This sketch lies on the $on of the part, and the plane normal '
                'points INTO the material. Extrude with direction "flipped" '
                'to build outward from it; a cut with the default direction '
                'goes into the part.',
      });
    }
    final plane = (a.text('plane') ?? 'xy').toLowerCase();
    if (!_planes.contains(plane)) {
      return AiActionOutcome.failed(
          a.op, 'plane must be one of ${_planes.join(", ")}');
    }
    if (p.childSketches.length >= 200) {
      return AiActionOutcome.failed(a.op, 'this part already has 200 sketches');
    }
    // M458 — A SKETCH AT A HEIGHT.
    //
    // The three origin planes all pass through the origin, so a model that
    // wanted to draw the top of something 40 mm up had to draw it at the
    // bottom and extrude 40 mm of material it did not want, or build a work
    // plane it had no op for. An offset sketch is the frame of the named
    // plane moved along its own normal — which is exactly what a work plane
    // at an offset IS, and it carries through every later feature because a
    // sketch on a frame is how this app already models a sketch on a face.
    final offset = a.number('offset') ?? 0;
    if (offset.abs() > 100000) {
      return AiActionOutcome.failed(a.op, 'offset is beyond 100 m');
    }
    final base = planeFrame(plane);
    final frame = offset == 0
        ? null
        : PlaneFrame('face', base.u, base.v, base.n, base.n * offset);
    final (name, nameWhy) = _newSketchName(p, a);
    if (name == null) return AiActionOutcome.failed(a.op, nameWhy!);
    final sketch = SketchModel(name);
    sketch.insertLayerAboveMarker(_layerName);
    p.appendChildSketch(ChildSketch(sketch, frame == null ? plane : 'face',
        frame, true, false, p.nextSeq()));
    _madeSketches.add('${p.name}/${sketch.name}');
    app.aiAdmitSketchRow(p);
    Log.i('ai',
        'sketch "${sketch.name}" created on $plane${offset == 0 ? "" : " + $offset mm"} of "${p.name}"');
    return AiActionOutcome(a.op, detail: {
      'sketch': sketch.name,
      'plane': plane,
      if (offset != 0) 'offsetMm': _r(offset),
      if (offset != 0)
        'note': 'This sketch sits ${_mm(offset)} mm along the ${plane.toUpperCase()} '
            'plane normal, so what you draw on it starts there.',
      // ISSUE #82 — every sketch says which way its own axes point, because
      // the alternative is the model working it out by building something and
      // measuring the result. See [frameAxisNote].
      'axes': frameAxisNote(frame ?? base),
    });
  }

  static const _layerName = 'Layer 1';

  /// The name a new sketch gets: the model's own `id`, or the next free
  /// "SketchN".
  ///
  /// ISSUE #87 — a block drew two sketches and then extruded "Sketch5",
  /// which was the model's guess at what the second one would be called. The
  /// app reuses freed numbers, so after a deletion or a rollback the guess is
  /// wrong, and the whole block failed on "no sketch named". An id is a name
  /// the model chose and can therefore say again.
  ///
  /// Sending the same id again REDRAWS it when nothing is built on it yet —
  /// so re-running a block that failed later is harmless — and is refused
  /// when a feature uses it, because redrawing a consumed sketch in place
  /// would move a feature nobody asked to move.
  (String?, String?) _newSketchName(PartModel p, AiAction a) {
    final id = a.text('id');
    if (id == null) return (p.nextSketchName(), null);
    if (!RegExp(r'^[A-Za-z0-9_][A-Za-z0-9_ \-]{0,39}$').hasMatch(id)) {
      return (null, 'id must be 1-40 letters, digits, spaces, _ or -');
    }
    final old = p.sketchByName(id);
    if (old == null) return (id, null);
    if (consumersOf(p, id).isNotEmpty) {
      return (
        null,
        'sketch "$id" is already used by ${consumersOf(p, id).map((f) => f.name).join(", ")}. '
            'Give the new sketch a new id; to change that feature, send it '
            'again with its own id and the new sketch'
      );
    }
    p.childSketches.remove(old);
    app.aiForgetRegions(id);
    return (id, null);
  }

  /// The sketch an action names, or the newest one. Named explicitly because
  /// "the newest" is a convenience, and a model that has built two sketches
  /// must be able to say which one it means.
  (ChildSketch?, String?) _sketchFor(PartModel p, AiAction a) {
    final named = a.text('sketch');
    if (named != null) {
      final cs = p.sketchByName(named);
      return cs == null ? (null, 'no sketch named "$named"') : (cs, null);
    }
    if (p.childSketches.isEmpty) {
      return (null, 'this part has no sketch yet — run create_sketch first');
    }
    return (p.childSketches.last, null);
  }

  AiActionOutcome _draw(PartModel p, AiAction a) {
    final (cs, err) = _sketchFor(p, a);
    if (cs == null) return AiActionOutcome.failed(a.op, err!);
    final sketch = cs.model;
    if (sketch.layers.isEmpty) sketch.insertLayerAboveMarker(_layerName);
    final layer = sketch.layers[sketch.eosAfter > 0 ? sketch.eosAfter - 1 : 0];

    // ISSUE #73/#78/#80 — A SLOT IS FOUR ENTITIES, NOT ONE.
    //
    // Every draw op used to make exactly one Geo, which is why the op set
    // stopped at rectangle, circle, polygon and line: anything with a curved
    // side needs several. The model's way round that was sketch_polygon —
    // 34 of them across the reported sessions, every one a curve approximated
    // by straight segments. That is the "handle which looks like circles but
    // isn't really", and it is why a fillet on it then fails: there is no
    // circular edge to blend, only a fan of facets.
    late final List<Geo> made;
    late final Map<String, dynamic> detail;
    // One block per case: switch cases share a scope, and several of these
    // want the same local names.
    switch (a.op) {
      case 'sketch_rect':
        {
          final w = a.number('width'), h = a.number('height');
          final x = a.number('x') ?? 0, y = a.number('y') ?? 0;
          if (w == null || h == null || w <= 0 || h <= 0) {
            return AiActionOutcome.failed(a.op, 'width and height must be > 0');
          }
          final centered = a.flag('centered');
          final x0 = centered ? x - w / 2 : x, y0 = centered ? y - h / 2 : y;
          made = [
            _polyline([
              [x0, y0],
              [x0 + w, y0],
              [x0 + w, y0 + h],
              [x0, y0 + h]
            ], closed: true, layer: layer)
          ];
          detail = {
            'shape': 'rectangle',
            'corner': [_r(x0), _r(y0)],
            'width': _r(w),
            'height': _r(h)
          };
        }
      case 'sketch_circle':
        {
          final diameter = a.number('diameter');
          final r = diameter != null ? diameter / 2 : a.number('radius');
          final x = a.number('x') ?? 0, y = a.number('y') ?? 0;
          if (r == null || r <= 0) {
            return AiActionOutcome.failed(
                a.op, 'diameter (or radius) must be > 0');
          }
          made = [Geo(Geo.circle, [x, y, r], layer: layer)];
          detail = {
            'shape': 'circle',
            'centre': [_r(x), _r(y)],
            'diameter': _r(r * 2)
          };
        }
      case 'sketch_polygon':
        {
          final pts = a.points('points');
          if (pts.length < 3) {
            return AiActionOutcome.failed(
                a.op, 'a polygon needs at least 3 finite points');
          }
          if (pts.length > 400) {
            return AiActionOutcome.failed(a.op, 'at most 400 points');
          }
          made = [
            _polyline(pts,
                closed: a.flag('closed', fallback: true), layer: layer)
          ];
          detail = {'shape': 'polygon', 'points': pts.length};
        }
      case 'sketch_line':
        {
          final x1 = a.number('x1'), y1 = a.number('y1');
          final x2 = a.number('x2'), y2 = a.number('y2');
          if (x1 == null || y1 == null || x2 == null || y2 == null) {
            return AiActionOutcome.failed(
                a.op, 'x1, y1, x2 and y2 are required');
          }
          if (x1 == x2 && y1 == y2) {
            return AiActionOutcome.failed(
                a.op, 'the two ends are the same point');
          }
          made = [Geo(Geo.line, [x1, y1, x2, y2], layer: layer)];
          detail = {
            'shape': 'line',
            'from': [_r(x1), _r(y1)],
            'to': [_r(x2), _r(y2)]
          };
        }
      case 'sketch_arc':
        {
          final three = [
            for (final k in const ['x1', 'y1', 'x2', 'y2', 'x3', 'y3'])
              a.number(k)
          ];
          if (three.every((v) => v != null)) {
            final arc = arcThrough(Offset(three[0]!, three[1]!),
                Offset(three[2]!, three[3]!), Offset(three[4]!, three[5]!));
            if (arc == null) {
              return AiActionOutcome.failed(
                  a.op, 'those three points are collinear — use sketch_line');
            }
            made = [Geo(Geo.arc, List<double>.of(arc.data), layer: layer)];
            detail = {
              'shape': 'arc',
              'through': 3,
              'centre': [_r(arc.data[0]), _r(arc.data[1])],
              'radius': _r(arc.data[2]),
            };
          } else {
            final diameter = a.number('diameter');
            final r = diameter != null ? diameter / 2 : a.number('radius');
            final x = a.number('x') ?? 0, y = a.number('y') ?? 0;
            final from = a.number('start_deg'), to = a.number('end_deg');
            if (r == null || r <= 0) {
              return AiActionOutcome.failed(
                  a.op, 'radius (or diameter) must be > 0');
            }
            if (from == null || to == null) {
              return AiActionOutcome.failed(
                  a.op,
                  'give either three points (x1..y3) or a centre with '
                  'radius, start_deg and end_deg');
            }
            if ((to - from).abs() < 1e-9) {
              return AiActionOutcome.failed(
                  a.op, 'start_deg and end_deg are the same angle');
            }
            const d2r = math.pi / 180;
            made = [
              Geo(Geo.arc, [x, y, r, from * d2r, to * d2r, 0], layer: layer)
            ];
            detail = {
              'shape': 'arc',
              'centre': [_r(x), _r(y)],
              'radius': _r(r),
              'sweepDeg': _r(to - from),
            };
          }
        }
      case 'sketch_slot':
        {
          final x1 = a.number('x1'), y1 = a.number('y1');
          final x2 = a.number('x2'), y2 = a.number('y2');
          final width = a.number('width');
          if (x1 == null || y1 == null || x2 == null || y2 == null) {
            return AiActionOutcome.failed(
                a.op, 'x1, y1, x2 and y2 are the centres of the two ends');
          }
          if (width == null || width <= 0) {
            return AiActionOutcome.failed(a.op, 'width must be > 0');
          }
          final dx = x2 - x1, dy = y2 - y1;
          final len = math.sqrt(dx * dx + dy * dy);
          if (len < 1e-9) {
            return AiActionOutcome.failed(
                a.op, 'the two ends are the same point — use sketch_circle');
          }
          final ux = dx / len, uy = dy / len;
          final r = width / 2;
          // The normal, and the four pieces of a stadium: two parallel sides
          // and a true semicircle at each end.
          final nx = -uy * r, ny = ux * r;
          Geo? capAt(double cx, double cy, double sx, double sy) => arcThrough(
              Offset(cx + sx, cy + sy),
              Offset(cx + ux * r * (sx == nx ? 1 : -1),
                  cy + uy * r * (sx == nx ? 1 : -1)),
              Offset(cx - sx, cy - sy));
          final endA = capAt(x2, y2, nx, ny);
          final endB = capAt(x1, y1, -nx, -ny);
          if (endA == null || endB == null) {
            return AiActionOutcome.failed(a.op, 'the slot could not be built');
          }
          made = [
            Geo(Geo.line, [x1 + nx, y1 + ny, x2 + nx, y2 + ny], layer: layer),
            Geo(Geo.arc, List<double>.of(endA.data), layer: layer),
            Geo(Geo.line, [x2 - nx, y2 - ny, x1 - nx, y1 - ny], layer: layer),
            Geo(Geo.arc, List<double>.of(endB.data), layer: layer),
          ];
          detail = {
            'shape': 'slot',
            'from': [_r(x1), _r(y1)],
            'to': [_r(x2), _r(y2)],
            'width': _r(width),
            'lengthOverall': _r(len + width),
          };
        }
      case 'sketch_rounded_rect':
        {
          final w = a.number('width'), h = a.number('height');
          final x = a.number('x') ?? 0, y = a.number('y') ?? 0;
          final radius = a.number('radius');
          if (w == null || h == null || w <= 0 || h <= 0) {
            return AiActionOutcome.failed(a.op, 'width and height must be > 0');
          }
          if (radius == null || radius <= 0) {
            return AiActionOutcome.failed(a.op, 'radius must be > 0');
          }
          if (radius > w / 2 + 1e-9 || radius > h / 2 + 1e-9) {
            return AiActionOutcome.failed(
                a.op,
                'radius ${_mm(radius)} does not fit a '
                '${_mm(w)} × ${_mm(h)} rectangle — the most that fits is '
                '${_mm(math.min(w, h) / 2)}');
          }
          final centered = a.flag('centered');
          final x0 = centered ? x - w / 2 : x, y0 = centered ? y - h / 2 : y;
          final x1r = x0 + w, y1r = y0 + h;
          const d2r = math.pi / 180;
          made = [
            Geo(Geo.line,
                [x0 + radius, y0, x1r - radius, y0], layer: layer),
            Geo(Geo.arc, [
              x1r - radius, y0 + radius, radius, -90 * d2r, 0, 0
            ], layer: layer),
            Geo(Geo.line,
                [x1r, y0 + radius, x1r, y1r - radius], layer: layer),
            Geo(Geo.arc, [
              x1r - radius, y1r - radius, radius, 0, 90 * d2r, 0
            ], layer: layer),
            Geo(Geo.line,
                [x1r - radius, y1r, x0 + radius, y1r], layer: layer),
            Geo(Geo.arc, [
              x0 + radius, y1r - radius, radius, 90 * d2r, 180 * d2r, 0
            ], layer: layer),
            Geo(Geo.line,
                [x0, y1r - radius, x0, y0 + radius], layer: layer),
            Geo(Geo.arc, [
              x0 + radius, y0 + radius, radius, 180 * d2r, 270 * d2r, 0
            ], layer: layer),
          ];
          detail = {
            'shape': 'rounded rectangle',
            'corner': [_r(x0), _r(y0)],
            'width': _r(w),
            'height': _r(h),
            'radius': _r(radius),
          };
        }
      case 'sketch_path':
      case 'sketch_ring':
        {
          final (geos, info, why) = a.op == 'sketch_path'
              ? buildSketchPath(a, layer)
              : buildSketchRing(a, layer);
          if (geos == null) return AiActionOutcome.failed(a.op, why!);
          made = geos;
          detail = info!;
        }
      case 'sketch_point':
        {
          final x = a.number('x'), y = a.number('y');
          if (x == null || y == null) {
            return AiActionOutcome.failed(a.op, 'x and y are required');
          }
          // M209's tagged point: the carrier is a circle because the core has
          // no point type, and the tag is what makes it a point everywhere
          // that matters — including to a hole and a sketch-driven pattern,
          // both of which place on points and on nothing else.
          made = [
            Geo(Geo.circle, [x, y, kSketchPointRadius],
                spline: Geo.pointTag, layer: layer)
          ];
          detail = {'shape': 'point', 'at': [_r(x), _r(y)]};
        }
      default:
        return AiActionOutcome.failed(a.op, 'unknown draw op');
    }
    if (sketch.geometry.length + made.length > 2000) {
      return AiActionOutcome.failed(a.op, 'this sketch already holds 2000 entities');
    }
    app.aiCommitSketch(sketch, [...sketch.geometry, ...made]);
    sketch.dirty = true;
    app.aiForgetRegions(sketch.name);
    final regions = app.sessionRegions(cs).length;
    return AiActionOutcome(a.op, detail: {
      'sketch': sketch.name,
      ...detail,
      // What the profile finder makes of the sketch NOW. This is the number
      // that decides whether an extrude has anything to work with, and the
      // model gets it before it asks for one.
      'closedProfiles': regions
    });
  }

  Geo _polyline(List<List<double>> pts,
          {required bool closed, required String layer}) =>
      Geo(
          Geo.polyline,
          [
            closed ? 1.0 : 0.0,
            pts.length.toDouble(),
            for (final p in pts) ...[p[0], p[1]]
          ],
          layer: layer);

  // ---- features ---------------------------------------------------------

  static const _outputs = {'new', 'join', 'cut', 'intersect'};

  /// The body a boolean acts on, and the name the feature should carry.
  (KernelSolid?, String) _target(PartModel p, AiAction a, String output) {
    final named = a.text('body');
    if (named != null && p.bodyNames.contains(named)) {
      return (currentBodySolid(p, named), named);
    }
    if (output == 'new') return (null, p.nextSolidName());
    final last = lastSolidFeature(p);
    if (last == null) return (null, p.nextSolidName());
    return (currentBodySolid(p, last.bodyName), last.bodyName);
  }

  String _outputOf(AiAction a, PartModel p) {
    final asked = (a.text('operation') ?? '').toLowerCase();
    if (_outputs.contains(asked)) return asked;
    // No body yet means there is nothing to join to: this is the base feature.
    return p.bodyNames.isEmpty ? 'new' : 'join';
  }

  /// Why a sketch has no closed region, said so the next block can fix it.
  ///
  /// ISSUE #82 — the bare "has no closed profile" sent the assistant back to
  /// the drawing board when its profile was 0.0008 mm from correct. Naming the
  /// gap and the two points makes the repair obvious; saying nothing makes
  /// redrawing from scratch the only visible option, and that is what it did.
  String _noProfile(ChildSketch cs, String verb) {
    final name = cs.model.name;
    // M397's finder: the distance from a loose end to the curve it nearly
    // meets, which is the number that actually explains the failure.
    final g = nearestProfileGap(cs.model);
    if (g == null) {
      return 'sketch "$name" has no closed profile to $verb — its curves do '
          'not enclose an area. Every region needs a chain of entities that '
          'returns to where it started.';
    }
    return 'sketch "$name" has no closed profile to $verb: the end at '
        '(${_r(g.at.dx)}, ${_r(g.at.dy)}) is ${g.gap.toStringAsFixed(4)} mm '
        'short of the curve it should meet. Move just that end onto the other '
        'one — or let a single op make the whole shape (sketch_slot, '
        'sketch_rounded_rect, sketch_circle, or sketch_arc given three points '
        'it passes THROUGH) instead of computing endpoints from angles and '
        'rounding them. Nothing else about this sketch is wrong.';
  }

  Future<AiActionOutcome> _extrude(PartModel p, AiAction a) async {
    final (cs, err) = _sketchFor(p, a);
    if (cs == null) return AiActionOutcome.failed(a.op, err!);
    app.aiForgetRegions(cs.model.name);
    final all = app.sessionRegions(cs);
    if (all.isEmpty) {
      return AiActionOutcome.failed(a.op, _noProfile(cs, 'extrude'));
    }
    final (regions, ruleWhy) = _pickRegions(all, a, _outputOf(a, p));
    if (regions == null) return AiActionOutcome.failed(a.op, ruleWhy!);
    final through = a.flag('through_all');
    final distance = a.number('distance');
    if (!through && (distance == null || distance <= 0)) {
      return AiActionOutcome.failed(a.op, 'distance must be > 0');
    }
    if (!through && distance! > 100000) {
      return AiActionOutcome.failed(a.op, 'distance is beyond 100 m');
    }
    final taper = a.number('taper') ?? 0;
    if (taper.abs() >= 90) {
      return AiActionOutcome.failed(a.op, 'taper must be between -90 and 90');
    }
    final direction = _direction(a);
    if (direction == null) {
      return AiActionOutcome.failed(a.op,
          'direction must be default, flipped or symmetric');
    }
    final output = _outputOf(a, p);
    if (through && output == 'new') {
      return AiActionOutcome.failed(
          a.op, 'through_all needs an existing body to pass through');
    }
    final (base, body) = _target(p, a, output);
    if (output != 'new' && base == null) {
      return AiActionOutcome.failed(
          a.op, 'no existing body for a $output — use operation "new"');
    }
    final d = distance ?? 0;
    final f = ExtrudeFeature(
      name: p.nextFeatureName(),
      bodyName: body,
      sketchName: cs.model.name,
      profiles: [
        for (final r in regions)
          ProfileSel(regionAnchor(r).dx, regionAnchor(r).dy, r.outer.area)
      ],
      direction: direction,
      distanceA: d,
      distanceB: direction == ExtrudeDirection.symmetric ? d : 0,
      taperDeg: taper,
      exprA: '$d mm',
      exprB: '$d mm',
      exprTaper: '$taper deg',
      extent: through ? FeatureExtent.throughAll : FeatureExtent.distance,
      output: output,
    );
    p.claimBodyName(body);
    return _commitFeature(p, a, f, base, {
      'sketch': cs.model.name,
      'profiles': f.profiles.length,
      if (regions.length != all.length)
        'profilesLeftOpen': all.length - regions.length,
      if (!through) 'distance': _r(d),
      'extent': through ? 'throughAll' : 'distance',
      'direction': extrudeDirName(direction),
      'operation': output,
      // #94 — the model read "-5.94" as "wider at the top" and built its
      // tapered cup upside down. Say which way it went, in words.
      if (taper != 0) 'taper': _r(taper),
      if (taper != 0)
        'taperNote': taper < 0
            ? 'Negative taper: every side leans IN by ${_r(-taper)}°, so the '
                'far end is SMALLER than the sketch. For a shape that widens '
                'away from the sketch, the taper is positive.'
            : 'Positive taper: every side leans OUT by ${_r(taper)}°, so the '
                'far end is LARGER than the sketch.',
    });
  }

  Future<AiActionOutcome> _revolve(PartModel p, AiAction a) async {
    final (cs, err) = _sketchFor(p, a);
    if (cs == null) return AiActionOutcome.failed(a.op, err!);
    app.aiForgetRegions(cs.model.name);
    final all = app.sessionRegions(cs);
    if (all.isEmpty) {
      return AiActionOutcome.failed(a.op, _noProfile(cs, 'revolve'));
    }
    final (regions, ruleWhy) = _pickRegions(all, a, _outputOf(a, p));
    if (regions == null) return AiActionOutcome.failed(a.op, ruleWhy!);
    final angle = a.number('angle') ?? 360;
    if (angle <= 0 || angle > 360) {
      return AiActionOutcome.failed(a.op, 'angle must be > 0 and <= 360');
    }
    final axis = (a.text('axis') ?? 'x').toLowerCase();
    if (axis != 'x' && axis != 'y') {
      return AiActionOutcome.failed(a.op, 'axis must be "x" or "y"');
    }
    // The profile must lie wholly on one side of the axis or the kernel builds
    // a self-intersecting body. Catching it here names the offending sketch;
    // the kernel's own refusal would only say the revolve failed.
    final crossing = regions.any((r) => r.outer.pts.any((q) =>
        (axis == 'x' ? q.dy : q.dx) < -1e-9) &&
        r.outer.pts.any((q) => (axis == 'x' ? q.dy : q.dx) > 1e-9));
    if (crossing) {
      return AiActionOutcome.failed(a.op,
          'the profile crosses the $axis axis it would revolve about');
    }
    final output = _outputOf(a, p);
    final (base, body) = _target(p, a, output);
    if (output != 'new' && base == null) {
      return AiActionOutcome.failed(
          a.op, 'no existing body for a $output — use operation "new"');
    }
    final f = RevolveFeature(
      name: p.nextFeatureName('Revolution'),
      bodyName: body,
      sketchName: cs.model.name,
      profiles: [
        for (final r in regions)
          ProfileSel(regionAnchor(r).dx, regionAnchor(r).dy, r.outer.area)
      ],
      axPx: 0,
      axPy: 0,
      axDx: axis == 'x' ? 1.0 : 0.0,
      axDy: axis == 'x' ? 0.0 : 1.0,
      angleA: angle,
      exprA: '$angle deg',
      full: angle >= 360,
      output: output,
    );
    p.claimBodyName(body);
    return _commitFeature(p, a, f, base, {
      'sketch': cs.model.name,
      'profiles': f.profiles.length,
      'angle': _r(angle),
      'axis': axis,
      'operation': output,
    });
  }

  /// Which closed regions of a sketch a feature is built from.
  ///
  /// Every region used to be taken, always. A plate drawn with a circle
  /// inside it is two regions — the plate with a hole, and the disc that
  /// fills the hole — and taking both builds a plate with no hole: the
  /// assistant had to extrude the plate and then cut the hole as a second
  /// feature, and a ring drawn as two circles came out a solid cylinder.
  ///
  /// So the default follows the rule every drawing program uses for nested
  /// outlines, EVEN-ODD: a region inside an odd number of other outlines is a
  /// hole and stays open, one inside an even number is material. Overlapping
  /// shapes are not nested — their pieces are side by side — so they still
  /// union. A cut takes every region, because cutting a plate outline with a
  /// circle in it means cutting all of it.
  ///
  ///   regions: "auto" (default) | "evenodd" | "all" | "largest"
  ///            | [[x, y], ...] — the regions containing these points
  (List<ProfileRegion>?, String?) _pickRegions(
      List<ProfileRegion> all, AiAction a, String output) {
    final rule = a.args['regions'];
    bool contains(ProfileRegion r, Offset q) =>
        pointInPolygon(q, r.outer.pts) &&
        !r.holes.any((h) => pointInPolygon(q, h.pts));
    if (rule is List) {
      final pts = a.points('regions');
      if (pts.isEmpty) {
        return (null, 'regions must be a rule name or [[x, y], ...]');
      }
      final picked = [
        for (final r in all)
          if (pts.any((q) => contains(r, Offset(q[0], q[1])))) r
      ];
      if (picked.isEmpty) {
        return (
          null,
          'none of the points in regions lies inside a closed region of the '
              'sketch (it has ${all.length})'
        );
      }
      return (picked, null);
    }
    final name = (rule is String ? rule : 'auto').toLowerCase();
    switch (name) {
      case 'all':
        return (all, null);
      case 'largest':
        final best = [...all]
          ..sort((x, y) => y.outer.area.compareTo(x.outer.area));
        return ([best.first], null);
      case 'auto':
      case 'evenodd':
        if (name == 'auto' && output == 'cut') return (all, null);
        final picked = <ProfileRegion>[];
        for (final r in all) {
          final q = regionAnchor(r);
          var depth = 0;
          for (final o in all) {
            if (identical(o, r)) continue;
            if (pointInPolygon(q, o.outer.pts)) depth++;
          }
          if (depth.isEven) picked.add(r);
        }
        return (picked.isEmpty ? all : picked, null);
    }
    return (
      null,
      'regions must be "auto", "evenodd", "all", "largest" or [[x, y], ...]'
    );
  }

  ExtrudeDirection? _direction(AiAction a) =>
      switch ((a.text('direction') ?? 'default').toLowerCase()) {
        'default' => ExtrudeDirection.defaultDir,
        'flipped' || 'reversed' => ExtrudeDirection.flipped,
        'symmetric' || 'midplane' => ExtrudeDirection.symmetric,
        _ => null,
      };

  // ---- fillet / chamfer -------------------------------------------------

  Future<AiActionOutcome> _blend(PartModel p, AiAction a) async {
    final isFillet = a.op == 'fillet';
    final size = a.number(isFillet ? 'radius' : 'distance');
    if (size == null || size <= 0) {
      return AiActionOutcome.failed(
          a.op, '${isFillet ? "radius" : "distance"} must be > 0');
    }
    final named = a.text('body');
    final body = named ??
        (p.bodyNames.isEmpty ? null : lastSolidFeature(p)?.bodyName);
    if (body == null || !p.bodyNames.contains(body)) {
      return AiActionOutcome.failed(
          a.op, named == null ? 'this part has no body yet' : 'no body "$named"');
    }
    final solid = currentBodySolid(p, body);
    if (solid == null) {
      return AiActionOutcome.failed(a.op, 'body "$body" has no built geometry');
    }
    final live = app.partKernel.edgesOf(solid);
    if (live.isEmpty) {
      return AiActionOutcome.failed(a.op,
          'the kernel reported no edges for "$body" — it may not be linked '
          'in this build');
    }
    final picked = _selectEdges(live, a, solid.mesh);
    if (picked.isEmpty) {
      // ISSUE #73/#78 — "no edge matched" told the model its selector was
      // wrong and nothing about what would have been right, so the next block
      // guessed again. This names what is actually there.
      final usable = [for (final e in live) if (e.filletable) e];
      final rings = usable.where((e) => e.kind == 2).length;
      return AiActionOutcome.failed(
          a.op,
          'no edge of "$body" matched that selection. It has ${live.length} '
          'live edges, ${usable.length} of them blendable: '
          '${usable.where((e) => e.kind == 1).length} straight, $rings '
          'circular, ${usable.where((e) => e.convexity > 0).length} convex, '
          '${usable.where((e) => e.convexity < 0).length} concave, '
          '${usable.where((e) => e.ty.abs() > 0.9).length} vertical. '
          'Selectors: all, top, bottom, outer, holes, rings, convex, concave, vertical, '
          'horizontal, or near with a point in mm.');
    }
    final selections = [
      for (final e in picked) EdgeSel(e.mx, e.my, e.mz, e.length, e.kind, e.radius)
    ];
    // ISSUE #73 — WHAT A FAILED BLEND HAS TO SAY.
    //
    // "no radius in this size range builds on these edges" three times in one
    // session, each costing a round trip, because the report named the
    // failure and not the remedy. The kernel can answer "what WOULD build"
    // directly — so on a failure the executor asks it, by bisection, and
    // hands back the largest radius that does. One round, not four.
    final f = isFillet
        ? FilletFeature(
            name: p.nextFeatureName('Fillet'),
            bodyName: body,
            edges: selections,
            radii: [for (var i = 0; i < selections.length; i++) size],
            exprRadius: '$size mm')
        : ChamferFeature(
            name: p.nextFeatureName('Chamfer'),
            bodyName: body,
            edges: selections,
            distance1: size,
            distance2: size,
            exprD1: '$size mm',
            exprD2: '$size mm');
    final outcome = await _commitFeature(p, a, f, currentBodySolid(p, body), {
      'body': body,
      'edges': selections.length,
      if (isFillet) 'radius': _r(size) else 'distance': _r(size),
      // ISSUE #72 — "die Radien sind an falschen orten". The report used to
      // be a COUNT. `{"edges": "horizontal"}` matched ten of them, the model
      // was told "edges: 10", and two of those ten were the mouths of the
      // Ø25 bores it had just cut — which it had no way of knowing and
      // therefore never questioned. Saying WHAT was rounded turns a silent
      // mistake into one the next round can read and undo.
      'rounded': _describeEdges(picked),
    });
    if (outcome.ok) return outcome;
    // The kernel refused this size. Ask it what it WOULD take, so the next
    // block is a build rather than another guess.
    final fits = _largestBlendThatBuilds(p, body, selections, isFillet, size);
    // #84/#83 — THE APP BUILDS WHAT IT FOUND. Told "0.88 builds", the model
    // has retried at exactly that number every time it was told, one round
    // trip each, and #84 spent eight rounds and 21 s of kernel time on it.
    // The number was already verified, so it is applied here and reported
    // plainly: what was asked, what was built, and how to ask for exactly the
    // original or nothing (`"exact": true`).
    if (fits != null && !a.flag('exact')) {
      final retry = AiAction(a.op, {
        ...a.args,
        isFillet ? 'radius' : 'distance': fits,
        'exact': true,
      });
      final built = await _blend(p, retry);
      if (built.ok) {
        return AiActionOutcome(a.op, detail: {
          ...?built.detail,
          isFillet ? 'radiusAsked' : 'distanceAsked': _r(size),
          'note': '${_mm(size)} mm does not build on these edges; '
              '${_mm(fits)} mm is the largest that does, so that was built. '
              'If the design needs the full size, change the geometry the '
              'blend runs between; to refuse a smaller blend, send '
              '"exact": true.',
        });
      }
    }
    if (fits == null) {
      final solid = currentBodySolid(p, body);
      if (solid?.shape != null && !solid!.shape!.valid) {
        return AiActionOutcome.failed(
            a.op,
            '${outcome.error} — and no size builds, because body "$body" is '
            'not a valid solid. The blend is not the problem: the last '
            'feature that made this body twisted or folded it (a sweep '
            'whose profile is not square to its path is the usual cause). '
            'Fix or replace that feature first.');
      }
    }
    return AiActionOutcome.failed(
        a.op,
        fits == null
            ? '${outcome.error} — no size builds on these '
                '${selections.length} edge(s). Blend fewer edges, or a '
                'different set: a blend cannot run off the end of the faces '
                'it follows.'
            // #83 — "Retry at X or less" was two mistakes. X was never built,
            // and "or less" is not true either: a blend that fails at one size
            // can fail at a smaller one too, because a different edge binds at
            // each size. This number HAS been built, at exactly this value.
            : '${outcome.error} — but ${_mm(fits)} mm does build on these '
                '${selections.length} edge(s); the app just built it to check. '
                'Retry at exactly ${_mm(fits)}. Do not go lower hoping for '
                'more room — a smaller radius is not safer here, it just '
                'moves which edge fails.');
  }

  /// What to try next, for the kernel failures that have a known remedy.
  ///
  /// ISSUE #76 — "Revolution did not build: occt_mesh_create: triangulation
  /// produced no triangles", three times in a row, and the model had nothing
  /// to go on but the words. A kernel message names what went wrong inside
  /// the kernel; it is not advice, and the model treated it as a dead end and
  /// deleted the feature instead of changing the thing that caused it.
  ///
  /// These are hints, phrased as hints. Where the cause is genuinely not
  /// established — an empty triangulation has several — the text says which
  /// things to check rather than asserting one.
  String _remedyFor(String? kernelError) {
    final e = (kernelError ?? '').toLowerCase();
    if (e.contains('no triangles') || e.contains('triangulation')) {
      return ' — the kernel made a shape with no surface. That is usually a '
          'profile that touches or crosses the axis or another profile '
          'exactly, or a revolve whose profile meets itself. Check the '
          'profile with section, give touching profiles a real gap, and keep '
          'the profile clear of the axis.';
    }
    if (e.contains('runs off the end of the faces')) {
      return ' — the blend is longer than the faces it follows. Use a smaller '
          'size, or select fewer edges so it does not have to turn a corner '
          'it cannot.';
    }
    if (e.contains('self-inters') || e.contains('not a valid solid')) {
      return ' — the result would intersect itself. Change the size, or build '
          'it as two features that are fused rather than one that folds over.';
    }
    if (e.contains('empty') || e.contains('no profile')) {
      return ' — there was no closed region to build from. Draw the profile '
          'first and check closedProfiles in the result.';
    }
    return '';
  }

  /// The largest blend size that the kernel accepts on [edges], by bisection
  /// over the two-decimal grid.
  ///
  /// Each probe is a real kernel build — on a 26-edge fillet they cost about a
  /// second each — so this is bounded, and nothing here reaches the document:
  /// a probe that succeeds is disposed exactly like one that fails, and no
  /// feature is ever appended.
  ///
  /// ISSUE #83 — WHY IT SEARCHES HUNDREDTHS AND NOT REALS.
  ///
  /// It used to bisect over the reals and then floor the winner to two
  /// decimals, with the comment "a value the model retries must still build".
  /// That is the one thing flooring cannot guarantee. Blend buildability is
  /// not monotonic in radius — with 26 edges a different edge set binds at
  /// each size, and the session that reported this shows the failure moving
  /// from "edge set 7" to "edge set 16" on the way down — so a value adjacent
  /// to one that builds routinely does not. Bisection verified 0.96875, the
  /// app promised 0.96, and 0.96 had never been built by anybody.
  ///
  /// The model then did exactly as instructed, five times:
  ///
  ///   asked 2.00 -> "0.96 does build" -> 0.96 fails -> "0.94 does build"
  ///              -> 0.94 fails        -> "0.92"     -> 0.92 fails
  ///              -> "0.90"            -> 0.90 fails -> "0.88" -> built
  ///
  /// Five provider round trips, about 110 seconds, every one of them spent on
  /// a promise the app had not checked, while the kernel could have walked the
  /// same staircase in a few seconds without anybody watching.
  ///
  /// Searching whole hundredths fixes it at the root: the value returned was
  /// built AT EXACTLY THE NUMBER THAT WILL BE PRINTED. [_mm] renders two
  /// decimals and rounds, so a real-valued answer could also be rounded UP on
  /// its way to the model — 0.96875 prints as "0.97" — into a third size
  /// nobody ever tried.
  double? _largestBlendThatBuilds(PartModel p, String body,
      List<EdgeSel> edges, bool isFillet, double asked) {
    if (!app.partKernel.available) return null;
    final base = currentBodySolid(p, body);
    bool builds(double size) {
      final probe = isFillet
          ? FilletFeature(
              name: '__probe',
              bodyName: body,
              edges: edges,
              radii: [for (var i = 0; i < edges.length; i++) size],
              exprRadius: '$size mm')
          : ChamferFeature(
              name: '__probe',
              bodyName: body,
              edges: edges,
              distance1: size,
              distance2: size,
              exprD1: '$size mm',
              exprD2: '$size mm');
      final ok = recomputeFeature(p, probe, app.partKernel, base: base);
      probe.disposeSolid();
      return ok;
    }

    // Hundredths, so every candidate is a number the report can print exactly.
    var lo = 1, hi = (asked * 100).floor() - 1;
    int? best;
    var probes = 0;
    // Wall clock as well as a count: a 26-edge probe took about a second in
    // #83, and one failing fillet held the block for 6.6 s. A search that
    // runs out of time returns the best size it has BUILT so far, which is
    // still a promise kept, just a smaller one.
    final clock = Stopwatch()..start();
    while (lo <= hi &&
        probes < _kMaxBlendProbes &&
        clock.elapsedMilliseconds < _kBlendSearchMs) {
      final mid = lo + (hi - lo + 1) ~/ 2;
      probes++;
      if (builds(mid / 100)) {
        best = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    // `best` is a size this method BUILT, at exactly the value it returns.
    return best == null ? null : best / 100;
  }

  /// How recently a feature must have been built for its deletion to count as
  /// a rebuild rather than a considered removal (#83).
  static const int _kChurnWindow = 8;

  /// How many kernel builds one blend search may spend.
  ///
  /// A 26-edge fillet probe is about a second, and bisecting the hundredths up
  /// to 2 mm needs eight. Twelve leaves room for a larger asked size without
  /// letting a pathological body stall the block (#83).
  static const int _kMaxBlendProbes = 12;

  /// How long one blend search may run, whatever the probe count.
  static const int _kBlendSearchMs = 3000;

  /// The picked edges as a person would describe them: straight ones, and
  /// circles grouped by diameter — a circular edge at the diameter of a hole
  /// IS that hole's mouth.
  Map<String, dynamic> _describeEdges(List<OcctEdgeInfo> picked) {
    final straight = picked.where((e) => e.kind == 1).length;
    final circles = <int, int>{};
    for (final e in picked) {
      if (e.kind == 2 && e.radius > 0) {
        final key = (e.radius * 200).round();
        circles[key] = (circles[key] ?? 0) + 1;
      }
    }
    final rings = [
      for (final e in circles.entries)
        '${e.value}× Ø${_mm(e.key / 100)}'
    ]..sort();
    return {
      if (straight > 0) 'straight': straight,
      if (rings.isNotEmpty) 'circular': rings,
      if (rings.isNotEmpty)
        'warning': 'a circular edge at a hole\'s diameter is that hole\'s '
            'mouth — check you meant to round it',
      'convex': picked.where((e) => e.convexity > 0).length,
      'concave': picked.where((e) => e.convexity < 0).length,
    };
  }

  /// Which live edges an action means.
  ///
  /// Every selector is GEOMETRIC, never an index: a topological index is not
  /// stable across a rebuild, so an agent that named one would be naming a
  /// different edge by the time the feature recomputed. `near` is the precise
  /// form — a point in world millimetres, matched to the edge whose arc-length
  /// midpoint is closest to it, and only within 5 mm so a mistyped coordinate
  /// selects nothing rather than something arbitrary.
  List<OcctEdgeInfo> _selectEdges(List<OcctEdgeInfo> live, AiAction a,
      [OcctMeshData? mesh]) {
    final usable = [for (final e in live) if (e.filletable) e];
    final near = a.args['near'];
    if (near is List && near.isNotEmpty) {
      // ISSUE #87 — "near" measured to an edge's MIDPOINT BY ARC LENGTH. For
      // a straight edge that is fine; for a cup's rim — a full circle — the
      // midpoint is one point on the far side, so a point the model placed
      // exactly ON the rim was 77 mm from "the rim" and matched nothing.
      // Three blocks failed on it. The distance is to the edge itself now,
      // along the polyline the mesh already carries for every drawn edge;
      // the midpoint stays as the fallback for edges the display leaves out.
      final curves = mesh == null ? const <int, List<double>>{} : _edgeCurves(mesh);
      final out = <OcctEdgeInfo>[];
      for (final raw in near) {
        if (raw is! List || raw.length < 3) continue;
        final xs = [for (final v in raw) if (v is num) v.toDouble()];
        if (xs.length < 3 || xs.any((v) => !v.isFinite)) continue;
        OcctEdgeInfo? best;
        var bestD = 5.0;
        for (final e in usable) {
          var d = math.sqrt(math.pow(e.mx - xs[0], 2) +
              math.pow(e.my - xs[1], 2) +
              math.pow(e.mz - xs[2], 2));
          final poly = curves[e.index];
          if (poly != null) {
            d = math.min(d, _toPolyline(poly, xs[0], xs[1], xs[2]));
          }
          if (d < bestD) {
            bestD = d;
            best = e;
          }
        }
        if (best != null && !out.contains(best)) out.add(best);
      }
      return out;
    }
    // A vertical edge runs along the world up axis, which is Y in this app
    // (see the world-frame note in part_model.dart) — not Z.
    bool vertical(OcctEdgeInfo e) => e.ty.abs() > 0.9;
    // A closed circular edge is the mouth of a bore or the rim of a boss.
    // "outer" is the selector that was missing when a model wanted the
    // silhouette of a plate and got the plate AND both bore mouths.
    bool ring(OcctEdgeInfo e) => e.kind == 2 && e.radius > 0;
    // #93 — but "circular" is not "a hole". On a turned part — a wheel, a
    // spool, a knob — EVERY edge is a circle, and `{"edges": "holes"}` on the
    // 28 mm wheel chamfered its outer rims along with the Ø5.5 bore. A mouth
    // has empty space just inside its circle and material just outside; a rim
    // is the other way round. Asked of the body itself, where the edge's
    // polyline says where the circle is; without one, as before.
    final curves =
        mesh == null ? const <int, List<double>>{} : _edgeCurves(mesh);
    bool mouth(OcctEdgeInfo e) {
      if (!ring(e)) return false;
      final poly = curves[e.index];
      if (mesh == null || poly == null) return true;
      return aiRingIsMouth(mesh, poly, e.radius) ?? true;
    }
    // #94 — "the rim" and "the foot" are the edges at the top and the bottom
    // of the body. Without a way to say so the model reached for "rings",
    // which on a cup is the rim, the foot AND the floor's inner edge, and
    // then "outer", which took the freshly filleted rim along with the foot.
    // An edge is "top" when it lies wholly within tol of the body's highest
    // point (world Y is up), "bottom" likewise at the lowest.
    double? yLo, yHi;
    if (mesh != null) {
      final pos = mesh.positions;
      for (var i = 1; i < pos.length; i += 3) {
        yLo = yLo == null ? pos[i] : math.min(yLo, pos[i]);
        yHi = yHi == null ? pos[i] : math.max(yHi, pos[i]);
      }
    }
    final tol = yLo == null ? 0.0 : math.max(0.05, (yHi! - yLo) * 0.002);
    (double, double) ySpan(OcctEdgeInfo e) {
      final poly = curves[e.index];
      if (poly == null || poly.length < 3) return (e.my, e.my);
      var lo = poly[1], hi = poly[1];
      for (var i = 1; i < poly.length; i += 3) {
        lo = math.min(lo, poly[i]);
        hi = math.max(hi, poly[i]);
      }
      return (lo, hi);
    }

    bool atTop(OcctEdgeInfo e) => yHi != null && ySpan(e).$1 >= yHi - tol;
    bool atBottom(OcctEdgeInfo e) => yLo != null && ySpan(e).$2 <= yLo + tol;
    return switch ((a.text('edges') ?? 'all').toLowerCase()) {
      'top' || 'rim' => [for (final e in usable) if (atTop(e)) e],
      'bottom' || 'foot' || 'base' => [
          for (final e in usable)
            if (atBottom(e)) e
        ],
      'convex' || 'rounds' => [for (final e in usable) if (e.convexity > 0) e],
      'concave' || 'fillets' => [for (final e in usable) if (e.convexity < 0) e],
      'vertical' => [for (final e in usable) if (vertical(e)) e],
      'horizontal' => [for (final e in usable) if (!vertical(e)) e],
      'outer' => [for (final e in usable) if (!mouth(e)) e],
      'holes' => [for (final e in usable) if (mouth(e)) e],
      'rings' => [for (final e in usable) if (ring(e)) e],
      _ => usable,
    };
  }

  /// Every drawn edge's polyline, keyed by its topological edge index.
  static Map<int, List<double>> _edgeCurves(OcctMeshData mesh) {
    final out = <int, List<double>>{};
    final starts = mesh.edgeStarts, pts = mesh.edgePoints, ids = mesh.edgeIds;
    if (ids.isEmpty || starts.length < 2) return out;
    for (var e = 0; e + 1 < starts.length && e < ids.length; e++) {
      final from = starts[e] * 3, to = starts[e + 1] * 3;
      if (from < 0 || to > pts.length || to - from < 6) continue;
      (out[ids[e]] ??= <double>[]).addAll(pts.sublist(from, to));
    }
    return out;
  }

  /// Distance from a point to a polyline given as xyz triples.
  static double _toPolyline(List<double> p, double x, double y, double z) {
    var best = double.infinity;
    for (var i = 0; i + 5 < p.length; i += 3) {
      final ax = p[i], ay = p[i + 1], az = p[i + 2];
      final dx = p[i + 3] - ax, dy = p[i + 4] - ay, dz = p[i + 5] - az;
      final len2 = dx * dx + dy * dy + dz * dz;
      var t = len2 < 1e-18
          ? 0.0
          : ((x - ax) * dx + (y - ay) * dy + (z - az) * dz) / len2;
      t = t.clamp(0.0, 1.0);
      final qx = ax + dx * t - x, qy = ay + dy * t - y, qz = az + dz * t - z;
      best = math.min(best, math.sqrt(qx * qx + qy * qy + qz * qz));
    }
    return best;
  }

  // ---- editing what is already there ------------------------------------

  PartFeature? _feature(PartModel p, String name) {
    for (final f in p.features) {
      if (f.name == name) return f;
    }
    return null;
  }

  Future<AiActionOutcome> _editFeature(PartModel p, AiAction a) async {
    final name = a.text('feature');
    if (name == null) return AiActionOutcome.failed(a.op, 'feature is required');
    final f = _feature(p, name);
    if (f == null) {
      return AiActionOutcome.failed(a.op,
          'no feature named "$name" (this part has: '
          '${p.features.map((g) => g.name).join(", ")})');
    }
    final changed = <String, dynamic>{};
    final operation = a.text('operation')?.toLowerCase();
    if (operation != null) {
      if (!_outputs.contains(operation)) {
        return AiActionOutcome.failed(a.op, 'operation must be one of '
            '${_outputs.join(", ")}');
      }
      if (f.modifiesBody) {
        return AiActionOutcome.failed(
            a.op, '${f.typeLabel} has no boolean output');
      }
      f.output = operation;
      changed['operation'] = operation;
    }
    // Each case is its own block: switch cases share one scope in Dart, and
    // two of these want a local called `d`.
    switch (f) {
      case final ExtrudeFeature extrude:
        {
          final d = a.number('distance');
          if (d != null) {
            if (d <= 0) {
              return AiActionOutcome.failed(a.op, 'distance must be > 0');
            }
            extrude.distanceA = d;
            extrude.exprA = '$d mm';
            // A typed distance is only consulted for the plain extent, so an
            // edit that set one and left the feature on Through All would
            // change nothing at all and report that it had.
            extrude.extent = FeatureExtent.distance;
            changed['distance'] = _r(d);
          }
          final b = a.number('distance_b');
          if (b != null && b > 0) {
            extrude.distanceB = b;
            extrude.exprB = '$b mm';
            extrude.direction = ExtrudeDirection.asymmetric;
            changed['distanceB'] = _r(b);
          }
          final t = a.number('taper');
          if (t != null) {
            if (t.abs() >= 90) {
              return AiActionOutcome.failed(
                  a.op, 'taper must be between -90 and 90');
            }
            extrude.taperDeg = t;
            extrude.exprTaper = '$t deg';
            changed['taper'] = _r(t);
          }
        }
      case final RevolveFeature revolve:
        {
          final angle = a.number('angle');
          if (angle != null) {
            if (angle <= 0 || angle > 360) {
              return AiActionOutcome.failed(a.op, 'angle must be > 0 and <= 360');
            }
            revolve.angleA = angle;
            revolve.exprA = '$angle deg';
            revolve.full = angle >= 360;
            changed['angle'] = _r(angle);
          }
        }
      case final FilletFeature fillet:
        {
          final r = a.number('radius');
          if (r != null) {
            if (r <= 0) {
              return AiActionOutcome.failed(a.op, 'radius must be > 0');
            }
            for (var i = 0; i < fillet.radii.length; i++) {
              fillet.radii[i] = r;
            }
            fillet.exprRadius = '$r mm';
            changed['radius'] = _r(r);
          }
        }
      case final ShellFeature shell:
        {
          final t = a.number('thickness');
          if (t != null) {
            if (t <= 0) {
              return AiActionOutcome.failed(a.op, 'thickness must be > 0');
            }
            shell.thickness = t;
            shell.exprThickness = '$t mm';
            changed['thickness'] = _r(t);
          }
        }
      case final ChamferFeature chamfer:
        {
          final d = a.number('distance');
          if (d != null) {
            if (d <= 0) {
              return AiActionOutcome.failed(a.op, 'distance must be > 0');
            }
            chamfer.distance1 = d;
            chamfer.distance2 = d;
            chamfer.exprD1 = '$d mm';
            chamfer.exprD2 = '$d mm';
            changed['distance'] = _r(d);
          }
        }
      default:
        break;
    }
    if (changed.isEmpty) {
      return AiActionOutcome.failed(a.op,
          'nothing to change: ${f.typeLabel} "$name" takes none of the '
          'arguments given');
    }
    app.aiRebuild(p);
    if (f.computeError != null) {
      return AiActionOutcome.failed(
          a.op, 'rebuild failed: ${f.computeError}');
    }
    Log.i('ai', 'feature "$name" edited: $changed');
    return AiActionOutcome(a.op, detail: {'feature': name, 'changed': changed});
  }

  Future<AiActionOutcome> _deleteFeature(PartModel p, AiAction a) async {
    final name = a.text('feature');
    if (name == null) return AiActionOutcome.failed(a.op, 'feature is required');
    final f = _feature(p, name);
    if (f == null) return AiActionOutcome.failed(a.op, 'no feature named "$name"');
    // The batch already holds the snapshot this delete belongs to.
    final madeAt = _madeAt.remove(name);
    await app.deleteFeature(f, checkpoint: false);
    // #83 — a delete of something this conversation built, a few blocks ago,
    // is a rebuild. Say so, and say it louder the third time.
    final own = madeAt != null && _blockNo - madeAt <= _kChurnWindow;
    if (own) {
      _churnAt
        ..add(_blockNo)
        ..removeWhere((b) => _blockNo - b > _kChurnWindow * 2);
    }
    final churn = _churnAt.length;
    // #90 — a delete that leaves a later feature without its base has to say
    // so here, not in a rebuild log the model never reads.
    final failing = [
      for (final g in p.features)
        if (g.computeError != null && !g.rolledBack) g.name
    ];
    return AiActionOutcome(a.op, detail: {
      'deleted': name,
      'featuresLeft': p.features.length,
      if (failing.isNotEmpty)
        'nowFailing': '${failing.join(", ")} failed after this delete. '
            'Delete them too if they belonged to it, or fix what they build '
            'on.',
      if (own)
        'churn': churn < 2
            ? 'You built "$name" ${_blockNo - madeAt} block(s) ago and have '
                'now removed it. If what was wrong with it was a NUMBER — a '
                'size, a position, a plane — edit_feature changes it in one '
                'action and keeps everything built on top of it. '
                'delete_feature is for an approach that should not exist.'
            : 'That is $churn features you have built and then deleted in '
                'the last few blocks, and you have not used edit_feature '
                'once. '
                'You are not converging — you are guessing, and each guess '
                'costs the user a round trip. STOP rebuilding. Read the '
                '`extentMm` and `centreMm` in this report and the `axes` line '
                'from the sketch you are drawing on, work out where the '
                'feature actually needs to be from those numbers, and then '
                'either edit the sketch that drives it or place the next one '
                'correctly the first time.'
    });
  }

  /// #90 — every run of consecutive `delete_feature` actions, reordered so
  /// the feature latest in the timeline goes first.
  ///
  /// The model deleted a gear as Extrusion1 then Extrusion2, so for one
  /// rebuild Extrusion2 was a join with nothing to join to: "FAIL Extrusion2
  /// ... To needs an existing body", and a recompute that froze the part's
  /// projections. Last first, every intermediate state is one that builds.
  /// Anything that is not a delete keeps its place; so does a run with a
  /// delete naming a feature that does not exist, which then fails where the
  /// model put it.
  @visibleForTesting
  static List<AiAction> deletesLastFirst(PartModel p, List<AiAction> batch) {
    int at(AiAction a) {
      final n = a.text('feature');
      return n == null ? -1 : p.features.indexWhere((f) => f.name == n);
    }

    final out = <AiAction>[];
    var i = 0;
    while (i < batch.length) {
      if (batch[i].op != 'delete_feature') {
        out.add(batch[i++]);
        continue;
      }
      var j = i;
      while (j < batch.length && batch[j].op == 'delete_feature') {
        j++;
      }
      final run = batch.sublist(i, j);
      if (run.length > 1 && run.every((a) => at(a) >= 0)) {
        run.sort((x, y) => at(y).compareTo(at(x)));
      }
      out.addAll(run);
      i = j;
    }
    return out;
  }

  /// #90 — "mach solid 2 unsichtbar". The assistant had no way to hide
  /// anything, said so, and the conversation ended in delete_feature on a
  /// body the user only wanted out of the way.
  Future<AiActionOutcome> _setVisible(PartModel p, AiAction a) async {
    final raw = a.args['visible'];
    final bool show;
    if (raw is bool) {
      show = raw;
    } else if (raw == 'true' || raw == 'false') {
      show = raw == 'true';
    } else {
      return AiActionOutcome.failed(
          a.op, 'visible: true or false is required');
    }
    final body = a.text('body'), name = a.text('feature');
    if ((body == null) == (name == null)) {
      return AiActionOutcome.failed(
          a.op, 'name exactly one of body or feature');
    }
    if (body != null) {
      final n = await app.setBodyVisible(p, body, show);
      if (n < 0) {
        return AiActionOutcome.failed(a.op,
            'no body named "$body" — the bodies are ${p.bodyNames.join(", ")}');
      }
      app.aiNotify();
      return AiActionOutcome(a.op, detail: {
        'body': body,
        'visible': show,
        'features': [
          for (final f in p.features)
            if (f.bodyName == body) f.name
        ],
      });
    }
    final f = _feature(p, name!);
    if (f == null) {
      return AiActionOutcome.failed(a.op, 'no feature named "$name"');
    }
    if (f.visible != show) {
      f.visible = show;
      p.dirty = true;
      final tab = app.curTab;
      if (tab != null) await app.savePart(tab);
    }
    app.aiNotify();
    return AiActionOutcome(a.op, detail: {'feature': f.name, 'visible': show});
  }

  Future<AiActionOutcome> _renameFeature(PartModel p, AiAction a) async {
    final name = a.text('feature'), to = a.text('name');
    if (name == null || to == null) {
      return AiActionOutcome.failed(a.op, 'feature and name are required');
    }
    final f = _feature(p, name);
    if (f == null) return AiActionOutcome.failed(a.op, 'no feature named "$name"');
    if (p.features.any((g) => !identical(g, f) && g.name == to)) {
      return AiActionOutcome.failed(a.op, '"$to" is already taken');
    }
    if (!app.renameFeature(f, to)) {
      return AiActionOutcome.failed(a.op, 'the rename was refused');
    }
    return AiActionOutcome(a.op, detail: {'feature': to, 'wasNamed': name});
  }

  // ---- inspection: reading the shape, never changing it -----------------

  /// The digest of a named body, or of the largest one.
  ShapeDigest? _digestOf(PartModel p, AiAction a) {
    final named = a.text('body');
    if (named != null) return digests.of(p, named, app.partKernel);
    final all = digests.all(p, app.partKernel);
    return all.isEmpty ? null : all.first;
  }

  AiActionOutcome _describeShape(PartModel p, AiAction a) {
    final d = _digestOf(p, a);
    if (d == null) {
      return AiActionOutcome.failed(a.op,
          p.bodyNames.isEmpty
              ? 'this part has no built body to describe'
              : 'no body "${a.text('body')}" (have: ${p.bodyNames.join(", ")})');
    }
    final detail = (a.text('detail') ?? 'digest').toLowerCase();
    return switch (detail) {
      'sections' => AiActionOutcome(a.op, detail: {
          'body': d.body,
          'axis': d.sectionAxis,
          'sections': [
            for (final s in d.sections)
              {
                'at': _r(s.at),
                'loops': s.loops,
                'width': _r(s.width),
                'height': _r(s.height),
                'areaMm2': _r(s.area)
              }
          ],
          'method': 'plane/triangle intersection on the tessellation (±0.1 mm)',
        }),
      'faces' => AiActionOutcome(a.op, detail: {
          'body': d.body,
          'faceCount': d.faces.length,
          'faces': _faceRows(p, d, _rank(d.faces).take(20)),
          if (d.faces.length > 20) 'omitted': d.faces.length - 20,
        }),
      _ => AiActionOutcome(a.op,
          detail: {'body': d.body, 'shape': d.toText()}),
    };
  }

  /// Largest first. An assistant reading a truncated list should see the faces
  /// that matter, not the ones that happened to be indexed first.
  List<DigestFace> _rank(List<DigestFace> faces) =>
      [...faces]..sort((x, y) => y.area.compareTo(x.area));

  /// #89 — a face row a model can picture without arithmetic. A centroid,
  /// a normal and an area left it reconstructing every face ("F6 at y=334
  /// pointing down with area 3100 — that's odd … confusing") across 43 000
  /// characters of one round. Where the face actually runs, and which feature
  /// made it, are two short strings the app already knows.
  List<Map<String, dynamic>> _faceRows(
      PartModel p, ShapeDigest d, Iterable<DigestFace> faces) {
    final solid = currentBodySolid(p, d.body);
    final spans = <int, FaceSurface>{
      if (solid != null)
        for (final s in faceSurfaces(solid.mesh)) s.id: s
    };
    final maker =
        solid == null ? const <int, String>{} : attributeFaces(p, d.body, solid);
    return [
      for (final f in faces)
        {
          'face': 'F${f.id}',
          'type': faceTypeName(f.type),
          if (f.type == kFacePlane && axisName(f.dir) != null)
            'facing': axisName(f.dir),
          if (f.radius > 0) 'diameter': _r(f.diameter),
          'areaMm2': _r(f.area),
          if (spans[f.id] != null) 'spans': faceSpan(spans[f.id]!.lo, spans[f.id]!.hi),
          if (maker[f.id] != null) 'madeBy': maker[f.id],
          'at': [_r(f.centroid.x), _r(f.centroid.y), _r(f.centroid.z)],
          'dir': [_r(f.dir.x), _r(f.dir.y), _r(f.dir.z)],
          if (f.type != kFacePlane) 'concave': f.concave,
          if (f.tangent) 'blend': true,
        }
    ];
  }

  static const _faceTypes = {
    'plane': kFacePlane,
    'cylinder': kFaceCylinder,
    'cone': kFaceCone,
    'sphere': kFaceSphere,
    'torus': kFaceTorus,
  };

  AiActionOutcome _facesWhere(PartModel p, AiAction a) {
    final d = _digestOf(p, a);
    if (d == null) {
      return AiActionOutcome.failed(a.op, 'this part has no built body');
    }
    var picked = _rank(d.faces);
    final type = a.text('type')?.toLowerCase();
    if (type != null) {
      final want = _faceTypes[type];
      if (want == null) {
        return AiActionOutcome.failed(
            a.op, 'type must be one of ${_faceTypes.keys.join(", ")}');
      }
      picked = [for (final f in picked) if (f.type == want) f];
    }
    final dia = a.number('diameter');
    if (dia != null) {
      picked = [
        for (final f in picked)
          if ((f.diameter - dia).abs() < 0.01) f
      ];
    }
    final minArea = a.number('min_area');
    if (minArea != null) {
      picked = [for (final f in picked) if (f.area >= minArea) f];
    }
    // ISSUES #74 AND #75 — "du hast den haken an der Seite nicht oben
    // gemacht", and it was still wrong after being told.
    //
    // `axis` compared |dot| > 0.99, so "+y" matched the TOP face and the
    // BOTTOM one equally. A model asking for the top of a holder got both and
    // had no way to tell them apart, which is exactly how a hook meant to
    // point up ends up on the far side. The sign is honoured now, and "top"
    // says it in the words the user used.
    final where = a.text('where')?.toLowerCase();
    final axis = a.text('axis')?.toLowerCase() ??
        switch (where) {
          'top' || 'up' => '+y',
          'bottom' || 'down' || 'base' => '-y',
          'right' => '+x',
          'left' => '-x',
          'front' => '+z',
          'back' || 'rear' => '-z',
          _ => null,
        };
    if (where != null && axis == null) {
      return AiActionOutcome.failed(
          a.op, 'where must be top, bottom, left, right, front or back');
    }
    if (axis != null) {
      final want = switch (axis) {
        'x' || '+x' || '-x' => const Vec3(1, 0, 0),
        'y' || '+y' || '-y' => const Vec3(0, 1, 0),
        'z' || '+z' || '-z' => const Vec3(0, 0, 1),
        _ => null,
      };
      if (want == null) {
        return AiActionOutcome.failed(a.op, 'axis must be x, y or z');
      }
      final signed = axis.startsWith('-')
          ? -1
          : axis.startsWith('+')
              ? 1
              : 0;
      picked = [
        for (final f in picked)
          if (signed == 0
              ? f.dir.dot(want).abs() > 0.99
              : f.dir.dot(want) * signed > 0.99)
            f
      ];
    }
    final near = a.args['near'];
    if (near is List && near.length >= 3) {
      final xs = [for (final v in near) if (v is num) v.toDouble()];
      if (xs.length >= 3) {
        final at = Vec3(xs[0], xs[1], xs[2]);
        picked = [...picked]
          ..sort((x, y) =>
              (x.centroid - at).length.compareTo((y.centroid - at).length));
      }
    }
    final limit = (a.number('limit') ?? 20).clamp(1, 20).toInt();
    return AiActionOutcome(a.op, detail: {
      'body': d.body,
      'matched': picked.length,
      'faces': _faceRows(p, d, picked.take(limit)),
      if (picked.length > limit) 'omitted': picked.length - limit,
    });
  }

  /// A face named as `F<id>`, resolved against the CURRENT digest.
  (DigestFace?, String?) _face(PartModel p, AiAction a, String key) {
    final d = _digestOf(p, a);
    if (d == null) return (null, 'this part has no built body');
    final name = a.text(key);
    if (name == null) return (null, '$key is required, as a face id like "F3"');
    final id = int.tryParse(name.replaceFirst(RegExp('^[Ff]'), ''));
    if (id == null) return (null, '"$name" is not a face id');
    for (final f in d.faces) {
      if (f.id == id) return (f, null);
    }
    return (
      null,
      'no face $name on ${d.body} (it has ${d.faces.length} faces; '
          'use faces_where to find one)'
    );
  }

  AiActionOutcome _measure(PartModel p, AiAction a) {
    final (from, e1) = _face(p, a, 'from');
    if (from == null) return AiActionOutcome.failed(a.op, e1!);
    final (to, e2) = _face(p, a, 'to');
    if (to == null) return AiActionOutcome.failed(a.op, e2!);
    final delta = to.centroid - from.centroid;
    final dot = from.dir.dot(to.dir).clamp(-1.0, 1.0);
    final angle = math.acos(dot) * 180 / math.pi;
    final parallel = dot.abs() > 0.999;
    return AiActionOutcome(a.op, detail: {
      'from': 'F${from.id}',
      'to': 'F${to.id}',
      'centroidDistanceMm': _r(delta.length),
      'angleDeg': _r(angle),
      if (parallel && from.type == kFacePlane && to.type == kFacePlane)
        'planeSeparationMm': _r(delta.dot(from.dir).abs()),
      'method': 'centroids and normals from the tessellation (±1%); '
          'a plane separation is exact where both faces are planar',
    });
  }

  AiActionOutcome _section(PartModel p, AiAction a) {
    final d = _digestOf(p, a);
    if (d == null) {
      return AiActionOutcome.failed(a.op, 'this part has no built body');
    }
    final axisName = (a.text('axis') ?? d.sectionAxis).toLowerCase();
    final axis = switch (axisName) {
      'x' => 0,
      'y' => 1,
      'z' => 2,
      _ => -1,
    };
    if (axis < 0) {
      return AiActionOutcome.failed(a.op, 'axis must be x, y or z');
    }
    final solid = currentBodySolid(p, d.body);
    if (solid == null) {
      return AiActionOutcome.failed(a.op, 'body "${d.body}" has no geometry');
    }
    final profiles = sectionProfiles(solid.mesh, axis, d.min, d.max);
    if (profiles.isEmpty) {
      return AiActionOutcome.failed(
          a.op, 'the plane met no geometry — check the axis and position');
    }
    final at = a.number('at');
    final chosen = at == null
        ? profiles
        : [
            (profiles..sort((x, y) =>
                    (x.at - at).abs().compareTo((y.at - at).abs())))
                .first
          ];
    return AiActionOutcome(a.op, detail: {
      'body': d.body,
      'axis': axisName.toUpperCase(),
      'sections': [
        for (final s in chosen)
          {
            'at': _r(s.at),
            'loops': s.loops,
            'width': _r(s.width),
            'height': _r(s.height),
            'areaMm2': _r(s.area)
          }
      ],
      'method': 'plane/triangle intersection on the tessellation (±0.1 mm)',
    });
  }

  // ---- direct editing: bodies with no feature tree -----------------------

  Future<AiActionOutcome> _faceEdit(PartModel p, AiAction a) async {
    final (face, err) = _face(p, a, 'face');
    if (face == null) return AiActionOutcome.failed(a.op, err!);
    if (face.topoId <= 0) {
      return AiActionOutcome.failed(a.op,
          'the kernel did not supply a topological id for F${face.id}, so it '
          'cannot be addressed — this build\'s shim is too old for face edits');
    }
    final d = _digestOf(p, a)!;
    final body = d.body;
    final base = currentBodySolid(p, body);
    if (base == null) {
      return AiActionOutcome.failed(a.op, 'body "$body" has no geometry');
    }
    final isDelete = a.op == 'delete_face';
    // M458 — DirectEdit has three modes and the assistant could reach one.
    // "size" resizes a cylindrical or spherical face to a new radius, which
    // is how a hole's diameter is changed on a body with no feature tree —
    // an imported STEP part, exactly the case direct editing exists for.
    final isSize = a.op == 'size_face';
    // DirectOp.scale resizes the WHOLE body about its centre — the third of
    // the three direct-edit modes, and the one that turns an imported part
    // that came in as inches into one that is millimetres.
    final isScale = a.op == 'scale_body';
    final factor = a.number('factor');
    if (isScale && (factor == null || factor <= 0)) {
      return AiActionOutcome.failed(a.op, 'factor must be > 0');
    }
    final distance = isDelete ? 0.0 : a.number('distance');
    final radius = a.number('radius') ??
        (a.number('diameter') == null ? null : a.number('diameter')! / 2);
    if (isSize) {
      if (radius == null || radius <= 0) {
        return AiActionOutcome.failed(
            a.op, 'radius (or diameter) must be > 0');
      }
      if (face.radius <= 0) {
        return AiActionOutcome.failed(
            a.op,
            'F${face.id} is a ${faceTypeName(face.type)} and has no radius to '
            'size — size_face takes a cylinder, cone or sphere');
      }
    } else if (!isDelete && !isScale && (distance == null || distance == 0)) {
      return AiActionOutcome.failed(a.op, 'distance is required and non-zero');
    }
    // A FacePick is the same "remember the geometry, re-find the index"
    // fingerprint the viewport's own picking produces, so a face the agent
    // names resolves after a rebuild exactly as a tapped one does.
    final pick = FacePick(face.centroid.x, face.centroid.y, face.centroid.z,
        face.dir.x, face.dir.y, face.dir.z, face.area, face.type);
    final f = isDelete
        ? DeleteFaceFeature(
            name: p.nextFeatureName('Delete Face'),
            bodyName: body,
            faces: [pick],
          )
        : isScale
            ? DirectEditFeature(
                name: p.nextFeatureName('Scale'),
                bodyName: body,
                faces: [pick],
                op: DirectOp.scale,
                dx: 0,
                dy: 0,
                dz: 0,
                factor: factor!,
              )
        : isSize
            ? DirectEditFeature(
                name: p.nextFeatureName('Size'),
                bodyName: body,
                faces: [pick],
                op: DirectOp.size,
                // The kernel takes the CHANGE in radius, the way the panel's
                // own drag does; the model says what it wants the radius to
                // be, which is the thing it actually knows.
                dx: radius! - face.radius,
                dy: 0,
                dz: 0,
              )
        // Direct edit moves faces by a WORLD delta, not by a scalar. Along the
        // face's own normal is what "offset this face by 2 mm" means, and it
        // is the only reading that does not need a direction argument.
        : DirectEditFeature(
            name: p.nextFeatureName('Direct'),
            bodyName: body,
            faces: [pick],
            op: DirectOp.move,
            dx: face.dir.x * distance!,
            dy: face.dir.y * distance,
            dz: face.dir.z * distance,
          );
    return _commitFeature(p, a, f, base, {
      'body': body,
      'face': 'F${face.id}',
      if (!isDelete) 'distance': _r(distance!),
    });
  }

  Future<AiActionOutcome> _sketchOnFace(PartModel p, AiAction a) async {
    final (face, err) = _face(p, a, 'face');
    if (face == null) return AiActionOutcome.failed(a.op, err!);
    if (face.type != kFacePlane) {
      return AiActionOutcome.failed(a.op,
          'F${face.id} is a ${faceTypeName(face.type)}; a sketch needs a '
          'planar face');
    }
    if (p.childSketches.length >= 200) {
      return AiActionOutcome.failed(a.op, 'this part already has 200 sketches');
    }
    // The app's own face-to-sketch frame, so the agent's sketch sits on the
    // face the same way a tapped one does.
    final frame = faceFrame(face.centroid, face.dir);
    final (name, nameWhy) = _newSketchName(p, a);
    if (name == null) return AiActionOutcome.failed(a.op, nameWhy!);
    final sketch = SketchModel(name);
    sketch.insertLayerAboveMarker(_layerName);
    p.appendChildSketch(ChildSketch(
        sketch, kWorkPlaneKey, frame, true, false, p.nextSeq()));
    _madeSketches.add('${p.name}/${sketch.name}');
    app.aiAdmitSketchRow(p);
    Log.i('ai', 'sketch "${sketch.name}" on face F${face.id} of "${p.name}"');
    return AiActionOutcome(a.op, detail: {
      'sketch': sketch.name,
      'face': 'F${face.id}',
      'origin': [
        _r(face.centroid.x),
        _r(face.centroid.y),
        _r(face.centroid.z)
      ],
      'normal': [_r(face.dir.x), _r(face.dir.y), _r(face.dir.z)],
      'note': 'sketch coordinates are in the face plane, origin at the point '
          'above. The sketch is pinned to that frame and does not follow the '
          'face if the body changes underneath it.',
      // ISSUE #82 — "+X follows the frame the app built for it" told the model
      // that a mapping exists without telling it what the mapping is. Say it.
      'axes': frameAxisNote(frame),
    });
  }

  // ---- the brief: what the shape cannot tell anyone ---------------------

  /// Records or closes a requirement for the document in focus.
  ///
  /// Deliberately outside the part transaction. A requirement is something the
  /// USER said; rolling it back because a later extrusion failed would throw
  /// away the one thing in the block that was not the app's to lose.
  AiActionOutcome _brief(AiAction a) {
    final controller = app.ai;
    final documentId = controller.document.id;
    if (a.op == 'brief_done') {
      final id = a.text('id');
      if (id == null) return AiActionOutcome.failed(a.op, 'id is required');
      final done = controller.briefs.markDone(documentId, id);
      if (done == null) {
        return AiActionOutcome.failed(
            a.op, 'no requirement "$id" on this document');
      }
      controller.briefChanged();
      return AiActionOutcome(a.op, detail: {'done': id, 'text': done.text});
    }
    final text = a.text('text');
    if (text == null) {
      return AiActionOutcome.failed(a.op, 'text is required');
    }
    if (text.length > kAiRequirementMaxLength) {
      return AiActionOutcome.failed(
          a.op, 'a requirement is at most $kAiRequirementMaxLength characters');
    }
    final source = a.text('source');
    if (source != null && source.length > kAiRequirementMaxLength) {
      return AiActionOutcome.failed(a.op,
          'source is the user\'s own words and is at most '
          '$kAiRequirementMaxLength characters');
    }
    try {
      final made = controller.briefs.add(
          documentId,
          AiRequirement(
              text: text,
              kind: aiRequirementKindFrom(a.text('kind')),
              source: source));
      controller.briefChanged();
      return AiActionOutcome(a.op,
          detail: {'id': made.id, 'kind': made.kind.name, 'text': made.text});
    } on AiException {
      return AiActionOutcome.failed(
          a.op, 'this document already holds $kAiMaxRequirements requirements');
    }
  }

  // ---- looking ----------------------------------------------------------

  /// Renders the part from a direction the model chooses.
  ///
  /// It answers less precisely than a digest and costs more, so sizes never
  /// come from it. Since #89 it answers the question the digest cannot answer
  /// at a glance — WHICH face is which — because every view is labelled with
  /// the face ids the ops take (see ai_view_marks.dart).
  ///
  /// The angles are the model's to choose, which is the difference between
  /// looking and being shown a contact sheet: it can orbit to the thing it
  /// cannot resolve rather than take six fixed views and hope one helps.
  Future<AiActionOutcome> _look(PartModel p, AiAction a) async {
    if (_views.length >= 2) {
      return AiActionOutcome.failed(
          a.op, 'at most two views per block — read them, then ask again');
    }
    final digest = _digestOf(p, a);
    if (digest == null) {
      return AiActionOutcome.failed(a.op, 'this part has no built body to look at');
    }
    // Defaults are the app's own gallery corner: the view a person gets when
    // they open the document, and the one most likely to mean something.
    final az = a.number('az') ?? 45;
    // ISSUES #73 AND #77 — "pol must be between 0 and 180" was refused twice,
    // both times for pol 0: the view from straight above, which is the single
    // most useful one for checking a footprint. The basis degenerates exactly
    // AT the pole because up and the view direction become parallel, and the
    // app's own plane views have always handled that by nudging a thousandth
    // of a radian off it (planeCameraTarget). Refusing the request instead
    // made the model spend a round discovering a rule it could not have
    // guessed, and then settle for an oblique view of a flat face.
    final asked = a.number('pol') ?? 55;
    final pol = asked.clamp(0.06, 179.94);
    if (!asked.isFinite) {
      return AiActionOutcome.failed(a.op, 'pol must be a number');
    }
    final size = ((a.number('size') ?? 512).clamp(256, 768)).toInt();

    // ISSUE #72 — THE VIEW THE MODEL CAN ALWAYS READ.
    //
    // The PNG below reaches Gemini and Claude. It does not reach Apple's
    // on-device model or DeepSeek, and on those the whole op used to be a
    // no-op dressed as a success: a picture was rendered, dropped, and the
    // model was told it had not seen it. This is the same projection as a
    // grid of characters, so `look` means the same thing on every provider.
    final solid = _solidFor(p, a);
    final text = solid == null
        ? null
        : renderTextView(solid.mesh.positions, solid.mesh.indices,
            azRad: az * math.pi / 180, polRad: pol * math.pi / 180);

    final png = await app.aiRenderView(
      azRad: az * math.pi / 180,
      polRad: pol * math.pi / 180,
      rollRad: (a.number('roll') ?? 0) * math.pi / 180,
      width: size,
      height: size,
      annotate: _labeller(p, a),
    );
    AiAttachment? image;
    if (png != null && png.isNotEmpty) {
      try {
        image = AiAttachment.fromBytes(
            name: 'view-az${az.round()}-pol${pol.round()}.png', bytes: png);
        _views.add(image);
      } on AiException {
        image = null; // The text view still stands on its own.
      }
    }
    if (image == null && text == null) {
      return AiActionOutcome.failed(a.op,
          'no renderer produced a view on this device — work from '
          'describe_shape and section instead');
    }
    return AiActionOutcome(a.op, detail: {
      if (image != null) 'view': image.name,
      'azDeg': _r(az),
      'polDeg': _r(pol),
      if ((pol - asked).abs() > 1e-9)
        'polNote': 'pol ${_r(asked)} is exactly along the up axis, where a '
            'view has no orientation; this is ${_r(pol)}, a hair off it.',
      if (image != null) 'pixels': size,
      'projection': 'orthographic',
      // An image with no scale is a picture; with one it is a measurement you
      // can sanity-check. The digest's bbox is that scale.
      'scaleNote': 'orthographic and framed to the body, whose bounding box is '
          '${_mm(digest.size.x)} × ${_mm(digest.size.y)} × '
          '${_mm(digest.size.z)} mm',
      if (text != null) 'silhouette': text.toText(),
      if (_seen.isNotEmpty) 'facesInView': _seenLine(),
      'note': image != null && _seenDrawn
          ? _kLabelNote
          : 'Describe only what is visible. Read dimensions from '
              'describe_shape, never off this image.',
    });
  }

  /// ISSUE #82 — one reference document, by id.
  ///
  /// The documents matching the user's request are already in the prompt
  /// before the first round (see [AiKnowledge]); this is for the one the model
  /// decides it wants afterwards, which is the case `knowledge/README.md`
  /// always meant by "opened on demand". Read-only, so it costs a block slot
  /// and nothing else — and it belongs in the same block as real work, never
  /// in a block of its own.
  AiActionOutcome _knowledge(AiAction a) {
    final kb = knowledge;
    if (kb == null || kb.isEmpty) {
      return AiActionOutcome.failed(a.op, 'no knowledge base is loaded');
    }
    final id = a.text('id')?.trim();
    if (id == null || id.isEmpty) {
      return AiActionOutcome.failed(
          a.op, 'knowledge needs an "id" from the menu in the instructions');
    }
    final doc = kb.byId(id);
    if (doc == null) {
      // Naming the near misses turns a typo into a fix instead of a dead end.
      final near = [
        for (final d in kb.documents)
          if (d.id.contains(id) || id.contains(d.id.split('/').last)) d.id
      ].take(4).toList();
      return AiActionOutcome.failed(
          a.op,
          'no document "$id"${near.isEmpty ? "" : " — did you mean "
              "${near.join(", ")}?"}');
    }
    return AiActionOutcome(a.op, detail: {
      'id': doc.id,
      'title': doc.title,
      'confidence': doc.confidence,
      'document': doc.body,
    });
  }

  /// The solid a view or a measurement is about — the named body, or the one
  /// the last solid feature built.
  KernelSolid? _solidFor(PartModel p, AiAction a) {
    final named = a.text('body');
    final body = named ??
        (p.bodyNames.isEmpty ? null : lastSolidFeature(p)?.bodyName);
    return body == null ? null : currentBodySolid(p, body);
  }

  // ---- commit + report --------------------------------------------------

  /// Builds [f], adds it to the timeline, and reports what the KERNEL said.
  ///
  /// A feature that does not compute is never added: an agent that could leave
  /// broken rows behind would accumulate them, and the user would inherit a
  /// timeline nobody can rebuild. The one exception is a build with no kernel
  /// linked at all (the desktop host), where the parameters are stored
  /// honestly and the report says exactly that rather than claiming geometry.
  Future<AiActionOutcome> _commitFeature(PartModel p, AiAction a, PartFeature f,
      KernelSolid? base, Map<String, dynamic> detail) async {
    final id = a.text('id');
    if (id != null) {
      if (!RegExp(r'^[A-Za-z0-9_][A-Za-z0-9_ \-]{0,39}$').hasMatch(id)) {
        return AiActionOutcome.failed(a.op,
            'id must be 1-40 letters, digits, spaces, _ or -');
      }
      final existing = _feature(p, id);
      if (existing != null) return _replaceFeature(p, a, existing, f, detail);
      f.name = id;
    }
    final ok = recomputeFeature(p, f, app.partKernel, base: base);
    if (!ok && app.partKernel.available) {
      f.disposeSolid();
      final why = f.computeError ?? app.partKernel.lastError;
      return AiActionOutcome.failed(
          a.op, '${f.typeLabel} did not build: $why${_remedyFor(why)}');
    }
    final twisted = _invalidSolid(f);
    if (twisted != null) {
      f.disposeSolid();
      return AiActionOutcome.failed(a.op, twisted);
    }
    // The body as it was, measured BEFORE the feature joins the fold: for an
    // extrude, the feature's own solid is only the tool, and the boolean with
    // the body happens in the rebuild below.
    final baseVolume = base?.volume;
    final basePieces = base == null ? 0 : meshComponentCount(base.mesh);
    f.seq = p.nextSeq();
    p.appendFeature(f);
    _madeAt[f.name] = _blockNo; // #83 — so a later delete can be recognised
    applyEndOfPart(p);
    // Inventor consumes the sketch into the feature that first uses it.
    if (f.sketchName.isNotEmpty && consumersOf(p, f.sketchName).length == 1) {
      p.sketchByName(f.sketchName)?.visible = false;
    }
    app.aiRebuild(p);
    // The feature's own solid built, but joining it to the body happens in
    // the rebuild — and a boolean can fail there. That used to be reported
    // as "ok" with a sick feature left in the timeline (#87: a handle whose
    // fuse failed, and a body that quietly became only the handle).
    final foldError = f.computeError;
    final wrong = foldError != null
        ? '${f.typeLabel} built on its own, but combining it with the body '
            'failed: $foldError${_remedyFor(foldError)} — often a surface '
            'that just touches another, or ends that meet a wall at a '
            'grazing angle. Overlap the new material into the body by a '
            'millimetre or more, or move it so it meets the body squarely.'
        : _geometryVerdict(p, f, baseVolume, basePieces);
    if (wrong != null) {
      // Out again, and the part rebuilt without it; the block's rollback
      // restores anything else this step touched.
      p.features.remove(f);
      _madeAt.remove(f.name);
      f.disposeSolid();
      app.aiRebuild(p);
      return AiActionOutcome.failed(a.op, wrong);
    }
    final change = _volumeChange(p, f, baseVolume);
    Log.i('ai', '${f.kind} "${f.name}" created on "${p.name}" ok=$ok');
    return AiActionOutcome(a.op, detail: {
      'feature': f.name,
      'body': f.bodyName,
      ...detail,
      if (!app.partKernel.available)
        'note': 'No 3D kernel is linked in this build, so the feature is '
            'stored with its parameters but carries no geometry yet.',
      ...?_bodyFacts(p, f.bodyName),
      ...?change,
    });
  }

  /// ISSUE #83 — "built four times, deleted four times". An `id` names a
  /// feature, and naming one that exists REPLACES it where it stands in the
  /// timeline: same position, same body, everything after it rebuilt on top
  /// of the new version. That is what the model was trying to do with
  /// delete_feature and a rebuild, except that the rebuild always landed at
  /// the END — after the blends and holes that depended on it — and every
  /// cycle cost a round trip. Now it is one action, and it cannot duplicate.
  Future<AiActionOutcome> _replaceFeature(PartModel p, AiAction a,
      PartFeature old, PartFeature f, Map<String, dynamic> detail) async {
    final at = p.features.indexOf(old);
    if (at < 0) return AiActionOutcome.failed(a.op, 'feature vanished');
    // A new body replacing a new body keeps its name, so the features that
    // were built on it still find it.
    if (!f.modifiesBody && f.output == 'new' && old.output == 'new') {
      f.bodyName = old.bodyName;
    } else if (a.text('body') == null && f.bodyName != old.bodyName) {
      f.bodyName = old.bodyName;
    }
    f.name = old.name;
    f.seq = old.seq;
    final oldSketch = old.sketchName;
    old.disposeSolid();
    p.features[at] = f;
    app.aiRebuild(p);
    final broken = [
      for (final g in p.features.skip(at))
        if (!g.rolledBack && g.computeError != null) g
    ];
    if (broken.isNotEmpty || (app.partKernel.available && f.solid == null)) {
      // The block's rollback restores the old version; say what broke.
      final first = broken.isEmpty ? f : broken.first;
      return AiActionOutcome.failed(
          a.op,
          identical(first, f)
              ? 'the new version of "${f.name}" did not build: '
                  '${f.computeError ?? app.partKernel.lastError}'
              : 'the new "${f.name}" built, but "${first.name}" after it no '
                  'longer does: ${first.computeError}');
    }
    // The sketch the old version was drawn on is nobody's any more.
    if (oldSketch.isNotEmpty &&
        oldSketch != f.sketchName &&
        consumersOf(p, oldSketch).isEmpty &&
        _madeSketches.contains('${p.name}/$oldSketch')) {
      p.childSketches.removeWhere((cs) => cs.model.name == oldSketch);
    }
    if (f.sketchName.isNotEmpty && consumersOf(p, f.sketchName).length == 1) {
      p.sketchByName(f.sketchName)?.visible = false;
    }
    _madeAt[f.name] = _blockNo;
    Log.i('ai', '${f.kind} "${f.name}" replaced in place on "${p.name}"');
    return AiActionOutcome(a.op, detail: {
      'feature': f.name,
      'replaced': true,
      'body': f.bodyName,
      ...detail,
      'note': 'The earlier "${f.name}" was replaced where it stood in the '
          'timeline; everything after it was rebuilt on the new one.',
      ...?_bodyFacts(p, f.bodyName),
    });
  }

  /// Sketches this executor created, as "part/sketch" — only these may be
  /// tidied away when the feature that consumed them is replaced.
  final Set<String> _madeSketches = {};

  /// Why a feature that BUILT is still wrong, measured on its result — or
  /// null when it is fine.
  ///
  /// Two failures the kernel reports as successes, and which #82 shipped:
  /// a cut that removes nothing (the countersink placed in open air still
  /// "builds"), and a join whose new material does not touch the body (the
  /// clamp "joined" while floating). Both leave a feature in the timeline
  /// that does nothing or does harm, and the model reads "ok" and moves on.
  String? _invalidSolid(PartFeature f) {
    final after = f.solid;
    if (after == null || !app.partKernel.available) return null;
    // ISSUE #84 — a sweep whose profile was not square to its path "built",
    // and every blend on the part then failed for eight rounds before the
    // model worked out why. Sweeps, lofts and coils are where a body can
    // come back self-intersecting; the kernel's checker says so at once.
    // Only these three: a boolean or a blend result can fail the strict
    // checker and still be a perfectly usable part.
    if ((f is SweepFeature || f is LoftFeature || f is CoilFeature) &&
        after.shape != null &&
        !after.shape!.valid) {
      return '${f.typeLabel} built a solid that is not valid — it twists '
          'through itself. For a sweep, the profile must sit at the START '
          'of the path, square to it: use profile_circle (the app places '
          'it for you), or draw the profile on the plane whose normal is '
          'the path\'s start direction.';
    }
    return null;
  }

  /// Why a feature that BUILT is still wrong, measured on the body after it
  /// joined the fold — or null when it is fine.
  ///
  /// Two failures the kernel reports as successes, and which #82 shipped:
  /// a cut that removes nothing (the countersink placed in open air still
  /// "builds"), and a join whose new material does not touch the body (the
  /// clamp "joined" while floating). Both leave a feature in the timeline
  /// that does nothing or does harm, and the model reads "ok" and moves on.
  String? _geometryVerdict(
      PartModel p, PartFeature f, double? baseVolume, int basePieces) {
    if (baseVolume == null || !app.partKernel.available) return null;
    final after = currentBodySolid(p, f.bodyName);
    if (after == null) return null;
    final removes = f is HoleFeature ||
        (!f.modifiesBody && f.output == 'cut');
    if (removes) {
      final removed = baseVolume - after.volume;
      if (removed.abs() <= math.max(1e-6, baseVolume * 1e-9)) {
        return '${f.typeLabel} removed no material — the tool does not '
            'reach the body. Read `extentMm` and put the profile where the '
            'body is (sk.cx, sk.cy are its middle in this sketch), or check '
            'the direction: a cut from a sketch ON a face goes into the part '
            'only when it points inward.';
      }
      return null;
    }
    if (!f.modifiesBody && f.output == 'join') {
      if (meshComponentCount(after.mesh) > basePieces) {
        return '${f.typeLabel} built, but its material does not touch the '
            'body it joins — it would float as a separate piece. Move it '
            'onto the body (read `extentMm`; sk.* anchors give the body\'s '
            'edges in this sketch), or use operation "new" if a separate '
            'body is really what you want.';
      }
    }
    return null;
  }

  /// How much material a feature added or removed, for the report.
  Map<String, dynamic>? _volumeChange(
      PartModel p, PartFeature f, double? baseVolume) {
    if (baseVolume == null || !app.partKernel.available) return null;
    if (f.output == 'new' && !f.modifiesBody) return null;
    final after = currentBodySolid(p, f.bodyName);
    if (after == null) return null;
    final d = after.volume - baseVolume;
    return {d >= 0 ? 'addedMm3' : 'removedMm3': _r(d.abs())};
  }

  Map<String, dynamic>? _bodyFacts(PartModel p, String body) {
    final solid = currentBodySolid(p, body);
    if (solid == null) return null;
    return {'volumeMm3': _r(solid.volume)};
  }

  /// What the document says after the block — measured, and the same shape
  /// `describe_part` returns. This is the model's only trustworthy account of
  /// what it just did.
  /// The one-line state that rides on every block.
  ///
  /// ISSUE #72 (follow-up) — the full timeline used to ride on EVERY block,
  /// and every one of those copies stayed in the conversation and was resent
  /// on every later round. Measured on the shaker-holder session: 54,637
  /// input tokens for a plate with two holes, most of it six near-identical
  /// copies of the same feature tree, each one inviting the model to wonder
  /// which of them is current.
  ///
  /// This says what changed and how big the thing is now. The full tree is
  /// one `describe_part` away and is never stale when it arrives.
  Map<String, dynamic> _stateBrief(PartModel p) {
    // Material only: see [_solidBounds] for why a sketch must not move the
    // centre the model places the next feature at.
    final bounds = _solidBounds(p);
    final last = p.features.isEmpty ? null : p.features.last;
    return {
      'name': p.name,
      'features': p.features.length,
      if (last != null) 'newest': '${last.name} (${last.kind})',
      'sketches': p.childSketches.length,
      'bodies': [for (final (name, _) in p.solidBodies()) name],
      // #90 — WHAT each body is. The model read "Solid1" as "the motor" and
      // measured 91 faces of motor plus the boss the user had joined onto it,
      // three rounds of it, without ever knowing which was which.
      'bodyMakeup': {
        for (final (name, fs) in p.solidBodies()) name: _makeup(fs),
      },
      if (bounds != null)
        'sizeMm': [
          _r(bounds.$2.x - bounds.$1.x),
          _r(bounds.$2.y - bounds.$1.y),
          _r(bounds.$2.z - bounds.$1.z)
        ],
      if (bounds != null) 'heightUpYMm': _r(bounds.$2.y - bounds.$1.y),
      // ISSUE #82 — a size does not say where the body IS, and the model that
      // only has a size puts the next feature at the origin. It did, twice, in
      // one session: a countersink 11 mm off centre onto the plate's edge, and
      // a clamp half in open air. The extent and the centre ride on EVERY
      // block now, not only on the describe_shape the model has to remember to
      // ask for — the mistake happens on the block after the first one, which
      // is exactly where no one calls describe_shape.
      if (bounds != null)
        'extentMm': {
          'x': [_r(bounds.$1.x), _r(bounds.$2.x)],
          'y': [_r(bounds.$1.y), _r(bounds.$2.y)],
          'z': [_r(bounds.$1.z), _r(bounds.$2.z)],
        },
      if (bounds != null)
        'centreMm': [
          _r((bounds.$1.x + bounds.$2.x) / 2),
          _r((bounds.$1.y + bounds.$2.y) / 2),
          _r((bounds.$1.z + bounds.$2.z) / 2),
        ],
      if (bounds != null &&
          ((bounds.$1.x + bounds.$2.x).abs() > 1e-2 ||
              (bounds.$1.z + bounds.$2.z).abs() > 1e-2))
        'centreNote': 'This body is NOT centred on the world origin. Put a '
            'centred feature at x=${_r((bounds.$1.x + bounds.$2.x) / 2)}, '
            'z=${_r((bounds.$1.z + bounds.$2.z) / 2)} — sketch (0,0) is '
            'somewhere else on this part.',
      'more': 'describe_part for the timeline, describe_shape for the shape',
    };
  }

  /// One line per body: its features in build order, what each one did to
  /// it, and whether the body is hidden. "Import1 (imported STEP) +
  /// Extrusion3 (extrude join)" is the line that tells a motor from a motor
  /// with a boss on it.
  static String _makeup(List<PartFeature> fs) {
    String one(PartFeature f) {
      final what = f is ExtrudeFeature && f.imported
          ? 'imported STEP'
          : f.modifiesBody
              ? f.kind
              : '${f.kind} ${f.output}';
      return '${f.name} ($what${f.computeError != null ? ', FAILED' : ''})';
    }

    final hidden = fs.isNotEmpty && fs.every((f) => !f.visible);
    return '${fs.map(one).join(' + ')}${hidden ? ' — hidden' : ''}';
  }

  Map<String, dynamic> _state(PartModel p) {
    // #89 — material only, from the B-Rep: one box in every report.
    final bounds = _solidBounds(p);
    return {
      'name': p.name,
      'units': {'length': 'mm', 'angle': 'deg'},
      'sketches': [
        for (final cs in p.childSketches.take(40))
          {
            'name': cs.model.name,
            'plane': cs.plane,
            'entities': cs.model.geometry.length,
            'closedProfiles': app.sessionRegions(cs).length,
          }
      ],
      'features': [
        for (final f in p.features.take(80))
          {
            'name': f.name,
            'type': f.kind,
            'body': f.bodyName,
            if (!f.modifiesBody) 'operation': f.output,
            if (f.sketchName.isNotEmpty) 'sketch': f.sketchName,
            if (f is ExtrudeFeature && f.extent == FeatureExtent.distance)
              'distance': _r(f.distanceA),
            if (f is ExtrudeFeature) 'extent': featureExtentName(f.extent),
            if (f is RevolveFeature) 'angle': _r(f.sweepDeg),
            if (f is FilletFeature && f.radii.isNotEmpty)
              'radius': _r(f.radii.first),
            if (f is ChamferFeature) 'distance': _r(f.distance1),
            if (f.rolledBack) 'rolledBack': true,
            if (f.computeError != null) 'error': f.computeError,
          }
      ],
      'bodies': [
        for (final (name, fs) in p.solidBodies())
          {
            'name': name,
            'makeup': _makeup(fs),
            if (currentBodySolid(p, name) != null)
              'volumeMm3': _r(currentBodySolid(p, name)!.volume),
          }
      ],
      if (bounds != null)
        'boundingBoxMm': {
          'min': [_r(bounds.$1.x), _r(bounds.$1.y), _r(bounds.$1.z)],
          'max': [_r(bounds.$2.x), _r(bounds.$2.y), _r(bounds.$2.z)],
          'size': [
            _r(bounds.$2.x - bounds.$1.x),
            _r(bounds.$2.y - bounds.$1.y),
            _r(bounds.$2.z - bounds.$1.z)
          ],
        },
      'coverage': 'Timeline and measured bounds only. No strength, clearance, '
          'interference or manufacturing check is implied.',
    };
  }

}

/// #93 — whether a full circular edge is the MOUTH of a hole (empty just
/// inside the circle, material just outside) rather than a rim (the other way
/// round). [poly] is the edge's polyline as xyz triples, [radius] its radius.
/// Null when the polyline is not a full circle or the probes disagree.
bool? aiRingIsMouth(OcctMeshData mesh, List<double> poly, double radius) {
  final n = poly.length ~/ 3;
  if (n < 6 || radius <= 0) return null;
  var cx = 0.0, cy = 0.0, cz = 0.0;
  for (var i = 0; i < n; i++) {
    cx += poly[3 * i];
    cy += poly[3 * i + 1];
    cz += poly[3 * i + 2];
  }
  cx /= n;
  cy /= n;
  cz /= n;
  // The circle's axis: the normal of two chords a quarter-turn apart.
  double at(int i, int k) => poly[3 * (i % n) + k];
  final ux = at(0, 0) - cx, uy = at(0, 1) - cy, uz = at(0, 2) - cz;
  final q = n ~/ 4;
  final vx = at(q, 0) - cx, vy = at(q, 1) - cy, vz = at(q, 2) - cz;
  var nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
  final nl = math.sqrt(nx * nx + ny * ny + nz * nz);
  final ul = math.sqrt(ux * ux + uy * uy + uz * uz);
  // Not centred where a circle's points would put it: an arc, not a ring.
  if (nl < 1e-9 || (ul - radius).abs() > radius * 0.1) return null;
  nx /= nl;
  ny /= nl;
  nz /= nl;
  final ex = ux / ul, ey = uy / ul, ez = uz / ul;
  final eps = math.min(0.3, radius * 0.15);
  bool anySide(double r) {
    for (final s in const [1.0, -1.0]) {
      if (aiInsideMesh(mesh, cx + ex * r + nx * eps * s,
          cy + ey * r + ny * eps * s, cz + ez * r + nz * eps * s)) {
        return true;
      }
    }
    return false;
  }

  final inner = anySide(radius - eps), outer = anySide(radius + eps);
  if (!inner && outer) return true;
  if (inner && !outer) return false;
  return null;
}

/// Whether a point is inside a closed triangle mesh: the parity of a ray's
/// crossings, cast along a direction no axis-aligned model lines up with.
bool aiInsideMesh(OcctMeshData mesh, double px, double py, double pz) {
  const dx = 0.5773, dy = 0.5774, dz = 0.5776;
  final p = mesh.positions, idx = mesh.indices;
  var hits = 0;
  for (var t = 0; t + 2 < idx.length; t += 3) {
    final a = idx[t] * 3, b = idx[t + 1] * 3, c = idx[t + 2] * 3;
    final e1x = p[b] - p[a], e1y = p[b + 1] - p[a + 1], e1z = p[b + 2] - p[a + 2];
    final e2x = p[c] - p[a], e2y = p[c + 1] - p[a + 1], e2z = p[c + 2] - p[a + 2];
    final hx = dy * e2z - dz * e2y,
        hy = dz * e2x - dx * e2z,
        hz = dx * e2y - dy * e2x;
    final det = e1x * hx + e1y * hy + e1z * hz;
    if (det.abs() < 1e-12) continue;
    final f = 1 / det;
    final sx = px - p[a], sy = py - p[a + 1], sz = pz - p[a + 2];
    final u = f * (sx * hx + sy * hy + sz * hz);
    if (u < 0 || u > 1) continue;
    final qx = sy * e1z - sz * e1y,
        qy = sz * e1x - sx * e1z,
        qz = sx * e1y - sy * e1x;
    final v = f * (dx * qx + dy * qy + dz * qz);
    if (v < 0 || u + v > 1) continue;
    if (f * (e2x * qx + e2y * qy + e2z * qz) > 1e-9) hits++;
  }
  return hits.isOdd;
}
