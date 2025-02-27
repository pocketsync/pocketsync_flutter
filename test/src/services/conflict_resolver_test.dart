import 'package:flutter_test/flutter_test.dart';
import 'package:pocketsync_flutter/src/services/conflict_resolver.dart';

void main() {
  group('ConflictResolver', () {
    final localRow = {'id': 1, 'name': 'Local Name', 'value': 100};
    final remoteRow = {'id': 1, 'name': 'Remote Name', 'value': 200};
    const tableName = 'test_table';

    test('should use remote row when strategy is ignore', () {
      final resolver =
          ConflictResolver(strategy: ConflictResolutionStrategy.ignore);
      final result = resolver.resolveConflict(tableName, localRow, remoteRow);
      expect(result, equals(remoteRow));
    });

    test('should use remote row when strategy is serverWins', () {
      final resolver =
          ConflictResolver(strategy: ConflictResolutionStrategy.serverWins);
      final result = resolver.resolveConflict(tableName, localRow, remoteRow);
      expect(result, equals(remoteRow));
    });

    test('should use local row when strategy is clientWins', () {
      final resolver =
          ConflictResolver(strategy: ConflictResolutionStrategy.clientWins);
      final result = resolver.resolveConflict(tableName, localRow, remoteRow);
      expect(result, equals(localRow));
    });

    test('should throw UnsupportedError when strategy is custom', () {
      // Define the custom resolver function properly
      customResolver(String tableName, Map<String, dynamic> localRow,
          Map<String, dynamic> remoteRow) async {
        return {'id': 1, 'name': 'Custom Name', 'value': 300};
      }

      final resolver = ConflictResolver(
        strategy: ConflictResolutionStrategy.custom,
        customResolver: customResolver,
      );

      expect(
        () => resolver.resolveConflict(tableName, localRow, remoteRow),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test(
        'should throw assertion error when custom strategy is used without resolver',
        () {
      expect(
        () => ConflictResolver(strategy: ConflictResolutionStrategy.custom),
        throwsA(isA<AssertionError>()),
      );
    });

    test('should use default strategy (ignore) when not specified', () {
      final resolver = ConflictResolver();
      expect(resolver.strategy, equals(ConflictResolutionStrategy.ignore));

      final result = resolver.resolveConflict(tableName, localRow, remoteRow);
      expect(result, equals(remoteRow));
    });
  });
}
