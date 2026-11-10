import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/oqb_trial.dart';
import 'local_preferences.dart';

class StudyAttempt {
  const StudyAttempt({
    required this.trial,
    required this.paper,
    required this.question,
    required this.subject,
    required this.topics,
    required this.difficulty,
    required this.correct,
    required this.timestamp,
  });
  final int trial, paper, question, difficulty;
  final String subject;
  final List<String> topics;
  final bool correct;
  final DateTime timestamp;
  String get key => '$trial:$question';
  Map<String, dynamic> toJson() => {
        'trial': trial,
        'paper': paper,
        'question': question,
        'subject': subject,
        'topics': topics,
        'difficulty': difficulty,
        'correct': correct,
        'timestamp': timestamp.toIso8601String(),
      };
  factory StudyAttempt.parse(Map<String, dynamic> value) => StudyAttempt(
        trial: value['trial'] as int,
        paper: value['paper'] as int,
        question: value['question'] as int,
        subject: value['subject'] as String,
        topics: List<String>.from(value['topics'] as List),
        difficulty: value['difficulty'] as int,
        correct: value['correct'] as bool,
        timestamp: DateTime.parse(value['timestamp'] as String),
      );
}

class TopicAccuracy {
  TopicAccuracy(this.subject, this.topic);
  final String subject, topic;
  int correct = 0, total = 0;
  double get accuracy => total == 0 ? 0 : correct / total;
}

/// Correctness is recorded only after OQB reveals the key or review verdict.
/// No answers, question HTML, tokens or signed URLs are stored here.
class MistakeHistory extends ChangeNotifier {
  MistakeHistory({this.storage});
  static final instance = MistakeHistory(storage: LocalPreferences.instance);
  final LocalPreferences? storage;
  final _attempts = <String, StudyAttempt>{};
  Future<void>? _loading;
  Object? error;
  List<StudyAttempt> get attempts => _attempts.values.toList()
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    try {
      final data = await storage?.read('mistakes');
      for (final row in data?['attempts'] as List? ?? []) {
        final attempt = StudyAttempt.parse(
          Map<String, dynamic>.from(row as Map),
        );
        _attempts.putIfAbsent(attempt.key, () => attempt);
      }
      error = null;
      notifyListeners();
    } catch (e) {
      error = e;
      notifyListeners();
    }
  }

  Future<void> record({
    required OqbTrialSession session,
    required OqbTrialQuestion question,
    required bool correct,
  }) async {
    await load();
    final id = question.questionId > 0 ? question.questionId : question.id;
    final key = '${session.trial.id}:$id';
    if (_attempts.containsKey(key)) return;
    final content = question.question;
    _attempts[key] = StudyAttempt(
      trial: session.trial.id,
      paper: session.paper.id,
      question: id,
      subject: content?.subjectCode ?? session.paper.subjectCode,
      topics: content?.topicCodes ?? const [],
      difficulty: content?.difficultyCode ?? 0,
      correct: correct,
      timestamp: DateTime.now(),
    );
    while (_attempts.length > 5000) {
      _attempts.remove(_attempts.keys.first);
    }
    notifyListeners();
    await persist();
  }

  Future<void> persist() async {
    try {
      await storage?.write('mistakes', {
        'version': 1,
        'attempts': [for (final a in attempts) a.toJson()],
      });
      error = null;
    } catch (e) {
      error = e;
    }
    notifyListeners();
  }

  List<TopicAccuracy> get topics {
    final rows = <String, TopicAccuracy>{};
    for (final a in attempts) {
      for (final topic in a.topics.isEmpty ? ['Unclassified'] : a.topics) {
        final row = rows.putIfAbsent(
          '${a.subject}:$topic',
          () => TopicAccuracy(a.subject, topic),
        );
        row.total++;
        if (a.correct) row.correct++;
      }
    }
    return rows.values.toList()
      ..sort((a, b) => a.accuracy.compareTo(b.accuracy));
  }

  List<StudyAttempt> get retryQueue {
    final latest = <String, StudyAttempt>{};
    for (final a in attempts) {
      latest['${a.subject}:${a.question}'] = a;
    }
    return latest.values.where((a) => !a.correct).toList();
  }

  String get weaknessPrompt {
    final rows = topics.where((t) => t.correct < t.total).take(5);
    return 'Based on my locally recorded practice results, suggest a short revision plan. '
        'Do not assume a cause from accuracy alone. Ask diagnostic questions and recommend practice.\n'
        '${rows.map((t) => '${t.subject} / ${t.topic}: ${t.correct}/${t.total} correct').join('\n')}';
  }
}
