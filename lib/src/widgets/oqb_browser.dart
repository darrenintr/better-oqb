import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:webview_cef/webview_cef.dart' as cef;

import '../services/oqb_bridge.dart';

class OqbBrowserController {
  Future<dynamic> Function(String source)? _evaluate;

  void _attach(Future<dynamic> Function(String source) evaluator) {
    _evaluate = evaluator;
  }

  void _detach() {
    _evaluate = null;
  }

  Future<void> answer(String key) async {
    await _evaluate?.call(
      'window.betterOqb?.answer(${jsonEncode(key)});',
    );
  }

  Future<void> previous() async {
    await _evaluate?.call('window.betterOqb?.previous();');
  }

  Future<void> next() async {
    await _evaluate?.call('window.betterOqb?.next();');
  }

  Future<void> submit() async {
    await _evaluate?.call('window.betterOqb?.submit();');
  }

  Future<void> back() async {
    await _evaluate?.call('window.betterOqb?.back();');
  }

  Future<void> refreshSnapshot() async {
    await _evaluate?.call('window.betterOqb?.snapshot();');
  }
}

class OqbBrowser extends StatefulWidget {
  const OqbBrowser({
    super.key,
    required this.bridge,
    required this.controller,
    this.initialUrl = 'https://oqb.edcity.hk',
  });

  final OqbBridge bridge;
  final OqbBrowserController controller;
  final String initialUrl;

  @override
  State<OqbBrowser> createState() => _OqbBrowserState();
}

class _OqbBrowserState extends State<OqbBrowser> {
  String? _bridgeScript;
  cef.WebViewController? _desktopController;
  bool _desktopReady = false;
  String? _mobileLoadError;
  int _mobileProgress = 0;

  bool get _useCef => Platform.isLinux;

  @override
  void initState() {
    super.initState();
    _loadBridge();
  }

  Future<void> _loadBridge() async {
    final script = await rootBundle.loadString('assets/oqb_bridge.js');
    if (!mounted) return;
    setState(() => _bridgeScript = script);
    if (_useCef) {
      await _initDesktop(script);
    }
  }

  Future<void> _initDesktop(String script) async {
    await cef.WebviewManager().initialize(userAgent: 'BetterOQB/0.1');
    final injected = cef.InjectUserScripts()
      ..add(cef.UserScript(script, cef.ScriptInjectTime.LOAD_END));

    final controller = cef.WebviewManager().createWebView(
      loading: const Center(child: CircularProgressIndicator()),
      injectUserScripts: injected,
    );

    controller.setJavaScriptChannels({
      cef.JavascriptChannel(
        name: 'BetterOqb',
        onMessageReceived: (message) {
          widget.bridge.handleMessage(message.message);
          controller.sendJavaScriptChannelCallBack(
            false,
            '{"ok":true}',
            message.callbackId,
            message.frameId,
          );
        },
      ),
    });

    controller.setWebviewListener(
      cef.WebviewEventsListener(
        onLoadEnd: (controller, url) => controller.executeJavaScript(script),
      ),
    );

    await controller.initialize(widget.initialUrl);
    widget.controller._attach(
      (source) => controller.executeJavaScript(source),
    );
    if (!mounted) {
      controller.dispose();
      return;
    }

    setState(() {
      _desktopController = controller;
      _desktopReady = true;
    });
  }

  @override
  void dispose() {
    widget.controller._detach();
    _desktopController?.dispose();
    if (_useCef) {
      cef.WebviewManager().quit();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_bridgeScript == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_useCef) {
      final controller = _desktopController;
      if (!_desktopReady || controller == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return ValueListenableBuilder<bool>(
        valueListenable: controller,
        builder: (context, ready, _) =>
            ready ? controller.webviewWidget : controller.loadingWidget,
      );
    }

    return Stack(
      children: [
        InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri(widget.initialUrl)),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            domStorageEnabled: true,
            databaseEnabled: true,
            thirdPartyCookiesEnabled: true,
            sharedCookiesEnabled: true,
          ),
          onWebViewCreated: (controller) {
            widget.controller._attach(
              (source) => controller.evaluateJavascript(source: source),
            );
            controller.addJavaScriptHandler(
              handlerName: 'betterOqbPageState',
              callback: (arguments) {
                if (arguments.isNotEmpty) {
                  widget.bridge.handleMessage(arguments.first);
                }
                return {'ok': true};
              },
            );
          },
          onLoadStart: (_, __) {
            if (mounted) {
              setState(() {
                _mobileLoadError = null;
                _mobileProgress = 0;
              });
            }
          },
          onProgressChanged: (_, progress) {
            if (mounted) setState(() => _mobileProgress = progress);
          },
          onReceivedError: (_, request, error) {
            if (request.isForMainFrame == true && mounted) {
              setState(() {
                _mobileLoadError =
                    '${error.description} (code ${error.type.toNativeValue()})';
              });
            }
          },
          onLoadStop: (controller, _) async {
            if (mounted) setState(() => _mobileProgress = 100);
            await controller.evaluateJavascript(source: _bridgeScript!);
          },
        ),
        if (_mobileProgress > 0 && _mobileProgress < 100)
          LinearProgressIndicator(value: _mobileProgress / 100),
        if (_mobileLoadError != null)
          Positioned.fill(
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surface,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        'OQB failed to load',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _mobileLoadError!,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
