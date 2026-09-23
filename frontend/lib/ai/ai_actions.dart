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
import 'dart:math' as math;

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
  'size_face',
  'scale_body',
  'sketch_on_face',
  'create_sketch',
  'sketch_rect',
  'sketch_circle',
  'sketch_polygon',
  'sketch_line',
  'sketch_arc',
  'sketch_slot',
  'sketch_rounded_rect',
  'sketch_point',
  // Geometry by construction: a profile whose segments each start where the
  // last one ended, so it closes because of how it is written, not because
  // two rounded numbers happened to agree.
  'sketch_path',
  'sketch_ring',
  'sketch_tool',
  'sketch_modify',
  'sketch_project',
  'sketch_pattern',
  'sketch_gear',
  'sketch_text',
  'sketch_constrain',
  'sketch_dimension',
  'extrude',
  'revolve',
  'hole',
  'sweep',
  'loft',
  'coil',
  'split_body',
  'combine',
  'pattern',
  // #85 — hollow to a wall, open on the named side.
  'shell',
  'fillet',
  'chamfer',
  'edit_feature',
  'delete_feature',
  'rename_feature',
  'brief_note',
  'brief_done',
  // #82 — opens one document from the bundled knowledge base by id.
  'knowledge',
  // Named numbers for this part, usable in any numeric argument.
  'vars',
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
  // #82 — reading a reference document changes nothing about the part, so it
  // never marks a block as mutating and never triggers a rollback.
  'knowledge',
  // Defining a named number changes nothing about the part either.
  'vars',
};

/// Ops that change the BRIEF rather than the geometry. A recorded requirement
/// must not be rolled back because an extrusion later in the same block
/// failed: it is something the user said, not something the app built.
const Set<String> kAiBriefOps = {'brief_note', 'brief_done'};

/// Ops after which the document is whole again: each one either builds a
/// feature, changes one, or removes one, and a successful one leaves nothing
/// half-drawn behind it. A block that fails later is committed up to the last
/// of these (see [AiActionReport.kept]). Sketch ops are deliberately absent —
/// a sketch drawn for a feature that then failed is part of the failed step.
const Set<String> kAiCommitOps = {
  'extrude',
  'revolve',
  'hole',
  'sweep',
  'loft',
  'coil',
  'shell',
  'split_body',
  'combine',
  'pattern',
  'fillet',
  'chamfer',
  'edit_feature',
  'delete_feature',
  'rename_feature',
  'delete_face',
  'move_face',
  'size_face',
  'scale_body',
};

/// Actions in one block.
///
/// Was 24, which let a model answer "make me an espresso cup" by planning the
/// entire part and emitting it at once. That is the wrong shape of work for
/// this panel (issue #70): the user waits a minute watching one unchanging
/// word, and if anything goes wrong they get nothing at all rather than the
/// three steps that did succeed.
///
/// Six forced the same part to arrive as a sequence of small blocks, each of
/// which lands in the document, is visible in the browser, and is undoable on
/// its own. It cost more requests — every round resends the conversation.
///
/// ISSUE #83 — THE COST WAS THE ROUND TRIPS. 21 provider rounds at 5 to 70
/// seconds each carried a part whose kernel work took under a second, and six
/// actions is less than one honest step of a real part: a sketch, a
/// three-segment profile and its extrude is already five. Twelve is one step
/// with room to finish it — a plate and its holes, a profile and its blends —
/// and it is safe now for the reason six was chosen: a block no longer fails
/// as a whole. Everything up to the last feature that built stays in the
/// document ([AiActionReport.kept]), so a long block that stumbles at its end
/// still delivers the steps that worked, which is what issue #70 asked for.
/// `vars` does not count: it names numbers and builds nothing.
const int kAiMaxActionsPerBlock = 12;

/// How many times one `send()` may go model -> actions -> results -> model.
///
/// Raised twice. Six actions a block needs more rounds to build the same part,
/// and stopping at four left a cup with no handle (issue #70). Ten then turned
/// out to be a ceiling on AMBITION rather than on cost: a finished cup is a
/// body, a wall, a base, a rim, a handle and the blends between them, which is
/// more than ten blocks before anyone has looked at it once (issue #71).
///
/// Forty is not "until it is happy" — that has no bound and would be somebody
/// else's bill. It is a budget large enough that the STOP BUTTON, and not this
/// number, is what normally ends a long build. Every round is a paid request
/// that resends the conversation, so the instructions ask for small blocks and
/// the loop stops the moment the model stops emitting them.
const int kAiMaxActionRounds = 40;

/// How many times the app may tell a model that stopped early that its own
/// recorded "must" requirements are still open (issue #71).
///
/// This is the only mechanical grip the app has on "production ready". It
/// cannot judge a cup. It CAN see that the model wrote down "must have a
/// handle", never marked it done, and then said it had finished — and say so.
/// Bounded, because a model that has answered the same push-back three times
/// is not going to answer it differently the fourth.
const int kAiMaxDoneChecks = 3;

/// The longest task title the panel will show. Two to five words is what the
/// instructions ask for; this is the guard, not the goal.
const int kAiTitleMaxLength = 60;

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
      final q = aiPoint(p);
      if (q != null) out.add(q);
    }
    return out;
  }

  /// One 2D point argument, or null when [key] is absent or not a point.
  List<double>? point(String key) => aiPoint(args[key]);

  Map<String, dynamic> toJson() => {'op': op, ...args};
}

