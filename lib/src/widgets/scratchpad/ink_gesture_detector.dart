import 'dart:math' as math;
import 'dart:ui';
import 'ink_model.dart';

enum InkShape {
  line,
  circle,
  ellipse,
  rectangle,
  triangle,
  arrow,
  polygon,
  axes,
}

class ShapeCandidate {
  const ShapeCandidate(this.kind, this.points);
  final InkShape kind;
  final List<Offset> points;
}

double pathLength(List<Offset> points) {
  var length = 0.0;
  for (var i = 1; i < points.length; i++) {
    length += (points[i] - points[i - 1]).distance;
  }
  return length;
}

List<Offset> simplifyInk(List<Offset> p, double epsilon) {
  if (p.length < 3) return List.of(p);
  var maxDistance = 0.0;
  var split = 0;
  for (var i = 1; i < p.length - 1; i++) {
    final distance = segmentDistance(p[i], p.first, p.last);
    if (distance > maxDistance) {
      maxDistance = distance;
      split = i;
    }
  }
  if (maxDistance <= epsilon) return [p.first, p.last];
  return [
    ...simplifyInk(p.sublist(0, split + 1), epsilon)..removeLast(),
    ...simplifyInk(p.sublist(split), epsilon),
  ];
}

ShapeCandidate? recognizeShape(List<Offset> p) {
  if (p.length > 512) {
    p = [for (var i = 0; i < 512; i++) p[(i * (p.length - 1) / 511).round()]];
  }
  if (p.length < 3) return null;
  final length = pathLength(p);
  final span = (p.last - p.first).distance;
  if (span >= 24 &&
      length / span < 1.12 &&
      p.every(
        (point) => segmentDistance(point, p.first, p.last) / span < .045,
      )) {
    return ShapeCandidate(InkShape.line, [p.first, p.last]);
  }
  final bounds = InkStroke(const Color(0x00000000), 1, p).bounds;
  if (bounds.shortestSide < 20) return null;
  final closed = span < bounds.longestSide * .18;
  if (closed) {
    final center = bounds.center;
    final rx = bounds.width / 2;
    final ry = bounds.height / 2;
    final residual = p
            .map(
              (v) => ((v.dx - center.dx) * (v.dx - center.dx) / (rx * rx) +
                      (v.dy - center.dy) * (v.dy - center.dy) / (ry * ry) -
                      1)
                  .abs(),
            )
            .reduce((a, b) => a + b) /
        p.length;
    if (residual < .18 &&
        length > 2.5 * bounds.shortestSide &&
        length < 4 * bounds.longestSide) {
      final circle = (rx - ry).abs() / math.max(rx, ry) < .12;
      final r = (rx + ry) / 2;
      return ShapeCandidate(circle ? InkShape.circle : InkShape.ellipse, [
        for (var i = 0; i <= 64; i++)
          center +
              Offset(
                (circle ? r : rx) * math.cos(i * math.pi / 32),
                (circle ? r : ry) * math.sin(i * math.pi / 32),
              ),
      ]);
    }
    final corners = simplifyInk([
      ...p.take(p.length - 1),
      p.first,
    ], bounds.longestSide * .04);
    if (corners.length >= 4 && corners.length <= 9) {
      if (corners.length == 5) {
        final edges = [
          for (var i = 1; i < corners.length; i++) corners[i] - corners[i - 1],
        ];
        var rectangular = true;
        for (var i = 0; i < edges.length; i++) {
          final a = edges[i];
          final b = edges[(i + 1) % edges.length];
          if ((a.dx * b.dx + a.dy * b.dy).abs() / (a.distance * b.distance) >
              .25) {
            rectangular = false;
          }
        }
        if (rectangular) return ShapeCandidate(InkShape.rectangle, corners);
      }
      return ShapeCandidate(
        corners.length == 4 ? InkShape.triangle : InkShape.polygon,
        corners,
      );
    }
  }
  final vertices = simplifyInk(p, bounds.longestSide * .035);
  // Single-stroke arrow: shaft, wing, tip, opposite wing.
  if (vertices.length == 5 &&
      (vertices[1] - vertices[3]).distance < bounds.longestSide * .12 &&
      (vertices[1] - vertices[0]).distance > length * .3 &&
      (vertices[2] - vertices[1]).distance < length * .3 &&
      (vertices[4] - vertices[3]).distance < length * .3) {
    return ShapeCandidate(InkShape.arrow, vertices);
  }
  if (vertices.length == 3) {
    final a = vertices[0] - vertices[1];
    final b = vertices[2] - vertices[1];
    if (a.distance > 30 &&
        b.distance > 30 &&
        (a.dx * b.dx + a.dy * b.dy).abs() / (a.distance * b.distance) < .08) {
      return ShapeCandidate(InkShape.axes, vertices);
    }
  }
  return null;
}

