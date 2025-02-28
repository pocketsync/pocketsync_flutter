import 'dart:async';

import 'package:meta/meta.dart';
import 'package:pocketsync_flutter/pocketsync_flutter.dart';
import 'package:pocketsync_flutter/src/database/database_change_manager.dart';
import 'package:pocketsync_flutter/src/database/pocket_sync_database_initializer.dart';
import 'package:pocketsync_flutter/src/database/query_watcher.dart';
import 'package:pocketsync_flutter/src/database/transaction_wrapper.dart';
import 'package:pocketsync_flutter/src/utils/table_utils.dart';
import 'package:sqflite/sqflite.dart';

import 'pocket_sync_batch.dart';

/// PocketSync database service for managing local database operations
/// with the ability to track changes and sync them with a remote server
class PocketSyncDatabase extends DatabaseExecutor {
  final DatabaseChangeManager _changeManager;
  final PocketSyncDatabaseInitializer _initializer;
  Database? _db;

  PocketSyncDatabase({
    DatabaseChangeManager? changeManager,
    PocketSyncDatabaseInitializer? initializer,
  })  : _changeManager = changeManager ?? DatabaseChangeManager(),
        _initializer = initializer ?? PocketSyncDatabaseInitializer();

  @override
  Database get database => _db!;

  /// Opens and initializes the database
  @internal
  Future<Database> initialize({
    required String dbPath,
    required DatabaseOptions options,
    required bool syncPreExistingRecords,
  }) async {
    _db = await openDatabase(
      dbPath,
      version: options.version,
      onConfigure: (db) async {
        await options.onConfigure?.call(db);
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _initializer.initializePocketSyncTables(db);

        await options.onCreate(db, version);

        await _initializer.setupChangeTracking(db);
        await _initializer.initializeTableVersions(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _initializer.backupTriggers(db);
        await _initializer.dropChangeTracking(db);

        await options.onUpgrade?.call(db, oldVersion, newVersion);

        await _initializer.setupChangeTracking(db);
        await _initializer.updateTableVersions(db);
      },
      onOpen: (db) async {
        await options.onOpen?.call(db);

        await _initializer.initializePocketSyncTables(db);
        await _initializer.verifyChangeTracking(db);

        if (syncPreExistingRecords) {
          await _initializer.syncPreExistingRecords(db);
        }
      },
      singleInstance: true,
    );
    return _db!;
  }

  Future<T> transaction<T>(Future<T> Function(Transaction txn) action) async {
    final affectedTables = <String>{};
    final result = await _db!.transaction((txn) async {
      try {
        return await action(TransactionWrapper(txn, affectedTables));
      } catch (e) {
        rethrow;
      }
    });

    if (affectedTables.isNotEmpty) {
      for (final table in affectedTables) {
        _changeManager.notifyChange(table);
      }
    }
    return result;
  }

  Future<void> close() async {
    _changeManager.dispose();
    await _db?.close();
    _db = null;
  }

  /// Executes a raw SQL query
  ///
  /// Refer to the [sqflite documentation](https://pub.dev/packages/sqflite) for more information
  @override
  Future<List<Map<String, dynamic>>> query(
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
    return await _db!.query(
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
  Future<void> execute(String sql, [List<Object?>? arguments]) {
    return _db!.execute(sql, arguments);
  }

  /// Inserts a row into the specified table
  ///
  /// Refer to the [sqflite documentation](https://pub.dev/packages/sqflite) for more information
  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    values = await _ensurePsGlobalId(values);

    final result = await _db!.insert(
      table,
      values,
      nullColumnHack: nullColumnHack,
      conflictAlgorithm: conflictAlgorithm,
    );

    await _notifyChanges([table]);

    return result;
  }

  /// Updates rows in the specified table
  ///
  /// Refer to the [sqflite documentation](https://pub.dev/packages/sqflite) for more information
  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    final result = await _db!.update(
      table,
      values,
      where: where,
      whereArgs: whereArgs,
      conflictAlgorithm: conflictAlgorithm,
    );

    await _notifyChanges([table]);

    return result;
  }

  /// Deletes rows from the specified table
  ///
  /// Refer to the [sqflite documentation](https://pub.dev/packages/sqflite) for more information
  @override
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final result = await _db!.delete(
      table,
      where: where,
      whereArgs: whereArgs,
    );

    await _notifyChanges([table]);

    return result;
  }

  /// Executes a raw SQL query with optional arguments
  ///
  /// Refer to the [sqflite documentation](https://pub.dev/packages/sqflite) for more information
  @override
  Future<List<Map<String, dynamic>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    final tables = extractAffectedTables(sql);
    final isInsertOperation = sql.trim().toUpperCase().startsWith('INSERT');

    if (isInsertOperation) {
      // Inject ps_global_id for INSERT operations
      final psGlobalId = await _generatePsGlobalId();
      sql = sql.replaceFirst(')', ', ps_global_id)');
      sql = sql.replaceFirst('?)', '?, ?)');
      arguments = (arguments ?? [])..add(psGlobalId);
    }

