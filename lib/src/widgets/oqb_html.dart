import 'dart:async';

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;

import '../models/oqb_trial.dart';
import '../services/performance_metrics.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../services/oqb_api_client.dart';

final Uri oqbBaseUri = Uri.parse('https://oqb.edcity.hk/');

/// In-memory loader for question assets that Flutter cannot fetch directly
/// (e.g. they need the WebView's cookies). Signed URLs and bytes are kept
/// only for the current app session and never written to disk.
class OqbAssetLoader {
  OqbAssetLoader(
    this.transport, {
    this.maxEntries = 120,
    this.maxBytes = 32 * 1024 * 1024,
    this.maxConcurrent = 3,
  })  : assert(maxEntries > 0),
        assert(maxBytes >= 0),
        assert(maxConcurrent > 0);
  final OqbApiTransport transport;
  final int maxEntries;
  final int maxBytes;
  final int maxConcurrent;
  int _running = 0;
  final _waiters = <Completer<void>>[];
  Future<void> _acquire() async {
    if (_running < maxConcurrent) {
      _running++;
      return;
    }
    final gate = Completer<void>();
    _waiters.add(gate);
    await gate.future;
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
    } else {
      _running--;
    }
  }

  int _bytes = 0;
  int _generation = 0;
  final _cache = <String, Uint8List>{};
  final _pending = <String, Future<Uint8List?>>{};
  int get cachedBytes => _bytes;
  int get cachedEntries => _cache.length;
  Future<Uint8List?> load(String url) {
    final cached = _cache.remove(url);
    if (cached != null) {
      _cache[url] = cached;
      return Future.value(cached);
    }
    return _pending[url] ??= _fetch(url);
  }

  Future<Uint8List?> _fetch(String url) async {
    final generation = _generation;
    await _acquire();
    try {
      if (generation != _generation) return null;
      final bytes = await PerformanceMetrics.instance
          .measure('Image fetch', () => transport.fetchAsset(url));
      if (generation == _generation &&
          bytes != null &&
          bytes.isNotEmpty &&
          bytes.length <= maxBytes) {
        _cache[url] = bytes;
        _bytes += bytes.length;
        while (_bytes > maxBytes || _cache.length > maxEntries) {
          _bytes -= _cache.remove(_cache.keys.first)!.length;
        }
      }
      return bytes;
    } finally {
      _release();
      if (generation == _generation) _pending.remove(url);
    }
  }

  void clear() {
    _generation++;
    _cache.clear();
    _pending.clear();
    _bytes = 0;
  }
}

/// Bounded parsed resource cache keyed by exact HTML, avoiding hash collisions.
class QuestionResourceCache {
  static final instance = QuestionResourceCache();
  final _urls = <String, List<String>>{};
  List<String> imageUrls(String html) {
    final cached = _urls.remove(html);
    if (cached != null) {
      _urls[html] = cached;
      return cached;
    }
    final urls = html_parser
        .parseFragment(html)
        .querySelectorAll('img')
        .map((e) => resolveOqbUrl(e.attributes['src'] ?? ''))
        .where((s) => s.isNotEmpty && !s.startsWith('data:'))
        .toSet()
        .toList();
    _urls[html] = urls;
    while (_urls.length > 24) {
      _urls.remove(_urls.keys.first);
    }
    return urls;
  }
}

Future<void> preloadQuestion(
  BuildContext context,
  OqbTrialQuestion question,
  OqbAssetLoader? loader,
) async {
  final content = question.question;
  if (content == null || loader == null) return;
  final urls = <String>{
    ...QuestionResourceCache.instance.imageUrls(content.displayContent),
    if (content.urlLooksLikeImage) resolveOqbUrl(content.url),
    for (final choice in content.choices) ...[
      ...QuestionResourceCache.instance.imageUrls(choice.displayHtml),
      if (choice.imageUrl.isNotEmpty) resolveOqbUrl(choice.imageUrl),
    ],
  }.take(8);
  // Two concurrent fetch/decode operations at most.
  final queue = urls.toList();
  Future<void> worker() async {
    while (queue.isNotEmpty && context.mounted) {
      final url = queue.removeAt(0);
      try {
        final bytes = await loader.load(url);
        if (bytes != null && context.mounted) {
          await precacheImage(
            ResizeImage.resizeIfNeeded(1600, null, MemoryImage(bytes)),
            context,
          );
        }
      } catch (_) {
        /* Speculative failures are retried when displayed. */
      }
    }
  }

  await Future.wait([worker(), worker()]);
}

class OqbAssetScope extends InheritedWidget {
  const OqbAssetScope({super.key, required this.loader, required super.child});

  final OqbAssetLoader? loader;

  static OqbAssetLoader? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OqbAssetScope>()?.loader;

  @override
  bool updateShouldNotify(OqbAssetScope oldWidget) =>
      loader != oldWidget.loader;
}

String resolveOqbUrl(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty || trimmed.startsWith('data:')) return trimmed;
  try {
    return oqbBaseUri.resolve(trimmed).toString();
  } catch (_) {
    return trimmed;
  }
}

/// Renders OQB question/choice HTML, preserving tables, formatting and
/// images. Images are zoomable and fall back to loading through the WebView.
class OqbHtml extends StatefulWidget {
  const OqbHtml(this.html, {super.key, this.textStyle});