/// Deliberately conservative: fast, dense backtracking AND repeated target hits.
Set<InkStroke> scratchTargets(
  List<Offset> p,
  Duration duration,
  InkSpatialIndex index,
) {
  if (p.length < 9 || duration.inMilliseconds > 1000 || pathLength(p) < 100) {
    return {};
  }
  final bounds = InkStroke(const Color(0x00000000), 1, p).bounds;
  if (pathLength(p) / math.max(bounds.longestSide, 1) < 4) return {};
  // Project onto the gesture's major axis. Small perpendicular connectors
  // between back-and-forth passes must not hide genuine direction reversals.
  final center = bounds.center;
  var xx = 0.0, xy = 0.0, yy = 0.0;
  for (final point in p) {
    final d = point - center;
    xx += d.dx * d.dx;
    xy += d.dx * d.dy;
    yy += d.dy * d.dy;
  }
  final angle = .5 * math.atan2(2 * xy, xx - yy);
  final axis = Offset(math.cos(angle), math.sin(angle));
  double project(Offset v) => v.dx * axis.dx + v.dy * axis.dy;
  var extreme = project(p.first);
  var direction = 0;
  var reversals = 0;
  for (final point in p.skip(1)) {
    final value = project(point);
    if (direction == 0) {
      if ((value - extreme).abs() >= 8) {
        direction = value > extreme ? 1 : -1;
        extreme = value;
      }
    } else if ((value - extreme) * direction >= 0) {
      extreme = value;
    } else if ((value - extreme).abs() >= 8) {
      reversals++;
      direction = -direction;
      extreme = value;
    }
  }
  if (reversals < 4) return {};
  return index.query(bounds.inflate(4)).where((stroke) {
    var crossings = 0;
    var touching = false;
    for (var i = 1; i < p.length; i++) {
      final at = p[i];
      final from = p[i - 1];
      var hit = stroke.points.length == 1 &&
          segmentDistance(stroke.points.first, from, at) < 6;
      for (var j = 1; j < stroke.points.length && !hit; j++) {
        final a = stroke.points[j - 1], b = stroke.points[j];
        hit = segmentDistance(at, a, b) < 6 + stroke.width / 2 ||
            segmentDistance(from, a, b) < 6 + stroke.width / 2 ||
            _segmentsCross(from, at, a, b);
      }
      if (hit && !touching) crossings++;
      // A crossing in the middle of a long sparse sample ends before the
      // next segment, so another pass is counted independently.
      touching = hit &&
          (stroke.points.length == 1
              ? (stroke.points.first - at).distance < 6
              : [
                  for (var j = 1; j < stroke.points.length; j++)
                    segmentDistance(at, stroke.points[j - 1], stroke.points[j])
                ].any((d) => d < 6 + stroke.width / 2));
    }
    return crossings >= 2;
  }).toSet();
}

bool inkPolygonContains(List<Offset> polygon, Offset p) {
  if (polygon.length < 3) return false;
  var inside = false;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final a = polygon[i], b = polygon[j];
    if ((a.dy > p.dy) != (b.dy > p.dy) &&
        p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
      inside = !inside;
    }
  }
  return inside;
}

bool _segmentsCross(Offset a, Offset b, Offset c, Offset d) {
  double cross(Offset x, Offset y) => x.dx * y.dy - x.dy * y.dx;
  final ab = b - a, cd = d - c;
  final denominator = cross(ab, cd);
  if (denominator.abs() < .000001) return false;
  final t = cross(c - a, cd) / denominator;
  final u = cross(c - a, ab) / denominator;
  return t >= 0 && t <= 1 && u >= 0 && u <= 1;
}
