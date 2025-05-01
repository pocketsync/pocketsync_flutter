import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pocketsync_flutter/src/engine/change_aggregator.dart';
import 'package:pocketsync_flutter/src/engine/pocket_sync_network_client.dart';
import 'package:pocketsync_flutter/src/engine/sync_queue.dart';
import 'package:sqflite/sqflite.dart';

/// Processes the sync queue when activated.
///
/// The SyncWorker is responsible for taking pending changes from the sync queue,
/// aggregating them into efficient transmission chunks, and sending them to the server.
class SyncWorker {
  final SyncQueue _syncQueue;
  final ChangeAggregator _changeAggregator;
  final PocketSyncNetworkClient _apiClient;
  final Database _database;

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
    Duration? syncInterval,
  })  : _syncQueue = syncQueue,
        _changeAggregator = changeAggregator,
        _apiClient = apiClient,
        _database = database,
        _syncInterval = syncInterval ?? const Duration(minutes: 5);

  /// Starts the sync worker.
  ///
  /// This method begins periodic processing of the sync queue based on the
  /// configured sync interval.
  Future<void> start() async {
    if (_isRunning) return;

    _isRunning = true;
    debugPrint('SyncWorker: Started');

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
    debugPrint('SyncWorker: Stopped');
  }

  /// Processes the sync queue.
  ///
  /// This method retrieves pending changes from the sync queue, aggregates them
  /// into optimized chunks using the change aggregator, and sends them to the server.
  Future<void> processQueue() async {
    if (_isSyncing || _syncQueue.isEmpty) return;

    try {
      _isSyncing = true;
      debugPrint('SyncWorker: Processing sync queue');

      // Get tables with pending changes
      final tables = _syncQueue.getTablesWithPendingChanges();

      // Process each table
      for (final table in tables) {
        try {
          // Aggregate changes for the table
          final changes = await _changeAggregator.aggregateChanges(table);

          if (changes.isEmpty) {
            debugPrint('SyncWorker: No changes to sync for table $table');
            continue;
          }

          debugPrint(
              'SyncWorker: Syncing ${changes.length} changes for table $table');

          // Send changes to the server
          final success = await _apiClient.uploadChanges(changes);

          if (success) {
            // Mark changes as synced in the database
            await _markChangesAsSynced(
                table, changes.map((c) => c.id).toList());

            // Mark changes as processed in the queue
            _syncQueue.markTableProcessed(table);

            debugPrint(
                'SyncWorker: Successfully synced changes for table $table');
          } else {
            debugPrint('SyncWorker: Failed to sync changes for table $table');
          }
        } catch (e) {
          debugPrint('SyncWorker: Error processing table $table: $e');
        }
      }
    } finally {
      _isSyncing = false;
    }
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
  }

  /// Checks if the sync worker is currently running.
  bool get isRunning => _isRunning;

  /// Checks if a sync operation is currently in progress.
  bool get isSyncing => _isSyncing;
}
