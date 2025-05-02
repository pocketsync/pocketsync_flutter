import 'dart:async';

import 'package:pocketsync_flutter/src/engine/listeners/change_listener.dart';
import 'package:pocketsync_flutter/src/engine/pocket_sync_network_client.dart';
import 'package:pocketsync_flutter/src/engine/sync_scheduler.dart';
import 'package:pocketsync_flutter/src/models/sync_notification.dart';
import 'package:pocketsync_flutter/src/utils/logger.dart';

class RemoteChangeListener extends ChangeListener {
  final DateTime since;
  final SyncScheduler _syncScheduler;
  final PocketSyncNetworkClient _apiClient;
  StreamSubscription<SyncNotification>? _subscription;

  RemoteChangeListener({
    required SyncScheduler syncScheduler,
    required PocketSyncNetworkClient apiClient,
    required this.since,
  })  : _syncScheduler = syncScheduler,
        _apiClient = apiClient;

  @override
  void startListening() {
    final notificationStream = _apiClient.listenForRemoteChanges(since: since);
    _subscription = notificationStream.listen(_onRemoteChange);
    Logger.log('RemoteChangeListener: Started listening for remote changes');
  }

  void _onRemoteChange(SyncNotification notification) {
    Logger.log(
        'RemoteChangeListener: Received notification - ${notification.changeCount} changes from device ${notification.sourceDeviceId}');
    _syncScheduler.scheduleDownload();
  }

  @override
  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
    _apiClient.stopListening();
    Logger.log('RemoteChangeListener: Stopped listening for remote changes');
  }

  @override
  void dispose() {
    stopListening();
    Logger.log('RemoteChangeListener: Disposed');
  }
}
