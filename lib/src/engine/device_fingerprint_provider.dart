import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class DeviceFingerprintProvider {
  const DeviceFingerprintProvider();

  Future<String> getDeviceFingerprint(DeviceInfoPlugin deviceInfo) async {
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
    } else if (Platform.isMacOS || Platform.isWindows) {
      // TODO: add device mac address
    } else {
      throw UnsupportedError('Unsupported platform');
    }

    return _generateHash(fingerprintData.join('::'));
  }

  static String _generateHash(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<Map<String, dynamic>> getDeviceData(
      DeviceInfoPlugin deviceInfo) async {
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      return {
        'brand': androidInfo.brand,
        'device': androidInfo.device,
        'id': androidInfo.id,
        'model': androidInfo.model,
        'product': androidInfo.product,
        'hardware': androidInfo.hardware,
        'bootloader': androidInfo.bootloader,
      };
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      return {
        'name': iosInfo.name,
        'systemName': iosInfo.systemName,
        'model': iosInfo.model,
        'localizedModel': iosInfo.localizedModel,
        'identifierForVendor': iosInfo.identifierForVendor,
        'utsnameMachine': iosInfo.utsname.machine,
        'utsnameNodename': iosInfo.utsname.nodename,
      };
    } else {
      throw UnsupportedError('Unsupported platform');
    }
  }
}
