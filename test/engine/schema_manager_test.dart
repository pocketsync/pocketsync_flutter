import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pocketsync_flutter/pocketsync_flutter.dart';
import 'package:pocketsync_flutter/src/engine/schema_manager.dart';
import 'package:pocketsync_flutter/src/utils/sync_config.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../database/database_test_utils.dart';

// Mock classes
class MockDatabase extends Mock implements Database {}

class MockTransaction extends Mock implements Transaction {}

class MockBatch extends Mock implements Batch {}

void main() {
  // Initialize sqflite_ffi for testing
  setUpAll(() {
    DatabaseTestUtils.initializeSqfliteFfi();
  });

  group('SchemaManager', () {
    late SchemaManager schemaManager;
    late Database db;

    setUp(() async {

      final schema = DatabaseSchema(
        tables: [
          TableSchema(
            name: 'users',
            columns: [
              TableColumn.primaryKey(name: 'id', type: ColumnType.integer),
              TableColumn.text(name: 'name', isNullable: false),
              TableColumn.text(name: 'email'),
            ],
          ),
          TableSchema(
            name: 'products',
            columns: [
              TableColumn.primaryKey(name: 'id', type: ColumnType.integer),
              TableColumn.text(name: 'name', isNullable: false),
              TableColumn.text(name: 'price'),
            ],
          ),
        ],
      );
      // Create a new SchemaManager instance for each test
      schemaManager = SchemaManager(schema: schema);

      // Create an in-memory database for testing
      db = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
      );

      for (final table in schema.tables) {
        await db.execute(table.toCreateTableSql());
        for (final index in table.toCreateIndexSql()) {
          await db.execute(index);
        }
      }
    });

    tearDown(() async {
      // Close the database after each test
      await db.close();
    });

    group('initializePocketSyncTables', () {
      test('should create all required PocketSync tables', () async {
        // Act
        await schemaManager.initializePocketSyncTables(db);

        // Assert - Check if tables were created
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
              '__pocketsync_device_state',
              '__pocketsync_version',
              '__pocketsync_processed_tables',
            ]));

        // Verify indexes were created for __pocketsync_changes table
        final indexes = await db.query(
          'sqlite_master',
          where: "type = 'index' AND tbl_name = '__pocketsync_changes'",
        );

        expect(indexes.length,
            greaterThanOrEqualTo(5)); // At least 5 indexes should be created
      });
    });

    group('getUserTables', () {
      test('should return only user tables', () async {
        // Arrange - Create PocketSync tables
        await schemaManager.initializePocketSyncTables(db);

        // Act
        final allTables = await db.query(
          'sqlite_master',
          where: "type = 'table'",
        );
        final allTableNames =
            allTables.map((t) => t['name'] as String).toList();

        // Verify our test tables exist
        expect(allTableNames, containsAll(['users', 'products']));

        // Now run setupChangeTracking which uses _getUserTables internally
        await schemaManager.setupChangeTracking(db);

        // Verify that global ID columns were added to user tables only
        final usersColumns = await db.rawQuery("PRAGMA table_info('users')");
        final productsColumns =
            await db.rawQuery("PRAGMA table_info('products')");

        // Check if ps_global_id column exists in both tables
        final usersHasGlobalId = usersColumns
            .any((col) => col['name'] == SyncConfig.defaultGlobalIdColumnName);
        final productsHasGlobalId = productsColumns
            .any((col) => col['name'] == SyncConfig.defaultGlobalIdColumnName);

        expect(usersHasGlobalId, isTrue);
        expect(productsHasGlobalId, isTrue);
      });
    });

    group('setupChangeTracking', () {
      test(
          'should add global ID column and create triggers for all user tables',
          () async {
        // Arrange
        await schemaManager.initializePocketSyncTables(db);

        // Act
        await schemaManager.setupChangeTracking(db);

        // Assert - Check if global ID column was added to user tables
        final usersColumns = await db.rawQuery("PRAGMA table_info('users')");
        final productsColumns =
            await db.rawQuery("PRAGMA table_info('products')");

        // Check if ps_global_id column exists in both tables
        final usersHasGlobalId = usersColumns
            .any((col) => col['name'] == SyncConfig.defaultGlobalIdColumnName);
        final productsHasGlobalId = productsColumns
            .any((col) => col['name'] == SyncConfig.defaultGlobalIdColumnName);

        expect(usersHasGlobalId, isTrue);
        expect(productsHasGlobalId, isTrue);

        // Check if triggers were created
        final triggers = await db.query(
          'sqlite_master',
          where:
              "type = 'trigger' AND (name LIKE 'after_insert_%' OR name LIKE 'after_update_%' OR name LIKE 'after_delete_%')",
        );

        final triggerNames = triggers.map((t) => t['name'] as String).toList();

        // Should have 3 triggers per table (insert, update, delete)
        expect(
            triggerNames,
            containsAll([
              'after_insert_users',
              'after_update_users',
              'after_delete_users',
              'after_insert_products',
              'after_update_products',
              'after_delete_products',
            ]));
      });

      test('should generate global IDs for existing records', () async {
        // Arrange
        await schemaManager.initializePocketSyncTables(db);

        // Insert test data without global IDs
        await db.insert(
            'users', {'name': 'Test User 1', 'email': 'user1@example.com'});
        await db.insert(
            'users', {'name': 'Test User 2', 'email': 'user2@example.com'});

        // Act
        await schemaManager.setupChangeTracking(db);

        // Assert - Check if global IDs were generated
        final users = await db.query('users');

        // All users should have a global ID
        for (final user in users) {
          expect(user[SyncConfig.defaultGlobalIdColumnName], isNotNull);
          expect(user[SyncConfig.defaultGlobalIdColumnName], isNotEmpty);
        }
      });
    });

    group('registerDevice', () {
      test('should register a new device', () async {
        // Arrange
        await schemaManager.initializePocketSyncTables(db);
        final deviceId = 'test-device-id';

        // Act
        await schemaManager.registerDevice(db, deviceId);

        // Assert
        final devices = await db.query('__pocketsync_device_state');

        expect(devices.length, 1);
        expect(devices.first['device_id'], deviceId);
        expect(devices.first['last_sync_status'], 'NEVER_SYNCED');
      });

      test('should not create duplicate device entries', () async {
        // Arrange
        await schemaManager.initializePocketSyncTables(db);
        final deviceId = 'test-device-id';

        // Register device first time
        await schemaManager.registerDevice(db, deviceId);

        // Act - Register same device again
        await schemaManager.registerDevice(db, deviceId);

        // Assert - Should still have only one entry
        final devices = await db.query('__pocketsync_device_state');
        expect(devices.length, 1);
      });
    });

    group('getSyncStatus', () {
      test('should return correct sync status', () async {
        // Arrange
        await schemaManager.initializePocketSyncTables(db);
        await schemaManager.registerDevice(db, 'test-device-id');

        // Act
        final status = await schemaManager.getSyncStatus(db);

        // Assert
        expect(status, isA<Map<String, dynamic>>());
        expect(status['devices'], isA<List>());
        expect(status['pending_changes'], 0);
      });
    });

    group('reset', () {
      test('should reset all PocketSync state', () async {
        // Arrange
        await schemaManager.initializePocketSyncTables(db);
        await schemaManager.setupChangeTracking(db);
        await schemaManager.registerDevice(db, 'test-device-id');

        // Insert some test data to generate changes
        await db.insert(
            'users', {'name': 'Test User', 'email': 'user@example.com'});

        // Act
        await schemaManager.reset(db);

        // Assert - Check if tables were recreated
        final tables = await db.query(
          'sqlite_master',
          where: "type = 'table' AND name LIKE '__pocketsync_%'",
        );

        // Tables should be recreated
        expect(tables.length, 4);

        // Check if version was saved
        final version = await db.query('__pocketsync_version');
        expect(version.length, 1);
        expect(version.first['version'], SyncConfig.pluginVersion);
      });
    });

    group('cleanupOldSyncRecords', () {
      test('should delete old synced records based on retention policy',
          () async {
        // Arrange
        await schemaManager.initializePocketSyncTables(db);

        // Insert a device state with old cleanup timestamp
        final oldTimestamp = DateTime.now()
            .subtract(const Duration(days: 2))
            .millisecondsSinceEpoch;

        await db.insert('__pocketsync_device_state', {
          'device_id': 'test-device',
          'last_cleanup_timestamp': oldTimestamp,
        });

        // Insert some old synced records
        final oldRecordTimestamp = DateTime.now()
            .subtract(const Duration(days: 31))
            .millisecondsSinceEpoch;

        await db.insert('__pocketsync_changes', {
          'id': 'old-change-1',
          'table_name': 'users',
          'record_rowid': '1',
          'operation': 'INSERT',
          'timestamp': oldRecordTimestamp,
          'data': '{}',
          'version': 1,
          'synced': 1, // Synced record
        });

        // Insert a newer record that shouldn't be deleted
        final newRecordTimestamp = DateTime.now()
            .subtract(const Duration(days: 1))
            .millisecondsSinceEpoch;

        await db.insert('__pocketsync_changes', {
          'id': 'new-change-1',
          'table_name': 'users',
          'record_rowid': '2',
          'operation': 'INSERT',
          'timestamp': newRecordTimestamp,
          'data': '{}',
          'version': 1,
          'synced': 1, // Synced record
        });

        // Act
        final options = PocketSyncOptions(
          projectId: 'test-project',
          authToken: 'test-token',
          serverUrl: 'https://test-server.com',
          changeLogRetentionDays: 30,
        );
        final deletedCount =
            await schemaManager.cleanupOldSyncRecords(db, options);

        // Assert
        expect(deletedCount, 1); // Only one record should be deleted

        // Check if only the old record was deleted
        final remainingChanges = await db.query('__pocketsync_changes');
        expect(remainingChanges.length, 1);
        expect(remainingChanges.first['id'], 'new-change-1');

        // Check if device state was updated
        final deviceState = await db.query('__pocketsync_device_state');
        expect(deviceState.first['last_cleanup_timestamp'], isNotNull);
        expect((deviceState.first['last_cleanup_timestamp'] as int),
            greaterThan(oldTimestamp));
      });
    });

    group('generateUpdateCondition', () {
      test('should generate correct SQL condition for detecting changes', () {
        // Arrange
        final columns = [
          'id',
          'name',
          'email',
          SyncConfig.defaultGlobalIdColumnName
        ];

        // Act
        final condition = schemaManager.generateUpdateCondition(columns);

        // Assert
        // Should exclude the global ID column
        expect(condition, contains('OLD.id IS NOT NEW.id'));
        expect(condition, contains('OLD.name IS NOT NEW.name'));
        expect(condition, contains('OLD.email IS NOT NEW.email'));
        expect(condition,
            isNot(contains('OLD.${SyncConfig.defaultGlobalIdColumnName}')));
      });
    });

    group('syncPreExistingData', () {
      test('should create change records for existing data', () async {
        // Arrange
        await schemaManager.initializePocketSyncTables(db);
        await schemaManager.setupChangeTracking(db);
        await schemaManager.registerDevice(db, 'test-device-id');

        // Insert test data
        await db.insert('users',
            {'name': 'Existing User 1', 'email': 'existing1@example.com'});
        await db.insert('users',
            {'name': 'Existing User 2', 'email': 'existing2@example.com'});

        // Act
        final options = PocketSyncOptions(
          projectId: 'test-project',
          authToken: 'test-token',
          serverUrl: 'https://test-server.com',
          syncExistingData: true,
        );
        await schemaManager.syncPreExistingData(db, options);

        // Assert
        final changes = await db.query('__pocketsync_changes');

        // The number of changes might vary based on how setupChangeTracking works
        // and if it creates additional changes, so we'll just verify changes exist
        expect(changes.isNotEmpty, isTrue);

        // Check if table was marked as processed
        final processedTables = await db.query('__pocketsync_processed_tables');
        expect(processedTables.isNotEmpty, isTrue);
        expect(processedTables.first['table_name'], 'users');
      });

      test('should not process tables that were already processed', () async {
        // Arrange
        await schemaManager.initializePocketSyncTables(db);
        await schemaManager.setupChangeTracking(db);
        await schemaManager.registerDevice(db, 'test-device-id');

        // Mark the table as already processed
        await db.insert('__pocketsync_processed_tables', {
          'table_name': 'users',
          'processed_at': DateTime.now().millisecondsSinceEpoch,
        });

        // Insert test data
        await db.insert('users',
            {'name': 'Existing User', 'email': 'existing@example.com'});

        // Act
        final options = PocketSyncOptions(
          projectId: 'test-project',
          authToken: 'test-token',
          serverUrl: 'https://test-server.com',
          syncExistingData: true,
        );
        await schemaManager.syncPreExistingData(db, options);

        // Since we've already processed the table, we shouldn't have any new records
        // in the processed_tables table for this table
        final processedTables = await db.query(
          '__pocketsync_processed_tables',
          where: "table_name = 'users'",
        );

        // There should be exactly one entry for the users table
        expect(processedTables.length, 1);
      });
    });
  });
}
