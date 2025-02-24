import 'dart:convert';
import 'dart:isolate';

import 'package:pocketsync_flutter/pocketsync_flutter.dart';
import 'package:pocketsync_flutter/src/database/database_change_manager.dart';
import 'package:pocketsync_flutter/src/models/change_log.dart';
import 'package:pocketsync_flutter/src/models/change_set.dart';
import 'package:pocketsync_flutter/src/services/logger_service.dart';
import 'package:sqflite/sqflite.dart';

class ChangesProcessor {
  static const _maxQueueSize = 10000;

  final Database _db;
  final DatabaseChangeManager _databaseChangeManager;
  final ConflictResolver _conflictResolver;
  final _logger = LoggerService.instance;
  bool _isApplyingRemoteChanges = false;

  ChangesProcessor(
    this._db, {
    ConflictResolver? conflictResolver,
    DatabaseChangeManager? databaseChangeManager,
  })  : _conflictResolver = conflictResolver ?? const ConflictResolver(),
        _databaseChangeManager =
            databaseChangeManager ?? DatabaseChangeManager();

  /// Gets local changes formatted as a ChangeSet
  /// Uses batch processing for better performance with large datasets
  Future<void> _pruneChangeQueue() async {
    final count = await _db
        .rawQuery('SELECT COUNT(*) FROM __pocketsync_changes WHERE synced = 0')
        .then((result) => result.first.values.first as int? ?? 0);

    if (count > _maxQueueSize) {
      await _db.transaction((txn) async {
        await txn.execute('''
          UPDATE __pocketsync_changes 
          SET synced = -1 
          WHERE id NOT IN (
            SELECT id FROM __pocketsync_changes 
            WHERE synced = 0 
            ORDER BY timestamp DESC 
            LIMIT $_maxQueueSize
          ) AND synced = 0
        ''');
      });

      _logger.warning('Pruned change queue to $_maxQueueSize items');
    }
  }

  Future<ChangeSet> getUnSyncedChanges({int batchSize = 1000}) async {
    await _pruneChangeQueue();
    return await _db.transaction((txn) async {
      final insertions = <String, List<Row>>{};
      final updates = <String, List<Row>>{};
      final deletions = <String, List<Row>>{};
      int lastId = 0;
      int lastVersion = 0;
      final changeIds = <int>[];

      _logger.debug(
        'Starting to fetch unsynced changes with batch size: $batchSize',
      );

      while (true) {
        List<Map<String, dynamic>> changes;
        try {
          changes = await txn.query(
            '__pocketsync_changes',
            where: 'synced = 0 AND id > ?',
            whereArgs: [lastId],
            orderBy: 'id ASC',
            limit: batchSize,
          );
        } catch (e) {
          _logger.error('Error querying changes', error: e);
          throw SyncStateError('Failed to query changes: ${e.toString()}');
        }

        if (changes.isEmpty) break;

        _logger.debug('Processing batch of ${changes.length} changes');

        for (final change in changes) {
          try {
            final id = change['id'] as int;
            final tableName = change['table_name'] as String;
            final operation = change['operation'] as String;
            final version = change['version'] as int;
            final timestamp = change['timestamp'] as int;

            Map<String, dynamic> data;
            try {
              final rawData = jsonDecode(change['data'] as String);
              if (rawData is! Map<String, dynamic>) {
                throw FormatException('Change data must be a JSON object');
              }

              data = rawData.containsKey('new')
                  ? (rawData['new'] as Map<String, dynamic>)
                  : rawData.containsKey('old')
                      ? (rawData['old'] as Map<String, dynamic>)
                      : rawData;
            } catch (e) {
              _logger.error('Error parsing change data for id $id: $e');
              throw SyncStateError(
                'Failed to parse change data: ${e.toString()}',
              );
            }

            // Use rowid as the primary key identifier
            final primaryKey = change['record_rowid'].toString();

            final row = Row(
              primaryKey: primaryKey,
              timestamp: timestamp,
              data: data,
              version: version,
            );

            switch (operation) {
              case 'INSERT':
                insertions.putIfAbsent(tableName, () => []).add(row);
                break;
              case 'UPDATE':
                updates.putIfAbsent(tableName, () => []).add(row);
                break;
              case 'DELETE':
                deletions.putIfAbsent(tableName, () => []).add(row);
                break;
              default:
                _logger.error('Invalid operation type: $operation');
                throw SyncStateError('Invalid operation type: $operation');
            }

            changeIds.add(id);
            lastId = id;
            if (version > lastVersion) lastVersion = version;
          } catch (e) {
            if (e is SyncError) rethrow;
            _logger.error('Error processing change: $e');
            throw SyncStateError('Failed to process change: ${e.toString()}');
          }
        }
      }

      return ChangeSet(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        version: lastVersion,
        localChangeIds: changeIds,
        insertions: TableChanges(
          Map.fromEntries(
            insertions.entries.map((e) => MapEntry(e.key, TableRows(e.value))),
          ),
        ),
        updates: TableChanges(
          Map.fromEntries(
            updates.entries.map((e) => MapEntry(e.key, TableRows(e.value))),
          ),
        ),
        deletions: TableChanges(
          Map.fromEntries(
            deletions.entries.map((e) => MapEntry(e.key, TableRows(e.value))),
          ),
        ),
      );
    });
  }

