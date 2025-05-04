import 'dart:async';

import 'package:pocketsync_flutter/src/database/database_watcher.dart';
import 'package:pocketsync_flutter/src/database/pocket_sync_batch.dart';
import 'package:pocketsync_flutter/src/database/pocket_sync_transaction.dart';
import 'package:pocketsync_flutter/src/database/query_watcher.dart';
import 'package:pocketsync_flutter/src/engine/schema_manager.dart';
import 'package:pocketsync_flutter/src/models/types.dart';
import 'package:pocketsync_flutter/src/utils/sql_utils.dart';
import 'package:sqflite/sqflite.dart';

/// A database instance that extends [DatabaseExecutor] and provides additional

class PocketSyncDatabase extends DatabaseExecutor {
  Database? _db;
  final SchemaManager _schemaManager;

  PocketSyncDatabase({required SchemaManager schemaManager})
      : _schemaManager = schemaManager;

  late final DatabaseWatcher _databaseWatcher;

  /// Flag to track if database watcher is already initialized
  bool _databaseWatcherInitialized = false;

  @override
  Database get database => _db!;

  /// Initializes the database.
  ///
  /// This method must be called before using any other database methods.
  ///
  /// [options] The configuration options for the database.
  /// [databaseWatcher] The database watcher to be used for change notifications.
  Future<void> initialize(
      DatabaseOptions options, DatabaseWatcher databaseWatcher) async {
    _db = await databaseFactory.openDatabase(
      options.dbPath,
      options: OpenDatabaseOptions(
        version: options.version,
        onConfigure: (db) async {
          await options.onConfigure?.call(db);
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await _schemaManager.initializePocketSyncTables(db);

          await options.onCreate(db, version);
          await _schemaManager.setupChangeTracking(db);
        },
        onDowngrade: (db, oldVersion, newVersion) async {
          await options.onDowngrade?.call(db, oldVersion, newVersion);

          await _schemaManager.handleSchemaChanges(db);
          await _schemaManager.setupChangeTracking(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          await options.onUpgrade?.call(db, oldVersion, newVersion);

          await _schemaManager.handleSchemaChanges(db);
          await _schemaManager.setupChangeTracking(db);
        },
        onOpen: (db) async {
          await options.onOpen?.call(db);

          await _schemaManager.initializePocketSyncTables(db);
          await _schemaManager.setupChangeTracking(db);
        },
        singleInstance: true,
      ),
    );
    // Only set the database watcher if it hasn't been initialized already
    if (!_databaseWatcherInitialized) {
      _databaseWatcher = databaseWatcher;
      _databaseWatcherInitialized = true;
    }
  }

  /// Returns a new batch for database operations.
  ///
  /// This method creates a new batch that can be used to perform multiple
  /// database operations in a single transaction.
  @override
  Batch batch() {
    final batch = database.batch();
    return PocketSyncBatch(batch);
  }

  /// Commits a batch of database operations.
  ///
  /// This method commits a batch of database operations and notifies the
  /// database watcher of any changes.
  Future<List<Object?>> commit(Batch batch) async {
    final result = await batch.commit();
    for (final mutation in (batch as PocketSyncBatch).mutations) {
      _databaseWatcher.notifyListeners(mutation.tableName, mutation.changeType);
    }
    return result;
  }

  /// Performs a database transaction.
  ///
  /// This method performs a database transaction and notifies the database
  /// watcher of any changes.
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action) async {
    final mutations = <DatabaseMutation>{};
    final result = await _db!.transaction((txn) async {
      try {
        return await action(PocketSyncTransaction(txn, mutations));
      } catch (e) {
        rethrow;
      }
    });

    for (final mutation in mutations) {
      _databaseWatcher.notifyListeners(mutation.tableName, mutation.changeType);
    }

    return result;
  }

