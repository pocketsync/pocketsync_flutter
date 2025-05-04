import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pocketsync_flutter/src/engine/sync_queue.dart';
import 'package:pocketsync_flutter/src/engine/sync_scheduler.dart';
import 'package:pocketsync_flutter/src/models/types.dart';

class MockSyncQueue extends Mock implements SyncQueue {}

void main() {
  group('SyncScheduler', () {
    late SyncScheduler syncScheduler;
    late MockSyncQueue mockSyncQueue;
    late bool syncCalled;

    setUp(() {
      mockSyncQueue = MockSyncQueue();
      syncCalled = false;
      
      // Setup default behavior for mockSyncQueue
      when(() => mockSyncQueue.isEmpty).thenReturn(false);
      
      syncScheduler = SyncScheduler(
        syncQueue: mockSyncQueue,
        onSyncRequired: () async {
          syncCalled = true;
        },
        // Use a very short debounce interval for testing
        debounceInterval: const Duration(milliseconds: 50),
      );
    });

    tearDown(() {
      syncScheduler.dispose();
    });

    test('should initialize with correct properties', () {
      expect(syncScheduler, isNotNull);
    });

    group('scheduleUpload', () {
      test('should add local change to queue', () async {
        // Act
        syncScheduler.scheduleUpload('users', ChangeType.insert);
        
        // Assert
        verify(() => mockSyncQueue.addLocalChange('users', ChangeType.insert)).called(1);
      });

      test('should trigger sync after debounce interval', () async {
        // Arrange
        when(() => mockSyncQueue.isEmpty).thenReturn(false);
        
        // Act
        syncScheduler.scheduleUpload('users', ChangeType.insert);
        
        // Assert - Initially sync should not be called
        expect(syncCalled, isFalse);
        
        // Wait for debounce interval to pass
        await Future.delayed(const Duration(milliseconds: 100));
        
        // Now sync should be called
        expect(syncCalled, isTrue);
      });

      test('should not trigger sync if queue is empty', () async {
        // Arrange
        when(() => mockSyncQueue.isEmpty).thenReturn(true);
        
        // Act
        syncScheduler.scheduleUpload('users', ChangeType.insert);
        
        // Wait for debounce interval to pass
        await Future.delayed(const Duration(milliseconds: 100));
        
        // Assert
        expect(syncCalled, isFalse);
      });

      test('should reset timer when multiple changes occur', () async {
        // Arrange
        when(() => mockSyncQueue.isEmpty).thenReturn(false);
        
        // Act - Schedule first upload
        syncScheduler.scheduleUpload('users', ChangeType.insert);
        
        // Wait a bit, but not enough to trigger sync
        await Future.delayed(const Duration(milliseconds: 20));
        
        // Schedule another upload - this should reset the timer
        syncScheduler.scheduleUpload('products', ChangeType.update);
        
        // Wait a bit more, but still not enough for the second timer
        await Future.delayed(const Duration(milliseconds: 40));
        
        // Assert - Sync should not be called yet
        expect(syncCalled, isFalse);
        
        // Wait for the full debounce interval from the second call
        await Future.delayed(const Duration(milliseconds: 60));
        
        // Now sync should be called
        expect(syncCalled, isTrue);
      });
    });

    group('scheduleDownload', () {
      test('should add remote change to queue', () {
        // Act
        syncScheduler.scheduleDownload();
        
        // Assert
        verify(() => mockSyncQueue.addRemoteChange()).called(1);
      });

      test('should trigger sync after debounce interval', () async {
        // Arrange
        when(() => mockSyncQueue.isEmpty).thenReturn(false);
        
        // Act
        syncScheduler.scheduleDownload();
        
        // Assert - Initially sync should not be called
        expect(syncCalled, isFalse);
        
        // Wait for debounce interval to pass
        await Future.delayed(const Duration(milliseconds: 100));
        
        // Now sync should be called
        expect(syncCalled, isTrue);
      });
    });

    group('forceSyncNow', () {
      test('should trigger sync immediately', () async {
        // Act
        await syncScheduler.forceSyncNow();
        
        // Assert
        expect(syncCalled, isTrue);
      });

      test('should cancel existing timers', () async {
        // Arrange
        syncScheduler.scheduleUpload('users', ChangeType.insert);
        
        // Act
        await syncScheduler.forceSyncNow();
        
        // Reset the flag
        syncCalled = false;
        
        // Wait for the original debounce interval
        await Future.delayed(const Duration(milliseconds: 100));
        
        // Assert - The original timer should have been cancelled
        expect(syncCalled, isFalse);
      });
    });

    test('dispose should cancel timers', () async {
      // Arrange
      syncScheduler.scheduleUpload('users', ChangeType.insert);
      
      // Act
      syncScheduler.dispose();
      
      // Wait for the debounce interval
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Assert - Sync should not be called because timers were cancelled
      expect(syncCalled, isFalse);
    });
  });
}
