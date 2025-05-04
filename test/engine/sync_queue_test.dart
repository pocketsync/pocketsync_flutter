import 'package:flutter_test/flutter_test.dart';
import 'package:pocketsync_flutter/src/engine/sync_queue.dart';
import 'package:pocketsync_flutter/src/models/sync_change.dart';
import 'package:pocketsync_flutter/src/models/types.dart';

void main() {
  group('SyncQueue', () {
    late SyncQueue syncQueue;

    setUp(() {
      syncQueue = SyncQueue();
    });

    test('should be empty when initialized', () {
      expect(syncQueue.isEmpty, isTrue);
      expect(syncQueue.hasDownloads, isFalse);
      expect(syncQueue.getTablesWithPendingUploads(), isEmpty);
    });

    group('local changes', () {
      test('should add local changes correctly', () {
        // Act
        syncQueue.addLocalChange('users', ChangeType.insert);
        syncQueue.addLocalChange('products', ChangeType.update);
        
        // Assert
        expect(syncQueue.isEmpty, isFalse);
        expect(syncQueue.getTablesWithPendingUploads(), containsAll(['users', 'products']));
      });

      test('should add multiple change types for the same table', () {
        // Act
        syncQueue.addLocalChange('users', ChangeType.insert);
        syncQueue.addLocalChange('users', ChangeType.update);
        
        // Assert
        expect(syncQueue.getTablesWithPendingUploads(), ['users']);
      });

      test('should mark table as uploaded', () {
        // Arrange
        syncQueue.addLocalChange('users', ChangeType.insert);
        syncQueue.addLocalChange('products', ChangeType.update);
        
        // Act
        syncQueue.markTableUploaded('users');
        
        // Assert
        expect(syncQueue.getTablesWithPendingUploads(), ['products']);
      });
    });

    group('remote changes', () {
      test('should add remote change notification', () {
        // Act
        syncQueue.addRemoteChange();
        
        // Assert
        expect(syncQueue.hasDownloads, isTrue);
        expect(syncQueue.isEmpty, isFalse);
      });

      test('should mark download as processed', () {
        // Arrange
        syncQueue.addRemoteChange();
        
        // Act
        syncQueue.markDownloadProcessed();
        
        // Assert
        expect(syncQueue.hasDownloads, isFalse);
      });

      test('should add remote changes list', () {
        // Arrange
        final changes = [
          SyncChange(
            id: '1',
            tableName: 'users',
            recordId: 'user1',
            operation: ChangeType.insert,
            data: {'new': {'name': 'User 1'}},
            timestamp: DateTime.now().millisecondsSinceEpoch,
            version: 1,
          ),
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
        syncQueue.addRemoteChanges(changes);
        
        // Assert
        expect(syncQueue.getRemoteChanges().length, 2);
      });

      test('should clear remote changes', () {
        // Arrange
        final changes = [
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
        syncQueue.addRemoteChanges(changes);
        
        // Act
        syncQueue.clearRemoteChanges();
        
        // Assert
        expect(syncQueue.getRemoteChanges(), isEmpty);
      });
    });

    test('isEmpty should return true when no changes exist', () {
      // Arrange
      syncQueue.addLocalChange('users', ChangeType.insert);
      syncQueue.addRemoteChange();
      
      // Act
      syncQueue.markTableUploaded('users');
      syncQueue.markDownloadProcessed();
      
      // Assert
      expect(syncQueue.isEmpty, isTrue);
    });
  });
}
