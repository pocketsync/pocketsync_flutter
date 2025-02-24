import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

class DeviceFingerprintService {
  const DeviceFingerprintService();

  static Future<String> getDeviceFingerprint(
    Database database,
    DeviceInfoPlugin deviceInfo,
  ) async {
    final deviceState =
        await database.query('__pocketsync_device_state', limit: 1);

    if (deviceState.isNotEmpty) {
      return deviceState.first['device_id'] as String;
    }

    final fingerprintData = <String>[];

    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      fingerprintData.addAll([
        androidInfo.brand,
        androidInfo.device,
        androidInfo.id,
        androidInfo.model,
        androidInfo.product,
        androidInfo.hardware,
        androidInfo.bootloader,
      ]);
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      fingerprintData.addAll([
        iosInfo.name,
        iosInfo.systemName,
        iosInfo.model,
        iosInfo.localizedModel,
        iosInfo.identifierForVendor ?? '',
        iosInfo.utsname.machine,
        iosInfo.utsname.nodename,
      ]);
    }

    final fingerprint = _generateHash(fingerprintData.join('::'));
    await database.update(
      '__pocketsync_device_state',
      {'device_id': fingerprint},
      where: '1=1',
    );
    return fingerprint;
  }

  static String _generateHash(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