  /// Marks changes as synced
  Future<void> markChangesSynced(List<int> changeIds) async {
    await _db.update(
      '__pocketsync_changes',
      {'synced': 1},
      where: 'id IN (${changeIds.map((e) => e).join(',')})',
    );
  }

  static ChangeSet _computeChangeSetFromChangeLogs(
      Iterable<ChangeLog> changeLogs) {
    final insertions = <String, List<Row>>{};
    final updates = <String, List<Row>>{};
    final deletions = <String, List<Row>>{};

    // Process each changelog to merge changes
    for (final log in changeLogs) {
      // Merge insertions
      log.changeSet.insertions.changes.forEach((tableName, tableRows) {
        insertions.putIfAbsent(tableName, () => []).addAll(
              tableRows.rows.map(
                (row) => Row(
                  primaryKey: row.primaryKey,
                  timestamp: row.timestamp,
                  data: row.data,
                  version: row.version,
                ),
              ),
            );
      });

      // Merge updates
      log.changeSet.updates.changes.forEach((tableName, tableRows) {
        updates.putIfAbsent(tableName, () => []).addAll(
              tableRows.rows.map(
                (row) => Row(
                  primaryKey: row.primaryKey,
                  timestamp: row.timestamp,
                  data: row.data,
                  version: row.version,
                ),
              ),
            );
      });

      // Merge deletions
      log.changeSet.deletions.changes.forEach((tableName, tableRows) {
        deletions.putIfAbsent(tableName, () => []).addAll(
              tableRows.rows.map(
                (row) => Row(
                  primaryKey: row.primaryKey,
                  timestamp: row.timestamp,
                  data: row.data,
                  version: row.version,
                ),
              ),
            );
      });
    }

    // Create merged ChangeSet from all changelogs
    return ChangeSet(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      version: changeLogs.isEmpty ? 0 : changeLogs.last.changeSet.version,
      serverChangeIds: changeLogs.map((log) => log.id).toList(),
      insertions: TableChanges(
        Map.fromEntries(
          insertions.entries.map((e) => MapEntry(e.key, TableRows(e.value))),
        ),
      ),
      updates: TableChanges(
        Map.fromEntries(
          updates.entries.map((e) => MapEntry(e.key, TableRows(e.value))),
        ),
      ),
      deletions: TableChanges(
        Map.fromEntries(
          deletions.entries.map((e) => MapEntry(e.key, TableRows(e.value))),
        ),
      ),
    );
  }

  /// Notifies database changes to registered listeners
  void _notifyChanges(ChangeSet changeSet) {
    if (changeSet.isNotEmpty) {
      final changedTables = <String>{};

      void collectChangedTables(Map<String, TableRows> changes) {
        changedTables.addAll(changes.keys);
      }

      collectChangedTables(changeSet.insertions.changes);
      collectChangedTables(changeSet.updates.changes);
      collectChangedTables(changeSet.deletions.changes);

      _logger.info('Notifying changes for ${changedTables.length} tables');

      for (final table in changedTables) {
        _databaseChangeManager.notifyChange(
          table,
          isRemote: _isApplyingRemoteChanges,
        );
      }
    }
  }

