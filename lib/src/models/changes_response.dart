import 'sync_change.dart';

class ChangesResponse {
  final int count;
  final DateTime timestamp;
  final List<SyncChange> changes;
  final String syncSessionId;

  ChangesResponse({
    required this.count,
    required this.timestamp,
    required this.changes,
    required this.syncSessionId,
  });

  factory ChangesResponse.fromJson(Map<String, dynamic> json) {
    return ChangesResponse(
      count: json['count'] as int,
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
      changes: (json['changes'] as List<dynamic>)
          .map((json) => SyncChange.fromJson(json))
          .toList(),
      syncSessionId: json['sync_session_id'] as String,
    );
  }
}
