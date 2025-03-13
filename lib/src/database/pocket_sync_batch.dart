import 'package:pocketsync_flutter/src/utils/table_utils.dart';
import 'package:sqflite/sqflite.dart';

class PocketSyncBatch implements Batch {
  final Batch _batch;

  PocketSyncBatch(this._batch);

  final Set<String> affectedTables = {};

  @override
  Future<List<Object?>> commit({
    bool? exclusive,
    bool? noResult,
    bool? continueOnError,
  }) async {
    return _batch.commit(
      exclusive: exclusive,
      noResult: noResult,
      continueOnError: continueOnError,
    );
  }

  @override
  void insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) {
    if (!values.containsKey('ps_global_id')) {
      values = Map.of(values);
      values['ps_global_id'] =
          'ps_${DateTime.now().microsecondsSinceEpoch}_${values.hashCode}';
    }
    _batch.insert(
      table,
      values,
      nullColumnHack: nullColumnHack,
      conflictAlgorithm: conflictAlgorithm,
    );

    affectedTables.add(table);
  }

  @override
  void rawInsert(String sql, [List<Object?>? arguments]) {
    if (!sql.toLowerCase().contains('ps_global_id')) {
      final psGlobalId =
          'ps_${DateTime.now().microsecondsSinceEpoch}_${sql.hashCode}';
      sql = sql.replaceFirst(')', ', ps_global_id)');
      sql = sql.replaceFirst('?)', '?, ?)');
      arguments = (arguments ?? [])..add(psGlobalId);
    }
    _batch.rawInsert(sql, arguments);

    final tables = extractAffectedTables(sql);
    affectedTables.addAll(tables);
  }

  @override
  void delete(String table, {String? where, List<Object?>? whereArgs}) {
    _batch.delete(table, where: where, whereArgs: whereArgs);
    affectedTables.add(table);
  }

  @override
  void execute(String sql, [List<Object?>? arguments]) {
    _batch.execute(sql, arguments);
  }

  @override
  void query(
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
  }) =>
      _batch.query(
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

  @override
  void rawQuery(String sql, [List<Object?>? arguments]) =>
      _batch.rawQuery(sql, arguments);

  @override
  void update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) {
    _batch.update(
      table,
      values,
      where: where,
      whereArgs: whereArgs,
      conflictAlgorithm: conflictAlgorithm,
    );

    affectedTables.add(table);
  }

  @override
  Future<List<Object?>> apply({bool? noResult, bool? continueOnError}) {
    return _batch.apply(noResult: noResult, continueOnError: continueOnError);
  }

  @override
  int get length => _batch.length;

  @override
  void rawDelete(String sql, [List<Object?>? arguments]) =>
      _batch.rawDelete(sql, arguments);

  @override
  void rawUpdate(String sql, [List<Object?>? arguments]) =>
      _batch.rawUpdate(sql, arguments);
}
