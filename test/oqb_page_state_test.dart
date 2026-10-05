import 'package:better_oqb/src/models/oqb_page_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses bridge snapshots defensively', () {
    final state = OqbPageState.fromJson({
      'url': 'https://oqb.edcity.hk/example',
      'title': 'OQB',
      'headings': ['Economics', 'Question 1'],
      'actions': ['A', 'B', 'Next'],
      'isLoggedIn': true,
    });

    expect(state.title, 'OQB');
    expect(state.headings, contains('Question 1'));
    expect(state.actions, contains('Next'));
    expect(state.isLoggedIn, isTrue);
  });

  test('recognises OQB question routes before DOM extraction completes', () {
    final state = OqbPageState.fromJson({
      'url': 'https://oqb.edcity.hk/paper/2658825/do/50',
      'title': 'OQB',
      'isLoggedIn': true,
    });

    expect(state.isQuestionRoute, isTrue);
    expect(state.routeQuestionNumber, 50);
    expect(state.hasQuestion, isFalse);
  });

  test('does not treat the paper chooser as a question route', () {
    final state = OqbPageState.fromJson({
      'url': 'https://oqb.edcity.hk/student/viewtest',
      'title': 'OQB',
      'isLoggedIn': true,
    });

    expect(state.isQuestionRoute, isFalse);
    expect(state.routeQuestionNumber, 0);
  });
}
