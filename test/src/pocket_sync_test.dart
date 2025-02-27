import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pocketsync_flutter/pocketsync_flutter.dart';
import 'package:pocketsync_flutter/src/services/connectivity_manager.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../fixtures/pocket_sync_options_fixtures.dart';

class _MockConnectivityManager extends Mock implements ConnectivityManager {}

void main() {
  late PocketSync pocketSync;
  late _MockConnectivityManager mockConnectivityManager;

  // Use in-memory database path instead of file path
  const testDbPath = inMemoryDatabasePath;

  setUp(() {
    mockConnectivityManager = _MockConnectivityManager();
    pocketSync = PocketSync.instance;

    // Setup connectivity manager mock
    when(() => mockConnectivityManager.isConnected).thenReturn(true);
  });

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    // Clean up after each test
    try {
      await databaseFactory.deleteDatabase(testDbPath);
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

      await pocketSync.initialize(
        dbPath: testDbPath,
        options: options,
        databaseOptions: databaseOptions,
      );

      expect(pocketSync.database, isNotNull);
      
      // Verify database is properly initialized by executing a query
      final tables = await pocketSync.database.query('sqlite_master', 
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
}
