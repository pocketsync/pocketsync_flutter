import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';

class SseEvent {
  final String? id;
  final String? event;
  final String data;

  SseEvent({this.id, this.event, required this.data});
}

class SseClient {
  final String url;
  final Map<String, String>? headers;
  final Duration reconnectDelay;
  final int maxRetryAttempts;

  StreamController<SseEvent>? _streamController;
  Dio? _client;
  StreamSubscription? _subscription;
  bool _isConnected = false;
  bool _shouldReconnect = false;
  String? _lastEventId;
  int _retryTimeout = 3000;
  int _retryAttempts = 0;
  Timer? _reconnectTimer;

  SseClient(
    this.url, {
    this.headers,
    this.reconnectDelay = const Duration(seconds: 3),
    this.maxRetryAttempts = 5,
  });

  Stream<SseEvent> get stream {
    _streamController ??= StreamController<SseEvent>.broadcast();
    return _streamController!.stream;
  }

  bool get isConnected => _isConnected;

  Future<void> connect() async {
    if (_isConnected) return;

    _shouldReconnect = true;
    _isConnected = true;
    await _establishConnection();
  }

  Future<void> _establishConnection() async {
    if (!_shouldReconnect) return;

    _client = Dio();

    try {
      // Build headers
      final requestHeaders = headers ?? {};
      requestHeaders['Accept'] = 'text/event-stream';
      requestHeaders['Cache-Control'] = 'no-cache';

      // Add last event ID if available
      if (_lastEventId != null) {
        requestHeaders['Last-Event-ID'] = _lastEventId!;
      }

      final options = Options(
        headers: requestHeaders,
        responseType: ResponseType.stream,
      );

      final response = await _client!.get(url, options: options);
      final responseStream = response.data.stream;

      _retryAttempts = 0;

      // Variables for event parsing
      String? eventId;
      String? eventType;
      StringBuffer data = StringBuffer();

      _subscription = responseStream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((String line) {
        // Empty line means end of event
        if (line.isEmpty) {
          if (data.isNotEmpty) {
            final event = SseEvent(
              id: eventId,
              event: eventType,
              data: data.toString(),
            );

            // Update last event ID if available
            if (eventId != null) {
              _lastEventId = eventId;
            }

            if (_streamController != null && !_streamController!.isClosed) {
              _streamController!.add(event);
            }
          }

          // Reset for next event
          eventId = null;
          eventType = null;
          data = StringBuffer();
          return;
        }

        // Process line based on field name
        if (line.startsWith('id:')) {
          eventId = line.substring(3).trim();
        } else if (line.startsWith('event:')) {
          eventType = line.substring(6).trim();
        } else if (line.startsWith('data:')) {
          // Add new line if we already have data
          if (data.isNotEmpty) {
            data.write('\n');
          }
          data.write(line.substring(5).trim());
        } else if (line.startsWith('retry:')) {
          // Update retry timeout
          final retryMs = int.tryParse(line.substring(6).trim());
          if (retryMs != null) {
            _retryTimeout = retryMs;
          }
        } else if (line.startsWith(':')) {
          // Comment, ignore
        }
      }, onDone: () {
        _isConnected = false;
        _scheduleReconnection();
      }, onError: (error) {
        _isConnected = false;
        _streamController?.addError(error);
        _scheduleReconnection();
      });
    } catch (e) {
      _isConnected = false;
      _streamController?.addError(e);
      _scheduleReconnection();
    }
  }

  void _scheduleReconnection() {
    if (!_shouldReconnect) return;
    if (_retryAttempts >= maxRetryAttempts) {
      _shouldReconnect = false;
      _streamController?.addError(Exception('Max retry attempts reached'));
      return;
    }

    _retryAttempts++;
    _subscription?.cancel();
    _subscription = null;
    _client?.close();
    _client = null;

    // Use the server-specified retry timeout or default reconnect delay
    final delay = Duration(milliseconds: _retryTimeout);

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () async {
      await _establishConnection();
    });
  }

  void disconnect() {
    _shouldReconnect = false;
    _isConnected = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _client?.close();
    _client = null;
  }

  void dispose() {
    disconnect();
    _streamController?.close();
    _streamController = null;
  }
}
