import 'package:pocketsync_flutter/src/models/sync_change.dart';

class AggregatedChanges {
  final List<SyncChange> changes;

  /// It's possible to have multiple changes that affect the same record.
  /// 
  /// This list contains the IDs of all changes that affected the same record.
  /// Optimized changes will only include the ID of the last change. So we need to keep track
  /// of intermediate changes to mark them as synced.
  final List<String> affectedChangeIds;

  AggregatedChanges({required this.changes, required this.affectedChangeIds});
}