import 'package:flutter_test/flutter_test.dart';
import 'package:pocketsync_flutter/src/database/database_watcher.dart';
import 'package:pocketsync_flutter/src/models/types.dart';
import 'package:mocktail/mocktail.dart';

class MockTableChangeCallback extends Mock {
  void call(String tableName, ChangeType changeType);
}

class MockDatabaseChangeCallback extends Mock {
  void call(String tableName, ChangeType changeType, bool triggerSync);
}

void main() {
  setUpAll(() {
    // Register fallback values for mocktail
    registerFallbackValue(ChangeType.insert);
  });

  group('DatabaseWatcher', () {
    late DatabaseWatcher watcher;

    setUp(() {
      watcher = DatabaseWatcher();
    });

    tearDown(() {
      watcher.dispose();
    });

    test('setGlobalCallback sets the callback', () {
      final callback = MockDatabaseChangeCallback();
      watcher.setGlobalCallback(callback.call);

      watcher.notifyListeners('users', ChangeType.insert);

      verify(() => callback('users', ChangeType.insert, true)).called(1);
    });

    test('addListener adds a table-specific callback', () {
      final callback = MockTableChangeCallback();
      watcher.addListener('users', callback.call);

      watcher.notifyListeners('users', ChangeType.update);

      verify(() => callback('users', ChangeType.update)).called(1);
    });

    test('removeListener removes a table-specific callback', () {
      final callback = MockTableChangeCallback();
      watcher.addListener('users', callback.call);
      watcher.removeListener('users');

      watcher.notifyListeners('users', ChangeType.delete);

      verifyNever(() => callback(any(), any()));
    });

    test('notifyListeners calls both global and table-specific callbacks', () {
      final tableCallback = MockTableChangeCallback();
      final globalCallback = MockDatabaseChangeCallback();

      watcher.addListener('users', tableCallback.call);
      watcher.setGlobalCallback(globalCallback.call);

      watcher.notifyListeners('users', ChangeType.insert);

      verify(() => tableCallback('users', ChangeType.insert)).called(1);
      verify(() => globalCallback('users', ChangeType.insert, true)).called(1);
    });

    test('notifyListeners respects triggerSync parameter', () {
      final globalCallback = MockDatabaseChangeCallback();
      watcher.setGlobalCallback(globalCallback.call);

      watcher.notifyListeners('users', ChangeType.update, triggerSync: false);

      verify(() => globalCallback('users', ChangeType.update, false)).called(1);
    });

    test('notifyListeners does not call callback for unregistered table', () {
      final callback = MockTableChangeCallback();
      watcher.addListener('users', callback.call);

      watcher.notifyListeners('posts', ChangeType.delete);

      verifyNever(() => callback(any(), any()));
    });

    test('dispose clears all callbacks', () {
      final tableCallback = MockTableChangeCallback();
      final globalCallback = MockDatabaseChangeCallback();

      watcher.addListener('users', tableCallback.call);
      watcher.setGlobalCallback(globalCallback.call);

      watcher.dispose();

      watcher.notifyListeners('users', ChangeType.insert);

      verifyNever(() => tableCallback(any(), any()));
      verifyNever(() => globalCallback(any(), any(), any()));
    });
  });
}
