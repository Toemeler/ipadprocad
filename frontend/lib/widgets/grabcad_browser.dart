import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:native_menu/grabcad.dart';

import '../app_state.dart';
import '../grabcad/grabcad_client.dart';
import '../l10n/l.dart';
import '../theme.dart';

class GrabCadBrowser extends StatefulWidget {
  const GrabCadBrowser(
      {super.key,
      required this.onOpen,
      this.clientFactory,
      this.componentOnly = false});
  final Future<bool> Function(String path) onOpen;
  final GrabCadClient Function()? clientFactory;
  final bool componentOnly;

  static Future<void> show(BuildContext context, AppState app) =>
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => GrabCadBrowser(
            onOpen: (path) async => await app.openPath(path) != null),
      );

  static Future<void> showForAssembly(
      BuildContext context, AppState app) async {
    final assemblyName = app.currentAssembly?.name;
    if (assemblyName == null) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => GrabCadBrowser(
        componentOnly: true,
        onOpen: (path) async =>
            await app.importAndPlaceComponent(path,
                assemblyName: assemblyName) !=
            null,
      ),
    );
  }

  @override
  State<GrabCadBrowser> createState() => _GrabCadBrowserState();
}

class _GrabCadBrowserState extends State<GrabCadBrowser> {
  final _query = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;
  GrabCadClient? _searchClient;
  GrabCadClient? _downloadClient;
  final _models = <GrabCadModel>[];
  int _revision = 0, _page = 0;
  String _activeQuery = '';
  bool _searching = false,
      _hasMore = false,
      _opening = false,
      _importing = false;
  String? _error;
  double? _progress;

  GrabCadClient _newClient() =>
      widget.clientFactory?.call() ??
      GrabCadClient(
          allowedExtensions:
              widget.componentOnly ? GrabCadClient.componentExtensions : null);

  @override
  void dispose() {
    _revision++;
    _debounce?.cancel();
    _query.dispose();
    _scroll.dispose();
    _searchClient?.close();
    _downloadClient?.close();
    if (_opening && NativeGrabCad.supported) {
      unawaited(NativeGrabCad.cancelDownload().catchError((_) {}));
    }
    super.dispose();
  }

