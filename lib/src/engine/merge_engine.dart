import 'dart:async';
import 'package:pocketsync_flutter/pocketsync_flutter.dart';
import 'package:pocketsync_flutter/src/models/sync_change.dart';

class MergeEngine {
  final ConflictResolutionStrategy strategy;
  final ConflictResolver? customResolver;

  MergeEngine({
    this.strategy = ConflictResolutionStrategy.lastWriteWins,
    this.customResolver,
  }) {
    if (strategy == ConflictResolutionStrategy.custom &&
        customResolver == null) {
      throw ArgumentError(
        'Custom resolver must be provided when using custom strategy',
      );
    }
  }

  /// Resolves conflicts between local and remote changes.
  ///
  /// Uses the configured conflict resolution strategy:
  /// - lastWriteWins: most recent change based on timestamp wins
  /// - serverWins: server changes always take precedence
  /// - clientWins: local changes always take precedence
  /// - custom: uses the provided custom resolver function
  Future<List<SyncChange>> resolveConflicts(
    List<SyncChange> localChanges,
    List<SyncChange> remoteChanges,
  ) async {
    final mergedChanges = <SyncChange>[];
    final conflictMap = <String, List<SyncChange>>{};

    // Group changes by their record identifier
    for (final change in [...localChanges, ...remoteChanges]) {
      final key = '${change.tableName}:${change.recordId}';
      conflictMap[key] = [...(conflictMap[key] ?? []), change];
    }

    // Resolve conflicts for each record
    for (final entry in conflictMap.entries) {
      final changes = entry.value;

      if (changes.length == 1) {
        // No conflict - just one change
        mergedChanges.add(changes.first);
      } else {
        // Separate local and remote changes
        final localChange = changes.firstWhere(
          (c) => localChanges.contains(c),
          orElse: () => changes.first,
        );
        final remoteChange = changes.firstWhere(
          (c) => remoteChanges.contains(c),
          orElse: () => changes.first,
        );

        // Apply the appropriate conflict resolution strategy
        SyncChange winningChange;

        switch (strategy) {
          case ConflictResolutionStrategy.lastWriteWins:
            // Sort by timestamp, most recent first
            changes.sort((a, b) => b.timestamp.compareTo(a.timestamp));
            winningChange = changes.first;
            break;

          case ConflictResolutionStrategy.serverWins:
            winningChange = remoteChange;
            break;

          case ConflictResolutionStrategy.clientWins:
            winningChange = localChange;
            break;

          case ConflictResolutionStrategy.custom:
            winningChange = await customResolver!(localChange, remoteChange);
            break;
        }

        mergedChanges.add(winningChange);
      }
    }

    return mergedChanges;
  }

  /// Merges changes from remote and local sources, resolving conflicts.
  Future<List<SyncChange>> mergeChanges(
    List<SyncChange> localChanges,
    List<SyncChange> remoteChanges,
  ) async {
    final resolvedChanges = await resolveConflicts(localChanges, remoteChanges);

    return resolvedChanges;
  }
}
