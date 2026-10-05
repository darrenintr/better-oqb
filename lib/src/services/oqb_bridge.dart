import 'dart:convert';

import '../models/oqb_api_data.dart';
import '../models/oqb_network_event.dart';
import '../models/oqb_page_state.dart';

typedef PageStateCallback = void Function(OqbPageState state);
typedef NetworkEventCallback = void Function(OqbNetworkEvent event);
typedef ApiDataCallback = void Function(OqbApiDataEvent event);
typedef ApiClientMessageCallback = void Function(Object? raw);

class OqbBridge {
  OqbBridge({
    required this.onPageState,
    this.onNetworkEvent,
    this.onApiData,
    this.onApiClientMessage,
  });

  final PageStateCallback onPageState;
  final NetworkEventCallback? onNetworkEvent;
  final ApiDataCallback? onApiData;

  /// Results/status from the same-origin API client (assets/oqb_api_client.js).
  final ApiClientMessageCallback? onApiClientMessage;

  void handleApiClientMessage(Object? raw) {
    try {
      onApiClientMessage?.call(raw);
    } catch (_) {
      // Never let a malformed client message break the browser.
    }
  }

  void handleMessage(Object? raw) {
    try {
      final dynamic decoded = raw is String ? jsonDecode(raw) : raw;
      if (decoded is! Map) return;
      onPageState(
        OqbPageState.fromJson(Map<String, dynamic>.from(decoded)),
      );
    } catch (_) {
      // OQB can change independently of this client. Invalid bridge data should
      // never make the study UI crash.
    }
  }

  void handleNetworkEvent(Object? raw) {
    try {
      final dynamic decoded = raw is String ? jsonDecode(raw) : raw;
      if (decoded is! Map) return;
      onNetworkEvent?.call(
        OqbNetworkEvent.fromJson(Map<String, dynamic>.from(decoded)),
      );
    } catch (_) {
      // Network inspection is best-effort and must never interrupt studying.
    }
  }

  void handleApiData(Object? raw) {
    try {
      final dynamic decoded = raw is String ? jsonDecode(raw) : raw;
      if (decoded is! Map) return;
      onApiData?.call(
        OqbApiDataEvent.fromJson(Map<String, dynamic>.from(decoded)),
      );
    } catch (_) {
      // Sanitized API observation is best-effort and should never interrupt
      // the authenticated OQB browser.
    }
  }
}
