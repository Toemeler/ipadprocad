import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../l10n/l.dart';
import '../log.dart';
import 'ai_models.dart';
import 'ai_trace.dart';

/// What one reply may cost in output tokens.
///
/// 4096 was fine while every provider spent its budget on the ANSWER. It is
/// not fine for a reasoning model: DeepSeek counts `reasoning_content` against
/// the same allowance, so a request big enough to think about ("make me an
/// espresso cup with a handle") spends the whole budget reasoning and returns
/// `finish_reason: "length"` with an EMPTY message. The turn then fails, the
/// draft is rolled back, and the transcript is left empty — which is issue #70
/// exactly: a minute of "thinking" and then nothing.
const int kAiMaxOutputTokens = 8192;

/// How many times a truncated reply is retried with more room before the user
/// is told anything.
///
/// "Frag in kleineren Schritten" is the app asking the USER to work around a
/// budget the app chose. A reply cut off mid-thought is recoverable without
/// them: ask again with a bigger allowance and less reasoning. Bounded,
/// because a model that fills 32k three times is not going to fit in four.
const int kAiMaxTruncationRetries = 2;

/// For a provider whose API makes the field mandatory.
int aiRequiredOutputBudget(int attempt) => switch (attempt) {
      <= 0 => kAiMaxOutputTokens,
      1 => kAiMaxOutputTokens * 4,
      _ => kAiMaxOutputTokens * 8,
    };

/// The largest output DeepSeek's chat completions accept, from its own
/// parameter documentation: 1 to 384K.
const int kDeepSeekMaxOutputTokens = 393216;

/// The output allowance for one attempt, or NULL to send no cap at all.
///
/// THE CAP WAS THE BUG. Sending `max_tokens: 8192` looked conservative and
/// was the opposite: DeepSeek's default when the field is ABSENT is 8K in
/// non-thinking mode and 64K in thinking mode (128K at reasoning_effort
/// "max"). So an explicit 8192 took a thinking model down to an eighth of
/// what it would have had on its own — and then the app told the user to ask
/// for a smaller step.
///
/// So the ordinary turn sends no cap and gets the model's own maximum. Only a
/// retry names a number, and only because by then the model's own default has
/// already proved too small; it has to be explicit there because the retry
/// also lowers reasoning_effort, and "none" would otherwise drop the implicit
/// default back to 8K.
int? aiOutputBudget(int attempt) => switch (attempt) {
      <= 0 => null,
      1 => kDeepSeekMaxOutputTokens ~/ 3,
      _ => kDeepSeekMaxOutputTokens ~/ 2,
    };

class AiCapabilities {
  const AiCapabilities(
      {required this.provider,
      required this.label,
      required this.available,
      this.supportsImages = true,
      this.maxInputBytes = 180000});
  final AiProvider provider;
  final String label;
  final bool available;
  final bool supportsImages;
  final int maxInputBytes;
}

class AiRequest {
  AiRequest(
      {required this.id,
      required this.instructions,
      required this.context,
      required List<AiMessage> messages,
      this.sessionId,
      this.round,
      this.attempt = 0,
      this.thorough = false})
      : messages = List.unmodifiable(messages);
  final String id;
  final String instructions;
  final String context;
  final List<AiMessage> messages;

  /// Which conversation this belongs to, and which pass of the action loop it
  /// is. Carried only so [AiTrace] can stitch a flat event list back into
  /// rounds and sessions; nothing on the wire depends on either.
  final String? sessionId;
  final int? round;

  /// Which try this is. 0 is the ordinary one; a higher number means the last
  /// attempt came back truncated, and the backend answers with a larger
  /// output allowance and less reasoning. See [aiOutputBudget].
  final int attempt;

  /// Whether this turn is doing work worth deliberating over — set by the
  /// controller from the document's own open requirements, never by the user.
  /// See [deepSeekReasoningEffort].
  final bool thorough;
}

class AiReply {
  const AiReply(this.text, this.provider);
  final String text;
  final String provider;
}

/// Injectable boundary: tests exercise races and persistence without a real key.
abstract class AiBackend {
  Future<AiCapabilities> capabilities(AiPreferences preferences);
  Future<bool> hasKey(AiProvider provider);
  Future<void> saveKey(AiProvider provider, String key);
  Future<void> removeKey(AiProvider provider);
  Future<AiReply> respond(AiPreferences preferences, AiRequest request);
  Future<void> cancel(String requestId);
  Future<AiAttachment?> pasteImage();
  void dispose();
}

/// No provider credentials, prompts, response bodies or document paths are logged.
/// Hosts are fixed; redirects are disabled so credentials cannot follow them.
/// Which DeepSeek models accept image input.
///
/// This app treated "DeepSeek" as a synonym for "text only", which was true
/// of deepseek-chat and deepseek-reasoner and stopped being true when the V4
/// line landed: DeepSeek-V4.1-Flash is natively multimodal, and its docs list
/// `image` among the model's input modalities. The cost of the stale
/// assumption was not an inconvenience — `look` rendered a view, the app
/// dropped it, and the report told the model it had NOT seen anything, every
/// single time (issue #72).
///
/// Decided from the MODEL ID rather than a hard-coded provider flag, so a
/// model DeepSeek ships next does not need a code change to be usable, and a
/// text-only model is never sent an image it will 400 on. Legacy ids that the
/// service reroutes server-side (deepseek-v4-pro has routed to V4.1-Flash
/// since 2026-09-14) are deliberately NOT assumed to accept image parts under
/// their old name: the routing is documented, accepting multimodal content
/// under the retired id is not, and a wrong guess here costs a failed request
/// rather than a missing feature.
bool deepSeekTakesImages(String model) {
  final m = model.toLowerCase();
  return m.contains('flash') || m.contains('vision');
}

