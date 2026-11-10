import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Local-only storage; handwritten working is never uploaded to OQB.
abstract class ScratchpadStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class FileScratchpadStorage implements ScratchpadStorage {
  FileScratchpadStorage({Future<Directory> Function()? directory})
      : _directory = directory ?? getApplicationSupportDirectory;

  static final instance = FileScratchpadStorage();
  final Future<Directory> Function() _directory;
  final _latest = <String, String>{};
  final _queues = <String, Future<void>>{};

  Future<File> _file(String key) async {
    if (!RegExp(r'^\d+_\d+$').hasMatch(key)) {
      throw ArgumentError.value(key, 'key', 'Expected paper_question IDs');
    }
    final root = await _directory();
    final folder = Directory('${root.path}/better_oqb_working');
    await folder.create(recursive: true);
    return File('${folder.path}/$key.json');
  }

  @override
  Future<String?> read(String key) async {
    if (_latest.containsKey(key)) return _latest[key];
    final file = await _file(key);
    final text = await file.exists() ? await file.readAsString() : null;
    // An edit may have been queued while the disk read was pending.
    if (_latest.containsKey(key)) return _latest[key];
    return text;
  }

  @override
  Future<void> write(String key, String value) {
    // Immediate cache prevents a rapid question switch from reloading stale ink.
    _latest[key] = value;
    final previous = _queues[key] ?? Future<void>.value();
    late final Future<void> next;
    next = previous.catchError((Object _) {}).then((_) async {
      final destination = await _file(key);
      final temporary = File('${destination.path}.tmp');
      await temporary.writeAsString(value, flush: true);
      // Atomic replacement preserves the previous completed document on failure.
      await temporary.rename(destination.path);
      if (_latest[key] == value) _latest.remove(key);
    }).whenComplete(() {
      if (identical(_queues[key], next)) _queues.remove(key);
    });
    _queues[key] = next;
    return next;
  }
}
