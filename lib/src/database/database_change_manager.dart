import 'dart:async';

/// Callback type for database change listeners
typedef DatabaseChangeListener = void Function(String table, bool isRemote);

/// Manages database change listeners with table-specific subscriptions
class DatabaseChangeManager {
  final Map<String, Map<int, DatabaseChangeListener>> _tableListeners = {};
  final Map<int, DatabaseChangeListener> _globalListeners = {};
  final Map<String, Timer> _debounceTimers = {};

  static const _debounceDuration = Duration(milliseconds: 100);

  /// Adds a listener for all database changes (prevents duplicates)
  void addGlobalListener(DatabaseChangeListener listener) {
    _globalListeners[listener.hashCode] = listener;
  }

  /// Removes a global listener
  void removeGlobalListener(DatabaseChangeListener listener) {
    _globalListeners.remove(listener.hashCode);
  }

  /// Adds a listener for changes to a specific table (prevents duplicates)
  void addTableListener(String table, DatabaseChangeListener listener) {
    _tableListeners.putIfAbsent(table, () => {});
    _tableListeners[table]![listener.hashCode] = listener;
  }

  /// Removes a table-specific listener
  void removeTableListener(String table, DatabaseChangeListener listener) {
    _tableListeners[table]?.remove(listener.hashCode);
    if (_tableListeners[table]?.isEmpty ?? false) {
      _tableListeners.remove(table);
    }
  }

  void notifySync() {
    for (final listener in _globalListeners.values) {
      listener('*', false);
    }
  }

  /// Notifies listeners of changes to a specific table
  void notifyChange(String table, {bool isRemote = false}) {
    _debounceTimers[table]?.cancel();
    _debounceTimers[table] = Timer(_debounceDuration, () {
      final listeners = _tableListeners[table]?.values;
      if (listeners != null) {
        for (final listener in listeners) {
          listener(table, isRemote);
        }
      }

      // Notify global listeners
      for (final listener in _globalListeners.values) {
        listener(table, isRemote);
      }

      _debounceTimers.remove(table);
    });
  }

  /// Disposes all resources
  void dispose() {
    _tableListeners.clear();
    _globalListeners.clear();
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();
  }
}
