import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as path;

import 'ai_build123d_transport.dart';

/// Runs the identical offline Python/WASM worker used on iPad, in a bundled
/// headless engine. No system browser, Python install or modelling server.
class DesktopBuild123dTransport implements Build123dTransport {
  DesktopBuild123dTransport({
    Directory? assets,
    File? executable,
    this.startupTimeout = const Duration(seconds: 30),
    this.buildTimeout = const Duration(seconds: 160),
  })  : assets = assets ??
            Directory('${File(Platform.resolvedExecutable).parent.path}'
                '/data/flutter_assets/assets/modelling'),
        executable = executable ??
            File('${File(Platform.resolvedExecutable).parent.path}'
                '/runtime/modelling/chrome-headless-shell'
                '${Platform.isWindows ? '.exe' : ''}');

  final Directory assets;
  final File executable;
  final Duration startupTimeout;
  final Duration buildTimeout;
  _DesktopJob? _active;

  @override
  void cancel() => _active?.cancel();

  @override
  Stream<Map<String, dynamic>> generate(Map<String, dynamic> job) async* {
    if (_active != null)
      throw StateError('A local model build is already running');
    final run = _DesktopJob(this);
    _active = run;
    try {
      yield* run.generate(job);
    } finally {
      _active = null;
    }
  }
}

class _DesktopJob {
  _DesktopJob(this.owner);
  final DesktopBuild123dTransport owner;
  final events = StreamController<Map<String, dynamic>>();
  Process? process;
  Directory? profile;
  HttpServer? server;
  _CadProtocol? protocol;
  Timer? deadline;
  bool cancelled = false;
  bool terminal = false;
  bool disposed = false;
  String session = '';
  String stderrTail = '';
  int eventCount = 0;
  int eventBytes = 0;

  void cancel() {
    if (terminal || disposed) return;
    cancelled = true;
    _fail(StateError('Local CAD build cancelled'));
  }

  void _fail(Object error) {
    if (disposed || events.isClosed) return;
    events.addError(error);
    unawaited(events.close());
    process?.kill();
  }

  void _checkCancelled() {
    if (cancelled || disposed) throw StateError('Local CAD build cancelled');
  }

