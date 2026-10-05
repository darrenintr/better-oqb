import 'package:better_oqb/src/models/oqb_meta.dart';
import 'package:better_oqb/src/models/oqb_review.dart';
import 'package:better_oqb/src/models/oqb_trial.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  group('start_trial parsing', () {
    test('parses paper, trial and ordered trial questions', () {
      final session = OqbTrialSession.fromResult(startTrialResult(count: 3));

      expect(session.paper.id, 2658825);
      expect(session.paper.subjectCode, 'econ');
      expect(session.trial.id, 77);
      expect(session.trial.submitted, isFalse);
      expect(session.trial.latestAccessQuestionNo, 1);
      // Fixture lists questions in reverse; seq must restore order.
      expect(session.questions.map((q) => q.seq), [1, 2, 3]);
      expect(session.total, 3);

      final first = session.questions.first;
      expect(first.question!.choices, hasLength(4));
      expect(first.question!.choices[2].label, 'C');
      expect(first.question!.choices[2].html, '<p>C0</p>');
      expect(first.question!.isMultipleChoice, isTrue);
      expect(first.question!.topicCodes, ['econ_1']);
      expect(first.question!.difficultyCode, 1);
    });

    test('keeps trial_question.id distinct from question.id', () {
      final session = OqbTrialSession.fromResult(startTrialResult());
      final first = session.questions.first;

      expect(first.id, 9000, reason: 'trial question id (used by save_trial)');
      expect(first.questionId, 500, reason: 'question-bank id');
      expect(first.question!.id, 500);
      expect(first.id, isNot(first.questionId));
    });

    test('parses trial state stored as a JSON string', () {
      final result = startTrialResult();
      (result['trial'] as Map)['state'] = '{"latestAccessQuestionNo":3}';
      final session = OqbTrialSession.fromResult(result);
      expect(session.trial.latestAccessQuestionNo, 3);
    });

    test('tolerates numbers as strings and missing optional fields', () {
      final session = OqbTrialSession.fromResult({
        'paper': {'id': '42'},
        'trial': {'id': '7', 'submitted': '0'},
        'trial_question': [
          {'id': '11', 'question_id': '5', 'user_input': '[1]'},
          {'id': 12},
          'garbage',
          {'question_id': 6}, // no trial question id: unusable for saving
        ],
      });

      expect(session.paper.id, 42);
      expect(session.trial.id, 7);
      expect(session.questions.map((q) => q.id), [11, 12]);
      expect(session.questions.first.userInput.single, 1);
      expect(session.questions.first.question, isNull);
      expect(session.questions.last.userInput.isEmpty, isTrue);
    });

    test('rejects a result without a trial id', () {
      expect(
        () => OqbTrialSession.fromResult({'paper': {'id': 1}, 'trial_question': []}),
        throwsA(isA<OqbTrialParseException>()),
      );
      expect(
        () => OqbTrialSession.fromResult(null),
        throwsA(isA<OqbTrialParseException>()),
      );
    });

    test('accepts map-shaped choices', () {
      final question = OqbQuestionContent.fromJson({
        'id': 1,
        'choices': [
          {'content': '<p>first</p>'},
          {'url': 'https://cdn.example/x.png?sig=abc'},
        ],
      });
      expect(question.choices.first.html, '<p>first</p>');
      expect(question.choices.last.imageUrl, contains('x.png'));
    });
  });

  group('user input', () {
    test('parses observed and defensive encodings', () {
      expect(OqbUserInput.parse('[0]').choices, [0]);
      expect(OqbUserInput.parse([2]).choices, [2]);
      expect(OqbUserInput.parse('2').choices, [2]);
      expect(OqbUserInput.parse(null).isEmpty, isTrue);
      expect(OqbUserInput.parse('null').isEmpty, isTrue);
      expect(OqbUserInput.parse('[]').isEmpty, isTrue);
      expect(OqbUserInput.parse('[0, 3]').choices, [0, 3]);
    });

    test('serializes MC answers as a JSON array of zero-based indexes', () {
      expect(const OqbUserInput([0]).serialize(), '[0]');
      expect(const OqbUserInput([3]).serialize(), '[3]');
      expect(OqbUserInput.empty.serialize(), '[]');
    });

    test('echoes unknown answer formats back unchanged', () {
      final longAnswer = OqbUserInput.parse('My essay answer');
      expect(longAnswer.isNotEmpty, isTrue);
      expect(longAnswer.choices, isEmpty);
      expect(longAnswer.serialize(), 'My essay answer');
    });
  });

  group('review parsing', () {
    test('exposes correctness, suggested and model answers', () {
      final session = OqbTrialSession.fromResult(
        startTrialResult(review: true, count: 3, userInputs: ['[2]', '[0]', null]),
        isReview: true,
      );
      final first = session.questions.first;

      expect(session.isReview, isTrue);
      expect(session.trial.submitted, isTrue);
      expect(first.isCorrect, isTrue);
      expect(first.score, 1);
      expect(first.question!.suggestedAnswer!.single, 2);
      expect(first.question!.modelAnswer, contains('Because C'));
      expect(session.questions[1].isCorrect, isFalse);
    });

    test('normal attempts carry no answer key', () {
      final session = OqbTrialSession.fromResult(startTrialResult());
      expect(session.questions.first.question!.suggestedAnswer, isNull);
      expect(session.questions.first.isCorrect, isNull);
    });

    test('computes topic and difficulty breakdowns locally', () {
      final review = OqbReview(
        session: OqbTrialSession.fromResult(
          startTrialResult(review: true, count: 4, userInputs: ['[2]', '[1]', '[2]', null]),
          isReview: true,
        ),
      );

      expect(review.total, 4);
      expect(review.answered, 3);
      expect(review.correct, 2); // indexes 0 and 2
      expect(review.score, 2);
      final topic1 = review.byTopic.firstWhere((row) => row.key == 'econ_1');
      expect(topic1.total, 2);
      expect(topic1.correct, 2);
      expect(review.byDifficulty.map((row) => row.key), ['1', '2', '3']);
    });

    test('detailed load_paper parsing tolerates unknown layouts', () {
      final detail = OqbPaperDetail.fromResult({
        'paper': {'id': 9, 'title': 'P'},
        'stat': {'topic': {'econ_1': 1}},
      });
      expect(detail.paper.id, 9);
      expect(detail.stat, isNotEmpty);

      final empty = OqbPaperDetail.fromResult('unexpected');
      expect(empty.paper.id, 0);
      expect(empty.stat, isEmpty);
    });
  });

  group('meta labels', () {
    test('indexes list and dictionary shaped entries, falling back to codes', () {
      final meta = OqbMeta.fromJson({
        'subject': [
          {'code': 'econ', 'title_zh': '經濟', 'title_en': 'Economics'},
        ],
        'topic': {
          'econ_5': {'name_en': 'Firms and production'},
        },
        'publisher': {'HKEAA': '香港考試及評核局'},
      });

      expect(meta.label('econ'), '經濟');
      expect(meta.label('econ', preferEnglish: true), 'Economics');
      expect(meta.label('HKEAA'), '香港考試及評核局');
      expect(meta.label('unknown_code'), 'unknown_code');
      expect(OqbMeta.fromJson('not json').label('econ'), 'econ');
    });
  });
}
