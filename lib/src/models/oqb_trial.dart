import 'dart:convert';

import 'oqb_json.dart';

/// A learner's answer for one trial question, as OQB stores it in
/// `trial_question.user_input`.
///
/// For observed multiple-choice items OQB uses a JSON array of zero-based
/// choice indexes encoded as a string, e.g. `"[0]"` for the first choice.
class OqbUserInput {
  const OqbUserInput(this.choices, {this.raw});

  static const empty = OqbUserInput(<int>[]);

  /// Zero-based choice indexes.
  final List<int> choices;

  /// The original value when it was not a recognisable choice array. Kept so
  /// that unknown answer formats (e.g. long answers) are not overwritten.
  final String? raw;

  bool get isEmpty => choices.isEmpty && (raw == null || raw!.isEmpty);
  bool get isNotEmpty => !isEmpty;

  /// The single selected choice, if any.
  int? get single => choices.isEmpty ? null : choices.first;

  /// Wire format for `trial_question[i][user_input]`. An unrecognised
  /// original value is echoed back unchanged rather than replaced.
  String serialize() => raw ?? jsonEncode(choices);

  bool sameAs(OqbUserInput other) {
    if (choices.length != other.choices.length) return false;
    for (var i = 0; i < choices.length; i++) {
      if (choices[i] != other.choices[i]) return false;
    }
    return raw == other.raw;
  }

  static OqbUserInput parse(dynamic value) {
    if (value == null) return empty;
    if (value is num) return OqbUserInput(<int>[value.toInt()]);
    if (value is List) {
      final indexes = <int>[];
      for (final item in value) {
        final index = asIntOrNull(item);
        if (index == null) return OqbUserInput(const <int>[], raw: jsonEncode(value));
        indexes.add(index);
      }
      return OqbUserInput(List<int>.unmodifiable(indexes));
    }
    if (value is String) {
      final text = value.trim();
      if (text.isEmpty || text == 'null' || text == '[]') return empty;
      if (text.startsWith('[')) {
        try {
          return parse(jsonDecode(text));
        } catch (_) {}
      }
      final number = int.tryParse(text);
      if (number != null) return OqbUserInput(<int>[number]);
      return OqbUserInput(const <int>[], raw: text);
    }
    return OqbUserInput(const <int>[], raw: '$value');
  }

  @override
  String toString() => serialize();
}

final RegExp _bareFileName = RegExp(
  r'^[\w\-. ]+\.(png|jpe?g|gif|webp|svg|bmp|pdf)$',
  caseSensitive: false,
);

/// Whether [html] is nothing but an asset file name such as `q_16_0.png`.
/// OQB sends the image's file name as the text of image-only questions and
/// choices; it is not meant to be shown to learners.
bool isBareFileName(String html) {
  final text = html.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll('&nbsp;', ' ').trim();
  return text.isNotEmpty && _bareFileName.hasMatch(text);
}

String choiceLabel(int index) =>
    index >= 0 && index < 26 ? String.fromCharCode(65 + index) : '${index + 1}';

class OqbChoice {
  const OqbChoice({
    required this.index,
    required this.html,
    this.imageUrl = '',
  });

  final int index;

  /// HTML (or plain text) body of the choice.
  final String html;

  /// Optional signed asset URL. Temporary; never persist.
  final String imageUrl;

  String get label => choiceLabel(index);

  /// [html] without a placeholder file name.
  String get displayHtml => isBareFileName(html) ? '' : html;

  /// `choices[]` has not been captured with a fully known item shape, so
  /// accept strings and maps with common content keys.
  factory OqbChoice.fromJson(int index, dynamic json) {
    if (json is String || json is num) {
      return OqbChoice(index: index, html: '$json');
    }
    final map = asMap(json);
    String pick(List<String> keys) {
      for (final key in keys) {
        final value = asString(map[key]);
        if (value.isNotEmpty) return value;
      }
      return '';
    }

    return OqbChoice(
      index: index,
      html: pick(const ['content', 'html', 'text', 'label', 'title', 'value']),
      imageUrl: pick(const ['url', 'image', 'img', 'src']),
    );
  }
}

