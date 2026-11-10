import 'dart:async';
import 'dart:typed_data';
import 'package:better_oqb/src/widgets/oqb_html.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fakes.dart';

class AssetTransport extends FakeTransport {
  AssetTransport() : super((_) => envelope([]));
  int calls = 0;
  Future<Uint8List?> Function(String)? asset;
  @override
  Future<Uint8List?> fetchAsset(String url) async {
    calls++;
    return asset == null ? Uint8List(4) : await asset!(url);
  }
}

void main() {
  test('deduplicates in-flight loads and enforces byte LRU budget', () async {
    final transport = AssetTransport();
    final gate = Completer<Uint8List?>();
    transport.asset = (_) => gate.future;
    final cache = OqbAssetLoader(transport, maxBytes: 8);
    final a = cache.load('a');
    final b = cache.load('a');
    await Future<void>.delayed(Duration.zero);
    expect(transport.calls, 1);
    gate.complete(Uint8List(4));
    await Future.wait([a, b]);
    transport.asset = null;
    await cache.load('b');
    await cache.load('a');
    await cache.load('c');
    expect(cache.cachedBytes, 8);
    expect(cache.cachedEntries, 2);
    await cache.load('b');
    expect(transport.calls, 4);
  });
  test('failed assets retry and clearing ignores old in-flight results',
      () async {
    final transport = AssetTransport()..asset = (_) async => null;
    final cache = OqbAssetLoader(transport);
    await cache.load('a');
    await cache.load('a');
    expect(transport.calls, 2);
    final gate = Completer<Uint8List?>();
    transport.asset = (_) => gate.future;
    final pending = cache.load('b');
    cache.clear();
    gate.complete(Uint8List(4));
    await pending;
    expect(cache.cachedBytes, 0);
    expect(cache.cachedEntries, 0);
  });
  test('resource cache preserves exact HTML and resolves image URLs', () {
    expect(
        QuestionResourceCache.instance
            .imageUrls('<img src="/a.png"><img src="/a.png">'),
        ['https://oqb.edcity.hk/a.png']);
    expect(
        QuestionResourceCache.instance.imageUrls('<p>No images</p>'), isEmpty);
  });
}
