import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Small atomic local records. Callers serialize allowlisted fields only.
class LocalPreferences {
  static final instance = LocalPreferences();
  final _queues = <String, Future<void>>{};
  Future<File> _file(String name) async {
    if (!RegExp(r'^[a-z_]+$').hasMatch(name)) throw ArgumentError.value(name);
    final root = await getApplicationSupportDirectory();
    await root.create(recursive: true);
    return File('${root.path}/better_oqb_$name.json');
  }

  Future<Map<String, dynamic>?> read(String name) async {
    final pending = _queues[name];
    if (pending != null) {
      try {
        await pending;
      } catch (_) {}
    }
    final file = await _file(name);
    if (!await file.exists()) return null;
    return Map<String, dynamic>.from(
      jsonDecode(await file.readAsString()) as Map,
    );
  }

  Future<void> write(String name, Map<String, dynamic> value) {
    final text = jsonEncode(value);
    final next = (_queues[name] ?? Future<void>.value())
        .catchError((Object _) {})
        .then((_) async {
      final file = await _file(name);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(text, flush: true);
      await tmp.rename(file.path);
    });
    _queues[name] = next;
    return next;
  }
}
