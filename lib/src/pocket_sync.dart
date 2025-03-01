import 'dart:async';
import 'package:meta/meta.dart';
import 'package:pocketsync_flutter/src/services/connectivity_manager.dart';
import 'package:pocketsync_flutter/src/database/database_change_manager.dart';
import 'package:pocketsync_flutter/src/database/pocket_sync_database.dart';
import 'package:pocketsync_flutter/src/models/change_set.dart';
import 'package:pocketsync_flutter/src/services/device_state_manager.dart';
import 'package:pocketsync_flutter/src/services/logger_service.dart';
import 'package:pocketsync_flutter/src/services/sync_retry_manager.dart';
import 'package:synchronized/synchronized.dart';
import 'models/pocket_sync_options.dart';
import 'models/change_processing_response.dart';
import 'services/pocket_sync_network_service.dart';
import 'services/changes_processor.dart';
import 'services/sync_task_queue.dart';
import 'models/sync_status.dart';

class PocketSync {
  static PocketSync get instance {
    assert(
      _instance._initialized,
      'You must initialize the pocketsync instance before calling PocketSync.instance',
    );
    return _instance;
  }

  bool _initialized = false;
  PocketSync._();
  static final PocketSync _instance = PocketSync._();

  // Factory constructor for testing
  @visibleForTesting
  factory PocketSync.test({
    PocketSyncDatabase? database,
    PocketSyncNetworkService? networkService,
    ChangesProcessor? changesProcessor,
    SyncTaskQueue? syncQueue,
    DatabaseChangeManager? dbChangeManager,
    SyncRetryManager? retryManager,
    ConnectivityManager? connectivityManager,
  }) {
    final instance = PocketSync._();
    if (database != null) instance._database = database;
    if (networkService != null) instance._networkService = networkService;
    if (changesProcessor != null) instance._changesProcessor = changesProcessor;
    if (syncQueue != null) instance._syncQueue = syncQueue;
    if (dbChangeManager != null) instance._dbChangeManager = dbChangeManager;
    if (retryManager != null) instance._retryManager = retryManager;
    if (connectivityManager != null) {
      instance._connectivityManager = connectivityManager;
    }
    instance._initialized = true;
    return instance;
  }

  final _logger = LoggerService.instance;

  late PocketSyncDatabase _database;
  String? _userId;
  final _syncLock = Lock();

  PocketSyncNetworkService? _networkService;
  ChangesProcessor? _changesProcessor;
  SyncTaskQueue? _syncQueue;
  DatabaseChangeManager? _dbChangeManager;
  SyncRetryManager? _retryManager;
  ConnectivityManager? _connectivityManager;

  SyncStatus _status = SyncStatus.idle;

  /// Returns the database instance
  /// Throws [StateError] if PocketSync is not initialized
  PocketSyncDatabase get database => _runGuarded(() => _database);

  T _runGuarded<T>(T Function() callback) {
    if (!_initialized) {
      throw StateError(
        'You should call PocketSync.initialize before any other call.',
      );
    }
    return callback();
  }

  /// Initializes PocketSync with the given configuration
  /// [dbPath] - Path to the local database file
  /// [options] - PocketSync configuration options
  /// [databaseOptions] - Database configuration options
  ///
  /// Throws [StateError] if PocketSync is already initialized
  static Future<PocketSync> initialize({
    required String dbPath,
    required PocketSyncOptions options,
    required DatabaseOptions databaseOptions,
  }) async {
    assert(
      !_instance._initialized,
      'This instance is already initialized',
    );

    await _instance._init(
      dbPath: dbPath,
      options: options,
      databaseOptions: databaseOptions,
    );

    return _instance;
  }

  Future<void> _init({
    required String dbPath,
    required PocketSyncOptions options,
    required DatabaseOptions databaseOptions,
  }) async {
    if (_status != SyncStatus.idle) return;

    _retryManager = SyncRetryManager();

    LoggerService.instance.isSilent = options.silent;

    _dbChangeManager = DatabaseChangeManager();
    _networkService = PocketSyncNetworkService(
      serverUrl: options.serverUrl ?? 'https://api.pocketsync.dev',
      projectId: options.projectId,
      authToken: options.authToken,
    );

    _syncQueue = SyncTaskQueue(
      processChanges: _processSync,
      debounceDuration: const Duration(milliseconds: 500),
    );

    _database = PocketSyncDatabase(changeManager: _dbChangeManager);
    final db = await _database.initialize(
      dbPath: dbPath,
      options: databaseOptions,
      syncPreExistingRecords: options.syncPreExistingRecords,
    );

    // Initialize device state
    await DeviceStateManager.setupDeviceInfo(db);

    // Set device info in network service
    final deviceState = await DeviceStateManager.getDeviceState(db);
    if (deviceState != null) {
      _networkService?.setDeviceId(deviceState['device_id'] as String);
      final lastSyncedAt = deviceState['last_sync_timestamp'] as int?;
      _networkService?.setLastSyncedAt(
        lastSyncedAt != null
            ? DateTime.fromMillisecondsSinceEpoch(lastSyncedAt)
            : null,
      );
    }

    _changesProcessor = ChangesProcessor(
      db,
      databaseChangeManager: _dbChangeManager,
      conflictResolver: options.conflictResolver,
    );

    _networkService?.onChangesReceived = _changesProcessor?.applyRemoteChanges;

    _initialized = true;
  }

