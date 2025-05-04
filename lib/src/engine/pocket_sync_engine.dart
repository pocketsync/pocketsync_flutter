import 'package:device_info_plus/device_info_plus.dart';
import 'package:pocketsync_flutter/pocketsync_flutter.dart';
import 'package:pocketsync_flutter/src/database/database_watcher.dart';
import 'package:pocketsync_flutter/src/engine/change_aggregator.dart';
import 'package:pocketsync_flutter/src/engine/listeners/database_change_listener.dart';
import 'package:pocketsync_flutter/src/engine/device_fingerprint_provider.dart';
import 'package:pocketsync_flutter/src/engine/listeners/remote_change_listener.dart';
import 'package:pocketsync_flutter/src/engine/merge_engine.dart';
import 'package:pocketsync_flutter/src/engine/pocket_sync_network_client.dart';
import 'package:pocketsync_flutter/src/engine/schema_manager.dart';
import 'package:pocketsync_flutter/src/engine/sync_queue.dart';
import 'package:pocketsync_flutter/src/engine/sync_scheduler.dart';
import 'package:pocketsync_flutter/src/engine/sync_worker.dart';
import 'package:sqflite/sqflite.dart';

/// Coordinates the overall synchronization process.
///
/// The PocketSyncEngine is the main orchestrator of the sync architecture, connecting
/// all the components together and managing the flow of data between them.
class PocketSyncEngine {
  final PocketSyncOptions options;
  final Database database;
  final SchemaManager schemaManager;
  final PocketSyncNetworkClient _apiClient;
  final DeviceFingerprintProvider _deviceFingerprintProvider;
  final DatabaseWatcher databaseWatcher;
  final DeviceInfoPlugin deviceInfo;
  final MergeEngine _mergeEngine;

  late SyncQueue _syncQueue;
  late ChangeAggregator _changeAggregator;
  late DatabaseChangeListener _databaseChangeListener;
  late RemoteChangeListener _remoteChangeListener;
  late SyncScheduler _syncScheduler;
  late SyncWorker _syncWorker;

  bool _isInitialized = false;

  PocketSyncEngine(
    this.database, {
    required this.options,
    required this.schemaManager,
    required this.databaseWatcher,
    required this.deviceInfo,
    PocketSyncNetworkClient? apiClient,
    DeviceFingerprintProvider? deviceFingerprintProvider,
    MergeEngine? mergeEngine,
  })  : _apiClient =
            apiClient ?? PocketSyncNetworkClient(baseUrl: options.serverUrl),
        _deviceFingerprintProvider =
            deviceFingerprintProvider ?? DeviceFingerprintProvider(),
        _mergeEngine = mergeEngine ??
            MergeEngine(
              strategy: options.conflictResolutionStrategy,
              customResolver: options.customResolver,
            );

  /// Initializes the sync engine and all its components.
  ///
  /// This method sets up the entire sync architecture and starts listening for
  /// database changes.
  Future<void> bootstrap() async {
    if (_isInitialized) return;

    final deviceFingerprint =
        await _deviceFingerprintProvider.getDeviceFingerprint(deviceInfo);

    await schemaManager.registerDevice(database.database, deviceFingerprint);

    _apiClient
      ..setupClient(options, deviceFingerprint)
      ..setDeviceInfos(await _deviceFingerprintProvider.getDeviceData(deviceInfo));

    // Process pre-existing data if enabled
    await schemaManager.syncPreExistingData(database.database, options);

    // Initialize components
    _syncQueue = SyncQueue();

    _changeAggregator = ChangeAggregator(
      database: database,
    );

    _syncScheduler = SyncScheduler(
      syncQueue: _syncQueue,
      onSyncRequired: _performSync,
    );

    _databaseChangeListener = DatabaseChangeListener(
      syncScheduler: _syncScheduler,
      databaseWatcher: databaseWatcher,
    );

    _syncWorker = SyncWorker(
      syncQueue: _syncQueue,
      changeAggregator: _changeAggregator,
      apiClient: _apiClient,
      database: database,
      mergeEngine: _mergeEngine,
      databaseWatcher: databaseWatcher,
      schemaManager: schemaManager,
    );

    _remoteChangeListener = RemoteChangeListener(
      syncScheduler: _syncScheduler,
      apiClient: _apiClient,
      since: await _syncWorker.getLastDownloadTimestamp(),
    );

    // Start listening for database changes
    _databaseChangeListener.startListening();
    _remoteChangeListener.startListening();

    _isInitialized = true;
  }

  /// Sets the user ID for synchronization.
  ///
  /// This method updates the user ID in the API client for authentication.
  void setUserId(String userId) {
    _apiClient.setUserId(userId);
  }

  /// Performs a sync operation.
  ///
  /// This method is called by the SyncScheduler when it determines that a sync
  /// should be performed.
  Future<void> _performSync() async {
    await _syncWorker.processQueue();

    await schemaManager.cleanupOldSyncRecords(database, options);
  }

  /// Manually triggers a sync operation.
  ///
  /// This method can be called to force a sync operation regardless of the
  /// current sync schedule.
  Future<void> scheduleSync() async {
    if (!_isInitialized) return;

    await _syncScheduler.forceSyncNow();
  }

  /// Pauses sync operations.
  ///
  /// This method stops the sync worker and change listener, effectively
  /// pausing all sync operations.
  Future<void> stop() async {
    if (!_isInitialized) return;

    _databaseChangeListener.stopListening();
    _remoteChangeListener.stopListening();
    await _syncWorker.stop();

    _isInitialized = false;
  }

  /// Resets the PocketSync engine.
  ///
  /// This method must be called to reset the engine.
  /// Be cautious when using this method as it will clear all change tracking data.
  Future<void> reset() async {
    if (!_isInitialized) return;

    schemaManager.reset(database.database);
  }

  /// Disposes of resources used by the sync engine.
  ///
  /// This method should be called when the sync engine is no longer needed.
  Future<void> dispose() async {
    if (!_isInitialized) return;

    _databaseChangeListener.dispose();
    _remoteChangeListener.dispose();
    await _syncWorker.stop();
    _apiClient.dispose();
    _isInitialized = false;
  }
}
