import 'dart:async';

import 'package:pocketsync_flutter/src/engine/sync_queue.dart';
import 'package:pocketsync_flutter/src/models/types.dart';
import 'package:pocketsync_flutter/src/utils/logger.dart';
import 'package:pocketsync_flutter/src/utils/sync_config.dart';

/// Manages the timing and scheduling of synchronization operations.
///
/// The SyncScheduler is responsible for determining when to perform sync
/// operations based on various factors such as:
/// - Application state
/// - Change frequency
///
/// It consolidates multiple changes that occur within a short time window
/// to reduce the number of sync operations and optimize resource usage.
class SyncScheduler {
  final SyncQueue _syncQueue;
  final Duration _debounceInterval;
  final Future<void> Function() _onSyncRequired;

  Timer? _uploadDebounceTimer;
  Timer? _downloadDebounceTimer;
  bool _uploadScheduled = false;
  bool _downloadScheduled = false;
  bool _isUploadInProgress = false;
  bool _isDownloadInProgress = false;

  /// Creates a new SyncScheduler.
  ///
  /// The [debounceInterval] determines how long to wait after the last change
  /// before triggering a sync operation. This helps consolidate multiple
  /// changes into a single sync operation.
  ///
  /// The [onSyncRequired] callback is invoked when the scheduler determines
  /// that a sync operation should be performed.
  SyncScheduler({
    required SyncQueue syncQueue,
    required Future<void> Function() onSyncRequired,
    Duration? debounceInterval,
  })  : _syncQueue = syncQueue,
        _onSyncRequired = onSyncRequired,
        _debounceInterval = debounceInterval ?? SyncConfig.defaultDebounceInterval;

  /// Schedules a sync operation based on a database change.
  void scheduleUpload(String tableName, ChangeType changeType) {
    _syncQueue.addLocalChange(tableName, changeType);

    if (_isUploadInProgress) {
      return;
    }

    _cancelExistingTimers();

    _uploadScheduled = true;
    _uploadDebounceTimer = Timer(_debounceInterval, _evaluateUploadConditions);
    Logger.log(
        'SyncScheduler: Upload scheduled in ${_debounceInterval.inSeconds} seconds');
  }

  /// Schedules a sync operation based on a remote change.
  void scheduleDownload() {
    _syncQueue.addRemoteChange();

    if (_isDownloadInProgress) {
      return;
    }

    if (_uploadScheduled || _isUploadInProgress) {
      return;
    }

    if (_downloadScheduled) {
      _downloadDebounceTimer?.cancel();
    }

    _downloadScheduled = true;
    _downloadDebounceTimer =
        Timer(_debounceInterval, _evaluateDownloadConditions);
  }

  /// Forces an immediate sync operation regardless of current conditions.
  Future<void> forceSyncNow() async {
    _cancelExistingTimers();

    if (_isUploadInProgress || _isDownloadInProgress) {
      return;
    }

    await _performSync();
  }

  void _cancelExistingTimers() {
    _uploadDebounceTimer?.cancel();
    _downloadDebounceTimer?.cancel();
    _uploadScheduled = false;
    _downloadScheduled = false;
  }

  Future<void> _evaluateUploadConditions() async {
    _uploadScheduled = false;

    if (_syncQueue.isEmpty) {
      return;
    }

    await _performUpload();
  }

  Future<void> _evaluateDownloadConditions() async {
    _downloadScheduled = false;

    if (_syncQueue.isEmpty) {
      return;
    }

    await _performDownload();
  }

  Future<void> _performUpload() async {
    if (_isUploadInProgress) {
      return;
    }

    try {
      _isUploadInProgress = true;

      await _onSyncRequired();
    } catch (e) {
      Logger.log('SyncScheduler: Error during upload: $e');
    } finally {
      _isUploadInProgress = false;
    }
  }

  Future<void> _performDownload() async {
    if (_isDownloadInProgress) {
      return;
    }

    try {
      _isDownloadInProgress = true;

      await _onSyncRequired();
    } catch (e) {
      Logger.log('SyncScheduler: Error during download: $e');
    } finally {
      _isDownloadInProgress = false;
    }
  }

  Future<void> _performSync() async {
    try {
      _isUploadInProgress = true;
      _isDownloadInProgress = true;

      await _onSyncRequired();
    } catch (e) {
      Logger.log('SyncScheduler: Error during sync: $e');
    } finally {
      _isUploadInProgress = false;
      _isDownloadInProgress = false;
    }
  }

  /// Disposes of resources used by the scheduler.
  void dispose() {
    _cancelExistingTimers();
    _isUploadInProgress = false;
    _isDownloadInProgress = false;
  }
}