  /// Applies remote changes to local database
  /// Checks which change logs have already been processed
  Future<List<int>> _getProcessedChangeLogIds(List<int> changeLogIds) async {
    if (changeLogIds.isEmpty) return [];

    final result = await _db.query(
      '__pocketsync_processed_changes',
      columns: ['change_log_id'],
      where: 'change_log_id IN (${changeLogIds.map((_) => '?').join(",")})',
      whereArgs: changeLogIds,
    );

    return result.map((row) => row['change_log_id'] as int).toList();
  }

  Future<void> applyRemoteChanges(Iterable<ChangeLog> changeLogs) async {
    if (changeLogs.isEmpty) return;

    final allChangeLogIds = changeLogs.map((log) => log.id).toList();
    final processedIds = await _getProcessedChangeLogIds(allChangeLogIds);
    final unprocessedChangeLogs =
        changeLogs.where((log) => !processedIds.contains(log.id));

    if (unprocessedChangeLogs.isEmpty) {
      _logger.info('All changes have already been processed');
      return;
    }

    _logger.info(
      'Processing ${unprocessedChangeLogs.length} changes',
    );

    _isApplyingRemoteChanges = true;
    try {
      // Pre-fetch existing rows on main thread since it requires DB access
      final changeSet = _computeChangeSetFromChangeLogs(changeLogs);
      final existingRows = await _db.transaction((txn) async {
        return await _preloadExistingRows(changeSet, txn);
      });

      // Process changes in background isolate
      final result = await _processChangesInIsolate(
        changeLogs.toList(),
        existingRows,
      );

      // Apply processed changes to database on main thread
      await _applyProcessedChanges(result);

      if (result.changeSet.isNotEmpty) {
        // Update last sync timestamp
        await _db.update(
          '__pocketsync_device_state',
          {'last_sync_timestamp': DateTime.now().millisecondsSinceEpoch},
        );

        _logger.info(
          'Successfully applied ${result.changeSet.length} remote changes',
        );
        _notifyChanges(result.changeSet);
      }
    } finally {
      _isApplyingRemoteChanges = false;
    }
  }

  /// Processes changes in a background isolate
  Future<_IsolateResult> _processChangesInIsolate(
    List<ChangeLog> changeLogs,
    Map<String, Map<String, Map<String, dynamic>>> existingRows,
  ) async {
    final receivePort = ReceivePort();
    final isolate = await Isolate.spawn(
      _processChangesIsolate,
      _IsolateMessage(
        changeLogs,
        existingRows,
        receivePort.sendPort,
        _conflictResolver,
      ),
    );

    try {
      final result = await receivePort.first as _IsolateResult;
      return result;
    } finally {
      receivePort.close();
      isolate.kill();
    }
  }

  /// Static method to run in isolate
  @pragma('vm:entry-point')
  static void _processChangesIsolate(_IsolateMessage message) {
    final changeSet = _computeChangeSetFromChangeLogs(message.changeLogs);
    final processedRows = <String, List<Map<String, dynamic>>>{};
    final affectedTables = <String>{};

    // Process deletions
    for (final entry in changeSet.deletions.changes.entries) {
      final tableName = entry.key;
      final rows = entry.value.rows;
      if (rows.isEmpty) continue;

      processedRows[tableName] = [];
      affectedTables.add(tableName);
    }

    // Process modifications (updates and inserts)
    void processModifications(
        Map<String, TableRows> changes, String operation) {
      for (final entry in changes.entries) {
        final tableName = entry.key;
        final rows = entry.value.rows;
        if (rows.isEmpty) continue;

        final tableExistingRows = message.existingRows[tableName] ?? {};
        final validRows = <Map<String, dynamic>>[];

        for (final row in rows) {
          final existing = tableExistingRows[row.primaryKey];

          if (existing != null) {
            final existingTimestamp = existing['timestamp'] as int?;
            if (existingTimestamp != null &&
                existingTimestamp >= row.timestamp) {
              continue; // Skip if existing version is newer
            }

            try {
              final resolvedRow = message.conflictResolver.resolveConflict(
                tableName,
                existing,
                row.data,
              );
              validRows.add(resolvedRow);
            } catch (e) {
              // If custom resolution is not supported, default to server wins
              validRows.add(row.data);
            }
          } else if (operation == 'INSERT') {
            validRows.add(row.data);
          }
        }

        if (validRows.isNotEmpty) {
          processedRows[tableName] = validRows;
          affectedTables.add(tableName);
        }
      }
    }

    processModifications(changeSet.updates.changes, 'UPDATE');
    processModifications(changeSet.insertions.changes, 'INSERT');

    message.sendPort.send(_IsolateResult(
      changeSet,
      processedRows,
      affectedTables.toList(),
    ));
  }

