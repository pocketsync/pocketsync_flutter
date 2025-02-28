import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pocketsync_flutter/src/database/database_change_manager.dart';
import 'package:pocketsync_flutter/src/services/changes_processor.dart';
import 'package:pocketsync_flutter/src/services/conflict_resolver.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../fixtures/change_log_fixtures.dart';

class MockDatabaseChangeManager extends Mock implements DatabaseChangeManager {}

void main() {
  late Database db;
  late MockDatabaseChangeManager mockChangeManager;
  late ConflictResolver conflictResolver;
  late ChangesProcessor processor;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1),
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS __pocketsync_changes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name TEXT NOT NULL,
        operation TEXT NOT NULL,
        data TEXT NOT NULL,
        record_rowid TEXT NOT NULL,
        version INTEGER NOT NULL,
        timestamp INTEGER NOT NULL,
        synced INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS __pocketsync_processed_changes (
        change_log_id INTEGER PRIMARY KEY,
        processed_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS __pocketsync_device_state (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_id TEXT NOT NULL,
        last_sync_timestamp INTEGER
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS test_table (
        ps_global_id TEXT PRIMARY KEY,
        name TEXT,
        timestamp INTEGER
      )
    ''');

    // Initialize device state
    await db.insert('__pocketsync_device_state', {
      'device_id': 'test_device',
      'last_sync_timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    mockChangeManager = MockDatabaseChangeManager();
    conflictResolver = const ConflictResolver();
    processor = ChangesProcessor(
      db,
      conflictResolver: conflictResolver,
      databaseChangeManager: mockChangeManager,
    );
  });

  group('ChangesProcessor', () {
    group('_pruneChangeQueue', () {
      test('should prune changes when queue size exceeds limit', () async {
        // Insert more than _maxQueueSize changes
        final batch = db.batch();
        for (var i = 0; i < 10100; i++) {
          batch.insert('__pocketsync_changes', {
            'table_name': 'test_table',
            'operation': 'INSERT',
            'data': '{"name":"test$i"}',
            'record_rowid': 'id$i',
            'version': 1,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'synced': 0
          });
        }
        await batch.commit();

        // Get unsynced changes (this will trigger pruning)
        await processor.getUnSyncedChanges();

        // Verify that only _maxQueueSize changes remain unsynced
        final count = await db
            .rawQuery(
              'SELECT COUNT(*) FROM __pocketsync_changes WHERE synced = 0',
            )
            .then((result) => result.first.values.first as int? ?? 0);

        expect(count, equals(10000));
      });
    });

    group('getUnSyncedChanges', () {
      test('should return changes in correct format', () async {
        // Insert test changes
        await db.insert('__pocketsync_changes', {
          'table_name': 'test_table',
          'operation': 'INSERT',
          'data': '{"name":"test1"}',
          'record_rowid': 'id1',
          'version': 1,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'synced': 0
        });

        final changes = await processor.getUnSyncedChanges();

        expect(changes.insertions.changes['test_table'], isNotNull);
        expect(
            changes.insertions.changes['test_table']!.rows.length, equals(1));
        expect(
            changes.insertions.changes['test_table']!.rows.first.data['name'],
            equals('test1'));
      });

      test('should handle multiple operations', () async {
        // Insert test changes with different operations
        await db.insert('__pocketsync_changes', {
          'table_name': 'test_table',
          'operation': 'INSERT',
          'data': '{"name":"test1"}',
          'record_rowid': 'id1',
          'version': 1,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'synced': 0
        });

        await db.insert('__pocketsync_changes', {
          'table_name': 'test_table',
          'operation': 'UPDATE',
          'data': '{"name":"test2"}',
          'record_rowid': 'id2',
          'version': 1,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'synced': 0
        });

        await db.insert('__pocketsync_changes', {
          'table_name': 'test_table',
          'operation': 'DELETE',
          'data': '{"name":"test3"}',
          'record_rowid': 'id3',
          'version': 1,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'synced': 0
        });

        final changes = await processor.getUnSyncedChanges();

        expect(
            changes.insertions.changes['test_table']!.rows.length, equals(1));
        expect(changes.updates.changes['test_table']!.rows.length, equals(1));
        expect(changes.deletions.changes['test_table']!.rows.length, equals(1));
      });
    });

    group('applyRemoteChanges', () {
      test('should handle empty change logs', () async {
        // When
        await processor.applyRemoteChanges([]);

        // Then
        final processedChanges =
            await db.query('__pocketsync_processed_changes');
        expect(processedChanges, isEmpty);
      });

      test('should skip already processed changes', () async {
        // Given
        final changeLogs = [ChangeLogFixtures.insert];

        // Insert a processed change
        await db.insert('__pocketsync_processed_changes', {
          'change_log_id': changeLogs.first.id,
          'processed_at': DateTime.now().toIso8601String(),
        });

        // When
        await processor.applyRemoteChanges(changeLogs);

        // Then
        final processedChanges =
            await db.query('__pocketsync_processed_changes');
        expect(processedChanges.length, equals(1));
      });

      test('should handle conflicts with existing records', () async {
        // Insert existing record
        await db.insert('test_table', {
          'ps_global_id': 'id1',
          'name': 'original',
          'timestamp': DateTime.now().millisecondsSinceEpoch - 1000,
        });

        // Create a change log with an update to the same record
        final changeLog = ChangeLogFixtures.update;

        // When
        await processor.applyRemoteChanges([changeLog]);

        // Then
        final updatedRecord = await db
            .query('test_table', where: 'ps_global_id = ?', whereArgs: ['id1']);
        expect(updatedRecord.first['name'], equals('updated'));
      });

      test('should notify changes for affected tables', () async {
        // When
        await processor.applyRemoteChanges([ChangeLogFixtures.insert]);

        // Then
        verify(() => mockChangeManager.notifyChange(any(), isRemote: true))
            .called(1);
      });
    });
  });

  group('markChangesSynced', () {
    test('should mark changes as synced', () async {
      // Insert test changes
      final ids = await Future.wait([
        db.insert('__pocketsync_changes', {
          'table_name': 'test_table',
          'operation': 'INSERT',
          'data': '{"name":"test1"}',
          'record_rowid': 'id1',
          'version': 1,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'synced': 0
        }),
        db.insert('__pocketsync_changes', {
          'table_name': 'test_table',
          'operation': 'UPDATE',
          'data': '{"name":"test2"}',
          'record_rowid': 'id2',
          'version': 1,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'synced': 0
        })
      ]);

      // When
      await processor.markChangesSynced(ids);

      // Then
      final changes =
          await db.query('__pocketsync_changes', where: 'synced = 1');
      expect(changes.length, equals(2));
    });
  });

  tearDown(() async {
    await db.close();
  });
}
