import 'package:better_oqb/src/services/ask_ai.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preformatted ICT code retains indentation and blank lines', () {
    expect(htmlToPlainText('<pre>for i in range(3):\n    if i &lt; 2:\n        print(i)\n\nprint(9)</pre>'),
        'for i in range(3):\n    if i < 2:\n        print(i)\n\nprint(9)');
  });
  test('malformed numeric entity cannot crash question conversion', () {
    expect(htmlToPlainText('x &#99999999999; y'), contains('&#99999999999;'));
  });
  test('long encoded Chinese prompts use a complete clipboard fallback', () {
    final prompt = AskAiPrompt('計算' * 2000);
    expect(prompt.chatGptUri.toString().length, lessThan(AskAiPrompt.maxLinkPromptLength));
    expect(prompt.chatGptUri.queryParameters['q'], contains('clipboard'));
    expect(prompt.text.length, 4000);
  });
}
