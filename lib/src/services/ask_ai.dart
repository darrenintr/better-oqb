import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/oqb_trial.dart';

/// Builds a "help me understand this question" prompt for an external chat
/// assistant (ChatGPT) from a question the learner got wrong.
///
/// Only the question text, the choices, the learner's answer and the correct
/// answer are included. Signed asset URLs are never included: they are
/// short-lived credentials for OQB's storage. Images are mentioned so the
/// learner knows to attach a screenshot.
class AskAiPrompt {
  const AskAiPrompt(this.text);

  /// ChatGPT's `?q=` link pre-fills the chat box. Very long links can be
  /// rejected or truncated, so the prompt is also copied to the clipboard and
  /// the link carries a shortened prompt when needed.
  static const int maxLinkPromptLength = 6000;

  final String text;

  Uri get chatGptUri {
    var prompt = text;
    if (prompt.length > maxLinkPromptLength) {
      prompt = '${prompt.substring(0, maxLinkPromptLength)}\n…\n'
          '(The full question is on my clipboard; I will paste it.)';
    }
    return Uri.https('chatgpt.com', '/', <String, String>{'q': prompt});
  }

  /// Returns null when the question cannot be described (no content) or no
  /// correct answer is known.
  static AskAiPrompt? forQuestion({
    required OqbQuestionContent? content,
    required OqbUserInput answer,
    required OqbUserInput? correct,
    String subject = '',
    String topic = '',
  }) {
    if (content == null || correct == null || correct.isEmpty) return null;

    final body = htmlToPlainText(content.displayContent);
    final hasImage = content.url.isNotEmpty ||
        RegExp(r'<img\b', caseSensitive: false).hasMatch(content.content);

    final buffer = StringBuffer()
      ..writeln('I got this multiple-choice question wrong. '
          'Please explain step by step why the correct answer is right, '
          'why my answer is wrong, and the key concept I should review.')
      ..writeln();
    final context = [
      if (subject.isNotEmpty) 'Subject: $subject',
      if (topic.isNotEmpty) 'Topic: $topic',
      if (content.year.isNotEmpty)
        'Source: ${content.publisherCode.isEmpty ? '' : '${content.publisherCode} '}'
            '${content.year}${content.questionNo.isEmpty ? '' : ' Q${content.questionNo}'}',
    ];
    for (final line in context) {
      buffer.writeln(line);
    }
    if (context.isNotEmpty) buffer.writeln();

    buffer.writeln('Question:');
    buffer.writeln(body.isEmpty ? '(The question is an image.)' : body);
    if (hasImage) {
      buffer.writeln('(The question has a diagram/image; I will attach a screenshot if needed.)');
    }
    buffer.writeln();

    if (content.choices.isNotEmpty) {
      buffer.writeln('Options:');
      for (final choice in content.choices) {
        final choiceText = htmlToPlainText(choice.displayHtml);
        final label = choiceText.isNotEmpty
            ? choiceText
            : (choice.imageUrl.isNotEmpty ? '(image)' : '(no text)');
        buffer.writeln('${choice.label}. $label');
      }
      buffer.writeln();
    }

    buffer.writeln('My answer: ${_describe(answer, content)}');
    buffer.write('Correct answer: ${_describe(correct, content)}');
    return AskAiPrompt(buffer.toString());
  }

  static String _describe(OqbUserInput input, OqbQuestionContent content) {
    if (input.isEmpty) return '(not answered)';
    if (input.choices.isEmpty) return htmlToPlainText(input.raw ?? '');
    return input.choices.map((index) {
      if (index < 0 || index >= content.choices.length) return choiceLabel(index);
      final choice = content.choices[index];
      final choiceText = htmlToPlainText(choice.displayHtml);
      return choiceText.isEmpty ? choice.label : '${choice.label} ($choiceText)';
    }).join(', ');
  }
}

/// Converts OQB question HTML to readable plain text: block elements become
/// line breaks, table cells are separated by " | ", tags are removed and
/// common entities decoded.
String htmlToPlainText(String html) {
  if (html.trim().isEmpty) return '';
  var text = html
      .replaceAll(RegExp(r'<(script|style)\b[^>]*>.*?</\1>', caseSensitive: false, dotAll: true), '')
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(td|th)>', caseSensitive: false), ' | ')
      .replaceAll(RegExp(r'</(p|div|tr|li|h[1-6]|table)>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<li\b[^>]*>', caseSensitive: false), '• ')
      .replaceAll(RegExp(r'<sup\b[^>]*>', caseSensitive: false), '^')
      .replaceAll(RegExp(r'<[^>]*>'), '');
  text = _decodeEntities(text);
  return text
      .split('\n')
      .map((line) => line.replaceAll(RegExp(r'[ \t ]+'), ' ').replaceAll(RegExp(r'\s*\|\s*$'), '').trim())
      .where((line) => line.isNotEmpty)
      .join('\n');
}

const Map<String, String> _entities = <String, String>{
  'nbsp': ' ',
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'times': '×',
  'divide': '÷',
  'minus': '−',
  'plusmn': '±',
  'le': '≤',
  'ge': '≥',
  'ne': '≠',
  'deg': '°',
  'hellip': '…',
  'ndash': '–',
  'mdash': '—',
  'lsquo': '‘',
  'rsquo': '’',
  'ldquo': '“',
  'rdquo': '”',
};

String _decodeEntities(String text) {
  return text.replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);'), (match) {
    final name = match[1]!;
    if (name.startsWith('#x') || name.startsWith('#X')) {
      final code = int.tryParse(name.substring(2), radix: 16);
      return code == null ? match[0]! : String.fromCharCode(code);
    }
    if (name.startsWith('#')) {
      final code = int.tryParse(name.substring(1));
      return code == null ? match[0]! : String.fromCharCode(code);
    }
    return _entities[name.toLowerCase()] ?? match[0]!;
  });
}

/// Opens [prompt] in ChatGPT in the system browser (or the ChatGPT app when
/// it handles chatgpt.com links). The prompt is copied to the clipboard first
/// so it can be pasted if the chat box is not pre-filled. Returns whether the
/// link could be opened.
Future<bool> openInChatGpt(AskAiPrompt prompt) async {
  await Clipboard.setData(ClipboardData(text: prompt.text));
  try {
    return await launchUrl(prompt.chatGptUri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
