import 'package:flutter/foundation.dart';

class Logger {
  static bool _enabled = true;

  static void setEnabled(bool enabled) {
    _enabled = enabled;
  }

  static void log(String message) {
    if (_enabled && !kReleaseMode) {
      debugPrint(message);
    }
  }
}
