/// The CAD actions the assistant may ask the app to perform, and the report it
/// gets back.
///
/// WHY A DECLARED BLOCK AND NOT PROVIDER TOOL CALLING. Four providers reach
/// this app — Apple Intelligence over a method channel, Gemini, Claude and
/// DeepSeek over three different HTTP shapes — and only three of them have a
/// tool-calling wire format at all. A fenced block is one protocol, one parser,
/// one set of limits, and the SAME set of operations on every provider,
/// including the on-device one. It also survives being read back out of the
/// stored conversation, because it is just text.
///
/// WHAT IS NOT HERE. This file parses, validates and reports. It performs
/// nothing: the executor lives next to the document model (`ai_cad.dart`),
/// where the part, the kernel and the undo journal are. Nothing in a model
/// reply is ever evaluated as code — an action is a name from [kAiOps] plus
/// typed arguments, and an unknown name is refused rather than ignored.
library;

import 'dart:convert';

import 'ai_models.dart';

/// Every operation the executor implements. An op outside this set never
/// reaches the document.
const Set<String> kAiOps = {
  'describe_part',
  'describe_shape',
  'faces_where',
  'measure',
  'section',
  'look',
  'delete_face',
  'move_face',
  'sketch_on_face',
  'create_sketch',
  'sketch_rect',
  'sketch_circle',
  'sketch_polygon',
  'sketch_line',
  'extrude',
  'revolve',
  'fillet',
  'chamfer',
  'edit_feature',
  'delete_feature',
  'rename_feature',
  'brief_note',
  'brief_done',
};

/// Ops that only READ. They take no part snapshot, never trigger a rollback,
/// and are not counted as changes in the panel.
///
/// Kept next to [kAiOps] so a new op has to be classified rather than default
/// into being a mutation — which is how a block of pure measurements came to
/// restore the document on its way out.
const Set<String> kAiReadOnlyOps = {
  'describe_part',
  'describe_shape',
  'faces_where',
  'measure',
  'section',
  'look',
};

/// Ops that change the BRIEF rather than the geometry. A recorded requirement
/// must not be rolled back because an extrusion later in the same block
/// failed: it is something the user said, not something the app built.
const Set<String> kAiBriefOps = {'brief_note', 'brief_done'};

/// Actions in one block.
///
/// Was 24, which let a model answer "make me an espresso cup" by planning the
/// entire part and emitting it at once. That is the wrong shape of work for
/// this panel (issue #70): the user waits a minute watching one unchanging
/// word, and if anything goes wrong they get nothing at all rather than the
/// three steps that did succeed.
///
/// Six forces the same part to arrive as a sequence of small blocks, each of
/// which lands in the document, is visible in the browser, and is undoable on
/// its own. It costs more requests — every round resends the conversation —
/// and that is the trade: time-to-first-geometry over total tokens.
const int kAiMaxActionsPerBlock = 6;

/// How many times one `send()` may go model -> actions -> results -> model.
///
/// Raised with the block size cut: six actions a block needs more rounds to
/// build the same part, and stopping at four would leave a cup with no handle.
/// Still bounded — every round is a paid request, and a model that has not
/// converged in ten is not going to.
const int kAiMaxActionRounds = 10;

class AiAction {
  const AiAction(this.op, this.args);
  final String op;
  final Map<String, dynamic> args;

  double? number(String key) {
    final v = args[key];
    if (v is num) return v.isFinite ? v.toDouble() : null;
    // A model that writes "12 mm" means 12 mm. Units other than the document's
    // own are NOT converted here: silently reinterpreting a number is how a
    // part ends up 25.4 times too big with nobody able to say where.
    if (v is String) {
      final m = RegExp(r'^\s*(-?\d+(?:\.\d+)?)\s*(mm)?\s*$').firstMatch(v);
      if (m != null) return double.tryParse(m.group(1)!);
    }
    return null;
  }

  String? text(String key) {
    final v = args[key];
    return v is String && v.trim().isNotEmpty ? v.trim() : null;
  }

  bool flag(String key, {bool fallback = false}) {
    final v = args[key];
    return v is bool ? v : fallback;
  }

  List<List<double>> points(String key) {
    final v = args[key];
    if (v is! List) return const [];
    final out = <List<double>>[];
    for (final p in v) {
      if (p is List && p.length >= 2 && p[0] is num && p[1] is num) {
        final x = (p[0] as num).toDouble(), y = (p[1] as num).toDouble();
        if (x.isFinite && y.isFinite) out.add([x, y]);
      } else if (p is Map && p['x'] is num && p['y'] is num) {
        final x = (p['x'] as num).toDouble(), y = (p['y'] as num).toDouble();
        if (x.isFinite && y.isFinite) out.add([x, y]);
      }
    }
    return out;
  }

