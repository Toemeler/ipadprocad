import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../l10n/l.dart';

/// IDs never depend on a display name or a provider's conversation ID.
String aiId() {
  final random = Random.secure();
  return List.generate(
      16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

enum AiProvider { apple, gemini, anthropic }

class AiException implements Exception {
  const AiException(this.code);
  final String code;
  String get message {
    final t = L.current;
    return switch (code) {
      'attachment' => t.aiErrorAttachment,
      'size' => t.aiErrorSize,
      'empty' => t.aiErrorEmpty,
      'credentials' => t.aiErrorCredentials,
      'secureStorage' => t.aiErrorSecureStorage,
      'unavailable' => t.aiErrorUnavailable,
      'imagesUnsupported' => t.aiErrorImages,
      'pdfUnsupported' => t.aiErrorPdf,
      'context' => t.aiErrorContext,
      'cancelled' => t.aiErrorCancelled,
      'network' => t.aiErrorNetwork,
      'quota' => t.aiErrorQuota,
      'model' => t.aiErrorModel,
      'refused' => t.aiErrorRefused,
      'storage' => t.aiErrorStorage,
      'document' => t.aiErrorDocument,
      'busy' => t.aiErrorBusy,
      _ => t.aiErrorResponse,
    };
  }

  @override
  String toString() => message;
}

class AiDocument {
  const AiDocument({required this.id, required this.name, required this.kind});
  final String id;
  final String name;
  final String kind;
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'kind': kind};
  factory AiDocument.fromJson(Map<String, dynamic> j) => AiDocument(
      id: j['id'] as String,
      name: j['name'] as String,
      kind: j['kind'] as String);
}

/// Deliberately small allowlist. Binary CAD documents belong in the workspace;
/// passing their bytes to a text model would imply an inspection that never ran.
class AiAttachment {
  AiAttachment._(
      {required this.id,
      required this.name,
      required this.mimeType,
      required Uint8List bytes})
      : bytes = bytes.asUnmodifiableView();
  final String id;
  final String name;
  final String mimeType;
  final Uint8List bytes;
  static const maxFileBytes = 5 * 1024 * 1024;
  bool get isImage => mimeType.startsWith('image/');
  bool get isPdf => mimeType == 'application/pdf';
  String? get text => mimeType.startsWith('text/') ? utf8.decode(bytes) : null;

  static AiAttachment fromBytes(
      {required String name, required Uint8List bytes}) {
    if (bytes.isEmpty || bytes.length > maxFileBytes)
      throw const AiException('size');
    final cleanName = name
        .replaceAll('\\', '/')
        .split('/')
        .last
        .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '')
        .trim();
    if (cleanName.isEmpty || cleanName.length > 180)
      throw const AiException('attachment');
    bool starts(List<int> signature) =>
        bytes.length >= signature.length &&
        Iterable<int>.generate(signature.length)
            .every((i) => bytes[i] == signature[i]);
    String? mime;
    if (starts([137, 80, 78, 71, 13, 10, 26, 10])) {
      mime = 'image/png';
    } else if (starts([255, 216, 255])) {
      mime = 'image/jpeg';
    } else if (bytes.length >= 12 &&
        ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
        ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP') {
      mime = 'image/webp';
    } else if (starts([37, 80, 68, 70, 45])) {
      mime = 'application/pdf';
    } else if (const ['txt', 'md', 'csv', 'json', 'yaml', 'yml', 'log']
        .contains(cleanName.split('.').last.toLowerCase())) {
      try {
        final decoded = utf8.decode(bytes);
        if (decoded.contains('\u0000') || decoded.length > 60000)
          throw const AiException('size');
        mime = 'text/plain';
      } on FormatException {
        throw const AiException('attachment');
      }
    }
    if (mime == null) throw const AiException('attachment');
    return AiAttachment._(
        id: aiId(),
        name: cleanName,
        mimeType: mime,
        bytes: Uint8List.fromList(bytes));
  }

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'mime': mimeType, 'data': base64Encode(bytes)};
  factory AiAttachment.fromJson(Map<String, dynamic> j) {
    final data = j['data'] as String;
    if (data.length > (maxFileBytes * 4 ~/ 3) + 8)
      throw const AiException('size');
    final checked =
        fromBytes(name: j['name'] as String, bytes: base64Decode(data));
    return AiAttachment._(
        id: j['id'] as String,
        name: checked.name,
        mimeType: checked.mimeType,
        bytes: checked.bytes);
  }
}