  Stream<Map<String, dynamic>> generate(Map<String, dynamic> job) async* {
    try {
      final code = job['code'];
      if (code is! String ||
          code.isEmpty ||
          utf8.encode(code).length > 100000 ||
          utf8.encode(jsonEncode(job)).length > 16 * 1024 * 1024) {
        throw const FormatException('Invalid or oversized local CAD script');
      }
      if (!await owner.executable.exists() ||
          !await File('${owner.assets.path}/manifest.json').exists()) {
        throw const FileSystemException(
            'Offline build123d runtime is missing from this app installation. '
            'Install the complete desktop release.');
      }
      // Attach the consumer before startup: cancellation and startup failures
      // must not create an unhandled error while Python is still loading.
      final startup = _start(job)
          .timeout(owner.startupTimeout)
          .catchError((Object error, StackTrace stack) {
        _fail(error);
      });
      deadline = Timer(owner.startupTimeout + owner.buildTimeout, () {
        _fail(TimeoutException('Local CAD runtime timed out'));
      });
      yield* events.stream;
      await startup;
      if (!terminal)
        throw const FormatException('Local CAD stopped before completing');
    } finally {
      disposed = true;
      deadline?.cancel();
      process?.kill();
      await protocol?.close();
      await server?.close(force: true);
      final child = process;
      if (child != null) {
        try {
          await child.exitCode.timeout(const Duration(seconds: 3));
        } on TimeoutException {
          child.kill(ProcessSignal.sigkill);
          await child.exitCode.timeout(const Duration(seconds: 3));
        }
      }
      if (!events.isClosed) unawaited(events.close());
      final dir = profile;
      if (dir != null && await dir.exists()) {
        // Windows can keep profile handles briefly after process exit.
        for (var i = 0; i < 5; i++) {
          try {
            await dir.delete(recursive: true);
            break;
          } on FileSystemException {
            if (i == 4) break;
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        }
      }
    }
  }

  Future<void> _start(Map<String, dynamic> job) async {
    _checkCancelled();
    final random = Random.secure();
    final route = List.generate(
            24, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
    final root = await owner.assets.resolveSymbolicLinks();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _checkCancelled();
    final base = 'http://127.0.0.1:${server!.port}/$route/';
    server!.listen((request) async {
      try {
        final path = request.uri.pathSegments;
        if (request.method != 'GET' ||
            path.length != 2 ||
            path.first != route ||
            path.last.contains('..') ||
            !RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(path.last)) {
          request.response.statusCode = HttpStatus.notFound;
        } else {
          final file = File(_assetPath(root, path.last));
          if (!await file.exists() ||
              !_samePath(await file.resolveSymbolicLinks(), file.path)) {
            request.response.statusCode = HttpStatus.notFound;
          } else {
            final ext = path.last.split('.').last;
            final mime = {
                  'html': 'text/html',
                  'js': 'application/javascript',
                  'wasm': 'application/wasm',
                  'json': 'application/json',
                  'py': 'text/plain'
                }[ext] ??
                'application/octet-stream';
            request.response.headers.set('Content-Type', mime);
            request.response.headers.set(
                'Content-Security-Policy',
                "default-src 'none'; script-src 'self' 'unsafe-eval' 'wasm-unsafe-eval'; "
                    "worker-src 'self'; connect-src 'self'; style-src 'none'; img-src 'none'");
            request.response.headers
                .set('Cross-Origin-Resource-Policy', 'same-origin');
            request.response.headers.set('X-Content-Type-Options', 'nosniff');
            request.response.contentLength = await file.length();
            await request.response.addStream(file.openRead());
          }
        }
        await request.response.close();
      } catch (_) {
        try {
          await request.response.close();
        } catch (_) {}
      }
    }, onError: (Object error) => _fail(error));
    profile = await Directory.systemTemp.createTemp('prototype-cad-');
    _checkCancelled();
    final endpoint = Completer<String>();
    process = await Process.start(
        owner.executable.path,
        [
          '--headless', '--remote-debugging-address=127.0.0.1',
          '--remote-debugging-port=0', '--user-data-dir=${profile!.path}',
          '--no-first-run', '--no-default-browser-check',
          '--disable-background-networking', '--disable-component-update',
          '--disable-sync', '--disable-gpu', '--disable-dev-shm-usage',
          '--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1',
          // Portable Linux installations have no root-owned setuid helper and
          // distributions may block user namespaces. Model code still has only
          // the Web Worker's WASM filesystem, same-origin assets and CSP.
          if (Platform.isLinux) '--no-sandbox',
          'about:blank',
        ],
        includeParentEnvironment: false,
        environment: {
          // Provider credentials and the app's environment never enter the child.
          if (Platform.isWindows && Platform.environment['SystemRoot'] != null)
            'SystemRoot': Platform.environment['SystemRoot']!,
          if (Platform.isLinux)
            'LD_LIBRARY_PATH': '${owner.executable.parent.path}/lib',
        });
    _checkCancelled();
    unawaited(process!.stdout.drain<void>());
    process!.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      stderrTail = '$stderrTail\n$line';
      if (stderrTail.length > 4000)
        stderrTail = stderrTail.substring(stderrTail.length - 4000);
      final match = RegExp(
              r'DevTools listening on (ws://127\.0\.0\.1:\d+/devtools/browser/[a-zA-Z0-9-]+)')
          .firstMatch(line);
      if (match != null && !endpoint.isCompleted)
        endpoint.complete(match.group(1));
    }, onError: (Object error) {
      if (!endpoint.isCompleted) endpoint.completeError(error);
    });
    unawaited(process!.exitCode.then((exit) {
      final error = StateError('Local CAD engine stopped ($exit). $stderrTail');
      if (!endpoint.isCompleted) endpoint.completeError(error);
      if (!terminal && !disposed) _fail(error);
    }));
    protocol = _CadProtocol(
        await WebSocket.connect(await endpoint.future)
            .timeout(const Duration(seconds: 5)),
        _fail);
    _checkCancelled();
    final target =
        await protocol!.call('Target.createTarget', {'url': 'about:blank'});
    final attached = await protocol!.call('Target.attachToTarget', {
      'targetId': target['targetId'],
      'flatten': true,
    });
    session = attached['sessionId'] as String;
    final loaded = Completer<void>();
    protocol!.onEvent = (method, params, eventSession) {
      if (eventSession != session) return;
      if (method == 'Page.loadEventFired' && !loaded.isCompleted)
        loaded.complete();
      if (method == 'Runtime.bindingCalled' &&
          params['name'] == 'cadDesktopEvent') {
        try {
          final payload = params['payload'] as String;
          if (utf8.encode(payload).length > 17 * 1024 * 1024) {
            throw const FormatException(
                'Local model event exceeds geometry limits');
          }
          final envelope = jsonDecode(payload) as Map;
          if (envelope['id'] != route || terminal) return;
          final event = Map<String, dynamic>.from(envelope['event'] as Map);
          final size = utf8.encode(jsonEncode(event)).length;
          eventBytes += size;
          if (++eventCount > 33 ||
              eventBytes > 64 * 1024 * 1024 ||
              !const {'preview', 'complete', 'error'}.contains(event['type'])) {
            throw const FormatException('Invalid or oversized local CAD event');
          }
          terminal = event['type'] != 'preview';
          events.add(event);
          if (terminal) unawaited(events.close());
        } catch (error) {
          _fail(error);
        }
      }
    };
    await protocol!.call('Page.enable', {}, session);
    await protocol!.call('Runtime.enable', {}, session);
    await protocol!
        .call('Runtime.addBinding', {'name': 'cadDesktopEvent'}, session);
    await protocol!.call(
        'Page.addScriptToEvaluateOnNewDocument',
        {
          'source':
              'window.cadTestEvent = payload => cadDesktopEvent(JSON.stringify(payload));',
        },
        session);
    await protocol!
        .call('Page.navigate', {'url': '${base}index.html'}, session);
    await loaded.future.timeout(owner.startupTimeout);
    _checkCancelled();
    final started = await protocol!.call(
        'Runtime.evaluate',
        {
          'expression':
              'window.cadRun(${jsonEncode(route)},${jsonEncode(job)})',
        },
        session);
    if (started['exceptionDetails'] != null) {
      throw StateError(
          'Local CAD worker could not start: ${started['exceptionDetails']}');
    }
  }
}

