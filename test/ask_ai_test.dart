import 'package:better_oqb/src/models/oqb_trial.dart';
import 'package:better_oqb/src/services/ask_ai.dart';
import 'package:flutter_test/flutter_test.dart';

OqbQuestionContent question({
  String content = '<p>Which is <b>true</b> when price &gt; P<sub>e</sub>?</p>',
  String url = '',
  List<dynamic> choices = const ['<p>Surplus</p>', '<p>Shortage</p>', 'q_1_2.png', '<p>Nothing</p>'],
}) {
  return OqbQuestionContent.fromJson({
    'id': 1,
    'subject_code': 'econ',
    'publisher_code': 'HKEAA',
    'year': '2019',
    'question_no': '12',
    'content': content,
    'url': url,
    'choices': choices,
  });
}

void main() {
  group('htmlToPlainText', () {
    test('keeps lines, table cells and entities readable', () {
      expect(
        htmlToPlainText('<p>A&nbsp;&amp;&nbsp;B</p><table><tr><td>x</td><td>1</td></tr>'
            '<tr><td>y</td><td>2</td></tr></table>x<sup>2</sup>&#8805;&#x3b1;'),
        'A & B\nx | 1\ny | 2\nx^2≥α',
      );
    });

    test('drops scripts and empty markup', () {
      expect(htmlToPlainText('<script>alert(1)</script><p> </p>'), '');
    });
  });

  group('AskAiPrompt', () {
    test('includes question, options, my answer and the correct answer', () {
      final prompt = AskAiPrompt.forQuestion(
        content: question(),
        answer: const OqbUserInput([1]),
        correct: const OqbUserInput([0]),
        subject: 'Economics',
        topic: 'Market intervention',
      )!;

      expect(prompt.text, contains('Subject: Economics'));
      expect(prompt.text, contains('Topic: Market intervention'));
      expect(prompt.text, contains('Source: HKEAA 2019 Q12'));
      expect(prompt.text, contains('Which is true when price > Pe?'));
      expect(prompt.text, contains('A. Surplus\nB. Shortage\nC. (no text)\nD. Nothing'));
      expect(prompt.text, contains('My answer: B (Shortage)'));
      expect(prompt.text, endsWith('Correct answer: A (Surplus)'));
      expect(prompt.text, isNot(contains('.png')));
    });

    test('never leaks signed asset URLs and mentions images instead', () {
      const signed = 'https://oqb-assets.example/q.png?Signature=secret';
      final prompt = AskAiPrompt.forQuestion(
        content: question(content: 'q_1.png', url: signed),
        answer: OqbUserInput.empty,
        correct: const OqbUserInput([2]),
      )!;

      expect(prompt.text, isNot(contains('Signature')));
      expect(prompt.text, contains('(The question is an image.)'));
      expect(prompt.text, contains('attach a screenshot'));
      expect(prompt.text, contains('My answer: (not answered)'));
    });

    test('needs content and a correct answer', () {
      expect(
        AskAiPrompt.forQuestion(content: null, answer: OqbUserInput.empty, correct: const OqbUserInput([0])),
        isNull,
      );
      expect(
        AskAiPrompt.forQuestion(content: question(), answer: OqbUserInput.empty, correct: null),
        isNull,
      );
    });

    test('ChatGPT link pre-fills the prompt and stays bounded', () {
      final short = AskAiPrompt('Explain x & y?');
      expect(short.chatGptUri.host, 'chatgpt.com');
      expect(short.chatGptUri.queryParameters['q'], 'Explain x & y?');

      final long = AskAiPrompt('x' * 20000);
      final q = long.chatGptUri.queryParameters['q']!;
      expect(q.length, lessThan(AskAiPrompt.maxLinkPromptLength + 200));
      expect(q, contains('clipboard'));
    });
  });
}