  void _changed(String text) {
    _debounce?.cancel();
    _revision++;
    _searchClient?.close();
    setState(() {
      _models.clear();
      _page = 0;
      _hasMore = false;
      _error = null;
      _activeQuery = text.trim();
      _searching = _activeQuery.isNotEmpty;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    if (_activeQuery.isNotEmpty) {
      _debounce =
          Timer(const Duration(milliseconds: 400), () => _search(reset: true));
    }
  }

  Future<void> _search({bool reset = false}) async {
    _debounce?.cancel();
    if (_opening || _activeQuery.isEmpty) return;
    final revision = ++_revision;
    _searchClient?.close();
    final client = _newClient();
    _searchClient = client;
    final nextPage = reset ? 1 : _page + 1;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      // Skip sparse incompatible-only pages automatically, with a bound so
      // even a very broad query cannot trigger an unbounded library scan.
      var page = nextPage;
      GrabCadPage result;
      do {
        result = await client.search(_activeQuery, page: page);
        if (!mounted || revision != _revision) return;
        if (result.models.isNotEmpty || !result.hasMore || page >= nextPage + 2)
          break;
        page++;
      } while (true);
      setState(() {
        if (reset) _models.clear();
        final seen = _models.map((m) => m.slug).toSet();
        _models.addAll(result.models.where((m) => seen.add(m.slug)));
        _page = page;
        _hasMore = result.hasMore;
        _searching = false;
      });
    } catch (_) {
      if (mounted && revision == _revision) {
        setState(() {
          _searching = false;
          _error = 'unavailable';
        });
      }
    }
  }

  Future<void> _select(GrabCadModel model) async {
    final t = L.of(context);
    final file = model.files.length == 1
        ? model.files.single
        : await showDialog<GrabCadFile>(
            context: context,
            builder: (context) => AlertDialog(
                  backgroundColor: T.fly,
                  title: Text(model.name, style: TextStyle(color: T.text)),
                  content: SizedBox(
                      width: 440,
                      child: SingleChildScrollView(
                          child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: model.files
                            .map((file) => ListTile(
                                  title: Text(file.name,
                                      style: TextStyle(color: T.text)),
                                  trailing: const Icon(Icons.open_in_new),
                                  onTap: () => Navigator.pop(context, file),
                                ))
                            .toList(),
                      ))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(t.cancel))
                  ],
                ));
    if (file == null || !mounted) return;
    await _open(file);
  }

  Future<String> _download(GrabCadFile file, GrabCadClient? client) async {
    if (NativeGrabCad.supported) {
      return NativeGrabCad.download(file.download.toString(), file.name);
    }
    return client!.download(file, onProgress: (received, total) {
      if (mounted && _opening)
        setState(() =>
            _progress = total == null || total <= 0 ? null : received / total);
    });
  }

  Future<void> _open(GrabCadFile file) async {
    final revision = ++_revision;
    final downloadClient = NativeGrabCad.supported ? null : _newClient();
    _downloadClient = downloadClient;
    _searchClient?.close();
    setState(() {
      _opening = true;
      _searching = false;
      _error = null;
      _progress = null;
    });
    String? path;
    try {
      try {
        path = await _download(file, downloadClient);
      } on PlatformException catch (e) {
        if (e.code != 'sign_in_required') rethrow;
        if (!mounted || revision != _revision) return;
        final t = L.of(context);
        final signedIn = await NativeGrabCad.signIn(
          title: t.grabCadSignIn,
          done: t.done,
          cancel: t.cancel,
          help: t.grabCadLoginHelp,
        );
        if (!signedIn || !mounted || revision != _revision) return;
        path = await _download(file, downloadClient);
      }
      if (!mounted || revision != _revision) return;
      setState(() {
        _importing = true;
        _progress = null;
      });
      final success = await widget.onOpen(path);
      if (!mounted) return;
      if (success) {
        Navigator.pop(context);
      } else {
        setState(() => _error = 'import_failed');
      }
    } catch (e) {
      if (mounted && revision == _revision) {
        setState(() => _error = e is GrabCadException
            ? e.code
            : e is PlatformException
                ? e.code
                : 'unavailable');
      }
    } finally {
      if (path != null) {
        // Importers copy required source files into their document before
        // returning. Download staging never becomes a persistent dependency.
        try {
          await File(path).parent.delete(recursive: true);
        } catch (_) {}
      }
      downloadClient?.close();
      if (identical(_downloadClient, downloadClient)) _downloadClient = null;
      if (mounted && revision == _revision) {
        setState(() {
          _opening = false;
          _importing = false;
        });
      }
    }
  }

  void _cancelDownload() {
    _revision++;
    _downloadClient?.close();
    if (NativeGrabCad.supported) {
      unawaited(NativeGrabCad.cancelDownload().catchError((_) {}));
    }
    setState(() {
      _opening = false;
      _error = null;
    });
  }

  String _errorText(AppL10n t) => switch (_error) {
        'too_large' => t.grabCadTooLarge,
        'sign_in_required' =>
          NativeGrabCad.supported ? t.grabCadLoginHelp : t.grabCadDesktopLogin,
        'invalid_download' => t.grabCadInvalidDownload,
        'import_failed' => t.grabCadImportFailed,
        _ => t.grabCadUnavailable,
      };

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    return PopScope(
        canPop: !_importing,
        child: Dialog(
          backgroundColor: T.fly,
          child: SizedBox(
              width: 840,
              height: 650,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(children: [
                  Row(children: [
                    Expanded(
                        child: Text(t.grabCadTitle, style: ts(22, T.text))),
                    IconButton(
                        tooltip: t.close,
                        onPressed:
                            _importing ? null : () => Navigator.pop(context),
                        icon: const Icon(Icons.close)),
                  ]),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('grabcad-search'),
                    controller: _query,
                    enabled: !_opening,
                    autofocus: true,
                    style: TextStyle(color: T.text),
                    decoration: InputDecoration(
                      labelText: t.grabCadSearch,
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                          tooltip: t.grabCadSearch,
                          onPressed: _opening || _activeQuery.isEmpty
                              ? null
                              : () => _search(reset: true),
                          icon: const Icon(Icons.arrow_forward)),
                    ),
                    onChanged: _changed,
                    onSubmitted: (_) => _search(reset: true),
                  ),
                  const SizedBox(height: 8),
                  Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                          widget.componentOnly
                              ? t.grabCadCompatibleComponents
                              : t.grabCadCompatible,
                          style: ts(12, T.text))),
                  if (_searching || _opening) ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(value: _opening ? _progress : null),
                    Row(children: [
                      Expanded(
                          child: Text(
                              _importing
                                  ? widget.componentOnly
                                      ? t.grabCadInserting
                                      : t.grabCadOpening
                                  : _opening
                                      ? t.grabCadDownloading
                                      : t.grabCadChecking,
                              style: ts(12, T.text))),
                      if (_opening && !_importing)
                        TextButton(
                            onPressed: _cancelDownload, child: Text(t.cancel)),
                    ]),
                  ],
                  if (_error != null)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(children: [
                          Expanded(
                              child:
                                  Text(_errorText(t), style: ts(13, T.text))),
                          if (_error == 'unavailable' &&
                              !_opening &&
                              !_searching)
                            TextButton(
                                onPressed: () => _search(reset: _page == 0),
                                child: Text(t.grabCadRetry)),
                        ])),
                  const SizedBox(height: 8),
                  Expanded(
                      child: _models.isEmpty
                          ? Center(
                              child: Text(
                              _activeQuery.isEmpty
                                  ? t.grabCadSearchHint
                                  : _searching
                                      ? t.grabCadChecking
                                      : _error != null
                                          ? ''
                                          : _hasMore
                                              ? t.grabCadKeepSearching
                                              : t.grabCadNoResults,
                              textAlign: TextAlign.center,
                              style: ts(14, T.text),
                            ))
                          : LayoutBuilder(
                              builder: (context, constraints) =>
                                  GridView.builder(
                                    controller: _scroll,
                                    gridDelegate:
                                        SliverGridDelegateWithFixedCrossAxisCount(
                                            crossAxisCount: constraints
                                                        .maxWidth >=
                                                    600
                                                ? 3
                                                : constraints.maxWidth >= 380
                                                    ? 2
                                                    : 1,
                                            mainAxisExtent: 220,
                                            crossAxisSpacing: 12,
                                            mainAxisSpacing: 12),
                                    itemCount: _models.length,
                                    itemBuilder: (context, index) {
                                      final model = _models[index];
                                      return Material(
                                          color: T.field,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          clipBehavior: Clip.antiAlias,
                                          child: InkWell(
                                            onTap: _opening
                                                ? null
                                                : () => _select(model),
                                            child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Expanded(
                                                      child: SizedBox(
                                                          width:
                                                              double.infinity,
                                                          child: model.preview ==
                                                                  null
                                                              ? const Icon(Icons
                                                                  .view_in_ar)
                                                              : Image.network(
                                                                  model.preview
                                                                      .toString(),
                                                                  fit: BoxFit
                                                                      .contain,
                                                                  errorBuilder: (_,
                                                                          __,
                                                                          ___) =>
                                                                      const Icon(
                                                                          Icons
                                                                              .view_in_ar),
                                                                ))),
                                                  Padding(
                                                      padding:
                                                          const EdgeInsets.all(
                                                              10),
                                                      child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Text(model.name,
                                                                maxLines: 1,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                                style: ts(14,
                                                                    T.text)),
                                                            Text(model.author,
                                                                maxLines: 1,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                                style: ts(11,
                                                                    T.text)),
                                                            Text(
                                                                model.files
                                                                    .map((f) => f
                                                                        .extension
                                                                        .toUpperCase())
                                                                    .toSet()
                                                                    .join(
                                                                        ' · '),
                                                                style: ts(11,
                                                                    T.text)),
                                                          ])),
                                                ]),
                                          ));
                                    },
                                  ))),
                  if (_hasMore && !_opening)
                    TextButton(
                        onPressed: _searching ? null : () => _search(),
                        child: Text(t.grabCadMore)),
                ]),
              )),
        ));
  }
}