String _assetPath(String root, String name) => path.join(root, name);
bool _samePath(String a, String b) => path.equals(a, b);

/// Small CDP client; the trusted page's binding is never installed in workers.
class _CadProtocol {
  _CadProtocol(this.socket, this.onFailure) {
    subscription = socket.listen((raw) {
      try {
        if (raw is! String || raw.length > 18 * 1024 * 1024) {
          throw const FormatException('Invalid local engine message');
        }
        final message = jsonDecode(raw) as Map;
        final id = message['id'];
        if (id is int) {
          final pending = requests.remove(id);
          if (message['error'] != null) {
            pending?.completeError(StateError('${message['error']}'));
          } else {
            pending?.complete(
                Map<String, dynamic>.from(message['result'] as Map? ?? {}));
          }
        } else {
          onEvent?.call(
              message['method'] as String,
              Map<String, dynamic>.from(message['params'] as Map? ?? {}),
              message['sessionId'] as String?);
        }
      } catch (error) {
        _fail(error);
      }
    },
        onError: (Object error) => _fail(error),
        onDone: () => _fail(StateError('Local CAD connection closed')));
  }
  final WebSocket socket;
  final void Function(Object) onFailure;
  late final StreamSubscription<dynamic> subscription;
  final requests = <int, Completer<Map<String, dynamic>>>{};
  void Function(String, Map<String, dynamic>, String?)? onEvent;
  int sequence = 0;

  Future<Map<String, dynamic>> call(String method, Map<String, dynamic> params,
      [String? session]) async {
    final id = ++sequence;
    final result = Completer<Map<String, dynamic>>();
    requests[id] = result;
    socket.add(jsonEncode({
      'id': id,
      'method': method,
      'params': params,
      if (session != null) 'sessionId': session
    }));
    try {
      return await result.future.timeout(const Duration(seconds: 20));
    } finally {
      requests.remove(id);
    }
  }

  void _fail(Object error) {
    final pending = requests.values.toList();
    requests.clear();
    for (final request in pending) {
      request.completeError(error);
    }
    onFailure(error);
  }

  Future<void> close() async {
    _fail(StateError('Local CAD connection closed'));
    await subscription.cancel();
    await socket.close();
  }
}
