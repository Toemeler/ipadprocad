// Bottom-right performance readout (M77).
//
// Exists because three rounds of this project's performance work went into the
// wrong layer: the 3D re-tessellation was optimised repeatedly while the
// reported stutter came from the 2D painter (see HANDOFF M75). The `perf:` log
// channel only covers re-meshing, and a log cannot show you a frame time while
// you are dragging. This can.
//
// It measures the FRAME time Flutter actually reports, not a wall clock, so it
// reflects the real cost of building and rasterising each frame.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../app_state.dart';
import '../perf.dart';
import '../theme.dart';

/// Rolling frame-time statistics fed by [SchedulerBinding]'s timings callback.
class PerfStats {
  static const _window = 60;
  final List<double> _ms = [];

  /// Worst frame in the window, in milliseconds. The average hides exactly the
  /// hitches we are hunting, so this is the number that matters.
  double worstMs = 0;
  double avgMs = 0;

  void add(double ms) {
    _ms.add(ms);
    if (_ms.length > _window) _ms.removeAt(0);
    var sum = 0.0, worst = 0.0;
    for (final v in _ms) {
      sum += v;
      if (v > worst) worst = v;
    }
    avgMs = sum / _ms.length;
    worstMs = worst;
  }

  double get fps => avgMs <= 0.01 ? 0 : 1000 / avgMs;
}

class PerfOverlay extends StatefulWidget {
  const PerfOverlay({super.key, required this.app});
  final AppState app;

  @override
  State<PerfOverlay> createState() => _PerfOverlayState();
}

class _PerfOverlayState extends State<PerfOverlay> {
  final _stats = PerfStats();
  TimingsCallback? _cb;
  DateTime _lastPaint = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _cb = (timings) {
      for (final t in timings) {
        _stats.add(t.totalSpan.inMicroseconds / 1000.0);
      }
      // Repaint at most ~5 Hz: an overlay that rebuilds every frame would
      // itself become a cost, which would be a silly way to measure cost.
      final now = DateTime.now();
      if (now.difference(_lastPaint).inMilliseconds >= 200 && mounted) {
        _lastPaint = now;
        setState(() {});
      }
    };
    SchedulerBinding.instance.addTimingsCallback(_cb!);
  }

  @override
  void dispose() {
    if (_cb != null) SchedulerBinding.instance.removeTimingsCallback(_cb!);
    super.dispose();
  }

  /// Scene cost that is NOT visible in a frame time but explains it.
  ///
  /// THROTTLED, because this walks every feature and sums every mesh's index
  /// count. At the overlay's 5 Hz repaint on a 34 000-triangle scene that is
  /// the instrument billing the app for being watched — precisely the failure
  /// mode perf.dart's header warns about. The counts change only when the
  /// model does, so recomputing them five times a second bought nothing.
  /// Once per second, cached in between.
  static const _sceneRecount = Duration(seconds: 1);
  DateTime _lastScene = DateTime.fromMillisecondsSinceEpoch(0);
  String _sceneCache = '';

  String _sceneLine() {
    final p = widget.app.currentPart;
    if (p == null) return '';
    final now = DateTime.now();
    if (now.difference(_lastScene) < _sceneRecount) return _sceneCache;
    _lastScene = now;
    var tris = 0, solids = 0, feats = 0;
    for (final f in p.features) {
      feats++;
      final s = f.solid;
      if (s == null || !f.visible || f.consumedByJoin) continue;
      solids++;
      tris += s.mesh.indices.length ~/ 3;
    }
    Perf.gauge('features', feats);
    Perf.gauge('solids', solids);
    Perf.gauge('triangles', tris);
    return _sceneCache = 'f$feats s$solids ${_k(tris)}tri';
  }

  String _sketchLine() {
    final s = widget.app.current;
    if (s == null) return '';
    final n = s.geometry.length;
    var proj = 0;
    for (final g in s.geometry) {
      if (g.isProjection) proj++;
    }
    Perf.gauge('sketchEntities', n);
    Perf.gauge('sketchProjections', proj);
    return 'geo $n${proj > 0 ? ' (proj $proj)' : ''}';
  }

  String _memLine() {
    try {
      final mb = ProcessInfo.currentRss ~/ (1024 * 1024);
      return '${mb}MB';
    } catch (_) {
      return '';
    }
  }

  static String _k(int v) =>
      v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}k' : '$v';

  @override
  Widget build(BuildContext context) {
    final fps = _stats.fps;
    // Colour only when it is actually bad, so the overlay stays quiet.
    final worst = _stats.worstMs;
    final tint = worst > 33
        ? T.err
        : worst > 20
            ? T.warnText
            : T.rawGrey;
    final lines = <String>[
      '${fps.toStringAsFixed(0)} fps  '
          '${_stats.avgMs.toStringAsFixed(1)}/${worst.toStringAsFixed(0)}ms',
      'build ${Perf.frameBuild.avgMs.toStringAsFixed(1)}  '
          'raster ${Perf.frameRaster.avgMs.toStringAsFixed(1)}ms',
      _sceneLine(),
      _sketchLine(),
      _memLine(),
    ].where((l) => l.isNotEmpty).toList();

    return Positioned(
      right: 6,
      bottom: 4,
      child: IgnorePointer(
        child: Opacity(
          opacity: 0.5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final l in lines)
                Text(
                  l,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontFamily: 'Menlo',
                    fontSize: 9,
                    height: 1.25,
                    color: l == lines.first ? tint : T.rawGrey,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rounds [v] for display without pretending to precision we do not have.
double roundMs(double v) => (v * 10).roundToDouble() / 10;

/// Kept for tests: the worst frame in a window drives the colour, not the
/// average, because an average of 16 ms with one 200 ms hitch still stutters.
double worstOf(Iterable<double> ms) =>
    ms.isEmpty ? 0 : ms.reduce((a, b) => math.max(a, b));
