import 'dart:convert';

import '../models/oqb_trial.dart';

/// One call to the same-origin JS client (assets/oqb_api_client.js).
///
/// [command] must be one of the commands the JS client allow-lists. [fields]
/// are the endpoint-specific form fields. `app`, `token` and `sesskey` are
/// added inside the WebView and must never appear here.
class OqbApiRequest {
  const OqbApiRequest(
    this.command,
    this.fields, {
    this.timeout = const Duration(seconds: 30),
    this.expectsEnvelope = true,
  });

  final String command;
  final Map<String, String> fields;
  final Duration timeout;

  /// Whether the response is OQB's `{success, result}` envelope.
  final bool expectsEnvelope;

  /// Non-sensitive one-line description for diagnostics.
  String describe() {
    final keys = fields.keys.where((key) => !key.startsWith('trial_question[')).join(',');
    final answers = fields.keys.where((key) => key.endsWith('[id]') && key.startsWith('trial_question[')).length;
    return '$command($keys${answers > 0 ? ', $answers answer(s)' : ''})';
  }
}

/// Answer/progress for one trial question in a save_trial request.
class OqbAnswerUpdate {
  const OqbAnswerUpdate({
    required this.trialQuestionId,
    required this.userInput,
    required this.timeSpent,
    this.status,
  });

  /// trial_question.id from start_trial — never question.id.
  final int trialQuestionId;
  final OqbUserInput userInput;

  /// Seconds spent on this question so far (cumulative).
  final int timeSpent;

  /// Last status known from OQB; serialized as `null` when unknown, matching
  /// the observed request.
  final String? status;
}

/// Builders for every OQB request Better OQB issues. Field layouts follow the
/// captures in docs/OQB_API_MAP.md; do not add endpoints that have not been
/// captured.
abstract final class OqbRequests {
  static const getMeta = OqbApiRequest(
    'getMeta',
    <String, String>{},
    expectsEnvelope: false,
  );

  static const getUserMeta = OqbApiRequest('getUserMeta', <String, String>{});

  static const getUsablePackages = OqbApiRequest('getUsablePackages', {
    'opts[stat]': '1',
    'opts[function_type]': 'question_attempt.compose.view',
  });

  static const loadPapersToSubmit = OqbApiRequest('loadPapers', {
    'criteria[to_submit]': '1',
  });

  static OqbApiRequest loadPresetPapers(String subjectCode) =>
      OqbApiRequest('loadPapers', {
        'criteria[preset]': '1',
        'criteria[subject_code]': subjectCode,
      });

  static OqbApiRequest loadSubmittedPapers(String subjectCode) =>
      OqbApiRequest('loadSubmittedPapers', {
        'criteria[subject_code]': subjectCode,
      });

  static OqbApiRequest getUserQuestionStat(String subjectCode) =>
      OqbApiRequest('getUserQuestionStat', {
        'criteria[subject_code]': subjectCode,
      });

  /// Read-only question search. [criteria] maps a criteria name (e.g.
  /// `subject_code`) to its values, encoded as `criteria[name][i]`.
  static OqbApiRequest searchQuestions(
    Map<String, List<String>> criteria, {
    int? limit,
    bool random = false,
    bool countOnly = false,
  }) {
    final fields = <String, String>{};
    criteria.forEach((name, values) {
      for (var i = 0; i < values.length; i++) {
        fields['criteria[$name][$i]'] = values[i];
      }
    });
    if (countOnly) {
      fields['opts[limit]'] = '';
      fields['opts[count]'] = '1';
    } else {
      if (random) fields['opts[rand]'] = '1';
      if (limit != null) fields['opts[limit]'] = '$limit';
    }
    return OqbApiRequest('searchQuestions', fields);
  }

  static OqbApiRequest loadPaper(int paperId, {bool detailed = false}) =>
      OqbApiRequest(
        'loadPaper',
        {
          'id': '$paperId',
          if (detailed) ...{
            'opts[with_content]': '1',
            'opts[with_trials]': '1',
            'opts[with_trial_questions]': '1',
            'opts[with_stat]': '1',
          },
        },
        timeout: const Duration(seconds: 60),
      );

  /// Starts or resumes an attempt. Only call after an explicit user action
  /// (or when OQB itself is already showing this paper's question route).
  static OqbApiRequest startTrial(int paperId, {bool review = false}) =>
      OqbApiRequest(
        'startTrial',
        {
          'id': '$paperId',
          if (review) 'opts[review]': '1',
        },
        timeout: const Duration(seconds: 60),
      );

  /// Saves answers/progress. The JS client forces `opts[submit]=0` for this
  /// command and adds the trial's sesskey.
  static OqbApiRequest saveTrial({
    required int trialId,
    required List<OqbAnswerUpdate> answers,
    required int trialTimeSpent,
    required int latestAccessQuestionNo,
  }) =>
      OqbApiRequest(
        'saveTrial',
        _trialFields(trialId, answers, trialTimeSpent, latestAccessQuestionNo),
      );

  /// Submits the trial. The JS client forces `opts[submit]=1` for this
  /// command. Must only be reached from an explicit, confirmed user action.
  static OqbApiRequest submitTrial({
    required int trialId,
    required List<OqbAnswerUpdate> answers,
    required int trialTimeSpent,
    required int latestAccessQuestionNo,
  }) =>
      OqbApiRequest(
        'submitTrial',
        _trialFields(trialId, answers, trialTimeSpent, latestAccessQuestionNo),
        timeout: const Duration(seconds: 60),
      );

  static Map<String, String> _trialFields(
    int trialId,
    List<OqbAnswerUpdate> answers,
    int trialTimeSpent,
    int latestAccessQuestionNo,
  ) {
    final fields = <String, String>{'trial_id': '$trialId'};
    for (var i = 0; i < answers.length; i++) {
      final answer = answers[i];
      fields['trial_question[$i][id]'] = '${answer.trialQuestionId}';
      fields['trial_question[$i][user_input]'] = answer.userInput.serialize();
      fields['trial_question[$i][time_spent]'] = '${answer.timeSpent}';
      fields['trial_question[$i][status]'] = answer.status ?? 'null';
    }
    fields['opts[time_spent]'] = '$trialTimeSpent';
    fields['opts[state]'] = jsonEncode({
      'latestAccessQuestionNo': latestAccessQuestionNo,
    });
    return fields;
  }
}
