import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:pocketsync_flutter/src/models/change_set.dart';
import 'package:pocketsync_flutter/src/services/logger_service.dart';

/// A task in the sync queue
class SyncTask {
  final ChangeSet changeSet;
  final Completer<void> completer;
  final DateTime createdAt;

  SyncTask(this.changeSet)
      : completer = Completer<void>(),
        createdAt = DateTime.now();
}

/// Manages a queue of sync tasks and processes them sequentially
class SyncTaskQueue {
  final _logger = LoggerService.instance;
  final Queue<SyncTask> _queue = Queue<SyncTask>();
  Timer? _debounceTimer;
  bool _isProcessing = false;
  int _retryAttempt = 0;

  /// Maximum number of retry attempts
  static const _maxRetries = 5;

  /// Base delay for retry backoff
  static const _baseRetryDelay = Duration(seconds: 1);

  /// The duration to wait before processing queued tasks
  final Duration debounceDuration;

  /// Callback to process a batch of changes
  final Future<void> Function(ChangeSet) processChanges;

  SyncTaskQueue({
    required this.processChanges,
    this.debounceDuration = const Duration(milliseconds: 500),
  });

  /// Adds a new sync task to the queue
  Future<void> enqueue(ChangeSet changes) {
    final task = SyncTask(changes);
    _queue.add(task);
    _scheduleProcessing();
    return task.completer.future;
  }

