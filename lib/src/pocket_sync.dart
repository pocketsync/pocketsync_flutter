import 'dart:async';
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

class PocketSync {
  static final PocketSync instance = PocketSync._internal();
  PocketSync._internal();

  final _logger = LoggerService.instance;

  late PocketSyncDatabase _database;
  String? _userId;

  late PocketSyncNetworkService _networkService;
  late ChangesProcessor _changesProcessor;
  late final SyncTaskQueue _syncQueue;
  late final DatabaseChangeManager _dbChangeManager;
  final _retryManager = SyncRetryManager();

  late final ConnectivityManager _connectivityManager;

  bool _isInitialized = false;
  bool _isSyncing = false;
  bool _isPaused = true;

  /// Returns the database instance
  /// Throws [StateError] if PocketSync is not initialized
  PocketSyncDatabase get database => _runGuarded(() => _database);

  T _runGuarded<T>(T Function() callback) {
    if (!_isInitialized) {
      throw StateError(
        'You should call PocketSync.instance.initialize before any other call.',
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
  Future<void> initialize({
    required String dbPath,
    required PocketSyncOptions options,
    required DatabaseOptions databaseOptions,
  }) async {
    if (_isInitialized) return;

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
    );

    // Initialize device state
    await DeviceStateManager.setupDeviceInfo(db);

    // Set device info in network service
    final deviceState = await DeviceStateManager.getDeviceState(db);
    if (deviceState != null) {
      _networkService.setDeviceId(deviceState['device_id'] as String);
      final lastSyncedAt = deviceState['last_sync_timestamp'] as int?;
      _networkService.setLastSyncedAt(
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

    _networkService.onChangesReceived = _changesProcessor.applyRemoteChanges;
    _isInitialized = true;
  }

  /// Sets up connectivity monitoring
  void _setupConnectivityMonitoring() {
    _connectivityManager = ConnectivityManager(
      onConnectivityChanged: (isConnected) async {
        if (!isConnected) {
          _networkService.disconnect();
        } else if (!_isPaused) {
          _networkService.reconnect();
          await _sync();
        }
      },
    );
    _connectivityManager.startMonitoring();
  }

  /// Sets the user ID for synchronization
  /// [userId] - User ID
  /// This method should be called before [start].
  /// Throws [StateError] if PocketSync is not initialized
  Future<void> setUserId({required String userId}) async {
    await _runGuarded(() async {
      _userId = userId;
      _networkService.setUserId(userId);
    });
  }

  /// Starts the synchronization process
  ///
  /// Throws [StateError] if user ID is not set
  /// Throws [StateError] if PocketSync is not initialized
  Future<void> start() async {
    await _runGuarded(() async {
      if (_userId == null) throw StateError('User ID not set');
      
      await _cleanupResources();
      
      _isPaused = false;

      _dbChangeManager.addGlobalListener(_syncChanges);

      // Initialize connectivity monitoring
      _setupConnectivityMonitoring();
      _networkService.reconnect();
      await _sync();
    });
  }

  /// Cleans up existing resources without full disposal
  Future<void> _cleanupResources() async {
    _networkService.disconnect();
    _dbChangeManager.removeGlobalListener(_syncChanges);
    _connectivityManager.stopMonitoring();
    
    _isSyncing = false;
    _isPaused = true;
  }

  final _syncLock = Lock();

  void _syncChanges(String table, bool isRemote) {
    if (isRemote) return;

    if (!_isSyncing && _connectivityManager.isConnected && !_isPaused) {
      scheduleMicrotask(() => _sync());
    } else {
      _logger.info('Skipping syncChanges: inappropriate state');
    }
  }

  /// Internal sync method
  Future<void> _sync() async {
    if (_userId == null || !_connectivityManager.isConnected || _isPaused) {
      _logger.info('Sync skipped: user ID not set or inappropriate state');
      return;
    }

    await _syncLock.synchronized(() async {
      if (_isSyncing) return;

      await _retryManager.executeWithRetry(() async {
        _isSyncing = true;
        try {
          final changeSet = await _changesProcessor.getUnSyncedChanges();
          if (changeSet.isNotEmpty) {
            await _syncQueue.enqueue(changeSet);
          }
        } finally {
          _isSyncing = false;
        }
      });
    });
  }

  /// Processes a batch of changes
  Future<void> _processSync(ChangeSet changeSet) async {
    try {
      _logger.info('Processing batch: ${changeSet.length} changes');

      final processedResponse = await _sendChanges(changeSet);

      if (processedResponse.status == 'success' &&
          processedResponse.processed) {
        await _markChangesSynced(changeSet.localChangeIds);
        _logger.info('Changes successfully synced');
      }
    } catch (e) {
      _logger.error('Error processing changes', error: e);
      rethrow;
    }
  }

  /// Sends changes to the server
  Future<ChangeProcessingResponse> _sendChanges(ChangeSet changes) async =>
      await _networkService.sendChanges(changes);

  /// Marks changes as synced
  Future<void> _markChangesSynced(List<int> changeIds) async =>
      await _changesProcessor.markChangesSynced(changeIds);

  /// Pauses the synchronization process
  /// This method can be called to pause the synchronization process
  ///
  /// Throws [StateError] if PocketSync is not initialized
  void pause() {
    _runGuarded(() {
      _isPaused = true;
      _networkService.disconnect();
      _dbChangeManager.removeGlobalListener(_syncChanges);
      _connectivityManager.stopMonitoring();
      _logger.info('Sync manually paused');
    });
  }

  /// Returns whether sync is currently paused
  bool get isPaused =>
      _runGuarded(() => !_connectivityManager.isConnected || _isPaused);

  /// Cleans up resources
  Future<void> dispose() async {
    _isInitialized = false;
    await _database.close();
    _syncQueue.dispose();
  }
}
