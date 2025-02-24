import 'package:flutter_test/flutter_test.dart';
import 'package:pocketsync_flutter/src/services/sync_retry_manager.dart';
import 'package:fake_async/fake_async.dart';

void main() {
  group('SyncRetryManager', () {
    late SyncRetryManager retryManager;

    setUp(() {
      retryManager = SyncRetryManager();
    });

    tearDown(() {
      retryManager.dispose();
    });

    test('successful operation completes without retries', () async {
      int callCount = 0;
      await retryManager.executeWithRetry(() async {
        callCount++;
      });

      expect(callCount, 1);
    });

    test('cancels retry timer on dispose', () {
      fakeAsync((async) {
        int callCount = 0;

        // Start an operation that will fail
        retryManager.executeWithRetry(() async {
          callCount++;
          throw Exception('Test error');
        }).catchError((_) {});

        // Elapse time for first attempt
        async.elapse(const Duration(milliseconds: 100));

        // Dispose before all retries complete
        retryManager.dispose();

        // Elapse time to ensure no more retries occur
        async.elapse(const Duration(seconds: 1));

        // Should only have the initial attempt and possibly one retry
        expect(callCount, lessThan(3));
      });
    });
  });
}
