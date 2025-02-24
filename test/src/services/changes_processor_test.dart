import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pocketsync_flutter/src/database/database_change_manager.dart';
import 'package:pocketsync_flutter/src/services/changes_processor.dart';
import 'package:pocketsync_flutter/src/services/conflict_resolver.dart';
import 'package:sqflite/sqflite.dart';

import '../../fixtures/change_log_fixtures.dart';

class MockDatabase extends Mock implements Database {}

class MockDatabaseChangeManager extends Mock implements DatabaseChangeManager {}

class MockTransaction extends Mock implements Transaction {}

void main() {
  late MockDatabase mockDb;
  late MockDatabaseChangeManager mockChangeManager;
  late ConflictResolver conflictResolver;
  late ChangesProcessor processor;

  setUp(() {
    mockDb = MockDatabase();
    mockChangeManager = MockDatabaseChangeManager();
    conflictResolver = const ConflictResolver();
    processor = ChangesProcessor(
      mockDb,
      conflictResolver: conflictResolver,
      databaseChangeManager: mockChangeManager,
    );

    // Setup transaction mock
    final mockTxn = MockTransaction();
    when(() => mockDb.transaction(any())).thenAnswer((invocation) async {
      final Function(Transaction) transactionFn =
          invocation.positionalArguments[0];
      return await transactionFn(mockTxn);
    });
  });

  group('ChangesProcessor', () {
    group('applyRemoteChanges', () {
      test('should handle empty change logs', () async {
        // When
        await processor.applyRemoteChanges([]);

        // When
        verifyNever(() => mockDb.query(any()));
        verifyNever(() => mockChangeManager.notifyChange(any()));
      });

      test('should skip already processed changes', () async {
        // Given
        final changeLogs = [ChangeLogFixtures.insert];

        when(() => mockDb.query(
              '__pocketsync_processed_changes',
              columns: any(named: 'columns'),
              where: any(named: 'where'),
              whereArgs: any(named: 'whereArgs'),
            )).thenAnswer((_) async => [
              {'change_log_id': 1}
            ]);

        // When
        await processor.applyRemoteChanges(changeLogs);

        // When
        verify(() => mockDb.query(
              '__pocketsync_processed_changes',
              columns: any(named: 'columns'),
              where: any(named: 'where'),
              whereArgs: any(named: 'whereArgs'),
            )).called(1);

        verifyNever(() => mockDb.transaction(any()));
      });
    });
  });
}
