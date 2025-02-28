/// Defines how conflicts should be resolved when remote and local changes conflict
enum ConflictResolutionStrategy {
  /// Ignore conflicts and apply remote changes
  ignore,

  /// Use server changes in case of conflict
  serverWins,

  /// Keep local changes in case of conflict
  clientWins,

  /// Use custom resolution strategy
  custom
}

/// Handles conflict resolution between local and remote changes.
/// The default strategy is to ignore conflicts and apply remote changes.
///
class ConflictResolver {
  final ConflictResolutionStrategy strategy;
  final Future<Map<String, dynamic>> Function(
    String tableName,
    Map<String, dynamic> localRow,
    Map<String, dynamic> remoteRow,
  )? customResolver;

  const ConflictResolver({
    this.strategy = ConflictResolutionStrategy.ignore,
    this.customResolver,
  }) : assert(
          strategy != ConflictResolutionStrategy.custom ||
              customResolver != null,
          'Custom resolver must be provided when using custom strategy',
        );

  /// Resolves conflicts synchronously - for use in isolates
  /// Note: This does not support custom resolvers that require async operations
  Map<String, dynamic> resolveConflict(String tableName,
      Map<String, dynamic> localRow, Map<String, dynamic> remoteRow) {
    // Implement last-write-wins strategy by comparing timestamps
    final localTimestamp = localRow['timestamp'] as int?;
    final remoteTimestamp = remoteRow['timestamp'] as int?;

    if (localTimestamp != null && remoteTimestamp != null) {
      return remoteTimestamp > localTimestamp ? remoteRow : localRow;
    }

    // If timestamps are not available, fall back to strategy-based resolution
    switch (strategy) {
      case ConflictResolutionStrategy.ignore:
      case ConflictResolutionStrategy.serverWins:
        return remoteRow;
      case ConflictResolutionStrategy.clientWins:
        return localRow;
      case ConflictResolutionStrategy.custom:
        throw UnsupportedError(
            'Custom conflict resolution is not supported in isolates');
    }
  }
}
