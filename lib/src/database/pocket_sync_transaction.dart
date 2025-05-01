import 'package:pocketsync_flutter/src/database/pocket_sync_batch.dart';
import 'package:pocketsync_flutter/src/models/types.dart';
import 'package:pocketsync_flutter/src/utils/sql_utils.dart';
import 'package:sqflite/sqflite.dart';

class PocketSyncTransaction extends Transaction {
  final Transaction _transaction;
  final Set<DatabaseMutation> _mutations;

  PocketSyncTransaction(this._transaction, this._mutations);

  @override
  Batch batch() {
    return PocketSyncBatch(_transaction.batch());
  }

  @override
  Database get database => _transaction.database;

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) {
    _transaction.delete(table, where: where, whereArgs: whereArgs);
    _mutations.add(DatabaseMutation(
      tableName: table,
      changeType: ChangeType.delete,
    ));
    return _transaction.delete(table, where: where, whereArgs: whereArgs);
  }

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) {
    final tables = extractAffectedTables(sql);
    for (final table in tables) {
      _mutations.add(DatabaseMutation(
          tableName: table, changeType: determineChangeType(sql)!));
    }
    return _transaction.execute(sql, arguments);
  }

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) {
    _transaction.insert(
      table,
      values,
      nullColumnHack: nullColumnHack,
      conflictAlgorithm: conflictAlgorithm,
    );
    _mutations.add(DatabaseMutation(
      tableName: table,
      changeType: ChangeType.insert,
    ));
    return _transaction.insert(
      table,
      values,
      nullColumnHack: nullColumnHack,
      conflictAlgorithm: conflictAlgorithm,
    );
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
  }) {
    return _transaction.query(table,
        distinct: distinct,
        columns: columns,
        where: where,
        whereArgs: whereArgs,
        groupBy: groupBy,
        having: having,
        orderBy: orderBy,
        limit: limit,
        offset: offset);
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
    return _transaction.queryCursor(table,
        distinct: distinct,
        columns: columns,
        where: where,
        whereArgs: whereArgs,
        groupBy: groupBy,
        having: having,
        orderBy: orderBy,
        limit: limit,
        offset: offset,
        bufferSize: bufferSize);
  }

  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) {
    final tables = extractAffectedTables(sql);
    for (final table in tables) {
      _mutations.add(DatabaseMutation(
        tableName: table,
        changeType: ChangeType.delete,
      ));
    }
    return _transaction.rawDelete(sql, arguments);
  }

  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) {
    final tables = extractAffectedTables(sql);
    for (final table in tables) {
      _mutations.add(DatabaseMutation(
        tableName: table,
        changeType: ChangeType.insert,
      ));
    }
    return _transaction.rawInsert(sql, arguments);
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql,
      [List<Object?>? arguments]) {
    return _transaction.rawQuery(sql, arguments);
  }

  @override
  Future<QueryCursor> rawQueryCursor(
    String sql,
    List<Object?>? arguments, {
    int? bufferSize,
  }) {
    return _transaction.rawQueryCursor(sql, arguments, bufferSize: bufferSize);
  }

  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) {
    final tables = extractAffectedTables(sql);
    for (final table in tables) {
      _mutations.add(DatabaseMutation(
        tableName: table,
        changeType: ChangeType.update,
      ));
    }
    return _transaction.rawUpdate(sql, arguments);
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) {
    _transaction.update(
      table,
      values,
      where: where,
      whereArgs: whereArgs,
      conflictAlgorithm: conflictAlgorithm,
    );
    _mutations.add(DatabaseMutation(
      tableName: table,
      changeType: ChangeType.update,
    ));
    return _transaction.update(
      table,
      values,
      where: where,
      whereArgs: whereArgs,
      conflictAlgorithm: conflictAlgorithm,
    );
  }
}
