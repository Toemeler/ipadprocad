import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/grabcad/grabcad_client.dart';
import 'package:prototype/l10n/l.dart';
import 'package:prototype/widgets/grabcad_browser.dart';

class SearchClient extends GrabCadClient {
  SearchClient(this.handler);
  final Future<GrabCadPage> Function(String, int) handler;
  @override
  Future<GrabCadPage> search(String query, {int page = 1}) =>
      handler(query, page);
}

GrabCadPage result(String title, {bool more = false}) => GrabCadPage([
      GrabCadModel(
          slug: title,
          name: title,
          author: 'Creator',
          preview: null,
          files: [
            GrabCadFile(
                '1', 'model.step', Uri.parse('https://grabcad.com/download'))
          ]),
    ], more);

void main() {
  setUp(() => L.set(kEn));
  tearDown(() => L.set(kDe));

  testWidgets('debounces search and rejects responses from an older query',
      (tester) async {
    final old = Completer<GrabCadPage>();
    final calls = <String>[];
    await tester.pumpWidget(MaterialApp(
        home: GrabCadBrowser(
      onOpen: (_) async => true,
      clientFactory: () => SearchClient((query, page) {
        calls.add(query);
        return query == 'old'
            ? old.future
            : Future.value(result('New compatible model'));
      }),
    )));
    final search = find.byKey(const Key('grabcad-search'));
    await tester.enterText(search, 'old');
    await tester.pump(const Duration(milliseconds: 399));
    expect(calls, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, ['old']);
    await tester.enterText(search, 'new');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.text('New compatible model'), findsOneWidget);
    old.complete(result('Stale model'));
    await tester.pump();
    expect(find.text('Stale model'), findsNothing);
    expect(find.text('New compatible model'), findsOneWidget);
  });

  testWidgets('skips incompatible-only pages and exposes more results',
      (tester) async {
    final pages = <int>[];
    await tester.pumpWidget(MaterialApp(
        home: GrabCadBrowser(
      onOpen: (_) async => true,
      clientFactory: () => SearchClient((query, page) async {
        pages.add(page);
        return page == 1
            ? const GrabCadPage([], true)
            : result('Compatible page $page', more: page == 2);
      }),
    )));
    await tester.enterText(find.byKey(const Key('grabcad-search')), 'bearing');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(pages, [1, 2]);
    expect(find.text('Compatible page 2'), findsOneWidget);
    await tester.tap(find.text('Search more results'));
    await tester.pump();
    await tester.pump();
    expect(pages, [1, 2, 3]);
    expect(find.text('Compatible page 3'), findsOneWidget);
    expect(find.text('Search more results'), findsNothing);
  });
}
