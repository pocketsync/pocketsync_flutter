import 'dart:async';

import 'package:pocketsync_flutter/src/engine/sync_queue.dart';
import 'package:pocketsync_flutter/src/types.dart';
import 'package:pocketsync_flutter/src/utils/logger.dart';

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
  DateTime _lastSyncTime = DateTime.fromMillisecondsSinceEpoch(0);

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
        _debounceInterval = debounceInterval ?? const Duration(seconds: 5);

  /// Schedules a sync operation based on a database change.
  void scheduleUpload(String tableName, ChangeType changeType) {
    _syncQueue.addLocalChange(tableName, changeType);

    if (_isUploadInProgress) {
      Logger.log('SyncScheduler: Upload already in progress, change queued');
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
      Logger.log('SyncScheduler: Download already in progress, change queued');
      return;
    }

    if (_uploadScheduled || _isUploadInProgress) {
      Logger.log(
          'SyncScheduler: Upload scheduled/in progress, postponing download');
      return;
    }

    if (_downloadScheduled) {
      _downloadDebounceTimer?.cancel();
    }

    _downloadScheduled = true;
    _downloadDebounceTimer =
        Timer(_debounceInterval, _evaluateDownloadConditions);
    Logger.log(
        'SyncScheduler: Download scheduled in ${_debounceInterval.inSeconds} seconds');
  }

  /// Forces an immediate sync operation regardless of current conditions.
  Future<void> forceSyncNow() async {
    Logger.log('SyncScheduler: Force sync requested');
    _cancelExistingTimers();

    if (_isUploadInProgress || _isDownloadInProgress) {
      Logger.log('SyncScheduler: Cannot force sync, sync already in progress');
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
      Logger.log('SyncScheduler: No changes to upload');
      return;
    }

    await _performUpload();
  }

  Future<void> _evaluateDownloadConditions() async {
    _downloadScheduled = false;

    if (_syncQueue.isEmpty) {
      Logger.log('SyncScheduler: No changes to download');
      return;
    }

    await _performDownload();
  }

  Future<void> _performUpload() async {
    if (_isUploadInProgress) {
      Logger.log('SyncScheduler: Upload already in progress, skipping');
      return;
    }

    try {
      _isUploadInProgress = true;
      Logger.log('SyncScheduler: Starting upload operation');

      await _onSyncRequired();
      _updateSyncTime();
    } catch (e) {
      Logger.log('SyncScheduler: Error during upload: $e');
    } finally {
      _isUploadInProgress = false;
    }
  }

  Future<void> _performDownload() async {
    if (_isDownloadInProgress) {
      Logger.log('SyncScheduler: Download already in progress, skipping');
      return;
    }

    try {
      _isDownloadInProgress = true;
      Logger.log('SyncScheduler: Starting download operation');

      await _onSyncRequired();
      _updateSyncTime();
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
      Logger.log('SyncScheduler: Starting sync operation');

      await _onSyncRequired();
      _updateSyncTime();
    } catch (e) {
      Logger.log('SyncScheduler: Error during sync: $e');
    } finally {
      _isUploadInProgress = false;
      _isDownloadInProgress = false;
    }
  }

  void _updateSyncTime() {
    _lastSyncTime = DateTime.now();
    Logger.log(
        'SyncScheduler: Sync completed at ${_lastSyncTime.toIso8601String()}');
  }

  /// Disposes of resources used by the scheduler.
  void dispose() {
    _cancelExistingTimers();
    _isUploadInProgress = false;
    _isDownloadInProgress = false;
  }
}
