import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/services/performance_metrics.dart';

void main() {
  final startup = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();
  WidgetsBinding.instance.addPostFrameCallback((_) => PerformanceMetrics
      .instance
      .record('Shell startup', startup.elapsedMicroseconds / 1000));
  PaintingBinding.instance.imageCache.maximumSizeBytes = 64 * 1024 * 1024;
  PerformanceMetrics.instance.start();
  runApp(const BetterOqbApp());
}
