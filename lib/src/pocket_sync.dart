import 'package:pocketsync_flutter/pocketsync_flutter.dart';
import 'package:pocketsync_flutter/src/database/database_watcher.dart';
import 'package:pocketsync_flutter/src/engine/pocket_sync_engine.dart';
import 'package:pocketsync_flutter/src/engine/schema_manager.dart';

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

  PocketSyncDatabase get database => _instance._database;

  static final SchemaManager _schemaManager = SchemaManager();
  final PocketSyncDatabase _database = PocketSyncDatabase(
    schemaManager: _schemaManager,
  );
  late PocketSyncEngine _engine;

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

  void setUserId(String userId) => _instance._engine.setUserId(userId);

  Future<void> start() async => await _instance._engine.bootstrap();

  Future<void> pause() async => await _instance._engine.stop();

  Future<void> dispose() async {
    _instance._engine.dispose();
    _instance._database.close();
    _instance._initialized = false;
  }
}
