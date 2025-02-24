import 'package:sqflite/sqflite.dart';

/// Internal class responsible for managing PocketSync system tables and triggers
class PocketSyncDatabaseInitializer {
  /// Sets up the initial PocketSync system tables
  Future<void> initializePocketSyncTables(Database db) async {
    await db.execute('''
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
      CREATE INDEX idx_pocketsync_changes_synced ON __pocketsync_changes(synced);
      CREATE INDEX idx_pocketsync_changes_version ON __pocketsync_changes(version);
      CREATE INDEX idx_pocketsync_changes_timestamp ON __pocketsync_changes(timestamp);
      CREATE INDEX idx_pocketsync_changes_table_name ON __pocketsync_changes(table_name);
      CREATE INDEX idx_pocketsync_changes_record_rowid ON __pocketsync_changes(record_rowid)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS __pocketsync_version (
        table_name TEXT PRIMARY KEY,
        version INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS __pocketsync_device_state (
        device_id TEXT PRIMARY KEY,
        last_sync_timestamp INTEGER NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS __pocketsync_processed_changes (
        change_log_id INTEGER PRIMARY KEY,
        processed_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS __pocketsync_trigger_backup (
        table_name TEXT NOT NULL,
        trigger_name TEXT NOT NULL,
        trigger_sql TEXT NOT NULL,
        PRIMARY KEY (table_name, trigger_name)
      )
    ''');
  }

  /// Gets all user tables (excluding system tables)
  Future<List<String>> getUserTables(Database db) async {
    final tables = await db.query(
      'sqlite_master',
      where: "type = 'table' AND name NOT LIKE '__pocketsync_%' "
          "AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'android_%' "
          "AND name NOT LIKE 'ios_%' AND name NOT LIKE '.%' "
          "AND name NOT LIKE 'system_%' AND name NOT LIKE 'sys_%'",
    );

    return tables.map((t) => t['name'] as String).toList();
  }

  /// Sets up change tracking triggers for all user tables
  Future<void> setupChangeTracking(Database db) async {
    final tables = await getUserTables(db);

    for (final tableName in tables) {
      var columnExists = await db.rawQuery('''
        SELECT 1 FROM pragma_table_info('$tableName') WHERE name = 'ps_global_id'
      ''');

      if (columnExists.isEmpty) {
        await db.execute(
            'ALTER TABLE $tableName ADD COLUMN ps_global_id TEXT NULL');
      }

      var indexExists = await db.rawQuery('''
        SELECT 1 FROM sqlite_master 
        WHERE type = 'index' AND name = 'idx_${tableName}_ps_global_id'
      ''');

      if (indexExists.isEmpty) {
        await db.execute(
          'CREATE INDEX idx_${tableName}_ps_global_id ON $tableName(ps_global_id)',
        );
      }

      await createTableTriggers(db, tableName);
    }
  }

  /// Creates triggers for a specific table
  Future<void> createTableTriggers(Database db, String tableName) async {
    final columns = (await db
            .rawQuery("SELECT name FROM pragma_table_info(?)", [tableName]))
        .map((row) => row['name'] as String)
        .toList();

    // UPDATE trigger
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS after_update_$tableName
      AFTER UPDATE ON $tableName
      WHEN ${_generateUpdateCondition(columns)}
      BEGIN
        INSERT INTO __pocketsync_changes (
          table_name, record_rowid, operation, timestamp, data, version
        ) VALUES (
          '$tableName',
          COALESCE(NEW.ps_global_id, (SELECT ps_global_id FROM $tableName WHERE rowid = NEW.rowid)),
          'UPDATE',
          (strftime('%s', 'now') * 1000),
          json_object(
            'old', json_object(${columns.map((col) => "'$col', OLD.$col").join(', ')}),
            'new', json_object(${columns.map((col) => "'$col', NEW.$col").join(', ')})
          ),
          (SELECT COALESCE(MAX(version), 0) + 1 FROM __pocketsync_version WHERE table_name = '$tableName')
        );
        
        UPDATE __pocketsync_version 
        SET version = version + 1
        WHERE table_name = '$tableName';
        
        SELECT changes.*
        FROM __pocketsync_changes changes
        WHERE changes.id = last_insert_rowid()
        AND EXISTS (SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = '__pocketsync_changes')
        AND (SELECT RAISE(ROLLBACK, 'Trigger callback failed')
             WHERE NOT EXISTS (SELECT 1 FROM __pocketsync_changes WHERE id = last_insert_rowid()));
      END;
    ''');

    // AFTER INSERT trigger for change tracking
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS after_insert_$tableName
      AFTER INSERT ON $tableName
      BEGIN
        INSERT INTO __pocketsync_changes (
          table_name, record_rowid, operation, timestamp, data, version
        ) VALUES (
          '$tableName',
          COALESCE(NEW.ps_global_id, (SELECT ps_global_id FROM $tableName WHERE rowid = NEW.rowid)),
          'INSERT',
          (strftime('%s', 'now') * 1000),
          json_object(
            'new', json_object(${columns.map((col) => "'$col', NEW.$col").join(', ')})
          ),
          (SELECT COALESCE(MAX(version), 0) + 1 FROM __pocketsync_version WHERE table_name = '$tableName')
        );
        
        UPDATE __pocketsync_version 
        SET version = version + 1
        WHERE table_name = '$tableName';
        
        SELECT changes.*
        FROM __pocketsync_changes changes
        WHERE changes.id = last_insert_rowid()
        AND EXISTS (SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = '__pocketsync_changes')
        AND (SELECT RAISE(ROLLBACK, 'Trigger callback failed')
             WHERE NOT EXISTS (SELECT 1 FROM __pocketsync_changes WHERE id = last_insert_rowid()));
      END;
    ''');