/// The DeepSeek model this app asks for unless the user says otherwise.
///
/// DeepSeek-V4.1-Flash. It is the one currently-served DeepSeek model that
/// accepts images, which for this app is not a nicety — `look` is how the
/// assistant checks its own work, and on a text-only model it never sees a
/// render at all (issue #72). Its thinking is also controllable, which the
/// V4-Pro line's is not: see [deepSeekReasoningEffort].
const String kDeepSeekDefaultModel = 'deepseek-flash';

/// Model ids this app will move OFF automatically, once.
///
/// Two of them are defaults this app itself shipped, and the third is the one
/// the user was left on. None was a considered choice by anyone, and every one
/// of them is blind.
const Set<String> kDeepSeekSupersededModels = {
  'deepseek-chat',
  'deepseek-reasoner',
  'deepseek-v4-pro',
};

/// Whether this model takes DeepSeek's thinking controls.
bool deepSeekTakesThinking(String model) =>
    model.toLowerCase().contains('flash');

/// How hard the model should think on this round.
///
/// MEASURED, on the session in issue #72: 8,906 of 9,662 output tokens were
/// reasoning — 92%. A single `{"op": "fillet", "radius": 2}` cost 424
/// reasoning tokens and eleven seconds, and the round after it 833 and twenty
/// seconds. That is not thought the part benefits from; it is the model
/// re-deriving the whole task before emitting two lines of JSON.
///
/// The first round of a turn is where the judgement actually lives: what the
/// user asked for, what to ask back, what the part should be. Every round
/// after it is execution against a plan the model already has, with the
/// result of the last block in front of it. So: full effort once, low effort
/// thereafter.
/// How hard to think, decided by the app, with nothing for the user to set.
///
/// THE ROUND NUMBER WAS THE WRONG SIGNAL. Tying full effort to round 0 meant
/// every turn paid for deliberation whether or not it needed any: in the
/// measured session, round 0 spent 1,922 reasoning tokens and 42 seconds
/// producing a single clarifying question. "Add a 5 mm hole" would have paid
/// the same.
///
/// The right signal is already in the document. The instructions tell the
/// model to write down what "done" means as `must` requirements before
/// building a whole object, and to ask about the manufacturing process first.
/// So an open "must" IS the record that a big job is in progress — and a
/// narrow change never creates one. "Add a hole" stays cheap end to end;
/// "make me a tea cup" thinks hard exactly while there is something
/// outstanding to think about.
///
/// It is also the model's own lever, through a mechanism that already exists
/// and that the user can see in the panel: what it recorded is what it gets.
///
/// A retry means the last answer did not fit the model's own ceiling, and on
/// this model reasoning is what fills that ceiling — so each attempt thinks
/// less as well as getting more room.
String deepSeekReasoningEffort({required bool thorough, int attempt = 0}) {
  if (attempt >= 2) return 'none';
  if (attempt == 1) return 'low';
  return thorough ? 'high' : 'low';
}

class DeviceAiBackend implements AiBackend {
  DeviceAiBackend({http.Client Function()? clientFactory})
      : _clientFactory = clientFactory ?? http.Client.new;
  static const _channel = MethodChannel('prototype/native_menu');
  static const _vault = FlutterSecureStorage();
  final http.Client Function() _clientFactory;
  final Map<String, http.Client> _clients = {};
  final Set<String> _cancelled = {};
  final Set<String> _nativeRequests = {};
  final Set<String> _pendingRequests = {};
  bool _disposed = false;

  Future<String?> _readKey(AiProvider provider) async {
    if (provider == AiProvider.apple) return null;
    try {
      return Platform.isIOS
          ? await _channel.invokeMethod<String>(
              'aiCredentialRead', {'provider': provider.name})
          : await _vault.read(key: 'prototype.ai.${provider.name}');
    } catch (_) {
      throw const AiException('secureStorage');
    }
  }

  @override
  Future<bool> hasKey(AiProvider provider) async =>
      (await _readKey(provider))?.isNotEmpty ?? false;

  @override
  Future<void> saveKey(AiProvider provider, String key) async {
    final clean = key.trim();
    if (provider == AiProvider.apple ||
        clean.isEmpty ||
        clean.length > 4096 ||
        RegExp(r'[\x00-\x20\x7f]').hasMatch(clean))
      throw const AiException('credentials');
    try {
      if (Platform.isIOS) {
        await _channel.invokeMethod<bool>(
            'aiCredentialWrite', {'provider': provider.name, 'key': clean});
      } else {
        await _vault.write(key: 'prototype.ai.${provider.name}', value: clean);
      }
    } catch (_) {
      throw const AiException('secureStorage');
    }
  }

  @override
  Future<void> removeKey(AiProvider provider) async {
    if (provider == AiProvider.apple) return;
    try {
      if (Platform.isIOS) {
        await _channel.invokeMethod<bool>(
            'aiCredentialDelete', {'provider': provider.name});
      } else {
        await _vault.delete(key: 'prototype.ai.${provider.name}');
      }
    } catch (_) {
      throw const AiException('secureStorage');
    }
  }

  /// The provider's own name, never a localised string: it identifies WHICH
  /// service a reply was billed to, and that is the same word in every
  /// language.
  static String providerName(AiProvider provider) => switch (provider) {
        AiProvider.gemini => 'Gemini',
        AiProvider.anthropic => 'Claude',
        AiProvider.deepseek => 'DeepSeek',
        AiProvider.apple => 'Apple Intelligence',
      };

