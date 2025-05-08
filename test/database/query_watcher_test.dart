import 'package:flutter_test/flutter_test.dart';
import 'package:pocketsync_flutter/src/database/query_watcher.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite/sqflite.dart';

class MockDatabase extends Mock implements Database {}

void main() {
  group('QueryWatcher', () {
    late MockDatabase mockDb;
    late QueryWatcher queryWatcher;
    final testSql = 'SELECT * FROM users WHERE age > ?';
    final testArgs = [18];
    final testTables = {'users'};

    setUp(() {
      mockDb = MockDatabase();
      queryWatcher = QueryWatcher(testSql, testArgs, testTables);
    });

    tearDown(() {
      queryWatcher.dispose();
    });

    test('constructor initializes properties correctly', () {
      expect(queryWatcher.sql, equals(testSql));
      expect(queryWatcher.arguments, equals(testArgs));
      expect(queryWatcher.tables, equals(testTables));
    });

    test('stream emits query results when notify is called', () async {
      final testResults = [
        {'id': 1, 'name': 'John', 'age': 25},
        {'id': 2, 'name': 'Jane', 'age': 30}
      ];

      when(() => mockDb.rawQuery(testSql, testArgs))
          .thenAnswer((_) async => testResults);

      expectLater(
        queryWatcher.stream,
        emits(testResults),
      );

      await queryWatcher.notify(mockDb);

      verify(() => mockDb.rawQuery(testSql, testArgs)).called(1);
    });

    test('stream emits error when query fails', () async {
      final testError = Exception('Test error');

      when(() => mockDb.rawQuery(testSql, testArgs)).thenThrow(testError);

      expectLater(
        queryWatcher.stream,
        emitsError(isA<Exception>()),
      );

      await queryWatcher.notify(mockDb);

      verify(() => mockDb.rawQuery(testSql, testArgs)).called(1);
    });

    test('notify does nothing when watcher is disposed', () async {
      queryWatcher.dispose();

      await queryWatcher.notify(mockDb);

      verifyNever(() => mockDb.rawQuery(any(), any()));
    });
  });
}