  final String html;
  final TextStyle? textStyle;

  @override
  State<OqbHtml> createState() => _OqbHtmlState();
}

class _OqbHtmlState extends State<OqbHtml> {
  Widget? _rendered;
  @override
  void didUpdateWidget(OqbHtml old) {
    super.didUpdateWidget(old);
    if (old.html != widget.html || old.textStyle != widget.textStyle) {
      _rendered = null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rendered = null;
  }

  @override
  Widget build(BuildContext context) {
    final html = widget.html;
    final textStyle = widget.textStyle;
    if (html.trim().isEmpty) return const SizedBox.shrink();
    if (_rendered == null && PerformanceMetrics.enabled) {
      final clock = Stopwatch()..start();
      WidgetsBinding.instance.addPostFrameCallback((_) => PerformanceMetrics
          .instance
          .record('HTML first frame', clock.elapsedMicroseconds / 1000));
    }
    return _rendered ??= HtmlWidget(
      html,
      baseUrl: oqbBaseUri,
      textStyle: textStyle,
      customStylesBuilder: (element) {
        if (element.localName == 'table') {
          return const {'border-collapse': 'collapse'};
        }
        if (element.localName == 'td' || element.localName == 'th') {
          return const {'border': '1px solid #9e9e9e', 'padding': '4px 8px'};
        }
        return null;
      },
      customWidgetBuilder: (element) {
        if (element.localName != 'img') return null;
        final src = element.attributes['src'] ?? '';
        if (src.isEmpty) return null;
        final width = double.tryParse(
          (element.attributes['width'] ?? '').replaceAll('px', ''),
        );
        final image = OqbImage(
          url: resolveOqbUrl(src),
          semanticLabel: element.attributes['alt'],
          preferredWidth: width,
        );
        // Small images (inline formulas, symbols) stay in the text flow.
        if (width != null && width <= 160) {
          return InlineCustomWidget(child: image);
        }
        return image;
      },
      // Links inside questions must not navigate the authenticated browser.
      onTapUrl: (_) => true,
    );
  }
}

/// Network image with WebView fallback, tap-to-zoom and graceful failure.
class OqbImage extends StatefulWidget {
  const OqbImage({
    super.key,
    required this.url,
    this.semanticLabel,
    this.preferredWidth,
  });

  final String url;
  final String? semanticLabel;
  final double? preferredWidth;

  @override
  State<OqbImage> createState() => _OqbImageState();
}

class _OqbImageState extends State<OqbImage> {
  Future<Uint8List?>? _fallback;

  ImageProvider? get _dataProvider {
    final url = widget.url;
    if (!url.startsWith('data:')) return null;
    try {
      return MemoryImage(UriData.parse(url).contentAsBytes());
    } catch (_) {
      return null;
    }
  }

  @override
  void didUpdateWidget(OqbImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      final loader = OqbAssetScope.of(context);
      _fallback = loader == null || widget.url.startsWith('data:')
          ? null
          : loader.load(widget.url);
    }
  }

  void _startFallback() {
    final loader = OqbAssetScope.of(context);
    if (loader == null || _fallback != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _fallback != null) return;
      setState(() => _fallback = loader.load(widget.url));
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final loader = OqbAssetScope.of(context);
    if (loader != null && !widget.url.startsWith('data:')) {
      _fallback ??= loader.load(widget.url);
    }
  }

  Widget _frame(Widget image, ImageProvider provider) {
    Widget child = image;
    if (widget.preferredWidth != null) {
      child = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.preferredWidth!),
        child: child,
      );
    }
    return MouseRegion(
      cursor: SystemMouseCursors.zoomIn,
      child: GestureDetector(
        onTap: () =>
            showOqbImageViewer(context, provider, widget.semanticLabel),
        child: child,
      ),
    );
  }

  Widget _unavailable() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, color: theme.colorScheme.outline),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Image unavailable. Open the original OQB page to view it.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _dataProvider;
    if (data != null) {
      return _frame(
        Image(image: data, semanticLabel: widget.semanticLabel),
        data,
      );
    }

    final fallback = _fallback;
    if (fallback != null) {
      return FutureBuilder<Uint8List?>(
        future: fallback,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox(
              height: 48,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          final bytes = snapshot.data;
          if (bytes == null || bytes.isEmpty) return _unavailable();
          final provider = ResizeImage.resizeIfNeeded(
            1600,
            null,
            MemoryImage(bytes),
          );
          return _frame(
            Image(
              image: provider,
              semanticLabel: widget.semanticLabel,
              errorBuilder: (context, _, __) => _unavailable(),
            ),
            MemoryImage(bytes),
          );
        },
      );
    }

    final provider = NetworkImage(widget.url);
    return _frame(
      Image(
        image: provider,
        semanticLabel: widget.semanticLabel,
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : const SizedBox(
                height: 48,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
        errorBuilder: (context, _, __) {
          if (OqbAssetScope.of(context) == null) return _unavailable();
          _startFallback();
          return const SizedBox(height: 48);
        },
      ),
      provider,
    );
  }
}

Future<void> showOqbImageViewer(
  BuildContext context,
  ImageProvider provider,
  String? label,
) {
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 6,
              child: Center(
                child: Image(image: provider, semanticLabel: label),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: SafeArea(
              child: IconButton.filledTonal(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
