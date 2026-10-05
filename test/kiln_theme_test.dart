import 'package:better_oqb/src/controllers/catalog_controller.dart';
import 'package:better_oqb/src/controllers/study_controller.dart';
import 'package:better_oqb/src/models/oqb_meta.dart';
import 'package:better_oqb/src/models/oqb_review.dart';
import 'package:better_oqb/src/models/oqb_trial.dart';
import 'package:better_oqb/src/screens/catalog_view.dart';
import 'package:better_oqb/src/screens/study_view.dart';
import 'package:better_oqb/src/services/oqb_api_requests.dart';
import 'package:better_oqb/src/services/oqb_repository.dart';
import 'package:better_oqb/src/theme/kiln_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

Widget kilnHost(Brightness brightness, Widget child) => MaterialApp(
      theme: buildKilnTheme(brightness),
      home: Scaffold(body: child),
    );

dynamic catalogResponses(OqbApiRequest request) {
  switch (request.command) {
    case 'getUsablePackages':
      return envelope([
        {
          'id': 16,
          'subject_code': 'econ',
          'publisher_code': 'HKEAA',
          'title_en': 'HKEAA Economics',
          'stat': {
            'count_topic': {'econ_5': 60},
            'count_topic_difficulty': {
              'econ_5': {'1': 16, '2': 35, '3': 9},
            },
          },
        },
      ]);
    case 'loadPapers':
      if (request.fields['criteria[to_submit]'] == '1') {
        return envelope([
          {'id': 1, 'subject_code': 'econ', 'title': 'Big practice', 'num_of_questions': 40},
        ]);
      }
      return envelope([]);
    case 'loadSubmittedPapers':
      return envelope([]);
  }
  return envelope(null);
}

void main() {
  test('Kiln tokens resolve per brightness', () {
    final light = buildKilnTheme(Brightness.light);
    final dark = buildKilnTheme(Brightness.dark);
    expect(light.extension<KilnColors>()!.bg, const Color(0xFFFAF9F5));
    expect(dark.extension<KilnColors>()!.bg, const Color(0xFF1F1E1D));
    expect(light.colorScheme.primary, KilnColors.light.ink);
    expect(dark.colorScheme.onPrimary, KilnColors.dark.onInk);
    expect(light.extension<KilnText>()!.prose.fontFamily, KilnFonts.serif);
    expect(light.textTheme.bodyMedium!.fontFamily, KilnFonts.sans);
  });

  for (final brightness in Brightness.values) {
    for (final size in const [Size(360, 740), Size(1600, 1000)]) {
      final label = '${brightness.name} ${size.width.toInt()}px';

      testWidgets('study and review render under Kiln $label', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final transport = FakeTransport((_) => envelope(true));

        final study = StudyController(OqbRepository(transport))
          ..attach(OqbTrialSession.fromResult(startTrialResult(count: 12)));
        addTearDown(study.dispose);
        await tester.pumpWidget(kilnHost(
          brightness,
          StudyView(
            controller: study,
            meta: OqbMeta.empty,
            onExit: () {},
            onOpenOriginal: () {},
            onSubmit: () async {},
          ),
        ));
        await tester.pumpAndSettle();
        expect(find.text('Question 1 of 12'), findsOneWidget);
        expect(find.text('Submit'), findsOneWidget);
        expect(tester.takeException(), isNull);

        final session = OqbTrialSession.fromResult(
          startTrialResult(review: true, count: 4, userInputs: ['[2]', '[0]', '[2]', null]),
          isReview: true,
        );
        final review = StudyController(OqbRepository(transport))..attach(session);
        addTearDown(review.dispose);
        await tester.pumpWidget(kilnHost(
          brightness,
          StudyView(
            controller: review,
            meta: OqbMeta.empty,
            review: OqbReview(session: session),
            onExit: () {},
            onOpenOriginal: () {},
          ),
        ));
        await tester.pumpAndSettle();
        expect(find.text('Model answer'), findsOneWidget);
        expect(find.byIcon(Icons.check_circle), findsWidgets);
        expect(tester.takeException(), isNull);
      });

      testWidgets('catalog renders under Kiln $label', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final catalog = CatalogController(OqbRepository(FakeTransport(catalogResponses)));
        addTearDown(catalog.dispose);
        await catalog.refresh();

        await tester.pumpWidget(kilnHost(
          brightness,
          CatalogView(
            controller: catalog,
            onStartPaper: (_) {},
            onReviewPaper: (_) {},
            onOpenOriginal: () {},
            onCreatePaper: () {},
          ),
        ));
        await tester.pumpAndSettle();
        expect(find.text('Big practice'), findsOneWidget);
        expect(find.text('New paper'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final size in const [Size(360, 740), Size(1180, 820)]) {
    testWidgets('continue cards show progress only when known at ${size.width.toInt()}px', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final transport = FakeTransport((request) {
        if (request.command == 'loadPapers' && request.fields['criteria[to_submit]'] == '1') {
          return envelope([
            {'id': 1, 'subject_code': 'econ', 'title': 'Big practice', 'num_of_questions': 40},
            {'id': 2, 'subject_code': 'econ', 'title': 'Fresh paper', 'num_of_questions': 10},
          ]);
        }
        return catalogResponses(request);
      });
      final catalog = CatalogController(OqbRepository(transport));
      addTearDown(catalog.dispose);
      await catalog.refresh();
      final started = <int>[];

      await tester.pumpWidget(kilnHost(
        Brightness.light,
        CatalogView(
          controller: catalog,
          progress: const {1: PaperProgress(answered: 16, total: 40, questionNumber: 17)},
          onStartPaper: (paper) => started.add(paper.id),
          onReviewPaper: (_) {},
          onOpenOriginal: () {},
          onCreatePaper: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('16 of 40 answered · question 17'), findsOneWidget);
      expect(find.text('Resume'), findsOneWidget);
      expect(find.text('Start or resume'), findsOneWidget, reason: 'no progress known for paper 2');
      final bar = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
      expect(bar.value, closeTo(0.4, 1e-9));

      await tester.tap(find.text('Fresh paper'));
      expect(started, [2]);
      expect(tester.takeException(), isNull);
    });
  }
}
