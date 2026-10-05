import 'oqb_api_data.dart';
import 'oqb_json.dart';
import 'oqb_trial.dart';

/// Detailed `load_paper` result (`with_content/with_trials/with_trial_questions/
/// with_stat`). Only the parts whose shape is known are interpreted; the
/// statistics object is kept as a sanitized map until its layout is captured.
class OqbPaperDetail {
  const OqbPaperDetail({
    required this.paper,
    this.stat = const <String, dynamic>{},
  });

  final OqbPaper paper;
  final Map<String, dynamic> stat;

  factory OqbPaperDetail.fromResult(dynamic result) {
    final map = asMap(result);
    // load_paper may wrap the paper or return it flat.
    final paperMap = map['paper'] is Map ? asMap(map['paper']) : map;
    return OqbPaperDetail(
      paper: OqbPaper.fromJson(paperMap),
      stat: asMap(map['stat'] ?? paperMap['stat']),
    );
  }
}

class OqbBreakdownRow {
  const OqbBreakdownRow({
    required this.key,
    required this.total,
    required this.correct,
  });

  final String key;
  final int total;
  final int correct;

  double get ratio => total == 0 ? 0 : correct / total;
}

/// Everything needed by the review screen. Breakdowns are computed locally
/// from per-question `is_correct`, `topic_code[]` and `difficulty_code`.
class OqbReview {
  OqbReview({
    required this.session,
    this.detail,
    this.summary,
  });

  final OqbTrialSession session;
  final OqbPaperDetail? detail;
  final OqbPaperSummary? summary;

  List<OqbTrialQuestion> get questions => session.questions;

  int get total => session.total;
  int get answered => questions.where((q) => q.userInput.isNotEmpty).length;
  int get correct => questions.where((q) => q.isCorrect == true).length;
  bool get hasCorrectness => questions.any((q) => q.isCorrect != null);

  num? get score {
    if (session.trial.score != null) return session.trial.score;
    if (summary?.score != null) return summary!.score;
    final scores = questions.map((q) => q.score).whereType<num>().toList();
    if (scores.isEmpty) return null;
    return scores.fold<num>(0, (sum, value) => sum + value);
  }

  num? get scoreFull => session.trial.scoreFull ?? summary?.scoreFull;

  late final List<OqbBreakdownRow> byTopic = _breakdown(
    (q) => q.question?.topicCodes ?? const <String>[],
  );

  late final List<OqbBreakdownRow> byDifficulty = _breakdown(
    (q) {
      final code = q.question?.difficultyCode ?? 0;
      return code > 0 ? <String>['$code'] : const <String>[];
    },
  );

  List<OqbBreakdownRow> _breakdown(List<String> Function(OqbTrialQuestion) keys) {
    final totals = <String, int>{};
    final correct = <String, int>{};
    for (final question in questions) {
      for (final key in keys(question).toSet()) {
        totals[key] = (totals[key] ?? 0) + 1;
        if (question.isCorrect == true) correct[key] = (correct[key] ?? 0) + 1;
      }
    }
    final rows = totals.entries
        .map((entry) => OqbBreakdownRow(
              key: entry.key,
              total: entry.value,
              correct: correct[entry.key] ?? 0,
            ))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return rows;
  }
}
