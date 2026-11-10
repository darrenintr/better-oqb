import 'package:better_oqb/src/services/mistake_history.dart';
import 'package:better_oqb/src/models/oqb_trial.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fakes.dart';

void main() {
  test('deduplicates same attempt and retry queue clears after later success',
      () async {
    final history = MistakeHistory();
    addTearDown(history.dispose);
    final session = OqbTrialSession.fromResult(startTrialResult());
    await history.record(
        session: session, question: session.questions.first, correct: false);
    await history.record(
        session: session, question: session.questions.first, correct: false);
    expect(history.attempts.length, 1);
    expect(history.retryQueue.length, 1);
    final retry = OqbTrialSession.fromResult(startTrialResult(trialId: 78));
    await history.record(
        session: retry, question: retry.questions.first, correct: true);
    expect(history.retryQueue, isEmpty);
    expect(history.topics.single.accuracy, .5);
    expect(history.weaknessPrompt, contains('1/2'));
    final saved = history.attempts.first.toJson();
    expect(saved.keys, isNot(contains('token')));
    expect(saved.keys, isNot(contains('sesskey')));
    expect(StudyAttempt.parse(saved).correct, false);
  });
}
