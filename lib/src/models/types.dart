import 'package:pocketsync_flutter/src/models/schema.dart';
import 'package:pocketsync_flutter/src/models/sync_change.dart';
import 'package:sqflite/sqflite.dart';

enum ChangeType {
  insert,
  update,
  delete,
}

typedef TableChangeCallback = void Function(
  String tableName,
  ChangeType changeType,
);

class DatabaseMutation {
  final String tableName;
  final ChangeType changeType;

  DatabaseMutation({required this.tableName, required this.changeType});

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DatabaseMutation &&
        other.tableName == tableName &&
        other.changeType == changeType;
  }

  @override
  int get hashCode => tableName.hashCode ^ changeType.hashCode;
}

/// Configuration options for PocketSync.
class PocketSyncOptions {
  /// The project ID obtained for your PocketSync dashboard.
  final String projectId;

  /// The authentication token.
  ///
  /// This is the token you get from the PocketSync dashboard.
  final String authToken;

  /// The server URL.
  ///
  /// This is the URL of the PocketSync server. Defaults to `https://api.pocketsync.dev`.
  final String serverUrl;

  /// The number of days to retain change logs.
  ///
  /// Defaults to 30 days.
  final int changeLogRetentionDays;

  /// Whether to sync existing data.
  ///
  /// Defaults to `true`.
  final bool syncExistingData;

  /// The conflict resolution strategy.
  ///
  /// Defaults to `lastWriteWins`.
  final ConflictResolutionStrategy conflictResolutionStrategy;

  /// A custom conflict resolver function.
  ///
  /// This is only used when `conflictResolutionStrategy` is set to `custom`.
  final ConflictResolver? customResolver;

  /// Whether to enable verbose logging.
  ///
  /// Defaults to `false`.
  final bool verbose;

  PocketSyncOptions({
    required this.projectId,
    required this.authToken,
    required this.serverUrl,
    this.changeLogRetentionDays = 30,
    this.syncExistingData = true,
    this.conflictResolutionStrategy = ConflictResolutionStrategy.lastWriteWins,
    this.customResolver,
    this.verbose = false,
  });
}

/// Configuration options for the database.
class DatabaseOptions {
  /// The database version.
  ///
  /// Defaults to 1.
  final int version;

  /// The path to the database file.
  ///
  /// This is the path to the SQLite database file.
  final String dbPath;

  /// The database schema.
  ///
  /// If provided, tables will be created automatically based on this schema.
  final DatabaseSchema schema;

  /// A callback function to configure the database.
  ///
  /// This is called when the database is first created.
  final OnDatabaseConfigureFn? onConfigure;

  /// A callback function to create the database.
  ///
  /// This is called when the database is first created.
  /// If [schema] is provided, it will be used to create tables before this callback is called.
  final OnDatabaseCreateFn? onCreate;

  /// A callback function to handle database version changes.
  ///
  /// This is called when the database version changes.
  final OnDatabaseVersionChangeFn? onUpgrade;

  /// A callback function to handle database downgrade.
  ///
  /// This is called when the database version is downgraded.
  final OnDatabaseVersionChangeFn? onDowngrade;

  /// A callback function to handle database opening.
  ///
  /// This is called when the database is opened.
  final OnDatabaseOpenFn? onOpen;

  const DatabaseOptions({
    this.version = 1,
    required this.dbPath,
    required this.schema,
    this.onCreate,
    this.onUpgrade,
    this.onConfigure,
    this.onDowngrade,
    this.onOpen,
  });
}

enum ConflictResolutionStrategy {
  /// Last-write-wins: most recent change based on timestamp wins
  lastWriteWins,

  /// Server changes always take precedence over local changes
  serverWins,

  /// Local/client changes always take precedence over server changes
  clientWins,

  /// Custom resolution strategy provided by the user
  custom,
}

typedef ConflictResolver = Future<SyncChange> Function(
  SyncChange localChange,
  SyncChange remoteChange,
);
