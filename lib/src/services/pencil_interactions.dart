import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Optional on other platforms, with native iOS interaction registration.
class PencilInteractions {
  static const _channel = MethodChannel('better_oqb/pencil');
  static final _events = StreamController<String>.broadcast();
  static int _clients = 0;
  static StreamSubscription<String> listen(void Function(String) callback) {
    if (_clients++ == 0 && defaultTargetPlatform == TargetPlatform.iOS) {
      _channel.setMethodCallHandler((call) async {
        _events.add(call.method);
      });
      unawaited(_setEnabled(true));
    }
    return _events.stream.listen(callback);
  }

  static Future<void> release(StreamSubscription<String> subscription) async {
    await subscription.cancel();
    if (--_clients == 0 && defaultTargetPlatform == TargetPlatform.iOS) {
      await _setEnabled(false);
    }
  }

  static Future<void> _setEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod<void>(enabled ? 'enable' : 'disable');
    } on MissingPluginException {
      /* Non-iOS runners and widget tests. */
    } on PlatformException {
      /* Drawing remains available without Pencil shortcuts. */
    }
  }
}
