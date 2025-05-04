import 'package:flutter_test/flutter_test.dart';
import 'package:pocketsync_flutter/src/database/pocket_sync_batch.dart';
import 'package:pocketsync_flutter/src/database/pocket_sync_transaction.dart';
import 'package:pocketsync_flutter/src/models/types.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  // Initialize sqflite_ffi for testing
  setUpAll(() {
    // Initialize FFI
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('PocketSyncTransaction', () {
    late Database inMemoryDb;

    late PocketSyncTransaction pocketSyncTransaction;
    late Set<DatabaseMutation> mutations;

    setUp(() async {
      // Create in-memory database
      inMemoryDb = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            // Create a test table
            await db.execute('''
              CREATE TABLE users (
                id INTEGER PRIMARY KEY,
                name TEXT NOT NULL,
                email TEXT
              )
            ''');
          },
        ),
      );

      // Create a set to track mutations
      mutations = <DatabaseMutation>{};

      // Start a transaction and wrap it with PocketSyncTransaction
      await inMemoryDb.transaction((txn) async {
        pocketSyncTransaction = PocketSyncTransaction(txn, mutations);

        // Run the tests inside the transaction
        await _runTests(pocketSyncTransaction, mutations);
      });
    });

    tearDown(() async {
      // Close the database to clean up resources
      await inMemoryDb.close();
    });
  });
}

// Helper function to run tests inside a transaction
Future<void> _runTests(
    PocketSyncTransaction transaction, Set<DatabaseMutation> mutations) async {
  // Test insert operation
  test('insert operation adds mutation to the set', () async {
    // Execute
    await transaction
        .insert('users', {'name': 'John Doe', 'email': 'john@example.com'});

    // Verify
    expect(mutations.length, 1);
    expect(mutations.first.tableName, 'users');
    expect(mutations.first.changeType, ChangeType.insert);

    // Verify data was inserted
    final result = await transaction.query('users');
    expect(result.length, 1);
    expect(result.first['name'], 'John Doe');
  });

  // Test update operation
  test('update operation adds mutation to the set', () async {
    // Setup - insert a record first
    await transaction.insert(
        'users', {'name': 'Original Name', 'email': 'original@example.com'});
    mutations.clear(); // Clear mutations from setup

    // Execute
    await transaction.update('users', {'name': 'Updated Name'},
        where: 'email = ?', whereArgs: ['original@example.com']);

    // Verify
    expect(mutations.length, 1);
    expect(mutations.first.tableName, 'users');
    expect(mutations.first.changeType, ChangeType.update);

    // Verify data was updated
    final result = await transaction.query('users',
        where: 'email = ?', whereArgs: ['original@example.com']);
    expect(result.length, 1);
    expect(result.first['name'], 'Updated Name');
  });

  // Test delete operation
  test('delete operation adds mutation to the set', () async {
    // Setup - insert a record first
    await transaction
        .insert('users', {'name': 'To Delete', 'email': 'delete@example.com'});
    mutations.clear(); // Clear mutations from setup

    // Execute
    await transaction
        .delete('users', where: 'email = ?', whereArgs: ['delete@example.com']);

    // Verify
    expect(mutations.length, 1);
    expect(mutations.first.tableName, 'users');
    expect(mutations.first.changeType, ChangeType.delete);

    // Verify data was deleted
    final result = await transaction
        .query('users', where: 'email = ?', whereArgs: ['delete@example.com']);
    expect(result.length, 0);
  });

  // Test execute operation
  test('execute operation adds mutation to the set', () async {
    // Execute
    await transaction.execute('INSERT INTO users (name, email) VALUES (?, ?)',
        ['Execute Test', 'execute@example.com']);

    // Verify
    expect(mutations.length, 1);
    expect(mutations.first.tableName, 'users');
    expect(mutations.first.changeType, ChangeType.insert);

    // Verify data was inserted
    final result = await transaction
        .query('users', where: 'email = ?', whereArgs: ['execute@example.com']);
    expect(result.length, 1);
    expect(result.first['name'], 'Execute Test');
  });

  // Test batch operation
  test('batch operation returns PocketSyncBatch', () {
    // Execute
    final batch = transaction.batch();

    // Verify
    expect(batch, isA<PocketSyncBatch>());
  });
}
