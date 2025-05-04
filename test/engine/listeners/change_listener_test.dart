import 'package:flutter_test/flutter_test.dart';
import 'package:pocketsync_flutter/src/engine/listeners/change_listener.dart';

// Create a concrete implementation of the abstract ChangeListener for testing
class TestChangeListener extends ChangeListener {
  bool isListening = false;
  int startCount = 0;
  int stopCount = 0;

  @override
  void startListening() {
    isListening = true;
    startCount++;
  }

  @override
  void stopListening() {
    isListening = false;
    stopCount++;
  }

  @override
  void dispose() {}
}

void main() {
  group('ChangeListener', () {
    late TestChangeListener listener;

    setUp(() {
      listener = TestChangeListener();
    });

    test('startListening sets listening state', () {
      expect(listener.isListening, false);

      listener.startListening();

      expect(listener.isListening, true);
      expect(listener.startCount, 1);
    });

    test('stopListening clears listening state', () {
      // First start listening
      listener.startListening();
      expect(listener.isListening, true);

      // Then stop
      listener.stopListening();

      expect(listener.isListening, false);
      expect(listener.stopCount, 1);
    });

    test('multiple start/stop calls work correctly', () {
      listener.startListening();
      listener.startListening();
      listener.stopListening();
      listener.startListening();
      listener.stopListening();
      listener.stopListening();

      expect(listener.startCount, 3);
      expect(listener.stopCount, 3);
      expect(listener.isListening, false);
    });
  });
}
