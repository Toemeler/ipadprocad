import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../doc_ref.dart';
import '../doc_file.dart';

/// Community's website API, isolated here because it is not a versioned public
/// integration contract. Never infer compatibility from its software labels.
class GrabCadClient {
  GrabCadClient({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;
  static const maxDownloadBytes = 250 * 1024 * 1024;
  static const _origin = 'https://grabcad.com';

  void close() => _http.close();

  Future<Map<String, dynamic>> _json(String path,
      {Map<String, dynamic>? body}) async {
    final uri = Uri.parse('$_origin/community/api/v1/$path');
    final response = await (body == null
            ? _http.get(uri, headers: {'Accept': 'application/json'})
            : _http.post(uri,
                headers: {
                  'Accept': 'application/json',
                  'Content-Type': 'application/json',
                },
                body: jsonEncode(body)))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw const GrabCadException('unavailable');
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['search_down'] == true || data['search_down'] == 1) {
        throw const GrabCadException('unavailable');
      }
      return data;
    } on FormatException {
      throw const GrabCadException('unavailable');
    }
  }

  /// Checks nested folders too. A model is visible only after its actual file
  /// names have been verified, including mixed STEP/IGES and Inventor uploads.
  Future<List<GrabCadFile>> files(String slug) async {
    final pending = <String?>[null];
    final visited = <String>{};
    final found = <String, GrabCadFile>{};
    var requests = 0;
    while (pending.isNotEmpty) {
      if (++requests > 64) throw const GrabCadException('unavailable');
      final folder = pending.removeLast();
      final path = 'models/${Uri.encodeComponent(slug)}/files';
      final data = await _json(folder == null
          ? path
          : '$path?folder_id=${Uri.encodeComponent(folder)}');
      if (data['files'] is! List || data['folders'] is! List) {
        throw const GrabCadException('unavailable');
      }
      for (final raw in data['files'] as List) {
        if (raw is! Map<String, dynamic>) continue;
        final file = GrabCadFile.fromJson(raw);
        if (file != null) found[file.id] = file;
      }
      for (final raw in data['folders'] as List) {
        if (raw is! Map || raw['id'] == null) continue;
        final id = raw['id'].toString();
        if (visited.add(id)) pending.add(id);
      }
    }
    final result = found.values.toList();
    result.sort((a, b) {
      final order = a.priority.compareTo(b.priority);
      return order != 0 ? order : a.name.compareTo(b.name);
    });
    return result;
  }

  Future<GrabCadPage> search(String query, {int page = 1}) async {
    if (query.trim().isEmpty) return const GrabCadPage([], false);
    final data = await _json('models', body: {
      'query': query.trim(),
      'page': page,
      'per_page': 24,
      'sort': 'recent',
      'time': 'all_time',
    });
    if (data['models'] is! List ||
        data['total_entries'] is! num ||
        data['per_page'] is! num ||
        (data['per_page'] as num) <= 0) {
      throw const GrabCadException('unavailable');
    }
    final candidates = (data['models'] as List)
        .whereType<Map<String, dynamic>>()
        .where((m) =>
            m['is_hidden'] != true &&
            m['is_tainted'] != true &&
            m['cached_slug'] is String &&
            m['name'] is String)
        .take(48)
        .toList();
    final verified = <GrabCadModel>[];
    // Bound parallel metadata requests rather than issuing one per search hit
    // at once. Any metadata failure is retryable, never a false "no results".
    for (var offset = 0; offset < candidates.length; offset += 4) {
      final batch = candidates.skip(offset).take(4);
      final models = await Future.wait(batch.map((raw) async {
        final slug = raw['cached_slug'] as String;
        final compatible = await files(slug);
        if (compatible.isEmpty) return null;
        final author = raw['author'];
        return GrabCadModel(
          slug: slug,
          name: raw['name'] as String,
          author: author is Map ? author['name']?.toString() ?? '' : '',
          preview: secureGrabCadUrl(raw['preview_image']?.toString()),
          files: compatible,
        );
      }));
      verified.addAll(models.whereType<GrabCadModel>());
    }
    return GrabCadPage(verified,
        page * (data['per_page'] as num) < (data['total_entries'] as num));
  }

  /// Desktop fallback. iPad downloads use WKWebView's authenticated cookies
  /// through native_menu; credentials never pass through Dart.
  Future<String> download(GrabCadFile file,
      {void Function(int received, int? total)? onProgress}) async {
    final directory = await Directory.systemTemp.createTemp('grabcad_');
    final output = File('${directory.path}/${file.name}');
    try {
      final response = await _http
          .send(http.Request('GET', file.download))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const GrabCadException('sign_in_required');
      }
      if (response.statusCode != 200)
        throw const GrabCadException('unavailable');
      final type = response.headers['content-type'] ?? '';
      if (type.contains('text/html') || type.contains('application/json')) {
        throw const GrabCadException('invalid_download');
      }
      final total = response.contentLength;
      if (total != null && total > maxDownloadBytes) {
        throw const GrabCadException('too_large');
      }
      final sink = output.openWrite();
      var received = 0;
      try {
        await for (final bytes
            in response.stream.timeout(const Duration(seconds: 60))) {
          received += bytes.length;
          if (received > maxDownloadBytes)
            throw const GrabCadException('too_large');
          sink.add(bytes);
          onProgress?.call(received, total);
        }
      } finally {
        await sink.close();
      }
      if (received == 0 || (total != null && total != received)) {
        throw const GrabCadException('invalid_download');
      }
      return output.path;
    } catch (_) {
      await directory.delete(recursive: true);
      rethrow;
    }
  }
}

Uri? secureGrabCadUrl(String? value) {
  if (value == null) return null;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.host != 'grabcad.com' ||
      (uri.hasPort && uri.port != 443)) return null;
  return uri;
}

class GrabCadFile {
  const GrabCadFile(this.id, this.name, this.download);
  final String id;
  final String name;
  final Uri download;
  String get extension => name.split('.').last.toLowerCase();
  int get priority => switch (extension) {
        'step' || 'stp' => 0,
        'ipt' => 1,
        'dxf' => 2,
        _ => 3,
      };

  static GrabCadFile? fromJson(Map<String, dynamic> raw) {
    final name = raw['name'];
    final id = raw['id'];
    final download = secureGrabCadUrl(raw['download_url']?.toString());
    if (name is! String ||
        id == null ||
        download == null ||
        name.contains('/') ||
        name.contains('\\') ||
        name.contains(RegExp(r'[\x00-\x1f]')) ||
        !name.contains('.')) return null;
    final extension = name.split('.').last.toLowerCase();
    // Native document containers are not foreign GrabCAD model formats.
    if (!kOpenableExtensions.contains(extension) ||
        kDocExtensions.contains(extension)) return null;
    return GrabCadFile(id.toString(), name, download);
  }
}

class GrabCadModel {
  const GrabCadModel(
      {required this.slug,
      required this.name,
      required this.author,
      required this.preview,
      required this.files});
  final String slug, name, author;
  final Uri? preview;
  final List<GrabCadFile> files;
}

class GrabCadPage {
  const GrabCadPage(this.models, this.hasMore);
  final List<GrabCadModel> models;
  final bool hasMore;
}

class GrabCadException implements Exception {
  const GrabCadException(this.code);
  final String code;
}
