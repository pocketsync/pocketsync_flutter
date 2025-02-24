import 'package:device_info_plus/device_info_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:pocketsync_flutter/src/services/device_fingerprint_service.dart';

class DeviceStateManager {
  static const String _tableName = '__pocketsync_device_state';

  /// Creates the device state table if it doesn't exist
  static Future<void> createDeviceStateTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableName (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_id TEXT NOT NULL,
        last_sync_timestamp INTEGER
      );
    ''');
  }

  /// Sets up device information in the database
  static Future<void> setupDeviceInfo(Database db) async {
    // Create table if it doesn't exist
    await createDeviceStateTable(db);

    // Check if device info exists
    final deviceState = await db.query(_tableName, limit: 1);
    if (deviceState.isEmpty) {
      // Generate a new device ID if none exists
      final deviceId = await DeviceFingerprintService.getDeviceFingerprint(
        db,
        DeviceInfoPlugin(),
      );
      await db.insert(_tableName, {
        'device_id': deviceId,
        'last_sync_timestamp': null,
      });
    }
  }

  /// Updates the last sync timestamp
  static Future<void> updateLastSyncTimestamp(
      Database db, DateTime timestamp) async {
    await db.update(
      _tableName,
      {'last_sync_timestamp': timestamp.millisecondsSinceEpoch},
      where: '1=1',
    );
  }

  /// Gets the current device state
  static Future<Map<String, dynamic>?> getDeviceState(Database db) async {
    final result = await db.query(_tableName, limit: 1);
    return result.isNotEmpty ? result.first : null;
  }
}