  /// The last raw `aiCapabilities` map the runner returned, including the
  /// `reason` string that says WHY Apple Intelligence is unavailable. The
  /// typed [AiCapabilities] has nowhere to put it, and "unavailable" without
  /// the reason is four different bugs wearing one label — a device that is
  /// not eligible, a feature switched off in Settings, a model still
  /// downloading, and a quota that is spent.
  Map<String, dynamic>? appleDetail;

  /// What was last traced, so a poll that changes nothing does not fill the
  /// ring. [capabilities] runs on every send, every panel open and every
  /// settings change.
  String? _tracedCaps;

  @override
  Future<AiCapabilities> capabilities(AiPreferences preferences) async {
    try {
      final caps = await _capabilities(preferences);
      _traceCapabilities(preferences, caps);
      return caps;
    } on AiException catch (e) {
      AiTrace.record('capabilities.error',
          data: {'provider': preferences.provider.name, 'code': e.code});
      rethrow;
    }
  }

  void _traceCapabilities(AiPreferences preferences, AiCapabilities caps) {
    final detail = caps.provider == AiProvider.apple ? appleDetail : null;
    final data = <String, dynamic>{
      'provider': caps.provider.name,
      if (preferences.model.isNotEmpty) 'model': preferences.model,
      'available': caps.available,
      'supportsImages': caps.supportsImages,
      'maxInputBytes': caps.maxInputBytes,
      'label': caps.label,
      if (detail != null) ...{
        'route': detail['route'],
        'appleModel': detail['model'],
        'contextTokens': detail['contextTokens'],
        'privateCloudComputeAvailable': detail['privateCloudComputeAvailable'],
        if ((detail['reason'] as String?)?.isNotEmpty ?? false)
          'reason': detail['reason'],
      },
      'allowEdits': preferences.allowEdits,
    };
    final fingerprint = data.toString();
    if (fingerprint == _tracedCaps) return;
    _tracedCaps = fingerprint;
    AiTrace.record('capabilities', data: data);
  }

  Future<AiCapabilities> _capabilities(AiPreferences preferences) async {
    if (preferences.provider != AiProvider.apple &&
        await hasKey(preferences.provider)) {
      appleDetail = null;
      return AiCapabilities(
          provider: preferences.provider,
          available: true,
          // Image support is a property of the MODEL, not of the provider.
          // This said `provider != deepseek` and was simply out of date: it
          // is why every `look` on DeepSeek rendered a view, dropped it, and
          // told the model it had not seen one. See [deepSeekTakesImages].
          supportsImages: preferences.provider != AiProvider.deepseek ||
              deepSeekTakesImages(preferences.model),
          label:
              '${providerName(preferences.provider)} · ${preferences.model}');
    }
    if (!Platform.isIOS) {
      appleDetail = null;
      return AiCapabilities(
          provider: AiProvider.apple,
          available: false,
          supportsImages: false,
          label: L.current.aiSettingsApple);
    }
    try {
      final value =
          await _channel.invokeMapMethod<String, dynamic>('aiCapabilities') ??
              {};
      appleDetail = value;
      return AiCapabilities(
          provider: AiProvider.apple,
          available: value['available'] == true,
          supportsImages: value['supportsImages'] == true,
          maxInputBytes: value['maxInputBytes'] as int? ?? 0,
          label: value['route'] == 'privateCloudCompute'
              ? L.current.aiProviderCloud
              : L.current.aiProviderOnDevice);
    } on MissingPluginException {
      appleDetail = {'reason': 'the host build has no AI plugin'};
      return AiCapabilities(
          provider: AiProvider.apple,
          available: false,
          supportsImages: false,
          label: L.current.aiSettingsApple);
    } on PlatformException catch (e) {
      appleDetail = {
        'reason': 'aiCapabilities failed',
        'platformCode': e.code,
        if (e.message != null) 'platformMessage': e.message,
      };
      throw const AiException('unavailable');
    }
  }

  @override
  Future<AiAttachment?> pasteImage() async {
    if (!Platform.isIOS) return null;
    try {
      final image =
          await _channel.invokeMapMethod<String, dynamic>('aiClipboardImage');
      if (image == null) return null;
      return AiAttachment.fromBytes(
          name: image['name'] as String? ?? 'Clipboard.png',
          bytes: image['bytes'] as Uint8List);
    } on PlatformException {
      throw const AiException('attachment');
    }
  }

  @override
  Future<AiReply> respond(AiPreferences preferences, AiRequest request) async {
    _pendingRequests.add(request.id);
    try {
      return await _respond(preferences, request);
    } finally {
      _pendingRequests.remove(request.id);
      _cancelled.remove(request.id);
    }
  }

