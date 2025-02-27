import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pocketsync_flutter/src/database/pocket_sync_database_initializer.dart';

void main() {
  late Database db;
  late PocketSyncDatabaseInitializer initializer;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // Create a new in-memory database for each test
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1),
    );
    initializer = PocketSyncDatabaseInitializer();
  });

  tearDown(() async {
    // Close the database after each test
    await db.close();
  });

  group('PocketSyncDatabaseInitializer', () {
    test('initializePocketSyncTables creates all required system tables',
        () async {
      // Initialize the system tables
      await initializer.initializePocketSyncTables(db);

      // Verify all system tables exist
      final tables = await db.query(
        'sqlite_master',
        where: "type = 'table' AND name LIKE '__pocketsync_%'",
      );

      // Extract table names
      final tableNames = tables.map((t) => t['name'] as String).toList();

      // Verify all expected tables exist
      expect(
          tableNames,
          containsAll([
            '__pocketsync_changes',
            '__pocketsync_version',
            '__pocketsync_device_state',
            '__pocketsync_processed_changes',
            '__pocketsync_trigger_backup',
          ]));

      // Verify __pocketsync_changes table structure
      final changesTableInfo =
          await db.rawQuery('PRAGMA table_info(__pocketsync_changes)');
      expect(changesTableInfo.length, 8); // Should have 8 columns

      // Verify column names
      final changesColumns =
          changesTableInfo.map((c) => c['name'] as String).toList();
      expect(
          changesColumns,
          containsAll([
            'id',
            'table_name',
            'record_rowid',
            'operation',
            'timestamp',
            'data',
            'version',
            'synced'
          ]));

      // Verify indexes on __pocketsync_changes
      final changesIndexes = await db.query(
        'sqlite_master',
        where: "type = 'index' AND tbl_name = '__pocketsync_changes'",
      );
      final indexNames =
          changesIndexes.map((i) => i['name'] as String).toList();
      expect(
          indexNames,
          containsAll([
            'idx_pocketsync_changes_synced',
            'idx_pocketsync_changes_version',
            'idx_pocketsync_changes_timestamp',
            'idx_pocketsync_changes_table_name',
            'idx_pocketsync_changes_record_rowid',
          ]));
    });

    test('getUserTables returns only user tables', () async {
      // Create some system tables
      await db
          .execute('CREATE TABLE __pocketsync_test (id INTEGER PRIMARY KEY)');
      await db
          .execute('CREATE TABLE test_sqlite_table (id INTEGER PRIMARY KEY)');

      // Create some user tables
      await db
          .execute('CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)');
      await db.execute(
          'CREATE TABLE products (id INTEGER PRIMARY KEY, title TEXT)');

      // Get user tables
      final userTables = await initializer.getUserTables(db);

      // Verify only user tables are returned
      expect(userTables, containsAll(['users', 'products']));
      expect(userTables, isNot(contains('__pocketsync_test')));
      expect(userTables, isNot(contains('test_sqlite_table')));
    });

    test('setupChangeTracking adds ps_global_id column and creates triggers',
        () async {
      // Create a test table
      await db
          .execute('CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)');

      // Initialize system tables
      await initializer.initializePocketSyncTables(db);

      // Setup change tracking
      await initializer.setupChangeTracking(db);

      // Verify ps_global_id column was added
      final columns = await db.rawQuery('PRAGMA table_info(users)');
      final columnNames = columns.map((c) => c['name'] as String).toList();
      expect(columnNames, contains('ps_global_id'));

      // Verify index was created
      final indexes = await db.query(
        'sqlite_master',
        where: "type = 'index' AND name = 'idx_users_ps_global_id'",
      );
      expect(indexes.length, 1);

      // Verify triggers were created
      final triggers = await db.query(
        'sqlite_master',
        where: "type = 'trigger' AND tbl_name = 'users'",
      );
      final triggerNames = triggers.map((t) => t['name'] as String).toList();
      expect(
          triggerNames,
          containsAll([
            'after_insert_users',
            'after_update_users',
            'after_delete_users',
          ]));
    });

    test('backupTriggers saves trigger definitions', () async {
      // Create a test table
      await db
          .execute('CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)');

      // Initialize system tables
      await initializer.initializePocketSyncTables(db);

      // Setup change tracking to create triggers
      await initializer.setupChangeTracking(db);

      // Backup triggers
      await initializer.backupTriggers(db);

      // Verify triggers were backed up
      final backups = await db.query('__pocketsync_trigger_backup');
      expect(backups.length, 3); // INSERT, UPDATE, DELETE triggers

      // Verify backup content
      final triggerNames =
          backups.map((b) => b['trigger_name'] as String).toList();
      expect(
          triggerNames,
          containsAll([
            'after_insert_users',
            'after_update_users',
            'after_delete_users',
          ]));
    });

    test('dropChangeTracking removes all triggers', () async {
      // Create a test table
      await db
          .execute('CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)');

      // Initialize system tables
      await initializer.initializePocketSyncTables(db);

      // Setup change tracking to create triggers
      await initializer.setupChangeTracking(db);

      // Verify triggers exist
      var triggers = await db.query(
        'sqlite_master',
        where: "type = 'trigger' AND name LIKE 'after_%'",
      );
      expect(triggers.length, 3);

      // Drop change tracking
      await initializer.dropChangeTracking(db);

      // Verify triggers were removed
      triggers = await db.query(
        'sqlite_master',
        where: "type = 'trigger' AND name LIKE 'after_%'",
      );
      expect(triggers.length, 0);
    });

    test('verifyChangeTracking recreates missing triggers', () async {
      // Create a test table
      await db
          .execute('CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)');

      // Initialize system tables
      await initializer.initializePocketSyncTables(db);

      // Setup change tracking
      await initializer.setupChangeTracking(db);

      // Drop one trigger
      await db.execute('DROP TRIGGER after_insert_users');

      // Verify trigger is missing
      var triggers = await db.query(
        'sqlite_master',
        where: "type = 'trigger' AND name = 'after_insert_users'",
      );
      expect(triggers.length, 0);

      // Verify and repair change tracking
      await initializer.verifyChangeTracking(db);

      // Verify trigger was recreated
      triggers = await db.query(
        'sqlite_master',
        where: "type = 'trigger' AND name = 'after_insert_users'",
      );
      expect(triggers.length, 1);
    });

    test('initializeTableVersions creates version records for all tables',
        () async {
      // Create test tables
      await db
          .execute('CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)');
      await db.execute(
          'CREATE TABLE products (id INTEGER PRIMARY KEY, title TEXT)');

      // Initialize system tables
      await initializer.initializePocketSyncTables(db);

      // Initialize table versions
      await initializer.initializeTableVersions(db);

      // Verify version records were created
      final versions = await db.query('__pocketsync_version');
      expect(versions.length, 2);

      // Verify version values
      for (final version in versions) {
        expect(version['version'], 1);
        expect(['users', 'products'], contains(version['table_name']));
      }
    });

    test('updateTableVersions increments version numbers', () async {
      // Create a test table
      await db
          .execute('CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)');

      // Initialize system tables
      await initializer.initializePocketSyncTables(db);

      // Initialize table versions
      await initializer.initializeTableVersions(db);

      // Update table versions
      await initializer.updateTableVersions(db);

      // Verify version was incremented
      final versions = await db.query('__pocketsync_version');
      expect(versions.length, 1);
      expect(versions.first['version'], 2);
    });

    test(
        'syncPreExistingRecords creates change records for existing data with id column',
        () async {
      // Create a test table with id column
      await db
          .execute('CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)');

      // Insert pre-existing data BEFORE PocketSync is initialized
      await db.insert('users', {'name': 'John'});
      await db.insert('users', {'name': 'Jane'});

      // Verify data exists in the table
      final preExistingData = await db.query('users');
      expect(preExistingData.length, 2);

      // Now initialize PocketSync system tables
      await initializer.initializePocketSyncTables(db);

      // Verify no change records exist yet
      var changes = await db.query('__pocketsync_changes');
      expect(changes.length, 0);

      // Setup change tracking - this adds ps_global_id column
      await initializer.setupChangeTracking(db);

      // Initialize table versions
      await initializer.initializeTableVersions(db);

      // Verify still no change records exist
      changes = await db.query('__pocketsync_changes');
      expect(changes.length, 0);

      // Sync pre-existing records - this should create change records for our data
      final syncedCount = await initializer.syncPreExistingRecords(db);

      // Verify correct number of records were synced
      expect(syncedCount, 2);

      // Verify change records were created
      changes = await db.query('__pocketsync_changes');
      expect(changes.length, 2);

      // Verify change record properties
      for (final change in changes) {
        expect(change['table_name'], 'users');
        expect(change['operation'], 'INSERT');
        expect(change['synced'], 0);

        // Verify the data field contains the original record data
        final dataString = change['data'] as String;
        expect(dataString, contains('"name"'));
        expect(
            dataString.contains('John') || dataString.contains('Jane'), isTrue);
      }

      // Verify ps_global_id was added to the original records
      final updatedRecords = await db.query('users');
      for (final record in updatedRecords) {
        expect(record['ps_global_id'], isNotNull);
      }
    });

    test(
        'syncPreExistingRecords handles tables with primary key but no id column',
        () async {
      // Create a test table with a primary key that is NOT named 'id'
      await db.execute(
          'CREATE TABLE products (product_code TEXT PRIMARY KEY, name TEXT, price REAL)');

      // Insert pre-existing data BEFORE PocketSync is initialized
      await db.insert('products',
          {'product_code': 'P001', 'name': 'Product 1', 'price': 10.99});
      await db.insert('products',
          {'product_code': 'P002', 'name': 'Product 2', 'price': 20.49});

      // Verify data exists in the table
      final preExistingData = await db.query('products');
      expect(preExistingData.length, 2);

      // Now initialize PocketSync system tables
      await initializer.initializePocketSyncTables(db);
      await initializer.setupChangeTracking(db);
      await initializer.initializeTableVersions(db);

      // Sync pre-existing records - this should create change records for our data
      final syncedCount = await initializer.syncPreExistingRecords(db);

      // Verify correct number of records were synced
      expect(syncedCount, 2);

      // Verify change records were created
      final changes = await db.query('__pocketsync_changes',
          where: 'table_name = ?', whereArgs: ['products']);
      expect(changes.length, 2);

      // Verify change record properties
      for (final change in changes) {
        expect(change['table_name'], 'products');
        expect(change['operation'], 'INSERT');
        expect(change['synced'], 0);

        // Verify the data field contains the original record data
        final dataString = change['data'] as String;
        expect(dataString, contains('"product_code"'));
        expect(dataString, contains('"name"'));
        expect(dataString, contains('"price"'));
      }
    });

    test(
        'syncPreExistingRecords handles tables without id or primary key columns',
        () async {
      // Create a test table with no primary key or id column
      await db.execute('CREATE TABLE settings (key TEXT, value TEXT)');

      // Insert pre-existing data BEFORE PocketSync is initialized
      await db.insert('settings', {'key': 'theme', 'value': 'dark'});
      await db.insert('settings', {'key': 'language', 'value': 'en'});

      // Verify data exists in the table
      final preExistingData = await db.query('settings');
      expect(preExistingData.length, 2);

      // Now initialize PocketSync system tables
      await initializer.initializePocketSyncTables(db);
      await initializer.setupChangeTracking(db);
      await initializer.initializeTableVersions(db);

      // Sync pre-existing records - this should create change records for our data
      final syncedCount = await initializer.syncPreExistingRecords(db);

      // Verify correct number of records were synced
      expect(syncedCount, 2);

      // Verify change records were created
      final changes = await db.query('__pocketsync_changes',
          where: 'table_name = ?', whereArgs: ['settings']);
      expect(changes.length, 2);

      // Verify change record properties
      for (final change in changes) {
        expect(change['table_name'], 'settings');
        expect(change['operation'], 'INSERT');
        expect(change['synced'], 0);

        // Verify the data field contains the original record data
        final dataString = change['data'] as String;
        expect(dataString, contains('"key"'));
        expect(dataString, contains('"value"'));
      }
    });

    test(
        'syncPreExistingRecords handles multiple tables with different structures',
        () async {
      // Create tables with different structures
      await db
          .execute('CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)');
      await db.execute(
          'CREATE TABLE products (product_code TEXT PRIMARY KEY, name TEXT)');
      await db.execute('CREATE TABLE settings (key TEXT, value TEXT)');

      // Insert pre-existing data
      await db.insert('users', {'name': 'User 1'});
      await db
          .insert('products', {'product_code': 'P001', 'name': 'Product 1'});
      await db.insert('settings', {'key': 'theme', 'value': 'light'});

      // Initialize PocketSync
      await initializer.initializePocketSyncTables(db);
      await initializer.setupChangeTracking(db);
      await initializer.initializeTableVersions(db);

      // Sync pre-existing records
      final syncedCount = await initializer.syncPreExistingRecords(db);

      // Verify correct number of records were synced
      expect(syncedCount, 3); // One from each table

      // Verify change records were created for each table
      final userChanges = await db.query('__pocketsync_changes',
          where: 'table_name = ?', whereArgs: ['users']);
      final productChanges = await db.query('__pocketsync_changes',
          where: 'table_name = ?', whereArgs: ['products']);
      final settingChanges = await db.query('__pocketsync_changes',
          where: 'table_name = ?', whereArgs: ['settings']);

      expect(userChanges.length, 1);
      expect(productChanges.length, 1);
      expect(settingChanges.length, 1);
    });

    test('_generateUpdateCondition creates correct SQL condition', () async {
      // Test with a simple column list
      final columns = ['id', 'name', 'email'];
      final condition = initializer.generateUpdateCondition(columns);

      // Verify condition format
      expect(condition, contains('OLD.id IS NOT NEW.id'));
      expect(condition, contains('OLD.name IS NOT NEW.name'));
      expect(condition, contains('OLD.email IS NOT NEW.email'));
      expect(condition, contains('OR'));
    });
  });
}
