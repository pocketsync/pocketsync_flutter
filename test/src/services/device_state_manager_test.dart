import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pocketsync_flutter/src/services/device_state_manager.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // Create a new in-memory database for each test
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1),
    );
  });

  tearDown(() async {
    // Close the database after each test
    await db.close();
  });

  group('DeviceStateManager', () {
    test('createDeviceStateTable creates table with correct schema', () async {
      // Create the table
      await DeviceStateManager.createDeviceStateTable(db);

      // Verify table structure
      final tableInfo =
          await db.rawQuery('PRAGMA table_info(__pocketsync_device_state)');

      expect(tableInfo.length, 3); // Should have 3 columns

      // Verify column names and types
      expect(tableInfo[0]['name'], 'id');
      expect(tableInfo[0]['type'], 'INTEGER');
      expect(tableInfo[1]['name'], 'device_id');
      expect(tableInfo[1]['type'], 'TEXT');
      expect(tableInfo[2]['name'], 'last_sync_timestamp');
      expect(tableInfo[2]['type'], 'INTEGER');
    });

    test('setupDeviceInfo creates new device entry if none exists', () async {
      await DeviceStateManager.setupDeviceInfo(db);

      final result = await db.query('__pocketsync_device_state');
      expect(result.length, 1);
      expect(result.first['device_id'], isNotNull);
      expect(result.first['last_sync_timestamp'], isNull);
    });

    test('setupDeviceInfo does not create duplicate entry', () async {
      // Setup device info twice
      await DeviceStateManager.setupDeviceInfo(db);
      await DeviceStateManager.setupDeviceInfo(db);

      final result = await db.query('__pocketsync_device_state');
      expect(result.length, 1); // Should still only have one entry
    });

    test('updateLastSyncTimestamp updates timestamp correctly', () async {
      // Setup initial device state
      await DeviceStateManager.setupDeviceInfo(db);

      final timestamp = DateTime(2023, 1, 1, 12, 0);
      await DeviceStateManager.updateLastSyncTimestamp(db, timestamp);

      final result = await db.query('__pocketsync_device_state');
      expect(result.first['last_sync_timestamp'],
          timestamp.millisecondsSinceEpoch);
    });

    test('getDeviceState returns null when no state exists', () async {
      await DeviceStateManager.createDeviceStateTable(db);

      final state = await DeviceStateManager.getDeviceState(db);
      expect(state, isNull);
    });

    test('getDeviceState returns correct state', () async {
      // Setup device info
      await DeviceStateManager.setupDeviceInfo(db);

      final timestamp = DateTime(2023, 1, 1, 12, 0);
      await DeviceStateManager.updateLastSyncTimestamp(db, timestamp);

      final state = await DeviceStateManager.getDeviceState(db);

      expect(state, isNotNull);
      expect(state!['device_id'], isNotNull);
      expect(state['last_sync_timestamp'], timestamp.millisecondsSinceEpoch);
    });
  });
}
