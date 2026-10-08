// #92 — "Sobald der Prompt abgesendet wird will ich Arbeit sehen … max 5 sek
// denken."
//
// A DeepSeek round used to be one request and one wait: the app knew nothing
// until the whole reply had arrived, so it could neither show that the model
// had started writing nor stop it from thinking for 79 seconds. Measured on
// the report: one turn, ten rounds, 278 s, of which the kernel took well
// under one; round 5 thought for 17,635 tokens and 78.7 s, then wrote a block
// that did not even parse. `reasoning_effort: "low"` was already being sent.
// It is a hint, not a limit.
//
// Streaming is what makes a limit possible. Each server-sent event carries a
// delta of either the reasoning or the answer, so the app sees the moment the
// model moves from one to the other, and can cut a round that is still only
// thinking when the budget runs out.

import 'dart:convert';

/// How long one round may think before the app cuts it and asks again with
/// thinking off. The owner's own number (#92: "max 5 sek oder so").
const Duration kAiThinkingBudget = Duration(seconds: 5);

/// Where a streamed reply is. Reported on each change, never repeated.
enum AiStreamStage {
  /// The model is reasoning; nothing of the answer has arrived.
  thinking,

  /// The answer itself is arriving.
  writing,
}

/// Reassembles DeepSeek's `stream: true` chat completion into the same map a
/// non-streamed completion returns, so everything downstream reads one shape.
///
/// It also accepts a plain, non-streamed JSON body — what a proxy that ignores
/// `stream`, or a test double, sends back — and then simply decodes it.
class DeepSeekStreamAssembler {
  final StringBuffer _content = StringBuffer();
  final StringBuffer _reasoning = StringBuffer();
  final StringBuffer _plain = StringBuffer();
  String? _id, _model, _finish;
  Map<String, dynamic>? _usage;
  bool? _streamed;
  bool _done = false;
  AiStreamStage? _stage;
  int _chars = 0;

  /// Characters taken in so far, for the size guard.
  int get chars => _chars;

  /// The answer so far, and its length.
  String get content => _content.toString();
  int get contentLength => _content.length;

  /// The stage the reply is in, or null before its first delta.
  AiStreamStage? get stage => _stage;

  /// Whether the `[DONE]` sentinel has been seen.
  bool get done => _done;

  /// Whether this body turned out to be server-sent events at all.
  bool get streamed => _streamed ?? false;

  /// How much reasoning has arrived. Only meaningful while [streamed].
  int get reasoningChars => _reasoning.length;

  /// Takes one line of the body. Returns the new stage when this line moved
  /// the reply into one, null otherwise.
  AiStreamStage? addLine(String line) {
    _chars += line.length + 1;
    if (_streamed == null) {
      final t = line.trimLeft();
      if (t.isEmpty) return null;
      _streamed = t.startsWith('data:') || t.startsWith(':');
    }
    if (_streamed == false) {
      _plain.writeln(line);
      return null;
    }
    if (!line.startsWith('data:')) return null; // comments, keep-alives
    final payload = line.substring(5).trim();
    if (payload.isEmpty) return null;
    if (payload == '[DONE]') {
      _done = true;
      return null;
    }
    final chunk = jsonDecode(payload) as Map<String, dynamic>;
    _id ??= chunk['id'] as String?;
    _model ??= chunk['model'] as String?;
    final usage = chunk['usage'];
    if (usage is Map) _usage = usage.cast<String, dynamic>();
    final choices = chunk['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final choice = (choices.first as Map).cast<String, dynamic>();
    final finish = choice['finish_reason'];
    if (finish is String) _finish = finish;
    final delta = choice['delta'];
    if (delta is! Map) return null;
    AiStreamStage? moved;
    final r = delta['reasoning_content'];
    if (r is String && r.isNotEmpty) {
      _reasoning.write(r);
      if (_stage == null) moved = _stage = AiStreamStage.thinking;
    }
    final c = delta['content'];
    if (c is String && c.isNotEmpty) {
      _content.write(c);
      if (_stage != AiStreamStage.writing) {
        moved = _stage = AiStreamStage.writing;
      }
    }
    return moved;
  }

  /// The whole reply, in the non-streamed completion's shape.
  Map<String, dynamic> toResponse() {
    if (_streamed != true) {
      return jsonDecode(_plain.toString()) as Map<String, dynamic>;
    }
    return {
      if (_id != null) 'id': _id,
      'object': 'chat.completion',
      if (_model != null) 'model': _model,
      'choices': [
        {
          'index': 0,
          'message': {
            'role': 'assistant',
            'content': _content.toString(),
            if (_reasoning.isNotEmpty)
              'reasoning_content': _reasoning.toString(),
          },
          'finish_reason': _finish,
        }
      ],
      if (_usage != null) 'usage': _usage,
      'streamed': true,
    };
  }
}

/// Reassembles Anthropic's `stream: true` Messages response into the same map
/// a non-streamed response returns, so everything downstream reads one shape.
///
/// Claude streams for the same reason DeepSeek does, plus one of its own: with
/// thinking on and a large `max_tokens`, a non-streamed request can sit silent
/// for minutes and die on an HTTP timeout. A stream also lets the panel say
/// "thinking" vs "writing", and lets a program start running while the rest of
/// it is still being written.
///
/// It also accepts a plain JSON body (a test double, a proxy that ignored
/// `stream`) and then simply decodes it.
class AnthropicStreamAssembler {
  final StringBuffer _plain = StringBuffer();
  final List<Map<String, dynamic>> _blocks = [];
  final StringBuffer _text = StringBuffer();
  Map<String, dynamic> _message = {};
  Map<String, dynamic> _usage = {};
  String? _stopReason;
  Object? _stopDetails;
  Map<String, dynamic>? _error;
  bool? _streamed;
  AiStreamStage? _stage;
  int _chars = 0;

