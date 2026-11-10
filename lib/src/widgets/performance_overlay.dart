import 'package:flutter/material.dart';
import '../services/performance_metrics.dart';

class OqbPerformanceOverlay extends StatelessWidget {
  const OqbPerformanceOverlay({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (!PerformanceMetrics.enabled) return child;
    final metrics = PerformanceMetrics.instance;
    return Stack(
      children: [
        child,
        Positioned(
          top: 50,
          right: 4,
          child: IgnorePointer(
            child: ListenableBuilder(
              listenable: metrics,
              builder: (context, _) => Material(
                color: Colors.black87,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    [
                      'UI ${metrics.uiMs.toStringAsFixed(1)}ms · Raster ${metrics.rasterMs.toStringAsFixed(1)}ms',
                      for (final e in metrics.samples.entries.where(
                        (e) => !e.key.endsWith('frame'),
                      ))
                        '${e.key}: ${e.value.last.toStringAsFixed(1)}ms',
                      for (final e in metrics.counters.entries)
                        '${e.key}: ${e.value}',
                    ].join('\n'),
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