  /// Schedules the processing of queued tasks
  void _scheduleProcessing() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceDuration, _processQueue);
  }

  /// Processes all queued tasks
  Future<void> _processQueue() async {
    if (_isProcessing || _queue.isEmpty) return;

    _isProcessing = true;
    try {
      // Merge all pending changes into a single batch
      final tasks = List<SyncTask>.from(_queue);
      _queue.clear();

      if (tasks.isEmpty) return;

      // Merge changes from all tasks
      final mergedChanges = _mergeChangeSets(tasks.map((t) => t.changeSet));

      _logger.info('Processing merged changes: ${tasks.length} tasks combined');

      try {
        await _processWithRetry(() => processChanges(mergedChanges));
        _retryAttempt = 0; // Reset retry counter on success

        // Complete all tasks successfully
        for (final task in tasks) {
          if (!task.completer.isCompleted) {
            task.completer.complete();
          }
        }
      } catch (e) {
        _logger.error(
          'Failed to process sync queue after $_retryAttempt attempts',
          error: e,
        );
        // If processing fails after all retries, complete all tasks with error
        for (final task in tasks) {
          if (!task.completer.isCompleted) {
            task.completer.completeError(e);
          }
        }
        rethrow;
      }
    } finally {
      _isProcessing = false;
      // If there are more tasks in the queue, schedule another processing
      if (_queue.isNotEmpty) {
        _scheduleProcessing();
      }
    }
  }

  /// Processes an operation with exponential backoff retry
  Future<void> _processWithRetry(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (e) {
      if (_retryAttempt >= _maxRetries) {
        throw Exception('Max retries exceeded: $e');
      }

      final delay = _calculateRetryDelay(_retryAttempt);
      _logger.warning(
        'Sync attempt $_retryAttempt failed. Retrying in ${delay.inSeconds}s',
        error: e,
      );

      await Future.delayed(delay);
      _retryAttempt++;
      await _processWithRetry(operation);
    }
  }

  /// Calculates the delay for the next retry attempt using exponential backoff with jitter
  Duration _calculateRetryDelay(int attempt) {
    final baseDelay = _baseRetryDelay.inMilliseconds;
    final maxDelay = Duration(minutes: 5).inMilliseconds;
    final exponentialDelay =
        baseDelay * pow(2, attempt).toInt() + Random().nextInt(1000);
    return Duration(milliseconds: min(exponentialDelay, maxDelay));
  }

  /// Merges multiple change sets into a single change set
  ChangeSet _mergeChangeSets(Iterable<ChangeSet> changeSets) {
    final allInsertions = <String, TableRows>{};
    final allUpdates = <String, TableRows>{};
    final allDeletions = <String, TableRows>{};
    final allChangeIds = <int>[];
    int latestTimestamp = 0;
    int latestVersion = 0;

    for (final changeSet in changeSets) {
      // Keep track of latest timestamp and version
      latestTimestamp = latestTimestamp < changeSet.timestamp
          ? changeSet.timestamp
          : latestTimestamp;
      latestVersion =
          latestVersion < changeSet.version ? changeSet.version : latestVersion;

      // Merge insertions with conflict detection
      changeSet.insertions.changes.forEach((table, rows) {
        final existingRows = allInsertions[table]?.rows ?? [];
        final newRows = rows.rows;

        for (final newRow in newRows) {
          final conflict = existingRows
              .where((r) =>
                  r.primaryKey == newRow.primaryKey &&
                  r.version != newRow.version &&
                  r.data != newRow.data)
              .firstOrNull;

          if (conflict != null) {
            _logger.warning(
                'Insertion conflict detected in table $table for key ${newRow.primaryKey}',
                error: {
                  'existing': conflict.data,
                  'new': newRow.data,
                  'resolution': 'Using newer version'
                });
          }
        }

        final mergedRows = _mergeRows(existingRows, newRows);
        allInsertions[table] = TableRows(mergedRows);
      });

      // Merge updates with conflict detection
      changeSet.updates.changes.forEach((table, rows) {
        final existingRows = allUpdates[table]?.rows ?? [];
        final newRows = rows.rows;

        for (final newRow in newRows) {
          final conflict = existingRows
              .where((r) =>
                  r.primaryKey == newRow.primaryKey &&
                  r.version != newRow.version &&
                  r.data != newRow.data)
              .firstOrNull;

          if (conflict != null) {
            _logger.warning(
                'Update conflict detected in table $table for key ${newRow.primaryKey}',
                error: {
                  'existing': conflict.data,
                  'new': newRow.data,
                  'resolution': conflict.version > newRow.version
                      ? 'Keeping existing version'
                      : 'Applying new version'
                });
          }
        }

        final mergedRows = _mergeRows(existingRows, newRows);
        allUpdates[table] = TableRows(mergedRows);
      });

      // Merge deletions with conflict detection
      changeSet.deletions.changes.forEach((table, rows) {
        final existingRows = allDeletions[table]?.rows ?? [];
        final newRows = rows.rows;

        // Check for delete-update conflicts
        for (final deletedRow in newRows) {
          final updateConflict = allUpdates[table]
              ?.rows
              .where((r) => r.primaryKey == deletedRow.primaryKey)
              .firstOrNull;

          if (updateConflict != null) {
            _logger.warning(
                'Delete-update conflict detected in table $table for key ${deletedRow.primaryKey}',
                error: {
                  'update': updateConflict.data,
                  'resolution': 'Prioritizing deletion'
                });
          }
        }

        final mergedRows = [...existingRows, ...newRows];
        allDeletions[table] = TableRows(mergedRows);

        // Remove deleted records from insertions and updates
        for (final row in newRows) {
          allInsertions[table]
              ?.rows
              .removeWhere((r) => r.primaryKey == row.primaryKey);
          allUpdates[table]
              ?.rows
              .removeWhere((r) => r.primaryKey == row.primaryKey);
        }
      });

      allChangeIds.addAll(changeSet.localChangeIds);
    }

    return ChangeSet(
      timestamp: latestTimestamp,
      version: latestVersion,
      insertions: TableChanges(allInsertions),
      updates: TableChanges(allUpdates),
      deletions: TableChanges(allDeletions),
      localChangeIds: allChangeIds,
    );
  }

  /// Merges two lists of rows, keeping the newer versions
  List<Row> _mergeRows(List<Row> existing, List<Row> newRows) {
    final mergedMap = <String, Row>{};

    // Add existing rows
    for (final row in existing) {
      mergedMap[row.primaryKey] = row;
    }

    // Add or update with new rows
    for (final row in newRows) {
      final existingRow = mergedMap[row.primaryKey];
      if (existingRow == null || existingRow.version <= row.version) {
        mergedMap[row.primaryKey] = row;
      }
    }

    return mergedMap.values.toList();
  }

  /// Disposes of the queue and cancels any pending tasks
  void dispose() {
    _debounceTimer?.cancel();
    _queue.clear();
  }
}
