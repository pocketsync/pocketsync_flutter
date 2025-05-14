import 'package:pocketsync_flutter/src/models/schema.dart';
import 'package:pocketsync_flutter/src/engine/schema_processor.dart';
import 'package:pocketsync_flutter/src/utils/logger.dart';
import 'package:pocketsync_flutter/src/utils/sync_config.dart';
import 'package:pocketsync_flutter/src/models/types.dart';
import 'package:sqflite/sqflite.dart';

/// Manages database schema operations including setup, change tracking, and migrations.
/// @nodoc
class SchemaManager {
  /// The database schema to use for creating tables.
  /// If null, no tables will be created automatically.
  final DatabaseSchema _schema;

  /// Creates a new schema manager.
  SchemaManager({required DatabaseSchema schema}) : _schema = schema;

  /// Sets up change tracking for all user tables.
  ///
  /// This method adds the global ID column and creates indexes for all user tables.
  /// It also creates triggers for change tracking.
  Future<void> setupChangeTracking(Database db) async {
    final tables = await _getUserTables(db);

    // Process each user table
    for (final tableName in tables) {
      await db.transaction((txn) async {
        try {
          // Add global ID column if it doesn't exist
          if (!await _columnExists(
              txn, tableName, SyncConfig.defaultGlobalIdColumnName)) {
            await txn.execute(
              'ALTER TABLE $tableName ADD COLUMN ${SyncConfig.defaultGlobalIdColumnName} TEXT NULL',
            );
          }

          // Create index if it doesn't exist
          final globalIdIndexName =
              'idx_${tableName}_${SyncConfig.defaultGlobalIdColumnName}';
          if (!await _indexExists(txn, globalIdIndexName)) {
            await txn.execute(
              'CREATE INDEX $globalIdIndexName ON $tableName(${SyncConfig.defaultGlobalIdColumnName})',
            );
          }

          // Generate global IDs for existing records that don't have one
          await txn.execute('''
            UPDATE $tableName
            SET ${SyncConfig.defaultGlobalIdColumnName} = hex(randomblob(16))
            WHERE ${SyncConfig.defaultGlobalIdColumnName} IS NULL
          ''');

          // Create triggers for change tracking
          await _createTableTriggers(txn, tableName);
        } catch (e) {
          Logger.log('Error setting up change tracking for $tableName: $e');
          rethrow;
        }
      });
    }
  }

  /// Creates tables from the schema.
  ///
  /// This method creates tables and indexes based on the schema definition.
  /// It also adds change tracking support to tables that need it.
  Future<void> createTablesFromSchema(Database db) async {
    // Add change tracking to the schema
    final schemaWithTracking = SchemaProcessor.addChangeTracking(_schema);

    // Generate SQL statements for each table
    final sqlStatements = _generateSqlStatements(schemaWithTracking);

    await db.transaction((txn) async {
      for (final sql in sqlStatements) {
        try {
          await txn.execute(sql);
        } catch (e) {
          Logger.log('Error executing SQL: $sql');
          Logger.log('Error: $e');
          rethrow;
        }
      }

      // Generate global IDs for all tables that need change tracking
      for (final table in SchemaProcessor.getUserTables(schemaWithTracking)) {
        await txn.execute('''
          UPDATE ${table.name}
          SET ${SyncConfig.defaultGlobalIdColumnName} = hex(randomblob(16))
          WHERE ${SyncConfig.defaultGlobalIdColumnName} IS NULL
        ''');
      }
    });
  }

  /// Initializes the database with the required tables and change tracking.
  Future<void> initializeDatabase(Database db) async {
    await createTablesFromSchema(db);
  }

