import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pocketsync_flutter/pocketsync_flutter.dart';
import 'package:pocketsync_flutter/src/database/database_watcher.dart';
import 'package:pocketsync_flutter/src/engine/device_fingerprint_provider.dart';
import 'package:pocketsync_flutter/src/engine/pocket_sync_engine.dart';
import 'package:pocketsync_flutter/src/engine/pocket_sync_network_client.dart';
import 'package:pocketsync_flutter/src/engine/schema_manager.dart';
import 'package:pocketsync_flutter/src/models/sync_notification.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../database/database_test_utils.dart';

// Mock classes
class MockDatabase extends Mock implements Database {}

class MockSchemaManager extends Mock implements SchemaManager {}

class MockPocketSyncNetworkClient extends Mock
    implements PocketSyncNetworkClient {}

class MockDeviceFingerprintProvider extends Mock
    implements DeviceFingerprintProvider {}

class MockDatabaseWatcher extends Mock implements DatabaseWatcher {}

class MockDeviceInfoPlugin extends Mock implements DeviceInfoPlugin {}

// Fake implementations for mocking
class FakeDeviceInfoPlugin extends Fake implements DeviceInfoPlugin {}

class FakeDatabase extends Fake implements Database {}

void main() {
  // Initialize sqflite_ffi for testing
  setUpAll(() {
    DatabaseTestUtils.initializeSqfliteFfi();

    // Register fallback values for mocktail
    registerFallbackValue(FakeDeviceInfoPlugin());
    registerFallbackValue(FakeDatabase());
    registerFallbackValue(PocketSyncOptions(
        serverUrl: 'https://example.com',
        authToken: 'test-token',
        projectId: 'test-project'));
    registerFallbackValue({'deviceType': 'test'});
  });

  group('PocketSyncEngine', () {
    late PocketSyncEngine engine;
    late MockSchemaManager mockSchemaManager;
    late MockPocketSyncNetworkClient mockApiClient;
    late MockDeviceFingerprintProvider mockDeviceFingerprintProvider;
    late MockDatabaseWatcher mockDatabaseWatcher;
    late MockDeviceInfoPlugin mockDeviceInfo;
    late Database db;
    late PocketSyncOptions options;

    setUp(() async {
      // Create mocks
      mockSchemaManager = MockSchemaManager();
      mockApiClient = MockPocketSyncNetworkClient();
      mockDeviceFingerprintProvider = MockDeviceFingerprintProvider();
      mockDatabaseWatcher = MockDatabaseWatcher();
      mockDeviceInfo = MockDeviceInfoPlugin();

      // Create an in-memory database for testing
      db = await openDatabase(
        inMemoryDatabasePath,
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

          // Create PocketSync tables
          await db.execute('''
            CREATE TABLE __pocketsync_device_state (
              id INTEGER PRIMARY KEY,
              device_id TEXT NOT NULL,
              last_download_timestamp INTEGER,
              last_upload_timestamp INTEGER
            )
          ''');

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

      // Set up default mock behaviors
      when(() => mockDeviceFingerprintProvider.getDeviceFingerprint(any()))
          .thenAnswer((_) async => 'test-device-id');
      when(() => mockDeviceFingerprintProvider.getDeviceData(any()))
          .thenAnswer((_) async => {'deviceType': 'test', 'osVersion': '1.0'});
      when(() => mockSchemaManager.registerDevice(any(), any()))
          .thenAnswer((_) async {});
      when(() => mockSchemaManager.syncPreExistingData(any(), any()))
          .thenAnswer((_) async {});
      when(() => mockSchemaManager.cleanupOldSyncRecords(any(), any()))
          .thenAnswer((_) async => 0);
      when(() => mockApiClient.setupClient(any(), any())).thenReturn(null);
      when(() => mockApiClient.setDeviceInfos(any())).thenReturn(null);
      when(() => mockApiClient.dispose()).thenReturn(null);

      // Mock the stream for remote changes
      final mockStream = Stream<SyncNotification>.empty();
      when(() =>
              mockApiClient.listenForRemoteChanges(since: any(named: 'since')))
          .thenAnswer((_) => mockStream);

      // Create options
      options = PocketSyncOptions(
        authToken: 'test-auth-token',
        projectId: 'test-project-id',
        serverUrl: 'https://example.com/api',
        conflictResolutionStrategy: ConflictResolutionStrategy.lastWriteWins,
      );

      // Create the engine with mocks
      engine = PocketSyncEngine(
        db,
        options: options,
        schemaManager: mockSchemaManager,
        databaseWatcher: mockDatabaseWatcher,
        deviceInfo: mockDeviceInfo,
        apiClient: mockApiClient,
        deviceFingerprintProvider: mockDeviceFingerprintProvider,
      );
    });

    tearDown(() async {
      // Dispose the engine and close the database
      await engine.dispose();
      await db.close();
    });

    test('should initialize with correct properties', () {
      expect(engine.options, equals(options));
      expect(engine.database, equals(db));
      expect(engine.schemaManager, equals(mockSchemaManager));
      expect(engine.databaseWatcher, equals(mockDatabaseWatcher));
      expect(engine.deviceInfo, equals(mockDeviceInfo));
    });

    group('bootstrap', () {
      test('should initialize all components correctly', () async {
        // Act
        await engine.bootstrap();

        // Assert
        verify(() => mockDeviceFingerprintProvider.getDeviceFingerprint(any()))
            .called(1);
        verify(() => mockSchemaManager.registerDevice(any(), any())).called(1);
        verify(() => mockApiClient.setupClient(any(), any())).called(1);
        verify(() => mockApiClient.setDeviceInfos(any())).called(1);
        verify(() => mockSchemaManager.syncPreExistingData(any(), any()))
            .called(1);
      });

      test('should not initialize twice', () async {
        // Arrange
        await engine.bootstrap();

        // Reset the mock call counts
        clearInteractions(mockSchemaManager);

        // Act
        await engine.bootstrap();

        // Assert - Should not call these methods again
        verifyNever(() => mockSchemaManager.registerDevice(any(), any()));
      });
    });

    group('setUserId', () {
      test('should update user ID in API client', () {
        // Act
        engine.setUserId('test-user-123');

        // Assert
        verify(() => mockApiClient.setUserId('test-user-123')).called(1);
      });
    });
  });
}
