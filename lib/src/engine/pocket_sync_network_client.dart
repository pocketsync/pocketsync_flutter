import 'dart:async';

import 'package:dio/dio.dart';
import 'package:pocketsync_flutter/src/models/changes_response.dart';
import 'package:pocketsync_flutter/src/models/types.dart';
import 'package:pocketsync_flutter/src/utils/logger.dart';
import 'package:pocketsync_flutter/src/models/sync_change.dart';
import 'package:pocketsync_flutter/src/models/sync_notification.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

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

  io.Socket? _socket;
  StreamController<SyncNotification>? _notificationController;
  Stream<SyncNotification>? _notificationStream;

  void setupClient(PocketSyncOptions options, String deviceId) {
    _deviceId = deviceId;

    _headers.addAll({
      'Authorization': 'Bearer ${options.authToken}',
      'x-project-id': options.projectId,
      'x-device-id': deviceId,
    });
  }

  void setUserId(String userId) {
    _userId = userId;
    _headers['x-user-id'] = userId;
  }

  /// Listens for remote changes using Socket.IO.
  ///
  /// This method establishes a connection to the server's Socket.IO endpoint
  /// and listens for change notifications.
  Stream<SyncNotification> listenForRemoteChanges({DateTime? since}) {
    if (_notificationStream != null) {
      return _notificationStream!;
    }

    _notificationController = StreamController<SyncNotification>.broadcast();

    try {
      // Initialize Socket.IO client
      _socket = io.io('$_baseUrl/sync/notifications', <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': true,
        'reconnection': true,
        'reconnectionDelay': 1000,
        'reconnectionDelayMax': 5000,
        'reconnectionAttempts': 10,
        'extraHeaders': _headers,
      });

      // Connect to the server
      _socket!.connect();

      // Listen for connection events
      _socket!.onConnect((_) {
        _socket!.emit('subscribe', {
          'userId': _userId,
          'deviceId': _deviceId,
          'since': since?.millisecondsSinceEpoch,
        });

        Logger.log('Connected to server');
      });

      _socket!.onConnectError((error) {
        Logger.log('Connection error: $error');
      });

      _socket!.onDisconnect((_) {
        Logger.log('Disconnected');
      });

      // Listen for sync notifications
      _socket!.on('sync-changes', (data) {
        try {
          final notification = SyncNotification.fromJson(data);
          Logger.log('New changes available: $notification');
          _notificationController!.add(notification);
        } catch (e) {
          Logger.log('Error parsing sync notification: $e');
        }
      });
    } catch (e) {
      Logger.log('Error setting up server connection: $e');
    }

    _notificationStream = _notificationController!.stream;
    return _notificationStream!;
  }

  /// Uploads a list of changes to the server.
  ///
  /// This method takes a list of [SyncChange] objects, bundles them into a
  /// [SyncChangeBatch], and sends them to the server for processing.
  Future<bool> uploadChanges(List<SyncChange> changes) async {
    if (changes.isEmpty || _deviceId == null || _userId == null) {
      Logger.log('No changes to upload');
      return true;
    }

    try {
      // Create a batch of changes
      final batch = SyncChangeBatch(changes: changes);

      // Convert the batch to JSON
      final payload = batch.toJson();

      Logger.log('Uploading ${changes.length} changes');

      final dio = Dio();
      final response = await dio.post(
        '$_baseUrl/sync/upload',
        data: payload,
        options: Options(headers: _headers),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        Logger.log('Successfully uploaded ${changes.length} changes');
        return true;
      } else {
        Logger.log('Failed to upload changes. Status: ${response.statusCode}');
        return false;
      }
    } on DioException catch (e) {
      Logger.log('Error uploading changes: ${e.response?.data}');
      return false;
    }
  }

  /// Downloads changes from the server.
  ///
  /// This method makes a REST call to the server to fetch available changes
  /// and returns them for processing.
  Future<ChangesResponse> downloadChanges({DateTime? since}) async {
    if (_deviceId == null || _userId == null) {
      Logger.log('Device ID or User ID not set, cannot download changes');
      return ChangesResponse(
        count: 0,
        timestamp: DateTime.now(),
        changes: [],
      );
    }

    try {
      // Use provided timestamp or the last one we stored
      final timestamp = since ??
          _lastFetchedTimestamp ??
          DateTime.fromMillisecondsSinceEpoch(0);

      final sinceTimestamp = timestamp.millisecondsSinceEpoch;

      Logger.log('Downloading changes since ${timestamp.toIso8601String()}');

      final dio = Dio();
      final response = await dio.get(
        '$_baseUrl/sync/download',
        queryParameters: {'since': sinceTimestamp},
        options: Options(headers: _headers),
      );

      if (response.statusCode == 200) {
        return ChangesResponse.fromJson(response.data);
      } else {
        Logger.log(
          'Failed to download changes. Status: ${response.statusCode}',
        );
        return ChangesResponse(
          count: 0,
          timestamp: DateTime.now(),
          changes: [],
        );
      }
    } on DioException catch (e) {
      Logger.log('Error downloading changes: ${e.response?.data}');
      return ChangesResponse(
        count: 0,
        timestamp: DateTime.now(),
        changes: [],
      );
    }
  }

  /// Stops listening for remote changes.
  void stopListening() {
    _socket?.disconnect();
    _notificationController?.close();
    _notificationController = null;
    _notificationStream = null;
  }

  /// Disposes of resources.
  void dispose() {
    stopListening();
    _socket?.dispose();
    _socket = null;
  }
}
