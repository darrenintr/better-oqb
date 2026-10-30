import '../models/oqb_trial.dart';

/// Providers reached through their public websites (or installed universal-link
/// handlers). The user chooses a provider before any question leaves Better OQB.
enum AiAssistant { chatgpt, claude, gemini }

extension AiAssistantDetails on AiAssistant {
  String get displayName => switch (this) {
        AiAssistant.chatgpt => 'ChatGPT',
        AiAssistant.claude => 'Claude',
        AiAssistant.gemini => 'Gemini',
      };

  /// Gemini currently has no reliable, documented web prompt-prefill contract.
  /// Its question is copied to the clipboard instead.
  bool get supportsWebPrefill => this != AiAssistant.gemini;

  Uri linkFor(String prompt) => switch (this) {
        AiAssistant.chatgpt => Uri.https('chatgpt.com', '/', {'q': prompt}),
        AiAssistant.claude => Uri.https('claude.ai', '/new', {'q': prompt}),
        AiAssistant.gemini => Uri.https('gemini.google.com', '/app'),
      };
}

/// Build an explanation request only from question content the learner has
/// already seen. In particular, never include OQB session keys, question API
/// identifiers, authenticated asset URLs, or image URLs.
String buildAiExplanationPrompt({
  required OqbTrialQuestion question,
  required OqbUserInput userAnswer,
  required OqbUserInput? correctAnswer,
  required int questionNumber,
  required String paperTitle,
  required String subjectCode,
}) {
  final content = question.question;
  final prompt = StringBuffer()
    ..writeln('請用繁體中文（香港用語），按照 HKDSE 程度解釋我做錯的 OQB 題目。')
    ..writeln('請逐步說明正確解法、我選的答案為何錯誤，以及相關概念和常見陷阱。')
    ..writeln('如文字缺少圖片、表格或公式的關鍵資訊，請指出限制並要求我補充截圖，不要自行猜測。')
    ..writeln();

  if (subjectCode.trim().isNotEmpty) {
    prompt.writeln('科目：' + subjectCode.trim());
  }
  if (paperTitle.trim().isNotEmpty) {
    prompt.writeln('試卷：' + paperTitle.trim());
  }
  prompt.writeln('題號：' + questionNumber.toString());
  if (content != null) {
    if (content.year.isNotEmpty) {
      prompt.writeln('年份：' + content.year);
    }
    if (content.questionNo.isNotEmpty) {
      prompt.writeln('原題號：' + content.questionNo);
    }
  }
  prompt.writeln();

  final stem = _visibleText(content?.displayContent ?? '');
  prompt.writeln('題目：' + (stem.isEmpty ? '（未能從題目擷取文字，請參考截圖）' : stem));

  final choices = content?.choices ?? const <OqbChoice>[];
  if (choices.isNotEmpty) {
    prompt.writeln();
    prompt.writeln('選項：');
    for (final choice in choices) {
      final body = _visibleText(choice.displayHtml);
      prompt.writeln(
        choice.label +
            '. ' +
            (body.isEmpty ? '（圖片或非文字選項，請參考截圖）' : body),
      );
    }
  }

  prompt.writeln();
  prompt.writeln('我的答案：' + _formatInput(userAnswer, choices));

  final answerKey = correctAnswer ?? content?.suggestedAnswer ?? question.suggestedAnswer;
  if (answerKey != null && answerKey.isNotEmpty) {
    prompt.writeln('正確答案：' + _formatInput(answerKey, choices));
  } else {
    prompt.writeln('正確答案：OQB 未提供；請先根據題目推理，勿假裝已有官方答案。');
  }

  final modelAnswer = _visibleText(content?.modelAnswer ?? '');
  final feedback = _visibleText(content?.feedback ?? '');
  if (modelAnswer.isNotEmpty) {
    prompt.writeln('OQB 參考答案：' + modelAnswer);
  }
  if (feedback.isNotEmpty) {
    prompt.writeln('OQB 回饋：' + feedback);
  }

  final includesMedia = content != null &&
      (content.url.isNotEmpty ||
          _hasEmbeddedMedia(content.content) ||
          content.choices.any((choice) =>
              choice.imageUrl.isNotEmpty || _hasEmbeddedMedia(choice.html)));
  if (includesMedia) {
    prompt.writeln();
    prompt.writeln('注意：原題包含圖片或附件，未隨文字傳送。必要時請要求我手動附上截圖。');
  }

  return prompt.toString().trim();
}

String _formatInput(OqbUserInput input, List<OqbChoice> choices) {
  if (input.isEmpty) return '未作答';
  if (input.choices.isNotEmpty) {
    return input.choices.map((index) {
      final body = choices.where((choice) => choice.index == index);
      final text = body.isEmpty ? '' : _visibleText(body.first.displayHtml);
      return choiceLabel(index) + (text.isEmpty ? '' : '. ' + text);
    }).join('、');
  }
  final text = _visibleText(input.raw ?? '');
  return text.isEmpty ? '（非文字答案）' : text;
}

bool _hasEmbeddedMedia(String html) =>
    RegExp(r'<(?:img|svg|canvas|video)\b', caseSensitive: false).hasMatch(html);

/// Convert OQB HTML to readable text, with no tags, attributes, or asset URLs.
/// This deliberately does not attempt to reproduce visual mathematical layout.
String _visibleText(String html) {
  if (isBareFileName(html)) return '';

  var text = html
      .replaceAll(
        RegExp(r'<(?:script|style)\b[^>]*>.*?</(?:script|style)>',
            caseSensitive: false, dotAll: true),
        '',
      )
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(?:p|div|li|tr|table|h[1-6])\s*>',
          caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(?:td|th)\s*>', caseSensitive: false), ' | ')
      .replaceAll(RegExp(r'<[^>]*>'), '');

  text = text.replaceAllMapped(RegExp(r'&#(x[0-9a-fA-F]+|[0-9]+);'), (match) {
    final digits = match.group(1)!;
    final codePoint = digits.startsWith('x')
        ? int.tryParse(digits.substring(1), radix: 16)
        : int.tryParse(digits);
    if (codePoint == null ||
        codePoint < 0 ||
        codePoint > 0x10ffff ||
        (codePoint >= 0xd800 && codePoint <= 0xdfff)) {
      return match.group(0)!;
    }
    return String.fromCharCode(codePoint);
  });
  const entities = <String, String>{
    '&nbsp;': ' ',
    '&amp;': '&',
    '&lt;': '<',
    '&gt;': '>',
    '&quot;': '"',
    '&apos;': "'",
    '&hellip;': '…',
    '&times;': '×',
    '&divide;': '÷',
    '&minus;': '−',
  };
  for (final entry in entities.entries) {
    text = text.replaceAll(entry.key, entry.value);
  }
  return text
      .replaceAll(RegExp(r'[ \t\r\f\v]+'), ' ')
      .replaceAll(RegExp(r' *\n *'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}
