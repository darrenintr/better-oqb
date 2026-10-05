import 'dart:async';

import 'package:better_oqb/src/services/oqb_api_client.dart';
import 'package:better_oqb/src/services/oqb_api_requests.dart';
import 'package:flutter/foundation.dart';

typedef FakeHandler = FutureOr<dynamic> Function(OqbApiRequest request);

/// Records requests and answers them from [handler]. Returning an
/// [OqbApiException] (or throwing) fails the request.
class FakeTransport implements OqbApiTransport {
  FakeTransport(this.handler);

  FakeHandler handler;
  final List<OqbApiRequest> requests = <OqbApiRequest>[];
  final ValueNotifier<OqbApiSessionStatus> _status = ValueNotifier(
    const OqbApiSessionStatus(onOqb: true, hasToken: true, pageInstance: 'p1'),
  );

  @override
  ValueListenable<OqbApiSessionStatus> get status => _status;

  set statusValue(OqbApiSessionStatus value) => _status.value = value;

  List<OqbApiRequest> commands(String command) =>
      requests.where((request) => request.command == command).toList();

  @override
  Future<OqbApiResponse> send(OqbApiRequest request) async {
    requests.add(request);
    final data = await handler(request);
    if (data is OqbApiException) throw data;
    return OqbApiResponse(data: data);
  }

  @override
  Future<Uint8List?> fetchAsset(String url) async => null;
}

Map<String, dynamic> envelope(dynamic result) => {'success': true, 'result': result};

/// start_trial result modelled on the captured shape in docs/OQB_API_MAP.md.
/// Trial question ids (9000+) deliberately differ from question ids (500+).
Map<String, dynamic> startTrialResult({
  int paperId = 2658825,
  int trialId = 77,
  int count = 3,
  Map<String, dynamic>? state,
  bool review = false,
  List<dynamic>? userInputs,
}) {
  return {
    'paper': {
      'id': paperId,
      'subject_code': 'econ',
      'title': 'Market intervention',
      'mode_review': 'test',
      'time_allowed': 120,
      'num_of_questions': count,
    },
    'trial': {
      'id': trialId,
      'submitted': review ? 1 : 0,
      'marked': review ? 1 : 0,
      'time_spent': 30,
      'state': state ?? {'latestAccessQuestionNo': 1},
      'resume': 1,
      // The real client strips this before Flutter sees it; included here to
      // prove Dart never depends on it.
    },
    'trial_question': [
      for (var i = count - 1; i >= 0; i--)
        {
          'id': 9000 + i,
          'seq': i + 1,
          'question_id': 500 + i,
          'status': null,
          'time_spent': 0,
          'user_input': userInputs != null && i < userInputs.length ? userInputs[i] : null,
          if (review) 'is_correct': i.isEven ? 1 : 0,
          if (review) 'score': i.isEven ? 1 : 0,
          'question': {
            'id': 500 + i,
            'qcode': 'Q$i',
            'subject_code': 'econ',
            'publisher_code': 'HKEAA',
            'difficulty_code': (i % 3) + 1,
            'year': '2019',
            'question_no': '${i + 1}',
            'itype': 'mc',
            'content_type': 'html',
            'content': '<p>Question <b>${i + 1}</b></p>',
            'url': '',
            'choices': ['<p>A$i</p>', '<p>B$i</p>', '<p>C$i</p>', '<p>D$i</p>'],
            'topic_code': ['econ_${(i % 2) + 1}'],
            'subtopic_code': ['econ_${(i % 2) + 1}_1'],
            'dimension_code': <String>[],
            if (review) 'suggested_answer': '[2]',
            if (review) 'model_answer': '<p>Because C.</p>',
            if (review) 'feedback': '',
          },
        },
    ],
  };
}
