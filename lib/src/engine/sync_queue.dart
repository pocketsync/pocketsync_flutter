import 'package:pocketsync_flutter/src/types.dart';
import 'package:pocketsync_flutter/src/utils/logger.dart';

/// Manages a queue of pending changes to be synchronized.
///
/// The SyncQueue stores information about database changes that need to be
/// synchronized with the server. It provides methods for adding, retrieving,
/// and managing these changes.
class SyncQueue {
  /// Map of table names to sets of change types
  /// This allows us to efficiently track which tables have pending changes
  /// and what types of changes they are.
  final Map<String, Set<ChangeType>> _pendingChanges = {};

  /// Adds a change to the queue.
  ///
  /// This method records that a change of type [changeType] has occurred
  /// in the table [tableName].
  void addChange(String tableName, ChangeType changeType) {
    _pendingChanges
        .putIfAbsent(tableName, () => <ChangeType>{})
        .add(changeType);
    Logger.log(
        'SyncQueue: Added ${changeType.name} change for table $tableName');
  }

  /// Checks if the queue is empty.
  bool get isEmpty => _pendingChanges.isEmpty;

  /// Checks if the queue has any pending changes.
  bool get isNotEmpty => _pendingChanges.isNotEmpty;

  /// Gets a map of all pending changes.
  ///
  /// Returns a copy of the internal map to prevent external modification.
  Map<String, Set<ChangeType>> getPendingChanges() {
    return Map.from(_pendingChanges);
  }

  /// Gets a list of table names that have pending changes.
  List<String> getTablesWithPendingChanges() {
    return _pendingChanges.keys.toList();
  }

  /// Checks if a specific table has pending changes.
  bool hasChangesForTable(String tableName) {
    return _pendingChanges.containsKey(tableName) &&
        _pendingChanges[tableName]!.isNotEmpty;
  }

  /// Checks if a specific table has a specific type of pending change.
  bool hasChangeTypeForTable(String tableName, ChangeType changeType) {
    return _pendingChanges.containsKey(tableName) &&
        _pendingChanges[tableName]!.contains(changeType);
  }

  /// Marks changes for a specific table as processed.
  ///
  /// This removes all pending changes for the specified table.
  void markTableProcessed(String tableName) {
    _pendingChanges.remove(tableName);
    Logger.log('SyncQueue: Marked table $tableName as processed');
  }

  /// Marks all pending changes as processed.
  ///
  /// This clears the entire queue.
  void markAllProcessed() {
    _pendingChanges.clear();
    Logger.log('SyncQueue: Marked all changes as processed');
  }

  /// Gets the number of tables with pending changes.
  int get pendingTableCount => _pendingChanges.length;

  /// Gets the total number of pending changes across all tables.
  int get totalPendingChanges {
    return _pendingChanges.values
        .fold(0, (sum, changes) => sum + changes.length);
  }
}
