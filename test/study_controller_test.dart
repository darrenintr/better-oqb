import 'dart:async';

import 'package:better_oqb/src/controllers/study_controller.dart';
import 'package:better_oqb/src/models/oqb_trial.dart';
import 'package:better_oqb/src/services/oqb_api_client.dart';
import 'package:better_oqb/src/services/oqb_api_requests.dart';
import 'package:better_oqb/src/services/oqb_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

Future<void> settle([int ms = 30]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  late FakeTransport transport;
  late StudyController controller;
  late DateTime now;

  StudyController build({List<Duration> retryDelays = const []}) {
    return StudyController(
      OqbRepository(transport),
      saveDelay: const Duration(milliseconds: 5),
      retryDelays: retryDelays,
      clock: () => now,
    );
  }

  setUp(() {
    now = DateTime(2026, 10, 5, 9);
    transport = FakeTransport((request) {
      switch (request.command) {
        case 'startTrial':
          return envelope(startTrialResult(count: 3));
        case 'saveTrial':
        case 'submitTrial':
          return {'success': true, 'result': true};
      }
      return envelope(null);
    });
    controller = build();
  });

  tearDown(() => controller.dispose());

  group('opening and navigation', () {
    test('open calls start_trial and resumes at OQB\'s last question', () async {
      transport.handler = (request) => envelope(
            startTrialResult(count: 3, state: {'latestAccessQuestionNo': 2}),
          );
      await controller.open(2658825);

      expect(transport.commands('startTrial').single.fields, {'id': '2658825'});
      expect(controller.hasSession, isTrue);
      expect(controller.total, 3);
      expect(controller.questionNumber, 2);
      expect(controller.current!.id, 9001);
    });

    test('route question number overrides stored progress', () async {
      await controller.open(2658825, questionNo: 3);
      expect(controller.questionNumber, 3);
    });

    test('navigates over the trial_question array without OQB buttons', () async {
      await controller.open(1);
      expect(controller.hasPrevious, isFalse);
      controller.next();
      controller.next();
      expect(controller.questionNumber, 3);
      expect(controller.hasNext, isFalse);
      controller.next(); // clamps
      expect(controller.questionNumber, 3);
      controller.goTo(0);
      expect(controller.questionNumber, 1);
      controller.goTo(-5);
      expect(controller.questionNumber, 1);
      controller.previous();
      expect(controller.questionNumber, 1);
      // Navigation alone never writes to OQB.
      expect(transport.commands('saveTrial'), isEmpty);
    });

    test('load errors are surfaced, not thrown', () async {
      transport.handler = (request) =>
          const OqbApiException('not_authenticated', 'No token');
      await controller.open(1);
      expect(controller.hasSession, isFalse);
      expect(controller.loadError, isA<OqbApiException>());
      expect(controller.isLoading, isFalse);
    });
  });

  group('answering and saving', () {
    test('selection updates immediately and saves with the trial question id', () async {
      await controller.open(1);
      final question = controller.current!;
      now = now.add(const Duration(seconds: 4));

      controller.selectChoice(2);
      expect(controller.answerFor(question).single, 2);
      expect(controller.saveStateFor(question), OqbSaveState.pending);
      expect(controller.saveState, OqbSaveState.pending);

      await settle();
      final save = transport.commands('saveTrial').single;
      expect(save.fields['trial_id'], '77');
      expect(save.fields['trial_question[0][id]'], '9000');
      expect(save.fields['trial_question[0][id]'], isNot('500'));
      expect(save.fields['trial_question[0][user_input]'], '[2]');
      expect(save.fields['trial_question[0][time_spent]'], '4');
      expect(save.fields['opts[state]'], '{"latestAccessQuestionNo":1}');
      expect(controller.saveState, OqbSaveState.saved);
      expect(controller.unsavedCount, 0);
      expect(transport.commands('submitTrial'), isEmpty);
    });

    test('shows saving while the request is in flight', () async {
      final gate = Completer<void>();
      transport.handler = (request) async {
        if (request.command == 'startTrial') return envelope(startTrialResult());
        await gate.future;
        return {'success': true, 'result': true};
      };
      await controller.open(1);
      controller.selectChoice(0);
      await settle();
      expect(controller.saveState, OqbSaveState.saving);
      expect(controller.saveStateFor(controller.current!), OqbSaveState.saving);
      gate.complete();
      await settle();
      expect(controller.saveState, OqbSaveState.saved);
    });

    test('a change made during a save is saved afterwards, not lost', () async {
      final gate = Completer<void>();
      var saves = 0;
      transport.handler = (request) async {
        if (request.command == 'startTrial') return envelope(startTrialResult());
        saves++;
        if (saves == 1) await gate.future;
        return {'success': true, 'result': true};
      };
      await controller.open(1);
      controller.selectChoice(0);
      await settle();
      controller.selectChoice(3); // while first save is in flight
      gate.complete();
      await settle(60);

      final saved = transport.commands('saveTrial');
      expect(saved, hasLength(2));
      expect(saved.last.fields['trial_question[0][user_input]'], '[3]');
      expect(controller.saveState, OqbSaveState.saved);
    });

    test('batches answers to several questions into one save', () async {
      await controller.open(1);
      controller.selectChoice(1);
      controller.next();
      controller.selectChoice(2);
      await settle();
      final save = transport.commands('saveTrial').single;
      expect(save.fields['trial_question[0][id]'], '9000');
      expect(save.fields['trial_question[1][id]'], '9001');
      expect(save.fields['trial_question[1][user_input]'], '[2]');
      expect(save.fields['opts[state]'], '{"latestAccessQuestionNo":2}');
    });

    test('failed saves keep the answer, retry automatically, and recover', () async {
      controller.dispose();
      controller = build(retryDelays: const [Duration(milliseconds: 20)]);
      var fail = true;
      transport.handler = (request) {
        if (request.command == 'startTrial') return envelope(startTrialResult());
        if (fail) return const OqbApiException('network', 'offline');
        return {'success': true, 'result': true};
      };
      await controller.open(1);
      controller.selectChoice(1);
      await settle(12);

      expect(controller.saveState, OqbSaveState.failed);
      expect(controller.saveError, isA<OqbApiException>());
      expect(controller.answerFor(controller.current!).single, 1);

      fail = false;
      await settle(60);
      expect(controller.saveState, OqbSaveState.saved);
      expect(transport.commands('saveTrial').length, greaterThanOrEqualTo(2));
    });

    test('manual retry after automatic retries are exhausted', () async {
      var fail = true;
      transport.handler = (request) {
        if (request.command == 'startTrial') return envelope(startTrialResult());
        if (fail) return const OqbApiException('oqb_error', 'rejected');
        return {'success': true, 'result': true};
      };
      await controller.open(1);
      controller.selectChoice(1);
      await settle();
      expect(controller.saveState, OqbSaveState.failed);

      fail = false;
      controller.retryNow();
      await settle();
      expect(controller.saveState, OqbSaveState.saved);
    });

    test('recovers a lost sesskey by resuming the same trial', () async {
      var first = true;
      transport.handler = (request) {
        if (request.command == 'startTrial') return envelope(startTrialResult());
        if (first) {
          first = false;
          return const OqbApiException('missing_sesskey', 'no sesskey');
        }
        return {'success': true, 'result': true};
      };
      await controller.open(1);
      controller.selectChoice(0);
      await settle();
      expect(transport.commands('startTrial'), hasLength(2));
      expect(transport.commands('saveTrial'), hasLength(2));
      expect(controller.saveState, OqbSaveState.saved);
    });

    test('ignores invalid selections and non-MC questions', () async {
      transport.handler = (request) => envelope({
            'paper': {'id': 1},
            'trial': {'id': 2},
            'trial_question': [
              {
                'id': 3,
                'question': {'id': 4, 'content': '<p>Explain.</p>', 'choices': []},
              },
            ],
          });
      await controller.open(1);
      controller.selectChoice(0);
      await settle();
      expect(controller.unsavedCount, 0);
      expect(transport.commands('saveTrial'), isEmpty);
    });

    test('does not resave an unchanged answer', () async {
      transport.handler = (request) => request.command == 'startTrial'
          ? envelope(startTrialResult(userInputs: ['[1]']))
          : {'success': true, 'result': true};
      await controller.open(1);
      expect(controller.answeredCount, 1);
      controller.selectChoice(1);
      await settle();
      expect(transport.commands('saveTrial'), isEmpty);
    });
  });

  group('submission', () {
    test('is never automatic', () async {
      await controller.open(1);
      for (var i = 0; i < 3; i++) {
        controller.selectChoice(i);
        controller.next();
      }
      await settle();
      expect(transport.commands('submitTrial'), isEmpty);
    });

    test('flushes pending answers first, then submits', () async {
      await controller.open(1);
      controller.selectChoice(2);
      await controller.submit();

      final commands = transport.requests.map((r) => r.command).toList();
      expect(commands.indexOf('saveTrial'), lessThan(commands.indexOf('submitTrial')));
      final submit = transport.commands('submitTrial').single;
      expect(submit.fields['trial_id'], '77');
      expect(submit.fields['trial_question[0][id]'], '9000');
      expect(submit.fields['trial_question[0][user_input]'], '[2]');
      expect(controller.isSubmitted, isTrue);
      expect(controller.isReadOnly, isTrue);

      controller.selectChoice(0);
      expect(controller.answerFor(controller.current!).single, 2);
    });

    test('refuses to submit while answers cannot be saved', () async {
      transport.handler = (request) {
        if (request.command == 'startTrial') return envelope(startTrialResult());
        return const OqbApiException('network', 'offline');
      };
      await controller.open(1);
      controller.selectChoice(2);

      await expectLater(
        controller.submit(),
        throwsA(isA<OqbApiException>().having((e) => e.code, 'code', 'unsaved')),
      );
      expect(transport.commands('submitTrial'), isEmpty);
      expect(controller.isSubmitted, isFalse);
      expect(controller.answerFor(controller.current!).single, 2);
    });

    test('review sessions are read-only', () async {
      controller.attach(OqbTrialSession.fromResult(
        startTrialResult(review: true),
        isReview: true,
      ));
      controller.selectChoice(0);
      await controller.submit();
      expect(transport.requests, isEmpty);
    });
  });

  test('saveAnswers request uses OqbRequests layout', () {
    // Guard: the controller depends on this command name being allow-listed
    // by assets/oqb_api_client.js.
    final request = OqbRequests.saveTrial(
      trialId: 1,
      answers: const [],
      trialTimeSpent: 0,
      latestAccessQuestionNo: 1,
    );
    expect(request.command, 'saveTrial');
  });
}