    final result = await _db!.rawQuery(sql, arguments);

    // Check if the query modifies data
    final normalizedSql = sql.trim().toUpperCase();
    if (isInsertOperation ||
        normalizedSql.startsWith('UPDATE') ||
        normalizedSql.startsWith('DELETE')) {
      await _notifyChanges(tables);
    }

    return result;
  }

  /// Starts a batch operation
  /// Refer to the [sqflite documentation](https://pub.dev/packages/sqflite) for more information
  @override
  Batch batch() {
    final batch = _db!.batch();
    return PocketSyncBatch(batch);
  }

  /// Commits a batch operation and notifies changes
  ///
  /// Refer to the [sqflite documentation](https://pub.dev/packages/sqflite) for more information
  Future<List<Object?>> commit(Batch batch) async {
    final result = await batch.commit();
    await _notifyChanges((batch as PocketSyncBatch).affectedTables);
    return result;
  }

  /// Applies a batch operation without reading the results and notifies changes
  ///
  /// Refer to the [sqflite documentation](https://pub.dev/packages/sqflite) for more information
  Future<void> apply(Batch batch) async {
    await batch.apply();
    await _notifyChanges((batch as PocketSyncBatch).affectedTables);
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
    return _db!.queryCursor(
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
    final result = _db!.rawDelete(sql, arguments);
    final tables = extractAffectedTables(sql);
    _notifyChanges(tables);

    return result;
  }

  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) async {
    final result = await _db!.rawInsert(sql, arguments);
    final tables = extractAffectedTables(sql);
    await _notifyChanges(tables);
    return result;
  }

  @override
  Future<QueryCursor> rawQueryCursor(
    String sql,
    List<Object?>? arguments, {
    int? bufferSize,
  }) {
    return _db!.rawQueryCursor(
      sql,
      arguments,
      bufferSize: bufferSize,
    );
  }

  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) {
    final result = _db!.rawUpdate(sql, arguments);
    final tables = extractAffectedTables(sql);
    _notifyChanges(tables);
    return result;
  }

  /// Private method to handle change notifications
  Future<void> _notifyChanges(Iterable<String> tables) async {
    // Get all recent changes from the change
    if (tables.isNotEmpty) {
      for (final table in tables) {
        _changeManager.notifyChange(table);
      }
    }
    _changeManager.notifySync();
  }

  /// Generates a new ps_global_id
  Future<String> _generatePsGlobalId() async {
    final result = await _db!.rawQuery('SELECT hex(randomblob(16)) as uuid');
    return result.first['uuid'] as String;
  }

  /// Ensures a map of values has a ps_global_id
  Future<Map<String, Object?>> _ensurePsGlobalId(
      Map<String, Object?> values) async {
    if (!values.containsKey('ps_global_id')) {
      values['ps_global_id'] = await _generatePsGlobalId();
    }
    return values;
  }
}

/// Wrapper for Batch to handle ps_global_id generationextension WatchExtension on PocketSyncDatabase {
///
extension WatchExtension on PocketSyncDatabase {
  static final Map<PocketSyncDatabase, Map<String, List<QueryWatcher>>>
      _watchersByDb = {};
  static final Map<PocketSyncDatabase, Timer?> _debounceTimers = {};
  static const _debounceMs = 50;

  Map<String, List<QueryWatcher>> get _watchers =>
      _watchersByDb.putIfAbsent(this, () => {});

  Timer? get _debounceTimer => _debounceTimers[this];
  set _debounceTimer(Timer? timer) => _debounceTimers[this] = timer;

  Set<String> _extractTablesFromSql(String sql) {
    final tables = <String>{};
    final regex = RegExp(r'(?:(?:FROM|JOIN|UPDATE|DELETE|INTO|TABLE)\s+)(\w+)',
        caseSensitive: false);
    for (final match in regex.allMatches(sql)) {
      tables.add(match.group(1)!);
    }
    return tables;
  }

  Stream<List<Map<String, dynamic>>> watch(
    String sql, [
    List<Object?>? arguments,
  ]) {
    final queryKey = '$sql${arguments?.toString() ?? ''}';
    final tables = _extractTablesFromSql(sql);
    final watcher = QueryWatcher(sql, arguments, tables);
    _watchers.putIfAbsent(queryKey, () => []).add(watcher);

    // Initial query
    watcher.notify(this);

    // Set up change listeners for relevant tables
    void handleChange(String table, bool isRemote) {
      if (tables.contains(table)) {
        _debounceTimer?.cancel();
        _debounceTimer = Timer(const Duration(milliseconds: _debounceMs), () {
          watcher.notify(this);
        });
      }
    }

    // Add listeners for each table
    for (final table in tables) {
      _changeManager.addTableListener(table, handleChange);
    }

    return watcher.stream.transform(
      StreamTransformer.fromHandlers(
        handleDone: (sink) {
          // Remove table listeners
          for (final table in tables) {
            _changeManager.removeTableListener(table, handleChange);
          }

          // Remove watcher
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
