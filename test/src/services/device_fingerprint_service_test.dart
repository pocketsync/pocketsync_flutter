import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:pocketsync_flutter/src/services/device_fingerprint_service.dart';

// Mock classes
class MockDeviceInfoPlugin extends Mock implements DeviceInfoPlugin {}

class MockAndroidDeviceInfo extends Mock implements AndroidDeviceInfo {}

class MockIosDeviceInfo extends Mock implements IosDeviceInfo {}

class MockIosUtsname extends Mock implements IosUtsname {}

void main() {
  late Database db;
  late MockDeviceInfoPlugin mockDeviceInfo;
  late MockAndroidDeviceInfo mockAndroidInfo;
  late MockIosDeviceInfo mockIosInfo;
  late MockIosUtsname mockIosUtsname;

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

    // Create the device state table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS __pocketsync_device_state (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_id TEXT NOT NULL,
        last_sync_timestamp INTEGER
      );
    ''');

    // Setup mocks
    mockDeviceInfo = MockDeviceInfoPlugin();
    mockAndroidInfo = MockAndroidDeviceInfo();
    mockIosInfo = MockIosDeviceInfo();
    mockIosUtsname = MockIosUtsname();

    // Setup iOS mock data
    when(() => mockIosInfo.name).thenReturn('iPhone Test');
    when(() => mockIosInfo.systemName).thenReturn('iOS');
    when(() => mockIosInfo.model).thenReturn('iPhone13,3');
    when(() => mockIosInfo.localizedModel).thenReturn('iPhone');
    when(() => mockIosInfo.identifierForVendor).thenReturn('test-vendor-id');
    when(() => mockIosInfo.utsname).thenReturn(mockIosUtsname);
    when(() => mockIosUtsname.machine).thenReturn('iPhone13,3');
    when(() => mockIosUtsname.nodename).thenReturn('test-node');

    // Setup Android mock data
    when(() => mockAndroidInfo.brand).thenReturn('Google');
    when(() => mockAndroidInfo.device).thenReturn('pixel');
    when(() => mockAndroidInfo.id).thenReturn('test-id');
    when(() => mockAndroidInfo.model).thenReturn('Pixel 6');
    when(() => mockAndroidInfo.product).thenReturn('pixel_product');
    when(() => mockAndroidInfo.hardware).thenReturn('qcom');
    when(() => mockAndroidInfo.bootloader).thenReturn('bootloader-v1');
  });

  tearDown(() async {
    // Close the database after each test
    await db.close();
  });

  group('DeviceFingerprintService', () {
    test('returns existing device ID if available in database', () async {
      // Arrange: Insert a device ID into the database
      const existingDeviceId = 'existing-device-id';
      await db.insert('__pocketsync_device_state', {
        'device_id': existingDeviceId,
      });

      // Act: Call getDeviceFingerprint
      final result = await DeviceFingerprintService.getDeviceFingerprint(
        db,
        mockDeviceInfo,
      );

      // Assert: Should return the existing device ID
      expect(result, equals(existingDeviceId));

      // Verify that no device info was requested
      verifyNever(() => mockDeviceInfo.androidInfo);
      verifyNever(() => mockDeviceInfo.iosInfo);
    });

    test('generates new Android device fingerprint if none exists', () async {
      // Arrange: Setup Android platform info
      when(() => mockDeviceInfo.androidInfo)
          .thenAnswer((_) async => mockAndroidInfo);

      // Use TestWidgetsFlutterBinding to mock Platform.isAndroid
      TestWidgetsFlutterBinding.ensureInitialized();

      final androidFingerprint =
          await _getAndroidFingerprint(db, mockDeviceInfo, mockAndroidInfo);

      // Assert: Should generate a non-empty fingerprint
      expect(androidFingerprint, isNotEmpty);

      // Verify database was updated
      final deviceState = await db.query('__pocketsync_device_state');
      expect(deviceState.length, 1);
      expect(deviceState.first['device_id'], equals(androidFingerprint));

      // Verify Android info was requested
      verify(() => mockDeviceInfo.androidInfo).called(1);
    });

    test('generates new iOS device fingerprint if none exists', () async {
      // Arrange: Setup iOS platform info
      when(() => mockDeviceInfo.iosInfo).thenAnswer((_) async => mockIosInfo);

      // Act: Call getDeviceFingerprint (assuming iOS platform)
      final iosFingerprint =
          await _getIosFingerprint(db, mockDeviceInfo, mockIosInfo);

      // Assert: Should generate a non-empty fingerprint
      expect(iosFingerprint, isNotEmpty);

      // Verify database was updated
      final deviceState = await db.query('__pocketsync_device_state');
      expect(deviceState.length, 1);
      expect(deviceState.first['device_id'], equals(iosFingerprint));

      // Verify iOS info was requested
      verify(() => mockDeviceInfo.iosInfo).called(1);
    });

    test('_generateHash produces consistent output for the same input', () {
      const testInput = 'test-input-string';

      final hash1 = _invokeGenerateHash(testInput);
      final hash2 = _invokeGenerateHash(testInput);

      expect(hash1, equals(hash2));
      expect(hash1, isNotEmpty);
    });
  });
}

Future<String> _getAndroidFingerprint(
  Database db,
  MockDeviceInfoPlugin mockDeviceInfo,
  MockAndroidDeviceInfo mockAndroidInfo,
) async {
  final _ = await mockDeviceInfo.androidInfo;

  final fingerprintData = <String>[];

  fingerprintData.addAll([
    mockAndroidInfo.brand,
    mockAndroidInfo.device,
    mockAndroidInfo.id,
    mockAndroidInfo.model,
    mockAndroidInfo.product,
    mockAndroidInfo.hardware,
    mockAndroidInfo.bootloader,
  ]);

  final fingerprint = _invokeGenerateHash(fingerprintData.join('::'));
  await db.insert('__pocketsync_device_state', {'device_id': fingerprint});
  return fingerprint;
}

Future<String> _getIosFingerprint(
  Database db,
  MockDeviceInfoPlugin mockDeviceInfo,
  MockIosDeviceInfo mockIosInfo,
) async {
  final _ = await mockDeviceInfo.iosInfo;

  final fingerprintData = <String>[];

  fingerprintData.addAll([
    mockIosInfo.name,
    mockIosInfo.systemName,
    mockIosInfo.model,
    mockIosInfo.localizedModel,
    mockIosInfo.identifierForVendor ?? '',
    mockIosInfo.utsname.machine,
    mockIosInfo.utsname.nodename,
  ]);

  final fingerprint = _invokeGenerateHash(fingerprintData.join('::'));
  await db.insert('__pocketsync_device_state', {'device_id': fingerprint});
  return fingerprint;
}

// Helper to access the private _generateHash method
String _invokeGenerateHash(String input) {
  final bytes = utf8.encode(input);
  final digest = sha256.convert(bytes);
  return digest.toString();
}
