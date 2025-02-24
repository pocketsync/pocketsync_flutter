import 'dart:developer' as developer;

enum LogLevel { debug, info, warning, error }

class LoggerService {
  static final LoggerService instance = LoggerService._internal();
  LoggerService._internal();

  bool _isSilent = false;
  set isSilent(bool value) => _isSilent = value;

  bool _shouldLog(LogLevel level) => !_isSilent;

  void _log(LogLevel level, String message,
      {Object? error, StackTrace? stackTrace}) {
    if (!_shouldLog(level)) return;

    final timestamp = DateTime.now().toIso8601String();
    final logMessage = '[$timestamp][${level.name.toUpperCase()}] $message';

    developer.log(
      logMessage,
      error: error,
      stackTrace: stackTrace,
      level: level.index,
      name: 'PocketSync',
    );
  }

  void debug(String message, {Object? error, StackTrace? stackTrace}) {
    _log(LogLevel.debug, message, error: error, stackTrace: stackTrace);
  }

  void info(String message, {Object? error, StackTrace? stackTrace}) {
    _log(LogLevel.info, message, error: error, stackTrace: stackTrace);
  }

  void warning(String message, {Object? error, StackTrace? stackTrace}) {
    _log(LogLevel.warning, message, error: error, stackTrace: stackTrace);
  }

  void error(String message, {Object? error, StackTrace? stackTrace}) {
    _log(LogLevel.error, message, error: error, stackTrace: stackTrace);
  }
}
