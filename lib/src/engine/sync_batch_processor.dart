import 'package:pocketsync_flutter/src/engine/change_aggregator.dart';
import 'package:pocketsync_flutter/src/engine/pocket_sync_network_client.dart';
import 'package:pocketsync_flutter/src/models/sync_change.dart';
import 'package:pocketsync_flutter/src/models/types.dart';
import 'package:sqflite/sqflite.dart';

/// Processes batches of changes grouped by table and change type.
///
/// This class is responsible for retrieving unsynced changes from the database,
/// grouping them by table and change type, and sending them to the server in batches.
class SyncBatchProcessor {
  final Database _database;
  final PocketSyncNetworkClient _apiClient;
  final ChangeAggregator _changeAggregator;
  final int _maxBatchSize;

  /// Creates a new SyncBatchProcessor.
  SyncBatchProcessor({
    required Database database,
    required PocketSyncNetworkClient apiClient,
    required ChangeAggregator changeAggregator,
    required int maxBatchSize,
  })  : _database = database,
        _apiClient = apiClient,
        _changeAggregator = changeAggregator,
        _maxBatchSize = maxBatchSize;

  /// Processes unsynced changes in batches.
  ///
  /// This method retrieves unsynced changes from the database, groups them by
  /// table and change type, and sends them to the server in batches.
  ///
  /// Returns a map of table names to booleans indicating whether all changes
  /// for that table were successfully synced.
  Future<Map<String, bool>> processUnsyncedChanges(List<String> tables) async {
    final results = <String, bool>{};

    for (final table in tables) {
      try {
        final changes = await _getUnsyncedChanges(table);

        if (changes.isEmpty) {
          results[table] = true;
          continue;
        }

        final groupedChanges = _groupChangesByType(changes);

        bool allSucceeded = true;

        for (final entry in groupedChanges.entries) {
          final changesOfType = entry.value;

          final success = await _processBatches(changesOfType);

          if (!success) {
            allSucceeded = false;
            break;
          }
        }

        results[table] = allSucceeded;
      } catch (e) {
        results[table] = false;
      }
    }

    return results;
  }

  /// Gets all unsynced changes for a table.
  Future<List<SyncChange>> _getUnsyncedChanges(String tableName) async {
    final aggregatedChanges =
        await _changeAggregator.aggregateChanges(tableName);
    return aggregatedChanges.changes;
  }

  /// Groups changes by change type.
  Map<ChangeType, List<SyncChange>> _groupChangesByType(
      List<SyncChange> changes) {
    final result = <ChangeType, List<SyncChange>>{};

    for (final change in changes) {
      result.putIfAbsent(change.operation, () => []).add(change);
    }

    return result;
  }

  /// Processes changes in batches.
  ///
  /// This method splits the changes into batches of the specified size and
  /// sends them to the server sequentially.
  Future<bool> _processBatches(List<SyncChange> changes) async {
    if (changes.length <= _maxBatchSize) {
      return await _apiClient.uploadChanges(changes);
    }

    bool allBatchesSucceeded = true;

    for (int i = 0; i < changes.length; i += _maxBatchSize) {
      final endIndex = (i + _maxBatchSize < changes.length)
          ? i + _maxBatchSize
          : changes.length;

      final batch = changes.sublist(i, endIndex);
      final success = await _apiClient.uploadChanges(batch);

      if (!success) {
        allBatchesSucceeded = false;
        break;
      }
    }

    return allBatchesSucceeded;
  }

  /// Marks changes as synced in the database.
  ///
  /// This method updates the __pocketsync_changes table to mark the specified
  /// changes as synced.
  Future<void> markChangesAsSynced(
      String tableName, List<String> changeIds) async {
    if (changeIds.isEmpty) return;

    await _database.rawUpdate(
      'UPDATE __pocketsync_changes SET synced = 1 WHERE id IN (${changeIds.map((_) => '?').join(', ')})',
      changeIds,
    );

    await _database.rawUpdate(
      'UPDATE __pocketsync_device_state SET last_upload_timestamp = ?',
      [DateTime.now().millisecondsSinceEpoch],
    );
  }
}