class OqbQuestionContent {
  const OqbQuestionContent({
    required this.id,
    this.qcode = '',
    this.lang = '',
    this.subjectCode = '',
    this.publisherCode = '',
    this.difficultyCode = 0,
    this.year = '',
    this.questionNo = '',
    this.itype = '',
    this.contentType = '',
    this.content = '',
    this.url = '',
    this.choices = const <OqbChoice>[],
    this.topicCodes = const <String>[],
    this.subtopicCodes = const <String>[],
    this.dimensionCodes = const <String>[],
    this.suggestedAnswer,
    this.modelAnswer = '',
    this.feedback = '',
  });

  /// Question-bank id. NOT the id used by save_trial.
  final int id;
  final String qcode;
  final String lang;
  final String subjectCode;
  final String publisherCode;
  final int difficultyCode;
  final String year;
  final String questionNo;
  final String itype;
  final String contentType;

  /// Question body HTML.
  final String content;

  /// Optional signed asset URL for the question body. Temporary.
  final String url;
  final List<OqbChoice> choices;
  final List<String> topicCodes;
  final List<String> subtopicCodes;
  final List<String> dimensionCodes;

  /// Review mode only. Same encoding as user input, e.g. `"[2]"`.
  final OqbUserInput? suggestedAnswer;
  final String modelAnswer;
  final String feedback;

  /// Observed MC questions have choices; anything else is answered in the
  /// original OQB page until its payloads are mapped.
  bool get isMultipleChoice => choices.length >= 2;

  /// [content] without a placeholder file name.
  String get displayContent => isBareFileName(content) ? '' : content;

  bool get urlLooksLikeImage {
    final lower = url.toLowerCase();
    final path = Uri.tryParse(lower)?.path ?? lower;
    return contentType.toLowerCase().contains('image') ||
        RegExp(r'\.(png|jpe?g|gif|webp|svg|bmp)$').hasMatch(path);
  }

  factory OqbQuestionContent.fromJson(Map<String, dynamic> json) {
    final choices = asList(json['choices']);
    final suggested = json['suggested_answer'];
    return OqbQuestionContent(
      id: asInt(json['id']),
      qcode: asString(json['qcode']),
      lang: asString(json['lang']),
      subjectCode: asString(json['subject_code']),
      publisherCode: asString(json['publisher_code']),
      difficultyCode: asInt(json['difficulty_code']),
      year: asString(json['year']),
      questionNo: asString(json['question_no']),
      itype: asString(json['itype']),
      contentType: asString(json['content_type']),
      content: asString(json['content']),
      url: asString(json['url']),
      choices: [
        for (var i = 0; i < choices.length; i++)
          OqbChoice.fromJson(i, choices[i]),
      ],
      topicCodes: asStringList(json['topic_code']),
      subtopicCodes: asStringList(json['subtopic_code']),
      dimensionCodes: asStringList(json['dimension_code']),
      suggestedAnswer: suggested == null ? null : OqbUserInput.parse(suggested),
      modelAnswer: asString(json['model_answer']),
      feedback: asString(json['feedback']),
    );
  }
}

class OqbTrialQuestion {
  const OqbTrialQuestion({
    required this.id,
    required this.seq,
    required this.questionId,
    this.status,
    this.timeSpent = 0,
    this.userInput = OqbUserInput.empty,
    this.question,
    this.isCorrect,
    this.score,
  });

  /// trial_question.id — the id save_trial expects.
  final int id;
  final int seq;

  /// Question-bank id (same as question.id).
  final int questionId;
  final String? status;
  final int timeSpent;
  final OqbUserInput userInput;
  final OqbQuestionContent? question;

  /// Review mode only.
  final bool? isCorrect;
  final num? score;

  OqbTrialQuestion copyWith({
    String? status,
    int? timeSpent,
    OqbUserInput? userInput,
  }) {
    return OqbTrialQuestion(
      id: id,
      seq: seq,
      questionId: questionId,
      status: status ?? this.status,
      timeSpent: timeSpent ?? this.timeSpent,
      userInput: userInput ?? this.userInput,
      question: question,
      isCorrect: isCorrect,
      score: score,
    );
  }

