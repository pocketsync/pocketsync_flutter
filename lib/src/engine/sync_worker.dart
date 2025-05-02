import 'dart:async';

import 'package:pocketsync_flutter/src/database/database_watcher.dart';
import 'package:pocketsync_flutter/src/engine/change_aggregator.dart';
import 'package:pocketsync_flutter/src/engine/merge_engine.dart';
import 'package:pocketsync_flutter/src/engine/pocket_sync_network_client.dart';
import 'package:pocketsync_flutter/src/engine/schema_manager.dart';
import 'package:pocketsync_flutter/src/models/sync_change.dart';
import 'package:pocketsync_flutter/src/engine/sync_queue.dart';
import 'package:pocketsync_flutter/src/models/types.dart';
import 'package:pocketsync_flutter/src/utils/logger.dart';
import 'package:sqflite/sqflite.dart';

/// Processes the sync queue when activated.
///
/// The SyncWorker is responsible for taking pending changes from the sync queue,
/// aggregating them into efficient transmission chunks, and sending them to the server.
/// It also processes remote changes received from the server during download operations.
class SyncWorker {
  final MergeEngine _mergeEngine;
  final SchemaManager _schemaManager;
  final SyncQueue _syncQueue;
  final ChangeAggregator _changeAggregator;
  final PocketSyncNetworkClient _apiClient;
  final Database _database;
  final DatabaseWatcher _databaseWatcher;

  bool _isRunning = false;
  bool _isSyncing = false;
  Timer? _syncTimer;
  final Duration _syncInterval;

  /// Creates a new SyncWorker.
  ///
  /// Requires a [SyncQueue] to get pending changes, a [ChangeAggregator] to optimize
  /// changes for transmission, a [PocketSyncNetworkClient] to send changes to the server,
  /// and a [Database] to access the local database.
  SyncWorker({
    required SyncQueue syncQueue,
    required ChangeAggregator changeAggregator,
    required PocketSyncNetworkClient apiClient,
    required Database database,
    required MergeEngine mergeEngine,
    required SchemaManager schemaManager,
    Duration? syncInterval,
    DatabaseWatcher? databaseWatcher,
  })  : _syncQueue = syncQueue,
        _changeAggregator = changeAggregator,
        _apiClient = apiClient,
        _database = database,
        _mergeEngine = mergeEngine,
        _schemaManager = schemaManager,
        _syncInterval = syncInterval ?? const Duration(minutes: 5),
        _databaseWatcher = databaseWatcher ?? DatabaseWatcher();

  /// Starts the sync worker.
  ///
  /// This method begins periodic processing of the sync queue based on the
  /// configured sync interval.
  Future<void> start() async {
    if (_isRunning) return;

    _isRunning = true;

    // Process the queue immediately when starting
    await processQueue();

    // Set up periodic sync
    _syncTimer = Timer.periodic(_syncInterval, (_) async {
      if (!_isSyncing) {
        await processQueue();
      }
    });
  }

  /// Stops the sync worker.
  ///
  /// This method cancels any pending sync operations and stops the periodic sync.
  Future<void> stop() async {
    if (!_isRunning) return;

    _syncTimer?.cancel();
    _syncTimer = null;
    _isRunning = false;
  }

  /// Processes the sync queue.
  ///
  /// This method handles both upload and download operations:
  /// - For uploads: retrieves pending changes, aggregates them, and sends to server
  /// - For downloads: processes remote changes received from the server
  Future<void> processQueue() async {
    if (_isSyncing || _syncQueue.isEmpty) return;

    try {
      _isSyncing = true;

      // Process uploads first
      await _processUploads();

      // Then process downloads if there are any
      if (_syncQueue.hasDownloads) {
        await _processDownloads(since: await getLastDownloadTimestamp());
      }
    } finally {
      _isSyncing = false;
    }
  }

  /// Processes pending uploads.
  ///
  /// This method retrieves pending upload changes from the sync queue, aggregates them
  /// into optimized chunks using the change aggregator, and sends them to the server.
  Future<void> _processUploads() async {
    // Get tables with pending upload changes
    final tables = _syncQueue.getTablesWithPendingUploads();

    // Process each table
    for (final table in tables) {
      try {
        // Aggregate changes for the table
        final changes = await _changeAggregator.aggregateChanges(table);

        if (changes.isEmpty) {
          continue;
        }

        // Send changes to the server
        final success = await _apiClient.uploadChanges(changes);

        if (success) {
          // Mark changes as synced in the database
          await _markChangesAsSynced(
            table,
            changes.map((c) => c.id).toList(),
          );

          // Mark changes as processed in the queue
          _syncQueue.markTableUploaded(table);
        }
      } catch (e) {
        Logger.log('SyncWorker: Error processing upload for table $table: $e');
      }
    }
  }

