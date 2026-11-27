import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Lightweight cross-platform screen keep-awake helper.
/// Uses Android's native `FLAG_KEEP_SCREEN_ON` via MethodChannel and safely
/// no-ops on platforms/tests where the channel is not registered.
class ScreenAwakeService {
  static const MethodChannel _channel = MethodChannel('partybox/wakelock');
  static bool _enabled = false;

  static void setEnabled(bool enabled) {
    if (_enabled == enabled) return;
    _enabled = enabled;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    unawaited(
      _channel
          .invokeMethod<bool>('setEnabled', {'enabled': enabled})
          .catchError((_) => null),
    );
  }
}
