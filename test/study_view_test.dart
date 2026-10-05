import 'package:better_oqb/src/controllers/catalog_controller.dart';
import 'package:better_oqb/src/controllers/study_controller.dart';
import 'package:better_oqb/src/models/oqb_api_data.dart';
import 'package:better_oqb/src/models/oqb_meta.dart';
import 'package:better_oqb/src/models/oqb_review.dart';
import 'package:better_oqb/src/models/oqb_trial.dart';
import 'package:better_oqb/src/screens/catalog_view.dart';
import 'package:better_oqb/src/screens/study_view.dart';
import 'package:better_oqb/src/services/oqb_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const sizes = <String, Size>{
  'phone': Size(360, 740),
  'small phone': Size(320, 568),
  'ipad portrait': Size(820, 1180),
  'ipad landscape': Size(1180, 820),
  'desktop': Size(1600, 1000),
};

Future<void> setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  late FakeTransport transport;

  setUp(() {
    transport = FakeTransport((request) {
      if (request.command == 'startTrial') return envelope(startTrialResult(count: 40));
      return {'success': true, 'result': true};
    });
  });

  StudyController attached({int count = 40}) {
    final controller = StudyController(
      OqbRepository(transport),
      saveDelay: const Duration(milliseconds: 100),
    );
    controller.attach(OqbTrialSession.fromResult(startTrialResult(count: count)));
    return controller;
  }

  for (final entry in sizes.entries) {
    testWidgets('study view lays out without overflow on ${entry.key}', (tester) async {
      await setSize(tester, entry.value);
      final controller = attached();
      addTearDown(controller.dispose);

      await tester.pumpWidget(host(StudyView(
        controller: controller,
        meta: OqbMeta.empty,
        onExit: () {},
        onOpenOriginal: () {},
        onSubmit: () async {},
      )));
      await tester.pumpAndSettle();

      expect(find.text('Question 1 of 40'), findsOneWidget);
      expect(find.text('A'), findsWidgets);
      // Navigation panel only on wide layouts; a sheet button otherwise.
      final wide = entry.value.width >= kStudyPanelBreakpoint;
      expect(find.byIcon(Icons.grid_view_rounded), wide ? findsNothing : findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('answering and navigating through the UI uses API state', (tester) async {
    await setSize(tester, const Size(1600, 1000));
    final controller = attached(count: 5);
    addTearDown(controller.dispose);

    await tester.pumpWidget(host(StudyView(
      controller: controller,
      meta: OqbMeta.empty,
      onExit: () {},
      onOpenOriginal: () {},
      onSubmit: () async {},
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('C0', findRichText: true));
    await tester.pump();
    expect(controller.answerFor(controller.current!).single, 2);
    expect(find.text('Unsaved'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(transport.commands('saveTrial'), hasLength(1));
    expect(find.text('Saved'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Question 2 of 5'), findsOneWidget);

    // Jump with the navigator panel.
    await tester.tap(find.text('5').first);
    await tester.pumpAndSettle();
    expect(controller.questionNumber, 5);
    expect(find.text('Question 5 of 5'), findsOneWidget);
  });

  testWidgets('image-only questions do not show OQB file names', (tester) async {
    await setSize(tester, const Size(1180, 820));
    final result = startTrialResult(count: 1);
    final question = (result['trial_question'] as List).single['question'] as Map;
    question['content'] = 'q_16_0.png';
    question['url'] = 'https://oqb.example/q_16_0.png';
    question['choices'] = [
      for (var i = 1; i <= 4; i++) {'content': 'q_16_$i.png', 'url': 'https://oqb.example/q_16_$i.png'},
    ];
    final controller = StudyController(OqbRepository(transport))
      ..attach(OqbTrialSession.fromResult(result));
    addTearDown(controller.dispose);

    await tester.pumpWidget(host(StudyView(
      controller: controller,
      meta: OqbMeta.empty,
      onExit: () {},
      onOpenOriginal: () {},
      onSubmit: () async {},
    )));
    await tester.pumpAndSettle();

    expect(find.textContaining('.png', findRichText: true), findsNothing);
    expect(find.text('Show answer'), findsNothing, reason: 'test paper');
    expect(find.text('A'), findsOneWidget);
    expect(find.text('This question has no text content.'), findsNothing);
  });

  testWidgets('exercise papers can show the answer', (tester) async {
    await setSize(tester, const Size(1180, 820));
    transport.handler = (request) => exerciseSaveResult(count: 2);
    final controller = StudyController(OqbRepository(transport), saveDelay: Duration.zero)
      ..attach(OqbTrialSession.fromResult(startTrialResult(count: 2, modeReview: 'exercise')));
    addTearDown(controller.dispose);

    await tester.pumpWidget(host(StudyView(
      controller: controller,
      meta: OqbMeta.empty,
      onExit: () {},
      onOpenOriginal: () {},
      onSubmit: () async {},
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('A0', findRichText: true));
    await tester.tap(find.text('Show answer'));
    await tester.pumpAndSettle();

    expect(transport.commands('saveTrial').last.fields['trial_question[0][status]'], 'submitted');
    expect(find.text('Incorrect'), findsOneWidget);
    expect(find.text('Show answer'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Choice C.*correct answer')), findsOneWidget);
  });

  testWidgets('submit requires confirmation', (tester) async {
    await setSize(tester, const Size(1180, 820));
    final controller = attached(count: 3);
    addTearDown(controller.dispose);
    var submitted = 0;

    await tester.pumpWidget(host(StudyView(
      controller: controller,
      meta: OqbMeta.empty,
      onExit: () {},
      onOpenOriginal: () {},
      onSubmit: () async => submitted++,
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(find.text('Submit this paper?'), findsOneWidget);
    expect(find.textContaining('3 questions unanswered'), findsOneWidget);

    await tester.tap(find.text('Keep working'));
    await tester.pumpAndSettle();
    expect(submitted, 0);

    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit paper'));
    await tester.pumpAndSettle();
    expect(submitted, 1);
  });

  testWidgets('phone navigator sheet jumps to a question', (tester) async {
    await setSize(tester, const Size(360, 740));
    final controller = attached(count: 30);
    addTearDown(controller.dispose);

    await tester.pumpWidget(host(StudyView(
      controller: controller,
      meta: OqbMeta.empty,
      onExit: () {},
      onOpenOriginal: () {},
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.grid_view_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('12'));
    await tester.pumpAndSettle();
    expect(controller.questionNumber, 12);
    expect(find.text('Question 12 of 30'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final entry in {'phone': const Size(360, 740), 'desktop': const Size(1600, 1000)}.entries) {
    testWidgets('review view shows correctness and model answers on ${entry.key}', (tester) async {
      await setSize(tester, entry.value);
      final session = OqbTrialSession.fromResult(
        startTrialResult(review: true, count: 4, userInputs: ['[2]', '[0]', '[2]', null]),
        isReview: true,
      );
      final review = OqbReview(session: session);
      final controller = StudyController(OqbRepository(transport))..attach(session);
      addTearDown(controller.dispose);

      await tester.pumpWidget(host(StudyView(
        controller: controller,
        meta: OqbMeta.empty,
        review: review,
        onExit: () {},
        onOpenOriginal: () {},
      )));
      await tester.pumpAndSettle();

      expect(find.text('Correct'), findsWidgets);
      expect(find.text('Model answer'), findsOneWidget);
      expect(find.text('Because C.', findRichText: true), findsOneWidget);
      expect(find.text('Submit'), findsNothing);
      expect(find.byIcon(Icons.check_circle), findsWidgets);

      await tester.tap(find.text('A0', findRichText: true));
      await tester.pump();
      expect(controller.answerFor(controller.current!).single, 2, reason: 'read-only');
      expect(transport.requests, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  for (final entry in {'phone': const Size(360, 740), 'ipad': const Size(1180, 820)}.entries) {
    testWidgets('catalog shows packages, papers and submitted attempts on ${entry.key}', (tester) async {
      await setSize(tester, entry.value);
      transport.handler = (request) {
        switch (request.command) {
          case 'getMeta':
            return {
              'subject': [
                {'code': 'econ', 'title_en': 'Economics', 'title_zh': '經濟'},
              ],
            };
          case 'getUsablePackages':
            return envelope([
              {
                'id': 16,
                'subject_code': 'econ',
                'publisher_code': 'HKEAA',
                'title_zh': '考評局經濟歷屆公開試試題',
                'title_en': 'HKEAA Economics',
                'access_type': ['school'],
                'stat': {
                  'count_topic': {'econ_1': 76, 'econ_5': 60},
                  'count_topic_difficulty': {
                    'econ_5': {'1': 16, '2': 35, '3': 9},
                  },
                },
              },
            ]);
          case 'loadPapers':
            if (request.fields['criteria[to_submit]'] == '1') {
              return envelope([
                {'id': 2658825, 'subject_code': 'econ', 'title': 'Big practice', 'num_of_questions': 552},
              ]);
            }
            return envelope([]);
          case 'loadSubmittedPapers':
            return envelope([
              {
                'paper_id': 2661977,
                'trial_id': 1,
                'subject_code': 'econ',
                'title': 'Last week',
                'submitted': 1,
                'marked': 1,
                'score': 3,
                'score_full': 4,
                'can_review': true,
              },
            ]);
        }
        return envelope(null);
      };
      final catalog = CatalogController(OqbRepository(transport));
      addTearDown(catalog.dispose);
      await catalog.refresh();
      expect(transport.commands('loadSubmittedPapers').single.fields['criteria[subject_code]'], 'econ');

      final started = <int>[];
      final reviewed = <int>[];
      await tester.pumpWidget(host(CatalogView(
        controller: catalog,
        onStartPaper: (paper) => started.add(paper.id),
        onReviewPaper: (paper) => reviewed.add(paper.id),
        onOpenOriginal: () {},
        onCreatePaper: () {},
      )));
      await tester.pumpAndSettle();

      expect(find.text('Big practice'), findsOneWidget);
      expect(find.text('經濟'), findsWidgets);
      await tester.tap(find.text('Big practice'));
      expect(started, [2658825]);

      if (entry.key == 'phone') {
        await tester.tap(find.text('經濟').first);
        await tester.pumpAndSettle();
      }
      expect(find.text('Last week'), findsOneWidget);
      expect(find.text('3/4'), findsOneWidget);
      await tester.tap(find.text('Last week'));
      expect(reviewed, [2661977], reason: 'paper_id, not trial_id');
      await tester.scrollUntilVisible(
        find.text('考評局經濟歷屆公開試試題'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('econ_5'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test('catalog folds passive observations into the same store', () {
    final catalog = CatalogController(OqbRepository(transport));
    catalog.observe(OqbApiDataEvent.fromJson({
      'path': '/api/load_papers',
      'requestBody': 'criteria%5Bto_submit%5D=1',
      'response': envelope([
        {'id': 5, 'title': 'Observed'},
      ]),
    }));
    expect(catalog.data.availablePapers.single.title, 'Observed');
    catalog.dispose();
  });
}
