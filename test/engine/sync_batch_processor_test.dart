import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pocketsync_flutter/src/engine/change_aggregator.dart';
import 'package:pocketsync_flutter/src/engine/pocket_sync_network_client.dart';
import 'package:pocketsync_flutter/src/engine/sync_batch_processor.dart';
import 'package:pocketsync_flutter/src/models/aggregated_changes.dart';
import 'package:pocketsync_flutter/src/models/sync_change.dart';
import 'package:pocketsync_flutter/src/models/types.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../database/database_test_utils.dart';

// Mock classes
class MockChangeAggregator extends Mock implements ChangeAggregator {}

class MockPocketSyncNetworkClient extends Mock
    implements PocketSyncNetworkClient {}

class MockDatabase extends Mock implements Database {}

void main() {
  // Initialize sqflite_ffi for testing
  setUpAll(() {
    DatabaseTestUtils.initializeSqfliteFfi();

    // Register fallback values for mocktail
    registerFallbackValue(<SyncChange>[]);
    registerFallbackValue(ChangeType.insert);
  });

  group('SyncBatchProcessor', () {
    late SyncBatchProcessor batchProcessor;
    late MockChangeAggregator mockChangeAggregator;
    late MockPocketSyncNetworkClient mockApiClient;
    late Database db;

    setUp(() async {
      // Create mocks
      mockChangeAggregator = MockChangeAggregator();
      mockApiClient = MockPocketSyncNetworkClient();

      // Create an in-memory database for testing
      db = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: (db, version) async {
          // Create the changes tracking table
          await db.execute('''
            CREATE TABLE __pocketsync_changes (
              id TEXT PRIMARY KEY,
              table_name TEXT NOT NULL,
              record_rowid TEXT NOT NULL,
              operation TEXT NOT NULL,
              data TEXT NOT NULL,
              timestamp INTEGER NOT NULL,
              version INTEGER NOT NULL,
              synced INTEGER NOT NULL DEFAULT 0
            )
          ''');

          // Create the device state table
          await db.execute('''
            CREATE TABLE __pocketsync_device_state (
              id INTEGER PRIMARY KEY,
              device_id TEXT NOT NULL,
              last_download_timestamp INTEGER,
              last_upload_timestamp INTEGER
            )
          ''');

          // Insert initial device state record
          await db.insert('__pocketsync_device_state', {
            'id': 1,
            'device_id': 'test-device',
            'last_download_timestamp': DateTime.now().millisecondsSinceEpoch,
            'last_upload_timestamp': DateTime.now().millisecondsSinceEpoch,
          });

          // Create a test table
          await db.execute('''
            CREATE TABLE users (
              id INTEGER PRIMARY KEY,
              name TEXT NOT NULL,
              email TEXT,
              ps_global_id TEXT
            )
          ''');
        },
      );

      // Create the SyncBatchProcessor with mocks
      batchProcessor = SyncBatchProcessor(
        database: db,
        apiClient: mockApiClient,
        changeAggregator: mockChangeAggregator,
        maxBatchSize: 2, // Small batch size for testing
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('should initialize with correct properties', () {
      expect(batchProcessor, isNotNull);
    });

    test('should process unsynced changes by table', () async {
      // Arrange
      final tables = ['users', 'posts'];

      // Mock change aggregator to return changes for each table
      final userChanges = [
        SyncChange(
          id: 'change1',
          tableName: 'users',
          recordId: 'user1',
          operation: ChangeType.insert,
          data: {
            'new': {'id': 1, 'name': 'John'}
          },
          timestamp: DateTime.now().millisecondsSinceEpoch,
          version: 1,
        ),
        SyncChange(
          id: 'change2',
          tableName: 'users',
          recordId: 'user2',
          operation: ChangeType.update,
          data: {
            'new': {'id': 2, 'name': 'Jane'},
            'old': {'id': 2, 'name': 'Janet'}
          },
          timestamp: DateTime.now().millisecondsSinceEpoch,
          version: 1,
        ),
      ];

      final postChanges = [
        SyncChange(
          id: 'change3',
          tableName: 'posts',
          recordId: 'post1',
          operation: ChangeType.insert,
          data: {
            'new': {'id': 1, 'title': 'Post 1'}
          },
          timestamp: DateTime.now().millisecondsSinceEpoch,
          version: 1,
        ),
      ];

      when(() => mockChangeAggregator.aggregateChanges('users'))
          .thenAnswer((_) async => AggregatedChanges(
                changes: userChanges,
                affectedChangeIds: ['change1', 'change2'],
              ));

      when(() => mockChangeAggregator.aggregateChanges('posts'))
          .thenAnswer((_) async => AggregatedChanges(
                changes: postChanges,
                affectedChangeIds: ['change3'],
              ));

      // Mock API client to return success for uploads
      when(() => mockApiClient.uploadChanges(any()))
          .thenAnswer((_) async => true);

      // Act
      final results = await batchProcessor.processUnsyncedChanges(tables);

      // Assert
      expect(results, {'users': true, 'posts': true});
      verify(() => mockChangeAggregator.aggregateChanges('users')).called(1);
      verify(() => mockChangeAggregator.aggregateChanges('posts')).called(1);

      // Verify uploads - should be called once for each change type per table
      // For users: once for inserts, once for updates
      // For posts: once for inserts
      verify(() => mockApiClient.uploadChanges(any())).called(3);
    });

    test('should handle empty changes', () async {
      // Arrange
      final tables = ['empty_table'];

      when(() => mockChangeAggregator.aggregateChanges('empty_table'))
          .thenAnswer((_) async => AggregatedChanges(
                changes: [],
                affectedChangeIds: [],
              ));

      // Act
      final results = await batchProcessor.processUnsyncedChanges(tables);

      // Assert
      expect(results, {'empty_table': true});
      verify(() => mockChangeAggregator.aggregateChanges('empty_table'))
          .called(1);
      verifyNever(() => mockApiClient.uploadChanges(any()));
    });

    test('should process changes in batches when exceeding max batch size',
        () async {
      // Arrange
      final tables = ['large_table'];

      // Create a list of 5 changes (larger than our max batch size of 2)
      final largeChanges = List.generate(
        5,
        (i) => SyncChange(
          id: 'change$i',
          tableName: 'large_table',
          recordId: 'record$i',
          operation: ChangeType.insert,
          data: {
            'new': {'id': i, 'name': 'Item $i'}
          },
          timestamp: DateTime.now().millisecondsSinceEpoch,
          version: 1,
        ),
      );

      when(() => mockChangeAggregator.aggregateChanges('large_table'))
          .thenAnswer((_) async => AggregatedChanges(
                changes: largeChanges,
                affectedChangeIds: largeChanges.map((c) => c.id).toList(),
              ));

      when(() => mockApiClient.uploadChanges(any()))
          .thenAnswer((_) async => true);

      // Act
      final results = await batchProcessor.processUnsyncedChanges(tables);

      // Assert
      expect(results, {'large_table': true});

      // Should be called 3 times:
      // - First batch of 2 changes
      // - Second batch of 2 changes
      // - Third batch of 1 change
      verify(() => mockApiClient.uploadChanges(any())).called(3);
    });

    test('should mark changes as synced', () async {
      // Arrange
      final tableName = 'users';
      final changeIds = ['change1', 'change2'];

      // Insert some test changes
      for (final id in changeIds) {
        await db.insert('__pocketsync_changes', {
          'id': id,
          'table_name': tableName,
          'record_rowid': 'record1',
          'operation': 'insert',
          'data': '{"new":{"id":1,"name":"Test"}}',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'version': 1,
          'synced': 0,
        });
      }

      // Act
      await batchProcessor.markChangesAsSynced(tableName, changeIds);

      // Assert
      final result = await db.query(
        '__pocketsync_changes',
        where: 'id IN (?, ?)',
        whereArgs: changeIds,
      );

      expect(result.length, 2);
      for (final row in result) {
        expect(row['synced'], 1);
      }
    });

    test('should handle upload failures', () async {
      // Arrange
      final tables = ['failing_table'];

      final changes = [
        SyncChange(
          id: 'change1',
          tableName: 'failing_table',
          recordId: 'record1',
          operation: ChangeType.insert,
          data: {
            'new': {'id': 1, 'name': 'Test'}
          },
          timestamp: DateTime.now().millisecondsSinceEpoch,
          version: 1,
        ),
      ];

      when(() => mockChangeAggregator.aggregateChanges('failing_table'))
          .thenAnswer((_) async => AggregatedChanges(
                changes: changes,
                affectedChangeIds: ['change1'],
              ));

      // Mock API client to return failure for uploads
      when(() => mockApiClient.uploadChanges(any()))
          .thenAnswer((_) async => false);

      // Act
      final results = await batchProcessor.processUnsyncedChanges(tables);

      // Assert
      expect(results, {'failing_table': false});
      verify(() => mockApiClient.uploadChanges(any())).called(1);
    });
  });
}
