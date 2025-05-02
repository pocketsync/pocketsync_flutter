import 'package:pocketsync_flutter/src/utils/logger.dart';

/// Represents a notification about sync changes from the server.
///
/// This class corresponds to the server's SyncNotificationDto and provides
/// information about changes that have occurred on the server.
class SyncNotification {
  /// The type of notification
  final String type;

  /// The ID of the device that originated the changes
  final String sourceDeviceId;

  /// The number of changes in this notification
  final int changeCount;

  /// The timestamp of the notification (milliseconds since epoch)
  final int timestamp;

  /// Creates a new SyncNotification.
  SyncNotification({
    required this.type,
    required this.sourceDeviceId,
    required this.changeCount,
    required this.timestamp,
  });

  /// Creates a SyncNotification from a JSON object.
  factory SyncNotification.fromJson(Map<String, dynamic> json) {
    try {
      return SyncNotification(
        type: json['type'] as String,
        sourceDeviceId: json['sourceDeviceId'] as String,
        changeCount: json['changeCount'] as int,
        timestamp: json['timestamp'] as int,
      );
    } catch (e) {
      Logger.log('Error parsing SyncNotification: $e');
      rethrow;
    }
  }

  /// Converts the SyncNotification to a JSON object.
  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'sourceDeviceId': sourceDeviceId,
      'changeCount': changeCount,
      'timestamp': timestamp,
    };
  }

  @override
  String toString() {
    return 'SyncNotification{type: $type, sourceDeviceId: $sourceDeviceId, '
        'changeCount: $changeCount, timestamp: $timestamp}';
  }
}