  /// Performs a database delete operation.
  ///
  /// This method performs a database delete operation and notifies the
  /// database watcher of the change.
  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) {
    _databaseWatcher.notifyListeners(table, ChangeType.delete);
    return database.delete(table, where: where, whereArgs: whereArgs);
  }

  /// Performs a database execute operation.
  ///
  /// This method performs a database execute operation and notifies the
  /// database watcher of any changes.
  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) {
    if (determineChangeType(sql) != null) {
      final tables = extractAffectedTables(sql);
      for (final table in tables) {
        _databaseWatcher.notifyListeners(table, determineChangeType(sql)!);
      }
    }
    return database.execute(sql, arguments);
  }

  /// Performs a database insert operation.
  ///
  /// This method performs a database insert operation and notifies the
  /// database watcher of the change.
  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) {
    _databaseWatcher.notifyListeners(table, ChangeType.insert);
    return database.insert(table, values,
        nullColumnHack: nullColumnHack, conflictAlgorithm: conflictAlgorithm);
  }

  /// Performs a database query operation.
  ///
  /// This method performs a database query operation and does not notify the
  /// database watcher of any changes.
  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    return database.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  /// Performs a database query cursor operation.
  ///
  /// This method performs a database query cursor operation and does not notify
  /// the database watcher of any changes.
  @override
  Future<QueryCursor> queryCursor(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
    int? bufferSize,
  }) {
    return database.queryCursor(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
      bufferSize: bufferSize,
    );
  }

  /// Performs a database raw delete operation.
  ///
  /// This method performs a database raw delete operation and notifies the
  /// database watcher of the change.
  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) {
    final tables = extractAffectedTables(sql);
    for (final table in tables) {
      _databaseWatcher.notifyListeners(table, ChangeType.delete);
    }
    return database.rawDelete(sql, arguments);
  }

  /// Performs a database raw insert operation.
  ///
  /// This method performs a database raw insert operation and notifies the
  /// database watcher of the change.
  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) {
    final tables = extractAffectedTables(sql);
    for (final table in tables) {
      _databaseWatcher.notifyListeners(table, ChangeType.insert);
    }
    return database.rawInsert(sql, arguments);
  }

  /// Performs a database raw query operation.
  ///
  /// This method performs a database raw query operation and does not notify
  /// the database watcher of any changes.
  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql,
      [List<Object?>? arguments]) {
    final changeType = determineChangeType(sql);
    if (changeType != null) {
      final tables = extractAffectedTables(sql);
      for (final table in tables) {
        _databaseWatcher.notifyListeners(table, changeType);
      }
    }
    return database.rawQuery(sql, arguments);
  }

  /// Performs a database raw query cursor operation.
  ///
  /// This method performs a database raw query cursor operation and does not
  /// notify the database watcher of any changes.
  @override
  Future<QueryCursor> rawQueryCursor(String sql, List<Object?>? arguments,
      {int? bufferSize}) {
    return database.rawQueryCursor(sql, arguments, bufferSize: bufferSize);
  }

  /// Performs a database raw update operation.
  ///
  /// This method performs a database raw update operation and notifies the
  /// database watcher of the change.
  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) {
    final tables = extractAffectedTables(sql);
    for (final table in tables) {
      _databaseWatcher.notifyListeners(table, ChangeType.update);
    }
    return database.rawUpdate(sql, arguments);
  }

  /// Performs a database update operation.
  ///
  /// This method performs a database update operation and notifies the
  /// database watcher of the change.
  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) {
    _databaseWatcher.notifyListeners(table, ChangeType.update);
    return database.update(
      table,
      values,
      where: where,
      whereArgs: whereArgs,
      conflictAlgorithm: conflictAlgorithm,
    );
  }

  /// Closes the database.
  ///
  /// This method must be called to close the database.
  void close() {
    _databaseWatcher.dispose();
    database.close();
  }
}

extension WatchExtension on PocketSyncDatabase {
  static final Map<PocketSyncDatabase, Map<String, List<QueryWatcher>>>
      _watchersByDb = {};
  static final Map<PocketSyncDatabase, Timer?> _debounceTimers = {};
  static const _debounceMs = 50;

  Map<String, List<QueryWatcher>> get _watchers =>
      _watchersByDb.putIfAbsent(this, () => {});

  Timer? get _debounceTimer => _debounceTimers[this];
  set _debounceTimer(Timer? timer) => _debounceTimers[this] = timer;

  /// Watches for changes in the database.
  ///
  /// This method returns a stream of changes to the database.
  ///
  /// [sql] The SQL query to watch.
  /// [arguments] The arguments for the SQL query.
  Stream<List<Map<String, dynamic>>> watch(
    String sql, [
    List<Object?>? arguments,
  ]) {
    final queryKey = '$sql${arguments?.toString() ?? ''}';
    final tables = extractAffectedTables(sql);
    final watcher = QueryWatcher(sql, arguments, tables);
    _watchers.putIfAbsent(queryKey, () => []).add(watcher);

    // Initial query
    watcher.notify(database);

    // Set up change listeners for relevant tables
    void handleChange(String table, ChangeType _) {
      if (tables.contains(table)) {
        _debounceTimer?.cancel();
        _debounceTimer = Timer(const Duration(milliseconds: _debounceMs), () {
          watcher.notify(database);
        });
      }
    }

    // Add listeners for each table
    for (final table in tables) {
      _databaseWatcher.addListener(table, handleChange);
    }

    return watcher.stream.transform(
      StreamTransformer.fromHandlers(
        handleDone: (sink) {
          // Clean up resources
          for (final table in tables) {
            _databaseWatcher.removeListener(table);
          }

          final watchers = _watchers[queryKey];
          if (watchers != null) {
            watchers.remove(watcher);
            if (watchers.isEmpty) {
              _watchers.remove(queryKey);
            }
          }

          if (_watchers.isEmpty) {
            _debounceTimer?.cancel();
            _debounceTimer = null;
            _watchersByDb.remove(this);
            _debounceTimers.remove(this);
          }

          watcher.dispose();
          sink.close();
        },
      ),
    );
  }
}