  factory OqbTrialQuestion.fromJson(Map<String, dynamic> json) {
    final rawQuestion = json['question'];
    final question = rawQuestion is Map
        ? OqbQuestionContent.fromJson(asMap(rawQuestion))
        : null;
    final status = json['status'];
    return OqbTrialQuestion(
      id: asInt(json['id']),
      seq: asInt(json['seq']),
      questionId: asInt(json['question_id'], question?.id ?? 0),
      status: status == null || '$status' == 'null' ? null : '$status',
      timeSpent: asInt(json['time_spent']),
      userInput: OqbUserInput.parse(json['user_input']),
      question: question,
      isCorrect: json.containsKey('is_correct') ? asBool(json['is_correct']) : null,
      score: asNum(json['score']),
    );
  }
}

class OqbPaper {
  const OqbPaper({
    required this.id,
    this.subjectCode = '',
    this.title = '',
    this.modeReview = '',
    this.timeAllowed = 0,
    this.numQuestions = 0,
  });

  final int id;
  final String subjectCode;
  final String title;
  final String modeReview;

  /// Units are not confirmed (observed values 120 and 1740).
  final int timeAllowed;
  final int numQuestions;

  factory OqbPaper.fromJson(Map<String, dynamic> json) => OqbPaper(
        id: asInt(json['id'] ?? json['paper_id']),
        subjectCode: asString(json['subject_code']),
        title: asString(json['title']),
        modeReview: asString(json['mode_review']),
        timeAllowed: asInt(json['time_allowed']),
        numQuestions: asInt(json['num_of_questions']),
      );
}

class OqbTrial {
  const OqbTrial({
    required this.id,
    this.submitted = false,
    this.marked = false,
    this.timeSpent = 0,
    this.state = const <String, dynamic>{},
    this.resume,
    this.score,
    this.scoreFull,
  });

  final int id;
  final bool submitted;
  final bool marked;
  final int timeSpent;

  /// OQB's progress state, e.g. `{"latestAccessQuestionNo": 1}`.
  final Map<String, dynamic> state;
  final bool? resume;
  final num? score;
  final num? scoreFull;

  /// One-based question number OQB last showed, if recorded.
  int get latestAccessQuestionNo => asInt(state['latestAccessQuestionNo']);

  factory OqbTrial.fromJson(Map<String, dynamic> json) => OqbTrial(
        id: asInt(json['id']),
        submitted: asBool(json['submitted']) ?? false,
        marked: asBool(json['marked']) ?? false,
        timeSpent: asInt(json['time_spent']),
        state: asMap(json['state']),
        resume: asBool(json['resume']),
        score: asNum(json['score']),
        scoreFull: asNum(json['score_full']),
      );
}

class OqbTrialParseException implements Exception {
  const OqbTrialParseException(this.message);
  final String message;

  @override
  String toString() => 'OqbTrialParseException: $message';
}

/// Parsed `start_trial` result (normal or review mode).
class OqbTrialSession {
  const OqbTrialSession({
    required this.paper,
    required this.trial,
    required this.questions,
    this.isReview = false,
  });

  final OqbPaper paper;
  final OqbTrial trial;

  /// Ordered by `seq`. Index i is shown as question number i + 1.
  final List<OqbTrialQuestion> questions;
  final bool isReview;

  int get total => questions.isNotEmpty ? questions.length : paper.numQuestions;

  /// Parses `result` of start_trial. Throws [OqbTrialParseException] when the
  /// essential ids are missing, because saving without them is impossible.
  factory OqbTrialSession.fromResult(dynamic result, {bool isReview = false}) {
    final map = asMap(result);
    final paper = OqbPaper.fromJson(asMap(map['paper']));
    final trial = OqbTrial.fromJson(asMap(map['trial']));
    if (trial.id <= 0) {
      throw const OqbTrialParseException('start_trial returned no trial id');
    }

    final questions = asMapList(map['trial_question'])
        .map(OqbTrialQuestion.fromJson)
        .where((item) => item.id > 0)
        .toList();
    final hasSeq = questions.any((item) => item.seq != 0);
    if (hasSeq) {
      // Stable sort: keep original order for equal seq values.
      final indexed = questions.asMap().entries.toList()
        ..sort((a, b) {
          final bySeq = a.value.seq.compareTo(b.value.seq);
          return bySeq != 0 ? bySeq : a.key.compareTo(b.key);
        });
      questions
        ..clear()
        ..addAll(indexed.map((entry) => entry.value));
    }

    return OqbTrialSession(
      paper: paper,
      trial: trial,
      questions: List<OqbTrialQuestion>.unmodifiable(questions),
      isReview: isReview,
    );
  }
}
