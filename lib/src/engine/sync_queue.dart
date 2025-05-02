import 'package:pocketsync_flutter/src/models/sync_change.dart';
import 'package:pocketsync_flutter/src/models/types.dart';

/// Manages a queue of pending changes to be synchronized.
///
/// The SyncQueue stores information about database changes that need to be
/// synchronized with the server. It provides methods for adding, retrieving,
/// and managing these changes for both upload and download operations.
class SyncQueue {
  /// Map of table names to sets of change types for upload operations
  /// This allows us to efficiently track which tables have pending changes
  /// and what types of changes they are.
  final Map<String, Set<ChangeType>> _pendingUploads = {};

  /// Flag indicating whether there's a pending download operation
  bool _hasPendingDownload = false;

  /// List of remote changes that have been received and need to be processed
  final List<SyncChange> _remoteChanges = [];

  /// Adds a local change to the upload queue.
  ///
  /// This method records that a change of type [changeType] has occurred
  /// in the table [tableName] and needs to be uploaded to the server.
  void addLocalChange(String tableName, ChangeType changeType) {
    _pendingUploads
        .putIfAbsent(tableName, () => <ChangeType>{})
        .add(changeType);
  }

  /// Adds a notification that remote changes are available.
  ///
  /// This method is called when the client receives a notification from the server
  /// that changes are available. The client will then schedule a REST call to
  /// download the actual changes from the server.
  void addRemoteChange() {
    _hasPendingDownload = true;
  }

  /// Adds a list of remote changes to be processed.
  ///
  /// This method is called after the client has made a REST call to download
  /// changes from the server. The downloaded SyncChange objects are stored in the queue
  /// for processing.
  void addRemoteChanges(List<SyncChange> changes) {
    // If we've received changes, we don't need to add a notification since
    // we already have the actual changes to process
    _remoteChanges.addAll(changes);
  }

  /// Gets the list of remote changes that need to be processed.
  List<SyncChange> getRemoteChanges() {
    return List.from(_remoteChanges);
  }

  /// Clears the list of remote changes after they have been processed.
  void clearRemoteChanges() {
    _remoteChanges.clear();
  }

  /// Checks if the queue is empty (both uploads and downloads).
  bool get isEmpty =>
      _pendingUploads.isEmpty && !_hasPendingDownload && _remoteChanges.isEmpty;

  /// Checks if there are any pending downloads.
  bool get hasDownloads => _hasPendingDownload;

  /// Gets a list of table names that have pending upload changes.
  List<String> getTablesWithPendingUploads() {
    return _pendingUploads.keys.toList();
  }

  /// Marks upload changes for a specific table as processed.
  ///
  /// This removes all pending upload changes for the specified table.
  void markTableUploaded(String tableName) {
    _pendingUploads.remove(tableName);
  }

  /// Marks download operation as processed.
  ///
  /// This clears the download flag since we treat downloads as a single operation.
  void markDownloadProcessed() {
    _hasPendingDownload = false;
  }
}
