import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/parser.dart' as html;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/oqb_trial.dart';
import '../widgets/oqb_html.dart';
import 'ask_ai.dart';

class QuestionImageException implements Exception {
  const QuestionImageException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Keep HTML intact: moving inline formula images to the end changes maths.
class QuestionShareSection {
  const QuestionShareSection(this.label, this.htmlText, this.imageUrl,
      {this.missingImage = false});
  final String label;
  final String htmlText;
  final String imageUrl;
  final bool missingImage;

  List<String> get inlineImages => html.parseFragment(htmlText)
      .querySelectorAll('img')
      .map((image) => image.attributes['src']?.trim() ?? '')
      .toList();

  List<String> get imageSources => [
        ...inlineImages,
        if (imageUrl.isNotEmpty && !inlineImages.contains(imageUrl)) imageUrl,
      ];
}

List<QuestionShareSection> questionShareSections(OqbQuestionContent question) => [
      QuestionShareSection('Question', question.displayContent, question.url,
          missingImage: isBareFileName(question.content) && question.url.isEmpty),
      for (final choice in question.choices)
        QuestionShareSection(choice.label, choice.displayHtml, choice.imageUrl,
            missingImage: isBareFileName(choice.html) && choice.imageUrl.isEmpty),
    ];

bool questionNeedsImageShare(OqbQuestionContent question) =>
    questionShareSections(question).any((part) =>
        part.missingImage || part.imageSources.isNotEmpty ||
        html.parseFragment(part.htmlText).querySelector('svg, object, iframe') != null);

typedef QuestionImageFetcher = Future<Uint8List?> Function(String url);

Future<Uint8List?> _fetchImage(String url, OqbAssetLoader? loader) async {
  if (url.startsWith('data:image/')) {
    try { return UriData.parse(url).contentAsBytes(); } catch (_) { return null; }
  }
  final uri = Uri.tryParse(url);
  if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) return null;
  if (loader != null) {
    try {
      final bytes = await loader.load(url).timeout(const Duration(seconds: 32));
      if (bytes != null && bytes.isNotEmpty) return bytes;
    } catch (_) {
      // A signed CDN image may work directly even if WebView fetch was denied.
    }
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
  try {
    final request = await client.getUrl(uri).timeout(const Duration(seconds: 12));
    final response = await request.close().timeout(const Duration(seconds: 12));
    if (response.statusCode != HttpStatus.ok || response.contentLength > 8 * 1024 * 1024) {
      return null;
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(const Duration(seconds: 15))) {
      bytes.add(chunk);
      if (bytes.length > 8 * 1024 * 1024) return null;
    }
    return bytes.takeBytes();
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

/// Obtain real bytes, not private URLs. Fail closed if any question/choice
/// image is absent. The injectable fetcher keeps tests independent of OQB.
Future<Map<String, Uint8List>> loadQuestionShareImages(
  OqbQuestionContent question, {
  OqbAssetLoader? loader,
  QuestionImageFetcher? fetchImage,
}) async {
  final result = <String, Uint8List>{};
  var totalBytes = 0;
  for (final part in questionShareSections(question)) {
    if (part.missingImage ||
        html.parseFragment(part.htmlText).querySelector('svg, object, iframe') != null) {
      throw QuestionImageException('${part.label}: original image is unavailable or unsupported. Please attach a screenshot of the original OQB page.');
    }
    for (final source in part.imageSources) {
      if (source.isEmpty) {
        throw QuestionImageException('${part.label}: image has no source. Please attach a screenshot.');
      }
      final url = resolveOqbUrl(source);
      if (result.containsKey(url)) continue;
      if (result.length >= 32) {
        throw const QuestionImageException('Too many images to export safely. Please attach screenshots.');
      }
      Uint8List? bytes;
      try {
        bytes = await (fetchImage != null ? fetchImage(url) : _fetchImage(url, loader));
      } catch (_) {
        bytes = null;
      }
      if (bytes == null || bytes.isEmpty) {
        throw QuestionImageException('${part.label}: could not load its image. Nothing was shared. Retry, or attach an original-page screenshot.');
      }
      totalBytes += bytes.length;
      if (bytes.length > 8 * 1024 * 1024 || totalBytes > 24 * 1024 * 1024) {
        throw const QuestionImageException('Images exceed the safe export size. Please attach screenshots.');
      }
      result[url] = bytes;
    }
  }
  return result;
}

String _answerLabels(OqbUserInput answer) => answer.choices.isEmpty
    ? (answer.raw ?? '(not answered)')
    : answer.choices.map(choiceLabel).join(', ');

/// Self-contained card: instructions, complete HTML/images and both answers.
/// No handwriting, login state, signed URL or surrounding app UI is exported.
class QuestionShareCard extends StatelessWidget {
  const QuestionShareCard({super.key, required this.question, required this.answer,
    required this.correct, required this.images});
  final OqbQuestionContent question;
  final OqbUserInput answer;
  final OqbUserInput correct;
  final Map<String, Uint8List> images;

  Widget _image(String url, {double? width}) {
    final bytes = images[resolveOqbUrl(url)];
    if (bytes == null) throw const QuestionImageException('An image is missing from the export.');
    return Image.memory(bytes, width: width, fit: BoxFit.contain, gaplessPlayback: true);
  }

  Widget _html(String value) => HtmlWidget(
        value,
        baseUrl: oqbBaseUri,
        textStyle: const TextStyle(fontSize: 19, height: 1.45, color: Colors.black),
        customStylesBuilder: (element) {
          if (element.localName == 'td' || element.localName == 'th') {
            return {'border': '1px solid #888', 'padding': '4px 8px'};
          }
          return null;
        },
        customWidgetBuilder: (element) {
          if (element.localName != 'img') return null;
          final source = element.attributes['src'] ?? '';
          final width = double.tryParse((element.attributes['width'] ?? '').replaceAll('px', ''));
          final image = _image(source, width: width != null && width > 0 ? width : null);
          return width != null && width > 0 && width <= 160
              ? InlineCustomWidget(child: image) : image;
        },
        onTapUrl: (_) => true,
      );

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: DefaultTextStyle(
            style: const TextStyle(fontSize: 18, height: 1.4, color: Colors.black),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Better OQB · Explain this question', style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text('請用繁體中文逐步解釋正確答案及我的錯誤，保留英文術語。數學請列計算步驟；ICT 請追蹤每輪變數、條件和輸出。若答案與題目不符，請指出。'),
              const SizedBox(height: 12),
              Text('${question.subjectCode} · ${question.publisherCode} · Q${question.questionNo}'),
              const Divider(),
              for (final part in questionShareSections(question)) ...[
                Text(part.label, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (part.htmlText.trim().isNotEmpty) _html(part.htmlText),
                if (part.imageUrl.isNotEmpty && !part.inlineImages.contains(part.imageUrl))
                  _image(part.imageUrl),
                const SizedBox(height: 18),
              ],
              const Divider(),
              Text('My answer: ${_answerLabels(answer)}', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('Correct answer: ${_answerLabels(correct)}', style: const TextStyle(fontWeight: FontWeight.bold)),
            ]),
          ),
        ),
      );
}

Future<void> showQuestionImageShare(BuildContext context, {
  required OqbQuestionContent question,
  required OqbUserInput answer,
  required OqbUserInput correct,
  required AskAiPrompt prompt,
  OqbAssetLoader? loader,
}) async {
  await Navigator.of(context).push<void>(MaterialPageRoute(
    builder: (_) => QuestionImageSharePage(question: question, answer: answer,
      correct: correct, prompt: prompt, loader: loader),
  ));
}

class QuestionImageSharePage extends StatefulWidget {
  const QuestionImageSharePage({super.key, required this.question, required this.answer,
    required this.correct, required this.prompt, this.loader, this.fetchImage,
    this.autoShare = true});
  final OqbQuestionContent question;
  final OqbUserInput answer;
  final OqbUserInput correct;
  final AskAiPrompt prompt;
  final OqbAssetLoader? loader;
  final QuestionImageFetcher? fetchImage;
  final bool autoShare;
  @override
  State<QuestionImageSharePage> createState() => _QuestionImageSharePageState();
}

class _QuestionImageSharePageState extends State<QuestionImageSharePage> {
  final _cardKey = GlobalKey();
  final _shareKey = GlobalKey();
  Map<String, Uint8List>? _images;
  String? _error;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final images = await loadQuestionShareImages(widget.question,
          loader: widget.loader, fetchImage: widget.fetchImage);
      if (!mounted) return;
      for (final bytes in images.values) {
        Object? failure;
        await precacheImage(MemoryImage(bytes), context,
            onError: (error, stack) { failure = error; });
        if (!mounted) return;
        if (failure != null) {
          throw const QuestionImageException('An image could not be decoded. Nothing was shared. Please attach an original-page screenshot.');
        }
      }
      setState(() { _images = images; _error = null; });
      if (widget.autoShare) {
        await WidgetsBinding.instance.endOfFrame;
        if (mounted) await _share();
      }
    } catch (error) {
      if (mounted) setState(() => _error = error is QuestionImageException
          ? error.message : 'Could not prepare the full question. Nothing was shared. Please retry.');
    }
  }

  Future<void> _share() async {
    if (_images == null || _sharing) return;
    setState(() { _sharing = true; _error = null; });
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final boundary = _cardKey.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary || !boundary.hasSize) {
        throw const QuestionImageException('Question preview is not ready. Please retry.');
      }
      final ratio = math.min(2.0, math.min(12000 / boundary.size.height, 2048 / boundary.size.width));
      if (!ratio.isFinite || ratio < 1) {
        throw const QuestionImageException('Question is too long for a readable single image. Please attach screenshots.');
      }
      final image = await boundary.toImage(pixelRatio: ratio);
      Uint8List png;
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw const QuestionImageException('Could not create the question image.');
        png = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } finally {
        image.dispose();
      }
      if (png.length > 20 * 1024 * 1024) {
        throw const QuestionImageException('Exported image is too large. Please attach smaller screenshots.');
      }
      final root = await getTemporaryDirectory();
      final directory = await Directory('${root.path}/oqb-question-shares').create(recursive: true);
      // Only clean our own old exports, not the user's files or current share.
      final cutoff = DateTime.now().subtract(const Duration(days: 1));
      await for (final entry in directory.list(followLinks: false)) {
        if (entry is File && (await entry.stat()).modified.isBefore(cutoff)) {
          try { await entry.delete(); } catch (_) { /* Best-effort cache cleanup. */ }
        }
      }
      final file = File('${directory.path}/question-${DateTime.now().microsecondsSinceEpoch}.png');
      await file.writeAsBytes(png, flush: true);
      try { await Clipboard.setData(ClipboardData(text: widget.prompt.text)); } catch (_) {
        // The image itself already contains the complete request and answers.
      }
      if (!mounted) return;
      final box = _shareKey.currentContext?.findRenderObject();
      final origin = box is RenderBox && box.hasSize
          ? box.localToGlobal(Offset.zero) & box.size
          : Rect.fromCenter(center: MediaQuery.sizeOf(context).center(Offset.zero), width: 1, height: 1);
      // Image-only sharing keeps image receivers available on iOS. All task
      // instructions are in the image; the text prompt is also on the clipboard.
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        title: 'Better OQB question',
        sharePositionOrigin: origin,
      ));
    } catch (error) {
      if (mounted) setState(() => _error = error is QuestionImageException
          ? error.message : 'Could not export or open sharing. Please retry; no automatic ChatGPT upload was performed.');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
        data: ThemeData(brightness: Brightness.light, useMaterial3: true),
        child: Scaffold(
          appBar: AppBar(title: const Text('Question with images')),
          body: SafeArea(child: Column(children: [
            const Padding(padding: EdgeInsets.all(12), child: Text(
              '完整題目、選項及答案會製成圖片。分享選單有 ChatGPT 時可選它；否則先儲存到「檔案」，再到 ChatGPT 附加。文字提問亦會複製。',
            )),
            if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
            Expanded(child: _images == null
                ? Center(child: _error == null ? const CircularProgressIndicator()
                    : OutlinedButton(onPressed: () {
                        setState(() => _error = null);
                        unawaited(_load());
                      }, child: const Text('Retry loading images')))
                : SingleChildScrollView(child: Center(child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: RepaintBoundary(key: _cardKey, child: QuestionShareCard(
                      question: widget.question, answer: widget.answer,
                      correct: widget.correct, images: _images!,
                    )),
                  )))),
            Padding(padding: const EdgeInsets.all(12), child: FilledButton.icon(
              key: _shareKey,
              onPressed: _images == null || _sharing ? null : _share,
              icon: const Icon(Icons.ios_share),
              label: Text(_sharing ? 'Preparing image…' : 'Share question image'),
            )),
          ])),
        ),
      );
}
