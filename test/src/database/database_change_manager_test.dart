import 'package:flutter_test/flutter_test.dart';
import 'package:pocketsync_flutter/src/database/database_change_manager.dart';

void main() {
  group('DatabaseChangeManager', () {
    late DatabaseChangeManager manager;

    setUp(() {
      manager = DatabaseChangeManager();
    });

    tearDown(() {
      manager.dispose();
    });

    test('addGlobalListener should register listener without duplicates', () {
      int callCount = 0;
      listener(String table, bool isRemote) => callCount++;

      // Add same listener twice
      manager.addGlobalListener(listener);
      manager.addGlobalListener(listener);

      manager.notifySync();
      expect(callCount, 1); // Should be called only once despite adding twice
    });

    test('removeGlobalListener should unregister listener', () {
      int callCount = 0;
      listener(String table, bool isRemote) => callCount++;

      manager.addGlobalListener(listener);
      manager.removeGlobalListener(listener);

      manager.notifySync();
      expect(callCount, 0);
    });

    test('addTableListener should register table-specific listener', () {
      int tableCallCount = 0;
      int otherTableCallCount = 0;

      manager.addTableListener('table1', (_, __) => tableCallCount++);
      manager.addTableListener('table2', (_, __) => otherTableCallCount++);

      manager.notifyChange('table1');
      
      // Wait for debounce timer
      Future.delayed(const Duration(milliseconds: 150), () {
        expect(tableCallCount, 1);
        expect(otherTableCallCount, 0);
      });
    });

    test('removeTableListener should unregister table-specific listener', () {
      int callCount = 0;
      listener(String table, bool isRemote) => callCount++;

      manager.addTableListener('table1', listener);
      manager.removeTableListener('table1', listener);

      manager.notifyChange('table1');
      
      // Wait for debounce timer
      Future.delayed(const Duration(milliseconds: 150), () {
        expect(callCount, 0);
      });
    });

    test('notifyChange should trigger both table and global listeners', () {
      int globalCallCount = 0;
      int tableCallCount = 0;

      manager.addGlobalListener((_, __) => globalCallCount++);
      manager.addTableListener('table1', (_, __) => tableCallCount++);

      manager.notifyChange('table1');
      
      // Wait for debounce timer
      Future.delayed(const Duration(milliseconds: 150), () {
        expect(globalCallCount, 1);
        expect(tableCallCount, 1);
      });
    });

    test('notifyChange should properly handle isRemote flag', () {
      bool? wasRemote;
      manager.addTableListener('table1', (_, isRemote) => wasRemote = isRemote);

      manager.notifyChange('table1', isRemote: true);
      
      // Wait for debounce timer
      Future.delayed(const Duration(milliseconds: 150), () {
        expect(wasRemote, true);
      });
    });

    test('dispose should cancel all listeners and timers', () {
      int globalCallCount = 0;
      int tableCallCount = 0;

      manager.addGlobalListener((_, __) => globalCallCount++);
      manager.addTableListener('table1', (_, __) => tableCallCount++);

      manager.dispose();

      manager.notifySync();
      manager.notifyChange('table1');
      
      // Wait for debounce timer
      Future.delayed(const Duration(milliseconds: 150), () {
        expect(globalCallCount, 0);
        expect(tableCallCount, 0);
      });
    });

    test('notifyChange should debounce multiple calls', () {
      int callCount = 0;
      manager.addTableListener('table1', (_, __) => callCount++);

      // Trigger multiple notifications in quick succession
      manager.notifyChange('table1');
      manager.notifyChange('table1');
      manager.notifyChange('table1');
      
      // Wait for debounce timer
      Future.delayed(const Duration(milliseconds: 150), () {
        expect(callCount, 1);
      });
    });
  });
}