  /// Processes pending downloads.
  ///
  /// This method handles the download process in three steps:
  /// 1. Makes a REST call to the server to fetch available changes
  /// 2. Merges remote changes with local data using the merge engine
  /// 3. Applies the merged changes to the local database
  Future<void> _processDownloads({DateTime? since}) async {
    try {
      if (!_syncQueue.hasDownloads) {
        return;
      }

      final downloadedChanges = await _apiClient.downloadChanges(since: since);

      if (downloadedChanges.isNotEmpty) {
        _syncQueue.addRemoteChanges(downloadedChanges);
      }

      final remoteChanges = _syncQueue.getRemoteChanges();

      if (remoteChanges.isEmpty) {
        _syncQueue.markDownloadProcessed();
        return;
      }

      final localChanges = await _getPendingLocalChanges(remoteChanges);
      final mergedChanges =
          await _mergeEngine.mergeChanges(localChanges, remoteChanges);

      for (final change in mergedChanges) {
        try {
          await _applyChange(change);
        } catch (e) {
          Logger.log('SyncWorker: Error applying merged change: $e');
        }
      }

      // Clear processed remote changes
      _syncQueue
        ..clearRemoteChanges()
        ..markDownloadProcessed();

      // Update device state
      await _database.rawUpdate(
        'UPDATE __pocketsync_device_state SET last_download_timestamp = ?',
        [DateTime.now().millisecondsSinceEpoch],
      );

      // Notify listeners about the changes
      // This is necessary because the engine internally does not use the database wrapper
      // and does not notify listeners about changes.
      for (final table in _getTables(remoteChanges)) {
        _databaseWatcher.notifyListeners(table, ChangeType.update);
      }
    } catch (e) {
      Logger.log('SyncWorker: Error processing downloads: $e');
    }
  }

  Set<String> _getTables(Iterable<SyncChange> changes) {
    return changes.map((c) => c.tableName).toSet();
  }

  /// Applies a change to the local database.
  ///
  /// This method applies a change to the local database, whether it's from
  /// a remote source or a merged result.
  Future<void> _applyChange(SyncChange change) async {
    final tableName = change.tableName;
    final recordId = change.recordId;
    final data = change.data;

    await _schemaManager.disableTriggers(_database);

    try {
      switch (change.operation) {
        case ChangeType.insert:
          // Insert new record
          await _database.insert(tableName, data);
          break;

        case ChangeType.update:
          // Update existing record
          await _database.update(
            tableName,
            data,
            where: 'id = ?',
            whereArgs: [recordId],
          );
          break;

        case ChangeType.delete:
          // Delete record
          await _database.delete(
            tableName,
            where: 'id = ?',
            whereArgs: [recordId],
          );
          break;
      }
    } finally {
      await _schemaManager.setupChangeTracking(_database);
    }
  }

  /// Retrieves pending local changes that might conflict with remote changes.
  ///
  /// This method queries the database for any pending local changes that affect
  /// the same records as the incoming remote changes.
  Future<List<SyncChange>> _getPendingLocalChanges(
      List<SyncChange> remoteChanges) async {
    final localChanges = <SyncChange>[];

    // Create a set of table:recordId keys for quick lookup
    final remoteChangeKeys =
        remoteChanges.map((c) => '${c.tableName}:${c.recordId}').toSet();

    // Query the database for pending changes that match the remote records
    for (final key in remoteChangeKeys) {
      final parts = key.split(':');
      if (parts.length != 2) continue;

      final tableName = parts[0];
      final recordId = parts[1];

      // Query for pending changes for this record
      final rows = await _database.query(
        '__pocketsync_changes',
        where: 'table_name = ? AND record_rowid = ? AND synced = 0',
        whereArgs: [tableName, recordId],
      );

      // Convert rows to SyncChange objects
      final changes = SyncChange.fromDatabaseRecords(rows);
      localChanges.addAll(changes);
    }

    return localChanges;
  }

  /// Marks changes as synced in the database.
  ///
  /// This method updates the __pocketsync_changes table to mark the specified
  /// changes as synced.
  Future<void> _markChangesAsSynced(
      String tableName, List<int> changeIds) async {
    if (changeIds.isEmpty) return;

    // Update the changes table to mark these changes as synced
    await _database.rawUpdate(
      'UPDATE __pocketsync_changes SET synced = 1 WHERE id IN (${changeIds.map((_) => '?').join(', ')})',
      changeIds,
    );

    // Update device state
    await _database.rawUpdate(
      'UPDATE __pocketsync_device_state SET last_upload_timestamp = ?',
      [DateTime.now().millisecondsSinceEpoch],
    );
  }

  Future<DateTime> getLastDownloadTimestamp() async {
    final rows = await _database.query(
      '__pocketsync_device_state',
      where: 'device_id = ?',
    );
    if (rows.isEmpty) {
      return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }
    return DateTime.fromMillisecondsSinceEpoch(
      rows[0]['last_download_timestamp'] as int,
      isUtc: true,
    );
  }

  /// Checks if the sync worker is currently running.
  bool get isRunning => _isRunning;

  /// Checks if a sync operation is currently in progress.
  bool get isSyncing => _isSyncing;
}