  Map<String, dynamic> toJson() => {'op': op, ...args};
}

/// What one action did, or why it did not.
class AiActionOutcome {
  const AiActionOutcome(this.op, {this.ok = true, this.detail, this.error});
  const AiActionOutcome.failed(this.op, String reason)
      : ok = false,
        detail = null,
        error = reason;
  final String op;
  final bool ok;
  final Map<String, dynamic>? detail;
  final String? error;
  Map<String, dynamic> toJson() => {
        'op': op,
        'ok': ok,
        if (detail != null) ...detail!,
        if (error != null) 'error': error,
      };
}

/// The result of one block, as the model sees it and as the composer draws it.
///
/// [reverted] is the part that matters: a batch that fails part-way is rolled
/// back to the state it started from, so the model is never told "step 3 of 5
/// worked" about a document that no longer contains steps 1 and 2.
class AiActionReport {
  AiActionReport(
      {required this.outcomes,
      this.reverted = false,
      this.state,
      this.blocked,
      List<AiAttachment> images = const []})
      : images = List.unmodifiable(images);
  final List<AiActionOutcome> outcomes;

  /// M446 — views the `look` op rendered, to travel back as attachments on the
  /// tool turn. Not part of [toJson]: an image is not text, and base64 in the
  /// report would spend the turn's budget twice.
  final List<AiAttachment> images;
  final bool reverted;
  final Map<String, dynamic>? state;

  /// Set when nothing ran at all — no part open, edits switched off. The
  /// string is a code, not prose: the composer localises it.
  final String? blocked;

  bool get ok => blocked == null && !reverted && outcomes.every((o) => o.ok);
  int get applied => reverted ? 0 : outcomes.where((o) => o.ok).length;

  Map<String, dynamic> toJson() => {
        'actionResults': [for (final o in outcomes) o.toJson()],
        if (reverted) 'reverted': true,
        if (reverted)
          'note': 'One action failed, so the whole block was rolled back. '
              'The document is exactly as it was before this block.',
        if (blocked != null) 'blocked': blocked,
        if (state != null) 'partAfter': state,
      };

  /// [imagesDropped] is set when a view was rendered but the provider cannot
  /// receive images. Saying so is the point: a model told nothing would
  /// describe the view it believes it was sent.
  String encode({bool imagesDropped = false}) => jsonEncode({
        ...toJson(),
        if (imagesDropped)
          'viewsNotSent': 'A view was rendered but this provider takes text '
              'only, so you have NOT seen it. Do not describe it. Work from '
              'describe_shape and section, or ask the user to look.',
      });

