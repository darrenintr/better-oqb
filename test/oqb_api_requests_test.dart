import 'package:better_oqb/src/models/oqb_trial.dart';
import 'package:better_oqb/src/services/oqb_api_requests.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('package request matches the captured form', () {
    expect(OqbRequests.getUsablePackages.command, 'getUsablePackages');
    expect(OqbRequests.getUsablePackages.fields, {
      'opts[stat]': '1',
      'opts[function_type]': 'question_attempt.compose.view',
    });
  });

  test('paper list requests use dynamic subjects', () {
    expect(OqbRequests.loadPapersToSubmit.fields, {'criteria[to_submit]': '1'});
    expect(OqbRequests.loadPresetPapers('chem').fields, {
      'criteria[preset]': '1',
      'criteria[subject_code]': 'chem',
    });
    expect(OqbRequests.loadSubmittedPapers('bafs').fields, {
      'criteria[subject_code]': 'bafs',
    });
  });

  test('start_trial normal and review forms', () {
    expect(OqbRequests.startTrial(2658825).fields, {'id': '2658825'});
    expect(OqbRequests.startTrial(5, review: true).fields, {
      'id': '5',
      'opts[review]': '1',
    });
  });

  test('detailed load_paper form', () {
    expect(OqbRequests.loadPaper(3).fields, {'id': '3'});
    expect(OqbRequests.loadPaper(3, detailed: true).fields, {
      'id': '3',
      'opts[with_content]': '1',
      'opts[with_trials]': '1',
      'opts[with_trial_questions]': '1',
      'opts[with_stat]': '1',
    });
  });

  test('search request encodes criteria arrays and count mode', () {
    final search = OqbRequests.searchQuestions(
      {
        'publisher_code': ['HKEAA'],
        'subject_code': ['econ'],
        'topic_code': ['econ_5'],
      },
      limit: 40,
      random: true,
    );
    expect(search.fields, {
      'criteria[publisher_code][0]': 'HKEAA',
      'criteria[subject_code][0]': 'econ',
      'criteria[topic_code][0]': 'econ_5',
      'opts[rand]': '1',
      'opts[limit]': '40',
    });

    final count = OqbRequests.searchQuestions({'subject_code': ['econ']}, countOnly: true);
    expect(count.fields['opts[count]'], '1');
    expect(count.fields['opts[limit]'], '');
  });

  test('save_trial matches the captured answer save', () {
    final request = OqbRequests.saveTrial(
      trialId: 77,
      answers: const [
        OqbAnswerUpdate(
          trialQuestionId: 9000,
          userInput: OqbUserInput([0]),
          timeSpent: 1,
        ),
      ],
      trialTimeSpent: 1,
      latestAccessQuestionNo: 1,
    );

    expect(request.command, 'saveTrial');
    expect(request.fields, {
      'trial_id': '77',
      'trial_question[0][id]': '9000',
      'trial_question[0][user_input]': '[0]',
      'trial_question[0][time_spent]': '1',
      'trial_question[0][status]': 'null',
      'opts[time_spent]': '1',
      'opts[state]': '{"latestAccessQuestionNo":1}',
    });
    // Secrets and submit flag are added by the JS client only.
    for (final key in ['token', 'sesskey', 'app', 'opts[submit]']) {
      expect(request.fields.containsKey(key), isFalse, reason: key);
    }
  });

  test('submit uses a distinct command so JS can force opts[submit]=1', () {
    final request = OqbRequests.submitTrial(
      trialId: 77,
      answers: const [
        OqbAnswerUpdate(
          trialQuestionId: 9001,
          userInput: OqbUserInput([3]),
          timeSpent: 12,
          status: 'attempted',
        ),
      ],
      trialTimeSpent: 40,
      latestAccessQuestionNo: 2,
    );
    expect(request.command, 'submitTrial');
    expect(request.fields['trial_question[0][status]'], 'attempted');
    expect(request.fields['trial_question[0][user_input]'], '[3]');
    expect(request.fields.containsKey('opts[submit]'), isFalse);
  });

  test('diagnostic description never includes field values', () {
    final request = OqbRequests.saveTrial(
      trialId: 77,
      answers: const [
        OqbAnswerUpdate(trialQuestionId: 9000, userInput: OqbUserInput([0]), timeSpent: 1),
      ],
      trialTimeSpent: 1,
      latestAccessQuestionNo: 1,
    );
    final text = request.describe();
    expect(text, contains('saveTrial'));
    expect(text, contains('1 answer(s)'));
    expect(text, isNot(contains('9000')));
  });
}
