import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pocketsync_flutter/src/engine/sync_queue.dart';
import 'package:pocketsync_flutter/src/types.dart';

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
  
  Timer? _debounceTimer;
  bool _syncScheduled = false;
  bool _isSyncInProgress = false;
  DateTime _lastSyncTime = DateTime.fromMillisecondsSinceEpoch(0);
  
  /// Callback to be invoked when a sync should be performed
  final Future<void> Function() _onSyncRequired;
  
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
  }) : _syncQueue = syncQueue,
       _onSyncRequired = onSyncRequired,
       _debounceInterval = debounceInterval ?? const Duration(seconds: 5);
  
  /// Schedules a sync operation based on a database change.
  ///
  /// This method is called when a change is detected in the database.
  /// It adds the change to the sync queue and schedules a sync operation
  /// based on the current conditions.
  void scheduleSync(String tableName, ChangeType changeType) {
    // Add the change to the sync queue
    _syncQueue.addChange(tableName, changeType);
    
    // If a sync is already in progress, we don't need to schedule another one
    if (_isSyncInProgress) {
      debugPrint('SyncScheduler: Sync already in progress, change queued');
      return;
    }
    
    // If a sync is already scheduled, reset the timer to wait for more changes
    if (_syncScheduled) {
      _debounceTimer?.cancel();
    }
    
    _syncScheduled = true;
    _debounceTimer = Timer(_debounceInterval, _evaluateSyncConditions);
    debugPrint('SyncScheduler: Sync scheduled in ${_debounceInterval.inSeconds} seconds');
  }
  
  /// Forces an immediate sync operation regardless of current conditions.
  ///
  /// This is useful for manual sync requests from the user.
  Future<void> forceSyncNow() async {
    debugPrint('SyncScheduler: Force sync requested');
    _debounceTimer?.cancel();
    _syncScheduled = false;
    
    // Don't start another sync if one is already in progress
    if (_isSyncInProgress) {
      debugPrint('SyncScheduler: Cannot force sync, sync already in progress');
      return;
    }
    
    await _performSync();
  }
  
  /// Evaluates the current conditions to determine if a sync should be performed.
  ///
  /// This method checks if there are any changes to sync and if enough time
  /// has passed since the last sync operation.
  Future<void> _evaluateSyncConditions() async {
    _syncScheduled = false;
    
    // Check if there are any changes to sync
    if (_syncQueue.isEmpty) {
      debugPrint('SyncScheduler: No changes to sync');
      return;
    }
    
    await _performSync();
  }
  
  /// Performs the actual sync operation.
  ///
  /// This method invokes the [_onSyncRequired] callback to trigger
  /// the sync process.
  Future<void> _performSync() async {
    if (_isSyncInProgress) {
      debugPrint('SyncScheduler: Sync already in progress, skipping');
      return;
    }
    
    try {
      _isSyncInProgress = true;
      debugPrint('SyncScheduler: Starting sync operation');
      
      await _onSyncRequired();
      
      _lastSyncTime = DateTime.now();
      debugPrint('SyncScheduler: Sync completed at ${_lastSyncTime.toIso8601String()}');
    } catch (e) {
      debugPrint('SyncScheduler: Error during sync: $e');
    } finally {
      _isSyncInProgress = false;
    }
  }
  
  /// Disposes of resources used by the scheduler.
  void dispose() {
    _debounceTimer?.cancel();
    _syncScheduled = false;
    _isSyncInProgress = false;
  }
}