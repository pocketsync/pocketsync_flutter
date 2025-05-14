import 'package:pocketsync_flutter/src/models/schema.dart';
import 'package:pocketsync_flutter/src/utils/sync_config.dart';

/// Internal class for processing schemas and adding change tracking functionality.
/// This class is not exported and is only used internally by the SDK.
/// @nodoc
class SchemaProcessor {
  /// Adds change tracking to a database schema.
  ///
  /// This method processes all user tables in the schema and adds the necessary
  /// columns and indexes for change tracking.
  static DatabaseSchema addChangeTracking(DatabaseSchema schema) {
    final updatedTables = <TableSchema>[];

    // Add internal tables first
    updatedTables.addAll(getInternalTablesSchema().tables);

    // Process user tables
    for (final table in schema.tables) {
      if (table.isInternalTable) {
        continue; // Skip internal tables from the original schema
      }

      // Add the global ID column if needed
      final tableWithTracking = _addGlobalIdColumn(table);

      // Create a new table with the updated columns and indexes
      updatedTables.add(TableSchema(
        name: tableWithTracking.name,
        columns: tableWithTracking.columns,
        indexes: tableWithTracking.indexes,
        isInternalTable: tableWithTracking.isInternalTable,
        isVirtual: tableWithTracking.isVirtual,
        module: tableWithTracking.module,
        moduleArgs: tableWithTracking.moduleArgs,
      ));
    }

    return DatabaseSchema(tables: updatedTables);
  }

  /// Adds a global ID column to a table if it doesn't already have one.
  static TableSchema _addGlobalIdColumn(TableSchema table) {
    if (table.isInternalTable) {
      return table;
    }

    // Check if the global ID column already exists
    final hasGlobalId = table.columns
        .any((column) => column.name == SyncConfig.defaultGlobalIdColumnName);

    if (hasGlobalId) {
      return table;
    }

    // Add the global ID column
    final updatedColumns = List<TableColumn>.from(table.columns);
    updatedColumns.add(TableColumn.text(
      name: SyncConfig.defaultGlobalIdColumnName,
      isNullable: true,
    ));

    // Add an index for the global ID column if it doesn't exist
    final hasGlobalIdIndex = table.indexes.any((index) =>
        index.columns.contains(SyncConfig.defaultGlobalIdColumnName));

    final updatedIndexes = List<Index>.from(table.indexes);
    if (!hasGlobalIdIndex) {
      updatedIndexes.add(Index(
        name: 'idx_${table.name}_${SyncConfig.defaultGlobalIdColumnName}',
        columns: [SyncConfig.defaultGlobalIdColumnName],
      ));
    }

    // Create a new table with the global ID column
    return TableSchema(
      name: table.name,
      columns: updatedColumns,
      indexes: updatedIndexes,
      isInternalTable: table.isInternalTable,
      isVirtual: table.isVirtual,
      module: table.module,
      moduleArgs: table.moduleArgs,
    );
  }

  /// Gets all user tables that need change tracking.
  static List<TableSchema> getUserTables(DatabaseSchema schema) {
    return schema.tables.where((table) => !table.isInternalTable).toList();
  }

  /// Gets the schema for internal tables used by PocketSync.
  /// @nodoc
  static DatabaseSchema getInternalTablesSchema() {
    return DatabaseSchema(
      tables: [
        _createChangesTable(),
        _createDeviceStateTable(),
        _createVersionTable(),
        _createProcessedTablesTable(),
      ],
    );
  }

  /// Creates the changes tracking table schema.
  /// @nodoc
  static TableSchema _createChangesTable() {
    return TableSchema(
      name: '__pocketsync_changes',
      isInternalTable: true,
      columns: [
        TableColumn.primaryKey(
          name: 'id',
          type: ColumnType.text,
          isNullable: false,
        ),
        TableColumn.text(
          name: 'table_name',
          isNullable: false,
        ),
        TableColumn.text(
          name: 'record_rowid',
          isNullable: false,
        ),
        TableColumn.text(
          name: 'operation',
          isNullable: false,
        ),
        TableColumn.integer(
          name: 'timestamp',
          isNullable: false,
        ),
        TableColumn.integer(
          name: 'synced',
          isNullable: false,
          defaultValue: 0,
        ),
      ],
      indexes: [
        Index(
          name: 'idx_pocketsync_changes_table_name',
          columns: ['table_name'],
        ),
        Index(
          name: 'idx_pocketsync_changes_synced',
          columns: ['synced'],
        ),
        Index(
          name: 'idx_pocketsync_changes_timestamp',
          columns: ['timestamp'],
        ),
      ],
    );
  }

