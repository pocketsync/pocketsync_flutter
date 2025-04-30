import 'package:pocketsync_flutter/src/types.dart';

class DatabaseWatcher {
  TableChangeCallback? _globalCallback;
  final Map<String, TableChangeCallback> _tableChangeCallbacks = {};

  DatabaseWatcher();

  void setGlobalCallback(TableChangeCallback callback) {
    _globalCallback = callback;
  }

  void addListener(String tableName, TableChangeCallback callback) {
    _tableChangeCallbacks[tableName] = callback;
  }

  void removeListener(String tableName) {
    _tableChangeCallbacks.remove(tableName);
  }

  void notifyListeners(String tableName, ChangeType changeType) {
    final callback = _tableChangeCallbacks[tableName];
    if (callback != null) {
      callback(tableName, changeType);
    }
    _globalCallback?.call(tableName, changeType);
  }

  void dispose() {
    _tableChangeCallbacks.clear();
    _globalCallback = null;
  }
}
