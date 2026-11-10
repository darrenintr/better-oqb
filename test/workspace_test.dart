import 'package:better_oqb/src/controllers/study_controller.dart';
import 'package:better_oqb/src/models/oqb_meta.dart';
import 'package:better_oqb/src/models/oqb_trial.dart';
import 'package:better_oqb/src/screens/study_view.dart';
import 'package:better_oqb/src/services/oqb_repository.dart';
import 'package:better_oqb/src/widgets/oqb_scratchpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'support/fakes.dart';
import 'scratchpad_test.dart' show MemoryWorking;

void main() {
  for (final size in [
    const Size(390, 844),
    const Size(820, 1180),
    const Size(1180, 820),
    const Size(1600, 1000)
  ]) {
    testWidgets(
        'working layout ${size.width}x${size.height} supports closing and resizing',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller =
          StudyController(OqbRepository(FakeTransport((_) => envelope(true))));
      controller.attach(OqbTrialSession.fromResult(startTrialResult()));
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: StudyView(
        controller: controller,
        meta: OqbMeta.empty,
        onExit: () {},
        onOpenOriginal: () {},
        scratchpadStorage: MemoryWorking(),
      ))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('toggle-working')));
      await tester.pumpAndSettle();
      expect(find.byType(OqbScratchpad), findsOneWidget);
      final divider = find.byKey(const Key('workspace-divider'));
      if (size.width > size.height) {
        expect(divider, findsOneWidget);
        final before = tester.getSize(find.byType(OqbScratchpad)).width;
        await tester.drag(divider, const Offset(90, 0));
        await tester.pumpAndSettle();
        expect(
            tester.getSize(find.byType(OqbScratchpad)).width, lessThan(before));
      } else {
        expect(divider, findsNothing);
        expect(find.text('Question 1 of 3'), findsNothing);
      }
      await tester.tap(find.byKey(const Key('toggle-working')));
      await tester.pumpAndSettle();
      expect(find.byType(OqbScratchpad), findsNothing);
      expect(find.text('Question 1 of 3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('answer saves retain the HTML widget for the question stem',
      (tester) async {
    final controller =
        StudyController(OqbRepository(FakeTransport((_) => envelope(true))));
    controller.attach(OqbTrialSession.fromResult(startTrialResult()));
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StudyView(
      controller: controller,
      meta: OqbMeta.empty,
      onExit: () {},
      onOpenOriginal: () {},
    ))));
    await tester.pumpAndSettle();
    final before = tester.widgetList<HtmlWidget>(find.byType(HtmlWidget)).first;
    controller.selectChoice(1);
    await tester.pump();
    final after = tester.widgetList<HtmlWidget>(find.byType(HtmlWidget)).first;
    expect(identical(before, after), isTrue);
    await tester.pump(const Duration(seconds: 1));
  });
}
