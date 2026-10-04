import 'dart:convert';

import '../models/oqb_page_state.dart';

typedef PageStateCallback = void Function(OqbPageState state);

class OqbBridge {
  OqbBridge({required this.onPageState});

  final PageStateCallback onPageState;

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
}