  /// Initializes PocketSync tables (legacy method name).
  ///
  /// This is an alias for initializeDatabase for backward compatibility.
  Future<void> initializePocketSyncTables(Database db) async {
    // Wrap in transaction for atomicity
    await db.transaction((txn) async {
      // Create changes tracking table
      await txn.execute('''
        CREATE TABLE IF NOT EXISTS __pocketsync_changes (
          id TEXT PRIMARY KEY,
          table_name TEXT NOT NULL,
          record_rowid TEXT NOT NULL,
          operation TEXT NOT NULL,
          timestamp INTEGER NOT NULL,
          data TEXT NOT NULL,
          version INTEGER NOT NULL,
          synced INTEGER DEFAULT 0
        );

        -- Create indexes for optimizing queries
        CREATE INDEX IF NOT EXISTS idx_pocketsync_changes_synced ON __pocketsync_changes(synced);
        CREATE INDEX IF NOT EXISTS idx_pocketsync_changes_version ON __pocketsync_changes(version);
        CREATE INDEX IF NOT EXISTS idx_pocketsync_changes_timestamp ON __pocketsync_changes(timestamp);
        CREATE INDEX IF NOT EXISTS idx_pocketsync_changes_table_name ON __pocketsync_changes(table_name);
        CREATE INDEX IF NOT EXISTS idx_pocketsync_changes_record_rowid ON __pocketsync_changes(record_rowid)
      ''');

      // Create device state tracking table
      await txn.execute('''
        CREATE TABLE IF NOT EXISTS __pocketsync_device_state (
          device_id TEXT PRIMARY KEY,
          last_upload_timestamp INTEGER NULL,
          last_download_timestamp INTEGER NULL,
          last_sync_status TEXT NULL,
          last_cleanup_timestamp INTEGER NULL
        )
      ''');

      // Create version tracking table
      await txn.execute('''
        CREATE TABLE IF NOT EXISTS __pocketsync_version (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          version TEXT NOT NULL,
          last_reset_timestamp INTEGER NOT NULL
        )
      ''');

      // Create table for tracking pre-existing data processing
      await txn.execute('''
        CREATE TABLE IF NOT EXISTS __pocketsync_processed_tables (
          table_name TEXT PRIMARY KEY,
          processed_at INTEGER NOT NULL
        )
      ''');
    });
  }

  /// Handles schema changes by recreating tables if needed.
  Future<void> handleSchemaChanges(Database db) async {
    final tables = await _getUserTables(db);

    for (final tableName in tables) {
      await db.transaction((txn) async {
        try {
          // This will recreate triggers with current schema
          await _createTableTriggers(txn, tableName);
        } catch (e) {
          Logger.log('Error updating triggers for $tableName: $e');
          rethrow;
        }
      });
    }
  }

  // Register this device in the sync system
  Future<void> registerDevice(Database db, String deviceId) async {
    final existingDevice = await db.query(
      '__pocketsync_device_state',
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );

    if (existingDevice.isEmpty) {
      await db.insert(
        '__pocketsync_device_state',
        {
          'device_id': deviceId,
          'last_upload_timestamp': null,
          'last_download_timestamp': null,
          'last_sync_status': 'NEVER_SYNCED'
        },
      );
    }
  }

  // This method is now implemented below

  // These methods are implemented below

  /// Disables all change tracking triggers.
  ///
  /// This method disables all PocketSync triggers in the database.
  Future<void> disableTriggers(Database db) async {
    final tables = await _getUserTables(db);

    for (final tableName in tables) {
      await db.transaction((txn) async {
        try {
          await _dropExistingTriggers(txn, tableName);
        } catch (e) {
          Logger.log('Error disabling triggers for $tableName: $e');
          rethrow;
        }
      });
    }
  }

