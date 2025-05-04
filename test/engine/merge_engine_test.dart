import 'package:flutter_test/flutter_test.dart';
import 'package:pocketsync_flutter/src/engine/merge_engine.dart';
import 'package:pocketsync_flutter/src/models/sync_change.dart';
import 'package:pocketsync_flutter/src/models/types.dart';

void main() {
  group('MergeEngine', () {
    late MergeEngine mergeEngine;
    final syncSessionId = 'test-session-123';
    
    setUp(() {
      // Default to lastWriteWins strategy
      mergeEngine = MergeEngine(
        strategy: ConflictResolutionStrategy.lastWriteWins,
      );
    });

    test('should initialize with default strategy', () {
      expect(mergeEngine.strategy, ConflictResolutionStrategy.lastWriteWins);
      expect(mergeEngine.customResolver, isNull);
    });

    test('should throw error when custom strategy is used without resolver', () {
      expect(
        () => MergeEngine(strategy: ConflictResolutionStrategy.custom),
        throwsArgumentError,
      );
    });

    group('resolveConflicts', () {
      test('should return single changes without conflicts', () async {
        // Arrange
        final localChanges = [
          SyncChange(
            id: '1',
            tableName: 'users',
            recordId: 'user1',
            operation: ChangeType.insert,
            data: {'new': {'name': 'User 1'}},
            timestamp: DateTime.now().millisecondsSinceEpoch,
            version: 1,
          ),
        ];
        
        final remoteChanges = [
          SyncChange(
            id: '2',
            tableName: 'products',
            recordId: 'product1',
            operation: ChangeType.insert,
            data: {'new': {'name': 'Product 1'}},
            timestamp: DateTime.now().millisecondsSinceEpoch,
            version: 1,
          ),
        ];
        
        // Act
        final result = await mergeEngine.resolveConflicts(
          localChanges,
          remoteChanges,
          syncSessionId,
          null,
        );
        
        // Assert
        expect(result.length, 2);
        expect(result.any((c) => c.id == '1'), isTrue);
        expect(result.any((c) => c.id == '2'), isTrue);
      });

      test('should resolve conflicts using lastWriteWins strategy', () async {
        // Arrange
        final now = DateTime.now();
        final earlier = now.subtract(const Duration(minutes: 5));
        
        final localChange = SyncChange(
          id: '1',
          tableName: 'users',
          recordId: 'user1',
          operation: ChangeType.update,
          data: {'old': {'name': 'Original'}, 'new': {'name': 'Local Update'}},
          timestamp: earlier.millisecondsSinceEpoch, // Local change is older
          version: 1,
        );
        
        final remoteChange = SyncChange(
          id: '2',
          tableName: 'users',
          recordId: 'user1',
          operation: ChangeType.update,
          data: {'old': {'name': 'Original'}, 'new': {'name': 'Remote Update'}},
          timestamp: now.millisecondsSinceEpoch, // Remote change is newer
          version: 2,
        );
        
        // Act
        final result = await mergeEngine.resolveConflicts(
          [localChange],
          [remoteChange],
          syncSessionId,
          null,
        );
        
        // Assert
        expect(result.length, 1);
        expect(result[0].id, '2'); // Remote change should win (newer timestamp)
      });

      test('should resolve conflicts using serverWins strategy', () async {
        // Arrange
        mergeEngine = MergeEngine(
          strategy: ConflictResolutionStrategy.serverWins,
        );
        
        final now = DateTime.now();
        
        final localChange = SyncChange(
          id: '1',
          tableName: 'users',
          recordId: 'user1',
          operation: ChangeType.update,
          data: {'old': {'name': 'Original'}, 'new': {'name': 'Local Update'}},
          timestamp: now.add(const Duration(minutes: 5)).millisecondsSinceEpoch, // Local change is newer
          version: 2,
        );
        
        final remoteChange = SyncChange(
          id: '2',
          tableName: 'users',
          recordId: 'user1',
          operation: ChangeType.update,
          data: {'old': {'name': 'Original'}, 'new': {'name': 'Remote Update'}},
          timestamp: now.millisecondsSinceEpoch, // Remote change is older
          version: 1,
        );
        
        // Act
        final result = await mergeEngine.resolveConflicts(
          [localChange],
          [remoteChange],
          syncSessionId,
          null,
        );
        
        // Assert
        expect(result.length, 1);
        expect(result[0].id, '2'); // Remote change should win (server wins)
      });

      test('should resolve conflicts using clientWins strategy', () async {
        // Arrange
        mergeEngine = MergeEngine(
          strategy: ConflictResolutionStrategy.clientWins,
        );
        
        final now = DateTime.now();
        
        final localChange = SyncChange(
          id: '1',
          tableName: 'users',
          recordId: 'user1',
          operation: ChangeType.update,
          data: {'old': {'name': 'Original'}, 'new': {'name': 'Local Update'}},
          timestamp: now.millisecondsSinceEpoch, // Local change is older
          version: 1,
        );
        
        final remoteChange = SyncChange(
          id: '2',
          tableName: 'users',
          recordId: 'user1',
          operation: ChangeType.update,
          data: {'old': {'name': 'Original'}, 'new': {'name': 'Remote Update'}},
          timestamp: now.add(const Duration(minutes: 5)).millisecondsSinceEpoch, // Remote change is newer
          version: 2,
        );
        
        // Act
        final result = await mergeEngine.resolveConflicts(
          [localChange],
          [remoteChange],
          syncSessionId,
          null,
        );
        
        // Assert
        expect(result.length, 1);
        expect(result[0].id, '1'); // Local change should win (client wins)
      });

      test('should resolve conflicts using custom resolver', () async {
        // Arrange
        mergeEngine = MergeEngine(
          strategy: ConflictResolutionStrategy.custom,
          customResolver: (localChange, remoteChange) async {
            // Custom logic: always choose the change with the higher version
            if (localChange.version > remoteChange.version) {
              return localChange;
            } else {
              return remoteChange;
            }
          },
        );
        
        final now = DateTime.now();
        
        final localChange = SyncChange(
          id: '1',
          tableName: 'users',
          recordId: 'user1',
          operation: ChangeType.update,
          data: {'old': {'name': 'Original'}, 'new': {'name': 'Local Update'}},
          timestamp: now.add(const Duration(minutes: 10)).millisecondsSinceEpoch, // Local change is newer
          version: 1, // But has lower version
        );
        
        final remoteChange = SyncChange(
          id: '2',
          tableName: 'users',
          recordId: 'user1',
          operation: ChangeType.update,
          data: {'old': {'name': 'Original'}, 'new': {'name': 'Remote Update'}},
          timestamp: now.millisecondsSinceEpoch, // Remote change is older
          version: 2, // But has higher version
        );
        
        // Act
        final result = await mergeEngine.resolveConflicts(
          [localChange],
          [remoteChange],
          syncSessionId,
          null,
        );
        
        // Assert
        expect(result.length, 1);
        expect(result[0].id, '2'); // Remote change should win (higher version)
      });

      test('should call conflict notification callback when conflicts are detected', () async {
        // Arrange
        var callbackCalled = false;
        var callbackStrategy = ConflictResolutionStrategy.lastWriteWins;
        var callbackWinningChange = '';
        
        final now = DateTime.now();
        final earlier = now.subtract(const Duration(minutes: 5));
        
        final localChange = SyncChange(
          id: '1',
          tableName: 'users',
          recordId: 'user1',
          operation: ChangeType.update,
          data: {'old': {'name': 'Original'}, 'new': {'name': 'Local Update'}},
          timestamp: earlier.millisecondsSinceEpoch, // Local change is older
          version: 1,
        );
        
        final remoteChange = SyncChange(
          id: '2',
          tableName: 'users',
          recordId: 'user1',
          operation: ChangeType.update,
          data: {'old': {'name': 'Original'}, 'new': {'name': 'Remote Update'}},
          timestamp: now.millisecondsSinceEpoch, // Remote change is newer
          version: 2,
        );
        
        // Act
        await mergeEngine.resolveConflicts(
          [localChange],
          [remoteChange],
          syncSessionId,
          (strategy, local, remote, winning, sessionId) {
            callbackCalled = true;
            callbackStrategy = strategy;
            callbackWinningChange = winning.id;
          },
        );
        
        // Assert
        expect(callbackCalled, isTrue);
        expect(callbackStrategy, ConflictResolutionStrategy.lastWriteWins);
        expect(callbackWinningChange, '2'); // Remote change should win (newer timestamp)
      });
    });

    group('mergeChanges', () {
      test('should delegate to resolveConflicts', () async {
        // Arrange
        final localChanges = [
          SyncChange(
            id: '1',
            tableName: 'users',
            recordId: 'user1',
            operation: ChangeType.update,
            data: {'old': {'name': 'Original'}, 'new': {'name': 'Local Update'}},
            timestamp: DateTime.now().millisecondsSinceEpoch,
            version: 1,
          ),
        ];
        
        final remoteChanges = [
          SyncChange(
            id: '2',
            tableName: 'products',
            recordId: 'product1',
            operation: ChangeType.insert,
            data: {'new': {'name': 'Product 1'}},
            timestamp: DateTime.now().millisecondsSinceEpoch,
            version: 1,
          ),
        ];
        
        // Act
        final result = await mergeEngine.mergeChanges(
          localChanges,
          remoteChanges,
          syncSessionId,
          null,
        );
        
        // Assert
        expect(result.length, 2);
        expect(result.any((c) => c.id == '1'), isTrue);
        expect(result.any((c) => c.id == '2'), isTrue);
      });
    });
  });
}
