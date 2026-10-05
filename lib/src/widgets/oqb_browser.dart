import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:webview_cef/webview_cef.dart' as cef;

import '../services/oqb_bridge.dart';

class OqbBrowserController {
  Future<dynamic> Function(String source)? _evaluate;
  final List<VoidCallback> _attachListeners = <VoidCallback>[];

  bool get isAttached => _evaluate != null;

  void _attach(Future<dynamic> Function(String source) evaluator) {
    _evaluate = evaluator;
    for (final listener in List<VoidCallback>.of(_attachListeners)) {
      listener();
    }
  }

  void _detach() {
    _evaluate = null;
  }

  void addAttachListener(VoidCallback listener) => _attachListeners.add(listener);

  /// Runs [source] in the OQB page. Returns false when no page is attached
  /// or the script evaluated to `false`. Only the API client and the legacy
  /// DOM commands below should use this; widgets must not build scripts.
  Future<bool> evaluate(String source) async {
    final evaluate = _evaluate;
    if (evaluate == null) return false;
    final result = await evaluate(source);
    return result != false;
  }

  /// Navigates the OQB page to a same-origin [path] (e.g. a question route).
  Future<bool> openPath(String path) =>
      evaluate('window.betterOqbApi ? window.betterOqbApi.navigate(${jsonEncode(path)}) : false;');

  // Legacy DOM commands used only by the compatibility question view.

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

  Future<void> clearNetworkCapture() async {
    await _evaluate?.call('window.betterOqbNetwork?.clear();');
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
  String? _apiClientScript;
  String? _networkProbeScript;
  String? _dataBridgeScript;
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
    final scripts = await Future.wait([
      rootBundle.loadString('assets/oqb_bridge.js'),
      rootBundle.loadString('assets/oqb_network_probe.js'),
      rootBundle.loadString('assets/oqb_data_bridge.js'),
      rootBundle.loadString('assets/oqb_api_client.js'),
    ]);
    if (!mounted) return;
    final bridgeScript = scripts[0];
    final networkProbeScript = scripts[1];
    final dataBridgeScript = scripts[2];
    final apiClientScript = scripts[3];
    setState(() {
      _bridgeScript = bridgeScript;
      _networkProbeScript = networkProbeScript;
      _dataBridgeScript = dataBridgeScript;
      _apiClientScript = apiClientScript;
    });
    if (_useCef) {
      await _initDesktop(
        bridgeScript,
        networkProbeScript,
        dataBridgeScript,
        apiClientScript,
      );
    }
  }

  // Injection order matters: the network probe wraps fetch first (so the
  // inspector sees API-client calls), then the API client captures that fetch,
  // then the data bridge wraps it again to observe OQB's own traffic only.
  Future<void> _initDesktop(
    String bridgeScript,
    String networkProbeScript,
    String dataBridgeScript,
    String apiClientScript,
  ) async {
    await cef.WebviewManager().initialize(userAgent: 'BetterOQB/0.1');
    final injected = cef.InjectUserScripts()
      ..add(
        cef.UserScript(
          networkProbeScript,
          cef.ScriptInjectTime.LOAD_START,
        ),
      )
      ..add(
        cef.UserScript(
          apiClientScript,
          cef.ScriptInjectTime.LOAD_START,
        ),
      )
      ..add(
        cef.UserScript(
          dataBridgeScript,
          cef.ScriptInjectTime.LOAD_START,
        ),
      )
      ..add(
        cef.UserScript(
          bridgeScript,
          cef.ScriptInjectTime.LOAD_END,
        ),
      );

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
      cef.JavascriptChannel(
        name: 'BetterOqbNetwork',
        onMessageReceived: (message) {
          widget.bridge.handleNetworkEvent(message.message);
          controller.sendJavaScriptChannelCallBack(
            false,
            '{"ok":true}',
            message.callbackId,
            message.frameId,
          );
        },
      ),
      cef.JavascriptChannel(
        name: 'BetterOqbApi',
        onMessageReceived: (message) {
          widget.bridge.handleApiClientMessage(message.message);
          controller.sendJavaScriptChannelCallBack(
            false,
            '{"ok":true}',
            message.callbackId,
            message.frameId,
          );
        },
      ),
      cef.JavascriptChannel(
        name: 'BetterOqbData',
        onMessageReceived: (message) {
          widget.bridge.handleApiData(message.message);
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
        onLoadEnd: (controller, url) async {
          await controller.executeJavaScript(bridgeScript);
          await controller.executeJavaScript(
            'window.betterOqbNetwork?.flush();',
          );
          await controller.executeJavaScript(
            'window.betterOqbApi && window.betterOqbApi.reportStatus();',
          );
        },
      ),
    );

    await controller.initialize(widget.initialUrl);
    widget.controller._attach((source) async {
      await controller.executeJavaScript(source);
      return true;
    });
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
    if (_bridgeScript == null ||
        _apiClientScript == null ||
        _networkProbeScript == null ||
        _dataBridgeScript == null) {
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
          initialUserScripts: UnmodifiableListView<UserScript>([
            UserScript(
              source: _networkProbeScript!,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
            UserScript(
              source: _apiClientScript!,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
            UserScript(
              source: _dataBridgeScript!,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
          ]),
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
            controller.addJavaScriptHandler(
              handlerName: 'betterOqbNetworkEvent',
              callback: (arguments) {
                if (arguments.isNotEmpty) {
                  widget.bridge.handleNetworkEvent(arguments.first);
                }
                return {'ok': true};
              },
            );
            controller.addJavaScriptHandler(
              handlerName: 'betterOqbApi',
              callback: (arguments) {
                if (arguments.isNotEmpty) {
                  widget.bridge.handleApiClientMessage(arguments.first);
                }
                return {'ok': true};
              },
            );
            controller.addJavaScriptHandler(
              handlerName: 'betterOqbApiData',
              callback: (arguments) {
                if (arguments.isNotEmpty) {
                  widget.bridge.handleApiData(arguments.first);
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
            await controller.evaluateJavascript(
              source: 'window.betterOqbNetwork?.flush();',
            );
            await controller.evaluateJavascript(
              source: 'window.betterOqbApi && window.betterOqbApi.reportStatus();',
            );
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
