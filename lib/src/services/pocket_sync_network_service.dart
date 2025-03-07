import 'dart:async';

import 'package:pocketsync_flutter/src/errors/sync_error.dart';
import 'package:pocketsync_flutter/src/models/change_log.dart';
import 'package:pocketsync_flutter/src/models/change_processing_response.dart';
import 'package:pocketsync_flutter/src/models/change_set.dart';
import 'package:pocketsync_flutter/src/services/logger_service.dart';
import 'package:dio/dio.dart';
import 'package:socket_io_client/socket_io_client.dart' as socket_io;

class PocketSyncNetworkService {
  final Dio _dio;
  socket_io.Socket? _socket;
  final _logger = LoggerService.instance;

  final String _serverUrl;
  final String _projectId;
  final String _authToken;

  String? _userId;
  String? _deviceId;
  DateTime? _lastSyncedAt;

  // Callback for handling incoming changes
  Future<void> Function(Iterable<ChangeLog>)? onChangesReceived;

  PocketSyncNetworkService({
    required String serverUrl,
    required String projectId,
    required String authToken,
    String? deviceId,
    Dio? dio,
  })  : _dio = dio ?? Dio(),
        _serverUrl = serverUrl,
        _projectId = projectId,
        _authToken = authToken,
        _deviceId = deviceId;

  void setUserId(String userId) => _userId = userId;

  void setDeviceId(String deviceId) => _deviceId = deviceId;

  void setLastSyncedAt(DateTime? lastSyncedAt) => _lastSyncedAt = lastSyncedAt;

  /// Disconnects from the WebSocket server
  /// This method should be called when sync is paused or the application is closed
  void disconnect() {
    if (_socket != null) {
      _logger.info('Disconnecting from WebSocket server');
      _socket!.disconnect();
      _socket = null;
    }
  }

  /// Reconnects to the WebSocket server
  /// If lastSyncedAt is provided, it will update the internal timestamp before reconnecting
  void reconnect({DateTime? lastSyncedAt}) {
    if (lastSyncedAt != null) {
      _logger.info(
          'Updating last sync timestamp before reconnecting: ${lastSyncedAt.toIso8601String()}');
      _lastSyncedAt = lastSyncedAt;
    }
    _connectWebSocket();
  }

  void _connectWebSocket() {
    if (_userId == null || _deviceId == null) {
      return;
    }

    if (_socket != null) {
      _socket!.disconnect();
      _socket = null;
    }

    try {
      _socket = socket_io.io('$_serverUrl/changes', {
        'transports': ['websocket'],
        'autoConnect': true,
        'reconnection': true,
        'reconnectionDelay': 5000,
        'reconnectionAttempts': double.infinity,
        'query': {
          'project_id': _projectId,
          'user_id': _userId,
          'device_id': _deviceId,
          if (_lastSyncedAt != null)
            'last_synced_at': _lastSyncedAt?.millisecondsSinceEpoch,
        },
        'extraHeaders': {
          'Authorization': 'Bearer $_authToken',
        }
      });

      _socket!.onConnect((_) => _logger.info('Connected to WebSocket'));

      _socket!.on('changes', (data) async {
        if (onChangesReceived != null) {
          final changesData = data as Map<String, dynamic>;
          final changelogs = List.from(changesData['changes']).map(
            (raw) => ChangeLog.fromJson(raw),
          );
          await onChangesReceived!(changelogs);
          // Acknowledge receipt of changes
          if (changesData['requiresAck'] == true) {
            _socket!.emit('acknowledge-changes', {
              'changeIds': changelogs.map((log) => log.id).toList(),
            });
          }
        }
      });

      _socket!.connect();
    } catch (e) {
      throw NetworkError('WebSocket connection failed', cause: e);
    }
  }

  Future<ChangeProcessingResponse> sendChanges(ChangeSet changes) {
    final completer = Completer<ChangeProcessingResponse>();

    // Execute network operations in a non-blocking way
    Future.microtask(() async {
      try {
        if (_userId == null) {
          completer.completeError(InitializationError('User ID not set'));
          return;
        }
        if (_deviceId == null) {
          completer.completeError(InitializationError('Device ID not set'));
          return;
        }

        final url = '$_serverUrl/sdk/changes';
        try {
          final response = await _dio.post(
            url,
            options: _getRequestOptions(),
            data: {
              'changeSets': [changes.toJson()],
            },
          );

          completer.complete(ChangeProcessingResponse.fromJson(response.data));
        } on DioException catch (e) {
          final statusCode = e.response?.statusCode;
          final message = e.response?.statusMessage ?? 'Network request failed';
          completer.completeError(
              NetworkError(message, statusCode: statusCode, cause: e));
        } catch (e) {
          completer
              .completeError(NetworkError('Failed to send changes', cause: e));
        }
      } catch (e) {
        _logger.error('Error sending changes to server');
        completer.completeError(e);
      }
    });

    return completer.future;
  }

  Options _getRequestOptions() {
    if (_userId == null) {
      throw InitializationError('User ID not set');
    }
    if (_deviceId == null) {
      throw InitializationError('Device ID not set');
    }

    return Options(
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_authToken',
        'x-project-id': _projectId,
        'x-user-id': _userId!,
        'x-device-id': _deviceId,
      },
    );
  }

  void dispose() {
    disconnect();
    _socket?.dispose();
    _socket = null;
    _dio.close();
  }
}