  /// Resets the PocketSync state completely.
  ///
  /// This method performs a complete reset of PocketSync by:
  /// 1. Disabling all change tracking triggers
  /// 2. Dropping all PocketSync internal tables (both current and previous versions)
  /// 3. Recreating the necessary tables
  /// 4. Re-enabling change tracking
  /// 5. Storing the current plugin version to prevent unnecessary resets
  ///
  /// This is useful for resetting the sync state on a device or when migrating
  /// from a previous version of the SDK.
  ///
  /// The reset will only be performed if the current plugin version differs from
  /// the stored version, ensuring it's only run once per plugin version.
  Future<void> reset(Database db) async {
    final shouldReset =
        await _shouldResetForVersion(db, SyncConfig.pluginVersion);
    if (!shouldReset) {
      Logger.log(
          'SchemaManager: Reset already performed for version ${SyncConfig.pluginVersion}, skipping');
      return;
    }

    try {
      await disableTriggers(db);

      await db.transaction((txn) async {
        await txn.execute('DROP TABLE IF EXISTS __pocketsync_device_state');
        await txn.execute('DROP TABLE IF EXISTS __pocketsync_changes');
        await txn.execute('DROP TABLE IF EXISTS __pocketsync_processed_tables');
        await txn.execute('DROP TABLE IF EXISTS __pocketsync_version');
      });

      await initializePocketSyncTables(db);

      await setupChangeTracking(db);

      await _saveCurrentVersion(db, SyncConfig.pluginVersion);
    } catch (e) {
      Logger.log('SchemaManager: Error during reset: $e');
      // Try to re-enable change tracking even if there was an error
      try {
        await setupChangeTracking(db);
      } catch (triggerError) {
        Logger.log(
            'SchemaManager: Error re-enabling triggers after reset failure: $triggerError');
      }
      rethrow;
    }
  }

  /// Checks if a reset is needed for the current plugin version
  ///
  /// Returns true if the stored version is different from the current version
  /// or if no version is stored yet.
  Future<bool> _shouldResetForVersion(
    Database db,
    String currentVersion,
  ) async {
    try {
      final result = await db.query('__pocketsync_version', where: 'id = 1');

      if (result.isEmpty) {
        return true;
      }

      final storedVersion = result.first['version'] as String;
      return storedVersion != currentVersion;
    } on DatabaseException catch (e) {
      // If there's an error (likely because the table doesn't exist yet),
      // assume reset is needed
      Logger.log('SchemaManager: Error checking version: $e');
      return true;
    }
  }

