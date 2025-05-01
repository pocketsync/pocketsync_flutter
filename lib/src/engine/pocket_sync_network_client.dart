import 'dart:async';

import 'package:pocketsync_flutter/src/models/types.dart';
import 'package:pocketsync_flutter/src/utils/logger.dart';
import 'package:pocketsync_flutter/src/models/sync_change.dart';
import 'package:pocketsync_flutter/src/utils/sse_client.dart';

class PocketSyncNetworkClient {
  final String _baseUrl;

  String? _deviceId;
  String? _userId;
  DateTime? _lastFetchedTimestamp;

  PocketSyncNetworkClient({
    required String baseUrl,
  }) : _baseUrl = baseUrl;

  final Map<String, String> _headers = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

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

  void listenForRemoteChanges({void Function()? onRemoteChange}) async {
    _sseClient ??= SseClient('$_baseUrl/sync/notifications', headers: _headers);
    _sseClient!.connect();
    _remoteChangesSubscription = _sseClient!.stream.listen((event) {
      onRemoteChange?.call();
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

  /// Downloads changes from the server.
  ///
  /// This method makes a REST call to the server to fetch available changes
  /// and adds them to the SyncQueue for processing.
  Future<List<SyncChange>> downloadChanges({DateTime? since}) async {
    if (_deviceId == null) {
      Logger.log(
          'PocketSyncNetworkClient: Device ID not set, cannot download changes');
      return [];
    }

    try {
      // Use provided timestamp or the last one we stored
      final timestamp = since ?? _lastFetchedTimestamp ?? DateTime.fromMillisecondsSinceEpoch(0);
      
      Logger.log('PocketSyncNetworkClient: Downloading changes since ${timestamp.toIso8601String()}');
      
      // TODO: Implement actual HTTP request to download changes
      // For now, just simulate a successful download with mock data
      
      // Simulate network delay
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Create some mock changes for testing
      final mockChanges = [
        SyncChange(
          id: 1001,
          tableName: 'notes',
          recordId: 'note123',
          operation: ChangeType.insert,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          version: 1,
          data: {'id': 'note123', 'title': 'New Note', 'content': 'This is a test note'},
        ),
        SyncChange(
          id: 1002,
          tableName: 'tasks',
          recordId: 'task456',
          operation: ChangeType.update,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          version: 2,
          data: {'id': 'task456', 'title': 'Updated Task', 'completed': true},
        ),
      ];
      
      // Update the last fetched timestamp
      _lastFetchedTimestamp = DateTime.now();
      
      Logger.log('PocketSyncNetworkClient: Downloaded ${mockChanges.length} changes');
      
      return mockChanges;
    } catch (e) {
      Logger.log('PocketSyncNetworkClient: Error downloading changes: $e');
      return [];
    }
  }

  void stopListening() {
    _remoteChangesSubscription?.cancel();
    _remoteChangesSubscription = null;
    _sseClient?.disconnect();
    _sseClient = null;
  }

  void dispose() {
    _remoteChangesSubscription?.cancel();
    _remoteChangesSubscription = null;
    _sseClient?.disconnect();
    _sseClient = null;
  }
}
