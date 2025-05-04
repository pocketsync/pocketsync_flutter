import 'package:flutter_test/flutter_test.dart';
import 'package:pocketsync_flutter/src/database/pocket_sync_batch.dart';
import 'package:pocketsync_flutter/src/models/types.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  // Initialize sqflite_ffi for testing
  setUpAll(() {
    // Initialize FFI
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('PocketSyncBatch', () {
    late Database inMemoryDb;
    late PocketSyncBatch pocketSyncBatch;
    
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
      
      // Create a PocketSyncBatch with the in-memory database
      pocketSyncBatch = PocketSyncBatch(inMemoryDb.batch());
    });
    
    tearDown(() async {
      // Close the database to clean up resources
      await inMemoryDb.close();
    });

    test('insert operation adds mutation to the set', () {
      // Execute
      pocketSyncBatch.insert('users', {
        'name': 'John Doe',
        'email': 'john@example.com'
      });
      
      // Verify
      expect(pocketSyncBatch.mutations.length, 1);
      expect(pocketSyncBatch.mutations.first.tableName, 'users');
      expect(pocketSyncBatch.mutations.first.changeType, ChangeType.insert);
    });
    
    test('update operation adds mutation to the set', () {
      // Execute
      pocketSyncBatch.update('users', {'name': 'Jane Doe'}, where: 'id = ?', whereArgs: [1]);
      
      // Verify
      expect(pocketSyncBatch.mutations.length, 1);
      expect(pocketSyncBatch.mutations.first.tableName, 'users');
      expect(pocketSyncBatch.mutations.first.changeType, ChangeType.update);
    });
    
    test('delete operation adds mutation to the set', () {
      // Execute
      pocketSyncBatch.delete('users', where: 'id = ?', whereArgs: [1]);
      
      // Verify
      expect(pocketSyncBatch.mutations.length, 1);
      expect(pocketSyncBatch.mutations.first.tableName, 'users');
      expect(pocketSyncBatch.mutations.first.changeType, ChangeType.delete);
    });
    
    test('rawInsert operation adds mutation to the set', () {
      // Execute
      pocketSyncBatch.rawInsert(
        'INSERT INTO users (name, email) VALUES (?, ?)',
        ['John Doe', 'john@example.com']
      );
      
      // Verify
      expect(pocketSyncBatch.mutations.length, 1);
      expect(pocketSyncBatch.mutations.first.tableName, 'users');
      expect(pocketSyncBatch.mutations.first.changeType, ChangeType.insert);
    });
    
    test('rawUpdate operation adds mutation to the set', () {
      // Execute
      pocketSyncBatch.rawUpdate(
        'UPDATE users SET name = ? WHERE id = ?',
        ['Jane Doe', 1]
      );
      
      // Verify
      expect(pocketSyncBatch.mutations.length, 1);
      expect(pocketSyncBatch.mutations.first.tableName, 'users');
      expect(pocketSyncBatch.mutations.first.changeType, ChangeType.update);
    });
    
    test('rawDelete operation adds mutation to the set', () {
      // Execute
      pocketSyncBatch.rawDelete(
        'DELETE FROM users WHERE id = ?',
        [1]
      );
      
      // Verify
      expect(pocketSyncBatch.mutations.length, 1);
      expect(pocketSyncBatch.mutations.first.tableName, 'users');
      expect(pocketSyncBatch.mutations.first.changeType, ChangeType.delete);
    });
    
    test('multiple operations add multiple mutations', () async {
      // Execute
      pocketSyncBatch.insert('users', {'name': 'John', 'email': 'john@example.com'});
      pocketSyncBatch.update('users', {'name': 'John Doe'}, where: 'email = ?', whereArgs: ['john@example.com']);
      pocketSyncBatch.delete('users', where: 'id = ?', whereArgs: [2]);
      
      // Verify
      expect(pocketSyncBatch.mutations.length, 3);
      
      // Verify mutations contain all expected operations
      final insertMutation = pocketSyncBatch.mutations.where(
        (m) => m.tableName == 'users' && m.changeType == ChangeType.insert
      );
      expect(insertMutation.length, 1);
      
      final updateMutation = pocketSyncBatch.mutations.where(
        (m) => m.tableName == 'users' && m.changeType == ChangeType.update
      );
      expect(updateMutation.length, 1);
      
      final deleteMutation = pocketSyncBatch.mutations.where(
        (m) => m.tableName == 'users' && m.changeType == ChangeType.delete
      );
      expect(deleteMutation.length, 1);
    });
    
    test('commit executes all operations', () async {
      // Setup
      pocketSyncBatch.insert('users', {'name': 'John', 'email': 'john@example.com'});
      
      // Execute
      await pocketSyncBatch.commit();
      
      // Verify data was inserted
      final result = await inMemoryDb.query('users');
      expect(result.length, 1);
      expect(result.first['name'], 'John');
      expect(result.first['email'], 'john@example.com');
    });
  });
}