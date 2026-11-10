import 'dart:ui';

/// Immutable completed ink. Coordinates are logical paper coordinates.
class InkStroke {
  InkStroke(
    this.color,
    this.width,
    Iterable<Offset> points, {
    Iterable<double>? pressures,
    this.smooth = true,
  })  : points = List.unmodifiable(points),
        pressures = List.unmodifiable(pressures ?? const <double>[]);
  final Color color;
  final double width;
  final List<Offset> points;
  final List<double> pressures;
  final bool smooth;
  late final Rect bounds = points.isEmpty
      ? Rect.zero
      : Rect.fromLTRB(
          points.map((p) => p.dx).reduce((a, b) => a < b ? a : b),
          points.map((p) => p.dy).reduce((a, b) => a < b ? a : b),
          points.map((p) => p.dx).reduce((a, b) => a > b ? a : b),
          points.map((p) => p.dy).reduce((a, b) => a > b ? a : b),
        ).inflate(width / 2);
  Map<String, Object> toJson() => _record;
  late final Map<String, Object> _record = Map.unmodifiable({
    'color': color.toARGB32(),
    'width': width,
    'points': [
      for (final p in points) [p.dx, p.dy],
    ],
    if (pressures.isNotEmpty) 'pressures': pressures,
    'smooth': smooth,
  });
  factory InkStroke.parse(dynamic raw) {
    if (raw is! Map ||
        raw['points'] is! List ||
        raw['color'] is! num ||
        raw['width'] is! num) {
      throw const FormatException('Invalid stroke');
    }
    final points = <Offset>[];
    for (final value in raw['points'] as List) {
      if (value is! List ||
          value.length != 2 ||
          value[0] is! num ||
          value[1] is! num) {
        throw const FormatException('Invalid point');
      }
      final p = Offset(
        (value[0] as num).toDouble(),
        (value[1] as num).toDouble(),
      );
      if (!p.dx.isFinite || !p.dy.isFinite) {
        throw const FormatException('Invalid coordinate');
      }
      points.add(p);
    }
    final width = (raw['width'] as num).toDouble();
    if (!width.isFinite || width <= 0) {
      throw const FormatException('Invalid width');
    }
    final pressure = raw['pressures'];
    if (pressure != null &&
        (pressure is! List ||
            pressure.length != points.length ||
            pressure.any((p) => p is! num || !p.isFinite || p <= 0 || p > 2))) {
      throw const FormatException('Invalid pressure');
    }
    return InkStroke(
      Color((raw['color'] as num).toInt()),
      width,
      points,
      pressures: pressure == null
          ? null
          : (pressure as List).map((p) => (p as num).toDouble()),
      smooth: raw['smooth'] != false,
    );
  }
}

double segmentDistance(Offset p, Offset a, Offset b) {
  final d = b - a;
  final length = d.distanceSquared;
  final t =
      length == 0 ? 0.0 : ((p - a).dx * d.dx + (p - a).dy * d.dy) / length;
  return (p - (a + d * t.clamp(0.0, 1.0))).distance;
}

/// Bounded spatial lookup. Index entries hold stroke identities, never point copies.
class InkSpatialIndex {
  InkSpatialIndex({this.cellSize = 64});
  final double cellSize;
  final _cells = <(int, int), Set<InkStroke>>{};
  Iterable<(int, int)> _keys(Rect bounds) sync* {
    for (var x = (bounds.left / cellSize).floor();
        x <= (bounds.right / cellSize).floor();
        x++) {
      for (var y = (bounds.top / cellSize).floor();
          y <= (bounds.bottom / cellSize).floor();
          y++) {
        yield (x, y);
      }
    }
  }

  void add(InkStroke stroke) {
    for (final key in _keys(stroke.bounds)) {
      (_cells[key] ??= {}).add(stroke);
    }
  }

  void remove(InkStroke stroke) {
    for (final key in _keys(stroke.bounds)) {
      final cell = _cells[key];
      cell?.remove(stroke);
      if (cell?.isEmpty ?? false) _cells.remove(key);
    }
  }

  void clear() => _cells.clear();
  Set<InkStroke> query(Rect area) => {
        for (final key in _keys(area)) ...?_cells[key],
      }.where((s) => s.bounds.overlaps(area)).toSet();
}