  static TableSchema _createDeviceStateTable() {
    return TableSchema(
      name: '__pocketsync_device_state',
      isInternalTable: true,
      columns: [
        TableColumn.primaryKey(
          name: 'device_id',
          type: ColumnType.text,
          isNullable: false,
        ),
        TableColumn.integer(
          name: 'last_upload_timestamp',
          isNullable: false,
        ),
        TableColumn.integer(
          name: 'last_download_timestamp',
          isNullable: false,
        ),
        TableColumn.text(
          name: 'last_sync_status',
          isNullable: false,
        ),
        TableColumn.integer(
          name: 'last_cleanup_timestamp',
          isNullable: false,
        ),
      ],
    );
  }

  static TableSchema _createVersionTable() {
    return TableSchema(
      name: '__pocketsync_version',
      isInternalTable: true,
      columns: [
        TableColumn.primaryKey(
          name: 'id',
          type: ColumnType.integer,
          isNullable: false,
        ),
        TableColumn.text(
          name: 'version',
          isNullable: false,
        ),
        TableColumn.integer(
          name: 'last_reset_timestamp',
          isNullable: false,
        ),
      ],
    );
  }

  static TableSchema _createProcessedTablesTable() {
    return TableSchema(
      name: '__pocketsync_processed_tables',
      isInternalTable: true,
      columns: [
        TableColumn.primaryKey(
          name: 'table_name',
          type: ColumnType.text,
          isNullable: false,
        ),
        TableColumn.integer(
          name: 'processed_at',
          isNullable: false,
        ),
      ],
    );
  }

  /// Creates change tracking triggers for a table.
  ///
  /// This method generates SQL triggers for INSERT, UPDATE, and DELETE operations
  /// on the specified table to track changes for synchronization.
  /// @nodoc
  static List<Trigger> createChangeTrackingTriggers(TableSchema table) {
    if (table.isInternalTable) {
      return []; // Don't create triggers for internal tables
    }

    final triggers = <Trigger>[];
    final tableName = table.name;
    final columns = table.columns
        .where((c) => c.name != SyncConfig.defaultGlobalIdColumnName)
        .toList();

    // INSERT trigger
    triggers.add(Trigger(
      name: '${tableName}_after_insert',
      tableName: tableName,
      event: 'INSERT',
      timing: 'AFTER',
      statements: [
        '''
        INSERT INTO __pocketsync_changes 
        (table_name, record_rowid, operation, timestamp, synced) 
        VALUES (
          '$tableName', 
          NEW.${SyncConfig.defaultGlobalIdColumnName}, 
          'INSERT', 
          strftime('%s', 'now') * 1000, 
          0
        );
        '''
      ],
    ));

    // UPDATE trigger
    final whenConditions = columns.map((column) {
      return 'OLD.${column.name} IS NOT NEW.${column.name}';
    }).join(' OR ');

    triggers.add(Trigger(
      name: '${tableName}_after_update',
      tableName: tableName,
      event: 'UPDATE',
      timing: 'AFTER',
      when: whenConditions,
      statements: [
        '''
        INSERT INTO __pocketsync_changes 
        (table_name, record_rowid, operation, timestamp, synced) 
        VALUES (
          '$tableName', 
          NEW.${SyncConfig.defaultGlobalIdColumnName}, 
          'UPDATE', 
          strftime('%s', 'now') * 1000, 
          0
        );
        '''
      ],
    ));

    // DELETE trigger
    triggers.add(Trigger(
      name: '${tableName}_after_delete',
      tableName: tableName,
      event: 'DELETE',
      timing: 'AFTER',
      statements: [
        '''
        INSERT INTO __pocketsync_changes 
        (table_name, record_rowid, operation, timestamp, synced) 
        VALUES (
          '$tableName', 
          OLD.${SyncConfig.defaultGlobalIdColumnName}, 
          'DELETE', 
          strftime('%s', 'now') * 1000, 
          0
        );
        '''
      ],
    ));

    return triggers;
  }
}
