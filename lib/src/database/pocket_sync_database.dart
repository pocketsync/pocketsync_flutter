import 'dart:async';

import 'package:pocketsync_flutter/src/database/database_watcher.dart';
import 'package:pocketsync_flutter/src/database/pocket_sync_batch.dart';
import 'package:pocketsync_flutter/src/database/pocket_sync_transaction.dart';
import 'package:pocketsync_flutter/src/database/query_watcher.dart';
import 'package:pocketsync_flutter/src/engine/schema_manager.dart';
import 'package:pocketsync_flutter/src/types.dart';
import 'package:pocketsync_flutter/src/utils/sql_utils.dart';
import 'package:sqflite/sqflite.dart';

class PocketSyncDatabase extends DatabaseExecutor {
  Database? _db;
  final SchemaManager _schemaManager;
  final DatabaseWatcher _databaseWatcher;

  PocketSyncDatabase({required SchemaManager schemaManager})
      : _schemaManager = schemaManager,
        _databaseWatcher = DatabaseWatcher();

  @override
  Database get database => _db!;

  Future<void> initialize(
      DatabaseOptions options, TableChangeCallback onDatabaseChange) async {
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

    _databaseWatcher.setGlobalCallback(onDatabaseChange);
  }

  @override
  Batch batch() {
    final batch = database.batch();
    return PocketSyncBatch(batch);
  }

  Future<List<Object?>> commit(Batch batch) async {
    final result = await batch.commit();
    for (final mutation in (batch as PocketSyncBatch).mutations) {
      _databaseWatcher.notifyListeners(mutation.tableName, mutation.changeType);
    }
    return result;
  }

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

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) {
    _databaseWatcher.notifyListeners(table, ChangeType.delete);
    return database.delete(table, where: where, whereArgs: whereArgs);
  }

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

  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) {
    final tables = extractAffectedTables(sql);
    for (final table in tables) {
      _databaseWatcher.notifyListeners(table, ChangeType.delete);
    }
    return database.rawDelete(sql, arguments);
  }

  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) {
    final tables = extractAffectedTables(sql);
    for (final table in tables) {
      _databaseWatcher.notifyListeners(table, ChangeType.insert);
    }
    return database.rawInsert(sql, arguments);
  }

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

  @override
  Future<QueryCursor> rawQueryCursor(String sql, List<Object?>? arguments,
      {int? bufferSize}) {
    return database.rawQueryCursor(sql, arguments, bufferSize: bufferSize);
  }

  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) {
    final tables = extractAffectedTables(sql);
    for (final table in tables) {
      _databaseWatcher.notifyListeners(table, ChangeType.update);
    }
    return database.rawUpdate(sql, arguments);
  }

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

  Stream<List<Map<String, dynamic>>> watch(
    String sql, [
    List<Object?>? arguments,
  ]) {
    final queryKey = '$sql${arguments?.toString() ?? ''}';
    final tables = extractAffectedTables(sql);
    final watcher = QueryWatcher(sql, arguments, tables);
    _watchers.putIfAbsent(queryKey, () => []).add(watcher);

    // Initial query
    watcher.notify(this);

    // Set up change listeners for relevant tables
    void handleChange(String table, ChangeType _) {
      if (tables.contains(table)) {
        _debounceTimer?.cancel();
        _debounceTimer = Timer(const Duration(milliseconds: _debounceMs), () {
          watcher.notify(this);
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
