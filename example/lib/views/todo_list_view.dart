import 'package:pocketsync_flutter/pocketsync_flutter.dart';
import 'package:flutter/material.dart';
import '../controllers/todo_controller.dart';
import '../models/todo.dart';

final TodoController _todoController = TodoController(
  PocketSync.instance.database,
);

class TodoListView extends StatefulWidget {
  const TodoListView({super.key});

  @override
  State<TodoListView> createState() => _TodoListViewState();
}

class _TodoListViewState extends State<TodoListView> {
  final TextEditingController _textController = TextEditingController();
  bool _isSyncPaused = false;

  @override
  void dispose() {
    _textController.dispose();
    _todoController.dispose();

    super.dispose();
  }

  void _toggleSync() async {
    setState(() {
      _isSyncPaused = !_isSyncPaused;
    });
    if (_isSyncPaused) {
      PocketSync.instance.pause();
    } else {
      await PocketSync.instance.start();
    }
  }

  Future<void> _handleTodoOperation(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Todo List'),
        actions: [
          IconButton(
            icon: Icon(_isSyncPaused ? Icons.play_arrow : Icons.pause),
            onPressed: _toggleSync,
            tooltip: _isSyncPaused ? 'Resume sync' : 'Pause sync',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: const InputDecoration(
                      hintText: 'Add a new todo',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () {
                    if (_textController.text.isNotEmpty) {
                      _handleTodoOperation(() async {
                        await _todoController.insertTodo(
                          Todo(title: _textController.text),
                        );
                        _textController.clear();
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Todo>>(
              stream: _todoController.getTodos(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 48, color: Colors.red),
                        const SizedBox(height: 16),
                        Text('Error: ${snapshot.error}'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => setState(() {}),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text('No todos yet'));
                }

                return ListView.builder(
                  itemCount: snapshot.data!.length,
                  itemBuilder: (context, index) {
                    final todo = snapshot.data![index];
                    return ListTile(
                      onTap: () {
                        _handleTodoOperation(() async {
                          await _todoController.updateTodo(
                            todo.copyWith(isCompleted: !todo.isCompleted),
                          );
                        });
                      },
                      leading: IgnorePointer(
                        child: Checkbox(
                          value: todo.isCompleted,
                          onChanged: (bool? value) {},
                        ),
                      ),
                      title: Text(
                        todo.title,
                        style: TextStyle(
                          decoration: todo.isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () {
                          _handleTodoOperation(() async {
                            await _todoController.deleteTodo(todo.id!);
                          });
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
