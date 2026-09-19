import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../l10n/l.dart';
import 'ai_models.dart';

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
      required List<AiMessage> messages})
      : messages = List.unmodifiable(messages);
  final String id;
  final String instructions;
  final String context;
  final List<AiMessage> messages;
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

  @override
  Future<AiCapabilities> capabilities(AiPreferences preferences) async {
    if (preferences.provider != AiProvider.apple &&
        await hasKey(preferences.provider)) {
      return AiCapabilities(
          provider: preferences.provider,
          available: true,
          label:
              '${preferences.provider == AiProvider.gemini ? 'Gemini' : 'Claude'} · ${preferences.model}');
    }
    if (!Platform.isIOS) {
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
      return AiCapabilities(
          provider: AiProvider.apple,
          available: value['available'] == true,
          supportsImages: value['supportsImages'] == true,
          maxInputBytes: value['maxInputBytes'] as int? ?? 0,
          label: value['route'] == 'privateCloudCompute'
              ? L.current.aiProviderCloud
              : L.current.aiProviderOnDevice);
    } on MissingPluginException {
      return AiCapabilities(
          provider: AiProvider.apple,
          available: false,
          supportsImages: false,
          label: L.current.aiSettingsApple);
    } on PlatformException {
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
    final body = isGemini
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
            'generationConfig': {'maxOutputTokens': 4096},
          }
        : <String, dynamic>{
            'model': preferences.model,
            'max_tokens': 4096,
            'system': request.instructions,
            'messages': request.messages
                .map((m) => {
                      'role': m.role,
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
    final client = _clientFactory();
    _clients[request.id] = client;
    try {
      if (_cancelled.contains(request.id) || _disposed)
        throw const AiException('cancelled');
      final outgoing = http.Request(
          'POST',
          isGemini
              ? Uri.https('generativelanguage.googleapis.com',
                  '/v1beta/models/${preferences.model}:generateContent')
              : Uri.https('api.anthropic.com', '/v1/messages'))
        ..followRedirects = false
        ..headers.addAll({
          'content-type': 'application/json',
          if (isGemini) 'x-goog-api-key': key,
          if (!isGemini) 'x-api-key': key,
          if (!isGemini) 'anthropic-version': '2023-06-01',
        })
        ..bodyBytes = bytes;
      final response = await (() async {
        final response = await client.send(outgoing);
        if (response.statusCode != 200) {
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
          if (data.length + chunk.length > 2 * 1024 * 1024)
            throw const AiException('response');
          data.add(chunk);
        }
        return jsonDecode(utf8.decode(data.takeBytes()))
            as Map<String, dynamic>;
      })()
          .timeout(const Duration(seconds: 120));
      if (_cancelled.contains(request.id) || _disposed)
        throw const AiException('cancelled');
      late String text;
      if (isGemini) {
        final candidates = response['candidates'] as List? ?? [];
        if (candidates.isEmpty) throw const AiException('refused');
        final candidate = candidates.first as Map;
        if (candidate['finishReason'] != 'STOP') {
          throw AiException(candidate['finishReason'] == 'MAX_TOKENS'
              ? 'response'
              : 'refused');
        }
        text = ((candidate['content'] as Map?)?['parts'] as List? ?? [])
            .whereType<Map>()
            .where((p) => p['thought'] != true)
            .map((p) => p['text'] as String? ?? '')
            .join();
      } else {
        if (response['stop_reason'] != 'end_turn') {
          throw AiException(
              response['stop_reason'] == 'refusal' ? 'refused' : 'response');
        }
        text = (response['content'] as List? ?? [])
            .whereType<Map>()
            .where((p) => p['type'] == 'text')
            .map((p) => p['text'] as String? ?? '')
            .join('\n');
      }
      if (text.trim().isEmpty || text.length > 100000)
        throw const AiException('response');
      return AiReply(text.trim(), caps.label);
    } on AiException {
      rethrow;
    } on FormatException {
      throw const AiException('response');
    } on TypeError {
      throw const AiException('response');
    } catch (_) {
      throw AiException(_cancelled.contains(request.id) || _disposed
          ? 'cancelled'
          : 'network');
    } finally {
      client.close();
      _clients.remove(request.id);
      _cancelled.remove(request.id);
    }
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
    if (utf8.encode(prompt).length + utf8.encode(request.instructions).length >
        caps.maxInputBytes) {
      throw const AiException('context');
    }
    Directory? temporary;
    Future<Map<String, dynamic>?>? nativeReply;
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
      if (text.trim().isEmpty || text.length > 100000)
        throw const AiException('response');
      return AiReply(
          text,
          response?['route'] == 'privateCloudCompute'
              ? L.current.aiProviderCloud
              : L.current.aiProviderOnDevice);
    } on PlatformException catch (e) {
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
