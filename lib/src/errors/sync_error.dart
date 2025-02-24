import 'package:meta/meta.dart';

/// Base class for all PocketSync-related errors
@immutable
abstract class SyncError implements Exception {
  final String message;
  final dynamic cause;

  const SyncError(this.message, [this.cause]);

  @override
  String toString() =>
      'SyncError: $message${cause != null ? '\nCause: $cause' : ''}';
}

/// Thrown when there's a network-related error during synchronization
class NetworkError extends SyncError {
  final int? statusCode;

  const NetworkError(String message, {this.statusCode, dynamic cause})
      : super(message, cause);
}

/// Thrown when there's a database-related error
class DatabaseError extends SyncError {
  const DatabaseError(super.message, [super.cause]);
}

/// Thrown when there's a conflict during synchronization that cannot be resolved
class ConflictError extends SyncError {
  final String? entityId;
  final String? entityType;

  const ConflictError(
    String message, {
    this.entityId,
    this.entityType,
    dynamic cause,
  }) : super(message, cause);
}

/// Thrown when there's an initialization error
class InitializationError extends SyncError {
  const InitializationError(super.message, [super.cause]);
}

/// Thrown when there's an error in the sync state
class SyncStateError extends SyncError {
  const SyncStateError(super.message, [super.cause]);
}

/// Thrown when there's an error in processing changes
class ChangeProcessingError extends SyncError {
  final List<String>? failedChanges;

  const ChangeProcessingError(
    String message, {
    this.failedChanges,
    dynamic cause,
  }) : super(message, cause);
}
