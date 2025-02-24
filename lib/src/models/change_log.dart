import 'dart:convert';

import 'package:pocketsync_flutter/src/models/change_set.dart';

class ChangeLog {
  final int id;
  final String userIdentifier;
  final String deviceId;
  final ChangeSet changeSet;
  final DateTime receivedAt;
  final DateTime? processedAt;

  ChangeLog({
    required this.id,
    required this.userIdentifier,
    required this.deviceId,
    required this.changeSet,
    required this.receivedAt,
    this.processedAt,
  });

  factory ChangeLog.fromJson(Map<String, dynamic> json) {
    return ChangeLog(
      id: json['id'],
      userIdentifier: json['userIdentifier'],
      deviceId: json['deviceId'],
      changeSet: ChangeSet.fromJson(jsonDecode(json['changeSet'])),
      receivedAt: DateTime.parse(json['receivedAt']),
      processedAt: json['processedAt'] != null
          ? DateTime.parse(json['processedAt'])
          : null,
    );
  }

  static List<ChangeLog> fromJsonList(List<dynamic> jsonList) {
    return jsonList.map((json) => ChangeLog.fromJson(json)).toList();
  }

  @override
  String toString() {
    return 'ChangeLog{id: $id, userIdentifier: $userIdentifier, deviceId: $deviceId, '
        'receivedAt: $receivedAt, processedAt: $processedAt}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChangeLog &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          userIdentifier == other.userIdentifier &&
          deviceId == other.deviceId &&
          changeSet == other.changeSet &&
          receivedAt == other.receivedAt &&
          processedAt == other.processedAt;

  @override
  int get hashCode =>
      id.hashCode ^
      userIdentifier.hashCode ^
      deviceId.hashCode ^
      changeSet.hashCode ^
      receivedAt.hashCode ^
      processedAt.hashCode;
}
