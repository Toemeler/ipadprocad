import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prototype/grabcad/grabcad_client.dart';

Map<String, dynamic> file(String name, {String id = '1', String? url}) => {
      'id': id,
      'name': name,
      'download_url': url ??
          'https://grabcad.com/community/api/v1/models/test/files/download?cadid=$id',
    };
http.Response jsonResponse(Object data) => http.Response(jsonEncode(data), 200,
    headers: {'content-type': 'application/json'});
Map<String, dynamic> listing(List<Object> files,
        {List<Object> folders = const []}) =>
    {'files': files, 'folders': folders};

void main() {
  test('assembly search excludes drawing-only models and DXF files', () async {
    final client = GrabCadClient(
      allowedExtensions: GrabCadClient.componentExtensions,
      client: MockClient((request) async {
        if (request.method == 'POST') {
          return jsonResponse({
            'per_page': 24,
            'total_entries': 2,
            'models': [
              {'cached_slug': 'drawing', 'name': 'Drawing'},
              {'cached_slug': 'part', 'name': 'Part with drawing'},
            ]
          });
        }
        return jsonResponse(listing(request.url.path.contains('/drawing/')
            ? [file('drawing.dxf')]
            : [file('part.step'), file('drawing.dxf', id: '2')]));
      }),
    );
    addTearDown(client.close);
    final result = await client.search('bearing');
    expect(result.models.map((m) => m.slug), ['part']);
    expect(result.models.single.files.map((f) => f.extension), ['step']);
  });
  test('compatibility uses actual extension, not software or extension labels',
      () {
    for (final name in [
      'a.STEP',
      'b.stp',
      'c.ipt',
      'd.dxf',
      'e.stl',
      'f.obj',
      'g.3mf'
    ]) {
      expect(GrabCadFile.fromJson(file(name)), isNotNull);
    }
    for (final name in [
      'a.iges',
      'b.sldprt',
      'c.iam',
      'd.zip',
      'e.png',
      'f.ptp',
      'g.pts',
      'h.pas'
    ]) {
      expect(
          GrabCadFile.fromJson(
              {...file(name), 'extension': 'step', 'system': 'STEP / IGES'}),
          isNull);
    }
    for (final name in [
      '../a.step',
      'folder/a.step',
      'folder\\a.step',
      'a\x00.step'
    ]) {
      expect(GrabCadFile.fromJson(file(name)), isNull);
    }
    for (final url in [
      'http://grabcad.com/a.step',
      'https://evil.test/a.step',
      'https://grabcad.com.evil.test/a.step',
      'https://user@grabcad.com/a.step'
    ]) {
      expect(GrabCadFile.fromJson(file('a.step', url: url)), isNull);
    }
  });

  test('search verifies nested files, excludes IGES-only and hidden models',
      () async {
    final requests = <http.Request>[];
    final client = GrabCadClient(client: MockClient((request) async {
      requests.add(request);
      final path = request.url.path;
      if (request.method == 'POST') {
        expect(jsonDecode(request.body)['query'], 'bearing');
        expect(jsonDecode(request.body)['page'], 2);
        return jsonResponse({
          'per_page': 24,
          'total_entries': 60,
          'models': [
            {
              'cached_slug': 'nested',
              'name': 'Nested bearing',
              'author': {'name': 'Creator'}
            },
            {
              'cached_slug': 'iges',
              'name': 'IGES only',
              'softwares': [
                {'name': 'STEP / IGES'}
              ]
            },
            {'cached_slug': 'hidden', 'name': 'Hidden', 'is_hidden': true},
          ]
        });
      }
      if (path.contains('/nested/')) {
        if (request.url.queryParameters['folder_id'] == '2') {
          return jsonResponse(
              listing([file('bearing.stp'), file('preview.png')]));
        }
        return jsonResponse(listing([
          file('bearing.stl', id: '2')
        ], folders: [
          {'id': 2}
        ]));
      }
      if (path.contains('/iges/'))
        return jsonResponse(listing([file('bearing.igs')]));
      fail('Unexpected metadata request: $path');
    }));
    addTearDown(client.close);
    final result = await client.search(' bearing ', page: 2);
    expect(result.models.map((m) => m.slug), ['nested']);
    expect(result.models.single.files.map((f) => f.name),
        ['bearing.stp', 'bearing.stl']);
    expect(result.hasMore, isTrue);
    expect(requests.any((r) => r.url.path.contains('/hidden/')), isFalse);
  });

  test('metadata errors are retryable instead of silently hiding results',
      () async {
    final client = GrabCadClient(
        client: MockClient((request) async => request.method == 'POST'
            ? jsonResponse({
                'per_page': 24,
                'total_entries': 1,
                'models': [
                  {'cached_slug': 'test', 'name': 'Bearing'}
                ],
              })
            : http.Response('Unavailable', 503)));
    addTearDown(client.close);
    await expectLater(
        client.search('bearing'), throwsA(isA<GrabCadException>()));
  });

  test('malformed search responses and search-down do not become empty success',
      () async {
    for (final data in [
      {'search_down': true},
      {'models': [], 'per_page': 0, 'total_entries': 1}
    ]) {
      final client =
          GrabCadClient(client: MockClient((_) async => jsonResponse(data)));
      await expectLater(
          client.search('bearing'), throwsA(isA<GrabCadException>()));
      client.close();
    }
  });

  test('folder cycles cannot cause endless metadata requests', () async {
    var calls = 0;
    final client = GrabCadClient(client: MockClient((_) async {
      calls++;
      return jsonResponse(listing([
        file('bearing.step')
      ], folders: [
        {'id': 1}
      ]));
    }));
    addTearDown(client.close);
    expect(await client.files('test'), hasLength(1));
    expect(calls, 2);
  });

  test('download streams to a local file and reports progress', () async {
    final client = GrabCadClient(
        client: MockClient((_) async => http.Response('ISO-10303-21;', 200,
            headers: {'content-type': 'application/octet-stream'})));
    addTearDown(client.close);
    var received = 0;
    final path = await client.download(
        GrabCadFile.fromJson(file('bearing.step'))!,
        onProgress: (count, _) => received = count);
    try {
      expect(await File(path).readAsString(), 'ISO-10303-21;');
      expect(received, 13);
      expect(File(path).uri.pathSegments.last, 'bearing.step');
    } finally {
      await File(path).parent.delete(recursive: true);
    }
  });

  test(
      'login pages, empty downloads and unauthorized responses cannot be imported',
      () async {
    for (final response in [
      http.Response('', 200),
      http.Response('Login', 401),
      http.Response('<html>login</html>', 200,
          headers: {'content-type': 'text/html'})
    ]) {
      final client = GrabCadClient(client: MockClient((_) async => response));
      await expectLater(
          client.download(GrabCadFile.fromJson(file('bearing.step'))!),
          throwsA(isA<GrabCadException>()));
      client.close();
    }
  });
}
