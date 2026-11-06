import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/oqb_trial.dart';

/// Only explicitly selected question data goes to ChatGPT. OQB asset URLs,
/// session tokens, cookies and local handwriting are never attached.
class AskAiPrompt {
  const AskAiPrompt(this.text);
  static const int maxLinkPromptLength = 6000;
  final String text;

  Uri get chatGptUri {
    final complete = Uri.https('chatgpt.com', '/', {'q': text});
    if (complete.toString().length <= maxLinkPromptLength) return complete;
    return Uri.https('chatgpt.com', '/', {
      'q': 'The full question, options, my answer and the correct answer are '
          'on my clipboard. I will paste them next. Please wait for the complete question.',
    });
  }

  static AskAiPrompt? forQuestion({
    required OqbQuestionContent? content,
    required OqbUserInput answer,
    required OqbUserInput? correct,
    String subject = '',
    String topic = '',
  }) {
    if (content == null || correct == null || correct.isEmpty) return null;
    final body = htmlToPlainText(content.displayContent);
    final images = content.url.isNotEmpty || _hasImage(content.content) ||
        content.choices.any((c) => c.imageUrl.isNotEmpty || _hasImage(c.html));
    final buffer = StringBuffer()
      ..writeln('I got this multiple-choice question wrong. Please explain step by step '
          'why the correct answer is right, why my answer is wrong, and the key concept I should review.')
      ..writeln('請用繁體中文解釋，保留題目的英文術語。數學題請列出完整計算步驟；'
          'ICT 程式題請逐步追蹤程式，列出每輪變數值、條件判斷及輸出。'
          '如果提供的答案與題目不一致，請指出，不要為答案強行辯護。')
      ..writeln();
    if (subject.isNotEmpty) buffer.writeln('Subject: $subject');
    if (topic.isNotEmpty) buffer.writeln('Topic: $topic');
    if (content.year.isNotEmpty) {
      buffer.writeln('Source: ${content.publisherCode.isEmpty ? '' : '${content.publisherCode} '}'
          '${content.year}${content.questionNo.isEmpty ? '' : ' Q${content.questionNo}'}');
    }
    buffer
      ..writeln()
      ..writeln('Question:')
      ..writeln(body.isEmpty ? '(The question is an image.)' : body);
    if (images) {
      buffer.writeln('(The question/options include an image; I will attach a screenshot. '
          'Do not guess unseen image content.)');
    }
    buffer.writeln();
    if (content.choices.isNotEmpty) {
      buffer.writeln('Options:');
      for (final choice in content.choices) {
        final text = htmlToPlainText(choice.displayHtml);
        final value = text.isNotEmpty ? text :
            (choice.imageUrl.isNotEmpty || _hasImage(choice.html) ? '(image)' : '(no text)');
        buffer.writeln('${choice.label}. $value');
      }
      buffer.writeln();
    }
    buffer
      ..writeln('My answer: ${_describe(answer, content)}')
      ..write('Correct answer: ${_describe(correct, content)}');
    return AskAiPrompt(buffer.toString());
  }

  static bool _hasImage(String html) => RegExp(r'<img\b', caseSensitive: false).hasMatch(html);

  static String _describe(OqbUserInput input, OqbQuestionContent content) {
    if (input.isEmpty) return '(not answered)';
    if (input.choices.isEmpty) return htmlToPlainText(input.raw ?? '');
    return input.choices.map((index) {
      if (index < 0 || index >= content.choices.length) return choiceLabel(index);
      final choice = content.choices[index];
      final text = htmlToPlainText(choice.displayHtml);
      return text.isEmpty ? choice.label : '${choice.label} ($text)';
    }).join(', ');
  }
}

/// Keeps preformatted code indentation, table cells and common math entities.
String htmlToPlainText(String html) {
  if (html.trim().isEmpty) return '';
  var text = html.replaceAll(
    RegExp(r'<(script|style)\b[^>]*>.*?</\1>', caseSensitive: false, dotAll: true), '',
  );
  final preformatted = <String>[];
  text = text.replaceAllMapped(
    RegExp(r'<(pre|code)\b[^>]*>(.*?)</\1>', caseSensitive: false, dotAll: true),
    (match) {
      final value = match[2]!
          .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
          .replaceAll(RegExp(r'<[^>]*>'), '');
      preformatted.add(_decodeEntities(value).replaceAll('\r\n', '\n'));
      return '\n@@OQB_CODE_${preformatted.length - 1}@@\n';
    },
  );
  text = text
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(td|th)>', caseSensitive: false), ' | ')
      .replaceAll(RegExp(r'</(p|div|tr|li|h[1-6]|table)>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<li\b[^>]*>', caseSensitive: false), '• ')
      .replaceAll(RegExp(r'<sup\b[^>]*>', caseSensitive: false), '^')
      .replaceAll(RegExp(r'<[^>]*>'), '');
  text = _decodeEntities(text).split('\n')
      .map((line) => line.replaceAll(RegExp(r'[ \t\u00a0]+'), ' ')
          .replaceAll(RegExp(r'\s*\|\s*$'), '').trim())
      .where((line) => line.isNotEmpty).join('\n');
  for (var i = 0; i < preformatted.length; i++) {
    text = text.replaceAll('@@OQB_CODE_$i@@', preformatted[i]);
  }
  return text;
}

const _entities = <String, String>{
  'nbsp': ' ', 'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'",
  'times': '×', 'divide': '÷', 'minus': '−', 'plusmn': '±',
  'le': '≤', 'ge': '≥', 'ne': '≠', 'deg': '°', 'hellip': '…',
  'ndash': '–', 'mdash': '—', 'lsquo': '‘', 'rsquo': '’', 'ldquo': '“', 'rdquo': '”',
};

String _decodeEntities(String text) => text.replaceAllMapped(
  RegExp(r'&(#x[0-9a-f]+|#\d+|[a-z]+);', caseSensitive: false),
  (match) {
    final name = match[1]!;
    if (!name.startsWith('#')) return _entities[name.toLowerCase()] ?? match[0]!;
    final hexadecimal = name.toLowerCase().startsWith('#x');
    final code = int.tryParse(name.substring(hexadecimal ? 2 : 1), radix: hexadecimal ? 16 : 10);
    if (code == null || code < 0 || code > 0x10ffff || (code >= 0xd800 && code <= 0xdfff)) {
      return match[0]!;
    }
    return String.fromCharCode(code);
  },
);

/// URL prefill depends on the browser/app; full clipboard text is the fallback.
Future<bool> openInChatGpt(AskAiPrompt prompt) async {
  await Clipboard.setData(ClipboardData(text: prompt.text));
  try {
    return await launchUrl(prompt.chatGptUri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
