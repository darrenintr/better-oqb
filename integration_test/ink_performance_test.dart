import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:better_oqb/src/services/scratchpad_storage.dart';
import 'package:better_oqb/src/widgets/oqb_scratchpad.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

class BenchmarkStorage implements ScratchpadStorage {
  String? text;
  int saveMicros = 0;
  @override
  Future<String?> read(String key) async => text;
  @override
  Future<void> write(String key, String value) async {
    final watch = Stopwatch()..start();
    final file = File('${Directory.systemTemp.path}/oqb_ink_benchmark.json');
    await file.writeAsString(value, flush: true);
    text = value;
    saveMicros = watch.elapsedMicroseconds;
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final count in [100, 500, 1000]) {
    testWidgets('profile ink over $count completed strokes', (tester) async {
      final store = BenchmarkStorage()
        ..text = jsonEncode({
          'version': 2,
          'strokes': [
            for (var i = 0; i < count; i++)
              {
                'color': 0xff263341,
                'width': 3.5,
                'points': [
                  for (var j = 0; j < 80; j++)
                    [j * 8, (i % 150) * 10 + math.sin(j / 8) * 4]
                ]
              },
          ]
        });
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: OqbScratchpad(
        paperId: 1,
        questionId: count,
        storage: store,
      ))));
      await tester.pumpAndSettle();
      final at = tester.getTopLeft(find.byKey(const Key('scratchpad-canvas'))) +
          const Offset(30, 40);
      await binding.watchPerformance(() async {
        final gesture =
            await tester.startGesture(at, kind: PointerDeviceKind.stylus);
        for (var i = 1; i <= 90; i++) {
          await gesture.moveTo(at + Offset(i * 2, math.sin(i / 8) * 10));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await gesture.up();
        await tester.pumpAndSettle();
      }, reportKey: 'ink_$count');
      await Future<void>.delayed(const Duration(seconds: 1));
      await tester.pump();
      binding.reportData ??= {};
      binding.reportData!['storage_$count'] = {
        'rss_bytes': ProcessInfo.currentRss,
        'disk_save_us': store.saveMicros,
        'json_bytes': store.text?.length
      };
      expect(jsonDecode(store.text!)['strokes'].length, count + 1);
    });
  }
}