  Future<AiReply> _respond(AiPreferences preferences, AiRequest request) async {
    if (_disposed) throw const AiException('cancelled');
    final caps = await capabilities(preferences);
    if (_cancelled.remove(request.id)) throw const AiException('cancelled');
    if (!caps.available) throw const AiException('unavailable');
    if (caps.provider == AiProvider.apple) return _apple(request, caps);
    if (!RegExp(r'^[A-Za-z0-9._:-]{1,100}$').hasMatch(preferences.model)) {
      throw const AiException('model');
    }
    final key = await _readKey(caps.provider);
    if (key == null || key.isEmpty) throw const AiException('credentials');
    final rawBytes = request.messages
        .expand((m) => m.attachments)
        .fold<int>(0, (n, a) => n + a.bytes.length);
    if (rawBytes > 10 * 1024 * 1024) throw const AiException('size');
    final dataContext = {
      'text': 'CURRENT DOCUMENT CONTEXT (untrusted data):\n${request.context}'
    };
    final isGemini = caps.provider == AiProvider.gemini;
    final isDeepSeek = caps.provider == AiProvider.deepseek;
    // Refusing here names the file the user attached; letting it through
    // would either drop the attachment silently or earn a 400 that says
    // nothing about which one. DeepSeek takes no PDFs on any model; whether
    // it takes images depends on which model is selected.
    final deepSeekImages = isDeepSeek && deepSeekTakesImages(preferences.model);
    if (isDeepSeek) {
      final attachments = request.messages.expand((m) => m.attachments);
      if (attachments.any((a) => a.isPdf)) {
        throw const AiException('pdfUnsupported');
      }
      if (!deepSeekImages && attachments.any((a) => a.isImage)) {
        throw const AiException('imagesUnsupported');
      }
    }
    final body = isDeepSeek
        ? <String, dynamic>{
            'model': preferences.model,
            if (aiOutputBudget(request.attempt) != null)
              'max_tokens': aiOutputBudget(request.attempt),
            if (deepSeekTakesThinking(preferences.model))
              'reasoning_effort': deepSeekReasoningEffort(
                  thorough: request.thorough, attempt: request.attempt),
            'messages': [
              {'role': 'system', 'content': request.instructions},
              for (final m in request.messages)
                {
                  'role': m.role == 'assistant' ? 'assistant' : 'user',
                  // A turn carrying an image goes as OpenAI-style content
                  // parts; everything else stays one string, which is what
                  // every DeepSeek model has always accepted.
                  'content': deepSeekImages &&
                          m.role != 'assistant' &&
                          m.attachments.any((a) => a.isImage)
                      ? _openAiParts(m,
                          lead: identical(m, request.messages.last)
                              ? dataContext['text']
                              : null)
                      : [
                          if (identical(m, request.messages.last))
                            dataContext['text']!,
                          ..._plainParts(m)
                        ].join('\n\n'),
                }
            ],
          }
        : isGemini
        ? <String, dynamic>{
            'systemInstruction': {
              'parts': [
                {'text': request.instructions}
              ]
            },
            'contents': request.messages
                .map((m) => {
                      'role': m.role == 'assistant' ? 'model' : 'user',
                      'parts': [
                        if (identical(m, request.messages.last)) dataContext,
                        ..._geminiParts(m)
                      ],
                    })
                .toList(),
            'generationConfig': {
              if (aiOutputBudget(request.attempt) != null)
                'maxOutputTokens': aiOutputBudget(request.attempt)
            },
          }
        : <String, dynamic>{
            'model': preferences.model,
            // Anthropic's Messages API REQUIRES this field, so Claude cannot
            // simply be handed the model's own ceiling the way DeepSeek and
            // Gemini can. It keeps the escalating number, which the retry
            // ladder then raises if a turn really does not fit.
            'max_tokens': aiRequiredOutputBudget(request.attempt),
            'system': request.instructions,
            'messages': request.messages
                .map((m) => {
                      // A 'tool' report is the app speaking to the model, and
                      // this wire format has two roles. It travels as user
                      // content, which is also what it is: input the model did
                      // not write.
                      'role': m.role == 'assistant' ? 'assistant' : 'user',
                      'content': [
                        if (identical(m, request.messages.last))
                          {'type': 'text', ...dataContext},
                        ..._claudeParts(m)
                      ],
                    })
                .toList(),
          };
    final bytes = utf8.encode(jsonEncode(body));
    if (bytes.length > 16 * 1024 * 1024) throw const AiException('size');
    final endpoint = isDeepSeek
        ? 'https://api.deepseek.com/chat/completions'
        : isGemini
            ? 'https://generativelanguage.googleapis.com/v1beta/models/'
                '${preferences.model}:generateContent'
            : 'https://api.anthropic.com/v1/messages';
    // THE REQUEST ITSELF, once, before it leaves. `body` is the wire shape —
    // system prompt, the whole conversation as the provider will see it, and
    // the document context riding on the last turn. [AiTrace.scrub] takes the
    // attachment payloads out and nothing key-shaped is in a body to begin
    // with (credentials travel in headers, which are never recorded).
    AiTrace.record('http.request',
        requestId: request.id,
        sessionId: request.sessionId,
        round: request.round,
        data: {
          'provider': caps.provider.name,
          'model': preferences.model,
          'endpoint': endpoint,
          'bodyBytes': bytes.length,
          'messages': request.messages.length,
          'instructionChars': request.instructions.length,
          'contextChars': request.context.length,
          'attachmentBytes': rawBytes,
          'body': body,
        });
    Log.i('ai', 'request ${request.id} -> ${caps.provider.name} '
        '${preferences.model} (${bytes.length} B, '
        '${request.messages.length} turns)');
    final client = _clientFactory();
    _clients[request.id] = client;
    try {
      if (_cancelled.contains(request.id) || _disposed)
        throw const AiException('cancelled');
      final outgoing = http.Request(
          'POST',
          isDeepSeek
              ? Uri.https('api.deepseek.com', '/chat/completions')
              : isGemini
                  ? Uri.https('generativelanguage.googleapis.com',
                      '/v1beta/models/${preferences.model}:generateContent')
                  : Uri.https('api.anthropic.com', '/v1/messages'))
        ..followRedirects = false
        ..headers.addAll({
          'content-type': 'application/json',
          if (isGemini) 'x-goog-api-key': key,
          if (isDeepSeek) 'authorization': 'Bearer $key',
          if (!isGemini && !isDeepSeek) 'x-api-key': key,
          if (!isGemini && !isDeepSeek) 'anthropic-version': '2023-06-01',
        })
        ..bodyBytes = bytes;
      final wall = Stopwatch()..start();
      var responseBytes = 0;
      final response = await (() async {
        final response = await client.send(outgoing);
        if (response.statusCode != 200) {
          // THE PROVIDER'S OWN WORDS, before the throw discards them. A 400
          // from Claude names the field it could not parse and a 429 from
          // DeepSeek says which limit was hit; the user saw "something went
          // wrong with the response" and the bundle recorded that sentence
          // rather than either of these. Bounded, and read from the same
          // stream the success path reads — an error body that is megabytes
          // long is itself the finding, and the size is recorded either way.
          final detail = await _errorBody(response.stream);
          AiTrace.record('http.error',
              requestId: request.id,
              sessionId: request.sessionId,
              round: request.round,
              data: {
                'provider': caps.provider.name,
                'model': preferences.model,
                'status': response.statusCode,
                if (response.reasonPhrase != null)
                  'reason': response.reasonPhrase,
                'elapsedMs': wall.elapsedMilliseconds,
                if (detail.isNotEmpty) 'body': detail,
              });
          Log.w('ai', 'request ${request.id}: HTTP ${response.statusCode} '
              'from ${caps.provider.name} after ${wall.elapsedMilliseconds} ms');
          throw AiException(switch (response.statusCode) {
            401 || 403 => 'credentials',
            429 => 'quota',
            404 => 'model',
            413 => 'size',
            400 => 'response',
            _ => 'network',
          });
        }
        final data = BytesBuilder(copy: false);
        await for (final chunk in response.stream) {
          if (data.length + chunk.length > 2 * 1024 * 1024) {
            AiTrace.record('http.oversize',
                requestId: request.id,
                sessionId: request.sessionId,
                round: request.round,
                data: {
                  'provider': caps.provider.name,
                  'readBytes': data.length,
                  'limitBytes': 2 * 1024 * 1024,
                });
            throw const AiException('response');
          }
          data.add(chunk);
        }
        final raw = data.takeBytes();
        responseBytes = raw.length;
        return jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
      })()
          .timeout(const Duration(seconds: 120));
      // THE WHOLE DECODED RESPONSE. Usage, stop reason, thinking blocks and
      // safety verdicts all live in here, and every one of them used to be
      // dropped by the three extractors below. Recorded before they run, so a
      // reply this method goes on to REJECT is still in the trace — a refusal
      // and a truncation are the two cases a reader most needs to see whole.
      AiTrace.record('http.response',
          requestId: request.id,
          sessionId: request.sessionId,
          round: request.round,
          data: {
            'provider': caps.provider.name,
            'model': preferences.model,
            'status': 200,
            'elapsedMs': wall.elapsedMilliseconds,
            'bodyBytes': responseBytes,
            'body': response,
          });
      _traceUsage(caps.provider, preferences.model, request, response);
      if (_cancelled.contains(request.id) || _disposed)
        throw const AiException('cancelled');
      late String text;
      if (isDeepSeek) {
        final choices = response['choices'] as List? ?? [];
        if (choices.isEmpty) throw const AiException('refused');
        final choice = (choices.first as Map).cast<String, dynamic>();
        final reason = choice['finish_reason'];
        // The scratchpad. Still not SHOWN — it is not the answer, and
        // presenting it as one would misstate what the model concluded — but
        // it is now recorded, because "why did it decide that" is exactly the
        // question a bug report about a wrong answer is asking.
        _traceThinking(caps.provider, request,
            (choice['message'] as Map?)?['reasoning_content'] as String?,
            stopReason: reason?.toString());
        // `null` is what a non-streamed completion reports while the provider
        // is still writing; anything other than a finished turn is a truncated
        // or withheld answer, and neither is a reply.
        if (reason != 'stop') {
          throw AiException(switch (reason) {
            'content_filter' => 'refused',
            // Say WHICH failure it was. "The reply was cut off" tells the user
            // to ask for less; a generic response error tells them nothing,
            // and a reasoning model hits this far more easily than a chat one.
            'length' => 'truncated',
            _ => 'response',
          });
        }
        text = ((choice['message'] as Map?)?['content'] as String?) ?? '';
      } else if (isGemini) {
        final candidates = response['candidates'] as List? ?? [];
        if (candidates.isEmpty) throw const AiException('refused');
        final candidate = candidates.first as Map;
        _traceThinking(
            caps.provider,
            request,
            ((candidate['content'] as Map?)?['parts'] as List? ?? [])
                .whereType<Map>()
                .where((p) => p['thought'] == true)
                .map((p) => p['text'] as String? ?? '')
                .join('\n')
                .trim(),
            stopReason: candidate['finishReason']?.toString(),
            extra: {
              if (candidate['safetyRatings'] != null)
                'safetyRatings': candidate['safetyRatings'],
              if (candidate['citationMetadata'] != null)
                'citationMetadata': candidate['citationMetadata'],
              if (response['promptFeedback'] != null)
                'promptFeedback': response['promptFeedback'],
            });
        if (candidate['finishReason'] != 'STOP') {
          throw AiException(switch (candidate['finishReason']) {
            'MAX_TOKENS' => 'truncated',
            _ => 'refused',
          });
        }
        text = ((candidate['content'] as Map?)?['parts'] as List? ?? [])
            .whereType<Map>()
            .where((p) => p['thought'] != true)
            .map((p) => p['text'] as String? ?? '')
            .join();
      } else {
        _traceThinking(
            caps.provider,
            request,
            (response['content'] as List? ?? [])
                .whereType<Map>()
                .where((p) => p['type'] == 'thinking')
                .map((p) =>
                    (p['thinking'] ?? p['text'] ?? '').toString())
                .join('\n')
                .trim(),
            stopReason: response['stop_reason']?.toString(),
            extra: {
              if (response['stop_sequence'] != null)
                'stopSequence': response['stop_sequence'],
              'blockTypes': [
                for (final p in (response['content'] as List? ?? [])
                    .whereType<Map>())
                  p['type']
              ],
            });
        if (response['stop_reason'] != 'end_turn') {
          throw AiException(switch (response['stop_reason']) {
            'refusal' => 'refused',
            'max_tokens' => 'truncated',
            _ => 'response',
          });
        }
        text = (response['content'] as List? ?? [])
            .whereType<Map>()
            .where((p) => p['type'] == 'text')
            .map((p) => p['text'] as String? ?? '')
            .join('\n');
      }
      if (text.trim().isEmpty || text.length > 100000) {
        AiTrace.record('reply.rejected',
            requestId: request.id,
            sessionId: request.sessionId,
            round: request.round,
            data: {
              'provider': caps.provider.name,
              'why': text.trim().isEmpty ? 'empty' : 'over 100000 characters',
              'chars': text.length,
            });
        throw const AiException('response');
      }
      AiTrace.record('reply',
          requestId: request.id,
          sessionId: request.sessionId,
          round: request.round,
          data: {
            'provider': caps.provider.name,
            'model': preferences.model,
            'label': caps.label,
            'chars': text.trim().length,
            'elapsedMs': wall.elapsedMilliseconds,
            'text': text.trim(),
          });
      return AiReply(text.trim(), caps.label);
    } on AiException catch (e) {
      _traceFailure(caps.provider, request, e.code);
      rethrow;
    } on FormatException catch (e) {
      _traceFailure(caps.provider, request, 'response',
          cause: 'the provider body is not the JSON this code expects: $e');
      throw const AiException('response');
    } on TypeError catch (e) {
      _traceFailure(caps.provider, request, 'response',
          cause: 'a field in the provider body had an unexpected type: $e');
      throw const AiException('response');
    } catch (e) {
      final code = _cancelled.contains(request.id) || _disposed
          ? 'cancelled'
          : 'network';
      // `catch (_)` used to make a DNS failure, a dropped TLS handshake, a
      // 120-second timeout and a closed socket into one word. The word is
      // still what the user sees; the reason is now in the trace.
      _traceFailure(caps.provider, request, code,
          cause: '${e.runtimeType}: $e');
      throw AiException(code);
    } finally {
      client.close();
      _clients.remove(request.id);
      _cancelled.remove(request.id);
    }
  }

