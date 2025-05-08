import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pocketsync_flutter/src/engine/connectivity_monitor.dart';
import 'package:pocketsync_flutter/src/engine/pocket_sync_network_client.dart';

class MockPocketSyncNetworkClient extends Mock
    implements PocketSyncNetworkClient {}

void main() {
  group('ConnectivityMonitor', () {
    late ConnectivityMonitor connectivityMonitor;
    late MockPocketSyncNetworkClient mockNetworkClient;
    late StreamController<bool> connectionStreamController;
    late bool onConnectedCalled;

    setUp(() {
      mockNetworkClient = MockPocketSyncNetworkClient();
      connectionStreamController = StreamController<bool>.broadcast();
      onConnectedCalled = false;

      // Setup mock network client
      when(() => mockNetworkClient.connectionStream)
          .thenAnswer((_) => connectionStreamController.stream);
      when(() => mockNetworkClient.isServerReachable()).thenReturn(false);

      // Create connectivity monitor
      connectivityMonitor = ConnectivityMonitor(
        networkClient: mockNetworkClient,
        onConnected: () {
          onConnectedCalled = true;
        },
      );
    });

    tearDown(() {
      connectivityMonitor.dispose();
      connectionStreamController.close();
    });

    test('should initialize with correct properties', () {
      expect(connectivityMonitor, isNotNull);
      expect(connectivityMonitor.isConnected, isFalse);
    });

    test('should update connection status when socket connection changes',
        () async {
      // Start monitoring
      connectivityMonitor.startMonitoring();

      // Verify initial state
      expect(connectivityMonitor.isConnected, isFalse);
      expect(onConnectedCalled, isFalse);

      // Simulate connection established
      connectionStreamController.add(true);

      // Need to wait for the stream event to be processed
      await Future.delayed(const Duration(milliseconds: 50));

      // Verify connection status updated and callback triggered
      expect(connectivityMonitor.isConnected, isTrue);
      expect(onConnectedCalled, isTrue);
    });

    test('should not trigger callback when already connected', () {
      // Setup initial state as connected
      when(() => mockNetworkClient.isServerReachable()).thenReturn(true);
      connectivityMonitor = ConnectivityMonitor(
        networkClient: mockNetworkClient,
        onConnected: () {
          onConnectedCalled = true;
        },
      );
      connectivityMonitor.startMonitoring();

      // Reset flag
      onConnectedCalled = false;

      // Simulate connection event when already connected
      connectionStreamController.add(true);

      // Verify callback not triggered
      expect(onConnectedCalled, isFalse);
    });

    test('should log connection lost when disconnected', () async {
      // Start as connected
      when(() => mockNetworkClient.isServerReachable()).thenReturn(true);
      connectivityMonitor = ConnectivityMonitor(
        networkClient: mockNetworkClient,
        onConnected: () {
          onConnectedCalled = true;
        },
      );
      connectivityMonitor.startMonitoring();

      // Need to wait for initialization to complete
      await Future.delayed(const Duration(milliseconds: 50));

      // Verify initial state
      expect(connectivityMonitor.isConnected, isTrue);

      // Simulate disconnection
      connectionStreamController.add(false);

      // Need to wait for the stream event to be processed
      await Future.delayed(const Duration(milliseconds: 50));

      // Verify connection status updated
      expect(connectivityMonitor.isConnected, isFalse);
    });

    test('should clean up resources when disposed', () {
      // Start monitoring
      connectivityMonitor.startMonitoring();

      // Dispose
      connectivityMonitor.dispose();

      // No way to directly test subscription cancellation, but we can verify
      // that adding to the stream after disposal doesn't trigger callback
      onConnectedCalled = false;
      connectionStreamController.add(true);
      expect(onConnectedCalled, isFalse);
    });
  });
}
