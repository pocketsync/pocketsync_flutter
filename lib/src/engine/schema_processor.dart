import 'package:pocketsync_flutter/src/models/schema.dart';
import 'package:pocketsync_flutter/src/utils/logger.dart';
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

  /// Perform validation on schema to ensure it meets requirements for PocketSync.
  ///
  /// This method checks for common issues in the schema definition that might
  /// cause problems during synchronization, such as:
  /// - Tables without primary keys
  /// - Reserved column names
  /// - Unsupported column types
  /// - Naming conflicts with internal tables
  ///
  /// Returns true if the schema is valid, false otherwise.
  /// Logs specific validation errors to help with debugging.
  static bool validateSchema(DatabaseSchema schema) {
    if (schema.tables.isEmpty) {
      Logger.log('Schema validation failed: No tables defined in schema');
      return false;
    }

    bool isValid = true;
    final reservedColumnNames = [
      SyncConfig.defaultGlobalIdColumnName,
      'id', // Not strictly reserved, but special handling is needed
      'rowid', // SQLite internal
      'oid', // SQLite internal
      '_rowid_', // SQLite internal
    ];

    final reservedTablePrefixes = [
      '__pocketsync',
      'sqlite_',
      'android_',
    ];

    // Check each user table
    for (final table in getUserTables(schema)) {
      // Check for reserved table names
      for (final prefix in reservedTablePrefixes) {
        if (table.name.startsWith(prefix)) {
          Logger.log(
              'Schema validation warning: Table ${table.name} uses reserved prefix $prefix');
          isValid = false;
        }
      }

      // Check if table has a primary key
      final hasPrimaryKey = table.columns.any((col) => col.isPrimaryKey);
      if (!hasPrimaryKey) {
        Logger.log(
            'Schema validation failed: Table ${table.name} has no primary key');
        isValid = false;
      }

      // Check column names and types
      for (final column in table.columns) {
        // Check for reserved column names
        if (reservedColumnNames.contains(column.name.toLowerCase()) &&
            column.name != 'id' && // Allow 'id' as it's commonly used as PK
            column.name != SyncConfig.defaultGlobalIdColumnName) {
          // Allow global ID if explicitly defined
          Logger.log(
              'Schema validation warning: Column ${column.name} in table ${table.name} uses reserved name');
        }

        // Check for unsupported column types or configurations
        if (column.type == ColumnType.blob && column.isPrimaryKey) {
          Logger.log(
              'Schema validation warning: BLOB type not recommended for primary key in ${table.name}.${column.name}');
        }
      }

      // Check for duplicate column names (case insensitive in SQLite)
      final columnNames =
          table.columns.map((c) => c.name.toLowerCase()).toList();
      final uniqueColumnNames = columnNames.toSet().toList();
      if (columnNames.length != uniqueColumnNames.length) {
        Logger.log(
            'Schema validation failed: Table ${table.name} has duplicate column names (SQLite is case-insensitive)');
        isValid = false;
      }

      // Check for duplicate index names
      if (table.indexes.isNotEmpty) {
        final indexNames =
            table.indexes.map((i) => i.name.toLowerCase()).toList();
        final uniqueIndexNames = indexNames.toSet().toList();
        if (indexNames.length != uniqueIndexNames.length) {
          Logger.log(
              'Schema validation failed: Table ${table.name} has duplicate index names');
          isValid = false;
        }
      }
    }

    return isValid;
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
        TableColumn.text(
          name: 'data',
          isNullable: false,
        ),
        TableColumn.integer(
          name: 'version',
          isNullable: false,
        ),
        TableColumn.integer(
          name: 'synced',
          isNullable: false,
          defaultValue: 0,
        ),
      ],
      indexes: [
        Index(name: 'idx_pocketsync_changes_synced', columns: ['synced']),
        Index(name: 'idx_pocketsync_changes_version', columns: ['version']),
        Index(name: 'idx_pocketsync_changes_timestamp', columns: ['timestamp']),
        Index(
            name: 'idx_pocketsync_changes_table_name', columns: ['table_name']),
        Index(
            name: 'idx_pocketsync_changes_record_rowid',
            columns: ['record_rowid']),
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
          isNullable: true,
        ),
        TableColumn.integer(
          name: 'last_download_timestamp',
          isNullable: true,
        ),
        TableColumn.text(
          name: 'last_sync_status',
          isNullable: false,
          defaultValue: 'NEVER_SYNCED',
        ),
        TableColumn.integer(
          name: 'last_cleanup_timestamp',
          isNullable: true,
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
}