  /// How much of a non-200 body is kept. Enough for any provider's error
  /// JSON and small enough that a misconfigured endpoint returning an HTML
  /// error page cannot push the bundle over the upload budget.
  static const int _errorBodyLimit = 16 * 1024;

  Future<String> _errorBody(Stream<List<int>> stream) async {
    try {
      final data = BytesBuilder(copy: false);
      await for (final chunk in stream) {
        data.add(chunk);
        if (data.length >= _errorBodyLimit) break;
      }
      final raw = data.takeBytes();
      final kept =
          raw.length > _errorBodyLimit ? raw.sublist(0, _errorBodyLimit) : raw;
      final text = utf8.decode(kept, allowMalformed: true).trim();
      return kept.length < raw.length
          ? '$text\n<truncated at $_errorBodyLimit bytes>'
          : text;
    } catch (e) {
      return '<the error body could not be read: $e>';
    }
  }

  /// Three providers spell the same five numbers five different ways. This
  /// normalises them so two bundles from two providers can be read side by
  /// side, and keeps the provider's own block beside the result so nothing is
  /// lost to the normalisation.
  void _traceUsage(AiProvider provider, String model, AiRequest request,
      Map<String, dynamic> response) {
    int? n(Object? v) => v is num ? v.toInt() : null;
    Map<String, dynamic>? raw;
    Map<String, dynamic> usage;
    switch (provider) {
      case AiProvider.gemini:
        raw = (response['usageMetadata'] as Map?)?.cast<String, dynamic>();
        usage = {
          'input': n(raw?['promptTokenCount']),
          'output': n(raw?['candidatesTokenCount']),
          'reasoning': n(raw?['thoughtsTokenCount']),
          'cacheRead': n(raw?['cachedContentTokenCount']),
        };
      case AiProvider.deepseek:
        raw = (response['usage'] as Map?)?.cast<String, dynamic>();
        usage = {
          'input': n(raw?['prompt_tokens']),
          'output': n(raw?['completion_tokens']),
          'reasoning': n((raw?['completion_tokens_details']
              as Map?)?['reasoning_tokens']),
          'cacheRead': n(raw?['prompt_cache_hit_tokens']),
        };
      case AiProvider.anthropic:
        raw = (response['usage'] as Map?)?.cast<String, dynamic>();
        usage = {
          'input': n(raw?['input_tokens']),
          'output': n(raw?['output_tokens']),
          'cacheRead': n(raw?['cache_read_input_tokens']),
          'cacheWrite': n(raw?['cache_creation_input_tokens']),
        };
      case AiProvider.apple:
        // The Foundation Models framework publishes no usage block at all.
        // The context size it WILL state is recorded with the capabilities.
        return;
    }
    usage.removeWhere((_, v) => v == null);
    if (usage.isEmpty && raw == null) return;
    AiTrace.usage(
        provider: provider.name,
        model: model,
        requestId: request.id,
        sessionId: request.sessionId,
        round: request.round,
        usage: usage,
        raw: raw);
  }

