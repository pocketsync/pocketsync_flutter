import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pocketsync_flutter/pocketsync_flutter.dart';
import 'package:pocketsync_flutter/src/services/connectivity_manager.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../fixtures/pocket_sync_options_fixtures.dart';

class _MockPocketSyncDatabase extends Mock implements PocketSyncDatabase {}

class _MockConnectivityManager extends Mock implements ConnectivityManager {}

class _MockDatabase extends Mock implements Database {}

void main() {
  late PocketSync pocketSync;
  late _MockPocketSyncDatabase mockPocketsyncDatabase;
  late _MockConnectivityManager mockConnectivityManager;
  final mockDatabase = _MockDatabase();

  const testDbPath = 'test.db';

  setUp(() {
    registerFallbackValue(DatabaseOptions(onCreate: (db, version) {}));

    mockPocketsyncDatabase = _MockPocketSyncDatabase();
    mockConnectivityManager = _MockConnectivityManager();

    pocketSync = PocketSync.instance;

    // Setup default responses
    when(() => mockPocketsyncDatabase.initialize(
          dbPath: any(named: 'dbPath'),
          options: any(named: 'options'),
        )).thenAnswer((_) async => mockDatabase);

    when(() => mockConnectivityManager.isConnected).thenReturn(true);
  });

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('initialization', () {
    test('should initialize successfully with valid options', () async {
      final options = PocketSyncOptionsFixtures.defaultOptions;
      final databaseOptions = DatabaseOptions(onCreate: (db, version) {});

      await pocketSync.initialize(
        dbPath: testDbPath,
        options: options,
        databaseOptions: databaseOptions,
      );

      expect(pocketSync.database, isNotNull);
    });
  });
}
