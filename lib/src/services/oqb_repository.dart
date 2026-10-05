import '../models/oqb_api_data.dart';
import '../models/oqb_json.dart';
import '../models/oqb_meta.dart';
import '../models/oqb_review.dart';
import '../models/oqb_trial.dart';
import 'oqb_api_client.dart';
import 'oqb_api_requests.dart';

/// Result of a save_trial call that OQB accepted.
class OqbSaveResult {
  const OqbSaveResult({this.statuses = const <int, String>{}});

  /// trial_question.id → status, when OQB echoed the updated questions.
  final Map<int, String> statuses;
}

/// Typed access to the OQB API through the authenticated WebView. This is
/// the only place that knows which request produces which model.
class OqbRepository {
  OqbRepository(this.transport);

  final OqbApiTransport transport;

  Future<OqbMeta> getMeta() async {
    final response = await transport.send(OqbRequests.getMeta);
    return OqbMeta.fromJson(response.data);
  }

  Future<List<OqbPackageSummary>> getUsablePackages() async {
    final response = await transport.send(OqbRequests.getUsablePackages);
    return OqbObservedApiState.parsePackages(response.result);
  }

  Future<List<OqbPaperSummary>> loadPapersToSubmit() async {
    final response = await transport.send(OqbRequests.loadPapersToSubmit);
    return OqbObservedApiState.parsePapers(response.result);
  }

  Future<List<OqbPaperSummary>> loadPresetPapers(String subject) async {
    final response = await transport.send(OqbRequests.loadPresetPapers(subject));
    return OqbObservedApiState.parsePapers(response.result);
  }

  Future<List<OqbPaperSummary>> loadSubmittedPapers(String subject) async {
    final response =
        await transport.send(OqbRequests.loadSubmittedPapers(subject));
    return OqbObservedApiState.parsePapers(response.result);
  }

  /// The layout of get_user_question_stat has not been captured precisely;
  /// return the sanitized result map for best-effort display.
  Future<Map<String, dynamic>> getUserQuestionStat(String subject) async {
    final response =
        await transport.send(OqbRequests.getUserQuestionStat(subject));
    return asMap(response.result);
  }

  /// Starts or resumes an attempt. Must follow an explicit user action.
  Future<OqbTrialSession> startTrial(int paperId) async {
    final response = await transport.send(OqbRequests.startTrial(paperId));
    return OqbTrialSession.fromResult(response.result);
  }

  Future<OqbSaveResult> saveAnswers({
    required int trialId,
    required List<OqbAnswerUpdate> answers,
    required int trialTimeSpent,
    required int latestAccessQuestionNo,
  }) async {
    final response = await transport.send(OqbRequests.saveTrial(
      trialId: trialId,
      answers: answers,
      trialTimeSpent: trialTimeSpent,
      latestAccessQuestionNo: latestAccessQuestionNo,
    ));
    return OqbSaveResult(statuses: _statuses(response.result));
  }

  /// Submits the attempt. Only call from a confirmed user action.
  Future<void> submitTrial({
    required int trialId,
    required List<OqbAnswerUpdate> answers,
    required int trialTimeSpent,
    required int latestAccessQuestionNo,
  }) async {
    await transport.send(OqbRequests.submitTrial(
      trialId: trialId,
      answers: answers,
      trialTimeSpent: trialTimeSpent,
      latestAccessQuestionNo: latestAccessQuestionNo,
    ));
  }

  /// Observed review flow: start_trial(review) then detailed load_paper.
  /// The detailed paper is optional; review still works without it.
  Future<OqbReview> loadReview(int paperId, {OqbPaperSummary? summary}) async {
    final response =
        await transport.send(OqbRequests.startTrial(paperId, review: true));
    final session = OqbTrialSession.fromResult(response.result, isReview: true);

    OqbPaperDetail? detail;
    try {
      final paper =
          await transport.send(OqbRequests.loadPaper(paperId, detailed: true));
      detail = OqbPaperDetail.fromResult(paper.result);
    } on OqbApiException {
      detail = null;
    }
    return OqbReview(session: session, detail: detail, summary: summary);
  }

  /// save_trial's response shape is only known to update statuses to
  /// `attempted`; read them if present and ignore anything else.
  static Map<int, String> _statuses(dynamic result) {
    final map = asMap(result);
    final rows = map.containsKey('trial_question')
        ? asMapList(map['trial_question'])
        : asMapList(result);
    final statuses = <int, String>{};
    for (final row in rows) {
      final id = asInt(row['id']);
      final status = asString(row['status']);
      if (id > 0 && status.isNotEmpty && status != 'null') statuses[id] = status;
    }
    return statuses;
  }
}
