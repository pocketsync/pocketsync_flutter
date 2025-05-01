import 'package:pocketsync_flutter/src/database/database_watcher.dart';
import 'package:pocketsync_flutter/src/engine/listeners/change_listener.dart';
import 'package:pocketsync_flutter/src/engine/sync_scheduler.dart';
import 'package:pocketsync_flutter/src/types.dart';
import 'package:pocketsync_flutter/src/utils/logger.dart';

/// Listens for database changes and schedules sync operations accordingly.
///
/// This class connects to the database's change notification system and
/// forwards those changes to the [SyncScheduler] for appropriate timing
/// of synchronization operations.
class DatabaseChangeListener extends ChangeListener {
  final SyncScheduler _syncScheduler;
  final DatabaseWatcher _databaseWatcher;
  bool _isListening = false;

  /// Creates a new DatabaseChangeListener.
  ///
  /// Requires a [SyncScheduler] to schedule sync operations when changes are detected.
  /// If a [DatabaseWatcher] is not provided, a new one will be created.
  DatabaseChangeListener({
    required SyncScheduler syncScheduler,
    required DatabaseWatcher databaseWatcher,
  })  : _syncScheduler = syncScheduler,
        _databaseWatcher = databaseWatcher;

  /// Starts listening for database changes.
  ///
  /// This method sets up the change listener on the database watcher.
  /// When changes are detected, they are forwarded to the sync scheduler.
  @override
  void startListening() {
    if (_isListening) return;
    
    _databaseWatcher.setGlobalCallback(_onDatabaseChange);
    _isListening = true;
  }

  /// Stops listening for database changes.
  @override
  void stopListening() {
    if (!_isListening) return;
    
    _databaseWatcher.setGlobalCallback(null);
    _isListening = false;
  }

  /// Adds a listener for a specific table.
  ///
  /// This allows for more granular control over which table changes
  /// trigger sync operations.
  void addTableListener(String tableName, TableChangeCallback callback) {
    _databaseWatcher.addListener(tableName, callback);
  }

  /// Removes a listener for a specific table.
  void removeTableListener(String tableName) {
    _databaseWatcher.removeListener(tableName);
  }

  /// Callback that's invoked when a database change is detected.
  ///
  /// This method forwards the change to the sync scheduler.
  void _onDatabaseChange(String tableName, ChangeType changeType) {
    Logger.log('DatabaseChangeListener: Change detected in $tableName (${changeType.name})');
    _syncScheduler.scheduleUpload(tableName, changeType);
  }

  /// Manually triggers a database change notification.
  ///
  /// This is useful for testing or for triggering sync operations
  /// from non-database sources.
  void notifyChange(String tableName, ChangeType changeType) {
    _onDatabaseChange(tableName, changeType);
  }

  /// Disposes of resources used by this listener.
  @override
  void dispose() {
    stopListening();
  }
}