    // DELETE trigger
    await db.execute('''
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
          (SELECT COALESCE(MAX(version), 0) + 1 FROM __pocketsync_version WHERE table_name = '$tableName')
        );
        
        UPDATE __pocketsync_version 
        SET version = version + 1
        WHERE table_name = '$tableName';
        
        SELECT changes.*
        FROM __pocketsync_changes changes
        WHERE changes.id = last_insert_rowid()
        AND EXISTS (SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = '__pocketsync_changes')
        AND (SELECT RAISE(ROLLBACK, 'Trigger callback failed')
             WHERE NOT EXISTS (SELECT 1 FROM __pocketsync_changes WHERE id = last_insert_rowid()));
      END;
    ''');
  }

  /// Backs up existing triggers
  Future<void> backupTriggers(Database db) async {
    final triggers = await db.query('sqlite_master',
        where: "type = 'trigger' AND name LIKE 'after_%'");

    final batch = db.batch();
    for (final trigger in triggers) {
      final tableName = trigger['tbl_name'] as String;
      final triggerName = trigger['name'] as String;
      final triggerSql = trigger['sql'] as String;

      batch.insert(
        '__pocketsync_trigger_backup',
        {
          'table_name': tableName,
          'trigger_name': triggerName,
          'trigger_sql': triggerSql,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit();
  }

  /// Drops existing change tracking triggers
  Future<void> dropChangeTracking(Database db) async {
    final triggers = await db.query('sqlite_master',
        where: "type = 'trigger' AND name LIKE 'after_%'");

    for (final trigger in triggers) {
      await db.execute(
        "DROP TRIGGER IF EXISTS ${trigger['name']}",
      );
    }
  }

  /// Verifies and repairs change tracking if needed
  Future<void> verifyChangeTracking(Database db) async {
    final tables = await getUserTables(db);
    final existingTriggers = await db.query(
      'sqlite_master',
      where: "type = 'trigger' AND name LIKE 'after_%'",
    );

    final expectedTriggerCount = tables.length * 3; // INSERT, UPDATE, DELETE
    if (existingTriggers.length != expectedTriggerCount) {
      // Re-setup change tracking if triggers are missing
      await setupChangeTracking(db);
    }
  }

  /// Updates version numbers for all tables
  Future<void> updateTableVersions(Database db) async {
    final tables = await getUserTables(db);
    final batch = db.batch();

    for (final table in tables) {
      batch.rawUpdate(
        'UPDATE __pocketsync_version SET version = version + 1 WHERE table_name = ?',
        [table],
      );
    }

    await batch.commit();
  }

  /// Initializes version records for all tables
  Future<void> initializeTableVersions(Database db) async {
    final tables = await getUserTables(db);
    final batch = db.batch();

    for (final table in tables) {
      batch.insert(
        '__pocketsync_version',
        {'table_name': table, 'version': 1},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    await batch.commit();
  }

  String _generateUpdateCondition(List<String> columns) {
    final conditions = columns.map((col) => '''(
          OLD.$col IS NOT NEW.$col OR 
          (OLD.$col IS NULL AND NEW.$col IS NOT NULL) OR
          (OLD.$col IS NOT NULL AND NEW.$col IS NULL)
        )''').join(' OR ');
    return conditions;
  }
}
