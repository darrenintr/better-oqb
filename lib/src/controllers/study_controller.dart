import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/oqb_trial.dart';
import '../services/oqb_api_client.dart';
import '../services/oqb_api_requests.dart';
import '../services/oqb_repository.dart';

enum OqbSaveState { saved, pending, saving, failed }

/// API-backed study session for one OQB trial.
///
/// Local answer state is authoritative for the UI and is never discarded
/// until OQB has accepted it. Saves are debounced, serialized (one request in
/// flight), retried with backoff, and can be retried manually. Submission is
/// only possible through [submit], which the UI calls after confirmation.
class StudyController extends ChangeNotifier {
  StudyController(
    this.repository, {
    this.saveDelay = const Duration(milliseconds: 600),
    this.retryDelays = const <Duration>[
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 15),
    ],
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final OqbRepository repository;
  final Duration saveDelay;
  final List<Duration> retryDelays;
  final DateTime Function() _clock;

  OqbTrialSession? _session;
  int? _loadingPaperId;
  Object? _loadError;
  int _loadGeneration = 0;
  int _index = 0;
  bool _submitting = false;
  bool _submitted = false;
  Object? _submitError;

  final Map<int, OqbUserInput> _answers = <int, OqbUserInput>{};
  final Map<int, int> _version = <int, int>{};
  final Map<int, int> _savedVersion = <int, int>{};
  final Map<int, int> _inFlight = <int, int>{};
  final Map<int, int> _timeSpent = <int, int>{};
  final Map<int, String?> _status = <int, String?>{};
  final Map<int, OqbUserInput> _answerKey = <int, OqbUserInput>{};
  final Set<int> _failed = <int>{};

  Future<void>? _currentSave;
  Timer? _saveTimer;
  Timer? _retryTimer;
  int _retryAttempt = 0;
  Object? _saveError;
  DateTime? _lastSavedAt;

  DateTime _questionEnteredAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _openedAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _baseTrialSeconds = 0;
  bool _disposed = false;

  // ---- read-only state -----------------------------------------------------

  OqbTrialSession? get session => _session;
  bool get hasSession => _session != null;
  bool get isLoading => _loadingPaperId != null;
  int? get loadingPaperId => _loadingPaperId;
  Object? get loadError => _loadError;
  int get index => _index;
  int get total => _session?.questions.length ?? 0;

  /// One-based number of the current question (matches OQB's /do/{n}).
  int get questionNumber => _index + 1;

  OqbTrialQuestion? get current {
    final questions = _session?.questions;
    if (questions == null || questions.isEmpty) return null;
    return questions[_index];
  }

  bool get isReadOnly =>
      _submitted || (_session?.isReview ?? false) || (_session?.trial.submitted ?? false);
  bool get isSubmitting => _submitting;
  bool get isSubmitted => _submitted;
  Object? get submitError => _submitError;
  Object? get saveError => _saveError;
  DateTime? get lastSavedAt => _lastSavedAt;

  OqbUserInput answerFor(OqbTrialQuestion question) =>
      _answers[question.id] ?? question.userInput;

  bool isAnswered(OqbTrialQuestion question) => answerFor(question).isNotEmpty;

  /// OQB's trial-question status for an answer that was checked in an
  /// exercise ("Show" in the original page).
  static const String checkedStatus = 'submitted';

  /// Exercise papers let the learner check each answer before submitting.
  /// Only `test` has been observed for tests, so anything else is treated
  /// as an exercise; OQB still decides whether it returns an answer key.
  bool get isExercise {
    final session = _session;
    return session != null &&
        !session.isReview &&
        session.paper.modeReview.toLowerCase() != 'test';
  }

  /// Suggested answer OQB sent for [question] during this attempt, if any.
  OqbUserInput? answerKeyFor(OqbTrialQuestion question) => _answerKey[question.id];

  /// Whether [question] was checked; OQB then treats its answer as final.
  bool isChecked(OqbTrialQuestion question) =>
      _status[question.id] == checkedStatus;

  /// Whether the answer of a checked question can be shown now.
  bool isAnswerShown(OqbTrialQuestion question) =>
      isChecked(question) && answerKeyFor(question) != null;

  bool canShowAnswer(OqbTrialQuestion question) =>
      isExercise &&
      !isReadOnly &&
      !_submitting &&
      (question.question?.isMultipleChoice ?? false) &&
      !isAnswerShown(question);

  int get answeredCount =>
      _session?.questions.where(isAnswered).length ?? 0;

  bool _isDirty(int id) => (_version[id] ?? 0) != (_savedVersion[id] ?? 0);

  List<int> get _dirtyIds =>
      _version.keys.where(_isDirty).toList(growable: false);

  int get unsavedCount => _dirtyIds.length;

  OqbSaveState saveStateFor(OqbTrialQuestion question) {
    final id = question.id;
    if (_inFlight.containsKey(id)) return OqbSaveState.saving;
    if (!_isDirty(id)) return OqbSaveState.saved;
    return _failed.contains(id) ? OqbSaveState.failed : OqbSaveState.pending;
  }

  OqbSaveState get saveState {
    if (_inFlight.isNotEmpty) return OqbSaveState.saving;
    final dirty = _dirtyIds;
    if (dirty.isEmpty) return OqbSaveState.saved;
    return dirty.any(_failed.contains) ? OqbSaveState.failed : OqbSaveState.pending;
  }

  /// Seconds spent on [question], including the running timer.
  int timeSpentOn(OqbTrialQuestion question) {
    var seconds = _timeSpent[question.id] ?? question.timeSpent;
    if (question.id == current?.id && !isReadOnly) {
      seconds += _clock().difference(_questionEnteredAt).inSeconds;
    }
    return seconds;
  }

  int get trialSeconds =>
      _baseTrialSeconds + _clock().difference(_openedAt).inSeconds;

  // ---- opening -------------------------------------------------------------

  /// Starts or resumes [paperId] through start_trial. Callers must only do
  /// this after an explicit user action or when OQB itself is already on the
  /// paper's question route.
  Future<void> open(int paperId, {int questionNo = 0}) async {
    if (_session?.paper.id == paperId && _loadError == null) {
      if (questionNo > 0) goTo(questionNo - 1);
      return;
    }
    final generation = ++_loadGeneration;
    _loadingPaperId = paperId;
    _loadError = null;
    _notify();
    try {
      final session = await repository.startTrial(paperId);
      if (generation != _loadGeneration || _disposed) return;
      attach(session, questionNo: questionNo);
    } catch (error) {
      if (generation != _loadGeneration || _disposed) return;
      _loadError = error;
      _loadingPaperId = null;
      _notify();
    }
  }

  /// Installs an already parsed trial (from [open] or a test).
  void attach(OqbTrialSession session, {int questionNo = 0}) {
    _resetTimers();
    _session = session;
    _loadingPaperId = null;
    _loadError = null;
    _submitted = false;
    _submitting = false;
    _submitError = null;
    _saveError = null;
    _retryAttempt = 0;
    _answers.clear();
    _version.clear();
    _savedVersion.clear();
    _inFlight.clear();
    _failed.clear();
    _timeSpent.clear();
    _status.clear();
    _answerKey.clear();
    for (final question in session.questions) {
      _answers[question.id] = question.userInput;
      _timeSpent[question.id] = question.timeSpent;
      _status[question.id] = question.status;
      final key = question.suggestedAnswer;
      if (key != null) _answerKey[question.id] = key;
    }
    _baseTrialSeconds = session.trial.timeSpent;
    _openedAt = _clock();
    _questionEnteredAt = _openedAt;

    final fallback = session.trial.latestAccessQuestionNo;
    final target = questionNo > 0 ? questionNo : fallback;
    _index = _clampIndex(target > 0 ? target - 1 : 0);
    _notify();
  }

  /// Re-reads the trial from OQB (e.g. after the user answered in the
  /// original page). Skipped while local answers are unsaved.
  Future<bool> reloadFromServer({int questionNo = 0}) async {
    final session = _session;
    if (session == null || unsavedCount > 0 || _inFlight.isNotEmpty) return false;
    try {
      final fresh = await repository.startTrial(session.paper.id);
      if (_disposed || _session?.paper.id != session.paper.id) return false;
      if (fresh.trial.id != session.trial.id) return false;
      attach(fresh, questionNo: questionNo > 0 ? questionNo : questionNumber);
      return true;
    } catch (_) {
      return false;
    }
  }

  void close() {
    _loadGeneration++;
    _resetTimers();
    _session = null;
    _loadingPaperId = null;
    _loadError = null;
    _submitted = false;
    _submitting = false;
    _answers.clear();
    _version.clear();
    _savedVersion.clear();
    _inFlight.clear();
    _failed.clear();
    _answerKey.clear();
    _notify();
  }

  // ---- navigation ----------------------------------------------------------

  void goTo(int index) {
    if (_session == null) return;
    final target = _clampIndex(index);
    if (target == _index) return;
    _accrueTime();
    _index = target;
    _questionEnteredAt = _clock();
    _notify();
  }

  void next() => goTo(_index + 1);
  void previous() => goTo(_index - 1);
  bool get hasNext => _index < total - 1;
  bool get hasPrevious => _index > 0;

  int _clampIndex(int index) {
    final count = total;
    if (count == 0) return 0;
    return index.clamp(0, count - 1);
  }

  /// Moves whole elapsed seconds on the current question into its total.
  void _accrueTime() {
    final question = current;
    if (question == null || isReadOnly) return;
    final seconds = _clock().difference(_questionEnteredAt).inSeconds;
    if (seconds <= 0) return;
    _timeSpent[question.id] = (_timeSpent[question.id] ?? 0) + seconds;
    _questionEnteredAt = _questionEnteredAt.add(Duration(seconds: seconds));
  }

  // ---- answering & saving ----------------------------------------------------

  /// Selects a single choice (zero-based) for the current question. The UI
  /// updates immediately; the save follows after [saveDelay].
  void selectChoice(int choiceIndex) {
    final question = current;
    if (question == null || isReadOnly || _submitting || isChecked(question)) return;
    final content = question.question;
    if (content == null || !content.isMultipleChoice) return;
    if (choiceIndex < 0 || choiceIndex >= content.choices.length) return;

    final next = OqbUserInput(<int>[choiceIndex]);
    if (answerFor(question).sameAs(next)) return;
    _answers[question.id] = next;
    _version[question.id] = (_version[question.id] ?? 0) + 1;
    _failed.remove(question.id);
    _scheduleSave(saveDelay);
    _notify();
  }

  /// Checks the current question the way OQB's "Show" button does: its
  /// status becomes [checkedStatus] and is saved straight away. OQB answers
  /// with the answer key, after which the answer is locked and shown.
  void showAnswer() {
    final question = current;
    if (question == null || !canShowAnswer(question)) return;
    _status[question.id] = checkedStatus;
    _version[question.id] = (_version[question.id] ?? 0) + 1;
    _failed.remove(question.id);
    _saveTimer?.cancel();
    _startSave();
    _notify();
  }

  void _scheduleSave(Duration delay) {
    _saveTimer?.cancel();
    _saveTimer = Timer(delay, () {
      _startSave();
    });
  }

  /// Saves immediately and retries failed answers.
  void retryNow() {
    _retryTimer?.cancel();
    _retryAttempt = 0;
    _failed.clear();
    _saveTimer?.cancel();
    _startSave();
    _notify();
  }

  Future<void> _startSave() {
    return _currentSave ??= _runSave().whenComplete(() {
      _currentSave = null;
      if (_disposed) return;
      // Answers changed while saving: save again (unless now failing).
      final dirty = _dirtyIds;
      if (dirty.isNotEmpty && !dirty.any(_failed.contains)) {
        _scheduleSave(Duration.zero);
      }
    });
  }

  Future<void> _runSave() async {
    final session = _session;
    if (session == null || isReadOnly) return;
    final dirty = _dirtyIds;
    if (dirty.isEmpty) return;

    _accrueTime();
    final updates = <OqbAnswerUpdate>[];
    for (final question in session.questions) {
      if (!dirty.contains(question.id)) continue;
      _inFlight[question.id] = _version[question.id] ?? 0;
      updates.add(_updateFor(question));
    }
    _notify();

    try {
      final result = await _withSesskeyRecovery(() => repository.saveAnswers(
            trialId: session.trial.id,
            answers: updates,
            trialTimeSpent: trialSeconds,
            latestAccessQuestionNo: questionNumber,
          ));
      if (_disposed || !identical(_session, session)) return;
      _inFlight.forEach((id, version) {
        if ((_savedVersion[id] ?? 0) < version) _savedVersion[id] = version;
        _failed.remove(id);
      });
      _status.addAll(result.statuses);
      _answerKey.addAll(result.answerKey);
      _saveError = null;
      _retryAttempt = 0;
      _lastSavedAt = _clock();
    } catch (error) {
      if (_disposed || !identical(_session, session)) return;
      _failed.addAll(_inFlight.keys);
      _saveError = error;
      _scheduleRetry();
    } finally {
      _inFlight.clear();
      _notify();
    }
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    if (_retryAttempt >= retryDelays.length) return;
    final delay = retryDelays[_retryAttempt++];
    _retryTimer = Timer(delay, () {
      _failed.clear();
      _startSave();
      _notify();
    });
  }

  /// A full page reload in the WebView loses the in-page sesskey. Resuming
  /// the same trial restores it; only accept it if it is the same trial.
  Future<T> _withSesskeyRecovery<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on OqbApiException catch (error) {
      if (error.code != 'missing_sesskey' && error.code != 'page_changed') rethrow;
      final session = _session;
      if (session == null) rethrow;
      final resumed = await repository.startTrial(session.paper.id);
      if (resumed.trial.id != session.trial.id || resumed.trial.submitted) {
        throw const OqbApiException(
          'trial_changed',
          'OQB returned a different attempt; answers were kept locally.',
        );
      }
      return action();
    }
  }

