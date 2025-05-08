import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pocketsync_flutter/src/database/database_watcher.dart';
import 'package:pocketsync_flutter/src/engine/change_aggregator.dart';
import 'package:pocketsync_flutter/src/engine/connectivity_monitor.dart';
import 'package:pocketsync_flutter/src/engine/merge_engine.dart';
import 'package:pocketsync_flutter/src/engine/pocket_sync_network_client.dart';
import 'package:pocketsync_flutter/src/engine/schema_manager.dart';
import 'package:pocketsync_flutter/src/engine/sync_batch_processor.dart';
import 'package:pocketsync_flutter/src/engine/sync_queue.dart';
import 'package:pocketsync_flutter/src/models/sync_change.dart';
import 'package:pocketsync_flutter/src/models/types.dart';
import 'package:pocketsync_flutter/src/utils/logger.dart';
import 'package:pocketsync_flutter/src/utils/sync_config.dart';
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
  late ConnectivityMonitor _connectivityMonitor;
  late SyncBatchProcessor _batchProcessor;

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
    int? maxBatchSize,
    DatabaseWatcher? databaseWatcher,
    ConnectivityMonitor? connectivityMonitor,
  })  : _syncQueue = syncQueue,
        _changeAggregator = changeAggregator,
        _apiClient = apiClient,
        _database = database,
        _mergeEngine = mergeEngine,
        _schemaManager = schemaManager,
        _syncInterval = syncInterval ?? const Duration(minutes: 5),
        _databaseWatcher = databaseWatcher ?? DatabaseWatcher() {
    // Initialize the connectivity monitor
    _connectivityMonitor = connectivityMonitor ??
        ConnectivityMonitor(
          networkClient: _apiClient,
          onConnected: _onConnectivityRestored,
        );

    // Initialize the batch processor
    _batchProcessor = SyncBatchProcessor(
      database: _database,
      apiClient: _apiClient,
      changeAggregator: _changeAggregator,
      maxBatchSize: maxBatchSize ?? SyncConfig.defaultMaxBatchSize,
    );
  }

  /// Starts the sync worker.
  ///
  /// This method begins periodic processing of the sync queue based on the
  /// configured sync interval.
  Future<void> start() async {
    if (_isRunning) return;

    _isRunning = true;

    // Start monitoring connectivity
    _connectivityMonitor.startMonitoring();

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

  /// Called when connectivity is restored.
  Future<void> _onConnectivityRestored() async {
    Logger.log('SyncWorker: Connectivity restored, processing queue');

    if (!_isSyncing) {
      await processQueue();
    }
  }

  /// Disposes of resources used by the sync worker.
  void dispose() {
    _syncTimer?.cancel();
    _connectivityMonitor.dispose();
  }

  // Test helper methods

  /// For testing only: Set a mock connectivity monitor
  @visibleForTesting
  void testSetConnectivityMonitor(ConnectivityMonitor monitor) {
    _connectivityMonitor = monitor;
  }

  /// For testing only: Set a mock batch processor
  @visibleForTesting
  void testSetBatchProcessor(SyncBatchProcessor processor) {
    _batchProcessor = processor;
  }

  /// For testing only: Trigger the connectivity restored callback
  @visibleForTesting
  Future<void> testOnConnectivityRestored() async {
    await _onConnectivityRestored();
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

      final isConnected = _connectivityMonitor.isConnected;
      if (isConnected) {
        if (_syncQueue.getTablesWithPendingUploads().isNotEmpty) {
          await _processUploads();
        }
        if (_syncQueue.hasDownloads) {
          await _processDownloads(since: await getLastDownloadTimestamp());
        }
      } else {
        Logger.log(
            'SyncWorker: Server not connected, will sync when connection is restored');
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

    // Process unsynced changes using the batch processor
    final results = await _batchProcessor.processUnsyncedChanges(tables);

    // Mark tables as processed based on results
    for (final table in tables) {
      final success = results[table] ?? false;

      if (success) {
        final aggregatedChanges =
            await _changeAggregator.aggregateChanges(table);

        await _batchProcessor.markChangesAsSynced(
            table, aggregatedChanges.affectedChangeIds);

        _syncQueue.markTableUploaded(table);

        Logger.log('SyncWorker: Successfully synced changes for table $table');
      } else {
        Logger.log('SyncWorker: Failed to sync some changes for table $table');
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

      if (downloadedChanges.changes.isNotEmpty) {
        _syncQueue.addRemoteChanges(downloadedChanges.changes);
      }

      final remoteChanges = _syncQueue.getRemoteChanges();

      if (remoteChanges.isEmpty) {
        _syncQueue.markDownloadProcessed();

        // Update the last download timestamp even when there are no changes
        await _database.rawUpdate(
          'UPDATE __pocketsync_device_state SET last_download_timestamp = ?',
          [downloadedChanges.timestamp.millisecondsSinceEpoch],
        );
        return;
      }

      final localChanges = await _getPendingLocalChanges(remoteChanges);
      final mergedChanges = await _mergeEngine.mergeChanges(
        localChanges,
        remoteChanges,
        downloadedChanges.syncSessionId,
        _onConflictDetected,
      );

      for (final change in mergedChanges) {
        try {
          await _applyChange(change);
        } catch (e) {
          Logger.log('SyncWorker: Error applying merged change: $e');
        }
      }

      _syncQueue
        ..clearRemoteChanges()
        ..markDownloadProcessed();

      await _database.rawUpdate(
        'UPDATE __pocketsync_device_state SET last_download_timestamp = ?',
        [DateTime.now().millisecondsSinceEpoch],
      );

      for (final table in _getTables(remoteChanges)) {
        _databaseWatcher.notifyListeners(table, ChangeType.update,
            triggerSync: false);
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
        case ChangeType.insert || ChangeType.update:
          final newData = Map<String, dynamic>.from(data['new']);
          if (newData.isEmpty) {
            return;
          }

          final columns = newData.keys.join(', ');
          final placeholders = List.filled(newData.length, '?').join(', ');
          final values = newData.values.toList();

          await _database.rawInsert(
            'INSERT OR REPLACE INTO $tableName ($columns) VALUES ($placeholders)',
            values,
          );
          break;

        case ChangeType.delete:
          await _database.rawDelete(
            'DELETE FROM $tableName WHERE ${SyncConfig.defaultGlobalIdColumnName} = ?',
            [recordId],
          );
          break;
      }
    } catch (e) {
      Logger.log('SyncWorker: Error applying change: $e');
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

    final remoteChangeKeys =
        remoteChanges.map((c) => '${c.tableName}:${c.recordId}').toSet();

    for (final key in remoteChangeKeys) {
      final parts = key.split(':');
      if (parts.length != 2) continue;

      final tableName = parts[0];
      final recordId = parts[1];

      final rows = await _database.query(
        '__pocketsync_changes',
        where: 'table_name = ? AND record_rowid = ? AND synced = 0',
        whereArgs: [tableName, recordId],
      );

      final changes = SyncChange.fromDatabaseRecords(rows);
      localChanges.addAll(changes);
    }

    return localChanges;
  }

  Future<DateTime> getLastDownloadTimestamp() async {
    final rows = await _database.query(
      '__pocketsync_device_state',
      columns: ['last_download_timestamp'],
      limit: 1,
    );
    if (rows.isEmpty) {
      return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }
    return DateTime.fromMillisecondsSinceEpoch(
      rows[0]['last_download_timestamp'] as int? ?? 0,
      isUtc: true,
    );
  }

  void _onConflictDetected(
    ConflictResolutionStrategy strategy,
    SyncChange localChange,
    SyncChange remoteChange,
    SyncChange winningChange,
    String syncSessionId,
  ) {
    _apiClient.reportConflict(
      strategy,
      localChange,
      remoteChange,
      winningChange,
      syncSessionId,
    );
  }
}
