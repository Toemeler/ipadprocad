// Prototype — the assistant's flight recorder.
//
// WHY THIS FILE EXISTS. "the ai answered something wrong" is a bug report that
// the bundle could not answer a single question about. Everything that would
// have answered it was deliberately thrown away one line after it arrived:
//
//   * TOKENS. Every provider returns a usage block — `usage.input_tokens`,
//     `usageMetadata.promptTokenCount`, `usage.prompt_tokens` — and
//     `_respond` read `content`/`candidates`/`choices` and dropped the rest.
//     So "why did this cost so much" and "did the context even fit" had no
//     evidence anywhere in the app.
//   * THINKING. Gemini's thought parts are filtered out by `p['thought'] !=
//     true`, DeepSeek's `reasoning_content` has a comment saying it is
//     deliberately not read, and Claude's thinking blocks fall out of the
//     `type == 'text'` filter. All three are correct decisions about what to
//     SHOW the user, and all three removed the only record of how the model
//     got to an answer it got wrong.
//   * THE ERROR. `AiException` carries a code — 'response', 'network' — and
//     the provider's own error body, the HTTP status, and the Apple
//     `PlatformException` code and message were all discarded at the throw.
//     Six different faults arrive at the user as one sentence, and the bundle
//     recorded which sentence, not which fault.
//   * THE REQUEST. What was actually sent — the instructions, the document
//     context, the conversation as the wire saw it — existed for the length of
//     one `jsonEncode` and was never on disk.
//   * THE TOOL USES. The action report is persisted (it is a 'tool' message),
//     but what the model ASKED for, how long each op took, and which one of
//     them triggered a rollback were not.
//
// So the ring below keeps all of it, in memory, bounded, and hands it to the
// bug bundle when the button is pressed. Nothing here is written to the
// rolling log: a prompt is the user's document in prose and a 200 KB request
// body would bury every other line. `log.dart` gets a headline per event and
// this gets the substance.
//
// NO CREDENTIALS, EVER. Keys travel in HTTP headers, which are not recorded at
// all, and [scrub] additionally blanks anything key-shaped that finds its way
// into a body. Attachment bytes are replaced by a descriptor — a 4 MB base64
// image in the trace would push the bundle straight back over the upload
// budget that #46 was about, and "image/png, 3.1 MB" answers every question
// the bytes would have.
library;

import 'dart:convert';

/// One thing the AI layer did, with everything that was known about it.
class AiTraceEvent {
  AiTraceEvent(
    this.kind, {
    this.requestId,
    this.sessionId,
    this.round,
    Map<String, dynamic> data = const {},
  })  : at = DateTime.now().toUtc(),
        sinceStartMs = AiTrace.clock.elapsedMilliseconds,
        data = AiTrace.scrub(data) as Map<String, dynamic>;

  /// A dotted name: `turn.begin`, `http.response`, `usage`, `thinking`,
  /// `action`, `error`. Dotted so a reader can grep one family out of a long
  /// trace without knowing the whole vocabulary.
  final String kind;
  final DateTime at;
  final int sinceStartMs;

  /// The backend request this belongs to. Every event of one round shares it,
  /// which is what makes a round reconstructable from a flat list.
  final String? requestId;

  /// The conversation. Survives across rounds and across requests, so the
  /// whole history of one session can be pulled out of the trace.
  final String? sessionId;

  /// Which pass of the model -> actions -> results -> model loop this was.
  final int? round;

  final Map<String, dynamic> data;

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        'tMs': sinceStartMs,
        'kind': kind,
        if (requestId != null) 'request': requestId,
        if (sessionId != null) 'session': sessionId,
        if (round != null) 'round': round,
        ...data,
      };

  /// Roughly what this event costs the ring. Approximate on purpose: the exact
  /// figure would mean encoding every event twice, and the budget only has to
  /// be right to within a factor of two to do its job.
  int get weight {
    var n = 64;
    void walk(Object? v) {
      if (v is String) {
        n += v.length;
      } else if (v is Map) {
        for (final e in v.entries) {
          n += (e.key as String?)?.length ?? 8;
          walk(e.value);
        }
      } else if (v is Iterable) {
        for (final x in v) {
          walk(x);
        }
      } else {
        n += 8;
      }
    }

    walk(data);
    return n;
  }

  /// The human-readable form. Scalars on the header line, long text indented
  /// beneath it — a reader opening `ai/trace.txt` is looking for the shape of
  /// a conversation first and the prompt bodies second.
  List<String> lines() {
    final head = StringBuffer()
      ..write('[${(sinceStartMs / 1000).toStringAsFixed(3).padLeft(9)}s] ')
      ..write(at.toIso8601String())
      ..write('  ')
      ..write(kind.padRight(18));
    if (sessionId != null) head.write(' sess=${_short(sessionId!)}');
    if (requestId != null) head.write(' req=${_short(requestId!)}');
    if (round != null) head.write(' round=$round');
    final out = <String>[head.toString()];
    final long = <String, String>{};
    final short = <String>[];
    for (final e in data.entries) {
      final v = e.value;
      if (v is String && (v.length > 80 || v.contains('\n'))) {
        long[e.key] = v;
      } else if (v is Map || v is Iterable) {
        final encoded = _encode(v);
        if (encoded.length > 80) {
          long[e.key] = encoded;
        } else {
          short.add('${e.key}=$encoded');
        }
      } else {
        short.add('${e.key}=$v');
      }
    }
    if (short.isNotEmpty) out.add('    ${short.join('  ')}');
    for (final e in long.entries) {
      out.add('    --- ${e.key} ---');
      for (final l in const LineSplitter().convert(e.value)) {
        out.add('    $l');
      }
    }
    return out;
  }

  static String _short(String id) =>
      id.length <= 8 ? id : id.substring(0, 8);

  static String _encode(Object? v) {
    try {
      return jsonEncode(v);
    } catch (_) {
      return '$v';
    }
  }
}

