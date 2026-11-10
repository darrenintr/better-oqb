import 'dart:convert';
import 'dart:math' as math;
import 'package:better_oqb/src/widgets/scratchpad/ink_controller.dart';
import 'package:better_oqb/src/widgets/scratchpad/ink_model.dart';
import 'package:better_oqb/src/widgets/scratchpad/ink_gesture_detector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

InkStroke line(Offset a, Offset b) => InkStroke(Colors.black, 3, [a, b]);
void main() {
  test('line fit rejects curved lines and backtracking', () {
    expect(
      recognizeShape([
        for (var i = 0; i <= 20; i++) Offset(i * 5, math.sin(i / 20 * math.pi)),
      ])?.kind,
      InkShape.line,
    );
    expect(
      recognizeShape([
        for (var i = 0; i <= 20; i++)
          Offset(i * 5, math.sin(i / 20 * math.pi) * 30),
      ])?.kind,
      isNot(InkShape.line),
    );
    expect(
      recognizeShape([
        for (var i = 0; i <= 20; i++) Offset(i * 5, i.isEven ? 0 : 20),
      ])?.kind,
      isNot(InkShape.line),
    );
  });
  test('recognizes closed shapes', () {
    expect(
      recognizeShape([
        for (var i = 0; i <= 64; i++)
          Offset(
            100 + 50 * math.cos(i * math.pi / 32),
            100 + 50 * math.sin(i * math.pi / 32),
          ),
      ])?.kind,
      InkShape.circle,
    );
    expect(
      recognizeShape(const [
        Offset(0, 0),
        Offset(100, 0),
        Offset(100, 100),
        Offset(0, 100),
        Offset(0, 0),
      ])?.kind,
      InkShape.rectangle,
    );
    expect(
      recognizeShape(const [
        Offset(0, 100),
        Offset(50, 0),
        Offset(100, 100),
        Offset(0, 100),
      ])?.kind,
      InkShape.triangle,
    );
  });
  testWidgets('hold snaps while down and undo restores original points', (
    tester,
  ) async {
    final ink = InkController();
    addTearDown(ink.dispose);
    ink.begin(Offset.zero);
    ink.move(const Offset(50, 1));
    ink.move(const Offset(100, 0));
    await tester.pump(const Duration(milliseconds: 449));
    expect(ink.candidate, isNull);
    await tester.pump(const Duration(milliseconds: 150));
    expect(ink.candidate?.kind, InkShape.line);
    ink.finish();
    expect(ink.strokes.single.points.length, 2);
    ink.undo();
    expect(ink.strokes.single.points.length, 3);
    ink.undo();
    expect(ink.strokes, isEmpty);
    ink.redo();
    ink.redo();
    expect(ink.strokes.single.points.length, 2);
  });
  testWidgets('motion resets hold and cancel never commits', (tester) async {
    final ink = InkController();
    addTearDown(ink.dispose);
    ink.begin(Offset.zero);
    ink.move(const Offset(50, 1));
    ink.move(const Offset(100, 0));
    await tester.pump(const Duration(milliseconds: 300));
    ink.move(const Offset(110, 0));
    await tester.pump(const Duration(milliseconds: 300));
    expect(ink.candidate, isNull);
    ink.cancelActive();
    await tester.pump(const Duration(seconds: 1));
    expect(ink.strokes, isEmpty);
    expect(ink.candidate, isNull);
  });
  test(
    'scratch requires repeated existing-ink crossings and a short duration',
    () {
      final index = InkSpatialIndex();
      final target = line(const Offset(50, 0), const Offset(50, 100));
      index.add(target);
      final scratch = <Offset>[];
      for (var row = 0; row < 7; row++) {
        for (var i = 0; i <= 10; i++) {
          scratch.add(Offset(row.isEven ? i * 10 : 100 - i * 10, 20 + row * 4));
        }
      }
      expect(
        scratchTargets(scratch, const Duration(milliseconds: 600), index),
        contains(target),
      );
      expect(
        scratchTargets(scratch, const Duration(seconds: 2), index),
        isEmpty,
      );
      expect(
        scratchTargets(
          scratch,
          const Duration(milliseconds: 600),
          InkSpatialIndex(),
        ),
        isEmpty,
      );
      expect(
        scratchTargets(
          [
            for (var i = 0; i <= 50; i++)
              Offset(i * 2, 50 + math.sin(i / 4) * 20),
          ],
          const Duration(milliseconds: 600),
          index,
        ),
        isEmpty,
      );
    },
  );
  test('eraser drag is one reversible edit and handles sparse segments', () {
    final ink = InkController();
    addTearDown(ink.dispose);
    final a = line(const Offset(0, 50), const Offset(100, 50));
    final b = line(const Offset(0, 80), const Offset(100, 80));
    ink.load([a, b]);
    ink.startErase();
    ink.erase(const Offset(50, 50), 10, segment: true);
    ink.erase(const Offset(50, 80), 10, segment: true);
    ink.endErase();
    expect(ink.strokes.length, 4);
    expect(ink.historySize, 1);
    expect(
      ink.strokes.every((s) => !s.bounds.contains(const Offset(50, 50))),
      isTrue,
    );
    ink.undo();
    expect(ink.strokes, [a, b]);
    ink.redo();
    expect(ink.strokes.length, 4);
  });
  test('spatial index excludes distant strokes, follows undo and clear', () {
    final ink = InkController();
    addTearDown(ink.dispose);
    final s = line(Offset.zero, const Offset(20, 20));
    ink.replace({}, [s]);
    expect(ink.index.query(const Rect.fromLTWH(500, 500, 20, 20)), isEmpty);
    ink.undo();
    expect(ink.index.query(const Rect.fromLTWH(0, 0, 30, 30)), isEmpty);
    ink.redo();
    expect(ink.index.query(const Rect.fromLTWH(0, 0, 30, 30)), contains(s));
  });
  test(
    'v1 ink loads and v2 pressure survives roundtrip; invalid points fail',
    () {
      final old = InkStroke.parse({
        'color': 0xff000000,
        'width': 3,
        'points': [
          [1, 2],
          [3, 4],
        ],
      });
      expect(old.pressures, isEmpty);
      final s = InkStroke(Colors.black, 3, old.points, pressures: [.8, 1.2]);
      expect(InkStroke.parse(jsonDecode(jsonEncode(s.toJson()))).pressures, [
        .8,
        1.2,
      ]);
      expect(
        () => InkStroke.parse({
          'color': 0,
          'width': 3,
          'points': [
            [double.nan, 0],
          ],
        }),
        throwsFormatException,
      );
    },
  );
  for (final count in [100, 500, 1000]) {
    test(
      'benchmark $count strokes: active input leaves completed history untouched',
      () {
        final ink = InkController();
        addTearDown(ink.dispose);
        ink.load([
          for (var i = 0; i < count; i++)
            InkStroke(Colors.black, 3, [
              for (var j = 0; j < 80; j++)
                Offset(j * 8, i.toDouble() + math.sin(j / 8))
            ]),
        ]);
        var commits = 0;
        ink.addListener(() => commits++);
        final timer = Stopwatch()..start();
        ink.begin(Offset.zero);
        for (var i = 0; i < 1000; i++) {
          ink.move(Offset(i % 700, i / 2));
        }
        timer.stop();
        expect(commits, 0);
        expect(ink.historySize, 0);
        expect(ink.strokes.length, count);
        final encode = Stopwatch()..start();
        final bytes = jsonEncode([for (final s in ink.strokes) s.toJson()]);
        encode.stop();
        // Informational host timings; frame budgets need profile-mode device runs.
        debugPrint(
          'INK_BENCH strokes=$count input_us=${timer.elapsedMicroseconds} encode_us=${encode.elapsedMicroseconds} bytes=${bytes.length}',
        );
        ink.cancelActive();
      },
    );
  }
}
