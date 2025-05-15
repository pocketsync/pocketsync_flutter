import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketsync_flutter/pocketsync_flutter.dart';
import 'package:pocketsync_flutter/src/engine/schema_manager.dart';
import 'package:pocketsync_flutter/src/utils/sync_config.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as path;

import '../database/database_test_utils.dart';

void main() {
  // Initialize sqflite_ffi for testing
  setUpAll(() {
    DatabaseTestUtils.initializeSqfliteFfi();
  });

  group('Schema Lifecycle Tests', () {
    late SchemaManager schemaManager;
    late Database db;
    late DatabaseSchema initialSchema;
    late String dbPath;

    setUp(() async {
      // Create a unique temporary database path for each test
      final testDir = Directory.systemTemp.createTempSync('pocketsync_test_');
      dbPath = path.join(testDir.path, 'test_db.sqlite');

      // Delete any existing database file
      final dbFile = File(dbPath);
      if (dbFile.existsSync()) {
        dbFile.deleteSync();
      }

      // Define initial schema
      initialSchema = DatabaseSchema(
        tables: [
          TableSchema(
            name: 'users',
            columns: [
              TableColumn.primaryKey(name: 'id', type: ColumnType.integer),
              TableColumn.text(name: 'name', isNullable: false),
              TableColumn.text(name: 'email'),
            ],
          ),
        ],
      );

      // Create a new SchemaManager instance with the initial schema
      schemaManager = SchemaManager(schema: initialSchema);

      // Create a file-based database for testing
      db = await openDatabase(
        dbPath,
        version: 1,
      );
    });

    tearDown(() async {
      // Close the database after each test
      await db.close();

      // Clean up the database file
      try {
        final dbFile = File(dbPath);
        if (dbFile.existsSync()) {
          dbFile.deleteSync();
        }
      } catch (e) {
        // Ignore cleanup errors
      }
    });

    test('should create tables from schema', () async {
      // Act - Create tables from schema
      await schemaManager.createTablesFromSchema(db);

      // Assert - Check if tables were created
      final tables = await db.query(
        'sqlite_master',
        where: "type = 'table'",
      );

      final tableNames = tables.map((t) => t['name'] as String).toList();

      // Verify user tables exist
      expect(tableNames, contains('users'));

      // Verify columns were created correctly
      final columns = await db.rawQuery("PRAGMA table_info('users')");
      final columnNames = columns.map((c) => c['name'] as String).toList();

      expect(columnNames, contains('id'));
      expect(columnNames, contains('name'));
      expect(columnNames, contains('email'));
      expect(columnNames, contains(SyncConfig.defaultGlobalIdColumnName));
    });

    test('should add global ID column during schema creation', () async {
      // Act - Create tables from schema
      await schemaManager.createTablesFromSchema(db);

      // Assert - Check if global ID column was added
      final columns = await db.rawQuery("PRAGMA table_info('users')");
      final globalIdColumn = columns.firstWhere(
        (c) => c['name'] == SyncConfig.defaultGlobalIdColumnName,
        orElse: () => {},
      );

      // Verify global ID column exists and has correct properties
      expect(globalIdColumn.isNotEmpty, isTrue);
      expect(globalIdColumn['type'], 'TEXT');
      expect(globalIdColumn['notnull'], 0); // Nullable
    });

    test('should handle schema changes when adding new columns', () async {
      // Arrange - Create initial schema
      await schemaManager.createTablesFromSchema(db);

      // Insert test data
      await db.insert('users', {
        'name': 'Test User',
        'email': 'test@example.com',
      });

      // Act - Create a new schema manager with updated schema
      final updatedSchema = DatabaseSchema(
        tables: [
          TableSchema(
            name: 'users',
            columns: [
              TableColumn.primaryKey(name: 'id', type: ColumnType.integer),
              TableColumn.text(name: 'name', isNullable: false),
              TableColumn.text(name: 'email'),
              TableColumn.text(name: 'phone'), // New column
            ],
          ),
        ],
      );

      final updatedSchemaManager = SchemaManager(schema: updatedSchema);

      // Simulate database upgrade
      await db.close();
      db = await openDatabase(
        dbPath,
        version: 2,
        onCreate: (db, version) async {},
        onUpgrade: (db, oldVersion, newVersion) async {
          // Handle schema changes
          await updatedSchemaManager.handleSchemaChanges(db);
        },
      );

      // Assert - Check if new column exists
      final columns = await db.rawQuery("PRAGMA table_info('users')");
      final columnNames = columns.map((c) => c['name'] as String).toList();

      // The phone column should be added during schema migration
      expect(columnNames, contains('phone'));

      // Existing data should be preserved
      final users = await db.query('users');
      expect(users.length, 1);
      expect(users.first['name'], 'Test User');
      expect(users.first['email'], 'test@example.com');
    });

    test('should preserve data during schema upgrades', () async {
      // Arrange - Create initial schema
      await schemaManager.createTablesFromSchema(db);

      // Insert test data with global ID
      final globalId = 'test-global-id-123';
      await db.insert('users', {
        'name': 'Original Name',
        'email': 'original@example.com',
        SyncConfig.defaultGlobalIdColumnName: globalId,
      });

      // Act - Simulate database upgrade with schema changes
      await db.close();
      db = await openDatabase(
        dbPath,
        version: 2,
        onCreate: (db, version) async {},
        onUpgrade: (db, oldVersion, newVersion) async {
          // Handle schema changes
          await schemaManager.handleSchemaChanges(db);

          // Setup change tracking again
          await schemaManager.setupChangeTracking(db);
        },
      );

      // Update the record
      await db.update(
        'users',
        {'name': 'Updated Name'},
        where: '${SyncConfig.defaultGlobalIdColumnName} = ?',
        whereArgs: [globalId],
      );

      // Assert - Check if data was preserved and change was tracked
      final users = await db.query('users');
      expect(users.length, 1);
      expect(users.first['name'], 'Updated Name');
      expect(users.first['email'], 'original@example.com');
      expect(users.first[SyncConfig.defaultGlobalIdColumnName], globalId);

      // Check if change was tracked
      final changes = await db.query('__pocketsync_changes');
      expect(changes.isNotEmpty, isTrue);
      expect(changes.first['operation'], 'UPDATE');
      expect(changes.first['record_rowid'], globalId);
    });

    test('should handle multiple schema versions', () async {
      // Arrange - Create initial schema (v1)
      await schemaManager.createTablesFromSchema(db);

      // Insert test data
      await db.insert('users', {
        'name': 'Test User',
        'email': 'test@example.com',
      });

      // Act - Simulate multiple database upgrades (v1 -> v2 -> v3)

      // First upgrade (v1 -> v2): Add phone column
      await db.close();
      final schemaV2 = DatabaseSchema(
        tables: [
          TableSchema(
            name: 'users',
            columns: [
              TableColumn.primaryKey(name: 'id', type: ColumnType.integer),
              TableColumn.text(name: 'name', isNullable: false),
              TableColumn.text(name: 'email'),
              TableColumn.text(name: 'phone'), // New column in v2
            ],
          ),
        ],
      );

      final schemaManagerV2 = SchemaManager(schema: schemaV2);

      db = await openDatabase(
        dbPath,
        version: 2,
        onCreate: (db, version) async {},
        onUpgrade: (db, oldVersion, newVersion) async {
          await db.execute('ALTER TABLE users ADD COLUMN phone TEXT');
          await schemaManagerV2.handleSchemaChanges(db);
        },
      );

      // Update data in v2
      await db.update('users', {'phone': '123-456-7890'}, where: 'id = 1');

      // Second upgrade (v2 -> v3): Add address column and products table
      await db.close();
      final schemaV3 = DatabaseSchema(
        tables: [
          TableSchema(
            name: 'users',
            columns: [
              TableColumn.primaryKey(name: 'id', type: ColumnType.integer),
              TableColumn.text(name: 'name', isNullable: false),
              TableColumn.text(name: 'email'),
              TableColumn.text(name: 'phone'),
              TableColumn.text(name: 'address'), // New column in v3
            ],
          ),
          TableSchema(
            name: 'products', // New table in v3
            columns: [
              TableColumn.primaryKey(name: 'id', type: ColumnType.integer),
              TableColumn.text(name: 'name', isNullable: false),
              TableColumn.real(name: 'price'),
            ],
          ),
        ],
      );

      final schemaManagerV3 = SchemaManager(schema: schemaV3);

      db = await openDatabase(
        dbPath,
        version: 3,
        onCreate: (db, version) async {},
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 3) {
            await db.execute('ALTER TABLE users ADD COLUMN address TEXT');
            await db.execute('''
              CREATE TABLE products (
                id INTEGER PRIMARY KEY,
                name TEXT NOT NULL,
                price REAL,
                ${SyncConfig.defaultGlobalIdColumnName} TEXT
              )
            ''');
            await schemaManagerV3.handleSchemaChanges(db);
          }
        },
      );

      // Assert - Check if all schema changes were applied correctly
      final userColumns = await db.rawQuery("PRAGMA table_info('users')");
      final userColumnNames =
          userColumns.map((c) => c['name'] as String).toList();

      expect(userColumnNames, contains('id'));
      expect(userColumnNames, contains('name'));
      expect(userColumnNames, contains('email'));
      expect(userColumnNames, contains('phone'));
      expect(userColumnNames, contains('address'));
      expect(userColumnNames, contains(SyncConfig.defaultGlobalIdColumnName));

      // Check if new table exists
      final tables = await db.query(
        'sqlite_master',
        where: "type = 'table'",
      );
      final tableNames = tables.map((t) => t['name'] as String).toList();
      expect(tableNames, contains('products'));

      // Check if data was preserved
      final users = await db.query('users');
      expect(users.length, 1);
      expect(users.first['name'], 'Test User');
      expect(users.first['email'], 'test@example.com');
      expect(users.first['phone'], '123-456-7890');
    });

    test('should handle database downgrade gracefully', () async {
      // First, create the tables with the initial schema
      await schemaManager.createTablesFromSchema(db);
      await schemaManager.setupChangeTracking(db);

      // Insert test data
      await db.insert('users', {
        'name': 'Test User',
        'email': 'test@example.com',
      });

      // Close the database and reopen with a schema that includes the phone column
      await db.close();

      // Define a schema with an additional column
      final enhancedSchema = DatabaseSchema(
        tables: [
          TableSchema(
            name: 'users',
            columns: [
              TableColumn.primaryKey(name: 'id', type: ColumnType.integer),
              TableColumn.text(name: 'name', isNullable: false),
              TableColumn.text(name: 'email'),
              TableColumn.text(name: 'phone'), // Additional column
            ],
          ),
        ],
      );

      final enhancedSchemaManager = SchemaManager(schema: enhancedSchema);

      // Open with version 2 and add the phone column
      db = await openDatabase(
        dbPath,
        version: 2,
        onCreate: (db, version) async {},
        onUpgrade: (db, oldVersion, newVersion) async {
          await enhancedSchemaManager.handleSchemaChanges(db);
        },
      );

      // Update the record to include phone
      await db.update('users', {'phone': '123-456-7890'}, where: 'id = 1');

      // Verify the phone column was added and data was updated
      var usersWithPhone = await db.query('users');
      expect(usersWithPhone.first['phone'], '123-456-7890');

      // Act - Simulate database downgrade (v2 -> v1)
      await db.close();
      final downgradedSchema = DatabaseSchema(
        tables: [
          TableSchema(
            name: 'users',
            columns: [
              TableColumn.primaryKey(name: 'id', type: ColumnType.integer),
              TableColumn.text(name: 'name', isNullable: false),
              TableColumn.text(name: 'email'),
              // phone column removed from schema but will remain in database
            ],
          ),
        ],
      );

      final downgradedSchemaManager = SchemaManager(schema: downgradedSchema);

      db = await openDatabase(
        dbPath,
        version: 1, // Lower version
        onCreate: (db, version) async {},
        onDowngrade: (db, oldVersion, newVersion) async {
          // Handle downgrade
          await downgradedSchemaManager.handleSchemaChanges(db);
          await downgradedSchemaManager.setupChangeTracking(db);
        },
      );

      // Assert - Check if database is still functional
      final users = await db.query('users');
      expect(users.length, 1);
      expect(users.first['name'], 'Test User');
      expect(users.first['email'], 'test@example.com');

      // The phone column might still exist since SQLite doesn't support dropping columns,
      // but our schema doesn't reference it anymore

      // Verify change tracking is still working
      await db.update('users', {'name': 'Updated Name'}, where: 'id = 1');
      final changes = await db.query('__pocketsync_changes');
      expect(changes.isNotEmpty, isTrue);
    });

    test('should recreate triggers during schema changes', () async {
      // Arrange - Create initial schema
      await schemaManager.createTablesFromSchema(db);
      await schemaManager.setupChangeTracking(db);

      // Get initial triggers
      final initialTriggers = await db.query(
        'sqlite_master',
        where: "type = 'trigger' AND tbl_name = 'users'",
      );

      // Act - Simulate schema change that should recreate triggers
      await schemaManager.handleSchemaChanges(db);

      // Assert - Check if triggers were recreated
      final updatedTriggers = await db.query(
        'sqlite_master',
        where: "type = 'trigger' AND tbl_name = 'users'",
      );

      // Should have the same number of triggers
      expect(updatedTriggers.length, initialTriggers.length);

      // Verify triggers are working by inserting data
      await db.insert(
          'users', {'name': 'Trigger Test', 'email': 'trigger@example.com'});

      final changes = await db.query('__pocketsync_changes');
      expect(changes.isNotEmpty, isTrue);
      expect(changes.first['operation'], 'INSERT');
      expect(changes.first['table_name'], 'users');
    });
  });

  group('Database Options Lifecycle Tests', () {
    late String optionsDbPath;

    setUp(() {
      // Create a unique temporary database path for this test group
      final testDir =
          Directory.systemTemp.createTempSync('pocketsync_options_test_');
      optionsDbPath = path.join(testDir.path, 'options_test_db.sqlite');

      // Delete any existing database file
      final dbFile = File(optionsDbPath);
      if (dbFile.existsSync()) {
        dbFile.deleteSync();
      }
    });

    tearDown(() {
      // Clean up the database file
      try {
        final dbFile = File(optionsDbPath);
        if (dbFile.existsSync()) {
          dbFile.deleteSync();
        }
      } catch (e) {
        // Ignore cleanup errors
      }
    });

    test('should properly initialize database with schema in options',
        () async {
      // Arrange
      final schema = DatabaseSchema(
        tables: [
          TableSchema(
            name: 'todos',
            columns: [
              TableColumn.primaryKey(name: 'id', type: ColumnType.integer),
              TableColumn.text(name: 'title'),
              TableColumn.boolean(name: 'isCompleted'),
            ],
            indexes: [
              Index(
                name: 'idx_todos_title',
                columns: ['title'],
              ),
            ],
          ),
        ],
      );

      final options = DatabaseOptions(
        dbPath: optionsDbPath,
        version: 1,
        schema: schema,
      );

      // Act - Initialize database with options
      final db = await databaseFactory.openDatabase(
        options.dbPath,
        options: OpenDatabaseOptions(
          version: options.version,
          onCreate: (db, version) async {
            final schemaManager = SchemaManager(schema: schema);
            await schemaManager.initializePocketSyncTables(db);
            await schemaManager.createTablesFromSchema(db);
            await schemaManager.setupChangeTracking(db);
          },
        ),
      );

      // Assert - Check if tables were created correctly
      final tables = await db.query(
        'sqlite_master',
        where: "type = 'table'",
      );
      final tableNames = tables.map((t) => t['name'] as String).toList();

      expect(tableNames, contains('todos'));

      // Check if columns were created
      final columns = await db.rawQuery("PRAGMA table_info('todos')");
      final columnNames = columns.map((c) => c['name'] as String).toList();

      expect(columnNames, contains('id'));
      expect(columnNames, contains('title'));
      expect(columnNames, contains('isCompleted'));
      expect(columnNames, contains(SyncConfig.defaultGlobalIdColumnName));

      // Check if index was created
      final indexes = await db.query(
        'sqlite_master',
        where: "type = 'index' AND tbl_name = 'todos'",
      );
      final indexNames = indexes.map((i) => i['name'] as String).toList();

      expect(indexNames, contains('idx_todos_title'));

      // Clean up
      await db.close();
    });
  });
}