  OqbAnswerUpdate _updateFor(OqbTrialQuestion question) => OqbAnswerUpdate(
        trialQuestionId: question.id,
        userInput: answerFor(question),
        timeSpent: _timeSpent[question.id] ?? question.timeSpent,
        status: _status[question.id],
      );

  /// Waits for all local answers to be accepted by OQB. Returns false if any
  /// answer is still unsaved afterwards.
  Future<bool> flush() async {
    _saveTimer?.cancel();
    _retryTimer?.cancel();
    for (var attempt = 0; attempt < 3; attempt++) {
      final inProgress = _currentSave;
      if (inProgress != null) await inProgress;
      if (_dirtyIds.isEmpty) return true;
      _failed.clear();
      await _startSave();
      if (_dirtyIds.any(_failed.contains)) return false;
    }
    return _dirtyIds.isEmpty;
  }

  // ---- submission ------------------------------------------------------------

  /// Submits the attempt. Never called automatically: the UI must confirm
  /// with the learner first. Throws if answers cannot be saved first.
  Future<void> submit() async {
    final session = _session;
    if (session == null || isReadOnly || _submitting) return;
    _submitting = true;
    _submitError = null;
    _notify();
    try {
      final saved = await flush();
      if (!saved) {
        throw const OqbApiException(
          'unsaved',
          'Some answers have not been saved. Retry saving before submitting.',
        );
      }
      _accrueTime();
      final answers = [
        for (final question in session.questions)
          if (isAnswered(question)) _updateFor(question),
      ];
      await _withSesskeyRecovery(() => repository.submitTrial(
            trialId: session.trial.id,
            answers: answers,
            trialTimeSpent: trialSeconds,
            latestAccessQuestionNo: questionNumber,
          ));
      if (_disposed) return;
      _submitted = true;
      _resetTimers();
    } catch (error) {
      _submitError = error;
      rethrow;
    } finally {
      _submitting = false;
      _notify();
    }
  }

  // ---- housekeeping ------------------------------------------------------------

  void _resetTimers() {
    _saveTimer?.cancel();
    _retryTimer?.cancel();
    _saveTimer = null;
    _retryTimer = null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _resetTimers();
    super.dispose();
  }
}
