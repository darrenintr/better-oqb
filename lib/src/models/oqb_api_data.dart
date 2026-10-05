import 'dart:convert';

import 'oqb_json.dart';

class OqbApiDataEvent {
  const OqbApiDataEvent({
    required this.timestamp,
    required this.url,
    required this.path,
    required this.method,
    required this.requestBody,
    required this.response,
  });

  final String timestamp;
  final String url;
  final String path;
  final String method;
  final String requestBody;
  final Map<String, dynamic> response;

  bool get success => response['success'] == true;
  dynamic get result => response['result'];

  Map<String, String> get form {
    if (requestBody.isEmpty) return const {};
    try {
      return Uri.splitQueryString(requestBody, encoding: utf8);
    } catch (_) {
      return const {};
    }
  }

  factory OqbApiDataEvent.fromJson(Map<String, dynamic> json) {
    final rawResponse = json['response'];
    return OqbApiDataEvent(
      timestamp: json['timestamp']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
      method: json['method']?.toString().toUpperCase() ?? 'GET',
      requestBody: json['requestBody']?.toString() ?? '',
      response: rawResponse is Map
          ? Map<String, dynamic>.from(rawResponse)
          : const <String, dynamic>{},
    );
  }
}

class OqbPackageSummary {
  const OqbPackageSummary({
    required this.id,
    required this.subjectCode,
    required this.publisherCode,
    required this.titleZh,
    required this.titleEn,
    required this.accessType,
    required this.topicCounts,
    required this.topicDifficultyCounts,
  });

  final int id;
  final String subjectCode;
  final String publisherCode;
  final String titleZh;
  final String titleEn;
  final List<String> accessType;
  final Map<String, int> topicCounts;
  final Map<String, Map<int, int>> topicDifficultyCounts;

  String get displayTitle =>
      titleZh.isNotEmpty ? titleZh : (titleEn.isNotEmpty ? titleEn : subjectCode);

  int get questionCount =>
      topicCounts.values.fold<int>(0, (sum, value) => sum + value);

  factory OqbPackageSummary.fromJson(Map<String, dynamic> json) {
    final stat = json['stat'];
    final statMap = stat is Map
        ? Map<String, dynamic>.from(stat)
        : const <String, dynamic>{};

    final topicCounts = <String, int>{};
    final rawTopicCounts = statMap['count_topic'];
    if (rawTopicCounts is Map) {
      for (final entry in rawTopicCounts.entries) {
        final value = entry.value;
        final count = value is num ? value.toInt() : int.tryParse('$value');
        if (count != null) topicCounts['${entry.key}'] = count;
      }
    }

    final difficultyCounts = <String, Map<int, int>>{};
    final rawDifficultyCounts = statMap['count_topic_difficulty'];
    if (rawDifficultyCounts is Map) {
      for (final topicEntry in rawDifficultyCounts.entries) {
        if (topicEntry.value is! Map) continue;
        final perDifficulty = <int, int>{};
        for (final entry in (topicEntry.value as Map).entries) {
          final difficulty = int.tryParse('${entry.key}');
          final count = entry.value is num
              ? (entry.value as num).toInt()
              : int.tryParse('${entry.value}');
          if (difficulty != null && count != null) {
            perDifficulty[difficulty] = count;
          }
        }
        difficultyCounts['${topicEntry.key}'] = perDifficulty;
      }
    }

    return OqbPackageSummary(
      id: _asInt(json['id']),
      subjectCode: json['subject_code']?.toString() ?? '',
      publisherCode: json['publisher_code']?.toString() ?? '',
      titleZh: json['title_zh']?.toString() ?? '',
      titleEn: json['title_en']?.toString() ?? '',
      accessType: (json['access_type'] is List)
          ? (json['access_type'] as List).map((value) => '$value').toList()
          : const <String>[],
      topicCounts: topicCounts,
      topicDifficultyCounts: difficultyCounts,
    );
  }
}

class OqbPaperSummary {
  const OqbPaperSummary({
    required this.id,
    required this.subjectCode,
    required this.title,
    required this.modeReview,
    required this.numQuestions,
    required this.timeAllowed,
    required this.isTeacher,
    this.submitted,
    this.marked,
    this.canReview,
    this.score,
    this.scoreFull,
    this.trialId,
  });

  /// Paper id (what start_trial expects).
  final int id;
  final String subjectCode;
  final String title;
  final String modeReview;
  final int numQuestions;
  final int timeAllowed;
  final bool isTeacher;
  final bool? submitted;
  final bool? marked;
  final bool? canReview;
  final num? score;
  final num? scoreFull;

  /// Present on submitted-paper rows.
  final int? trialId;

  bool get isReviewable => submitted == true && canReview != false;

  factory OqbPaperSummary.fromJson(Map<String, dynamic> json) {
    // Submitted rows carry both paper and trial ids; prefer the explicit
    // paper_id so we never pass a trial id to start_trial.
    return OqbPaperSummary(
      id: _asInt(json['paper_id'] ?? json['id']),
      subjectCode: json['subject_code']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Untitled paper',
      modeReview: json['mode_review']?.toString() ?? '',
      numQuestions: _asInt(json['num_of_questions']),
      timeAllowed: _asInt(json['time_allowed']),
      isTeacher: _asBool(json['is_teacher']) ?? false,
      submitted: _asBool(json['submitted']),
      marked: _asBool(json['marked']),
      canReview: _asBool(json['can_review']),
      score: json['score'] is num
          ? json['score'] as num
          : num.tryParse('${json['score'] ?? ''}'),
      scoreFull: json['score_full'] is num
          ? json['score_full'] as num
          : num.tryParse('${json['score_full'] ?? ''}'),
      trialId: asIntOrNull(json['trial_id']),
    );
  }
}