  void _traceThinking(AiProvider provider, AiRequest request, String? thinking,
      {String? stopReason, Map<String, dynamic> extra = const {}}) {
    final clean = thinking?.trim() ?? '';
    final more = <String, dynamic>{
      for (final e in extra.entries)
        if (e.value != null) e.key: e.value
    };
    if (clean.isEmpty && stopReason == null && more.isEmpty) return;
    AiTrace.record('thinking',
        requestId: request.id,
        sessionId: request.sessionId,
        round: request.round,
        data: {
          'provider': provider.name,
          if (stopReason != null) 'stopReason': stopReason,
          if (clean.isNotEmpty) 'chars': clean.length,
          ...more,
          if (clean.isNotEmpty) 'text': clean,
        });
  }

  void _traceFailure(AiProvider provider, AiRequest request, String code,
      {String? cause}) {
    AiTrace.record('error',
        requestId: request.id,
        sessionId: request.sessionId,
        round: request.round,
        data: {
          'provider': provider.name,
          'code': code,
          if (cause != null) 'cause': cause,
        });
    Log.w('ai',
        'request ${request.id} failed: $code${cause == null ? '' : ' — $cause'}');
  }

  List<Map<String, dynamic>> _geminiParts(AiMessage message) => [
        if (message.text.isNotEmpty) {'text': message.text},
        for (final a in message.attachments)
          if (a.text != null)
            {'text': 'ATTACHED FILE: ${a.name}\n${a.text}'}
          else ...[
            {'text': 'ATTACHED FILE: ${a.name}'},
            {
              'inlineData': {
                'mimeType': a.mimeType,
                'data': base64Encode(a.bytes)
              }
            },
          ],
      ];

