import 'package:better_oqb/src/services/mistake_history.dart';
import 'package:better_oqb/src/models/oqb_trial.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fakes.dart';
import 'package:better_oqb/src/services/local_preferences.dart';

class MemoryHistoryPreferences extends LocalPreferences {
  int writes = 0;
  Map<String, dynamic>? saved;
  @override
  Future<Map<String, dynamic>?> read(String name) async => null;
  @override
  Future<void> write(String name, Map<String, dynamic> value) async {
    writes++;
    saved = value;
  }
}

void main() {
  testWidgets(
      'review batches history writes and explicit flush saves immediately',
      (tester) async {
    final storage = MemoryHistoryPreferences();
    final history = MistakeHistory(storage: storage);
    addTearDown(history.dispose);
    final session = OqbTrialSession.fromResult(startTrialResult(count: 40));
    for (final q in session.questions) {
      await history.record(session: session, question: q, correct: false);
    }
    expect(storage.writes, 0);
    await tester.pump(const Duration(milliseconds: 650));
    expect(storage.writes, 1);
    expect((storage.saved!['attempts'] as List).length, 40);
    final retry = OqbTrialSession.fromResult(startTrialResult(trialId: 78));
    await history.record(
        session: retry, question: retry.questions.first, correct: true);
    await history.persist();
    expect(storage.writes, 2);
    await tester.pump(const Duration(seconds: 1));
    expect(storage.writes, 2);
  });

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
