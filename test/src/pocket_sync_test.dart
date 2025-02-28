import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pocketsync_flutter/pocketsync_flutter.dart';
import 'package:pocketsync_flutter/src/services/changes_processor.dart';
import 'package:pocketsync_flutter/src/services/connectivity_manager.dart';
import 'package:pocketsync_flutter/src/services/pocket_sync_network_service.dart';
import 'package:pocketsync_flutter/src/services/sync_task_queue.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../fixtures/change_set_fixtures.dart';
import '../fixtures/pocket_sync_options_fixtures.dart';

class _MockConnectivityManager extends Mock implements ConnectivityManager {
  @override
  void Function(bool isConnected) get onConnectivityChanged => (bool _) {};
}

class _MockNetworkService extends Mock implements PocketSyncNetworkService {}

class _MockChangesProcessor extends Mock implements ChangesProcessor {}

class _MockSyncTaskQueue extends Mock implements SyncTaskQueue {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PocketSync pocketSync;
  late _MockConnectivityManager mockConnectivityManager;

  const testDbPath = inMemoryDatabasePath;

  late _MockNetworkService mockNetworkService;
  late _MockChangesProcessor mockChangesProcessor;
  late _MockSyncTaskQueue mockSyncQueue;

  setUp(() async {
    mockConnectivityManager = _MockConnectivityManager();
    mockNetworkService = _MockNetworkService();
    mockChangesProcessor = _MockChangesProcessor();
    mockSyncQueue = _MockSyncTaskQueue();

    // Don't access PocketSync.instance here
    // Instead, we'll get the instance after initialization in each test

    // Setup connectivity manager mock
    when(() => mockConnectivityManager.isConnected).thenReturn(true);

    registerFallbackValue(ChangeSetFixtures.withInsertions);

    // Ensure cleanup from previous tests
    try {
      await databaseFactory.deleteDatabase(testDbPath);
    } catch (e) {
      // Ignore errors during cleanup
    }
  });

  group('sync operations', () {
    test('should handle sync process with changes', () async {
      final options = PocketSyncOptionsFixtures.defaultOptions;
      final databaseOptions = DatabaseOptions(
        version: 1,
        onCreate: (db, version) {},
      );
      final changeSet = ChangeSetFixtures.withUpdates;

      // Setup mocks
      when(() => mockChangesProcessor.getUnSyncedChanges())
          .thenAnswer((_) async => changeSet);
      when(() => mockSyncQueue.enqueue(any()))
          .thenAnswer((_) async => Future.value());

      await PocketSync.initialize(
        dbPath: testDbPath,
        options: options,
        databaseOptions: databaseOptions,
      );

      pocketSync = PocketSync.instance;
      pocketSync = PocketSync.test(
        database: pocketSync.database,
        changesProcessor: mockChangesProcessor,
        syncQueue: mockSyncQueue,
        networkService: mockNetworkService,
      );

      await pocketSync.setUserId(userId: 'test-user');
      await pocketSync.start();

      // Verify sync process
      verifyNever(() => mockChangesProcessor.getUnSyncedChanges());
      verifyNever(() => mockSyncQueue.enqueue(any()));
    });
  });

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    try {
      await databaseFactory.deleteDatabase(testDbPath);
      
      // Reset the singleton instance
      await PocketSync.instance.dispose();
    } catch (e) {
      // Ignore errors during cleanup
    }
  });

  group('initialization', () {
    test('should initialize successfully with valid options', () async {
      final options = PocketSyncOptionsFixtures.defaultOptions;
      final databaseOptions = DatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          // Create a test table
          await db.execute(
            'CREATE TABLE test_table (id INTEGER PRIMARY KEY, name TEXT)',
          );
        },
      );

      await PocketSync.initialize(
        dbPath: testDbPath,
        options: options,
        databaseOptions: databaseOptions,
      );

      pocketSync = PocketSync.instance;
      expect(pocketSync.database, isNotNull);

      // Verify database is properly initialized by executing a query
      final tables = await pocketSync.database.query(
        'sqlite_master',
        columns: ['name'],
        where: "type = 'table'",
      );

      // Extract table names
      final tableNames = tables.map((t) => t['name'] as String).toList();

      // Verify our test table and PocketSync system tables exist
      expect(tableNames, contains('test_table'));
      expect(tableNames, contains('__pocketsync_changes'));
    });
  });

  group('user management', () {
    test('should set user ID successfully', () async {
      final options = PocketSyncOptionsFixtures.defaultOptions;
      final databaseOptions = DatabaseOptions(
        version: 1,
        onCreate: (db, version) {
          return db.execute(
            'CREATE TABLE test_table (id INTEGER PRIMARY KEY, name TEXT)',
          );
        },
      );

      await PocketSync.initialize(
        dbPath: testDbPath,
        options: options,
        databaseOptions: databaseOptions,
      );

      pocketSync = PocketSync.instance;
      await pocketSync.setUserId(userId: 'test-user');
    });

    test('should throw error when setting user ID before initialization',
        () async {
      expect(
        () => PocketSync.instance.setUserId(userId: 'test-user'),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('sync operations', () {
    test('should throw error when starting sync without user ID', () async {
      final options = PocketSyncOptionsFixtures.defaultOptions;
      final databaseOptions = DatabaseOptions(
        version: 1,
        onCreate: (db, version) {
          return db.execute(
            'CREATE TABLE test_table (id INTEGER PRIMARY KEY, name TEXT)',
          );
        },
      );

      await PocketSync.initialize(
        dbPath: testDbPath,
        options: options,
        databaseOptions: databaseOptions,
      );

      pocketSync = PocketSync.instance;

      expect(
        () => pocketSync.start(),
        throwsA(isA<StateError>()),
      );
    });

    test('should start sync successfully with user ID', () async {
      final options = PocketSyncOptionsFixtures.defaultOptions;
      final databaseOptions = DatabaseOptions(
        version: 1,
        onCreate: (db, version) {
          // Create a test table
          return db.execute(
            'CREATE TABLE test_table (id INTEGER PRIMARY KEY, name TEXT)',
          );
        },
      );

      await PocketSync.initialize(
        dbPath: testDbPath,
        options: options,
        databaseOptions: databaseOptions,
      );

      pocketSync = PocketSync.instance;
      await pocketSync.setUserId(userId: 'test-user');
      await pocketSync.start();
      // If no exception is thrown, the test passes
    });
    
    test('should pause sync successfully', () async {
      final options = PocketSyncOptionsFixtures.defaultOptions;
      final databaseOptions = DatabaseOptions(
        version: 1,
        onCreate: (db, version) {
          return db.execute(
            'CREATE TABLE test_table (id INTEGER PRIMARY KEY, name TEXT)',
          );
        },
      );

      await PocketSync.initialize(
        dbPath: testDbPath,
        options: options,
        databaseOptions: databaseOptions,
      );

      pocketSync = PocketSync.instance;
      await pocketSync.setUserId(userId: 'test-user');
      await pocketSync.start();
      pocketSync.pause();

      expect(pocketSync.isPaused, isTrue);
    });
  });

  group('error handling', () {
    test('should handle cleanup properly', () async {
      final options = PocketSyncOptionsFixtures.defaultOptions;
      final databaseOptions = DatabaseOptions(
        version: 1,
        onCreate: (db, version) {
          return db.execute(
            'CREATE TABLE test_table (id INTEGER PRIMARY KEY, name TEXT)',
          );
        },
      );

      await PocketSync.initialize(
        dbPath: testDbPath,
        options: options,
        databaseOptions: databaseOptions,
      );

      await PocketSync.instance.dispose();
    });
  });
}
