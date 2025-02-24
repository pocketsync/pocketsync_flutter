import 'package:flutter_test/flutter_test.dart';
import 'package:pocketsync_flutter/src/models/change_set.dart';
import 'package:pocketsync_flutter/src/services/sync_task_queue.dart';
import '../../fixtures/change_set_fixtures.dart';

void main() {
  group('SyncTaskQueue', () {
    late SyncTaskQueue queue;
    late List<ChangeSet> processedChanges;

    setUp(() {
      processedChanges = [];
      queue = SyncTaskQueue(
        processChanges: (changes) async {
          processedChanges.add(changes);
        },
        debounceDuration: const Duration(milliseconds: 100),
      );
    });

    tearDown(() {
      queue.dispose();
    });

    test('enqueues and processes a single task', () async {
      final changes = ChangeSetFixtures.withInsertions;
      await queue.enqueue(changes);
      await Future.delayed(const Duration(milliseconds: 150));

      expect(processedChanges.length, 1);
      expect(processedChanges.first.insertions.changes,
          changes.insertions.changes);
    });

    test('debounces multiple tasks', () async {
      final changes1 = ChangeSetFixtures.withInsertions;
      final changes2 = ChangeSetFixtures.withUpdates;

      await Future.wait([
        queue.enqueue(changes1),
        queue.enqueue(changes2),
      ]);

      await Future.delayed(const Duration(milliseconds: 150));

      expect(processedChanges.length, 1);
      expect(
        processedChanges.first.localChangeIds,
        containsAll([...changes1.localChangeIds, ...changes2.localChangeIds]),
      );
    });

    test('handles processing errors with retry', () async {
      int attempts = 0;
      queue = SyncTaskQueue(
        processChanges: (changes) async {
          attempts++;
          if (attempts < 2) {
            throw Exception('Test error');
          }
          processedChanges.add(changes);
        },
        debounceDuration: const Duration(milliseconds: 100),
      );

      final changes = ChangeSetFixtures.withMultipleChanges;
      await queue.enqueue(changes);
      await Future.delayed(const Duration(milliseconds: 150));

      expect(attempts, 2);
      expect(processedChanges.length, 1);
      expect(processedChanges.first.serverChangeIds, changes.serverChangeIds);
    });

    test('merges changes correctly', () async {
      final changes1 = ChangeSetFixtures.withUpdates;
      final changes2 = ChangeSetFixtures.withMultipleChanges;

      await Future.wait([
        queue.enqueue(changes1),
        queue.enqueue(changes2),
      ]);

      await Future.delayed(const Duration(milliseconds: 150));

      expect(processedChanges.length, 1);
      final mergedChanges = processedChanges.first;

      // Verify insertions and updates are merged
      expect(mergedChanges.insertions.changes.isNotEmpty, true);
      expect(mergedChanges.updates.changes.isNotEmpty, true);
    });
  });
}
