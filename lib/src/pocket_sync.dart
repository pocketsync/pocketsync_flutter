import 'package:pocketsync_flutter/pocketsync_flutter.dart';
import 'package:pocketsync_flutter/src/database/database_watcher.dart';
import 'package:pocketsync_flutter/src/engine/pocket_sync_engine.dart';
import 'package:pocketsync_flutter/src/engine/schema_manager.dart';

/// The main entry point for PocketSync.
class PocketSync {
  /// Returns the singleton instance of PocketSync.
  ///
  /// Throws an error if the instance has not been initialized.
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

  /// Returns the database instance.
  PocketSyncDatabase get database => _instance._database;


  static final SchemaManager _schemaManager = SchemaManager();
  final PocketSyncDatabase _database = PocketSyncDatabase(
    schemaManager: _schemaManager,
  );
  late PocketSyncEngine _engine;

  /// Initializes the PocketSync instance.
  ///
  /// This method must be called before using any other PocketSync methods.
  ///
  /// [options] The configuration options for PocketSync.
  /// [databaseOptions] The configuration options for the database.
  static Future<void> initialize({
    required PocketSyncOptions options,
    required DatabaseOptions databaseOptions,
  }) async {
    final DatabaseWatcher databaseWatcher = DatabaseWatcher();
    _instance._engine = PocketSyncEngine(
      _instance._database,
      options: options,
      schemaManager: _schemaManager,
      databaseWatcher: databaseWatcher,
    );
    await _instance._database.initialize(
      databaseOptions,
      databaseWatcher,
    );

    _instance._initialized = true;
  }

  /// Sets the user ID for synchronization.
  ///
  /// This method updates the user ID in the API client for authentication.
  void setUserId(String userId) => _instance._engine.setUserId(userId);

  /// Starts the PocketSync engine.
  ///
  /// This method must be called after initialization to start the engine.
  Future<void> start() async => await _instance._engine.bootstrap();

  /// Stops the PocketSync engine.
  ///
  /// This method must be called to stop the engine.
  Future<void> stop() async => await _instance._engine.stop();

  /// Schedules a sync operation.
  ///
  /// This method can be called to force a sync operation regardless of the
  /// current sync schedule.
  Future<void> scheduleSync() async => await _instance._engine.scheduleSync();

  /// Resets the PocketSync engine.
  ///
  /// This method must be called to reset the engine.
  /// Be cautious when using this method as it will clear all change tracking data.
  Future<void> reset() async {
    // TODO: Implement reset logic
  }

  /// Disposes of the PocketSync instance.
  ///
  /// This method must be called to dispose of the instance.
  Future<void> dispose() async {
    _instance._engine.dispose();
    _instance._database.close();
    _instance._initialized = false;
  }
}
