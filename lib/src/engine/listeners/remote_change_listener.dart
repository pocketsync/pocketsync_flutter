import 'package:pocketsync_flutter/src/engine/listeners/change_listener.dart';
import 'package:pocketsync_flutter/src/engine/pocket_sync_network_client.dart';
import 'package:pocketsync_flutter/src/engine/sync_scheduler.dart';

class RemoteChangeListener extends ChangeListener {
  final SyncScheduler _syncScheduler;
  final PocketSyncNetworkClient _apiClient;

  RemoteChangeListener({
    required SyncScheduler syncScheduler,
    required PocketSyncNetworkClient apiClient,
  })  : _syncScheduler = syncScheduler,
        _apiClient = apiClient;

  @override
  void startListening() {
    _apiClient.listenForRemoteChanges(onRemoteChange: _onRemoteChange);
  }
  
  void _onRemoteChange() {
    _syncScheduler.scheduleDownload();
  }

  @override
  void stopListening() {
    _apiClient.stopListening();
  }

  @override
  void dispose() {
    _apiClient.dispose();
  }
}
