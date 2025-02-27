import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:pocketsync_flutter/src/services/connectivity_manager.dart';

class MockConnectivity extends Mock implements Connectivity {}

void main() {
  late ConnectivityManager connectivityManager;
  late MockConnectivity mockConnectivity;
  late bool lastConnectionState;
  late Function(bool) onConnectivityChangedCallback;

  setUp(() {
    mockConnectivity = MockConnectivity();
    lastConnectionState =
        true; // Initialize to match ConnectivityManager's default state
    onConnectivityChangedCallback = (isConnected) {
      lastConnectionState = isConnected;
    };

    // Setup the mock connectivity stream
    final streamController = Stream.fromIterable([
      [ConnectivityResult.wifi]
    ]);
    when(() => mockConnectivity.onConnectivityChanged)
        .thenAnswer((_) => streamController);

    connectivityManager = ConnectivityManager(
      connectivity: mockConnectivity,
      onConnectivityChanged: onConnectivityChangedCallback,
    );
  });

  group('ConnectivityManager', () {
    test('initializes with correct default values', () {
      expect(connectivityManager.isConnected, isTrue);
    });

    test('startMonitoring subscribes to connectivity changes', () {
      // Act
      connectivityManager.startMonitoring();

      // Assert
      verify(() => mockConnectivity.onConnectivityChanged).called(1);
    });

    test('stopMonitoring cancels subscription', () {
      // Arrange
      final streamController =
          StreamController<List<ConnectivityResult>>.broadcast();
      when(() => mockConnectivity.onConnectivityChanged)
          .thenAnswer((_) => streamController.stream);

      connectivityManager = ConnectivityManager(
        connectivity: mockConnectivity,
        onConnectivityChanged: onConnectivityChangedCallback,
      );

      // Act
      connectivityManager.startMonitoring();
      connectivityManager.stopMonitoring();

      // Add an event after stopping - this should not trigger the callback
      streamController.add([ConnectivityResult.none]);

      // Assert - lastConnectionState should remain unchanged
      expect(lastConnectionState, isTrue);

      // Clean up
      streamController.close();
    });

    test('_handleConnectivityChange updates connection state correctly', () async {
      // Arrange
      final streamController =
          StreamController<List<ConnectivityResult>>.broadcast();
      when(() => mockConnectivity.onConnectivityChanged)
          .thenAnswer((_) => streamController.stream);

      connectivityManager = ConnectivityManager(
        connectivity: mockConnectivity,
        onConnectivityChanged: onConnectivityChangedCallback,
      );
      connectivityManager.startMonitoring();

      // Act & Assert - Connected (WiFi)
      streamController.add([ConnectivityResult.wifi]);
      await Future.microtask(() {});
      expect(connectivityManager.isConnected, isTrue);
      expect(lastConnectionState, isTrue);

      // Act & Assert - Disconnected (None)
      streamController.add([ConnectivityResult.none]);
      await Future.microtask(() {});
      expect(connectivityManager.isConnected, isFalse);
      expect(lastConnectionState, isFalse);

      // Act & Assert - Connected again (Mobile)
      streamController.add([ConnectivityResult.mobile]);
      await Future.microtask(() {});
      expect(connectivityManager.isConnected, isTrue);
      expect(lastConnectionState, isTrue);

      // Act & Assert - Empty list (should be treated as disconnected)
      streamController.add([]);
      await Future.microtask(() {});
      expect(connectivityManager.isConnected, isFalse);
      expect(lastConnectionState, isFalse);

      // Clean up
      streamController.close();
    });

    test('callback is not triggered when connection state does not change', () async {
      // Arrange
      int callbackCount = 0;
      final streamController =
          StreamController<List<ConnectivityResult>>.broadcast();
      when(() => mockConnectivity.onConnectivityChanged)
          .thenAnswer((_) => streamController.stream);

      connectivityManager = ConnectivityManager(
        connectivity: mockConnectivity,
        onConnectivityChanged: (_) {
          callbackCount++;
        },
      );
      connectivityManager.startMonitoring();

      // Act - Connected (WiFi)
      streamController.add([ConnectivityResult.wifi]);
      await Future.microtask(() {});
      expect(callbackCount, 0); // No change from initial true state

      // Act - Still connected (Mobile)
      streamController.add([ConnectivityResult.mobile]);
      await Future.microtask(() {});
      expect(callbackCount, 0); // Still connected, no change

      // Act - Disconnected
      streamController.add([ConnectivityResult.none]);
      await Future.microtask(() {});
      expect(callbackCount, 1); // Changed to disconnected

      // Act - Still disconnected
      streamController.add([]);
      await Future.microtask(() {});
      expect(callbackCount, 1); // Still disconnected, no change

      // Clean up
      streamController.close();
    });

    test('dispose calls stopMonitoring', () {
      // Arrange
      final streamController =
          StreamController<List<ConnectivityResult>>.broadcast();
      when(() => mockConnectivity.onConnectivityChanged)
          .thenAnswer((_) => streamController.stream);

      connectivityManager = ConnectivityManager(
        connectivity: mockConnectivity,
        onConnectivityChanged: onConnectivityChangedCallback,
      );
      connectivityManager.startMonitoring();

      // Act
      connectivityManager.dispose();
      streamController.add([ConnectivityResult.mobile]);

      // Assert - lastConnectionState should remain unchanged
      expect(lastConnectionState, isTrue);

      // Clean up
      streamController.close();
    });
  });
}