  /// Reads a report back out of a stored tool message. Returns null for
  /// anything that is not one — a conversation loaded from disk is data.
  static AiActionReport? decode(String text) {
    try {
      final j = jsonDecode(text);
      if (j is! Map || j['actionResults'] is! List) return null;
      return AiActionReport(
        outcomes: [
          for (final o in (j['actionResults'] as List).whereType<Map>())
            AiActionOutcome(o['op'] as String? ?? '?',
                ok: o['ok'] as bool? ?? false, error: o['error'] as String?)
        ],
        reverted: j['reverted'] as bool? ?? false,
        blocked: j['blocked'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

/// A fenced ```cad block and what it parsed to.
class AiActionBlock {
  const AiActionBlock(this.actions, {this.parseError});
  final List<AiAction> actions;
  final String? parseError;
  bool get isEmpty => actions.isEmpty && parseError == null;
}

final RegExp _fence = RegExp(r'```[ \t]*cad[ \t]*\r?\n(.*?)```',
    multiLine: true, dotAll: true, caseSensitive: false);

/// Every action a reply asks for, in order.
///
/// Deliberately strict. A block that is not valid JSON, names an op that does
/// not exist, or asks for more than [kAiMaxActionsPerBlock] is reported as a
/// parse error and executed not at all — the model is told what was wrong and
/// can write it again. Guessing at a malformed block would mean guessing at
/// geometry.
AiActionBlock parseAiActions(String reply) {
  final actions = <AiAction>[];
  String? error;
  for (final m in _fence.allMatches(reply)) {
    final raw = m.group(1)!.trim();
    if (raw.isEmpty) continue;
    Object? parsed;
    try {
      parsed = jsonDecode(raw);
    } catch (_) {
      error ??= 'The cad block is not valid JSON.';
      continue;
    }
    final list = parsed is List
        ? parsed
        : parsed is Map && parsed['actions'] is List
            ? parsed['actions'] as List
            : parsed is Map && parsed['op'] is String
                ? [parsed]
                : null;
    if (list == null) {
      error ??= 'A cad block must be {"actions": [ ... ]}.';
      continue;
    }
    for (final entry in list) {
      if (entry is! Map) {
        error ??= 'Every action must be a JSON object with an "op".';
        continue;
      }
      final args = entry.cast<String, dynamic>();
      final op = args.remove('op');
      if (op is! String || !kAiOps.contains(op)) {
        error ??= 'Unknown op "$op". Use one of: ${kAiOps.join(', ')}.';
        continue;
      }
      actions.add(AiAction(op, args));
    }
  }
  if (actions.length > kAiMaxActionsPerBlock) {
    return AiActionBlock(const [],
        parseError: 'At most $kAiMaxActionsPerBlock actions per block; '
            'this one had ${actions.length}. Split the work across turns.');
  }
  return AiActionBlock(error == null ? actions : const [], parseError: error);
}

/// The reply with its cad blocks taken out — what the composer shows above the
/// executed-changes card, so the user reads the explanation and not the JSON.
String aiReplyWithoutActions(String reply) {
  final stripped = reply.replaceAll(_fence, '').trim();
  return stripped.isEmpty ? reply.trim() : stripped;
}

/// Called as each action of a block starts, so the UI can say what is
/// happening in a few words instead of showing a spinner for the whole batch.
typedef AiProgress = void Function(String op, int step, int total);

/// Runs a block against the open document. Supplied by the app layer; null in
/// a controller with no workspace attached, which is what makes editing
/// unavailable rather than merely unused.
typedef AiActionRunner = Future<AiActionReport> Function(List<AiAction> batch,
    {AiProgress? onStep});

/// What the assistant is doing right now.
///
/// The app derives this from its OWN work rather than asking the model to
/// narrate — a status the model writes is one more thing it can get wrong, and
/// it arrives only when the model does. This arrives immediately and is always
/// true.
enum AiPhase {
  /// Nothing running.
  idle,

  /// Waiting on the provider.
  thinking,

  /// Executing a block against the document.
  working,
}

class AiActivity {
  AiActivity(this.phase, {this.op, this.step = 0, this.total = 0, DateTime? since})
      : since = since ?? DateTime.now();
  static final none = AiActivity(AiPhase.idle);

  /// When this phase began, so the panel can show how long it has been going.
  ///
  /// One unchanging word for a minute is indistinguishable from a hang — which
  /// is what issue #70 reported. A counter next to it is the difference
  /// between "it is working" and "it has stopped".
  final DateTime since;

  Duration get elapsed => DateTime.now().difference(since);

  final AiPhase phase;

  /// The op id currently running, for the UI to turn into a few words. Null
  /// while merely thinking.
  final String? op;
  final int step, total;

  bool get isBusy => phase != AiPhase.idle;

  /// Which short label an op belongs under. Kept here, next to the op set, so
  /// adding an op and forgetting to give it a word is a compile-time gap
  /// rather than a silent "working…".
  AiWork get work => switch (op) {
        null => AiWork.thinking,
        'describe_part' ||
        'describe_shape' ||
        'faces_where' ||
        'section' =>
          AiWork.reading,
        'measure' => AiWork.measuring,
        'create_sketch' ||
        'sketch_rect' ||
        'sketch_circle' ||
        'sketch_polygon' ||
        'sketch_line' ||
        'sketch_on_face' =>
          AiWork.sketching,
        'extrude' || 'revolve' || 'fillet' || 'chamfer' => AiWork.building,
        'edit_feature' ||
        'delete_feature' ||
        'rename_feature' ||
        'delete_face' ||
        'move_face' =>
          AiWork.editing,
        'look' => AiWork.looking,
        'brief_note' || 'brief_done' => AiWork.noting,
        _ => AiWork.working,
      };
}

/// The short words the panel shows. One per kind of work, not one per op: the
/// user asked to know what is happening in a few words, not to read a log.
enum AiWork {
  thinking,
  reading,
  measuring,
  sketching,
  building,
  editing,
  looking,
  noting,
  working
}

/// The protocol, as the model is told it. Appended to the instructions only
/// when a runner is attached — a model that cannot edit is never told it can.
const String kAiActionInstructions = '''

MODEL EDITING. You can change the open part by emitting a fenced block:

```cad
{"actions": [{"op": "create_sketch", "plane": "xy"},
             {"op": "sketch_rect", "width": 60, "height": 40, "centered": true},
             {"op": "extrude", "distance": 10}]}
```

START NOW, IN SMALL STEPS. Do not plan the whole part before acting and do
not describe what you are about to do. Emit the FIRST small block immediately —
one or two actions is a good first block — and let the result come back before
deciding the next one. The user watches the model change as each block lands,
so three small blocks that arrive over ten seconds are worth far more than one
perfect block that arrives after a minute. If you find yourself writing a plan,
stop and run its first step instead.

Rules that are not negotiable:
- Lengths are millimetres, angles are degrees, in the document's own frame.
- The block is executed in order, as ONE transaction. If any action fails, the
  whole block is rolled back and you are told why. Nothing is half-applied.
- You are given the result of every block before you answer the user. Read it.
  Report what the document actually says, not what you asked for.
- Emit at most one block per turn, and at most $kAiMaxActionsPerBlock actions
  in it. Prefer fewer: the first block should usually be one or two actions.
- If you are unsure what is in the document, run {"op": "describe_part"} first.
- Never claim a change you did not make, or a measurement the report does not
  contain.

Operations and their arguments (an omitted optional argument takes its
default):
- describe_part — features, sketches, bodies, bounding box, errors.
- describe_shape {body?, detail?: "digest"|"sections"|"faces"} — what the body
  IS: measured bounding box, volume, face inventory, holes, blends, symmetry,
  minimum wall. Run this before describing an imported body: the feature tree
  of an import is a placeholder and its numbers are not dimensions.
- faces_where {type?: "plane"|"cylinder"|"cone"|"sphere"|"torus", axis?,
  diameter?, min_area?, near?: [x,y,z], limit?} — finds faces and returns an
  ID for each. Face IDs are what delete_face, move_face and sketch_on_face
  take.
- measure {from: face-id, to: face-id} — distance and angle between two faces.
- section {axis?: "x"|"y"|"z", at?} — one cross-section outline.
- look {az?, pol?, zoom_to?: face-id, style?: "shaded"|"wire", annotate?} —
  renders the model from a direction you choose and returns it as an image.
  Only ask when the question is visual; the digest answers most questions more
  precisely and for a fraction of the cost.
- delete_face {face} — removes a face and heals the body (direct editing, for
  bodies with no feature tree).
- move_face {face, distance} — offsets a face along its own normal.
- sketch_on_face {face} — starts a sketch on a face; then use the sketch and
  extrude ops as normal.
- create_sketch {plane: "xy"|"xz"|"yz"} — creates and returns a sketch name.
- sketch_rect {sketch?, x, y, width, height, centered?} — x/y is the corner,
  or the centre when centered is true. Defaults to the newest sketch.
- sketch_circle {sketch?, x, y, diameter} (or radius).
- sketch_polygon {sketch?, points: [[x,y], ...], closed?} — closed by default.
- sketch_line {sketch?, x1, y1, x2, y2}.
- extrude {sketch?, distance, operation?: "new"|"join"|"cut"|"intersect",
  direction?: "default"|"flipped"|"symmetric", taper?, through_all?,
  body?} — extrudes every closed profile of the sketch.
- revolve {sketch?, angle?, axis?: "x"|"y", operation?, body?} — about a
  sketch axis; angle defaults to 360.
- fillet {radius, edges?: "all"|"convex"|"concave"|"vertical"|"horizontal",
  body?, near?: [[x,y,z], ...]} — rounds live edges of a body.
- chamfer {distance, edges?, body?, near?} — same selection as fillet.
- edit_feature {feature, distance?, distance_b?, taper?, angle?, radius?,
  operation?} — changes an existing feature and rebuilds.
- delete_feature {feature}.
- rename_feature {feature, name}.
- brief_note {text, kind?: "must"|"prefer"|"assumption", source?} — records a
  requirement for THIS document so it survives the conversation. `text` is
  your reading of it; `source` is the user's own words, quoted exactly. Record
  a requirement the moment you learn it, and record your own assumptions as
  "assumption" so the user can correct them. Never record a "must" the user
  did not actually state.
- brief_done {id} — marks a recorded requirement satisfied.
''';

/// An [AiMessage] carrying an action report. Role 'tool' so the composer can
/// draw it as what it is — something the APP did — rather than as either
/// party's words.
AiMessage aiToolMessage(AiActionReport report, {bool withImages = true}) {
  final dropped = !withImages && report.images.isNotEmpty;
  return AiMessage(
      role: 'tool',
      text: report.encode(imagesDropped: dropped),
      attachments: withImages ? report.images : const []);
}
