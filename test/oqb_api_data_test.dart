import 'package:better_oqb/src/models/oqb_api_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses usable package catalog from sanitized API data', () {
    final event = OqbApiDataEvent.fromJson({
      'timestamp': '2026-10-05T01:15:00Z',
      'url': '/api/get_usable_packages',
      'path': '/api/get_usable_packages',
      'method': 'POST',
      'requestBody': 'app=OQB&token=%5Bredacted%5D',
      'response': {
        'success': true,
        'result': [
          {
            'id': 16,
            'subject_code': 'econ',
            'publisher_code': 'HKEAA',
            'title_zh': '考評局經濟歷屆公開試試題',
            'title_en': 'HKEAA Economics Public Exam Past Paper',
            'access_type': ['school'],
            'stat': {
              'count_topic': {
                'econ_1': 76,
                'econ_5': 60,
              },
              'count_topic_difficulty': {
                'econ_5': {'1': 16, '2': 35, '3': 9},
              },
            },
          },
        ],
      },
    });

    final state = const OqbObservedApiState().apply(event);

    expect(state.packages, hasLength(1));
    expect(state.packages.single.subjectCode, 'econ');
    expect(state.packages.single.publisherCode, 'HKEAA');
    expect(state.packages.single.questionCount, 136);
    expect(state.packages.single.topicDifficultyCounts['econ_5']?[2], 35);
  });

  test('separates resumable and preset paper lists', () {
    const response = {
      'success': true,
      'result': [
        {
          'id': 1057307,
          'subject_code': 'econ',
          'title': '市場干預',
          'mode_review': 'test',
          'num_of_questions': 21,
          'time_allowed': 1740,
          'is_teacher': 1,
        },
      ],
    };

    final resumable = OqbApiDataEvent.fromJson({
      'timestamp': '',
      'url': '/api/load_papers',
      'path': '/api/load_papers',
      'method': 'POST',
      'requestBody': 'app=OQB&criteria%5Bto_submit%5D=1',
      'response': response,
    });
    final preset = OqbApiDataEvent.fromJson({
      'timestamp': '',
      'url': '/api/load_papers',
      'path': '/api/load_papers',
      'method': 'POST',
      'requestBody':
          'app=OQB&criteria%5Bpreset%5D=1&criteria%5Bsubject_code%5D=econ',
      'response': response,
    });

    final afterResumable = const OqbObservedApiState().apply(resumable);
    final afterPreset = afterResumable.apply(preset);

    expect(afterPreset.availablePapers, hasLength(1));
    expect(afterPreset.presetPapersBySubject['econ'], hasLength(1));
    expect(afterPreset.presetPapersBySubject['econ']!.single.isTeacher, isTrue);
  });

  test('keeps package statistics when a later package refresh omits stat', () {
    final rich = OqbApiDataEvent.fromJson({
      'timestamp': '',
      'url': '/api/get_usable_packages',
      'path': '/api/get_usable_packages',
      'method': 'POST',
      'requestBody': 'app=OQB&opts%5Bstat%5D=1',
      'response': {
        'success': true,
        'result': [
          {
            'id': 16,
            'subject_code': 'econ',
            'publisher_code': 'HKEAA',
            'title_zh': '經濟',
            'title_en': 'Economics',
            'access_type': ['school'],
            'stat': {
              'count_topic': {'econ_5': 60},
              'count_topic_difficulty': {
                'econ_5': {'1': 16, '2': 35, '3': 9},
              },
            },
          },
        ],
      },
    });
    final lean = OqbApiDataEvent.fromJson({
      'timestamp': '',
      'url': '/api/get_usable_packages',
      'path': '/api/get_usable_packages',
      'method': 'POST',
      'requestBody': 'app=OQB',
      'response': {
        'success': true,
        'result': [
          {
            'id': 16,
            'subject_code': 'econ',
            'publisher_code': 'HKEAA',
            'title_zh': '經濟',
            'title_en': 'Economics',
            'access_type': ['school'],
          },
        ],
      },
    });

    final state = const OqbObservedApiState().apply(rich).apply(lean);

    expect(state.packages.single.topicCounts['econ_5'], 60);
    expect(state.packages.single.topicDifficultyCounts['econ_5']?[2], 35);
  });

  test('parses submitted paper score and review capability', () {
    final event = OqbApiDataEvent.fromJson({
      'timestamp': '',
      'url': '/api/load_submitted_papers',
      'path': '/api/load_submitted_papers',
      'method': 'POST',
      'requestBody': 'app=OQB&criteria%5Bsubject_code%5D=econ',
      'response': {
        'success': true,
        'result': [
          {
            'paper_id': 2661977,
            'subject_code': 'econ',
            'title': '我的新評估',
            'mode_review': 'test',
            'num_of_questions': 1,
            'submitted': 1,
            'marked': 1,
            'score': 0,
            'score_full': 1,
            'can_review': true,
          },
        ],
      },
    });

    final state = const OqbObservedApiState().apply(event);
    final paper = state.submittedPapersBySubject['econ']!.single;

    expect(paper.id, 2661977);
    expect(paper.submitted, isTrue);
    expect(paper.marked, isTrue);
    expect(paper.canReview, isTrue);
    expect(paper.score, 0);
    expect(paper.scoreFull, 1);
  });
}