  /// One flat text block per message, for a provider that takes a plain
  /// string. Binary attachments never reach here — [_respond] refuses them for
  /// DeepSeek before the body is built.
  List<String> _plainParts(AiMessage message) => [
        if (message.text.isNotEmpty) message.text,
        for (final a in message.attachments)
          if (a.text != null) 'ATTACHED FILE: ${a.name}\n${a.text}',
      ];

  /// OpenAI-shaped content parts, which is what DeepSeek's chat completions
  /// take for a multimodal turn.
  List<Map<String, dynamic>> _openAiParts(AiMessage message, {String? lead}) {
    final text = [
      if (lead != null) lead,
      ..._plainParts(message),
    ].join('\n\n');
    return [
      if (text.isNotEmpty) {'type': 'text', 'text': text},
      for (final a in message.attachments)
        if (a.isImage)
          {
            'type': 'image_url',
            'image_url': {
              'url': 'data:${a.mimeType};base64,${base64Encode(a.bytes)}'
            }
          }
    ];
  }

  List<Map<String, dynamic>> _claudeParts(AiMessage message) => [
        if (message.text.isNotEmpty) {'type': 'text', 'text': message.text},
        for (final a in message.attachments)
          if (a.text != null)
            {'type': 'text', 'text': 'ATTACHED FILE: ${a.name}\n${a.text}'}
          else ...[
            {'type': 'text', 'text': 'ATTACHED FILE: ${a.name}'},
            {
              'type': a.isImage ? 'image' : 'document',
              'source': {
                'type': 'base64',
                'media_type': a.mimeType,
                'data': base64Encode(a.bytes)
              }
            },
          ],
      ];

