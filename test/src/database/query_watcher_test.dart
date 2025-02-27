import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pocketsync_flutter/pocketsync_flutter.dart';
import 'package:pocketsync_flutter/src/database/query_watcher.dart';

class MockPocketSyncDatabase extends Mock implements PocketSyncDatabase {}

void main() {
  late MockPocketSyncDatabase mockDb;
  late QueryWatcher queryWatcher;
  
  const testSql = 'SELECT * FROM test_table';
  final testArgs = ['arg1', 'arg2'];
  final testTables = <String>{'test_table'};
  final testResults = [
    {'id': 1, 'name': 'Test 1'},
    {'id': 2, 'name': 'Test 2'},
  ];

  setUp(() {
    mockDb = MockPocketSyncDatabase();
    queryWatcher = QueryWatcher(testSql, testArgs, testTables);
  });

  group('QueryWatcher', () {
    test('initializes with correct values', () {
      expect(queryWatcher.sql, equals(testSql));
      expect(queryWatcher.arguments, equals(testArgs));
      expect(queryWatcher.tables, equals(testTables));
    });

    test('stream is broadcast stream', () {
      expect(queryWatcher.stream.isBroadcast, isTrue);
    });

    test('notify adds query results to stream', () async {
      // Arrange
      when(() => mockDb.rawQuery(testSql, testArgs))
          .thenAnswer((_) async => testResults);

      // Act & Assert
      expectLater(
        queryWatcher.stream,
        emits(testResults),
      );

      await queryWatcher.notify(mockDb);
      verify(() => mockDb.rawQuery(testSql, testArgs)).called(1);
    });

    test('notify adds error to stream when query fails', () async {
      // Arrange
      final testError = Exception('Test error');
      when(() => mockDb.rawQuery(testSql, testArgs))
          .thenThrow(testError);

      // Act & Assert
      expectLater(
        queryWatcher.stream,
        emitsError(isA<Exception>()),
      );

      await queryWatcher.notify(mockDb);
      verify(() => mockDb.rawQuery(testSql, testArgs)).called(1);
    });

    test('notify does nothing when watcher is not active', () async {
      // Arrange
      queryWatcher.dispose();
      
      // Act
      await queryWatcher.notify(mockDb);
      
      // Assert
      verifyNever(() => mockDb.rawQuery(any(), any()));
    });

    test('dispose marks watcher as inactive and closes stream', () async {
      // Act
      queryWatcher.dispose();
      
      // Assert
      expect(queryWatcher.stream, emitsDone);
      
      // Verify that notify doesn't do anything after dispose
      await queryWatcher.notify(mockDb);
      verifyNever(() => mockDb.rawQuery(any(), any()));
    });

    test('notify early returns if disposed during query execution', () async {
      // Arrange
      when(() => mockDb.rawQuery(testSql, testArgs)).thenAnswer((_) async {
        // Simulate disposal during query execution
        queryWatcher.dispose();
        return testResults;
      });

      // Act
      await queryWatcher.notify(mockDb);
      
      // Assert
      verify(() => mockDb.rawQuery(testSql, testArgs)).called(1);
      // No results should be added to the stream since it was disposed
    });

    test('notify early returns if disposed during error handling', () async {
      // Arrange
      final testError = Exception('Test error');
      when(() => mockDb.rawQuery(testSql, testArgs)).thenAnswer((_) async {
        // Simulate disposal during query execution
        queryWatcher.dispose();
        throw testError;
      });

      // Act
      await queryWatcher.notify(mockDb);
      
      // Assert
      verify(() => mockDb.rawQuery(testSql, testArgs)).called(1);
      // No error should be added to the stream since it was disposed
    });
  });
}