  /// Sets the user ID for synchronization
  /// [userId] - User ID
  /// This method should be called before [start].
  /// Throws [StateError] if PocketSync is not initialized
  Future<void> setUserId({required String userId}) async {
    await _runGuarded(() async {
      _userId = userId;
      _networkService?.setUserId(userId);
    });
  }

  /// Starts the synchronization process
  ///
  /// Throws [StateError] if user ID is not set
  /// Throws [StateError] if PocketSync is not initialized
  Future<void> start() async {
    await _runGuarded(() async {
      if (_userId == null) throw StateError('User ID not set');

      _status = SyncStatus.idle;

      // Initialize connectivity manager before cleanup
      _setupConnectivityMonitoring();

      _dbChangeManager?.addGlobalListener(_syncChanges);
      _networkService?.reconnect();
      
      await _sync();
    });
  }

  /// Pauses the synchronization process
  /// This method can be called to pause the synchronization process
  ///
  /// Throws [StateError] if PocketSync is not initialized
  void pause() {
    _runGuarded(() {
      _status = SyncStatus.paused;
      _networkService?.disconnect();
      _dbChangeManager?.removeGlobalListener(_syncChanges);
      _connectivityManager?.stopMonitoring();
    });
  }

  /// Returns whether sync is currently paused
  bool get isPaused => _runGuarded(() =>
      _connectivityManager?.isConnected != true ||
      _status == SyncStatus.paused);

  /// Sets up connectivity monitoring
  void _setupConnectivityMonitoring() {
    _connectivityManager = ConnectivityManager(
      onConnectivityChanged: (isConnected) async {
        if (!isConnected) {
          _status = SyncStatus.paused;
          _networkService?.disconnect();
        } else if (_status != SyncStatus.idle && _status != SyncStatus.paused) {
          _networkService?.reconnect();
          await _sync();
        }
      },
    );
    _connectivityManager?.startMonitoring();
  }

  /// Cleans up existing resources without full disposal
  Future<void> _cleanupResources() async {
    // Disconnect network service
    _networkService?.disconnect();

    // Remove listener from database change manager
    _dbChangeManager?.removeGlobalListener(_syncChanges);

    // Stop connectivity monitoring
    _connectivityManager?.stopMonitoring();
  }

  void _syncChanges(String table, bool isRemote) {
    if (isRemote) return;
    scheduleMicrotask(() => _sync());
  }

  /// Internal sync method
  Future<void> _sync() async {
    if (_userId == null ||
        _connectivityManager?.isConnected != true ||
        _status == SyncStatus.paused) {
      _logger.info('Skipping sync due to connectivity, status or user ID');
      return;
    }

    await _syncLock.synchronized(() async {
      if (_status == SyncStatus.syncing) return;

      _status = SyncStatus.syncing;

      await _retryManager?.executeWithRetry(() async {
        try {
          final changeSet = await _changesProcessor?.getUnSyncedChanges();
          if (changeSet != null && changeSet.isNotEmpty) {
            await _syncQueue?.enqueue(changeSet);
          } else {
            _status = SyncStatus.idle;
          }
        } catch (e) {
          _logger.error('Error syncing changes', error: e);
          _status = SyncStatus.idle;
          rethrow;
        }
      });
    });
  }

  /// Processes a batch of changes
  Future<void> _processSync(ChangeSet changeSet) async {
    try {
      final processedResponse = await _sendChanges(changeSet);

      if (processedResponse != null &&
          processedResponse.status == 'success' &&
          processedResponse.processed) {
        await _markChangesSynced(changeSet.localChangeIds);
        _status = SyncStatus.idle;
      }
    } catch (e) {
      _logger.error('Error processing changes');
      _status = SyncStatus.idle;
      rethrow;
    }
  }

  /// Sends changes to the server
  Future<ChangeProcessingResponse?> _sendChanges(ChangeSet changes) async =>
      await _networkService?.sendChanges(changes);

  /// Marks changes as synced
  Future<void> _markChangesSynced(List<int> changeIds) async =>
      await _changesProcessor?.markChangesSynced(changeIds);

  /// Cleans up resources
  Future<void> dispose() async {
    await _cleanupResources();
    _status = SyncStatus.idle;
    await _database.close();
    _syncQueue?.dispose();

    _initialized = false;
  }
}
