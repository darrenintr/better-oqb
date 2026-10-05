import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/oqb_json.dart';
import 'oqb_api_requests.dart';

/// Runs a JavaScript snippet in the authenticated OQB WebView. Returns false
/// when no WebView is attached.
typedef OqbScriptRunner = Future<bool> Function(String source);

class OqbApiException implements Exception {
  const OqbApiException(this.code, this.message, {this.httpStatus});

  /// Machine-readable reason, e.g. `not_authenticated`, `missing_sesskey`,
  /// `timeout`, `oqb_error`, `network`.
  final String code;
  final String message;
  final int? httpStatus;

  bool get isAuth => code == 'not_authenticated' || httpStatus == 401 || httpStatus == 403;

  @override
  String toString() => message.isEmpty ? code : message;
}

class OqbApiResponse {
  const OqbApiResponse({required this.data, this.httpStatus, this.elapsedMs});

  /// Sanitized JSON payload (token/sesskey/personal identifiers removed).
  final dynamic data;
  final int? httpStatus;
  final int? elapsedMs;

  dynamic get result => asMap(data)['result'];
}

/// What the JS client reports about the authenticated WebView. Contains no
/// secrets: only whether a token is available, never the token.
@immutable
class OqbApiSessionStatus {
  const OqbApiSessionStatus({
    this.pageInstance = '',
    this.onOqb = false,
    this.path = '',
    this.hasToken = false,
    this.tokenSource = '',
  });

  static const unknown = OqbApiSessionStatus();

  final String pageInstance;
  final bool onOqb;
  final String path;
  final bool hasToken;
  final String tokenSource;

  bool get isReady => onOqb && hasToken;

  factory OqbApiSessionStatus.fromJson(Map<String, dynamic> json) =>
      OqbApiSessionStatus(
        pageInstance: asString(json['pageInstance']),
        onOqb: asBool(json['onOqb']) ?? false,
        path: asString(json['path']),
        hasToken: asBool(json['hasToken']) ?? false,
        tokenSource: asString(json['tokenSource']),
      );

  @override
  bool operator ==(Object other) =>
      other is OqbApiSessionStatus &&
      other.pageInstance == pageInstance &&
      other.onOqb == onOqb &&
      other.path == path &&
      other.hasToken == hasToken &&
      other.tokenSource == tokenSource;

  @override
  int get hashCode => Object.hash(pageInstance, onOqb, path, hasToken, tokenSource);
}

/// Anything that can execute [OqbApiRequest]s. The WebView implementation is
/// [OqbWebViewApiClient]; tests use fakes.
abstract class OqbApiTransport {
  ValueListenable<OqbApiSessionStatus> get status;

  /// Resolves with the sanitized payload, or throws [OqbApiException].
  Future<OqbApiResponse> send(OqbApiRequest request);

  /// Loads an image through the WebView (for assets Flutter cannot fetch
  /// directly). Returns null on failure. Bytes are for rendering only.
  Future<Uint8List?> fetchAsset(String url);
}

class _Pending {
  _Pending(this.completer, this.label, this.started, this.envelope);
  final Completer<dynamic> completer;
  final String label;
  final DateTime started;
  final bool envelope;
}

/// Sends commands to `window.betterOqbApi` in the OQB WebView and correlates
/// asynchronous results delivered through the `betterOqbApi` JS handler.
class OqbWebViewApiClient implements OqbApiTransport {
  OqbWebViewApiClient({OqbScriptRunner? runner}) : _runner = runner;

  OqbScriptRunner? _runner;
  final Map<String, _Pending> _pending = <String, _Pending>{};
  final ValueNotifier<OqbApiSessionStatus> _status =
      ValueNotifier<OqbApiSessionStatus>(OqbApiSessionStatus.unknown);
  int _nextId = 0;

  /// Recent non-sensitive diagnostics (command, outcome, payload shape).
  final ValueNotifier<List<String>> diagnostics = ValueNotifier<List<String>>(const []);

  @override
  ValueListenable<OqbApiSessionStatus> get status => _status;

  void attach(OqbScriptRunner runner) {
    _runner = runner;
  }

  /// Asks the page to report its status again (e.g. after a page load).
  Future<void> requestStatus() async {
    await _runner?.call('window.betterOqbApi && window.betterOqbApi.reportStatus();');
  }

  void log(String line) {
    final stamp = DateTime.now().toIso8601String().substring(11, 19);
    final next = [...diagnostics.value, '$stamp $line'];
    diagnostics.value = next.length > 200 ? next.sublist(next.length - 200) : next;
    if (kDebugMode) debugPrint('[BetterOQB] $line');
  }

  @override
  Future<OqbApiResponse> send(OqbApiRequest request) async {
    final data = await _call(
      request.describe(),
      request.timeout,
      request.expectsEnvelope,
      (id) => 'window.betterOqbApi.run(${jsonEncode(id)}, '
          '${jsonEncode(request.command)}, ${jsonEncode(request.fields)});',
    );
    final message = asMap(data);
    return OqbApiResponse(
      data: message['data'],
      httpStatus: asIntOrNull(message['httpStatus']),
      elapsedMs: asIntOrNull(message['elapsedMs']),
    );
  }

