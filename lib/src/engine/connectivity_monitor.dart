import 'dart:async';

import 'package:pocketsync_flutter/src/engine/pocket_sync_network_client.dart';

/// Monitors connectivity to the server using socket connection.
///
/// This class uses the socket connection from the network client to determine
/// when the device is online or offline. It notifies listeners when connectivity
/// changes, allowing the sync system to react accordingly.
class ConnectivityMonitor {
  final PocketSyncNetworkClient _networkClient;
  final void Function() _onConnected;

  bool _isConnected = false;
  StreamSubscription? _connectionSubscription;

  /// Creates a new ConnectivityMonitor.
  ///
  /// The [onConnected] callback is invoked when connectivity is established
  /// after being offline.
  ConnectivityMonitor({
    required PocketSyncNetworkClient networkClient,
    required void Function() onConnected,
  })  : _networkClient = networkClient,
        _onConnected = onConnected;

  /// Starts monitoring connectivity.
  ///
  /// This method sets up a listener for socket connection events to determine
  /// if the device is online or offline.
  void startMonitoring() {
    _connectionSubscription =
        _networkClient.connectionStream.listen(_handleConnectivityChange);

    _isConnected = _networkClient.isServerReachable();
  }

  /// Handles connectivity changes.
  ///
  /// This method is called when connectivity changes. If the device transitions
  /// from offline to online, it triggers the onConnected callback.
  void _handleConnectivityChange(bool isConnected) {
    final wasConnected = _isConnected;
    _isConnected = isConnected;

    if (!wasConnected && isConnected) {
      _onConnected();
    }
  }

  /// Gets the current connectivity status.
  bool get isConnected => _isConnected;

  /// Stops monitoring connectivity.
  void dispose() {
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
  }
}