/// Running totals for one provider+model pair, across the whole session.
///
/// Kept separately from the ring because the ring forgets: a report filed
/// after a long conversation should still be able to say what the whole of it
/// cost, even when the first twenty rounds have been evicted.
class AiTokenTotals {
  AiTokenTotals(this.provider, this.model);
  final String provider;
  final String model;
  int requests = 0;
  int input = 0;
  int output = 0;
  int reasoning = 0;
  int cacheRead = 0;
  int cacheWrite = 0;

  void add(Map<String, dynamic> usage) {
    requests++;
    input += _n(usage['input']);
    output += _n(usage['output']);
    reasoning += _n(usage['reasoning']);
    cacheRead += _n(usage['cacheRead']);
    cacheWrite += _n(usage['cacheWrite']);
  }

  static int _n(Object? v) => v is num ? v.toInt() : 0;

  Map<String, dynamic> toJson() => {
        'provider': provider,
        'model': model,
        'requests': requests,
        'input': input,
        'output': output,
        if (reasoning > 0) 'reasoning': reasoning,
        if (cacheRead > 0) 'cacheRead': cacheRead,
        if (cacheWrite > 0) 'cacheWrite': cacheWrite,
        'total': input + output,
      };

  @override
  String toString() => '$provider · ${model.isEmpty ? '(default)' : model}: '
      '$requests request(s), in=$input out=$output'
      '${reasoning > 0 ? ' reasoning=$reasoning' : ''}'
      '${cacheRead > 0 ? ' cacheRead=$cacheRead' : ''}'
      '${cacheWrite > 0 ? ' cacheWrite=$cacheWrite' : ''} '
      'total=${input + output}';
}

/// The ring itself. Static because there is one AI layer per process and a
/// bug report is taken from wherever the button was pressed, with no handle to
/// an instance in between — the same reason [GestureTrace] and [RealityPush]
/// are static.
class AiTrace {
  AiTrace._();

  /// Off switch. Tests that assert on an empty trace, and one place to turn
  /// the whole facility off if it is ever not wanted.
  static bool enabled = true;

  /// Events. A conversation of eight rounds produces roughly forty, so this is
  /// several long sessions rather than "the last thing that happened".
  static const int capacity = 600;

  /// ...and the budget that actually binds, because one event can be a 200 KB
  /// request body and six hundred of those are not a bug report, they are a
  /// reason the upload fails. Oldest events are dropped until the ring fits.
  static const int maxBytes = 3 * 1024 * 1024;

  /// The longest single string kept verbatim. Prompts and replies are the
  /// point of this file, so it is generous; what it stops is one pathological
  /// member eating the whole budget on its own.
  static const int maxStringChars = 120000;

  /// Above this, a string under a base64-ish key is replaced by its size.
  static const int base64Threshold = 256;

  static final Stopwatch clock = Stopwatch()..start();
  static final List<AiTraceEvent> _ring = <AiTraceEvent>[];
  static final Map<String, AiTokenTotals> _totals = {};
  static int _bytes = 0;
  static int _dropped = 0;

  /// Field names whose value is never recorded, whatever it contains.
  static const Set<String> _secret = {
    'key',
    'apikey',
    'api_key',
    'authorization',
    'x-api-key',
    'x-goog-api-key',
    'accesstoken',
    'access_token',
    'refreshtoken',
    'refresh_token',
    'clientsecret',
    'client_secret',
    'password',
    'token',
  };

  /// Field names that carry attachment payloads rather than text.
  static const Set<String> _binary = {'data', 'bytes', 'base64', 'inlinedata'};

