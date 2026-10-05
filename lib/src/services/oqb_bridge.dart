import 'dart:convert';

import '../models/oqb_network_event.dart';
import '../models/oqb_page_state.dart';

typedef PageStateCallback = void Function(OqbPageState state);
typedef NetworkEventCallback = void Function(OqbNetworkEvent event);

class OqbBridge {
  OqbBridge({
    required this.onPageState,
    this.onNetworkEvent,
  });

  final PageStateCallback onPageState;
  final NetworkEventCallback? onNetworkEvent;

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
}
