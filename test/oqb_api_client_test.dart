import 'dart:convert';

import 'package:better_oqb/src/services/oqb_api_client.dart';
import 'package:better_oqb/src/services/oqb_api_requests.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<String> scripts;
  late OqbWebViewApiClient client;

  String lastId() =>
      RegExp(r'"(boqb-\d+)"').firstMatch(scripts.last)!.group(1)!;

  setUp(() {
    scripts = <String>[];
    client = OqbWebViewApiClient(runner: (source) async {
      scripts.add(source);
      return true;
    });
  });

  tearDown(() => client.dispose());

  test('correlates asynchronous results by request id', () async {
    final future = client.send(OqbRequests.startTrial(5));
    await Future<void>.delayed(Duration.zero);

    expect(scripts.single, contains('window.betterOqbApi.run('));
    expect(scripts.single, contains('"startTrial"'));
    expect(scripts.single, contains('{"id":"5"}'));

    client.handleMessage(jsonEncode({
      'type': 'result',
      'id': lastId(),
      'ok': true,
      'httpStatus': 200,
      'data': {'success': true, 'result': {'trial': {'id': 1}}},
    }));

    final response = await future;
    expect(response.result, {'trial': {'id': 1}});
    expect(response.httpStatus, 200);
  });

  test('turns success=false and JS errors into OqbApiException', () async {
    final rejected = client.send(OqbRequests.loadPapersToSubmit);
    await Future<void>.delayed(Duration.zero);
    client.handleMessage({
      'type': 'result',
      'id': lastId(),
      'ok': true,
      'data': {'success': false, 'message': 'Session expired'},
    });
    await expectLater(
      rejected,
      throwsA(isA<OqbApiException>()
          .having((e) => e.code, 'code', 'oqb_error')
          .having((e) => e.message, 'message', 'Session expired')),
    );

    final missing = client.send(OqbRequests.loadPapersToSubmit);
    await Future<void>.delayed(Duration.zero);
    client.handleMessage({
      'type': 'result',
      'id': lastId(),
      'ok': false,
      'error': {'code': 'missing_sesskey', 'message': 'No sesskey'},
    });
    await expectLater(
      missing,
      throwsA(isA<OqbApiException>().having((e) => e.code, 'code', 'missing_sesskey')),
    );
  });

  test('times out when the page never answers', () async {
    final request = OqbApiRequest(
      'getUserMeta',
      const {},
      timeout: const Duration(milliseconds: 20),
    );
    await expectLater(
      client.send(request),
      throwsA(isA<OqbApiException>().having((e) => e.code, 'code', 'timeout')),
    );
  });

  test('fails fast without an attached browser', () async {
    final detached = OqbWebViewApiClient();
    await expectLater(
      detached.send(OqbRequests.getUsablePackages),
      throwsA(isA<OqbApiException>().having((e) => e.code, 'code', 'no_browser')),
    );
    detached.dispose();
  });

  test('tracks session status and fails pending requests on page reload', () async {
    client.handleMessage({'type': 'status', 'pageInstance': 'a', 'onOqb': true, 'hasToken': true});
    expect(client.status.value.isReady, isTrue);

    final pending = client.send(OqbRequests.startTrial(1));
    await Future<void>.delayed(Duration.zero);
    client.handleMessage({'type': 'status', 'pageInstance': 'b', 'onOqb': true, 'hasToken': false});

    await expectLater(
      pending,
      throwsA(isA<OqbApiException>().having((e) => e.code, 'code', 'page_changed')),
    );
    expect(client.status.value.hasToken, isFalse);
  });

  test('ignores malformed and unknown messages', () {
    client.handleMessage('not json');
    client.handleMessage(42);
    client.handleMessage({'type': 'result', 'id': 'unknown'});
    expect(client.status.value, OqbApiSessionStatus.unknown);
  });

  test('diagnostics describe shapes without values', () async {
    final future = client.send(OqbRequests.getUsablePackages);
    await Future<void>.delayed(Duration.zero);
    client.handleMessage({
      'type': 'result',
      'id': lastId(),
      'ok': true,
      'data': {
        'success': true,
        'result': [
          {'id': 16, 'title_en': 'Secret-ish title'},
        ],
      },
    });
    await future;
    final log = client.diagnostics.value.join('\n');
    expect(log, contains('getUsablePackages'));
    expect(log, contains('title_en'));
    expect(log, isNot(contains('Secret-ish title')));
  });
}
