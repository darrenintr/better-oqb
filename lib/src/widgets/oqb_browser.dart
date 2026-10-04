import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:webview_cef/webview_cef.dart' as cef;

import '../services/oqb_bridge.dart';

class OqbBrowser extends StatefulWidget {
  const OqbBrowser({
    super.key,
    required this.bridge,
    this.initialUrl = 'https://oqb.edcity.hk',
  });

  final OqbBridge bridge;
  final String initialUrl;

  @override
  State<OqbBrowser> createState() => _OqbBrowserState();
}

class _OqbBrowserState extends State<OqbBrowser> {
  String? _bridgeScript;
  InAppWebViewController? _mobileController;
  cef.WebViewController? _desktopController;
  bool _desktopReady = false;

  bool get _useCef =>
      Platform.isLinux || Platform.isWindows || Platform.isMacOS;

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

    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(widget.initialUrl)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        useShouldOverrideUrlLoading: true,
        sharedCookiesEnabled: true,
      ),
      onWebViewCreated: (controller) {
        _mobileController = controller;
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
      onLoadStop: (controller, _) async {
        await controller.evaluateJavascript(source: _bridgeScript!);
      },
    );
  }
}