  int get chars => _chars;
  String get content => _text.toString();
  int get contentLength => _text.length;
  AiStreamStage? get stage => _stage;
  bool get streamed => _streamed ?? false;

  /// The `error` event's payload, if the stream ended in one (an overload
  /// mid-stream arrives this way, after a 200).
  Map<String, dynamic>? get error => _error;

  AiStreamStage? addLine(String line) {
    _chars += line.length + 1;
    if (_streamed == null) {
      final t = line.trimLeft();
      if (t.isEmpty) return null;
      _streamed =
          t.startsWith('event:') || t.startsWith('data:') || t.startsWith(':');
    }
    if (_streamed == false) {
      _plain.writeln(line);
      return null;
    }
    if (!line.startsWith('data:')) return null; // event names, pings
    final payload = line.substring(5).trim();
    if (payload.isEmpty) return null;
    final event = jsonDecode(payload) as Map<String, dynamic>;
    switch (event['type']) {
      case 'message_start':
        _message = Map<String, dynamic>.from(event['message'] as Map? ?? {});
        final u = _message['usage'];
        if (u is Map) _usage = Map<String, dynamic>.from(u);
        return null;
      case 'content_block_start':
        final block =
            Map<String, dynamic>.from(event['content_block'] as Map? ?? {});
        // A server-side fallback re-runs the request on another model and
        // marks the seam with a `fallback` block. Whatever the first model
        // wrote before it is not part of the answer that follows.
        if (block['type'] == 'fallback') {
          _text.clear();
          _blocks.clear();
          _stage = null;
        }
        _blocks.add(block);
        if (block['type'] == 'thinking' ||
            block['type'] == 'redacted_thinking') {
          if (_stage == null) return _stage = AiStreamStage.thinking;
        }
        return null;
      case 'content_block_delta':
        if (_blocks.isEmpty) return null;
        final block = _blocks.last;
        final delta = event['delta'] as Map? ?? const {};
        switch (delta['type']) {
          case 'text_delta':
            final t = delta['text'] as String? ?? '';
            block['text'] = '${block['text'] ?? ''}$t';
            if (t.isEmpty) return null;
            _text.write(t);
            if (_stage != AiStreamStage.writing) {
              return _stage = AiStreamStage.writing;
            }
            return null;
          case 'thinking_delta':
            block['thinking'] =
                '${block['thinking'] ?? ''}${delta['thinking'] ?? ''}';
            return null;
          case 'signature_delta':
            block['signature'] = delta['signature'];
            return null;
        }
        return null;
      case 'message_delta':
        final d = event['delta'] as Map? ?? const {};
        if (d['stop_reason'] != null) _stopReason = d['stop_reason'] as String;
        if (d['stop_details'] != null) _stopDetails = d['stop_details'];
        final u = event['usage'];
        if (u is Map) _usage.addAll(Map<String, dynamic>.from(u));
        return null;
      case 'error':
        _error = Map<String, dynamic>.from(event['error'] as Map? ?? {});
        return null;
    }
    return null;
  }

  Map<String, dynamic> toResponse() {
    if (_streamed != true) {
      return jsonDecode(_plain.toString()) as Map<String, dynamic>;
    }
    return {
      ..._message,
      'content': _blocks,
      'stop_reason': _stopReason,
      if (_stopDetails != null) 'stop_details': _stopDetails,
      'usage': _usage,
      if (_error != null) 'error': _error,
      'streamed': true,
    };
  }
}
