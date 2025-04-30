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

class PocketSyncOptions {
  final String projectId;
  final String authToken;
  final String serverUrl;

  PocketSyncOptions({
    required this.projectId,
    required this.authToken,
    required this.serverUrl,
  });
}

class DatabaseOptions {
  final int version;
  final String dbPath;
  final OnDatabaseConfigureFn? onConfigure;
  final OnDatabaseCreateFn onCreate;
  final OnDatabaseVersionChangeFn? onUpgrade;
  final OnDatabaseVersionChangeFn? onDowngrade;
  final OnDatabaseOpenFn? onOpen;

  const DatabaseOptions({
    this.version = 1,
    required this.dbPath,
    required this.onCreate,
    this.onUpgrade,
    this.onConfigure,
    this.onDowngrade,
    this.onOpen,
  });
}
