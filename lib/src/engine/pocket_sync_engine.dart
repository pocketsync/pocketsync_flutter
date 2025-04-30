import 'package:pocketsync_flutter/src/database/pocket_sync_database.dart';
import 'package:pocketsync_flutter/src/engine/pocket_sync_network_client.dart';

class PocketSyncEngine {
  final PocketSyncDatabase database;
  final PocketSyncNetworkClient _apiClient;

  PocketSyncEngine(
    this.database, {
    PocketSyncNetworkClient? apiClient,
  }) : _apiClient = apiClient ?? PocketSyncNetworkClient();

  Future<void> bootstrap() async {
    // TODO: start sync worker
  }

  void setUserId(String userId) {
    // TODO: Implement setting user id
  }

  Future<void> scheduleSync() async {
    // TODO: Implement schedule sync
  }

  Future<void> sync() async {
    await _apiClient.uploadChanges();
    await _apiClient.downloadChanges();
  }

  Future<void> stop() async {
    // TODO: Implement stop
  }
}