class OqbObservedApiState {
  const OqbObservedApiState({
    this.packages = const <OqbPackageSummary>[],
    this.availablePapers = const <OqbPaperSummary>[],
    this.presetPapersBySubject = const <String, List<OqbPaperSummary>>{},
    this.submittedPapersBySubject = const <String, List<OqbPaperSummary>>{},
  });

  final List<OqbPackageSummary> packages;
  final List<OqbPaperSummary> availablePapers;
  final Map<String, List<OqbPaperSummary>> presetPapersBySubject;
  final Map<String, List<OqbPaperSummary>> submittedPapersBySubject;

  bool get hasCatalog => packages.isNotEmpty;

  /// Distinct subject codes in package order.
  List<String> get subjects {
    final seen = <String>{};
    return [
      for (final package in packages)
        if (package.subjectCode.isNotEmpty && seen.add(package.subjectCode))
          package.subjectCode,
    ];
  }

  List<OqbPackageSummary> packagesFor(String subject) =>
      packages.where((item) => item.subjectCode == subject).toList();

  OqbObservedApiState copyWith({
    List<OqbPackageSummary>? packages,
    List<OqbPaperSummary>? availablePapers,
    Map<String, List<OqbPaperSummary>>? presetPapersBySubject,
    Map<String, List<OqbPaperSummary>>? submittedPapersBySubject,
  }) {
    return OqbObservedApiState(
      packages: packages ?? this.packages,
      availablePapers: availablePapers ?? this.availablePapers,
      presetPapersBySubject: presetPapersBySubject ?? this.presetPapersBySubject,
      submittedPapersBySubject:
          submittedPapersBySubject ?? this.submittedPapersBySubject,
    );
  }

  OqbObservedApiState withPackages(List<OqbPackageSummary> incoming) =>
      copyWith(packages: _mergePackages(packages, incoming));

  OqbObservedApiState withPreset(String subject, List<OqbPaperSummary> papers) =>
      copyWith(presetPapersBySubject: {...presetPapersBySubject, subject: papers});

  OqbObservedApiState withSubmitted(
    String subject,
    List<OqbPaperSummary> papers,
  ) =>
      copyWith(
        submittedPapersBySubject: {...submittedPapersBySubject, subject: papers},
      );

  static List<OqbPackageSummary> parsePackages(dynamic raw) => _parsePackages(raw);

  static List<OqbPaperSummary> parsePapers(dynamic raw) => _parsePapers(raw);

  /// Folds a passively observed OQB API response into the catalog.
  OqbObservedApiState apply(OqbApiDataEvent event) {
    if (!event.success) return this;
    final form = event.form;

    switch (event.path) {
      case '/api/get_usable_packages':
        return withPackages(_parsePackages(event.result));
      case '/api/load_papers':
        final papers = _parsePapers(event.result);
        if (form['criteria[to_submit]'] == '1') {
          return copyWith(availablePapers: papers);
        }
        if (form['criteria[preset]'] == '1') {
          return withPreset(form['criteria[subject_code]'] ?? '', papers);
        }
        return this;
      case '/api/load_submitted_papers':
        return withSubmitted(
          form['criteria[subject_code]'] ?? '',
          _parsePapers(event.result),
        );
    }
    return this;
  }

  static List<OqbPackageSummary> _parsePackages(dynamic raw) {
    if (raw is! List) return const <OqbPackageSummary>[];
    return raw
        .whereType<Map>()
        .map((item) => OqbPackageSummary.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  static List<OqbPackageSummary> _mergePackages(
    List<OqbPackageSummary> existing,
    List<OqbPackageSummary> incoming,
  ) {
    if (existing.isEmpty) return incoming;
    final byId = <int, OqbPackageSummary>{
      for (final item in existing) item.id: item,
    };

    return incoming.map((item) {
      final previous = byId[item.id];
      if (previous == null || item.topicCounts.isNotEmpty) return item;
      return OqbPackageSummary(
        id: item.id,
        subjectCode: item.subjectCode,
        publisherCode: item.publisherCode,
        titleZh: item.titleZh,
        titleEn: item.titleEn,
        accessType: item.accessType,
        topicCounts: previous.topicCounts,
        topicDifficultyCounts: previous.topicDifficultyCounts,
      );
    }).toList(growable: false);
  }

  static List<OqbPaperSummary> _parsePapers(dynamic raw) {
    if (raw is! List) return const <OqbPaperSummary>[];
    return raw
        .whereType<Map>()
        .map((item) => OqbPaperSummary.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }
}

int _asInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}') ?? 0;
}

bool? _asBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value?.toString().toLowerCase();
  if (text == 'true' || text == '1') return true;
  if (text == 'false' || text == '0') return false;
  return null;
}
