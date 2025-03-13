import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:pocketsync_flutter/src/models/change_set.dart';
import 'package:pocketsync_flutter/src/services/logger_service.dart';

class SyncTask {
  final ChangeSet changeSet;
  final Completer<void> completer;
  final DateTime createdAt;

  SyncTask(this.changeSet)
      : completer = Completer<void>(),
        createdAt = DateTime.now();
}

class SyncTaskQueue {
  final _logger = LoggerService.instance;
  final Queue<SyncTask> _queue = Queue<SyncTask>();
  Timer? _debounceTimer;
  bool _isProcessing = false;
  int _retryAttempt = 0;

  static const _maxRetries = 5;
  static const _baseRetryDelay = Duration(seconds: 1);

  final Duration debounceDuration;

  final Future<void> Function(ChangeSet) processChanges;

  SyncTaskQueue({
    required this.processChanges,
    this.debounceDuration = const Duration(milliseconds: 500),
  });

  Future<void> enqueue(ChangeSet changes) {
    final task = SyncTask(changes);
    _queue.add(task);
    _scheduleProcessing();
    return task.completer.future;
  }

  void _scheduleProcessing() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceDuration, _processQueue);
  }
  Future<void> _processQueue() async {
    if (_isProcessing || _queue.isEmpty) return;

    _isProcessing = true;
    try {
      final tasks = List<SyncTask>.from(_queue);
      _queue.clear();

      if (tasks.isEmpty) return;

      final mergedChanges = _mergeChangeSets(tasks.map((t) => t.changeSet));

      try {
        await _processWithRetry(() => processChanges(mergedChanges));
        _retryAttempt = 0;
        for (final task in tasks) {
          if (!task.completer.isCompleted) {
            task.completer.complete();
          }
        }
      } catch (e) {
        _logger.error(
            'Failed to process sync queue after $_retryAttempt attempts');
        for (final task in tasks) {
          if (!task.completer.isCompleted) {
            task.completer.completeError(e);
          }
        }
        rethrow;
      }
    } finally {
      _isProcessing = false;
      if (_queue.isNotEmpty) {
        _scheduleProcessing();
      }
    }
  }

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
      );

      await Future.delayed(delay);
      _retryAttempt++;
      await _processWithRetry(operation);
    }
  }

  Duration _calculateRetryDelay(int attempt) {
    final baseDelay = _baseRetryDelay.inMilliseconds;
    final maxDelay = Duration(minutes: 5).inMilliseconds;
    final exponentialDelay =
        baseDelay * pow(2, attempt).toInt() + Random().nextInt(1000);
    return Duration(milliseconds: min(exponentialDelay, maxDelay));
  }

  ChangeSet _mergeChangeSets(Iterable<ChangeSet> changeSets) {
    final allInsertions = <String, TableRows>{};
    final allUpdates = <String, TableRows>{};
    final allDeletions = <String, TableRows>{};
    final allChangeIds = <int>[];
    int latestTimestamp = 0;
    int latestVersion = 0;

    for (final changeSet in changeSets) {
      latestTimestamp = latestTimestamp < changeSet.timestamp
          ? changeSet.timestamp
          : latestTimestamp;
      latestVersion =
          latestVersion < changeSet.version ? changeSet.version : latestVersion;

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

      changeSet.deletions.changes.forEach((table, rows) {
        final existingRows = allDeletions[table]?.rows ?? [];
        final newRows = rows.rows;

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

  List<Row> _mergeRows(List<Row> existing, List<Row> newRows) {
    final mergedMap = <String, Row>{};

    for (final row in existing) {
      mergedMap[row.primaryKey] = row;
    }

    for (final row in newRows) {
      final existingRow = mergedMap[row.primaryKey];
      if (existingRow == null || existingRow.version <= row.version) {
        mergedMap[row.primaryKey] = row;
      }
    }

    return mergedMap.values.toList();
  }

  void dispose() {
    _debounceTimer?.cancel();
    _queue.clear();
  }
}