class AiMessage {
  AiMessage(
      {required this.role,
      required this.text,
      List<AiAttachment> attachments = const [],
      this.provider,
      this.contextLabel,
      String? id,
      DateTime? createdAt})
      : id = id ?? aiId(),
        createdAt = createdAt ?? DateTime.now().toUtc(),
        attachments = List.unmodifiable(attachments);
  final String id;
  final String role;
  final String text;
  final List<AiAttachment> attachments;
  final DateTime createdAt;
  final String? provider;
  final String? contextLabel;
  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        'text': text,
        'at': createdAt.toIso8601String(),
        'attachments': attachments.map((a) => a.toJson()).toList(),
        if (provider != null) 'provider': provider,
        if (contextLabel != null) 'contextLabel': contextLabel
      };
  factory AiMessage.fromJson(Map<String, dynamic> j) {
    if (!['user', 'assistant'].contains(j['role']) ||
        (j['text'] as String).length > 100000) {
      throw const FormatException('Invalid AI message');
    }
    return AiMessage(
        id: j['id'] as String,
        role: j['role'] as String,
        text: j['text'] as String,
        createdAt: DateTime.parse(j['at'] as String),
        provider: j['provider'] as String?,
        contextLabel: j['contextLabel'] as String?,
        attachments: (j['attachments'] as List? ?? [])
            .map((a) =>
                AiAttachment.fromJson(Map<String, dynamic>.from(a as Map)))
            .toList());
  }
}

class AiSession {
  AiSession({required this.documentId, required this.name, String? id})
      : id = id ?? aiId();
  final String id;
  String documentId;
  String name;
  final List<AiMessage> messages = [];
  String draft = '';
  final List<AiAttachment> attachments = [];
  final Set<String> contextDocumentIds = {};
  String? errorCode;
  bool busy = false;
  bool get isEmpty => messages.isEmpty && draft.isEmpty && attachments.isEmpty;
  Map<String, dynamic> toJson() => {
        'id': id,
        'documentId': documentId,
        'name': name,
        'messages': messages.map((m) => m.toJson()).toList(),
        'draft': draft,
        'attachments': attachments.map((a) => a.toJson()).toList(),
        'context': contextDocumentIds.toList()
      };
  factory AiSession.fromJson(Map<String, dynamic> j) {
    final s = AiSession(
        id: j['id'] as String,
        documentId: j['documentId'] as String,
        name: j['name'] as String);
    if (s.name.length > 100 || (j['messages'] as List).length > 160) {
      throw const FormatException('Invalid AI session');
    }
    s.messages.addAll((j['messages'] as List)
        .map((m) => AiMessage.fromJson(Map<String, dynamic>.from(m as Map))));
    s.draft = j['draft'] as String? ?? '';
    if (s.draft.length > 12000) throw const FormatException('Invalid AI draft');
    s.attachments.addAll((j['attachments'] as List? ?? []).map(
        (a) => AiAttachment.fromJson(Map<String, dynamic>.from(a as Map))));
    s.contextDocumentIds.addAll((j['context'] as List? ?? []).cast<String>());
    return s;
  }
}

class AiPreferences {
  const AiPreferences({this.provider = AiProvider.apple, this.model = ''});
  final AiProvider provider;
  final String model;
  Map<String, dynamic> toJson() => {'provider': provider.name, 'model': model};
  factory AiPreferences.fromJson(Map<String, dynamic> j) => AiPreferences(
      provider: AiProvider.values.firstWhere((p) => p.name == j['provider'],
          orElse: () => AiProvider.apple),
      model: j['model'] as String? ?? '');
}
