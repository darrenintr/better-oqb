import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:better_oqb/src/models/oqb_trial.dart';
import 'package:better_oqb/src/services/ask_ai.dart';
import 'package:better_oqb/src/services/ask_ai_images.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

final pixel = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAIAAAAmkwkpAAAAFElEQVR4nGP8//8/AwwwMSAB3BwAlm4DBfIlvvkAAAAASUVORK5CYII=');

OqbQuestionContent imageQuestion() => OqbQuestionContent.fromJson({
  'id': 535,
  'subject_code': 'math',
  'publisher_code': 'MERS',
  'question_no': '535',
  'content': 'question.png',
  'url': 'https://assets.example/question.png?Signature=private',
  'choices': [
    for (final label in ['A', 'B', 'C', 'D'])
      {'content': '$label.png', 'url': 'https://assets.example/$label.png?Signature=private'},
  ],
});

void main() {
  test('all-image question takes the attachment path, text-only does not', () {
    expect(questionNeedsImageShare(imageQuestion()), isTrue);
    expect(questionNeedsImageShare(const OqbQuestionContent(id: 1,
      content: '<p>2 + 2 = ?</p>',
      choices: [OqbChoice(index: 0, html: '4'), OqbChoice(index: 1, html: '5')],
    )), isFalse);
  });

  test('extracts body and all four choices in original order', () {
    final parts = questionShareSections(imageQuestion());
    expect(parts.map((part) => part.label), ['Question', 'A', 'B', 'C', 'D']);
    expect(parts.expand((part) => part.imageSources).length, 5);
    expect(parts.every((part) => !part.missingImage), isTrue);
    expect(parts.every((part) => part.htmlText.isEmpty), isTrue);
  });

  test('inline formula markup stays between its surrounding text', () {
    const source = '<p>2 + <img width="40" src="/formula.png?a=1&amp;b=2"> = ?</p>';
    final parts = questionShareSections(const OqbQuestionContent(id: 2, content: source));
    expect(parts.first.htmlText, source);
    expect(parts.first.inlineImages, ['/formula.png?a=1&b=2']);
  });

  test('loads actual bytes for every question and option image', () async {
    final requested = <String>[];
    final images = await loadQuestionShareImages(imageQuestion(), fetchImage: (url) async {
      requested.add(url);
      return pixel;
    });
    expect(requested.length, 5);
    expect(images.length, 5);
    expect(images.values.every((value) => identical(value, pixel)), isTrue);
    expect(requested.last, contains('/D.png'));
  });

  test('deduplicates repeated inline URLs after resolving them', () async {
    var requests = 0;
    final images = await loadQuestionShareImages(const OqbQuestionContent(
      id: 3,
      content: '<img src="/same.png"><img src="/same.png">',
      url: 'https://oqb.edcity.hk/same.png',
    ), fetchImage: (_) async { requests++; return pixel; });
    expect(requests, 1);
    expect(images.keys.single, 'https://oqb.edcity.hk/same.png');
  });

  test('missing filename-only source refuses incomplete export', () async {
    var called = false;
    await expectLater(loadQuestionShareImages(const OqbQuestionContent(
      id: 4, content: 'missing.png',
    ), fetchImage: (_) async { called = true; return pixel; }),
      throwsA(isA<QuestionImageException>()));
    expect(called, isFalse);
  });

  test('one failed choice prevents sharing only the remaining images', () async {
    await expectLater(loadQuestionShareImages(imageQuestion(), fetchImage: (url) async {
      return url.contains('/B.png') ? null : pixel;
    }), throwsA(isA<QuestionImageException>().having((e) => e.message, 'section', startsWith('B:'))));
  });

  test('source-less HTML image is not silently discarded', () async {
    await expectLater(loadQuestionShareImages(const OqbQuestionContent(
      id: 5, content: '<p>Find x.</p><img alt="diagram">',
    ), fetchImage: (_) async => pixel), throwsA(isA<QuestionImageException>()));
  });

  test('unsupported embedded media requests a screenshot instead', () async {
    const question = OqbQuestionContent(id: 6, content: '<svg><path d="M0 0"/></svg>');
    expect(questionNeedsImageShare(question), isTrue);
    await expectLater(loadQuestionShareImages(question, fetchImage: (_) async => pixel),
      throwsA(isA<QuestionImageException>()));
  });

  test('prompt still never exposes signed asset URLs', () {
    final prompt = AskAiPrompt.forQuestion(content: imageQuestion(),
      answer: const OqbUserInput([1]), correct: const OqbUserInput([0]))!;
    expect(prompt.text, isNot(contains('Signature')));
    expect(prompt.text, contains('My answer: B'));
    expect(prompt.text, contains('Correct answer: A'));
  });

  testWidgets('export card contains all images, choices and both answer labels', (tester) async {
    final question = imageQuestion();
    final images = await loadQuestionShareImages(question, fetchImage: (_) async => pixel);
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: RepaintBoundary(key: boundaryKey, child: QuestionShareCard(
        question: question, answer: const OqbUserInput([1]),
        correct: const OqbUserInput([0]), images: images,
      )),
    ))));
    await tester.runAsync(() async {
      await precacheImage(MemoryImage(pixel), tester.element(find.byType(QuestionShareCard)));
    });
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNWidgets(5));
    for (final label in ['Question', 'A', 'B', 'C', 'D']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('My answer: B'), findsOneWidget);
    expect(find.text('Correct answer: A'), findsOneWidget);
    expect(find.text('(image)'), findsNothing);
    expect(tester.takeException(), isNull);

    final boundary = boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final png = await tester.runAsync<Uint8List>(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      try {
        expect(image.height, boundary.size.height.ceil());
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List();
      } finally { image.dispose(); }
    });
    expect(png!.take(8).toList(), [137, 80, 78, 71, 13, 10, 26, 10]);
  });

  testWidgets('load failure displays retry and disables image sharing', (tester) async {
    await tester.pumpWidget(MaterialApp(home: QuestionImageSharePage(
      question: imageQuestion(), answer: const OqbUserInput([1]),
      correct: const OqbUserInput([0]), prompt: const AskAiPrompt('Explain'),
      autoShare: false, fetchImage: (_) async => null,
    )));
    await tester.pumpAndSettle();
    expect(find.text('Retry loading images'), findsOneWidget);
    expect(find.textContaining('Nothing was shared.'), findsOneWidget);
    final share = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Share question image'));
    expect(share.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
}
