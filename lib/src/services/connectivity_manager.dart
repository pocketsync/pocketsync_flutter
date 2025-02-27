import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityManager {
  final void Function(bool isConnected) onConnectivityChanged;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isConnected = true;

  late final Connectivity _connectivity;

  ConnectivityManager({
    Connectivity? connectivity,
    required this.onConnectivityChanged,
  }) : _connectivity = connectivity ?? Connectivity();

  bool get isConnected => _isConnected;

  void startMonitoring() {
    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen(_handleConnectivityChange);
  }

  void stopMonitoring() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
  }

  void _handleConnectivityChange(List<ConnectivityResult> result) {
    final wasConnected = _isConnected;
    _isConnected = result.isNotEmpty && !result.contains(ConnectivityResult.none);

    if (wasConnected != _isConnected) {
      onConnectivityChanged(_isConnected);
    }
  }

  void dispose() {
    stopMonitoring();
  }
}
