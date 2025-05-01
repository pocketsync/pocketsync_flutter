import 'dart:async';

import 'package:pocketsync_flutter/src/types.dart';
import 'package:pocketsync_flutter/src/utils/logger.dart';
import 'package:pocketsync_flutter/src/engine/sync_change.dart';
import 'package:pocketsync_flutter/src/utils/sse_client.dart';

class PocketSyncNetworkClient {
  final String _baseUrl;

  String? _deviceId;
  String? _userId;

  PocketSyncNetworkClient({required String baseUrl})
      : _baseUrl = baseUrl;

  final Map<String, String> _headers = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  Stream<String> get remoteChangesStream => _remoteChangesStream.stream;
  final _remoteChangesStream = StreamController<String>();
  StreamSubscription<SseEvent>? _remoteChangesSubscription;

   SseClient? _sseClient;

  void setupClient(PocketSyncOptions options, String deviceId) {
    _deviceId = deviceId;

    _headers.addAll({
      'Authorization': 'Api-Key ${options.authToken}',
      'x-project-id': options.projectId,
      'x-device-id': deviceId,
    });

    Logger.log(
        'PocketSyncNetworkClient: Initialized with device ID: $deviceId');
  }

  void setUserId(String userId) {
    _userId = userId;
    _headers['x-user-id'] = userId;
    Logger.log('PocketSyncNetworkClient: User ID set to: $userId');
  }

  void listenForRemoteChanges() async {
    _sseClient ??= SseClient('$_baseUrl/sync/notifications', headers: _headers);
    _sseClient!.connect();
    _remoteChangesSubscription = _sseClient!.stream.listen((event) {
      _remoteChangesStream.add(event.data);
    });
  }

  /// Uploads a list of changes to the server.
  ///
  /// This method takes a list of [SyncChange] objects, bundles them into a
  /// [SyncChangeBatch], and sends them to the server for processing.
  Future<bool> uploadChanges(List<SyncChange> changes) async {
    if (changes.isEmpty) {
      Logger.log('PocketSyncNetworkClient: No changes to upload');
      return true;
    }

    if (_deviceId == null) {
      Logger.log(
          'PocketSyncNetworkClient: Device ID not set, cannot upload changes');
      return false;
    }

    try {
      // Create a batch of changes
      final batch = SyncChangeBatch(
        deviceId: _deviceId!,
        userId: _userId,
        changes: changes,
      );

      // Convert the batch to JSON
      final payload = batch.toJson();

      // TODO: Implement actual HTTP request to upload changes
      // For now, just simulate a successful upload
      Logger.log(
          'PocketSyncNetworkClient: Uploading ${changes.length} changes');
      Logger.log(
          'PocketSyncNetworkClient: Payload size: ${payload.length} bytes');

      // Simulate network delay
      await Future.delayed(const Duration(milliseconds: 500));

      // Return success
      return true;
    } catch (e) {
      Logger.log('PocketSyncNetworkClient: Error uploading changes: $e');
      return false;
    }
  }

  Future<void> downloadChanges() async {
    // TODO: Implement download changes
  }

  void dispose() {
    _remoteChangesSubscription?.cancel();
    _remoteChangesSubscription = null;
    _sseClient?.disconnect();
    _sseClient = null;
  }
}
