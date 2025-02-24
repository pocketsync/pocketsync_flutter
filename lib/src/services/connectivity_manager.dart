import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityManager {
  final void Function(bool isConnected) onConnectivityChanged;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isConnected = true;

  ConnectivityManager({required this.onConnectivityChanged});

  bool get isConnected => _isConnected;

  void startMonitoring() {
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen(_handleConnectivityChange);
  }

  void stopMonitoring() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
  }

  void _handleConnectivityChange(List<ConnectivityResult> result) {
    final wasConnected = _isConnected;
    _isConnected =
        !(result.contains(ConnectivityResult.none) || result.isEmpty);

    if (wasConnected != _isConnected) {
      onConnectivityChanged(_isConnected);
    }
  }

  void dispose() {
    stopMonitoring();
  }
}
