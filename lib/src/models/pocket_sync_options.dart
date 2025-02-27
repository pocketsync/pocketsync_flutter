import 'package:flutter/foundation.dart';
import 'package:pocketsync_flutter/pocketsync_flutter.dart';
import 'package:sqflite/sqflite.dart';

/// Options for configuring PocketSync
/// [projectId] - The project ID for the PocketSync project. This can be found in the PocketSync dashboard.
/// [authToken] - The auth token for the PocketSync project. This can be found in the PocketSync dashboard.
/// [serverUrl] - The URL of the PocketSync server. Default value is 'https://api.pocketsync.dev'.
/// [conflictResolver] - The conflict resolver to use when local and remote changes conflict. By default, conflicts are ignored and remote changes are applied.
/// [silent] - Whether to run in silent mode. In silent mode, no logs are printed to the console. Defaults to true in release mode and false in debug mode.
/// [syncPreExistingRecords] - Whether to automatically sync pre-existing records during initialization. When enabled, PocketSync will automatically create synthetic INSERT change records for all existing records in user tables that don't already have corresponding change records. This is useful when adding PocketSync to an existing app with data that needs to be synced. Defaults to true.
class PocketSyncOptions {
  /// The project ID for the PocketSync project. This can be found in the PocketSync dashboard.
  /// This is required.
  final String projectId;

  /// The auth token for the PocketSync project. This can be found in the PocketSync dashboard.
  final String authToken;

  /// The URL of the PocketSync server. This is required.
  /// Default value is 'https://api.pocketsync.dev'.
  final String? serverUrl;

  /// The conflict resolver to use when local and remote changes conflict.
  /// By default, conflicts are ignored and remote changes are applied.
  final ConflictResolver conflictResolver;

  /// Whether to run in silent mode. In silent mode, no logs are printed to the console.
  /// Defaults to true in release mode and false in debug mode.
  final bool silent;

  /// Whether to automatically sync pre-existing records during initialization.
  /// When enabled, PocketSync will automatically create synthetic INSERT change records
  /// for all existing records in user tables that don't already have corresponding change records.
  /// This is useful when adding PocketSync to an existing app with data that needs to be synced.
  /// Defaults to true.
  final bool syncPreExistingRecords;

  PocketSyncOptions({
    required this.projectId,
    required this.authToken,
    this.serverUrl = 'https://api.pocketsync.dev',
    this.conflictResolver = const ConflictResolver(),
    this.silent = !kDebugMode,
    this.syncPreExistingRecords = true,
  });
}

class DatabaseOptions {
  final int version;
  final OnDatabaseConfigureFn? onConfigure;
  final OnDatabaseCreateFn onCreate;
  final OnDatabaseVersionChangeFn? onUpgrade;
  final OnDatabaseVersionChangeFn? onDowngrade;
  final OnDatabaseOpenFn? onOpen;

  const DatabaseOptions({
    this.version = 1,
    required this.onCreate,
    this.onUpgrade,
    this.onConfigure,
    this.onDowngrade,
    this.onOpen,
  });
}
