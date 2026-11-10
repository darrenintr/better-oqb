import 'package:flutter/material.dart';
import 'ink_controller.dart';
import 'ink_model.dart';
import '../../services/performance_metrics.dart';

enum InkPaper { plain, grid, ruled }

Path inkPath(InkStroke stroke) {
  final p = stroke.points;
  final path = Path();
  if (p.isEmpty) return path;
  path.moveTo(p.first.dx, p.first.dy);
  if (!stroke.smooth || p.length < 3) {
    for (final v in p.skip(1)) {
      path.lineTo(v.dx, v.dy);
    }
  } else {
    for (var i = 1; i < p.length - 1; i++) {
      final mid = (p[i] + p[i + 1]) / 2;
      path.quadraticBezierTo(p[i].dx, p[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(p.last.dx, p.last.dy);
  }
  return path;
}

void paintStroke(Canvas canvas, InkStroke s) {
  if (s.points.isEmpty) return;
  final paint = Paint()
    ..color = s.color
    ..strokeWidth = s.width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;
  if (s.points.length == 1) {
    canvas.drawCircle(s.points.first, s.width / 2, Paint()..color = s.color);
  } else if (s.pressures.length == s.points.length) {
    // Short quadratic sections preserve pressure without rebuilding a filled outline.
    for (var i = 1; i < s.points.length; i++) {
      paint.strokeWidth = s.width * (s.pressures[i - 1] + s.pressures[i]) / 2;
      final a =
          i == 1 ? s.points.first : (s.points[i - 2] + s.points[i - 1]) / 2;
      final b = i == s.points.length - 1
          ? s.points.last
          : (s.points[i - 1] + s.points[i]) / 2;
      canvas.drawPath(
        Path()
          ..moveTo(a.dx, a.dy)
          ..quadraticBezierTo(
            s.points[i - 1].dx,
            s.points[i - 1].dy,
            b.dx,
            b.dy,
          ),
        paint,
      );
    }
  } else {
    canvas.drawPath(inkPath(s), paint);
  }
}

class PaperPainter extends CustomPainter {
  PaperPainter(this.paper, this.scale);
  final InkPaper paper;
  final double scale;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(Colors.white, BlendMode.src);
    canvas.scale(scale);
    final guide = Paint()
      ..color = const Color(0xFFDCE5E7)
      ..strokeWidth = 1;
    if (paper == InkPaper.grid) {
      for (var x = 32.0; x < 800; x += 32) {
        canvas.drawLine(Offset(x, 0), Offset(x, 1800), guide);
      }
    }
    if (paper != InkPaper.plain) {
      for (var y = 32.0; y < 1800; y += 32) {
        canvas.drawLine(Offset(0, y), Offset(800, y), guide);
      }
    }
  }

  @override
  bool shouldRepaint(PaperPainter old) =>
      old.paper != paper || old.scale != scale;
}

/// Retains a display list across active-pointer frames. Only completed edits rebuild it.
class CommittedInkPainter extends CustomPainter {
  CommittedInkPainter(this.controller, this.scale) : super(repaint: controller);
  final InkController controller;
  final double scale;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(scale);
    for (final s in controller.strokes) {
      paintStroke(canvas, s);
    }
  }

  @override
  bool shouldRepaint(CommittedInkPainter old) =>
      old.controller != controller || old.scale != scale;
}

class ActiveInkPainter extends CustomPainter {
  ActiveInkPainter(this.controller, this.scale)
      : super(repaint: controller.activeChanged);
  final InkController controller;
  final double scale;
  @override
  void paint(Canvas canvas, Size size) {
    PerformanceMetrics.instance.end('Ink event to paint');
    canvas.scale(scale);
    paintStroke(
      canvas,
      InkStroke(
        controller.color,
        controller.width,
        controller.preview,
        pressures: controller.candidate == null ? controller.pressures : null,
        smooth: controller.candidate == null,
      ),
    );
  }

  @override
  bool shouldRepaint(ActiveInkPainter old) =>
      old.controller != controller || old.scale != scale;
}
