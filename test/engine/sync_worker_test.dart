import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pocketsync_flutter/src/database/database_watcher.dart';
import 'package:pocketsync_flutter/src/engine/change_aggregator.dart';
import 'package:pocketsync_flutter/src/engine/merge_engine.dart';
import 'package:pocketsync_flutter/src/engine/pocket_sync_network_client.dart';
import 'package:pocketsync_flutter/src/engine/schema_manager.dart';
import 'package:pocketsync_flutter/src/engine/sync_queue.dart';
import 'package:pocketsync_flutter/src/engine/sync_worker.dart';
import 'package:pocketsync_flutter/src/models/aggregated_changes.dart';
import 'package:pocketsync_flutter/src/models/changes_response.dart';
import 'package:pocketsync_flutter/src/models/sync_change.dart';
import 'package:pocketsync_flutter/src/models/types.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../database/database_test_utils.dart';

// Mock classes
class MockSyncQueue extends Mock implements SyncQueue {}

class MockChangeAggregator extends Mock implements ChangeAggregator {}

class MockPocketSyncNetworkClient extends Mock
    implements PocketSyncNetworkClient {}

class MockMergeEngine extends Mock implements MergeEngine {}

class MockSchemaManager extends Mock implements SchemaManager {}

class MockDatabaseWatcher extends Mock implements DatabaseWatcher {}

// Fake implementations and mocks for testing
class FakeDatabase extends Fake implements Database {}

class MockDatabase extends Mock implements Database {}