  /// Copies [value], blanking credentials and replacing attachment payloads
  /// with a description of what was there.
  ///
  /// A copy rather than an edit in place: the caller is handing us a live
  /// request body, and a recorder that mutated it would change what is sent.
  static Object? scrub(Object? value, [int depth = 0]) {
    if (depth > 12) return '<depth limit>';
    if (value is Map) {
      final out = <String, dynamic>{};
      for (final e in value.entries) {
        final key = '${e.key}';
        final norm = key.replaceAll(RegExp(r'[-_\s]'), '').toLowerCase();
        if (_secret.contains(norm) || _secret.contains(key.toLowerCase())) {
          out[key] = '<redacted>';
          continue;
        }
        final v = e.value;
        if (_binary.contains(norm) &&
            v is String &&
            v.length > base64Threshold) {
          // base64 is 4 characters per 3 bytes; the decoded size is what a
          // reader is actually asking about.
          out[key] = '<binary payload, ~${(v.length * 3) ~/ 4} bytes, '
              '${v.length} base64 chars>';
          continue;
        }
        out[key] = scrub(v, depth + 1);
      }
      return out;
    }
    if (value is Iterable) {
      return [for (final v in value) scrub(v, depth + 1)];
    }
    if (value is String && value.length > maxStringChars) {
      return '${value.substring(0, maxStringChars)}\n'
          '<${value.length - maxStringChars} more characters omitted>';
    }
    if (value is num && !value.isFinite) return '$value';
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    return '$value';
  }

  static void record(
    String kind, {
    String? requestId,
    String? sessionId,
    int? round,
    Map<String, dynamic> data = const {},
  }) {
    if (!enabled) return;
    final event = AiTraceEvent(kind,
        requestId: requestId, sessionId: sessionId, round: round, data: data);
    _ring.add(event);
    _bytes += event.weight;
    while (_ring.length > capacity || (_bytes > maxBytes && _ring.length > 1)) {
      _bytes -= _ring.removeAt(0).weight;
      _dropped++;
    }
  }

  /// Records a usage block and adds it to the running totals.
  ///
  /// [usage] is the NORMALISED shape — input/output/reasoning/cacheRead/
  /// cacheWrite — because three providers spell the same five numbers five
  /// different ways and a reader comparing two bundles should not have to
  /// know which. The provider's own block goes in beside it under `raw`, so
  /// nothing is lost to the normalisation.
  static void usage({
    required String provider,
    required String model,
    required String requestId,
    String? sessionId,
    int? round,
    required Map<String, dynamic> usage,
    Object? raw,
  }) {
    final key = '$provider/$model';
    (_totals[key] ??= AiTokenTotals(provider, model)).add(usage);
    record('usage',
        requestId: requestId,
        sessionId: sessionId,
        round: round,
        data: {
          'provider': provider,
          if (model.isNotEmpty) 'model': model,
          ...usage,
          if (raw != null) 'raw': raw,
        });
  }

  static List<AiTraceEvent> get events => List.unmodifiable(_ring);

  static List<AiTokenTotals> get totals =>
      List.unmodifiable(_totals.values);

  /// Every token this app has spent since launch, across all providers.
  static Map<String, dynamic> get totalsJson => {
        'perProvider': [for (final t in _totals.values) t.toJson()],
        'requests':
            _totals.values.fold<int>(0, (n, t) => n + t.requests),
        'input': _totals.values.fold<int>(0, (n, t) => n + t.input),
        'output': _totals.values.fold<int>(0, (n, t) => n + t.output),
        'reasoning': _totals.values.fold<int>(0, (n, t) => n + t.reasoning),
      };

  /// How many events fell off the front of the ring. Stated in the dump so a
  /// reader knows the trace does not start at the first request.
  static int get dropped => _dropped;

  /// The machine-readable form: `ai/trace.json`.
  static Map<String, dynamic> json() => {
        'droppedEvents': _dropped,
        'events': [for (final e in _ring) e.toJson()],
        'tokenTotals': totalsJson,
      };

  /// The human-readable form: `ai/trace.txt`.
  static List<String> dump() {
    final out = <String>[];
    if (_ring.isEmpty) {
      return ['(no AI request has been made in this session)'];
    }
    if (_dropped > 0) {
      out.add('[$_dropped earlier event(s) dropped — the ring holds the most '
          'recent $capacity events or ${maxBytes ~/ 1024} KiB, whichever '
          'binds first]');
      out.add('');
    }
    for (final t in _totals.values) {
      out.add('TOKENS  $t');
    }
    if (_totals.isNotEmpty) out.add('');
    for (final e in _ring) {
      out.addAll(e.lines());
    }
    return out;
  }

  /// For tests, and for "delete all conversations" — a trace that outlived the
  /// conversation it describes would put the deleted messages back into the
  /// next bug report.
  static void clear() {
    _ring.clear();
    _totals.clear();
    _bytes = 0;
    _dropped = 0;
  }
}