/// A 2D point in any of the forms the protocol accepts: `[x, y]`,
/// `{"x": .., "y": ..}`, or POLAR — `{"r": 5, "deg": 30}`, optionally about
/// `{"cx": .., "cy": ..}`.
///
/// Polar is here for the same reason expressions are (see ai_expr.dart): the
/// point on a circle at 30 degrees is a fact the app can compute exactly and
/// the model can only round. Arguments reach this after the executor has
/// evaluated any expressions in them, so every component is a number here.
List<double>? aiPoint(Object? p) {
  double? n(Object? v) => v is num && v.isFinite ? v.toDouble() : null;
  if (p is List && p.length >= 2) {
    final x = n(p[0]), y = n(p[1]);
    return x == null || y == null ? null : [x, y];
  }
  if (p is Map) {
    final x = n(p['x']), y = n(p['y']);
    if (x != null && y != null) return [x, y];
    final r = n(p['r']) ?? n(p['radius']);
    final deg = n(p['deg']) ?? n(p['angle']);
    if (r != null && deg != null) {
      final cx = n(p['cx']) ?? 0, cy = n(p['cy']) ?? 0;
      final a = deg * math.pi / 180;
      // Snapped like the expression evaluator's trig, so r at 90 degrees is
      // exactly (0, r) and not (6e-16, r).
      double clean(double v) => v.abs() < 1e-15 ? 0 : v;
      return [cx + r * clean(math.cos(a)), cy + r * clean(math.sin(a))];
    }
  }
  return null;
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
      this.kept = 0,
      this.state,
      this.blocked,
      this.title,
      this.problems = const [],
      List<AiAttachment> images = const []})
      : images = List.unmodifiable(images);
  final List<AiActionOutcome> outcomes;

  /// How many of [outcomes], from the start, are still in the document when
  /// [reverted] is set. Zero is the old whole-block rollback.
  ///
  /// A block is committed up to the last FEATURE that built before the
  /// failure: that point is a consistent document (every feature in it built,
  /// no half-drawn sketch hanging off the end), and throwing it away cost a
  /// whole round trip to rebuild what had already worked (#83). Everything
  /// after it goes back, including sketch geometry drawn for the step that
  /// failed, so the model is never told "step 3 of 5 worked" about a document
  /// that does not contain steps 1 and 2 — the rule this report was built on.
  final int kept;

  /// Design-rule violations the app found in the result — a join that left
  /// material floating, a cut that removed nothing. Each is a fact about the
  /// geometry, measured after the block, and while any is open the block's
  /// "say" line is not taken: a part that fails its own checks is not done.
  final List<String> problems;

  /// The user-facing title of the block that produced this report, so the
  /// transcript can say "Rounding the rim" where it used to say "4 changes".
  final String? title;

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
  int get applied => reverted
      ? outcomes.take(kept).where((o) => o.ok).length
      : outcomes.where((o) => o.ok).length;

  /// Whether part of a failed block is still in the document.
  bool get partial => reverted && kept > 0;

  /// The same report under a user-facing title. The executor does not know
  /// the title — it belongs to the block, not to any one action — so the
  /// controller attaches it once the block has run.
  AiActionReport withTitle(String? value) =>
      value == null || value.isEmpty || value == title
          ? this
          : AiActionReport(
              outcomes: outcomes,
              reverted: reverted,
              kept: kept,
              state: state,
              blocked: blocked,
              title: value,
              problems: problems,
              images: images);

  Map<String, dynamic> toJson() => {
        if (title != null) 'title': title,
        'actionResults': [for (final o in outcomes) o.toJson()],
        if (reverted) 'reverted': true,
        if (reverted && kept > 0) 'kept': kept,
        if (reverted)
          'note': kept == 0
              ? 'One action failed, so the whole block was rolled back. '
                  'The document is exactly as it was before this block.'
              : 'Action ${outcomes.length} failed. Actions 1-$kept are in '
                  'the document and stay there — do not build them again. '
                  'Actions ${kept + 1}-${outcomes.length} were rolled back, '
                  'including any sketch drawn for the step that failed. '
                  'Continue from action ${kept + 1}.',
        if (problems.isNotEmpty) 'problems': problems,
        if (problems.isNotEmpty)
          'problemsNote': 'The app checked the result and these are wrong '
              'with it. Fix them before anything else; the part is not done '
              'while any is open.',
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
        kept: (j['kept'] as num?)?.toInt() ?? 0,
        problems: [
          if (j['problems'] is List)
            for (final p in (j['problems'] as List).whereType<String>()) p
        ],
        blocked: j['blocked'] as String?,
        title: j['title'] is String && (j['title'] as String).trim().isNotEmpty
            ? (j['title'] as String).trim()
            : null,
      );
    } catch (_) {
      return null;
    }
  }
}

/// A fenced ```cad block and what it parsed to.
class AiActionBlock {
  const AiActionBlock(this.actions, {this.parseError, this.title, this.say});
  final List<AiAction> actions;
  final String? parseError;

  /// The answer to give the user IF this block succeeds completely, so a
  /// finished job does not cost one more provider round trip just to say so.
  ///
  /// Measured on the session in issue #72: the closing "Fertig: 140 × 70 × 8
  /// mm …" was its own round — 8.4 s and 365 output tokens, 327 of them
  /// reasoning, to write one sentence about work already done.
  ///
  /// It is only used when every action in the block succeeded and nothing was
  /// rolled back. A model cannot claim a result this way and be wrong about
  /// it: if anything failed, the line is discarded and it gets the report and
  /// another round, exactly as before.
  final String? say;

  /// What the USER is shown while this block runs (issue #71).
  ///
  /// The panel never shows the block itself; the model's own short title for
  /// it is what appears in its place. Null when the model omitted one, which
  /// is not an error — the app then falls back to its own word for the work,
  /// because refusing a whole block over a missing label would trade a
  /// cosmetic problem for a functional one.
  final String? title;

  bool get isEmpty => actions.isEmpty && parseError == null;
}

final RegExp _fence = RegExp(r'```[ \t]*cad[ \t]*\r?\n(.*?)```',
    multiLine: true, dotAll: true, caseSensitive: false);

/// Some models answer with a ```json fence, or with nothing but the JSON.
/// Only consulted when there is no ```cad fence at all — see [_actionSpans].
final RegExp _looseFence = RegExp(r'```[ \t]*[a-z]*[ \t]*\r?\n(.*?)```',
    multiLine: true, dotAll: true, caseSensitive: false);

/// Where in a reply the action payloads are, so the parser and the panel
/// agree exactly: everything this finds is EXECUTED and never displayed, and
/// everything else is displayed and never executed.
class _Span {
  const _Span(this.start, this.end, this.raw);
  final int start, end;
  final String raw;
}

/// Does this decode to something the executor could take?
bool _isPayload(Object? parsed) {
  if (parsed is Map) {
    if (parsed['actions'] is List) return true;
    return parsed['op'] is String && kAiOps.contains(parsed['op']);
  }
  if (parsed is List && parsed.isNotEmpty) {
    return parsed.every(
        (e) => e is Map && e['op'] is String && kAiOps.contains(e['op']));
  }
  return false;
}

bool _isPayloadText(String raw) {
  try {
    return _isPayload(jsonDecode(raw));
  } catch (_) {
    return false;
  }
}

/// The index just past the brace matching the one at [start], or -1.
///
/// Written out rather than done with a regular expression because braces
/// nest and strings may contain them; a regex that "works" here is one that
/// truncates a payload at the first `}` inside a quoted note.
int _matchingBrace(String s, int start) {
  final open = s.codeUnitAt(start);
  final close = open == 0x7B ? 0x7D : 0x5D;
  var depth = 0;
  var inString = false, escaped = false;
  final limit = s.length - start > 20000 ? start + 20000 : s.length;
  for (var i = start; i < limit; i++) {
    final c = s.codeUnitAt(i);
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (c == 0x5C) {
        escaped = true;
      } else if (c == 0x22) {
        inString = false;
      }
      continue;
    }
    if (c == 0x22) {
      inString = true;
    } else if (c == open) {
      depth++;
    } else if (c == close) {
      if (--depth == 0) return i + 1;
    }
  }
  return -1;
}

/// Bare JSON in the middle of prose. Bounded: at most 40 candidate positions
/// and 20 000 characters a span, so a long reply cannot turn this into a
/// quadratic scan.
List<_Span> _bareSpans(String reply) {
  final out = <_Span>[];
  var i = 0, tried = 0;
  while (i < reply.length && tried < 40) {
    final c = reply.codeUnitAt(i);
    if (c != 0x7B && c != 0x5B) {
      i++;
      continue;
    }
    tried++;
    final end = _matchingBrace(reply, i);
    if (end < 0) break;
    final raw = reply.substring(i, end);
    if (_isPayloadText(raw)) {
      out.add(_Span(i, end, raw));
      i = end;
    } else {
      i++;
    }
  }
  return out;
}

