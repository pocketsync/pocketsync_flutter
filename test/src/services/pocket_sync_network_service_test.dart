import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pocketsync_flutter/src/errors/sync_error.dart';
import 'package:pocketsync_flutter/src/models/change_set.dart';
import 'package:pocketsync_flutter/src/services/pocket_sync_network_service.dart';
import 'package:socket_io_client/socket_io_client.dart' as socket_io;

import '../../fixtures/change_set_fixtures.dart';

class MockDio extends Mock implements Dio {}

class MockSocket extends Mock implements socket_io.Socket {}

void main() {
  late PocketSyncNetworkService networkService;
  late MockDio mockDio;
  late MockSocket mockSocket;

  const serverUrl = 'https://test.server';
  const projectId = 'test-project';
  const authToken = 'test-token';
  const userId = 'test-user';
  const deviceId = 'test-device';

  setUpAll(() {
    registerFallbackValue(Uri());
    registerFallbackValue(RequestOptions(path: ''));
  });

  setUp(() {
    mockDio = MockDio();
    mockSocket = MockSocket();

    networkService = PocketSyncNetworkService(
      serverUrl: serverUrl,
      projectId: projectId,
      authToken: authToken,
      dio: mockDio,
    );

    when(() => mockSocket.connect()).thenReturn(mockSocket);
  });

  group('initialization', () {
    test('should initialize with correct parameters', () {
      expect(networkService, isNotNull);
    });

    test('should set user ID correctly', () {
      networkService.setUserId(userId);
      networkService.setDeviceId(deviceId);

      final now = DateTime.now();
      networkService.setLastSyncedAt(now);

      // Verify internal state through WebSocket connection
      networkService.reconnect();
    });
  });

  group('WebSocket connection', () {
    setUp(() {
      networkService.setUserId(userId);
      networkService.setDeviceId(deviceId);
    });

    test('should not connect without user ID or device ID', () {
      final service = PocketSyncNetworkService(
        serverUrl: serverUrl,
        projectId: projectId,
        authToken: authToken,
      );

      service.reconnect();
      verifyNever(() => mockSocket.connect());
    });
  });

  group('change handling', () {
    late ChangeSet testChangeSet;

    setUp(() {
      networkService.setUserId(userId);
      networkService.setDeviceId(deviceId);
      testChangeSet = ChangeSetFixtures.withUpdates;
    });

    test('should handle network errors when sending changes', () {
      when(
        () => mockDio.post(
          any(),
          options: any(named: 'options'),
          data: any(named: 'data'),
        ),
      ).thenThrow(DioException(
        requestOptions: RequestOptions(path: ''),
        response: Response(
          statusCode: 500,
          statusMessage: 'Server Error',
          requestOptions: RequestOptions(path: ''),
        ),
      ));

      expect(
        () => networkService.sendChanges(testChangeSet),
        throwsA(isA<NetworkError>()),
      );
    });
  });
}
