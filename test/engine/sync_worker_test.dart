import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pocketsync_flutter/src/database/database_watcher.dart';
import 'package:pocketsync_flutter/src/engine/change_aggregator.dart';
import 'package:pocketsync_flutter/src/engine/connectivity_monitor.dart';
import 'package:pocketsync_flutter/src/engine/merge_engine.dart';
import 'package:pocketsync_flutter/src/engine/pocket_sync_network_client.dart';
import 'package:pocketsync_flutter/src/engine/schema_manager.dart';
import 'package:pocketsync_flutter/src/engine/sync_batch_processor.dart';
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

class MockConnectivityMonitor extends Mock implements ConnectivityMonitor {}

class MockSyncBatchProcessor extends Mock implements SyncBatchProcessor {}

void main() {
  // Initialize sqflite_ffi for testing
  setUpAll(() {
    DatabaseTestUtils.initializeSqfliteFfi();

    // Register fallback values for mocktail
    registerFallbackValue(DateTime(2025));
    registerFallbackValue(<SyncChange>[]);
    registerFallbackValue(<String, dynamic>{});
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

      // Setup connection stream for network client
      final connectionStreamController = StreamController<bool>.broadcast();
      when(() => mockApiClient.connectionStream)
          .thenAnswer((_) => connectionStreamController.stream);
      when(() => mockApiClient.isServerReachable()).thenReturn(true);
      when(() => mockApiClient.isConnected).thenReturn(true);

      // Setup default behaviors for mocks
      when(() => mockSyncQueue.isEmpty).thenReturn(false);
      when(() => mockSyncQueue.hasDownloads).thenReturn(false);
      when(() => mockChangeAggregator.aggregateChanges(any())).thenAnswer(
          (_) async => AggregatedChanges(changes: [], affectedChangeIds: []));

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
        'last_download_timestamp': null,
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
        connectivityMonitor: ConnectivityMonitor(
          networkClient: mockApiClient,
          onConnected: () {},
        ),
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
        // Set a specific timestamp for testing
        final testTimestamp = 1620000000000; // May 3, 2021
        await db.update(
          '__pocketsync_device_state',
          {'last_download_timestamp': testTimestamp},
          where: 'id = 1',
        );

        // Act
        final result = await syncWorker.getLastDownloadTimestamp();

        // Assert
        expect(result, isNotNull);
        expect(result.millisecondsSinceEpoch, testTimestamp);
      });

      test('should return first day of 1970 if no timestamp exists', () async {
        final testWorker = SyncWorker(
          syncQueue: mockSyncQueue,
          changeAggregator: mockChangeAggregator,
          apiClient: mockApiClient,
          database: db,
          mergeEngine: mockMergeEngine,
          schemaManager: mockSchemaManager,
          databaseWatcher: mockDatabaseWatcher,
        );

        // Act
        final result = await testWorker.getLastDownloadTimestamp();

        // Assert
        expect(result, DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
      });
    });

    group('connectivity-aware syncing', () {
      late StreamController<bool> connectionStreamController;
      late MockConnectivityMonitor mockConnectivityMonitor;
      late SyncWorker syncWorkerWithMocks;
      late MockSyncBatchProcessor mockBatchProcessor;

      setUp(() async {
        // Create mocks for connectivity testing
        mockConnectivityMonitor = MockConnectivityMonitor();
        mockBatchProcessor = MockSyncBatchProcessor();
        connectionStreamController = StreamController<bool>.broadcast();

        // Setup default behaviors
        when(() => mockConnectivityMonitor.isConnected).thenReturn(true);
        when(() => mockBatchProcessor.processUnsyncedChanges(any()))
            .thenAnswer((_) async => {'users': true});
        when(() => mockBatchProcessor.markChangesAsSynced(any(), any()))
            .thenAnswer((_) async {});

        // Setup SyncQueue behavior
        when(() => mockSyncQueue.getTablesWithPendingUploads())
            .thenReturn(['users']);

        // Create SyncWorker with mocked dependencies for connectivity testing
        syncWorkerWithMocks = SyncWorker(
          syncQueue: mockSyncQueue,
          changeAggregator: mockChangeAggregator,
          apiClient: mockApiClient,
          database: db,
          mergeEngine: mockMergeEngine,
          schemaManager: mockSchemaManager,
          databaseWatcher: mockDatabaseWatcher,
          syncInterval: const Duration(milliseconds: 100),
        );

        // Replace the internal connectivity monitor and batch processor with mocks
        syncWorkerWithMocks.testSetConnectivityMonitor(mockConnectivityMonitor);
        syncWorkerWithMocks.testSetBatchProcessor(mockBatchProcessor);
      });

      tearDown(() {
        connectionStreamController.close();
      });

      test('should not process uploads when offline', () async {
        // Arrange
        when(() => mockConnectivityMonitor.isConnected).thenReturn(false);

        // Act
        await syncWorkerWithMocks.processQueue();

        // Assert
        verifyNever(() => mockBatchProcessor.processUnsyncedChanges(any()));
      });

      test('should process uploads when online', () async {
        // Arrange
        when(() => mockConnectivityMonitor.isConnected).thenReturn(true);

        // Act
        await syncWorkerWithMocks.processQueue();

        // Assert
        verify(() => mockBatchProcessor.processUnsyncedChanges(['users']))
            .called(1);
      });

      test('should process queue when connectivity is restored', () async {
        // Arrange
        when(() => mockConnectivityMonitor.isConnected).thenReturn(true);

        // Act - simulate connectivity restored callback
        await syncWorkerWithMocks.testOnConnectivityRestored();

        // Assert
        verify(() => mockBatchProcessor.processUnsyncedChanges(['users']))
            .called(1);
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

        // Allow time for the queue to be processed
        await Future.delayed(const Duration(milliseconds: 50));

        // Assert - getTablesWithPendingUploads is called during initialization and processing
        verify(() => mockSyncQueue.getTablesWithPendingUploads())
            .called(greaterThanOrEqualTo(1));
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
        // Create a separate mock setup for this test
        final mockConnectivityMonitor = MockConnectivityMonitor();
        when(() => mockConnectivityMonitor.isConnected).thenReturn(true);

        // Create a test worker with our mocks
        final testWorker = SyncWorker(
          syncQueue: mockSyncQueue,
          changeAggregator: mockChangeAggregator,
          apiClient: mockApiClient,
          database: db,
          mergeEngine: mockMergeEngine,
          schemaManager: mockSchemaManager,
          databaseWatcher: mockDatabaseWatcher,
        );
        testWorker.testSetConnectivityMonitor(mockConnectivityMonitor);

        // Arrange
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
        testWorker.processQueue();

        // Act - Try to start another sync immediately
        await testWorker.processQueue();

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
        // Create a test worker with controlled connectivity
        final mockConnectivityMonitor = MockConnectivityMonitor();
        when(() => mockConnectivityMonitor.isConnected).thenReturn(true);

        final testWorker = SyncWorker(
          syncQueue: mockSyncQueue,
          changeAggregator: mockChangeAggregator,
          apiClient: mockApiClient,
          database: db,
          mergeEngine: mockMergeEngine,
          schemaManager: mockSchemaManager,
          databaseWatcher: mockDatabaseWatcher,
        );
        testWorker.testSetConnectivityMonitor(mockConnectivityMonitor);

        // Arrange
        when(() => mockSyncQueue.isEmpty).thenReturn(false);
        when(() => mockSyncQueue.hasDownloads).thenReturn(false);

        when(() => mockSyncQueue.getTablesWithPendingUploads())
            .thenReturn(['users', 'products']);

        registerFallbackValue(['users', 'products']);
        when(() => mockSyncQueue.markTableUploaded(any())).thenReturn(null);

        final userChanges = [
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

        // Set up mocks with specific responses for each call
        when(() => mockChangeAggregator.aggregateChanges('users')).thenAnswer(
            (_) async => AggregatedChanges(
                changes: userChanges, affectedChangeIds: ['1']));
        when(() => mockChangeAggregator.aggregateChanges('products'))
            .thenAnswer((_) async =>
                AggregatedChanges(changes: [], affectedChangeIds: []));
        when(() => mockApiClient.uploadChanges(any()))
            .thenAnswer((_) async => true);

        // Act
        await testWorker.processQueue();

        // Assert
        verify(() => mockSyncQueue.getTablesWithPendingUploads())
            .called(greaterThanOrEqualTo(1));
        verify(() => mockChangeAggregator.aggregateChanges('users'))
            .called(greaterThanOrEqualTo(1));
        verify(() => mockChangeAggregator.aggregateChanges('products'))
            .called(greaterThanOrEqualTo(1));
        verify(() => mockSyncQueue.markTableUploaded('users')).called(1);
        verify(() => mockSyncQueue.markTableUploaded('products')).called(1);
      });

      test('should handle upload failures gracefully', () async {
        // Create a test worker with controlled connectivity
        final mockConnectivityMonitor = MockConnectivityMonitor();
        when(() => mockConnectivityMonitor.isConnected).thenReturn(true);

        final testWorker = SyncWorker(
          syncQueue: mockSyncQueue,
          changeAggregator: mockChangeAggregator,
          apiClient: mockApiClient,
          database: db,
          mergeEngine: mockMergeEngine,
          schemaManager: mockSchemaManager,
          databaseWatcher: mockDatabaseWatcher,
        );
        testWorker.testSetConnectivityMonitor(mockConnectivityMonitor);

        // Arrange
        when(() => mockSyncQueue.isEmpty).thenReturn(false);
        when(() => mockSyncQueue.hasDownloads).thenReturn(false);
        when(() => mockSyncQueue.getTablesWithPendingUploads())
            .thenReturn(['users']);

        final failChanges = [
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
            (_) async => AggregatedChanges(
                changes: failChanges, affectedChangeIds: ['1']));

        // Simulate upload failure
        when(() => mockApiClient.uploadChanges(any()))
            .thenAnswer((_) async => false);

        // Act
        await testWorker.processQueue();

        // Assert
        verify(() => mockApiClient.uploadChanges(any())).called(1);
        verifyNever(() => mockSyncQueue.markTableUploaded(any()));
      });
    });

    group('_processDownloads', () {
      test('should process downloads when queue has downloads', () async {
        // Create a test worker with controlled connectivity
        final mockConnectivityMonitor = MockConnectivityMonitor();
        when(() => mockConnectivityMonitor.isConnected).thenReturn(true);

        final testWorker = SyncWorker(
          syncQueue: mockSyncQueue,
          changeAggregator: mockChangeAggregator,
          apiClient: mockApiClient,
          database: db,
          mergeEngine: mockMergeEngine,
          schemaManager: mockSchemaManager,
          databaseWatcher: mockDatabaseWatcher,
        );
        testWorker.testSetConnectivityMonitor(mockConnectivityMonitor);

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
        await testWorker.processQueue();

        // Assert - Verify the correct calls were made
        verify(() => mockSyncQueue.hasDownloads)
            .called(greaterThanOrEqualTo(1));
        verify(() => mockApiClient.downloadChanges(since: any(named: 'since')))
            .called(1);
        verify(() => mockSyncQueue.addRemoteChanges(any())).called(1);
        verify(() => mockSyncQueue.getRemoteChanges()).called(1);
        verify(() => mockSyncQueue.clearRemoteChanges()).called(1);
        verify(() => mockSyncQueue.markDownloadProcessed()).called(1);
      });

      test('should handle empty downloads gracefully', () async {
        // Create a test worker with controlled connectivity
        final mockConnectivityMonitor = MockConnectivityMonitor();
        when(() => mockConnectivityMonitor.isConnected).thenReturn(true);

        final testWorker = SyncWorker(
          syncQueue: mockSyncQueue,
          changeAggregator: mockChangeAggregator,
          apiClient: mockApiClient,
          database: db,
          mergeEngine: mockMergeEngine,
          schemaManager: mockSchemaManager,
          databaseWatcher: mockDatabaseWatcher,
        );
        testWorker.testSetConnectivityMonitor(mockConnectivityMonitor);

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
        when(() => mockSyncQueue.addRemoteChanges(any())).thenReturn(null);
        when(() => mockSyncQueue.clearRemoteChanges()).thenReturn(null);
        when(() => mockSyncQueue.markDownloadProcessed()).thenReturn(null);

        // Get the initial timestamp
        final initialTimestamp = await db.query(
          '__pocketsync_device_state',
          columns: ['last_download_timestamp'],
          where: 'id = 1',
        );
        final initialValue =
            initialTimestamp.first['last_download_timestamp'] as int?;

        // Manually set the timestamp to a lower value to ensure our test passes
        await db.update('__pocketsync_device_state',
            {'last_download_timestamp': (initialValue ?? 0) - 1000},
            where: 'id = 1');

        // Act
        await testWorker.processQueue();

        // Assert - Check that the timestamp was updated
        final updatedTimestamp = await db.query(
          '__pocketsync_device_state',
          columns: ['last_download_timestamp'],
          where: 'id = 1',
        );
        final updatedValue =
            updatedTimestamp.first['last_download_timestamp'] as int?;

        // Verify merge was not called with empty changes
        verifyNever(
            () => mockMergeEngine.mergeChanges(any(), any(), any(), any()));
        verify(() => mockSyncQueue.markDownloadProcessed()).called(1);

        // Verify timestamp was updated
        expect(updatedValue, greaterThan((initialValue ?? 0) - 1000));
      });

      test('should update last_download_timestamp after processing downloads',
          () async {
        // Create a test worker with controlled connectivity
        final mockConnectivityMonitor = MockConnectivityMonitor();
        when(() => mockConnectivityMonitor.isConnected).thenReturn(true);

        final testWorker = SyncWorker(
          syncQueue: mockSyncQueue,
          changeAggregator: mockChangeAggregator,
          apiClient: mockApiClient,
          database: db,
          mergeEngine: mockMergeEngine,
          schemaManager: mockSchemaManager,
          databaseWatcher: mockDatabaseWatcher,
        );
        testWorker.testSetConnectivityMonitor(mockConnectivityMonitor);

        // Arrange
        when(() => mockSyncQueue.isEmpty).thenReturn(false);
        when(() => mockSyncQueue.hasDownloads).thenReturn(true);
        when(() => mockSyncQueue.getTablesWithPendingUploads()).thenReturn([]);

        // Get current timestamp
        final initialTimestamp = await db.query(
          '__pocketsync_device_state',
          columns: ['last_download_timestamp'],
          where: 'id = 1',
        );
        final initialValue =
            initialTimestamp.first['last_download_timestamp'] as int?;

        // Set timestamp to a known value
        final testTimestamp = (initialValue ?? 0) - 5000;
        await db.update(
          '__pocketsync_device_state',
          {'last_download_timestamp': testTimestamp},
          where: 'id = 1',
        );

        // Mock the response with a newer timestamp
        final serverTimestamp = DateTime.now().millisecondsSinceEpoch;
        final downloadedChanges = ChangesResponse(
          changes: [],
          count: 0,
          timestamp: DateTime.fromMillisecondsSinceEpoch(serverTimestamp),
          syncSessionId: 'test-session',
        );

        when(() => mockApiClient.downloadChanges(since: any(named: 'since')))
            .thenAnswer((_) async => downloadedChanges);
        when(() => mockSyncQueue.getRemoteChanges()).thenReturn([]);

        // Act
        await testWorker.processQueue();

        // Assert - Verify timestamp was updated
        final updatedTimestamp = await db.query(
          '__pocketsync_device_state',
          columns: ['last_download_timestamp'],
          where: 'id = 1',
        );
        final updatedValue =
            updatedTimestamp.first['last_download_timestamp'] as int?;

        // The updated timestamp should be greater than our test value
        expect(updatedValue, greaterThan(testTimestamp));

        // Verify the correct methods were called
        verify(() => mockSyncQueue.hasDownloads)
            .called(greaterThanOrEqualTo(1));
        verify(() => mockApiClient.downloadChanges(since: any(named: 'since')))
            .called(1);
        verify(() => mockSyncQueue.markDownloadProcessed()).called(1);
      });
    });
  });
}
