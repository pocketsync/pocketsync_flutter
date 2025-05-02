/// Abstract base class for change listeners.
/// 
/// This class defines the interface for change listeners, which are used to 
/// listen for changes to the database (or remote changes) and trigger sync 
/// operations.
abstract class ChangeListener {
  /// Starts listening for changes.
  void startListening();

  /// Stops listening for changes.
  void stopListening();

  /// Disposes of resources used by the change listener.
  void dispose();
}