import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pocketsync_flutter/src/database/database_watcher.dart';
import 'package:pocketsync_flutter/src/database/pocket_sync_database.dart';
import 'package:pocketsync_flutter/src/engine/schema_manager.dart';
import 'package:pocketsync_flutter/src/models/schema.dart';
import 'package:pocketsync_flutter/src/models/types.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'database_test_utils.dart';

// Mock classes
class MockDatabaseWatcher extends Mock implements DatabaseWatcher {}

class MockSchemaManager extends Mock implements SchemaManager {}

void main() {
  // Initialize sqflite_ffi for testing
  setUpAll(() {
    DatabaseTestUtils.initializeSqfliteFfi();
    registerFallbackValue(ChangeType.insert);
    registerFallbackValue('table_name');
  });

  group('PocketSyncDatabase', () {
    late PocketSyncDatabase pocketSyncDb;
    late MockDatabaseWatcher mockDatabaseWatcher;
    late SchemaManager schemaManager;

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
      ],
    );

    setUp(() async {
      // Create real SchemaManager and mock DatabaseWatcher
      schemaManager = SchemaManager(schema: schema);
      mockDatabaseWatcher = MockDatabaseWatcher();

      // Create the PocketSyncDatabase instance
      pocketSyncDb = PocketSyncDatabase(schemaManager: schemaManager);

      // Initialize the database with in-memory database
      final options = DatabaseOptions(
        version: 1,
        schema: schema,
        dbPath: inMemoryDatabasePath,
      );

      // Initialize the database with our mock watcher
      await pocketSyncDb.initialize(options, mockDatabaseWatcher);

      // Initialize the database with our mock watcher
      await pocketSyncDb.initialize(options, mockDatabaseWatcher);

      for (final table in schema.tables) {
        await pocketSyncDb.execute(table.toCreateTableSql());
      }

      // Insert test data
      await pocketSyncDb.insert(
          'users', {'name': 'Test User 1', 'email': 'user1@example.com'});

      // Reset the mock to clear previous calls
      reset(mockDatabaseWatcher);
    });

    tearDown(() async {
      // Close the database after each test
      pocketSyncDb.close();
    });

    group('Database initialization', () {
      test('initializes the database with the correct schema', () async {
        // Arrange
        final options = DatabaseOptions(
          version: 1,
          schema: schema,
          dbPath: inMemoryDatabasePath,
        );

        // Act
        await pocketSyncDb.initialize(options, mockDatabaseWatcher);

        // Act
        await pocketSyncDb.initialize(options, mockDatabaseWatcher);

        // Assert
        final users = await pocketSyncDb.query('users');
        // Dear future me, the user was created in test setUp in case i'm wondering why it's 1
        expect(users.length, 1);
      });
    });

    group('CRUD operations', () {
      test('insert adds data and notifies watchers', () async {
        // Arrange
        final userData = {'name': 'Test User 2', 'email': 'user2@example.com'};

        // Act
        await pocketSyncDb.insert('users', userData);

        // Assert
        final users = await pocketSyncDb
            .query('users', where: 'name = ?', whereArgs: ['Test User 2']);
        expect(users.length, 1);
        expect(users.first['name'], 'Test User 2');

        // Verify that the database watcher was notified
        verify(() =>
                mockDatabaseWatcher.notifyListeners('users', ChangeType.insert))
            .called(1);
      });

      test('update modifies data and notifies watchers', () async {
        // Arrange
        final updatedData = {
          'name': 'Updated User 1',
          'email': 'updated1@example.com'
        };

        // Act
        await pocketSyncDb.update('users', updatedData,
            where: 'name = ?', whereArgs: ['Test User 1']);

        // Assert
        final users = await pocketSyncDb
            .query('users', where: 'name = ?', whereArgs: ['Updated User 1']);
        expect(users.length, 1);
        expect(users.first['email'], 'updated1@example.com');

        // Verify that the database watcher was notified
        verify(() =>
                mockDatabaseWatcher.notifyListeners('users', ChangeType.update))
            .called(1);
      });

      test('delete removes data and notifies watchers', () async {
        // Act
        await pocketSyncDb
            .delete('users', where: 'name = ?', whereArgs: ['Test User 1']);

        // Assert
        final users = await pocketSyncDb.query('users');
        expect(users.length, 0);

        // Verify that the database watcher was notified
        verify(() =>
                mockDatabaseWatcher.notifyListeners('users', ChangeType.delete))
            .called(1);
      });

      test('execute with INSERT notifies watchers', () async {
        // Act
        await pocketSyncDb.execute(
            "INSERT INTO users (name, email) VALUES ('SQL User', 'sql@example.com')");

        // Assert
        final users = await pocketSyncDb
            .query('users', where: 'name = ?', whereArgs: ['SQL User']);
        expect(users.length, 1);

        // Verify that the database watcher was notified
        verify(() =>
                mockDatabaseWatcher.notifyListeners('users', ChangeType.insert))
            .called(1);
      });

      test('execute with UPDATE notifies watchers', () async {
        // Act
        await pocketSyncDb.execute(
            "UPDATE users SET email = 'new@example.com' WHERE name = 'Test User 1'");

        // Assert
        final users = await pocketSyncDb
            .query('users', where: 'name = ?', whereArgs: ['Test User 1']);
        expect(users.first['email'], 'new@example.com');

        // Verify that the database watcher was notified
        verify(() =>
                mockDatabaseWatcher.notifyListeners('users', ChangeType.update))
            .called(1);
      });

      test('execute with DELETE notifies watchers', () async {
        // Act
        await pocketSyncDb
            .execute("DELETE FROM users WHERE name = 'Test User 1'");

        // Assert
        final users = await pocketSyncDb.query('users');
        expect(users.length, 0);

        // Verify that the database watcher was notified
        verify(() =>
                mockDatabaseWatcher.notifyListeners('users', ChangeType.delete))
            .called(1);
      });

      test('rawInsert adds data and notifies watchers', () async {
        // Act
        await pocketSyncDb.rawInsert(
            "INSERT INTO users (name, email) VALUES (?, ?)",
            ['Raw User', 'raw@example.com']);

        // Assert
        final users = await pocketSyncDb
            .query('users', where: 'name = ?', whereArgs: ['Raw User']);
        expect(users.length, 1);

        // Verify that the database watcher was notified
        verify(() =>
                mockDatabaseWatcher.notifyListeners('users', ChangeType.insert))
            .called(1);
      });

      test('rawUpdate updates data and notifies watchers', () async {
        // Act
        await pocketSyncDb.rawUpdate(
            "UPDATE users SET email = ? WHERE name = ?",
            ['raw_updated@example.com', 'Test User 1']);

        // Assert
        final users = await pocketSyncDb
            .query('users', where: 'name = ?', whereArgs: ['Test User 1']);
        expect(users.first['email'], 'raw_updated@example.com');

        // Verify that the database watcher was notified
        verify(() =>
                mockDatabaseWatcher.notifyListeners('users', ChangeType.update))
            .called(1);
      });

      test('rawDelete deletes data and notifies watchers', () async {
        // Act
        await pocketSyncDb
            .rawDelete("DELETE FROM users WHERE name = ?", ['Test User 1']);

        // Assert
        final users = await pocketSyncDb.query('users');
        expect(users.length, 0);

        // Verify that the database watcher was notified
        verify(() =>
                mockDatabaseWatcher.notifyListeners('users', ChangeType.delete))
            .called(1);
      });

      test('rawQuery with SELECT does not notify watchers', () async {
        // Act
        await pocketSyncDb
            .rawQuery("SELECT * FROM users WHERE name = ?", ['Test User 1']);

        // Assert - No notifications should be sent for SELECT queries
        verifyNever(() => mockDatabaseWatcher.notifyListeners(any(), any()));
      });
    });

    group('Batch operations', () {
      test('batch operations notify database watcher for all mutations',
          () async {
        // Arrange
        final batch = pocketSyncDb.batch();

        // Act - Add multiple operations to the batch
        batch.insert(
            'users', {'name': 'Batch User 1', 'email': 'batch1@example.com'});
        batch.update('users', {'email': 'updated@example.com'},
            where: 'name = ?', whereArgs: ['Batch User 1']);

        // Commit the batch
        await pocketSyncDb.commit(batch);

        // Assert - Should notify for both operations
        verify(() =>
                mockDatabaseWatcher.notifyListeners('users', ChangeType.insert))
            .called(1);
        verify(() =>
                mockDatabaseWatcher.notifyListeners('users', ChangeType.update))
            .called(1);
      });
    });

    group('Transaction operations', () {
      test('transaction operations notify database watcher for all mutations',
          () async {
        // Act
        await pocketSyncDb.transaction((txn) async {
          await txn.insert(
              'users', {'name': 'Txn User 1', 'email': 'txn1@example.com'});
          await txn.update('users', {'email': 'txn_updated@example.com'},
              where: 'name = ?', whereArgs: ['Txn User 1']);
          return true;
        });

        // Assert - Should notify for both operations
        verify(() =>
                mockDatabaseWatcher.notifyListeners('users', ChangeType.insert))
            .called(1);
        verify(() =>
                mockDatabaseWatcher.notifyListeners('users', ChangeType.update))
            .called(1);
      });
    });

    group('Watch functionality', () {
      test('watch returns a stream of query results', () async {
        // Arrange
        await pocketSyncDb.insert(
            'users', {'name': 'Watch User', 'email': 'watch@example.com'});
        reset(mockDatabaseWatcher);

        // Act
        final stream = pocketSyncDb
            .watch('SELECT * FROM users WHERE name = ?', ['Watch User']);

        // Assert
        expect(stream, isA<Stream<List<Map<String, dynamic>>>>());

        // Verify the stream emits the correct data
        final result = await stream.first;
        expect(result.length, 1);
        expect(result.first['name'], 'Watch User');
      });
    });
  });
}