  @override
  Future<Uint8List?> fetchAsset(String url) async {
    try {
      final data = await _call(
        'fetchAsset',
        const Duration(seconds: 30),
        false,
        (id) => 'window.betterOqbApi.fetchAsset(${jsonEncode(id)}, ${jsonEncode(url)});',
      );
      final dataUrl = asString(asMap(asMap(data)['data'])['dataUrl']);
      final comma = dataUrl.indexOf(',');
      if (!dataUrl.startsWith('data:') || comma < 0) return null;
      return base64Decode(dataUrl.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }

  Future<dynamic> _call(
    String label,
    Duration timeout,
    bool envelope,
    String Function(String id) script,
  ) async {
    final runner = _runner;
    if (runner == null) {
      throw const OqbApiException('no_browser', 'The OQB browser is not ready yet');
    }
    final id = 'boqb-${++_nextId}';
    final pending = _Pending(Completer<dynamic>(), label, DateTime.now(), envelope);
    _pending[id] = pending;

    final source = 'if (window.betterOqbApi) { ${script(id)} } else { false; }';
    bool dispatched;
    try {
      dispatched = await runner(source);
    } catch (_) {
      dispatched = false;
    }
    if (!dispatched) {
      _pending.remove(id);
      log('$label → not dispatched');
      throw const OqbApiException('no_browser', 'The OQB browser is not available');
    }

    try {
      return await pending.completer.future.timeout(timeout);
    } on TimeoutException {
      log('$label → timeout after ${timeout.inSeconds}s');
      throw OqbApiException('timeout', 'OQB did not respond within ${timeout.inSeconds}s');
    } finally {
      _pending.remove(id);
    }
  }

  /// Entry point for messages posted by the JS client.
  void handleMessage(Object? raw) {
    Map<String, dynamic> message;
    try {
      message = asMap(raw is String ? jsonDecode(raw) : raw);
    } catch (_) {
      return;
    }
    switch (message['type']) {
      case 'status':
        _handleStatus(OqbApiSessionStatus.fromJson(message));
      case 'result':
        _handleResult(message);
    }
  }

  void _handleStatus(OqbApiSessionStatus next) {
    final previous = _status.value;
    if (previous.pageInstance.isNotEmpty &&
        next.pageInstance.isNotEmpty &&
        previous.pageInstance != next.pageInstance &&
        _pending.isNotEmpty) {
      // A full page load destroyed the JS context; its requests can no longer
      // report back. Their outcome is unknown, so fail them for retry.
      log('page reloaded; failing ${_pending.length} pending request(s)');
      for (final pending in _pending.values.toList()) {
        if (!pending.completer.isCompleted) {
          pending.completer.completeError(
            const OqbApiException('page_changed', 'OQB reloaded before replying'),
          );
        }
      }
      _pending.clear();
    }
    if (previous != next) {
      if (previous.hasToken != next.hasToken || previous.onOqb != next.onOqb) {
        log('session: onOqb=${next.onOqb} hasToken=${next.hasToken}'
            '${next.tokenSource.isEmpty ? '' : ' (${next.tokenSource})'}');
      }
      _status.value = next;
    }
  }

  void _handleResult(Map<String, dynamic> message) {
    final id = asString(message['id']);
    final pending = _pending[id];
    if (pending == null || pending.completer.isCompleted) return;

    final elapsed = DateTime.now().difference(pending.started).inMilliseconds;
    final httpStatus = asIntOrNull(message['httpStatus']);
    final ok = asBool(message['ok']) ?? false;

    if (!ok) {
      final error = asMap(message['error']);
      final code = asString(error['code']).isEmpty
          ? 'http_${httpStatus ?? 0}'
          : asString(error['code']);
      final text = asString(error['message']).isEmpty
          ? 'OQB request failed (${httpStatus ?? 'no status'})'
          : asString(error['message']);
      log('${pending.label} → $code ($elapsed ms)');
      pending.completer.completeError(
        OqbApiException(code, text, httpStatus: httpStatus),
      );
      return;
    }

    final data = message['data'];
    if (pending.envelope) {
      final envelope = asMap(data);
      if (envelope['success'] != true) {
        final reason = _errorText(envelope);
        log('${pending.label} → success=false ${describeShape(envelope)} ($elapsed ms)');
        pending.completer.completeError(
          OqbApiException('oqb_error', reason, httpStatus: httpStatus),
        );
        return;
      }
      log('${pending.label} → ok result=${describeShape(envelope['result'])} ($elapsed ms)');
    } else {
      log('${pending.label} → ok ($elapsed ms)');
    }
    pending.completer.complete(message);
  }

  static String _errorText(Map<String, dynamic> envelope) {
    for (final key in const ['message', 'error', 'msg', 'error_msg']) {
      final value = envelope[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
      if (value is Map) {
        final nested = asString(asMap(value)['message']);
        if (nested.isNotEmpty) return nested;
      }
    }
    return 'OQB rejected the request';
  }

  void dispose() {
    for (final pending in _pending.values) {
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(
          const OqbApiException('disposed', 'Better OQB closed'),
        );
      }
    }
    _pending.clear();
    _status.dispose();
    diagnostics.dispose();
  }
}
