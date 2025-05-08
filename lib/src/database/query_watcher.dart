import 'dart:async';

import 'package:sqflite/sqflite.dart';

class QueryWatcher {
  final String sql;
  final List<Object?>? arguments;
  final StreamController<List<Map<String, dynamic>>> _controller;
  final Set<String> tables;
  bool _isActive = true;

  QueryWatcher(this.sql, this.arguments, this.tables)
      : _controller = StreamController<List<Map<String, dynamic>>>.broadcast();

  Stream<List<Map<String, dynamic>>> get stream => _controller.stream;

  void dispose() {
    _isActive = false;
    _controller.close();
  }

  Future<void> notify(Database db) async {
    if (!_isActive) return;

    try {
      final results = await db.rawQuery(sql, arguments);
      if (!_isActive) return;
      _controller.add(results);
    } catch (e) {
      if (!_isActive) return;
      _controller.addError(e);
    }
  }
}