  /// Applies the processed changes to the database
  Future<void> _applyProcessedChanges(_IsolateResult result) async {
    await _db.transaction((txn) async {
      await txn.execute('PRAGMA recursive_triggers = OFF;');

      try {
        // Apply deletions first
        for (final entry in result.changeSet.deletions.changes.entries) {
          final tableName = entry.key;
          final rows = entry.value.rows;
          if (rows.isEmpty) continue;

          final primaryKeys = rows.map((r) => r.primaryKey).toList();
          final placeholders = List.filled(primaryKeys.length, '?').join(',');

          await txn.rawDelete(
            'DELETE FROM $tableName WHERE ps_global_id IN ($placeholders)',
            primaryKeys,
          );
        }

        // Apply modifications
        for (final tableName in result.affectedTables) {
          final rows = result.processedRows[tableName];
          if (rows == null || rows.isEmpty) continue;

          final batchSize = 100;
          for (var i = 0; i < rows.length; i += batchSize) {
            final batch = rows.skip(i).take(batchSize).toList();
            final columns = batch.first.keys.toList();
            final placeholders = List.filled(columns.length, '?').join(',');
            final values = batch.map((_) => '($placeholders)').join(',');

            await txn.rawInsert(
              'INSERT OR REPLACE INTO $tableName (${columns.join(',')}) VALUES $values',
              batch.expand((row) => columns.map((c) => row[c])).toList(),
            );
          }
        }

        // Mark changes as processed
        final now = DateTime.now().toIso8601String();
        await txn.rawInsert(
          'INSERT OR REPLACE INTO __pocketsync_processed_changes (change_log_id, processed_at) VALUES ${result.changeSet.serverChangeIds.map((_) => '(?, ?)').join(', ')}',
          result.changeSet.serverChangeIds.expand((id) => [id, now]).toList(),
        );
      } finally {
        await txn.execute('PRAGMA recursive_triggers = ON;');
      }
    });
  }

  /// Pre-loads existing rows for all affected records to minimize database queries
  Future<Map<String, Map<String, Map<String, dynamic>>>> _preloadExistingRows(
    ChangeSet changeSet,
    Transaction txn,
  ) async {
    final result = <String, Map<String, Map<String, dynamic>>>{};
    final allChanges = {
      ...changeSet.updates.changes,
      ...changeSet.insertions.changes,
    };

    for (final entry in allChanges.entries) {
      final tableName = entry.key;
      final rows = entry.value.rows;
      if (rows.isEmpty) continue;

      // Batch fetch existing rows
      final primaryKeys = rows.map((r) => r.primaryKey).toList();
      final placeholders = List.filled(primaryKeys.length, '?').join(',');
      final existingRows = await txn.query(
        tableName,
        where: 'ps_global_id IN ($placeholders)',
        whereArgs: primaryKeys,
      );

      // Index rows by primary key
      result[tableName] = {
        for (final row in existingRows) row['ps_global_id'] as String: row,
      };
    }

    return result;
  }
}

/// Message for isolate processing
class _IsolateMessage {
  final List<ChangeLog> changeLogs;
  final Map<String, Map<String, Map<String, dynamic>>> existingRows;
  final SendPort sendPort;
  final ConflictResolver conflictResolver;

  _IsolateMessage(
    this.changeLogs,
    this.existingRows,
    this.sendPort,
    this.conflictResolver,
  );
}

/// Result from isolate processing
class _IsolateResult {
  final ChangeSet changeSet;
  final Map<String, List<Map<String, dynamic>>> processedRows;
  final List<String> affectedTables;

  _IsolateResult(this.changeSet, this.processedRows, this.affectedTables);
}