/// Every action payload in a reply, in order.
///
/// ISSUE #71 — "i currently see the json output". The agreed protocol is a
/// ```cad fence, and when the model uses it the panel showed the prose and
/// hid the block. When the model did NOT — a bare object, a ```json fence —
/// two things went wrong at once: nothing ran, and the user read the JSON.
///
/// So the untagged forms are accepted, but only when there is no ```cad fence
/// in the reply. That ordering is what keeps a model ANSWERING a question
/// about the protocol ("a block looks like {\"actions\": ...}") from having
/// its example executed: a reply that contains a real block is parsed
/// strictly, and a reply that contains none is the only one where a bare
/// object can plausibly be an instruction rather than an illustration.
List<_Span> _actionSpans(String reply) {
  final tagged = [
    for (final m in _fence.allMatches(reply))
      _Span(m.start, m.end, m.group(1)!.trim())
  ];
  if (tagged.isNotEmpty) return tagged;
  final loose = [
    for (final m in _looseFence.allMatches(reply))
      if (_isPayloadText(m.group(1)!.trim()))
        _Span(m.start, m.end, m.group(1)!.trim())
  ];
  if (loose.isNotEmpty) return loose;
  return _bareSpans(reply);
}

String? _clampTitle(Object? value) {
  if (value is! String) return null;
  final one = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (one.isEmpty) return null;
  return one.length <= kAiTitleMaxLength
      ? one
      : '${one.substring(0, kAiTitleMaxLength - 1).trimRight()}…';
}