void main() {
  // Initialize sqflite_ffi for testing
  setUpAll(() {
    DatabaseTestUtils.initializeSqfliteFfi();

    // Register fallback values for mocktail
    registerFallbackValue(DateTime(2025));
    registerFallbackValue(<SyncChange>[]);
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(FakeDatabase());
  });

  group('SyncWorker', () {
    late SyncWorker syncWorker;
    late MockSyncQueue mockSyncQueue;
    late MockChangeAggregator mockChangeAggregator;
    late MockPocketSyncNetworkClient mockApiClient;
    late MockMergeEngine mockMergeEngine;
    late MockSchemaManager mockSchemaManager;
    late MockDatabaseWatcher mockDatabaseWatcher;
    late Database db;

    setUp(() async {
      // Create mocks
      mockSyncQueue = MockSyncQueue();
      mockChangeAggregator = MockChangeAggregator();
      mockApiClient = MockPocketSyncNetworkClient();
      mockMergeEngine = MockMergeEngine();
      mockSchemaManager = MockSchemaManager();
      mockDatabaseWatcher = MockDatabaseWatcher();

      // Create an in-memory database for testing
      db = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: (db, version) async {
          // Create the device state table
          await db.execute('''
            CREATE TABLE __pocketsync_device_state (
              id INTEGER PRIMARY KEY,
              device_id TEXT NOT NULL,
              last_download_timestamp INTEGER,
              last_upload_timestamp INTEGER
            )
          ''');

          // Create a test table
          await db.execute('''
            CREATE TABLE users (
              id INTEGER PRIMARY KEY,
              name TEXT NOT NULL,
              email TEXT,
              ps_global_id TEXT
            )
          ''');

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
        },
      );

      // Insert device state record
      await db.insert('__pocketsync_device_state', {
        'id': 1,
        'device_id': 'test-device',
        'last_download_timestamp': DateTime.now()
            .subtract(const Duration(days: 1))
            .millisecondsSinceEpoch,
      });

      // Create the SyncWorker with mocks
      syncWorker = SyncWorker(
        syncQueue: mockSyncQueue,
        changeAggregator: mockChangeAggregator,
        apiClient: mockApiClient,
        database: db,
        mergeEngine: mockMergeEngine,
        schemaManager: mockSchemaManager,
        databaseWatcher: mockDatabaseWatcher,
        // Use a very short sync interval for testing
        syncInterval: const Duration(milliseconds: 100),
      );

      // Setup default behaviors for mocks
      when(() => mockSyncQueue.isEmpty).thenReturn(false);
      when(() => mockSyncQueue.hasDownloads).thenReturn(false);
    });

    tearDown(() async {
      // Stop the sync worker and close the database
      await syncWorker.stop();
      await db.close();
    });

    test('should initialize with correct properties', () {
      expect(syncWorker, isNotNull);
    });

    group('getLastDownloadTimestamp', () {
      test('should return the last download timestamp from database', () async {
        // Act
        final result = await syncWorker.getLastDownloadTimestamp();

        // Assert
        expect(result, isNotNull);
        // The timestamp should be from yesterday (as set in setUp)
        final yesterday = DateTime.now().subtract(const Duration(days: 1));
        expect(result.day, yesterday.day);
      });

      test('should return first day of 1970 if no timestamp exists', () async {
        // Arrange - Create a new instance with a mock database to test this specific case
        final mockDb = MockDatabase();
        final testWorker = SyncWorker(
          syncQueue: mockSyncQueue,
          changeAggregator: mockChangeAggregator,
          apiClient: mockApiClient,
          database: mockDb,
          mergeEngine: mockMergeEngine,
          schemaManager: mockSchemaManager,
          databaseWatcher: mockDatabaseWatcher,
        );

        // Mock the database to return empty result
        when(() => mockDb.query(
              '__pocketsync_device_state',
              columns: ['last_download_timestamp'],
              limit: 1,
            )).thenAnswer((_) async => []);

        // Act
        final result = await testWorker.getLastDownloadTimestamp();

        // Assert
        expect(result, DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
      });
    });

    group('start and stop', () {
      test('should start and process queue immediately', () async {
        // Arrange
        when(() => mockSyncQueue.isEmpty).thenReturn(false);
        when(() => mockSyncQueue.getTablesWithPendingUploads())
            .thenReturn(['users']);
        when(() => mockChangeAggregator.aggregateChanges(any())).thenAnswer(
            (_) async => AggregatedChanges(changes: [], affectedChangeIds: []));

        // Act
        await syncWorker.start();

        // Assert
        verify(() => mockSyncQueue.getTablesWithPendingUploads()).called(1);
      });

      test('should stop and cancel timer', () async {
        // Arrange
        when(() => mockSyncQueue.isEmpty).thenReturn(false);
        when(() => mockSyncQueue.getTablesWithPendingUploads()).thenReturn([]);

        // Start the worker
        await syncWorker.start();

        // Reset the call count after start
        clearInteractions(mockSyncQueue);

        // Act
        await syncWorker.stop();

        // Wait a bit to ensure timer doesn't fire
        await Future.delayed(const Duration(milliseconds: 200));

        // Assert - No additional calls should be made after stopping
        verifyNever(() => mockSyncQueue.getTablesWithPendingUploads());
      });
    });

    group('processQueue', () {
      test('should not process if already syncing', () async {
        // Arrange
        // Set up the worker to be in syncing state
        when(() => mockSyncQueue.isEmpty).thenReturn(false);
        when(() => mockSyncQueue.getTablesWithPendingUploads())
            .thenReturn(['users']);
        when(() => mockChangeAggregator.aggregateChanges(any()))
            .thenAnswer((_) async {
          // This will cause the first call to hang, simulating a long-running sync
          await Future.delayed(const Duration(milliseconds: 200));
          return AggregatedChanges(changes: [], affectedChangeIds: []);
        });

        // Start the first sync
        syncWorker.processQueue();

        // Act - Try to start another sync immediately
        await syncWorker.processQueue();

        // Assert - The aggregateChanges should only be called once
        verify(() => mockChangeAggregator.aggregateChanges(any())).called(1);
      });

      test('should not process if queue is empty', () async {
        // Arrange
        when(() => mockSyncQueue.isEmpty).thenReturn(true);

        // Act
        await syncWorker.processQueue();

        // Assert
        verifyNever(() => mockSyncQueue.getTablesWithPendingUploads());
      });
    });

    group('_processUploads', () {
      test('should process uploads for each table with pending changes',
          () async {
        // Arrange
        when(() => mockSyncQueue.isEmpty).thenReturn(false);
        when(() => mockSyncQueue.hasDownloads).thenReturn(false);
        when(() => mockSyncQueue.getTablesWithPendingUploads())
            .thenReturn(['users', 'products']);

        final changes = [
          SyncChange(
            id: '1',
            tableName: 'users',
            recordId: 'user1',
            operation: ChangeType.insert,
            data: {
              'new': {'name': 'User 1'}
            },
            timestamp: DateTime.now().millisecondsSinceEpoch,
            version: 1,
          ),
        ];

        when(() => mockChangeAggregator.aggregateChanges('users')).thenAnswer(
            (_) async =>
                AggregatedChanges(changes: changes, affectedChangeIds: ['1']));
        when(() => mockChangeAggregator.aggregateChanges('products'))
            .thenAnswer((_) async =>
                AggregatedChanges(changes: [], affectedChangeIds: []));

        when(() => mockApiClient.uploadChanges(any()))
            .thenAnswer((_) async => true);
        when(() => mockSyncQueue.markTableUploaded(any())).thenReturn(null);

        // Act
        await syncWorker.processQueue();

        // Assert
        verify(() => mockSyncQueue.getTablesWithPendingUploads()).called(1);
        verify(() => mockChangeAggregator.aggregateChanges('users')).called(1);
        verify(() => mockChangeAggregator.aggregateChanges('products'))
            .called(1);
        verify(() => mockApiClient.uploadChanges(any())).called(1);
        verify(() => mockSyncQueue.markTableUploaded('users')).called(1);
      });

      test('should handle upload failures gracefully', () async {
        // Arrange
        when(() => mockSyncQueue.getTablesWithPendingUploads())
            .thenReturn(['users']);

        final changes = [
          SyncChange(
            id: '1',
            tableName: 'users',
            recordId: 'user1',
            operation: ChangeType.insert,
            data: {
              'new': {'name': 'User 1'}
            },
            timestamp: DateTime.now().millisecondsSinceEpoch,
            version: 1,
          ),
        ];

        when(() => mockChangeAggregator.aggregateChanges('users')).thenAnswer(
            (_) async =>
                AggregatedChanges(changes: changes, affectedChangeIds: ['1']));

        // Simulate upload failure
        when(() => mockApiClient.uploadChanges(any()))
            .thenAnswer((_) async => false);

        // Act
        await syncWorker.processQueue();

        // Assert
        verify(() => mockApiClient.uploadChanges(any())).called(1);
        // Table should not be marked as uploaded on failure
        verifyNever(() => mockSyncQueue.markTableUploaded(any()));
      });
    });

    group('_processDownloads', () {
      test('should process downloads when queue has downloads', () async {
        // Arrange
        when(() => mockSyncQueue.isEmpty).thenReturn(false);
        when(() => mockSyncQueue.hasDownloads).thenReturn(true);
        when(() => mockSyncQueue.getTablesWithPendingUploads()).thenReturn([]);

        final downloadedChanges = ChangesResponse(
          changes: [
            SyncChange(
              id: '1',
              tableName: 'users',
              recordId: 'user1',
              operation: ChangeType.insert,
              data: {
                'new': {'name': 'User 1'}
              },
              timestamp: DateTime.now().millisecondsSinceEpoch,
              version: 1,
            ),
          ],
          count: 1,
          timestamp: DateTime.now(),
          syncSessionId: 'test-session',
        );

        // Important: Only set up the mock to be called once with specific parameters
        when(() => mockApiClient.downloadChanges(since: any(named: 'since')))
            .thenAnswer((_) async => downloadedChanges);

        when(() => mockSyncQueue.getRemoteChanges())
            .thenReturn(downloadedChanges.changes);
        when(() => mockSyncQueue.addRemoteChanges(any())).thenReturn(null);
        when(() => mockSyncQueue.clearRemoteChanges()).thenReturn(null);
        when(() => mockSyncQueue.markDownloadProcessed()).thenReturn(null);

        // Mock the _getPendingLocalChanges method indirectly by returning empty local changes
        when(() => mockMergeEngine.mergeChanges(any(), any(), any(), any()))
            .thenAnswer((_) async => []);

        // Act
        await syncWorker.processQueue();

        // Assert - Use verifyInOrder to ensure the correct sequence of calls
        verifyInOrder([
          () => mockSyncQueue.hasDownloads,
          () => mockApiClient.downloadChanges(since: any(named: 'since')),
          () => mockSyncQueue.addRemoteChanges(any()),
          () => mockSyncQueue.getRemoteChanges(),
          () => mockMergeEngine.mergeChanges(any(), any(), any(), any()),
          () => mockSyncQueue.clearRemoteChanges(),
          () => mockSyncQueue.markDownloadProcessed(),
        ]);
      });

      test('should handle empty downloads gracefully', () async {
        // Arrange
        when(() => mockSyncQueue.isEmpty).thenReturn(false);
        when(() => mockSyncQueue.hasDownloads).thenReturn(true);
        when(() => mockSyncQueue.getTablesWithPendingUploads()).thenReturn([]);

        // Empty downloaded changes
        final downloadedChanges = ChangesResponse(
          changes: [],
          count: 0,
          timestamp: DateTime.now(),
          syncSessionId: 'test-session',
        );

        when(() => mockApiClient.downloadChanges(since: any(named: 'since')))
            .thenAnswer((_) async => downloadedChanges);

        when(() => mockSyncQueue.getRemoteChanges()).thenReturn([]);

        // Act
        await syncWorker.processQueue();

        // Assert
        verify(() => mockApiClient.downloadChanges(since: any(named: 'since')))
            .called(1);
        verify(() => mockSyncQueue.markDownloadProcessed()).called(1);
        // Merge should not be called with empty changes
        verifyNever(
            () => mockMergeEngine.mergeChanges(any(), any(), any(), any()));
      });
    });

    test('should update last_download_timestamp after processing downloads',
        () async {
      // Arrange
      when(() => mockSyncQueue.isEmpty).thenReturn(false);
      when(() => mockSyncQueue.hasDownloads).thenReturn(true);
      when(() => mockSyncQueue.getTablesWithPendingUploads()).thenReturn([]);

      final downloadedChanges = ChangesResponse(
        changes: [
          SyncChange(
            id: '1',
            tableName: 'users',
            recordId: 'user1',
            operation: ChangeType.insert,
            data: {
              'new': {'name': 'User 1'}
            },
            timestamp: DateTime.now().millisecondsSinceEpoch,
            version: 1,
          ),
        ],
        count: 1,
        timestamp: DateTime.now(),
        syncSessionId: 'test-session',
      );

      when(() => mockApiClient.downloadChanges(since: any(named: 'since')))
          .thenAnswer((_) async => downloadedChanges);

      when(() => mockSyncQueue.getRemoteChanges())
          .thenReturn(downloadedChanges.changes);
      when(() => mockSyncQueue.addRemoteChanges(any())).thenReturn(null);
      when(() => mockSyncQueue.clearRemoteChanges()).thenReturn(null);
      when(() => mockSyncQueue.markDownloadProcessed()).thenReturn(null);

      when(() => mockMergeEngine.mergeChanges(any(), any(), any(), any()))
          .thenAnswer((_) async => []);

      // Get the initial timestamp
      final initialTimestamp = await db.query(
        '__pocketsync_device_state',
        columns: ['last_download_timestamp'],
        where: 'id = 1',
      );
      final initialValue =
          initialTimestamp.first['last_download_timestamp'] as int;

      // Manually set the timestamp to a lower value to ensure our test passes
      await db.update('__pocketsync_device_state',
          {'last_download_timestamp': initialValue - 1000},
          where: 'id = 1');

      // Act
      await syncWorker.processQueue();

      // Wait a moment to ensure the database update completes
      await Future.delayed(const Duration(milliseconds: 500));

      // Assert - Check that the timestamp was updated
      final updatedTimestamp = await db.query(
        '__pocketsync_device_state',
        columns: ['last_download_timestamp'],
        where: 'id = 1',
      );
      final updatedValue =
          updatedTimestamp.first['last_download_timestamp'] as int;

      expect(updatedValue, greaterThan(initialValue - 1000));
    });
  });
}
