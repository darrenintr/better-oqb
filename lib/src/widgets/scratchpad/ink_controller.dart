import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'ink_model.dart';
import '../../services/performance_metrics.dart';
import 'ink_gesture_detector.dart';

enum InkPressure { off, low, medium }

class InkEdit {
  InkEdit(this.removed, this.added);
  final Map<int, InkStroke> removed;
  final Map<int, InkStroke> added;
}

/// Completed ink and active input notify separate repaint boundaries.
class InkController extends ChangeNotifier {
  final activeChanged = ChangeNotifier();
  final index = InkSpatialIndex();
  final strokes = <InkStroke>[];
  final _undo = <InkEdit>[];
  final _redo = <InkEdit>[];
  final _pendingRemoved = <int, InkStroke>{};
  final _pendingAdded = <int, InkStroke>{};
  List<Offset> active = [];
  List<double> pressures = [];
  ShapeCandidate? candidate;
  Color color = const Color(0xFF263341);
  double width = 3.5;
  InkPressure sensitivity = InkPressure.low;
  bool holdToSnap = true;
  bool scratchToErase = true;
  bool reducedMotion = false;
  Timer? _hold;
  Timer? _animation;
  Offset? _anchor;
  DateTime _started = DateTime.now();
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  int get historySize => _undo.length;
  bool get isDrawing => active.isNotEmpty;

  void load(Iterable<InkStroke> value) {
    cancelActive();
    strokes
      ..clear()
      ..addAll(value);
    index.clear();
    for (final s in strokes) {
      index.add(s);
    }
    _undo.clear();
    _redo.clear();
    notifyListeners();
  }

  double _pressure(double p) => switch (sensitivity) {
        InkPressure.off => 1,
        InkPressure.low => .85 + p.clamp(0.0, 1.0) * .3,
        InkPressure.medium => .75 + p.clamp(0.0, 1.0) * .6,
      };
  void begin(Offset p, {double pressure = .5}) {
    cancelActive();
    active = [p];
    pressures = [_pressure(pressure)];
    _started = DateTime.now();
    _anchor = p;
    _armHold();
    activeChanged.notifyListeners();
  }

  void move(Offset p, {double pressure = .5}) {
    PerformanceMetrics.instance.begin('Ink event to paint');
    if (active.isEmpty) return;
    if (candidate != null) {
      if ((p - _anchor!).distance <= 8) return;
      // Moving away releases the preview and resumes the original stroke.
      candidate = null;
      _animation?.cancel();
    }
    if ((p - active.last).distance < .6) return;
    active.add(p);
    pressures.add(_pressure(pressure));
    if (_anchor == null || (p - _anchor!).distance > 2) {
      _anchor = p;
      _armHold();
    }
    activeChanged.notifyListeners();
  }

  void _armHold() {
    _hold?.cancel();
    if (!holdToSnap) return;
    _hold = Timer(const Duration(milliseconds: 450), () {
      if (active.length < 3) return;
      final recognized = recognizeShape(active);
      if (recognized == null) return;
      candidate = recognized;
      _previewProgress = reducedMotion ? 1 : 0;
      _animation?.cancel();
      if (!reducedMotion) {
        final clock = Stopwatch()..start();
        _animation = Timer.periodic(const Duration(milliseconds: 16), (timer) {
          _previewProgress = (clock.elapsedMilliseconds / 140).clamp(0.0, 1.0);
          activeChanged.notifyListeners();
          if (_previewProgress >= 1) timer.cancel();
        });
      }
      activeChanged.notifyListeners();
    });
  }

  double _previewProgress = 1;
  List<Offset> get preview {
    final shape = candidate;
    if (shape == null) return active;
    if (_previewProgress >= 1) return shape.points;
    final target = shape.points;
    final lengths = <double>[0];
    for (var i = 1; i < target.length; i++) {
      lengths.add(lengths.last + (target[i] - target[i - 1]).distance);
    }
    var segment = 1;
    return [
      for (var i = 0; i < active.length; i++)
        (() {
          final distance = lengths.last * i / (active.length - 1);
          while (segment < lengths.length - 1 && lengths[segment] < distance) {
            segment++;
          }
          final span = lengths[segment] - lengths[segment - 1];
          final point = Offset.lerp(target[segment - 1], target[segment],
              span == 0 ? 0 : (distance - lengths[segment - 1]) / span)!;
          return Offset.lerp(active[i], point, _previewProgress)!;
        })()
    ];
  }

  void finish({bool allowScratch = true}) {
    if (active.isEmpty) return;
    final targets = allowScratch && scratchToErase && candidate == null
        ? scratchTargets(active, DateTime.now().difference(_started), index)
        : <InkStroke>{};
    if (targets.isNotEmpty) {
      replace(targets, const []);
    } else {
      final shape = candidate;
      final stroke = InkStroke(
        color,
        width,
        shape?.points ?? active,
        pressures: shape == null ? pressures : null,
        smooth: shape == null,
      );
      replace(const {}, [stroke]);
      if (shape != null) {
        // A second undo restores the original freehand stroke before removing it.
        final original = InkStroke(color, width, active, pressures: pressures);
        final at = strokes.indexOf(stroke);
        final edit = _undo.removeLast();
        _undo.add(InkEdit({}, {at: original}));
        _undo.add(InkEdit({at: original}, edit.added));
      }
    }
    cancelActive();
  }

