import 'dart:convert';

import 'package:pocketsync_flutter/src/models/sync_change.dart';
import 'package:pocketsync_flutter/src/utils/logger.dart';
import 'package:sqflite/sqflite.dart';

/// Optimizes database changes into efficient transmission chunks.
///
/// The ChangeAggregator is responsible for retrieving changes from the database
/// and optimizing them for efficient transmission to the server. It combines
/// related changes and collapses multiple changes to the same record when possible.
class ChangeAggregator {
  final Database _database;

  /// Creates a new ChangeAggregator.
  ///
  /// Requires a [Database] to access the local database.
  ChangeAggregator({required Database database}) : _database = database;

  /// Aggregates changes for a specific table.
  ///
  /// This method retrieves all pending changes for the specified table from the
  /// database and optimizes them for transmission. It combines related changes
  /// and collapses multiple changes to the same record when possible.
  /// 
  /// Returns a list of [SyncChange] objects ready for transmission to the server.
  Future<List<SyncChange>> aggregateChanges(String tableName) async {
    final rawChanges = await _database.query(
      '__pocketsync_changes',
      where: 'table_name = ? AND synced = 0',
      whereArgs: [tableName],
      orderBy: 'record_rowid, timestamp ASC',
    );

    if (rawChanges.isEmpty) {
      return [];
    }

    // Group changes by record ID
    final changesByRecord = <String, List<Map<String, dynamic>>>{};

    for (final change in rawChanges) {
      final recordId = change['record_rowid'] as String;
      changesByRecord.putIfAbsent(recordId, () => []).add(change);
    }

    // Process each record's changes to optimize
    final optimizedChanges = <Map<String, dynamic>>[];

    for (final recordId in changesByRecord.keys) {
      final recordChanges = changesByRecord[recordId]!;

      // If there's only one change for this record, add it directly
      if (recordChanges.length == 1) {
        optimizedChanges.add(recordChanges.first);
        continue;
      }

      // Multiple changes for the same record - optimize
      final optimizedChange = _optimizeChangesForRecord(recordChanges);
      if (optimizedChange != null) {
        optimizedChanges.add(optimizedChange);
      }
    }
    
    return SyncChange.fromDatabaseRecords(optimizedChanges);
  }

  /// Optimizes multiple changes for a single record.
  ///
  /// This method analyzes the sequence of changes for a single record and
  /// collapses them into a single optimized change when possible.
  Map<String, dynamic>? _optimizeChangesForRecord(
      List<Map<String, dynamic>> changes) {
    // If there are no changes, return null
    if (changes.isEmpty) return null;

    // If there's only one change, return it directly
    if (changes.length == 1) return changes.first;

    // Get the first and last operations
    final firstChange = changes.first;
    final lastChange = changes.last;
    final firstOp = firstChange['operation'] as String;
    final lastOp = lastChange['operation'] as String;

    // Special case: If the record was inserted and then deleted, we can skip both operations
    if (firstOp == 'INSERT' && lastOp == 'DELETE') {
      // If the record was created and then deleted within this sync batch,
      // we can skip syncing it altogether
      return null;
    }

    // Special case: If the record was deleted, only the delete matters
    if (lastOp == 'DELETE') {
      return lastChange;
    }

    // For INSERT followed by UPDATEs, we can combine them into a single INSERT
    if (firstOp == 'INSERT') {
      // Start with the first change
      final optimizedChange = Map<String, dynamic>.from(firstChange);

      // Update with the latest data
      final lastData = _parseChangeData(lastChange['data'] as String);
      if (lastData.containsKey('new')) {
        // Update the data with the latest values
        final newData = {
          'new': lastData['new'],
        };

        optimizedChange['data'] = _serializeChangeData(newData);
        optimizedChange['version'] = lastChange['version'];
        optimizedChange['timestamp'] = lastChange['timestamp'];
      }

      return optimizedChange;
    }

    // For multiple UPDATEs, we can combine them into a single UPDATE
    if (firstOp == 'UPDATE' && lastOp == 'UPDATE') {
      // Start with the first change
      final optimizedChange = Map<String, dynamic>.from(firstChange);

      // Get the original 'old' data from the first change
      final firstData = _parseChangeData(firstChange['data'] as String);

      // Get the latest 'new' data from the last change
      final lastData = _parseChangeData(lastChange['data'] as String);

      // Combine them to create a single update that goes from the original state to the final state
      final newData = {
        'old': firstData['old'],
        'new': lastData['new'],
      };

      optimizedChange['data'] = _serializeChangeData(newData);
      optimizedChange['version'] = lastChange['version'];
      optimizedChange['timestamp'] = lastChange['timestamp'];

      return optimizedChange;
    }

    // Default: If we can't optimize, return the last change
    return lastChange;
  }

  /// Parses the JSON data from a change record.
  Map<String, dynamic> _parseChangeData(String data) {
    try {
      return Map<String, dynamic>.from(
        const JsonDecoder().convert(data) as Map,
      );
    } catch (e) {
      Logger.log('ChangeAggregator: Error parsing change data: $e');
      return {};
    }
  }

  /// Serializes change data to JSON.
  String _serializeChangeData(Map<String, dynamic> data) {
    try {
      return const JsonEncoder().convert(data);
    } catch (e) {
      Logger.log('ChangeAggregator: Error serializing change data: $e');
      return '{}';
    }
  }
}
