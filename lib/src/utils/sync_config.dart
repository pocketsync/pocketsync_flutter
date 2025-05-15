class SyncConfig {
  /// Default debounce interval for sync operations.
  static const Duration defaultDebounceInterval = Duration(seconds: 3);

  /// Default maximum number of changes to upload in a single batch.
  static const int defaultMaxBatchSize = 1000;

  /// Default column name for global IDs.
  static const String defaultGlobalIdColumnName = 'ps_global_id';

  /// Plugin version.
  static const String pluginVersion = '0.5.0';
}
