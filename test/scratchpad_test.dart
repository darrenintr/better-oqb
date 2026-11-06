import 'dart:convert';
import 'dart:io';

import 'package:better_oqb/src/services/scratchpad_storage.dart';
import 'package:better_oqb/src/widgets/oqb_scratchpad.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryWorking extends ScratchpadStorage {
  final values = <String, String>{};
  bool failWrites = false;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw const FileSystemException('Simulated disk failure');
    values[key] = value;
  }
  int count(String key) => values[key] == null ? 0 :
      ((jsonDecode(values[key]!) as Map)['strokes'] as List).length;
}

Widget host(MemoryWorking storage, {int question = 11}) => MaterialApp(
  home: Scaffold(body: OqbScratchpad(
    key: ValueKey(question), paperId: 7, questionId: question, storage: storage,
  )),
);

Future<void> draw(WidgetTester tester, {PointerDeviceKind kind = PointerDeviceKind.stylus}) async {
  final origin = tester.getTopLeft(find.byKey(const Key('scratchpad-canvas'))) + const Offset(100, 80);
  final gesture = await tester.startGesture(origin, kind: kind);
  await gesture.moveBy(const Offset(45, 30));
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Pencil writes and touch does not write by default', (tester) async {
    final storage = MemoryWorking();
    await tester.pumpWidget(host(storage));
    await tester.pumpAndSettle();
    await draw(tester, kind: PointerDeviceKind.touch);
    expect(storage.count('7_11'), 0);
    await draw(tester);
    expect(storage.count('7_11'), 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('undo and redo persist strokes', (tester) async {
    final storage = MemoryWorking();
    await tester.pumpWidget(host(storage));
    await tester.pumpAndSettle();
    await draw(tester);
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(storage.count('7_11'), 0);
    await tester.tap(find.byTooltip('Redo'));
    await tester.pumpAndSettle();
    expect(storage.count('7_11'), 1);
  });

  testWidgets('questions are independent and reload previous working', (tester) async {
    final storage = MemoryWorking();
    await tester.pumpWidget(host(storage));
    await tester.pumpAndSettle();
    await draw(tester);
    await tester.pumpWidget(host(storage, question: 12));
    await tester.pumpAndSettle();
    expect(storage.count('7_12'), 0);
    await draw(tester);
    await draw(tester);
    expect(storage.count('7_12'), 2);
    await tester.pumpWidget(host(storage));
    await tester.pumpAndSettle();
    await draw(tester);
    expect(storage.count('7_11'), 2);
    expect(storage.count('7_12'), 2);
  });

  testWidgets('switching question while Pencil is down preserves partial stroke', (tester) async {
    final storage = MemoryWorking();
    await tester.pumpWidget(host(storage));
    await tester.pumpAndSettle();
    final origin = tester.getTopLeft(find.byKey(const Key('scratchpad-canvas'))) + const Offset(100, 80);
    final gesture = await tester.startGesture(origin, kind: PointerDeviceKind.stylus);
    await gesture.moveBy(const Offset(50, 30));
    await tester.pumpWidget(host(storage, question: 12));
    await tester.pumpAndSettle();
    await gesture.up();
    expect(storage.count('7_11'), 1);
    expect(storage.count('7_12'), 0);
  });

  testWidgets('failed save is visible and can be retried', (tester) async {
    final storage = MemoryWorking()..failWrites = true;
    await tester.pumpWidget(host(storage));
    await tester.pumpAndSettle();
    await draw(tester);
    expect(find.text('Retry'), findsOneWidget);
    storage.failWrites = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(storage.count('7_11'), 1);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('corrupted stored working is not silently overwritten', (tester) async {
    final storage = MemoryWorking()..values['7_11'] = 'invalid-json';
    await tester.pumpWidget(host(storage));
    await tester.pumpAndSettle();
    expect(find.text('Could not load working. Existing data was not changed.'), findsOneWidget);
    expect(storage.values['7_11'], 'invalid-json');
  });

  test('file writes are serialized and can be reloaded by a new store', () async {
    final root = await Directory.systemTemp.createTemp('oqb-working-test-');
    addTearDown(() => root.delete(recursive: true));
    final storage = FileScratchpadStorage(directory: () async => root);
    await Future.wait([storage.write('7_11', 'first'), storage.write('7_11', 'second')]);
    final reopened = FileScratchpadStorage(directory: () async => root);
    expect(await reopened.read('7_11'), 'second');
    expect(await reopened.read('7_12'), isNull);
  });
}