  Future<AiReply> _apple(AiRequest request, AiCapabilities caps) async {
    final attachments = request.messages.expand((m) => m.attachments).toList();
    if (attachments.any((a) => a.isPdf))
      throw const AiException('pdfUnsupported');
    final images = attachments.where((a) => a.isImage).toList();
    if (images.isNotEmpty && !caps.supportsImages)
      throw const AiException('imagesUnsupported');
    if (images.length > 4) throw const AiException('context');
    final prompt = jsonEncode({
      'documentContext': request.context,
      'conversation': request.messages
          .map((m) => {
                'role': m.role,
                'text': m.text,
                if (m.attachments.isNotEmpty)
                  'attachments': m.attachments
                      .map((a) => {
                            'name': a.name,
                            if (a.text != null) 'text': a.text,
                            if (a.isImage)
                              'attachmentLabel':
                                  'reference-${images.indexOf(a) + 1}',
                          })
                      .toList(),
              })
          .toList(),
    });
    final promptBytes = utf8.encode(prompt).length;
    final instructionBytes = utf8.encode(request.instructions).length;
    // Apple Intelligence is the provider with the SMALLEST context and the
    // least said about it: there is no usage block, so the only numbers that
    // will ever exist for a request on this route are the ones measured here.
    AiTrace.record('apple.request',
        requestId: request.id,
        sessionId: request.sessionId,
        round: request.round,
        data: {
          'provider': 'apple',
          'route': appleDetail?['route'],
          'appleModel': appleDetail?['model'],
          'contextTokens': appleDetail?['contextTokens'],
          'promptBytes': promptBytes,
          'instructionBytes': instructionBytes,
          'maxInputBytes': caps.maxInputBytes,
          'images': images.length,
          'imageNames': [for (final i in images) i.name],
          'messages': request.messages.length,
          'instructions': request.instructions,
          'prompt': prompt,
        });
    if (promptBytes + instructionBytes > caps.maxInputBytes) {
      AiTrace.record('error',
          requestId: request.id,
          sessionId: request.sessionId,
          round: request.round,
          data: {
            'provider': 'apple',
            'code': 'context',
            'cause': 'the request is ${promptBytes + instructionBytes} bytes '
                'and the available Apple model accepts ${caps.maxInputBytes}',
          });
      throw const AiException('context');
    }
    Directory? temporary;
    Future<Map<String, dynamic>?>? nativeReply;
    final wall = Stopwatch()..start();
    try {
      final paths = <String>[];
      if (images.isNotEmpty) {
        temporary = await Directory.systemTemp.createTemp('prototype-ai-');
        for (var i = 0; i < images.length; i++) {
          final extension = switch (images[i].mimeType) {
            'image/jpeg' => 'jpg',
            'image/webp' => 'webp',
            _ => 'png'
          };
          final f = File('${temporary.path}/image-$i.$extension');
          await f.writeAsBytes(images[i].bytes, flush: true);
          paths.add(f.path);
        }
      }
      if (_cancelled.contains(request.id) || _disposed)
        throw const AiException('cancelled');
      _nativeRequests.add(request.id);
      nativeReply = _channel.invokeMapMethod<String, dynamic>('aiRespond', {
        'requestId': request.id,
        'instructions': request.instructions,
        'prompt': prompt,
        'imagePaths': paths,
      });
      final response = await nativeReply.timeout(const Duration(seconds: 120),
          onTimeout: () {
        unawaited(cancel(request.id));
        throw const AiException('network');
      });
      if (_cancelled.contains(request.id) || _disposed)
        throw const AiException('cancelled');
      final text = response?['text'] as String? ?? '';
      AiTrace.record('apple.reply',
          requestId: request.id,
          sessionId: request.sessionId,
          round: request.round,
          data: {
            'provider': 'apple',
            'route': response?['route'],
            'appleModel': response?['model'],
            // THE SILENT DOWNGRADE. When Private Cloud Compute cannot answer,
            // the runner retries on the on-device model and says so in this
            // field — which Dart read past. "The same question gave a much
            // worse answer this time" is that fallback, and nothing anywhere
            // recorded that it had happened.
            if (response?['fallbackReason'] != null)
              'fallbackReason': response?['fallbackReason'],
            'chars': text.trim().length,
            'elapsedMs': wall.elapsedMilliseconds,
            'text': text,
          });
      if (text.trim().isEmpty || text.length > 100000) {
        AiTrace.record('reply.rejected',
            requestId: request.id,
            sessionId: request.sessionId,
            round: request.round,
            data: {
              'provider': 'apple',
              'why': text.trim().isEmpty ? 'empty' : 'over 100000 characters',
              'chars': text.length,
            });
        throw const AiException('response');
      }
      return AiReply(
          text,
          response?['route'] == 'privateCloudCompute'
              ? L.current.aiProviderCloud
              : L.current.aiProviderOnDevice);
    } on AiException catch (e) {
      _traceFailure(AiProvider.apple, request, e.code);
      rethrow;
    } on PlatformException catch (e) {
      // The runner's code AND its sentence. `AiException` keeps only a code of
      // its own, so "Turn on Apple Intelligence in the device Settings" and
      // "the model download has not finished" both reached the user — and the
      // bundle — as one localised line about the assistant being unavailable.
      AiTrace.record('error',
          requestId: request.id,
          sessionId: request.sessionId,
          round: request.round,
          data: {
            'provider': 'apple',
            'platformCode': e.code,
            if (e.message != null) 'platformMessage': e.message,
            if (e.details != null) 'platformDetails': '${e.details}',
          });
      Log.w('ai', 'request ${request.id}: Apple Intelligence returned '
          '${e.code}');
      throw AiException(switch (e.code) {
        'ai_cancelled' => 'cancelled',
        'ai_unavailable' => 'unavailable',
        'ai_images_unsupported' => 'imagesUnsupported',
        'ai_context_too_large' || 'ai_request_too_large' => 'context',
        'ai_busy' => 'busy',
        'ai_refused' || 'ai_guardrail' => 'refused',
        'ai_rate_limited' => 'quota',
        'ai_timeout' => 'network',
        'ai_invalid_image' || 'ai_content_unsupported' => 'attachment',
        'ai_image_too_large' => 'size',
        'ai_language_unsupported' => 'refused',
        _ => 'response',
      });
    } on MissingPluginException {
      _traceFailure(AiProvider.apple, request, 'unavailable',
          cause: 'this host build has no AI plugin registered');
      throw const AiException('unavailable');
    } finally {
      Future<void> cleanup() async {
        _nativeRequests.remove(request.id);
        _cancelled.remove(request.id);
        // Only clean our own directory after native work has stopped reading it.
        if (temporary != null) {
          try {
            await temporary.delete(recursive: true);
          } catch (_) {/* system temp cleanup */}
        }
      }

      if (nativeReply == null) {
        await cleanup();
      } else {
        unawaited(nativeReply.then<void>((_) => cleanup(),
            onError: (Object _, StackTrace __) => cleanup()));
      }
    }
  }

  @override
  Future<void> cancel(String requestId) async {
    if (!_pendingRequests.contains(requestId) && !_nativeRequests.contains(requestId)) return;
    AiTrace.record('cancel', requestId: requestId, data: {
      'native': _nativeRequests.contains(requestId),
      'http': _clients.containsKey(requestId),
    });
    _cancelled.add(requestId);
    _clients.remove(requestId)?.close();
    if (Platform.isIOS) {
      try {
        await _channel.invokeMethod<bool>('aiCancel', {'requestId': requestId});
      } catch (_) {/* best effort */}
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final id in _nativeRequests.toList()) {
      unawaited(cancel(id));
    }
    for (final client in _clients.values) {
      client.close();
    }
    _clients.clear();
  }
}