  /// Saves the current plugin version after a successful reset
  Future<void> _saveCurrentVersion(Database db, String version) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    await db.execute('''
      INSERT OR REPLACE INTO __pocketsync_version (id, version, last_reset_timestamp)
      VALUES (1, ?, ?)
    ''', [version, timestamp]);
  }

  /// Get the device ID from the device state table
  Future<String> getDeviceId(Database db) async {
    final result = await db.query('__pocketsync_device_state', limit: 1);
    if (result.isEmpty) {
      throw Exception('Device not registered');
    }
    return result.first['device_id'] as String;
  }

  // Method to monitor sync states
  Future<Map<String, dynamic>> getSyncStatus(Database db) async {
    final deviceStates = await db.query('__pocketsync_device_state');
    final pendingChanges = await db.rawQuery(
        'SELECT COUNT(*) as count FROM __pocketsync_changes WHERE synced = 0');

    return {
      'devices': deviceStates,
      'pending_changes': pendingChanges.first['count'],
    };
  }

  /// Gets the primary key column name for a table.
  /// This method is used by the change tracking system to identify records.
  Future<String?> getPrimaryKeyColumn(dynamic db, String tableName) async {
    try {
      final result = await db.rawQuery(
        "SELECT name FROM pragma_table_info('$tableName') WHERE pk = 1",
      );

      if (result.isNotEmpty) {
        final name = result.first['name'] as String;
        return name;
      }

      // If no primary key is found, check for a column named 'id'
      final columns = await db.rawQuery("PRAGMA table_info($tableName)");
      for (final column in columns) {
        final name = column['name'] as String;
        if (name.toLowerCase() == 'id') {
          return name;
        }
      }

      return null;
    } catch (e) {
      Logger.log('Error getting primary key for $tableName: $e');
      return null;
    }
  }

  /// Process pre-existing data for synchronization.
  Future<void> syncPreExistingData(
      Database db, PocketSyncOptions options) async {
    final tables = await _getUserTables(db);
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    for (final tableName in tables) {
      // Check if the table has already been processed
      if (await _isTableProcessed(db, tableName)) {
        continue;
      }

      // Mark the table as processed
      await _markTableAsProcessed(db, tableName, timestamp);
    }
  }

  /// Cleans up old sync records based on retention policy.
  /// Returns the number of records deleted.
  Future<int> cleanupOldSyncRecords(
      Database db, PocketSyncOptions options) async {
    try {
      // Check if cleanup was recently performed
      final deviceState = await db.query('__pocketsync_device_state', limit: 1);
      if (deviceState.isNotEmpty &&
          deviceState.first['last_cleanup_timestamp'] != null) {
        final lastCleanupTimestamp =
            deviceState.first['last_cleanup_timestamp'] as int;
        final currentTime = DateTime.now().millisecondsSinceEpoch;

        if (currentTime - lastCleanupTimestamp <
            const Duration(hours: 24).inMilliseconds) {
          return 0; // Skip cleanup if done within the last 24 hours
        }
      }

      // Use the retention days from options
      final retentionDays = options.changeLogRetentionDays;

      if (retentionDays <= 0) {
        return 0; // No cleanup needed
      }

      final cutoffTimestamp = DateTime.now()
          .subtract(Duration(days: retentionDays))
          .millisecondsSinceEpoch;

      int deletedCount = 0;
      final deviceId = await getDeviceId(db);
      await db.transaction((txn) async {
        // Delete old synced changes
        deletedCount = await txn.delete(
          '__pocketsync_changes',
          where: 'synced = 1 AND timestamp < ?',
          whereArgs: [cutoffTimestamp],
        );

        // Update last cleanup timestamp
        try {
          // First try to update existing record
          final updateCount = await txn.update(
            '__pocketsync_device_state',
            {'last_cleanup_timestamp': DateTime.now().millisecondsSinceEpoch},
            where: 'device_id = ?',
            whereArgs: [deviceId],
          );

          // If no record was updated, insert a new one
          if (updateCount == 0) {
            await txn.insert(
              '__pocketsync_device_state',
              {
                'device_id': deviceId,
                'last_cleanup_timestamp': DateTime.now().millisecondsSinceEpoch,
                'last_sync_status': 'cleanup_performed'
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        } catch (e) {
          Logger.log('Error updating device state during cleanup: $e');
          // Continue with the transaction even if updating device state fails
        }
      });

      return deletedCount;
    } catch (e) {
      Logger.log('Error cleaning up old sync records: $e');
      // Don't rethrow - cleanup errors shouldn't break the app
      return 0;
    }
  }

  /// Check if a table has already had its pre-existing data processed.
  Future<bool> _isTableProcessed(Database db, String tableName) async {
    try {
      final result = await db.query(
        '__pocketsync_processed_tables',
        where: 'table_name = ?',
        whereArgs: [tableName],
        limit: 1,
      );

      return result.isNotEmpty;
    } catch (e) {
      Logger.log('Error checking if table $tableName is processed: $e');
      return false;
    }
  }

  /// Mark a table as having had its pre-existing data processed.
  Future<void> _markTableAsProcessed(
    DatabaseExecutor db,
    String tableName,
    int timestamp,
  ) async {
    try {
      // Create table for tracking pre-existing data processing
      await db.execute('''
        CREATE TABLE IF NOT EXISTS __pocketsync_processed_tables (
          table_name TEXT PRIMARY KEY,
          processed_at INTEGER NOT NULL
        )
      ''');

      // Insert the record
      await db.insert(
        '__pocketsync_processed_tables',
        {
          'table_name': tableName,
          'processed_at': timestamp,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      Logger.log('Error marking table $tableName as processed: $e');
      rethrow;
    }
  }

  /// Gets a list of all user tables in the database.
  Future<List<String>> _getUserTables(Database db) async {
    final result = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE '__pocketsync%' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'android_%'",
    );

    final tables = result.map((row) => row['name'] as String).toList();
    return tables;
  }

  /// Creates triggers for a table to track changes.
  Future<void> _createTableTriggers(Transaction txn, String tableName) async {
    // First drop any existing triggers to avoid conflicts
    await _dropExistingTriggers(txn, tableName);

    // Get all columns for the table
    final columnsResult = await txn.rawQuery(
      "PRAGMA table_info('$tableName')",
    );

    final columns = columnsResult.map((col) => col['name'] as String).toList();

    // Create INSERT trigger with proper handling of global ID
    await txn.execute('''
      CREATE TRIGGER IF NOT EXISTS after_insert_$tableName
      AFTER INSERT ON $tableName
      BEGIN
        -- Generate a global ID if not provided
        UPDATE $tableName
        SET ${SyncConfig.defaultGlobalIdColumnName} = COALESCE(NEW.${SyncConfig.defaultGlobalIdColumnName}, hex(randomblob(16)))
        WHERE rowid = NEW.rowid AND NEW.${SyncConfig.defaultGlobalIdColumnName} IS NULL;
        
        -- Use a subquery to get the complete record with the updated global ID
        INSERT INTO __pocketsync_changes (
          id, table_name, record_rowid, operation, timestamp, data, version, synced
        )
        SELECT 
          hex(randomblob(16)),
          '$tableName',
          T.${SyncConfig.defaultGlobalIdColumnName},
          'INSERT',
          (strftime('%s', 'now') * 1000),
          json_object(${columns.map((col) => "'$col', T.$col").join(', ')}),
          1,  -- First version for new record
          0
        FROM $tableName T
        WHERE T.rowid = NEW.rowid;
      END;
    ''');

    // Create UPDATE trigger with proper handling of changes
    await txn.execute('''
      CREATE TRIGGER IF NOT EXISTS after_update_$tableName
      AFTER UPDATE ON $tableName
      WHEN ${generateUpdateCondition(columns)}
      BEGIN
        -- First ensure global ID is set properly
        UPDATE $tableName
        SET ${SyncConfig.defaultGlobalIdColumnName} = COALESCE(NEW.${SyncConfig.defaultGlobalIdColumnName}, OLD.${SyncConfig.defaultGlobalIdColumnName}, hex(randomblob(16)))
        WHERE rowid = NEW.rowid AND (NEW.${SyncConfig.defaultGlobalIdColumnName} IS NULL);
        
        -- Now fetch the complete record with guaranteed global ID for the change log
        INSERT INTO __pocketsync_changes (
          id, table_name, record_rowid, operation, timestamp, data, version, synced
        )
        SELECT 
          hex(randomblob(16)),
          '$tableName',
          T.${SyncConfig.defaultGlobalIdColumnName},
          'UPDATE',
          (strftime('%s', 'now') * 1000),
          json_object(
            'old', json_object(${columns.map((col) => "'$col', OLD.$col").join(', ')}),
            'new', json_object(${columns.map((col) => "'$col', T.$col").join(', ')})
          ),
          COALESCE((SELECT MAX(version) FROM __pocketsync_changes WHERE table_name = '$tableName' AND record_rowid = T.${SyncConfig.defaultGlobalIdColumnName}), 0) + 1,
          0
        FROM $tableName T
        WHERE T.rowid = NEW.rowid;
      END;
    ''');

    // Create DELETE trigger with proper handling of deleted records
    await txn.execute('''
      CREATE TRIGGER IF NOT EXISTS after_delete_$tableName
      AFTER DELETE ON $tableName
      BEGIN
        -- For DELETE operations, we need to ensure we have a valid global ID
        INSERT INTO __pocketsync_changes (
          id, table_name, record_rowid, operation, timestamp, data, version, synced
        ) VALUES (
          hex(randomblob(16)),
          '$tableName',
          COALESCE(OLD.${SyncConfig.defaultGlobalIdColumnName}, hex(randomblob(16))),
          'DELETE',
          (strftime('%s', 'now') * 1000),
          json_object(${columns.map((col) => "'$col', OLD.$col").join(', ')}),
          COALESCE((SELECT MAX(version) FROM __pocketsync_changes WHERE table_name = '$tableName' AND record_rowid = OLD.${SyncConfig.defaultGlobalIdColumnName}), 0) + 1,
          0
        );
      END;
    ''');
  }

  /// Drops existing triggers for a table.
  Future<void> _dropExistingTriggers(Transaction txn, String tableName) async {
    try {
      final result = await txn.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='trigger' AND tbl_name='$tableName'",
      );

      for (final row in result) {
        final triggerName = row['name'] as String;
        await txn.execute('DROP TRIGGER IF EXISTS $triggerName');
      }

      // Also drop triggers with old naming convention
      final oldTriggers = [
        '${tableName}_after_insert',
        '${tableName}_after_update',
        '${tableName}_after_delete',
        '${tableName}_insert_trigger',
        '${tableName}_update_trigger',
        '${tableName}_delete_trigger'
      ];

      for (final triggerName in oldTriggers) {
        await txn.execute('DROP TRIGGER IF EXISTS $triggerName');
      }
    } catch (e) {
      Logger.log('Error dropping triggers for $tableName: $e');
      // Continue execution even if there's an error
    }
  }

  /// Generates the SQL condition for the UPDATE trigger.
  String generateUpdateCondition(List<String> columns) {
    // Exclude ps_global_id from the update condition to avoid triggering
    // changes when just the global ID is updated
    final filteredColumns = columns
        .where((col) => col != SyncConfig.defaultGlobalIdColumnName)
        .toList();

    // Create more comprehensive conditions that handle NULL values properly
    final conditions = filteredColumns.map((col) => '''(
        OLD.$col IS NOT NEW.$col OR 
        (OLD.$col IS NULL AND NEW.$col IS NOT NULL) OR
        (OLD.$col IS NOT NULL AND NEW.$col IS NULL)
      )''').join(' OR ');

    return conditions.isEmpty ? '1=1' : conditions;
  }

  /// Checks if a column exists in a table.
  Future<bool> _columnExists(
    Transaction txn,
    String tableName,
    String columnName,
  ) async {
    final result = await txn.rawQuery(
      "PRAGMA table_info('$tableName')",
    );

    return result.any((row) => row['name'] == columnName);
  }

  /// Checks if an index exists.
  Future<bool> _indexExists(Transaction txn, String indexName) async {
    final result = await txn.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index' AND name=?",
      [indexName],
    );

    return result.isNotEmpty;
  }

  /// Generates SQL statements for creating tables and indexes from a schema.
  List<String> _generateSqlStatements(DatabaseSchema schema) {
    final statements = <String>[];

    for (final table in schema.tables) {
      statements.add(_generateCreateTableSql(table));

      for (final index in table.indexes) {
        statements.add(_generateCreateIndexSql(table.name, index));
      }
    }

    return statements;
  }

  /// Generates a CREATE TABLE SQL statement for the given table schema.
  String _generateCreateTableSql(TableSchema table) {
    final buffer = StringBuffer('CREATE TABLE IF NOT EXISTS ${table.name} (\n');

    // Add columns
    final columnDefinitions =
        table.columns.map((column) => '  ${column.toSql()}').join(',\n');
    buffer.write(columnDefinitions);

    // Primary keys are handled in the column definitions
    // Foreign keys are handled in the column definitions

    buffer.write('\n)');
    buffer.write(';');
    return buffer.toString();
  }

  /// Generates a CREATE INDEX SQL statement for the given index.
  String _generateCreateIndexSql(String tableName, Index index) {
    return index.toSql(tableName);
  }
}
