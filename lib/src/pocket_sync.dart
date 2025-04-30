import 'package:pocketsync_flutter/pocketsync_flutter.dart';

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

  final PocketSyncDatabase _database = PocketSyncDatabase();

  static Future<void> initialize({
    required PocketSyncOptions options,
    required DatabaseOptions databaseOptions,
  }) async {
    await _instance._database.initialize(databaseOptions);
    _instance._initialized = true;
  }

  void setUserId(String userId) {
    // TODO: Implement setting user id
  }

  Future<void> start() async {
    // TODO: Implement start
  }

  Future<void> pause() async {
    // TODO: Implement pause
  }

  Future<void> dispose() async {
    // TODO: Implement dispose
  }
}
