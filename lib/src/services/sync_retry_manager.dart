import 'dart:async';

class SyncRetryManager {
  static const _initialDelay = Duration(seconds: 1);
  static const _maxDelay = Duration(minutes: 5);
  static const _maxAttempts = 5;

  int _attempts = 0;
  Timer? _retryTimer;
  bool _isRetrying = false;

  Future<void> executeWithRetry(Future<void> Function() syncOperation) async {
    if (_isRetrying) return;

    try {
      _isRetrying = true;
      await syncOperation();
      _resetRetry();
    } catch (e) {
      if (_attempts >= _maxAttempts) {
        _resetRetry();
        rethrow;
      }

      final delay = _calculateDelay();
      _attempts++;

      _retryTimer?.cancel();
      _retryTimer = Timer(delay, () => executeWithRetry(syncOperation));
    } finally {
      _isRetrying = false;
    }
  }

  Duration _calculateDelay() {
    return Duration(
        milliseconds: (_initialDelay.inMilliseconds * (1 << _attempts))
            .clamp(0, _maxDelay.inMilliseconds));
  }

  void _resetRetry() {
    _attempts = 0;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void dispose() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }
}
