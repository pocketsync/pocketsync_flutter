import 'package:pocketsync_flutter/src/engine/sync_config.dart';
import 'package:sqflite/sqflite.dart';

class SchemaManager {
  Future<void> setupChangeTracking(Database db) async {
    final tables = await _getUserTables(db);

    for (final tableName in tables) {
      await db.transaction((txn) async {
        try {
          // Add global ID column if it doesn't exist
          var columnExists = await txn.rawQuery('''
            SELECT 1 FROM pragma_table_info('$tableName') WHERE name = 'ps_global_id'
          ''');

          if (columnExists.isEmpty) {
            await txn.execute(
              'ALTER TABLE $tableName ADD COLUMN ps_global_id TEXT NULL',
            );
          }

          // Create index if it doesn't exist
          var indexExists = await txn.rawQuery('''
            SELECT 1 FROM sqlite_master 
            WHERE type = 'index' AND name = 'idx_${tableName}_ps_global_id'
          ''');

          if (indexExists.isEmpty) {
            await txn.execute(
              'CREATE INDEX idx_${tableName}_ps_global_id ON $tableName(ps_global_id)',
            );
          }

          // Generate global IDs for existing records that don't have one
          await txn.execute('''
            UPDATE $tableName
            SET ps_global_id = hex(randomblob(16))
            WHERE ps_global_id IS NULL
          ''');

          // Create triggers for change tracking
          await _createTableTriggers(txn, tableName);
        } catch (e) {
          print('Error setting up change tracking for $tableName: $e');
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
          id INTEGER PRIMARY KEY AUTOINCREMENT,
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
          last_sync_timestamp INTEGER NULL,
          device_name TEXT NULL,
          last_sync_status TEXT NULL
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
        -- Get the latest version number from existing changes
        INSERT INTO __pocketsync_changes (
          table_name, record_rowid, operation, timestamp, data, version
        ) VALUES (
          '$tableName',
          COALESCE(NEW.ps_global_id, OLD.ps_global_id, hex(randomblob(16))),
          'UPDATE',
          (strftime('%s', 'now') * 1000),
          json_object(
            'old', json_object(${columns.map((col) => "'$col', OLD.$col").join(', ')}),
            'new', json_object(${columns.map((col) => "'$col', NEW.$col").join(', ')})
          ),
          COALESCE((SELECT MAX(version) FROM __pocketsync_changes WHERE table_name = '$tableName' AND record_rowid = NEW.ps_global_id), 0) + 1
        );
        
        -- Ensure global ID is set
        UPDATE $tableName
        SET ps_global_id = COALESCE(NEW.ps_global_id, OLD.ps_global_id, hex(randomblob(16)))
        WHERE rowid = NEW.rowid AND (NEW.ps_global_id IS NULL);
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
        
        INSERT INTO __pocketsync_changes (
          table_name, record_rowid, operation, timestamp, data, version
        ) VALUES (
          '$tableName',
          (SELECT ps_global_id FROM $tableName WHERE rowid = NEW.rowid),
          'INSERT',
          (strftime('%s', 'now') * 1000),
          json_object(
            'new', json_object(${columns.map((col) => "'$col', NEW.$col").join(', ')})
          ),
          1  -- First version for new record
        );
      END;
    ''');

    // Create DELETE trigger
    await txn.execute('''
      CREATE TRIGGER IF NOT EXISTS after_delete_$tableName
      AFTER DELETE ON $tableName
      BEGIN
        INSERT INTO __pocketsync_changes (
          table_name, record_rowid, operation, timestamp, data, version
        ) VALUES (
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
    final conditions = columns.map((col) => '''(
          OLD.$col IS NOT NEW.$col OR 
          (OLD.$col IS NULL AND NEW.$col IS NOT NULL) OR
          (OLD.$col IS NOT NULL AND NEW.$col IS NULL)
        )''').join(' OR ');
    return conditions;
  }

  // Clean up old sync records based on retention policy
  Future<int> cleanupOldSyncRecords(Database db) async {
    try {
      final retentionDays = SyncConfig.changeRetentionDays;

      // Calculate cutoff timestamp
      final cutoffTimestamp = DateTime.now()
          .subtract(Duration(days: retentionDays))
          .millisecondsSinceEpoch;

      // Delete old sync records that have been synced
      return await db.delete('__pocketsync_changes',
          where: 'synced = 1 AND timestamp < ?', whereArgs: [cutoffTimestamp]);
    } catch (e) {
      print('Error cleaning up old sync records: $e');
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
          print('Error updating triggers for $tableName: $e');
          rethrow;
        }
      });
    }
  }

  // Register this device in the sync system
  Future<void> registerDevice(Database db, String deviceId,
      {String? deviceName}) async {
    await db.insert(
        '__pocketsync_device_state',
        {
          'device_id': deviceId,
          'device_name': deviceName,
          'last_sync_timestamp': null,
          'last_sync_status': 'NEVER_SYNCED'
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
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
}
