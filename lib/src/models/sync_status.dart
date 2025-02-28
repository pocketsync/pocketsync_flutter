/// Represents the current state of the synchronization process
enum SyncStatus {
  /// Initial state when PocketSync is not yet initialized.
  /// This state indicates that the system has not been initialized yet.
  idle,

  /// Active state when PocketSync is currently synchronizing changes
  /// with the server. In this state, local changes are being processed
  /// and sent to the remote server.
  syncing,

  /// State when synchronization is temporarily stopped.
  /// This can occur due to manual pause, loss of connectivity,
  /// or when cleaning up resources. In this state, changes are still
  /// tracked but not synchronized until resumed.
  paused,
}