  void cancelActive() {
    _hold?.cancel();
    _animation?.cancel();
    active = [];
    pressures = [];
    candidate = null;
    _anchor = null;
    activeChanged.notifyListeners();
  }

  void replace(Set<InkStroke> removed, List<InkStroke> added) {
    final before = <int, InkStroke>{};
    for (var i = 0; i < strokes.length; i++) {
      if (removed.contains(strokes[i])) before[i] = strokes[i];
    }
    if (before.isEmpty && added.isEmpty) return;
    final after = <int, InkStroke>{};
    final start = strokes.length - before.length;
    for (var i = 0; i < added.length; i++) {
      after[start + i] = added[i];
    }
    final edit = InkEdit(before, after);
    _apply(edit, true);
    _undo.add(edit);
    _redo.clear();
    if (_undo.length > 100) _undo.removeAt(0);
    notifyListeners();
  }

  void _apply(InkEdit edit, bool forward) {
    final remove = forward ? edit.removed : edit.added;
    final add = forward ? edit.added : edit.removed;
    for (final at in remove.keys.toList()..sort((a, b) => b.compareTo(a))) {
      index.remove(strokes.removeAt(at));
    }
    for (final at in add.keys.toList()..sort()) {
      strokes.insert(at, add[at]!);
      index.add(add[at]!);
    }
  }

  void undo() {
    if (!canUndo || isDrawing) return;
    final edit = _undo.removeLast();
    _apply(edit, false);
    _redo.add(edit);
    notifyListeners();
  }

  void redo() {
    if (!canRedo || isDrawing) return;
    final edit = _redo.removeLast();
    _apply(edit, true);
    _undo.add(edit);
    notifyListeners();
  }

  void beginErase() {
    _pendingRemoved.clear();
    _pendingAdded.clear();
  }

  void erase(Offset p, double radius, {bool segment = false}) {
    final targets = index.query(Rect.fromCircle(center: p, radius: radius));
    final removed = <InkStroke>{};
    final added = <InkStroke>[];
    for (final s in targets) {
      var hit = s.points.any((v) => (v - p).distance <= radius);
      for (var j = 1; j < s.points.length && !hit; j++) {
        hit = segmentDistance(p, s.points[j - 1], s.points[j]) <=
            radius + s.width / 2;
      }
      if (!hit) continue;
      removed.add(s);
      if (segment) {
        // Subdivide long segments so erasing between sparse samples still cuts ink.
        var run = <Offset>[];
        void flush() {
          if (run.isNotEmpty) {
            added.add(InkStroke(s.color, s.width, run, smooth: s.smooth));
          }
          run = [];
        }

        for (var j = 0; j < s.points.length; j++) {
          final a = s.points[j == 0 ? 0 : j - 1];
          final b = s.points[j];
          final steps = ((b - a).distance / 2).ceil().clamp(1, 10000);
          for (var step = 1; step <= steps; step++) {
            final at = Offset.lerp(a, b, step / steps)!;
            if ((at - p).distance <= radius + s.width / 2) {
              flush();
            } else {
              run.add(at);
            }
          }
        }
        flush();
      }
    }
    if (removed.isEmpty) return;
    // Merge the whole eraser drag into one command, with identity deltas.
    for (final s in removed) {
      if (_pendingAdded.containsValue(s)) {
        _pendingAdded.removeWhere((_, v) => identical(v, s));
      } else {
        _pendingRemoved[identityHashCode(s)] = s;
      }
      index.remove(s);
    }
    strokes.removeWhere(removed.contains);
    for (final s in added) {
      strokes.add(s);
      index.add(s);
      _pendingAdded[identityHashCode(s)] = s;
    }
    notifyListeners();
  }

  List<InkStroke>? _eraseOrder;
  void startErase() {
    beginErase();
    _eraseOrder = List.of(strokes);
  }

  void endErase() {
    final order = _eraseOrder;
    _eraseOrder = null;
    if (order == null || _pendingRemoved.isEmpty && _pendingAdded.isEmpty) {
      return;
    }
    final before = <int, InkStroke>{};
    final after = <int, InkStroke>{};
    for (var i = 0; i < order.length; i++) {
      if (_pendingRemoved.containsValue(order[i])) before[i] = order[i];
    }
    for (var i = 0; i < strokes.length; i++) {
      if (_pendingAdded.containsValue(strokes[i])) after[i] = strokes[i];
    }
    _undo.add(InkEdit(before, after));
    _redo.clear();
    _pendingRemoved.clear();
    _pendingAdded.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _hold?.cancel();
    _animation?.cancel();
    activeChanged.dispose();
    super.dispose();
  }
}
