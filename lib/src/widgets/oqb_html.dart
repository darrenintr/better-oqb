import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../services/oqb_api_client.dart';

final Uri oqbBaseUri = Uri.parse('https://oqb.edcity.hk/');

/// In-memory loader for question assets that Flutter cannot fetch directly
/// (e.g. they need the WebView's cookies). Signed URLs and bytes are kept
/// only for the current app session and never written to disk.
class OqbAssetLoader {
  OqbAssetLoader(this.transport, {this.maxEntries = 120});

  final OqbApiTransport transport;
  final int maxEntries;
  final Map<String, Future<Uint8List?>> _cache = <String, Future<Uint8List?>>{};

  Future<Uint8List?> load(String url) {
    final cached = _cache.remove(url);
    if (cached != null) {
      _cache[url] = cached; // refresh LRU position
      return cached;
    }
    final future = transport.fetchAsset(url);
    _cache[url] = future;
    while (_cache.length > maxEntries) {
      _cache.remove(_cache.keys.first);
    }
    return future;
  }

  void clear() => _cache.clear();
}

class OqbAssetScope extends InheritedWidget {
  const OqbAssetScope({super.key, required this.loader, required super.child});

  final OqbAssetLoader? loader;

  static OqbAssetLoader? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OqbAssetScope>()?.loader;

  @override
  bool updateShouldNotify(OqbAssetScope oldWidget) => loader != oldWidget.loader;
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
class OqbHtml extends StatelessWidget {
  const OqbHtml(this.html, {super.key, this.textStyle});

  final String html;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    if (html.trim().isEmpty) return const SizedBox.shrink();
    return HtmlWidget(
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
        if (width != null && width <= 160) return InlineCustomWidget(child: image);
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
    if (oldWidget.url != widget.url) _fallback = null;
  }

  void _startFallback() {
    final loader = OqbAssetScope.of(context);
    if (loader == null || _fallback != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _fallback != null) return;
      setState(() => _fallback = loader.load(widget.url));
    });
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
        onTap: () => showOqbImageViewer(context, provider, widget.semanticLabel),
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
      return _frame(Image(image: data, semanticLabel: widget.semanticLabel), data);
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
          final provider = MemoryImage(bytes);
          return _frame(
            Image(
              image: provider,
              semanticLabel: widget.semanticLabel,
              errorBuilder: (context, _, __) => _unavailable(),
            ),
            provider,
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
              child: Center(child: Image(image: provider, semanticLabel: label)),
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
