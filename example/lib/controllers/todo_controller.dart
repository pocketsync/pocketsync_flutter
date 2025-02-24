import 'package:pocketsync_flutter/pocketsync_flutter.dart';
import '../models/todo.dart';

class TodoController {
  final PocketSyncDatabase db;

  TodoController(this.db);

  Future<void> insertTodo(Todo todo) async {
    db.rawQuery(
      'INSERT OR REPLACE INTO todos (title, isCompleted) VALUES (?, ?)',
      [todo.title, todo.isCompleted ? 1 : 0],
    );
  }

  Stream<List<Todo>> getTodos() {
    return db.watch('SELECT * FROM todos ORDER BY id DESC').map((row) {
      return row.map((e) => Todo.fromMap(e)).toList();
    });
  }

  Future<void> updateTodo(Todo todo) async {
    await db.rawQuery(
      'UPDATE todos SET title = ?, isCompleted = ? WHERE id = ?',
      [todo.title, todo.isCompleted ? 1 : 0, todo.id],
    );
  }

  Future<void> deleteTodo(int id) async {
    await db.rawQuery('DELETE FROM todos WHERE id = ?', [id]);
  }

  void dispose() {
    db.close();
  }
}
