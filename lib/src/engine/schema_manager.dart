import 'package:pocketsync_flutter/pocketsync_flutter.dart';
import 'package:pocketsync_flutter/src/utils/logger.dart';
import 'package:pocketsync_flutter/src/utils/sync_config.dart';
import 'package:sqflite/sqflite.dart';

class SchemaManager {
  Future<void> setupChangeTracking(Database db) async {
    final tables = await _getUserTables(db);

    for (final tableName in tables) {
      await db.transaction((txn) async {
        try {
          // 1. First add global ID column if it doesn't exist
          var columnExists = await txn.rawQuery('''
            SELECT 1 FROM pragma_table_info('$tableName') WHERE name = 'ps_global_id'
          ''');

          if (columnExists.isEmpty) {
            await txn.execute(
              'ALTER TABLE $tableName ADD COLUMN ps_global_id TEXT NULL',
            );
          }

          // 2. Create index if it doesn't exist
          var indexExists = await txn.rawQuery('''
            SELECT 1 FROM sqlite_master 
            WHERE type = 'index' AND name = 'idx_${tableName}_ps_global_id'
          ''');

          if (indexExists.isEmpty) {
            await txn.execute(
              'CREATE INDEX idx_${tableName}_ps_global_id ON $tableName(ps_global_id)',
            );
          }

          // 3. Generate global IDs for existing records that don't have one
          // This happens BEFORE triggers are created to avoid triggering updates
          await txn.execute('''
            UPDATE $tableName
            SET ps_global_id = hex(randomblob(16))
            WHERE ps_global_id IS NULL
          ''');

          // 4. Only now create triggers for change tracking
          await _createTableTriggers(txn, tableName);
        } catch (e) {
          Logger.log('Error setting up change tracking for $tableName: $e');
          rethrow;
        }
      });
    }
  }

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
    });
  }

  Future<List<String>> _getUserTables(Database db) async {
    final tables = await db.query(
      'sqlite_master',
      where: "type = 'table' AND name NOT LIKE '__pocketsync_%' "
          "AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'android_%' "
          "AND name NOT LIKE 'ios_%' AND name NOT LIKE '.%' "
          "AND name NOT LIKE 'system_%' AND name NOT LIKE 'sys_%' "
          "AND name NOT LIKE 'test_sqlite_%'",
    );

    return tables.map((t) => t['name'] as String).toList();
  }

  Future<void> _createTableTriggers(Transaction txn, String tableName) async {
    // Get column information for the table
    final columns = (await txn
            .rawQuery("SELECT name FROM pragma_table_info(?)", [tableName]))
        .map((row) => row['name'] as String)
        .toList();

    // Check if triggers already exist and drop them to update
    await _dropExistingTriggers(txn, tableName);

    // Create UPDATE trigger
    await txn.execute('''
      CREATE TRIGGER IF NOT EXISTS after_update_$tableName
      AFTER UPDATE ON $tableName
      WHEN ${generateUpdateCondition(columns)}
      BEGIN
        -- First ensure global ID is set properly
        UPDATE $tableName
        SET ps_global_id = COALESCE(NEW.ps_global_id, OLD.ps_global_id, hex(randomblob(16)))
        WHERE rowid = NEW.rowid AND (NEW.ps_global_id IS NULL);
        
        -- Now fetch the complete record with guaranteed ps_global_id for the change log
        -- Get the latest version number from existing changes
        INSERT INTO __pocketsync_changes (
          id, table_name, record_rowid, operation, timestamp, data, version
        )
        SELECT 
          hex(randomblob(16)),
          '$tableName',
          T.ps_global_id,
          'UPDATE',
          (strftime('%s', 'now') * 1000),
          json_object(
            'old', json_object(${columns.map((col) => "'$col', OLD.$col").join(', ')}),
            'new', json_object(${columns.map((col) => "'$col', T.$col").join(', ')})
          ),
          COALESCE((SELECT MAX(version) FROM __pocketsync_changes WHERE table_name = '$tableName' AND record_rowid = T.ps_global_id), 0) + 1
        FROM $tableName T
        WHERE T.rowid = NEW.rowid;
      END;
    ''');

    // Create INSERT trigger
    await txn.execute('''
      CREATE TRIGGER IF NOT EXISTS after_insert_$tableName
      AFTER INSERT ON $tableName
      BEGIN
        -- Generate a global ID if not provided
        UPDATE $tableName
        SET ps_global_id = COALESCE(NEW.ps_global_id, hex(randomblob(16)))
        WHERE rowid = NEW.rowid AND NEW.ps_global_id IS NULL;
        
        -- Use a subquery to get the complete record with the updated ps_global_id
        INSERT INTO __pocketsync_changes (
          id, table_name, record_rowid, operation, timestamp, data, version
        )
        SELECT 
          hex(randomblob(16)),
          '$tableName',
          T.ps_global_id,
          'INSERT',
          (strftime('%s', 'now') * 1000),
          json_object(
            'new', json_object(${columns.map((col) => "'$col', T.$col").join(', ')})
          ),
          1  -- First version for new record
        FROM $tableName T
        WHERE T.rowid = NEW.rowid;
      END;
    ''');

    // Create DELETE trigger
    await txn.execute('''
      CREATE TRIGGER IF NOT EXISTS after_delete_$tableName
      AFTER DELETE ON $tableName
      BEGIN
        -- For DELETE operations, we need to ensure we have a valid global ID
        -- even though the record is being deleted
        INSERT INTO __pocketsync_changes (
          id, table_name, record_rowid, operation, timestamp, data, version
        ) VALUES (
          hex(randomblob(16)),
          '$tableName',
          COALESCE(OLD.ps_global_id, hex(randomblob(16))),
          'DELETE',
          (strftime('%s', 'now') * 1000),
          json_object(
            'old', json_object(${columns.map((col) => "'$col', OLD.$col").join(', ')})
          ),
          COALESCE((SELECT MAX(version) FROM __pocketsync_changes WHERE table_name = '$tableName' AND record_rowid = OLD.ps_global_id), 0) + 1
        );
      END;
    ''');
  }

  Future<void> _dropExistingTriggers(Transaction txn, String tableName) async {
    final triggers = [
      'after_update_$tableName',
      'after_insert_$tableName',
      'after_delete_$tableName'
    ];

    for (final trigger in triggers) {
      await txn.execute('''
        DROP TRIGGER IF EXISTS $trigger
      ''');
    }
  }

  String generateUpdateCondition(List<String> columns) {
    // Exclude ps_global_id from the update condition to avoid triggering
    // changes when just the global ID is updated
    final filteredColumns =
        columns.where((col) => col != 'ps_global_id').toList();

    final conditions = filteredColumns.map((col) => '''(
          OLD.$col IS NOT NEW.$col OR 
          (OLD.$col IS NULL AND NEW.$col IS NOT NULL) OR
          (OLD.$col IS NOT NULL AND NEW.$col IS NULL)
        )''').join(' OR ');
    return conditions;
  }

  // Clean up old sync records based on retention policy
  Future<int> cleanupOldSyncRecords(
    Database db,
    PocketSyncOptions options,
  ) async {
    try {
      final deviceState = await db.query('__pocketsync_device_state', limit: 1);
      
      if (deviceState.isNotEmpty && deviceState.first['last_cleanup_timestamp'] != null) {
        final lastCleanupTimestamp = deviceState.first['last_cleanup_timestamp'] as int;
        final currentTime = DateTime.now().millisecondsSinceEpoch;
        
        if (currentTime - lastCleanupTimestamp < const Duration(hours: 24).inMilliseconds) {
          return 0;
        }
      }
      
      final retentionDays = options.changeLogRetentionDays;

      // Calculate cutoff timestamp
      final cutoffTimestamp = DateTime.now()
          .subtract(Duration(days: retentionDays))
          .millisecondsSinceEpoch;

      // Delete old sync records that have been synced
      final deletedCount = await db.delete('__pocketsync_changes',
          where: 'synced = 1 AND timestamp < ?', whereArgs: [cutoffTimestamp]);
      
      // Update the last cleanup timestamp
      final currentTime = DateTime.now().millisecondsSinceEpoch;
      await db.execute(
        'UPDATE __pocketsync_device_state SET last_cleanup_timestamp = ?',
        [currentTime],
      );
      
      return deletedCount;
    } catch (e) {
      Logger.log('Error cleaning up old sync records: $e');
      return 0;
    }
  }

  // Method to handle schema changes by recreating triggers
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

  /// Checks if a reset is needed for the current plugin version
  ///
  /// Returns true if the stored version is different from the current version
  /// or if no version is stored yet.
  Future<bool> _shouldResetForVersion(
    Database db,
    String currentVersion,
  ) async {
    try {
      // Check if we have a version record
      final result = await db.query('__pocketsync_version', where: 'id = 1');

      if (result.isEmpty) {
        // No version record, reset needed
        return true;
      }

      final storedVersion = result.first['version'] as String;
      return storedVersion != currentVersion;
    } catch (e) {
      Logger.log('SchemaManager: Error checking version: $e');
      // If there's an error, assume reset is needed
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

    Logger.log('SchemaManager: Updated stored plugin version to $version');
  }

  Future<void> disableTriggers(Database db) async {
    final tables = await _getUserTables(db);

    for (final tableName in tables) {
      await db.transaction((txn) async {
        try {
          await _dropExistingTriggers(txn, tableName);
        } catch (e) {
          Logger.log('Error updating triggers for $tableName: $e');
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
    // Check if reset is needed for the current plugin version
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
        // Current version tables
        await txn.execute('DROP TABLE IF EXISTS __pocketsync_device_state');
        await txn.execute('DROP TABLE IF EXISTS __pocketsync_changes');

        // Previous version tables
        await txn.execute('DROP TABLE IF EXISTS __pocketsync_version');
        await txn
            .execute('DROP TABLE IF EXISTS __pocketsync_processed_changes');
      });

      // 3. Recreate the necessary tables
      await initializePocketSyncTables(db);

      // 4. Re-enable change tracking
      await setupChangeTracking(db);

      // 5. Store the current plugin version
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
}