/// A title for a task made from the words the user asked for it with.
///
/// The model's own block title is better when there is one (issue #71), but it
/// arrives a whole provider round late — so the panel had nothing to announce
/// until after the work had already started, which is precisely the wrong way
/// round. The request's own first sentence is always available and is always
/// true, and it is clamped to the same length as a model title so the two
/// cannot lay out differently.
String? aiTitleFrom(String request) => _clampTitle(request);

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
  String? title;
  String? say;
  for (final span in _actionSpans(reply)) {
    final raw = span.raw;
    if (raw.isEmpty) continue;
    Object? parsed;
    try {
      parsed = jsonDecode(raw);
    } catch (_) {
      error ??= 'The cad block is not valid JSON.';
      continue;
    }
    if (parsed is Map) {
      title ??= _clampTitle(parsed['title']);
      final line = parsed['say'];
      if (line is String && line.trim().isNotEmpty) say ??= line.trim();
      // Block-level named numbers: {"vars": {"wall": 2, "r": "d/2"}, ...}.
      // They run first, as an ordinary `vars` action, so every action in the
      // block — and every later block on this part — can use the names.
      final vars = parsed['vars'];
      if (vars is Map && vars.isNotEmpty) {
        actions.add(AiAction('vars', vars.cast<String, dynamic>()));
      } else if (vars != null && vars is! Map) {
        error ??= '"vars" must be an object of name: number pairs.';
      }
    }
    final list = parsed is List
        ? parsed
        : parsed is Map && parsed['actions'] is List
            ? parsed['actions'] as List
            : parsed is Map && parsed['op'] is String
                ? [parsed]
                : null;
    if (list == null) {
      // A block that only closes the turn: {"title": ..., "say": ...}.
      if (parsed is Map && say != null) continue;
      error ??= 'A cad block must be {"title": "...", "actions": [ ... ]}.';
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
  final counted = actions.where((a) => a.op != 'vars').length;
  if (counted > kAiMaxActionsPerBlock) {
    return AiActionBlock(const [],
        parseError: 'At most $kAiMaxActionsPerBlock actions per block; '
            'this one had $counted. Split the work across turns.',
        title: title);
  }
  return AiActionBlock(error == null ? actions : const [],
      parseError: error, title: title, say: say);
}

/// A remainder that is still machine text: a payload the brace matcher could
/// not close, which is what a reply truncated mid-block leaves behind.
bool _looksLikeStrayJson(String text) {
  if (!text.startsWith('{') && !text.startsWith('[')) return false;
  return text.contains('"actions"') || text.contains('"op"');
}

/// The reply with its action payloads taken out — everything the panel shows.
///
/// ISSUE #71 — this used to fall back to the WHOLE reply when stripping left
/// nothing, which is precisely the reply that is nothing but a block, so the
/// one case the strip existed for was the one case it did not handle. It
/// returns the empty string now: a turn that only acted has nothing to say,
/// and the title of what it did is shown in its place.
String aiReplyWithoutActions(String reply) {
  final spans = _actionSpans(reply);
  final buffer = StringBuffer();
  var at = 0;
  for (final span in spans) {
    if (span.start > at) buffer.write(reply.substring(at, span.start));
    at = span.end;
  }
  if (at < reply.length) buffer.write(reply.substring(at));
  // A removed block leaves the blank lines that framed it; three or more in
  // a row is a hole in the answer, not a paragraph break.
  final text =
      buffer.toString().replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  return _looksLikeStrayJson(text) ? '' : text;
}

/// Whether the assistant's turn is a question waiting on the user.
///
/// Used by the loop to tell "I have stopped because I need you" apart from
/// "I have stopped because I think I am finished" — only the second one is
/// pushed back on.
/// A reply with the context we just sent it stripped back out.
///
/// ISSUE #83 — the model answered one round by REGURGITATING its own input:
/// 2,600 characters of the document context, wrapped in an
/// `<untrusted_document_data>` element the app has never sent, before the
/// block it was actually asked for. That costs three ways. It is output
/// tokens; it is stored in the conversation and resent on every later round,
/// which is most of why per-request input grew from about 8.7K tokens in the
/// session before it to 13.2K in this one; and the app shows whatever is
/// outside the fence to the USER as the assistant's answer, so a wall of JSON
/// landed in the panel.
///
/// The instructions already say never to write JSON outside the fence. This
/// is the app not depending on that: text the app itself sent cannot be an
/// answer to anything, so it does not survive the round trip back.
String aiStripEchoedContext(String reply) {
  var out = reply;
  // The wrapper is the model's own invention — this app has never emitted an
  // `<untrusted_document_data>` element in its life — so anything wearing one
  // is quoted input and goes, whatever is inside it.
  out = out.replaceAll(
      RegExp(
          r'<untrusted_document_data>[\s\S]*?</untrusted_document_data>\s*',
          caseSensitive: false),
      '');
  // The same echo without a wrapper: the header plus the JSON object after it.
  out = out.replaceAll(
      RegExp(r'CURRENT DOCUMENT CONTEXT \(untrusted data\):\s*\{[\s\S]*?\}\s*(?=\n|$)'),
      '');
  return out.trim();
}

bool aiReplyIsQuestion(String reply) =>
    aiReplyWithoutActions(reply).trimRight().endsWith('?');

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
  AiActivity(this.phase,
      {this.op, this.step = 0, this.total = 0, this.title, DateTime? since})
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

  /// The model's own title for the block in flight (issue #71). Shown in
  /// place of [work]'s generic word when it is there, because "Rounding the
  /// rim" says more than "Building" and costs the user nothing to read.
  ///
  /// It is the one part of the status the model writes, and it is a LABEL,
  /// never a claim: the phase, the step counter and the clock beside it stay
  /// the app's own, so a wrong title cannot make stalled work look busy.
  final String? title;

  bool get isBusy => phase != AiPhase.idle;

  /// Which short label an op belongs under. Kept here, next to the op set, so
  /// adding an op and forgetting to give it a word is a compile-time gap
  /// rather than a silent "working…".
  AiWork get work => switch (op) {
        null => AiWork.thinking,
        'describe_part' ||
        'describe_shape' ||
        'faces_where' ||
        'section' ||
        // #82 — opening a reference document is reading, same as reading the
        // part. The panel does not need a word of its own for it.
        'knowledge' =>
          AiWork.reading,
        'measure' => AiWork.measuring,
        'create_sketch' ||
        'sketch_rect' ||
        'sketch_circle' ||
        'sketch_polygon' ||
        'sketch_line' ||
        'sketch_arc' ||
        'sketch_slot' ||
        'sketch_rounded_rect' ||
        'sketch_point' ||
        'sketch_path' ||
        'sketch_ring' ||
        'sketch_tool' ||
        'sketch_project' ||
        'sketch_pattern' ||
        'sketch_gear' ||
        'sketch_text' ||
        'sketch_on_face' =>
          AiWork.sketching,
        'extrude' ||
        'revolve' ||
        'fillet' ||
        'chamfer' ||
        'hole' ||
        'sweep' ||
        'loft' ||
        'coil' ||
        'split_body' ||
        'combine' ||
        'pattern' ||
        'shell' =>
          AiWork.building,
        'edit_feature' ||
        'delete_feature' ||
        'rename_feature' ||
        'delete_face' ||
        'move_face' ||
        'size_face' ||
        'scale_body' ||
        'sketch_modify' ||
        'sketch_constrain' ||
        'sketch_dimension' =>
          AiWork.editing,
        'look' => AiWork.looking,
        'brief_note' || 'brief_done' || 'vars' => AiWork.noting,
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
{"title": "Drawing the base plate",
 "actions": [{"op": "create_sketch", "plane": "xy"},
             {"op": "sketch_rect", "width": 60, "height": 40, "centered": true},
             {"op": "extrude", "distance": 10}]}
```

THE WORLD FRAME — READ THIS BEFORE YOUR FIRST SKETCH. This app is Y-UP.
Fusion, SolidWorks and Onshape are Z-up; assuming that here builds the part
lying on its side, and nothing in the feature tree will look wrong afterwards.

  +Y is UP, against gravity. -Y is down, toward the bench.
  XZ is the GROUND plane. Sketch there and extrude along +Y for anything that
    stands up or sits on a surface: a base plate, a cup, a housing, a bracket.
  XY is a VERTICAL wall facing +Z.
  YZ is a VERTICAL wall facing +X.

So {"op": "create_sketch", "plane": "xz"} then {"op": "extrude",
"distance": 8} is a plate 8 mm thick lying flat. The SAME sketch on "xy" is
that plate standing on its edge like a road sign. A part's footprint belongs
on XZ; its height is Y.

WHICH WAY THE SKETCH AXES POINT. A sketch is 2D: you give x and y, and the
app decides where that lands in the world. It is NOT the same pair of world
axes on every plane, and it is not always positive. This is the whole table —
do not derive it by extruding something and reading the bounding box back:

  plane   sketch +x     sketch +y     extrudes along
  xz      +X            -Z            +Y      (the ground plane)
  xy      +X            +Y            +Z
  yz      -Z            +Y            +X

Every create_sketch and sketch_on_face returns this same statement for the
sketch it just made, as "axes". A sketch on a FACE has its own frame and its
own origin, so read the one you are given rather than assuming this table.

You rarely need the table: {"op": "create_sketch", "on": "top"} puts a sketch
on the top of the part (also bottom, front, back, left, right), and the
anchors below give you the part's edges and middle IN THAT SKETCH'S OWN x/y,
with every sign already applied.

SKETCH (0,0) IS THE WORLD ORIGIN, NOT THE MIDDLE OF YOUR PART. This is the
single most common way a correct-looking block lands in the wrong place. If
you draw a plate with {"sketch_rounded_rect": {"x": 0, "y": 11, ...}} its
centre is at sketch (0, 11) — world z = -11 on the xz plane — and (0,0) is
now on its EDGE. Put a hole "in the middle" at (0,0) after that and it comes
out on the rim, half of it cutting air.

So never place a feature on an existing body by typing its coordinates.
Use the ANCHORS: in any numeric argument of a sketch op, `sk.cx` and `sk.cy`
are the middle of the part as seen in that sketch, and `sk.left`,
`sk.right`, `sk.bottom`, `sk.top`, `sk.w`, `sk.h` its edges and size. `part.*`
gives the same in world millimetres (part.xmin .. part.zmax, part.cx,
part.cy, part.cz, part.w, part.h, part.d). A hole in the middle of the top:
{"op": "create_sketch", "on": "top"}, {"op": "hole", "x": "sk.cx", "y":
"sk.cy", "diameter": 5, "through_all": true}. The cheapest habit on top of
that: draw the first profile CENTRED on (0,0) with "centered": true.

describe_shape prints a "stance" line naming which dimension is the height in
this frame, then an "extent" line giving where the body actually sits in x, y
and z, and a "centre" line. If the number you meant to be a width is the
height, the part is rotated: rebuild the sketch on the right plane. Do not try
to fix it by changing the view — the view is not part of the model.

EVERY BLOCK CARRIES A TITLE, AND THE USER SEES NOTHING ELSE OF IT. The block
itself is never shown: while it runs, the panel shows your "title" and nothing
more. Write it as two to five plain words in the user's language, naming what
this block does to the part — "Drawing the cup body", "Hollowing the inside",
"Rounding the rim". Not op names, not JSON, not a sentence. A block without a
title still runs, but the user then reads a generic word instead of yours.

NEVER WRITE JSON OUTSIDE THE FENCE, and never explain the block in prose. The
JSON is for the app; the title is for the user; anything else you type is read
as an answer and shown as one.

START NOW, IN SMALL STEPS. Do not plan the whole part before acting and do
not describe what you are about to do. Emit the first block immediately and
let the result come back before deciding the next one. If you find yourself
writing a plan, stop and run its first step instead. The one thing that comes
BEFORE the first block is the question below, when the request needs it:
asking what you are building is not planning, it is finding out what to build.

A STEP IS ONE BLOCK, AND EVERY BLOCK COSTS THE USER 10 TO 50 SECONDS. Each
one is a network round trip on which you are re-read from the beginning, so
an empty round is the most expensive thing you can do. Put everything that
belongs to ONE step in ONE block:

  - a sketch, its geometry and the extrude that consumes it are one step
  - two holes on the same face are one step, not two
  - never spend a whole block on a single brief_done — hang it on the next
    block that does real work
  - never spend a whole block saying you have finished — use "say" below

"Small" means one step of the part, not one action. The limit is
$kAiMaxActionsPerBlock actions; use as many of them as the step needs.

NEVER COMPUTE A COORDINATE IN YOUR HEAD. THE APP DOES ARITHMETIC EXACTLY.
Every numeric argument may be an expression, and the app evaluates it in
full precision: "r*cos(30)", "wall*2+0.4", "sk.w/2-3", "sqrt(2)*5". Trig
takes DEGREES. Name the numbers a part is designed around once, in the block,
and use the names afterwards — they stay defined for later blocks too:

```cad
{"title": "Drawing the clip", "vars": {"ro": 6, "ri": 3.5, "t": 10},
 "actions": [{"op": "create_sketch", "plane": "xz"},
             {"op": "sketch_ring", "outer": "2*ro", "inner": "2*ri",
              "opening": 5, "opening_deg": 270},
             {"op": "extrude", "distance": "t"}]}
```

A typed 4.330 for 5·cos 30° is a rounded guess, and a profile of rounded
guesses does not close. Write "5*cos(30)" and it does.

GEOMETRY BY CONSTRUCTION. Prefer the op that makes the whole shape over
drawing it from separate lines and arcs:
- sketch_ring — a ring, or a C with an opening: clips, cable holders, collars.
- sketch_path — ANY closed outline, one segment after another, each starting
  where the last one really ended, closed back to the start by the app. It
  cannot fail to close. Lines, arcs about a centre, arcs through a point,
  arcs of a radius, tangent arcs, and rounded corners (`round`,
  `corner_radius`) in one op.
- sketch_slot, sketch_rounded_rect, sketch_circle for those shapes.
- A plate with holes in ONE sketch: draw the outline and the circles inside
  it, extrude once. Nested outlines stay holes (even-odd), overlapping ones
  merge. `regions` overrides that when you need to.
- shell — hollows a solid to a wall, open on a side: a cup, a box, a cover,
  a sheet-metal part. Never build a wall by cutting the inside out by hand.
- sweep with profile_circle — the app puts the profile at the start of the
  path, square to it. A profile you draw yourself must be exactly that.

GIVE A FEATURE AN "id" when you might change it: {"op": "extrude",
"distance": 4, "id": "base"}. Sending the same id again REPLACES that feature
where it stands in the timeline, and everything built after it is rebuilt on
the new one. That is how you change a feature you got wrong — never delete
and rebuild it.

DO NOT THINK. BUILD, LOOK, CORRECT. This is the fastest way to a good part
and it is also the most accurate, and those are the same fact.

Running a block costs the app about a MILLISECOND. Thinking about what the
block would do costs the user a minute. So never reason your way to an answer
the app will simply give you: if you are unsure where a face is, what a sketch
encloses, how big something came out, or which way an axis points — build it,
or measure it, and READ THE ANSWER. Every block comes back with the feature,
the volume, the closed-profile count, the part's extent and centre, and a
picture of what it now looks like. That is ground truth. What you worked out
in your head is a guess about ground truth, and it takes a thousand times
longer to produce.

A wrong block is cheap: you are told exactly what happened and you fix it in
the next one. A long deliberation is expensive whether it is right or wrong.
But every block is also a round trip, so make each one a WHOLE step: the
profile, its extrude and its holes; the shell and the rim blend. You may have
up to 40 rounds; a good part needs far fewer.

Concretely, when you catch yourself doing any of these, stop: working out a
coordinate from trigonometry (write the expression instead), deducing which
way an axis points (use `on` and the sk.* anchors), predicting what a
bounding box will be, imagining what the shape looks like, or planning more
than the one next step.

"say": THE ANSWER THAT SAVES A ROUND TRIP. When a block is the last one — the
job is done and you know what you will tell the user — put that sentence in
the block as "say" and the turn ends there:

```cad
{"title": "Rounding the rim", "say": "Fertig: 140 × 70 × 8 mm, zwei Ø25-mm-
Taschen 6 mm tief, Kanten R2.", "actions": [{"op": "fillet", "radius": 2,
"edges": "outer"}]}
```

It is used ONLY if every action in the block succeeds, nothing is rolled
back and the app's checks find no problem with the part. If anything fails
you get the report and another round as usual, so "say" can never become a
claim about work that did not happen. Do not put a "say" on a block whose
result you still need to read. When the work is already done, a block with
only a title and a "say" (no actions) ends the turn with that sentence.

Rules that are not negotiable:
- Lengths are millimetres, angles are degrees, in the document's own frame.
- The block is executed in order. If an action fails, everything up to the
  last FEATURE that built before it stays in the document ("kept"), and the
  rest — including any sketch drawn for the failed step — is rolled back. The
  report says exactly which actions are in the document. Never rebuild the
  kept ones.
- After every block the app CHECKS the part: a cut that removes nothing and a
  join that leaves material floating are refused outright, and a body in
  several pieces or a feature that does not build is listed under
  "problems". Fix problems before anything else.
- You are given the result of every block before you answer the user. Read it.
  Report what the document actually says, not what you asked for.
- A block's report carries a SHORT state: the newest feature, the counts and
  the size. Older reports in this conversation have had their snapshots
  removed and say "superseded" — the document has changed since, so do not
  read a dimension off them. describe_part gives the timeline, describe_shape
  the measured shape, and both are current when they arrive.
- Emit at most one block per turn, and at most $kAiMaxActionsPerBlock actions
  in it.
- If you are unsure what is in the document, run {"op": "describe_part"} first.
- Never claim a change you did not make, or a measurement the report does not
  contain.

DRAW THE PROFILE PROPERLY BEFORE YOU EXTRUDE ANYTHING. Most of the shape of
a good part is decided in the sketch, and a sketch that is one rectangle is a
part that looks like one rectangle. Before the first extrude of any shape
that is not literally a block:
- Draw the WHOLE outline, with arcs where the real object has curves. A
  handle, a hook, a clip, a spout, a fillet you want to be exact — these are
  arcs, and sketch_arc, sketch_slot and sketch_rounded_rect exist so that you
  never have to fake one with a polygon. A polygon standing in for a circle
  is visibly faceted, and a 3D fillet on its facets will fail.
- Read `closedProfiles` in the result. It is the number of closed regions the
  sketch has. If it is not what you expect, fix the sketch — an extrude of
  the wrong region is a part you will have to delete.
- Put the curve in the sketch rather than fixing it later with a 3D fillet
  wherever you can. A rounded rectangle drawn as one is exact; four fillets
  on a sharp rectangle is four chances for the kernel to refuse.

A BLEND THAT DOES NOT FIT IS BUILT AT THE LARGEST SIZE THAT DOES. If the
radius you asked for does not build on those edges, the app finds the
largest one that does, builds that, and says so ("radiusAsked"). Add
"exact": true only when a smaller blend is worse than none. If NO size
builds, the report says why — often the body itself is broken by an earlier
feature; fix that, not the blend.

WORK WITH WHAT IS THERE. Deleting a feature and building it again is almost
never the fastest way to change something, and it throws away every later
feature that depended on it:
- To change a dimension, use edit_feature. That is what it is for.
- To change where something sits, edit the sketch that drives it.
- delete_feature is for a feature that should not exist at all — a wrong
  approach, not a wrong number.
- If you find yourself rebuilding what you just built, stop: read
  describe_part, and change the one thing that is wrong.

BUILD IT WHERE THE USER SAID. "On top" means at maximum Y; "on the side"
means on an X or Z face. Before placing a feature on an existing body, find
the face the user named — read its label off the picture, or run
faces_where — and put it there. Getting this wrong is not a detail — it is a
different part.

THE PICTURE IS LABELLED: READ IT, DO NOT RECONSTRUCT IT. Every view of the
part carries yellow labels with the face ids faces_where uses and the way
each face looks ("F12 -X"), and a triad for X, Y (up) and Z. The report
lists the same faces as `facesInView`, each with the feature that made it,
and the document context's `timeline` says what every sketch and feature
did, in world millimetres. Together they answer "which face is the bottom",
"what is that recess" and "which side did the user mean" at a glance. Never
work that out from centroids, normals and areas in your head: if the face
you need has no label, look from the side it is on. If the user's word could
mean two different faces of THIS part — the "bottom" of a slab standing on
its edge is either the narrow end or the big side it would lie on — ask
which, in their words, in one short question.

DOES THE THING ACTUALLY WORK? Before you call any functional part finished,
say to yourself what it has to DO and check the geometry allows it:
- a holder or a clip needs an OPENING the thing goes in through, wider than
  nothing and springy enough to matter — a closed circle in a plate holds
  nothing, because nothing can get into it
- a hole that locates a shaft needs clearance, not a nominal fit
- a hook needs an opening bigger than what hangs on it
- a lid needs a lip that engages, and a gap so it can be pushed on
- anything that stands needs a flat base at its lowest Y
If the mechanism does not work on the screen, it will not work in the hand.

MATCH THE EFFORT TO THE ASK. This is the single most important judgement you
make, and it goes both ways.
- A narrow, named change is exactly that change. "Add a 5 mm hole there" is
  one block, no questions, no extras: add the hole and stop. Do not round its
  edges, rename anything, or improve what you were not asked about.
- A whole object is a FINISHED object. "Make me a tea cup" is not a cylinder
  with a hollow in it. It is a cup somebody could drink from and somebody
  could make: a body with a usable volume, a wall of a thickness the chosen
  process can actually produce, a base that stands flat and does not pool,
  a rim that is comfortable and not a knife edge, a handle a finger fits
  through if the design has one, and blends where a hand touches it. Stop
  when THAT exists, not when the first solid appears.
- BE AMBITIOUS, AND SPEND STEPS RATHER THAN THOUGHT. Do not set yourself a
  small goal because it is safer. Aim at the part a good engineer would hand
  over, and then spend the STEPS it takes: the profile drawn properly, the
  walls sized for the process, the edges a hand touches rounded, the corners a
  tool has to reach radiused, clearances on anything that mates, and a flat,
  generous base. Every one of those is a block, and a part that took twenty
  quick correct blocks is worth far more than one that took four and looks
  like a first draft. Ambition is how many steps you are willing to run, never
  how long you are willing to think before running one.

ASK BEFORE YOU BUILD A WHOLE OBJECT. If the request is a whole part and how it
will be MADE is not stated, ask that first — it changes every dimension you are
about to choose. Reply with the question alone, no block, and wait:

  (in the user's own language, e.g.) "Wie soll die Tasse gefertigt werden —
   FDM-Druck, SLA/SLS, Guss, Spritzguss oder CNC?"

Ask other things the same way when they genuinely change the geometry — size
or capacity, whether it must stack, hold heat, fit an existing part. Ask them
TOGETHER with the process in one short question, not one per turn, and never
ask about anything you can reasonably assume and record as an assumption
instead. A narrow change is never worth a question.

Then design FOR that process, and record it with brief_note as a "must":
- FDM/FFF — walls a multiple of the nozzle width (0.8-2.4 mm typical),
  every downward face rising at least 30 deg from horizontal (the app MEASURES
  this on an FDM part and lists anything flatter under "problems"), no
  cantilevered flat undersides, layer lines across the strong axis, flat and
  generous first layer, a 0.6 mm foot chamfer added LAST.
- SLA/SLS — finer walls possible (0.8-1.5 mm), drain and escape holes for
  resin or powder in any closed volume, no fully enclosed cavities.
- Casting — draft on every vertical face (1-3 deg), generous radii, uniform
  wall thickness, no undercuts in the parting direction.
- Injection moulding — uniform walls (1.5-3 mm), draft (0.5-2 deg), no
  undercuts, ribs at 0.6 of the wall, cored-out thick sections.
- CNC — internal corners get a radius no smaller than the tool (3 mm typical),
  no deep narrow pockets, tool-reachable faces only, no sharp internal
  intersections.

WORK UNTIL IT IS DONE, THEN CHECK IT.
- Before the first block of a whole-object request, write down what DONE means
  with brief_note "must" entries — one per property the finished part has to
  have. That list is your definition of finished, and the app holds you to it.
- Mark each one with brief_done as it becomes true in the model, and only
  then.
- Keep emitting blocks. The user stops you with the stop button; you do not
  stop because it is taking a while.
- LOOK AT WHAT YOU JUST BUILT, EVERY TIME. You do not have to ask for this and
  you must not skip it: every block that changes the geometry comes back with
  a picture of the part and a `silhouette` — '#' is material, 'o' is an
  opening you can see straight through — taken after that block ran. That is
  the part, not your idea of the part. Read it before you write the next
  block. If it does not look like the thing you were asked for, fix THAT
  before adding anything else; carrying on and hoping is how a part ends up
  as a slab with four unused sketches. Use {"op": "look"} only when you want a
  different angle, and {"op": "section"} to see inside.
- Before you say you are finished, run one describe_shape and read it with the
  latest view. Check, in this order, and fix anything that is wrong instead of
  mentioning it:
    - the stance line: is the dimension you meant as the height the height?
    - every hole: does it say THROUGH? A hole that must hold, seat, locate or
      retain something needs a FLOOR. A pocket is a cut that stops short of
      the far face — set its distance to (thickness − floor), never to the
      full thickness.
    - the silhouette: does the outline look like the thing you were asked
      for, from two different directions?
    - what you rounded: the blend report lists the circular edges it caught.
      A circular edge at a bore's diameter is that bore's MOUTH; if you meant
      the outside corners, use {"edges": "outer"} and do it again.
- Only when every "must" is done, answer in one short sentence. If one cannot
  be met, say which one and why — do not quietly drop it.

Operations and their arguments (an omitted optional argument takes its
default):
- describe_part — features, sketches, bodies, bounding box, errors.
- describe_shape {body?, detail?: "digest"|"sections"|"faces"} — what the body
  IS: measured bounding box, volume, face inventory, holes, blends, symmetry,
  minimum wall. Run this before describing an imported body: the feature tree
  of an import is a placeholder and its numbers are not dimensions.
- faces_where {where?: "top"|"bottom"|"left"|"right"|"front"|"back",
  type?: "plane"|"cylinder"|"cone"|"sphere"|"torus", axis?, diameter?,
  min_area?, near?: [x,y,z], limit?} — finds faces and returns an ID for
  each, the way it faces, where it `spans` in world mm and which feature
  made it (`madeBy`). Face IDs are what delete_face, move_face,
  sketch_on_face and shell take — and what the labels on a picture show.
  `where` is the frame above: "top" is the face whose normal is +Y. `axis`
  takes a sign — "+y" is upward-facing only, "y" is both ways — so ask for
  the one you mean rather than picking from a list of two.
- measure {from: face-id, to: face-id} — distance and angle between two faces.
- section {axis?: "x"|"y"|"z", at?} — one cross-section outline.
- look {az?, pol?, size?, body?} — renders the model from a direction you
  choose. It returns a TEXT SILHOUETTE every provider can read ('#' material,
  'o' an opening straight through, blank background) and, where the provider
  takes images, a picture as well, with its faces labelled by id and an X/Y/Z
  triad. az turns around +Y; pol is the angle down from +Y, so pol 90 is a
  level side view and pol 0 is from straight above. Two views from different
  directions tell you far more than one.
- delete_face {face} — removes a face and heals the body (direct editing, for
  bodies with no feature tree).
- move_face {face, distance} — offsets a face along its own normal.
- size_face {face, diameter|radius} — resizes a cylindrical, conical or
  spherical face. How a hole's diameter changes on a body with no feature
  tree, which is what an imported STEP part is.
- scale_body {face, factor} — scales the whole body about its centre. What
  turns a part that came in as inches into one that is millimetres.
- sketch_on_face {face} — starts a sketch on a face; then use the sketch and
  extrude ops as normal.
- vars {name: number-or-expression, ...} — names numbers for this part (or
  put "vars" on the block itself). Usable in every numeric argument.
- create_sketch {plane: "xy"|"xz"|"yz", offset?} or {on: "top"|"bottom"|
  "front"|"back"|"left"|"right"} — creates and returns a sketch name.
  `offset` moves the plane along its own normal, which is how you draw
  something at a height instead of drawing it on the ground and extruding
  material you did not want. `on` puts it on that side of the part. Give it
  an `id` and refer to it by that id — never guess what "SketchN" the app
  will call it; numbers are reused after a rollback.
- sketch_rect {sketch?, x, y, width, height, centered?} — x/y is the corner,
  or the centre when centered is true. Defaults to the newest sketch.
- sketch_circle {sketch?, x, y, diameter} (or radius).
- sketch_polygon {sketch?, points: [[x,y], ...], closed?} — closed by default.
  STRAIGHT SEGMENTS ONLY. Never use it to approximate a curve: use sketch_arc.
- sketch_line {sketch?, x1, y1, x2, y2}.
- sketch_point {sketch?, x, y} — a sketch point. Holes and sketch-driven
  patterns are placed ON points, so this is how you say where they go.
- sketch_arc {sketch?, x, y, radius|diameter, start_deg, end_deg} — a TRUE
  arc about a centre, angles measured anticlockwise from +x. Or give three
  points it passes through: {x1, y1, x2, y2, x3, y3}.
- sketch_slot {sketch?, x1, y1, x2, y2, width} — a stadium: two parallel
  sides and a true semicircle at each end. x1,y1 and x2,y2 are the CENTRES of
  the two ends, so the overall length is the distance between them plus
  width. This is the shape of a cable channel, an adjustment slot, a finger
  grip and the opening of a clip.
- sketch_rounded_rect {sketch?, x, y, width, height, radius, centered?} — a
  rectangle whose corners are true arcs. Cheaper and more reliable than a
  rectangle plus four 3D fillets, and it cannot fail at rebuild time.
- sketch_ring {sketch?, x?, y?, outer, inner, opening?, opening_deg?} — outer
  and inner are DIAMETERS. With `opening` (the mouth width, parallel-sided)
  it is one closed C profile facing opening_deg; without, a plain ring.
- sketch_path {sketch?, start: [x,y], segments: [...], closed?,
  corner_radius?} — each segment is one of {"to": [x,y]} (line),
  {"by": [dx,dy]} (line by an offset), {"to": [x,y], "centre": [cx,cy],
  "cw"?} (arc about a centre), {"to": [x,y], "through": [x,y]},
  {"to": [x,y], "radius": r, "cw"?, "large"?}, {"to": [x,y], "tangent": true}
  (arc tangent to the segment before). Add "round": r to a straight segment
  to round the corner after it. Closed by default: the app draws the last
  side back to the start. With "closed": false it is an open PATH for a
  sweep — a handle is a leg, a tangent arc and a leg — and the sweep follows
  the whole chain as one smooth curve.
- extrude {sketch?, distance, operation?: "new"|"join"|"cut"|"intersect",
  direction?: "default"|"flipped"|"symmetric", taper?, through_all?,
  body?, regions?, id?} — extrudes the sketch's closed regions: nested ones
  stay holes (a cut takes them all). regions: "all" | "largest" |
  [[x, y], ...] picks explicitly.
- Every op that builds a feature takes `id` — see GIVE A FEATURE AN "id".
- revolve {sketch?, angle?, axis?: "x"|"y", operation?, body?} — about a
  sketch axis; angle defaults to 360.
EVERY OTHER 2D TOOL, through one op:
- sketch_tool {sketch?, tool, points: [[x,y], ...], radius?, distance?,
  distance2?, angle?, sides?, mode?, expr?} — draws with the app's own tool,
  by name, from the same picks a person would make. The ops above are the
  common shapes said in words; this is the rest of the toolbox. EVERY name it
  takes, with the number of picks each one needs — there is no other list,
  and nothing here needs approximating with something else:
    LINES     line (2) · line_midpoint (2, the midpoint then one end) ·
              bridge (2, joins two entities with a smooth link)
    CURVES    spline (2+, through the points) ·
              spline_control (3+, the points PULL the curve) ·
              equation_curve (1, plus `expr` like "t,t*t") ·
              ellipse (3: centre, end of one axis, point on the other)
    CIRCLES   circle (2: centre, then a point on it) ·
              circle_tangent (3 picks on three entities it touches)
    ARCS      arc_centre (3: centre, start, end) ·
              arc_3point (3 the arc passes through) ·
              arc_tangent (2: a point on an entity, then the far end —
              leaves the curve smooth where it meets that entity)
    RECTS     rect (2 opposite corners) · rect_centre (2: centre, corner) ·
              rect_3point (3) · rect_centre_3point (3) — the 3-point forms
              are how a rectangle ends up ROTATED
    SLOTS     slot_centres (3) · slot_overall (3) · slot_centre_point (3) ·
              slot_3arc (4) · slot_centre_arc (4) — sketch_slot is the
              centres form said in numbers, and is usually what you want
    OTHER     polygon_regular (2, with `sides`) · point (1)
    CORNERS   fillet (2, with `radius`) · chamfer (2, with `distance`) —
              these round or cut the corner BETWEEN two sketch entities and
              TRIM them both. The two points pick the two entities, one each,
              near the corner they share. Drawing a corner radius in the
              sketch is more reliable than a 3D fillet on a sharp edge: it
              cannot fail at rebuild time.

SHAPING WHAT IS ALREADY DRAWN:
- sketch_modify {sketch?, action, near?: [[x,y], ...], ...} — the modify
  tools. `near` picks entities, one point each, and with no `near` the whole
  sketch is the selection. Actions:
    move / copy {dx, dy} · rotate {angle, about?: [x,y]} ·
    scale {factor, about?} · mirror {axis: "x"|"y", or x1,y1,x2,y2} ·
    offset {distance} · trim / split {near} · extend {near}
  For trim and split the point does double duty: it picks the entity AND
  says which piece of it you mean. Trim is how two overlapping circles become
  one outline; offset is how a wall gets a constant thickness.

MAKING THE SKETCH EDITABLE — do this on anything you may need to change:
- sketch_constrain {sketch?, type, near: [[x,y], ...]} — coincident,
  collinear, concentric, fix, parallel, perpendicular, horizontal, vertical,
  tangent, smooth, symmetric, equal, midpoint. A constraint that cannot be
  satisfied is not added, and the report says so.
- sketch_dimension {sketch?, near: [[x,y], ...], value,
  kind?: "dist"|"distx"|"disty"|"rad"|"dia"|"ang"} — a DRIVING dimension.
  A rectangle drawn at computed coordinates has no width; one with a
  dimension has a width the user can change afterwards. That difference is
  most of what separates a drawing from a picture.

- sketch_project {sketch?, near?: [[x,y], ...]} — brings the SOLID'S EDGES
  into the sketch as real entities. This is how a second feature lines up
  with the first instead of you re-deriving its coordinates, which is where
  "the hole is 0.3 mm off" comes from. With no `near` the whole projectable
  outline comes across.
- sketch_pattern {sketch?, kind: "rect"|"circ", count, dx?, dy?, angle?,
  about?, near?} — repeats sketch geometry before it is ever extruded, for
  when the copies are meant to be one profile. The copies are independent
  geometry; for occurrences that stay linked to their source, pattern the
  FEATURE in 3D instead.

TWO MORE THINGS THE SKETCHER MAKES:
- sketch_gear {sketch?, teeth, module, x?, y?, bore?, pressure_angle?,
  profile_shift?, internal?, angle?} — a true involute gear. Pitch diameter
  is module × teeth. Never approximate teeth with a polygon.
- sketch_text {sketch?, text, x?, y?, height?} — parametric text that
  extrudes like any other profile, for a label moulded into a part.

THE 3D TOOLS BEYOND EXTRUDE AND REVOLVE:
- hole {sketch?, places: [[x,y], ...] (or x,y), diameter, depth|through_all,
  type?: "simple"|"counterbore"|"spotface"|"countersink", cb_diameter?,
  cb_depth?, cs_diameter?, cs_angle?, flip?} — a real Hole feature, not a cut
  extrusion: it places its own sketch points, carries its mouth geometry, and
  edits as a hole afterwards. Use it for every hole.
- sweep {path_sketch, profile_circle? (a diameter) | profile_width +
  profile_height | profile_sketch, orientation?: "path"|"fixed", taper?,
  operation?} — drives a profile along an open curve. A handle, a pipe run,
  a bead round a rim. A handle is a ROUND tube swept along a path, never an
  extruded outline with a window in it. With profile_circle the app draws the profile at the
  path's start, square to it; a profile_sketch you drew must be that too.
- shell {thickness, open: "top"|"bottom"|... or a list, faces?: ["F3"],
  outward?} — hollows the body to a constant wall, open where you say. The
  wall grows inward, so the outside keeps its size; outward: true keeps the
  inside instead. A cup is a solid cylinder shelled open at the top.
- loft {sketches: [a, b, ...], ruled?, closed?, operation?} — blends through
  two or more sections in the order given. The only feature that changes
  cross-section along its length.
- coil {sketch?, axis?: "x"|"y", method?: "revolution_height"|
  "pitch_revolution"|"pitch_height"|"spiral", revolutions?, height?, pitch?,
  taper?, clockwise?, operation?} — a spring, a thread, a spiral. Give the
  two numbers your method names and the app works out the rest.
- pattern {kind: "rect"|"circ"|"mirror", features?: [name, ...], count?,
  spacing?, direction?, count2?, spacing2?, direction2?, axis?, angle?,
  centre?, plane?, offset?} — one feature that repeats work, instead of
  emitting the same block six times with six chances to mistype a
  coordinate. Omit `features` to pattern the whole body. A bolt circle is
  {"kind": "circ", "axis": "y", "count": 6, "angle": 360}.
- split_body {plane?: "xy"|"xz"|"yz", offset?, flip?, body?} (or px/py/pz +
  nx/ny/nz) — trims everything on one side of a plane away. How a printed
  part is cut to fit the bed.
- combine {tools: [body, ...], operation: "join"|"cut"|"intersect",
  keep_tool?, body?} — a boolean between whole BODIES, as against the
  boolean an extrude does against the body it lands in.
- fillet {radius, edges?: "all"|"outer"|"holes"|"convex"|"concave"|
  "vertical"|"horizontal", body?, near?: [[x,y,z], ...]} — rounds live edges.
  "outer" excludes every circular edge, which is what you want when you mean
  the outside corners and not the mouths of the holes; "holes" is only those
  mouths. The report names what it actually caught — read it.
- chamfer {distance, edges?, body?, near?} — same selection as fillet.
- edit_feature {feature, distance?, distance_b?, taper?, angle?, radius?,
  thickness?, operation?} — changes an existing feature and rebuilds.
- delete_feature {feature}.
- rename_feature {feature, name}.
- knowledge {id} — opens ONE reference document from the knowledge base by its
  id. The documents matching this request are already in your instructions, in
  full; this is for one you decide you want afterwards. It reads nothing about
  the part, so put it in the SAME block as real work rather than spending a
  round on it.
- brief_note {text, kind?: "must"|"prefer"|"assumption", source?} — records a
  requirement for THIS document so it survives the conversation. `text` is
  your reading of it; `source` is the user's own words, quoted exactly. Record
  a requirement the moment you learn it, and record your own assumptions as
  "assumption" so the user can correct them. Never record a "must" the user
  did not actually state.
- brief_done {id} — marks a recorded requirement satisfied.
''';

/// Keys in a tool message that describe the document AS IT WAS at that
/// moment, and are therefore wrong by the time the next block has run.
const Set<String> kAiSupersededKeys = {
  'partAfter',
  'shape',
  'silhouette',
  'part',
  'partNow',
};

/// The conversation as it should be SENT, with superseded state removed from
/// every tool message but the newest one.
///
/// ISSUE #72 (follow-up) — "it used way too many tokens". Every round resends
/// the whole conversation, and every block's report carried a full snapshot
/// of the document plus, after a `look`, a whole silhouette. Six rounds in,
/// the model was being sent six descriptions of a part that only one of them
/// still described, and paying for all six. It is also the answer to "hard
/// for an LLM to get": the most confusing thing in that transcript was five
/// stale copies of the truth sitting next to the current one.
///
/// What is NEVER removed: which actions ran and what they returned, any
/// error, and the newest state. The record of what was done stays complete;
/// only descriptions the document has since invalidated are dropped, and each
/// one says so where it stood.
List<AiMessage> aiCompactTurns(List<AiMessage> turns) {
  var newestTool = -1;
  for (var i = 0; i < turns.length; i++) {
    if (turns[i].role == 'tool') newestTool = i;
  }
  if (newestTool < 0) return turns;
  final out = <AiMessage>[];
  for (var i = 0; i < turns.length; i++) {
    final m = turns[i];
    if (m.role != 'tool' || i == newestTool) {
      out.add(m);
      continue;
    }
    final trimmed = _stripSuperseded(m.text);
    // THE PICTURES GO WITH THE SNAPSHOT THEY SHOW. Since #82 every block that
    // changes the geometry carries a render — about 190 KB of PNG and a
    // vision-token bill — of a part the next block supersedes. They were
    // dropped here before only BY ACCIDENT: rebuilding the message for its
    // trimmed text did not pass the attachments on, so an image survived
    // exactly when the text had nothing to trim. That is now the rule rather
    // than a side effect, in both directions: only the newest tool turn keeps
    // its images, anything that is not an image stays, and what the USER
    // attached lives on user turns and is never touched.
    final images = m.attachments.where((a) => a.isImage).length;
    if (trimmed == null && images == 0) {
      out.add(m);
      continue;
    }
    out.add(AiMessage(
        id: m.id,
        role: m.role,
        text: trimmed ?? m.text,
        attachments: [
          for (final a in m.attachments)
            if (!a.isImage) a
        ],
        provider: m.provider,
        contextLabel: m.contextLabel,
        createdAt: m.createdAt));
  }
  return out;
}

String? _stripSuperseded(String text) {
  Object? parsed;
  try {
    parsed = jsonDecode(text);
  } catch (_) {
    return null;
  }
  if (parsed is! Map) return null;
  final map = Map<String, dynamic>.from(parsed);
  var removed = false;
  for (final key in kAiSupersededKeys) {
    if (map.remove(key) != null) removed = true;
  }
  if (!removed) return null;
  map['superseded'] = 'The document has changed since. Run describe_part or '
      'describe_shape if you need this again.';
  return jsonEncode(map);
}

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
