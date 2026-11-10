import 'dart:collection';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Opt in with --dart-define=OQB_PERF=true. Samples stay in process memory.
class PerformanceMetrics extends ChangeNotifier {
  static final instance = PerformanceMetrics();
  static const enabled = bool.fromEnvironment('OQB_PERF');
  final samples = <String, ListQueue<double>>{};
  final counters = <String, int>{};
  final _marks = <String, Stopwatch>{};
  void begin(String name) {
    if (enabled) _marks[name] = Stopwatch()..start();
  }

  void end(String name) {
    final clock = _marks.remove(name);
    if (clock != null) record(name, clock.elapsedMicroseconds / 1000);
  }

  double uiMs = 0, rasterMs = 0;
  int _frames = 0;
  void start() {
    if (enabled) SchedulerBinding.instance.addTimingsCallback(_timings);
  }

  void _timings(List<FrameTiming> frames) {
    for (final f in frames) {
      uiMs = f.buildDuration.inMicroseconds / 1000;
      rasterMs = f.rasterDuration.inMicroseconds / 1000;
      record('UI frame', uiMs);
      record('Raster frame', rasterMs);
    }
    _frames += frames.length;
    if (_frames >= 15) {
      _frames = 0;
      notifyListeners();
    }
  }

  void record(String name, double milliseconds) {
    if (!enabled) return;
    final queue = samples.putIfAbsent(name, ListQueue.new)..add(milliseconds);
    if (queue.length > 120) queue.removeFirst();
  }

  void count(String name, int value) {
    if (enabled) counters[name] = value;
  }

  Future<T> measure<T>(String name, Future<T> Function() action) async {
    if (!enabled) return action();
    final timer = Stopwatch()..start();
    final task = TimelineTask()..start(name);
    try {
      return await action();
    } finally {
      task.finish();
      record(name, timer.elapsedMicroseconds / 1000);
    }
  }
}
