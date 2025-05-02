import 'dart:convert';

import 'package:pocketsync_flutter/src/models/types.dart';
import 'package:pocketsync_flutter/src/utils/logger.dart';

/// Represents a single change to be synchronized with the server.
///
/// This class provides a standardized structure for changes that need to be
/// transmitted to the server during synchronization.
class SyncChange {
  /// Unique identifier for the change
  final int id;

  /// The table that was changed
  final String tableName;

  /// The global ID of the record that was changed
  final String recordId;

  /// The type of operation (insert, update, delete)
  final ChangeType operation;

  /// Timestamp when the change occurred (milliseconds since epoch)
  final int timestamp;

  /// Version number for the change
  final int version;

  /// Whether the change has been synced to the server
  final bool synced;

  /// The data associated with the change
  ///
  /// For inserts, this contains only 'new' data.
  /// For updates, this contains both 'old' and 'new' data.
  /// For deletes, this contains only 'old' data.
  final Map<String, dynamic> data;

  /// Creates a new SyncChange.
  SyncChange({
    required this.id,
    required this.tableName,
    required this.recordId,
    required this.operation,
    required this.timestamp,
    required this.version,
    this.synced = false,
    required this.data,
  });

  /// Creates a SyncChange from a database record.
  ///
  /// This factory method converts a raw database record from the
  /// __pocketsync_changes table into a structured SyncChange object.
  factory SyncChange.fromDatabaseRecord(Map<String, dynamic> record) {
    // Parse the operation string to the enum value
    final operationStr = record['operation'] as String;
    final operation = ChangeType.values.firstWhere(
      (op) => op.name.toUpperCase() == operationStr,
      orElse: () => ChangeType.update,
    );

    // Parse the JSON data
    Map<String, dynamic> data;
    try {
      final dataStr = record['data'] as String;
      data = json.decode(dataStr) as Map<String, dynamic>;
    } catch (e) {
      Logger.log('Error parsing change data: $e');
      data = {};
    }

    return SyncChange(
      id: record['id'] as int,
      tableName: record['table_name'] as String,
      recordId: record['record_rowid'] as String,
      operation: operation,
      timestamp: record['timestamp'] as int,
      version: record['version'] as int,
      synced: (record['synced'] as int) == 1,
      data: data,
    );
  }

  /// Converts the SyncChange to a map for transmission to the server.
  ///
  /// This method creates a standardized format for sending changes to the server.
  Map<String, dynamic> toTransmissionFormat() {
    return {
      'change_id': id,
      'table_name': tableName,
      'record_id': recordId,
      'operation': operation.name,
      'timestamp': timestamp,
      'version': version,
      'data': data,
    };
  }

  /// Converts a list of database records to SyncChange objects.
  ///
  /// This utility method converts a list of raw database records into
  /// a list of structured SyncChange objects.
  static List<SyncChange> fromDatabaseRecords(
      List<Map<String, dynamic>> records) {
    return records
        .map((record) => SyncChange.fromDatabaseRecord(record))
        .toList();
  }

  @override
  String toString() {
    return 'SyncChange{id: $id, tableName: $tableName, recordId: $recordId, '
        'operation: ${operation.name}, version: $version, synced: $synced}';
  }
}

/// Represents a batch of changes to be synchronized with the server.
///
/// This class groups multiple SyncChange objects together for efficient
/// transmission to the server.
class SyncChangeBatch {
  /// The device ID that generated these changes
  final String deviceId;

  /// The user ID associated with these changes
  final String userId;

  /// The list of changes in this batch
  final List<SyncChange> changes;

  /// Creates a new SyncChangeBatch.
  SyncChangeBatch({
    required this.deviceId,
    required this.userId,
    required this.changes,
  });

  /// Converts the SyncChangeBatch to a map for transmission to the server.
  ///
  /// This method creates a standardized format for sending a batch of changes
  /// to the server.
  Map<String, dynamic> toTransmissionFormat() {
    return {
      'device_id': deviceId,
      'user_id': userId,
      'changes':
          changes.map((change) => change.toTransmissionFormat()).toList(),
      'batch_timestamp': DateTime.now().millisecondsSinceEpoch,
      'change_count': changes.length,
    };
  }

  /// Converts the SyncChangeBatch to a JSON string for transmission to the server.
  String toJson() {
    return json.encode(toTransmissionFormat());
  }
}
