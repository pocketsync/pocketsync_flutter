import 'package:pocketsync_flutter/src/models/types.dart';

typedef DatabaseChangeCallback = void Function(
  String tableName,
  ChangeType changeType,
  bool triggerSync,
);

class DatabaseWatcher {
  DatabaseChangeCallback? _globalCallback;
  final Map<String, TableChangeCallback> _tableChangeCallbacks = {};

  DatabaseWatcher();

  void setGlobalCallback(DatabaseChangeCallback? callback) {
    _globalCallback = callback;
  }

  void addListener(String tableName, TableChangeCallback callback) {
    _tableChangeCallbacks[tableName] = callback;
  }

  void removeListener(String tableName) {
    _tableChangeCallbacks.remove(tableName);
  }

  void notifyListeners(String tableName, ChangeType changeType, {bool triggerSync = true}) {
    final callback = _tableChangeCallbacks[tableName];
    if (callback != null) {
      callback(tableName, changeType);
    }
    _globalCallback?.call(tableName, changeType, triggerSync);
  }

  void dispose() {
    _tableChangeCallbacks.clear();
    _globalCallback = null;
  }
}
