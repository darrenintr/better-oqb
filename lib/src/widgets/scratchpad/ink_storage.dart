import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../services/scratchpad_storage.dart';

/// Stages the document synchronously so a new question widget can await the
/// newest ink even while encoding/disk IO is still pending in the old widget.
class InkDocumentStorage {
  static final _pending = <(ScratchpadStorage, String), Future<String>>{};
  static final _queues = <(ScratchpadStorage, String), Future<void>>{};
  static Future<String?> read(ScratchpadStorage storage, String key) =>
      _pending[(storage, key)] ?? storage.read(key);
  static Future<void> write(
      ScratchpadStorage storage, String key, Map<String, dynamic> document) {
    final id = (storage, key);
    final encoded = (document['strokes'] as List).length >= 100
        ? compute(_encode, document)
        : Future.value(jsonEncode(document));
    _pending[id] = encoded;
    late final Future<void> next;
    next = (_queues[id] ?? Future.value())
        .catchError((Object _) {})
        .then((_) async {
      final text = await encoded;
      await storage.write(key, text);
      if (identical(_pending[id], encoded)) _pending.remove(id);
    }).whenComplete(() {
      if (identical(_queues[id], next)) _queues.remove(id);
    });
    _queues[id] = next;
    return next;
  }
}

String _encode(Map<String, dynamic> document) => jsonEncode(document);
