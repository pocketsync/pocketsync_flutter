import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pocketsync_flutter/pocketsync_flutter.dart';
import 'package:path/path.dart';
import 'views/todo_list_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  String path = join(await getDatabasesPath(), 'todo_database.db');

  await PocketSync.initialize(
    options: PocketSyncOptions(
      projectId: '1d0c9a33-e5bd-4149-9971-8b2568f22469',
      authToken: 'ds_NzhkNzk3ZWE1NGE1NDA1NDk0ZGU5ODAxZDBkZjQ4MmY=',
      serverUrl: defaultTargetPlatform == TargetPlatform.android
          ? 'http://10.0.2.2:3000'
          : 'http://127.0.0.1:3000',
    ),
    databaseOptions: DatabaseOptions(
      dbPath: path,
      schema: DatabaseSchema(
        tables: [
          TableSchema(
            name: 'todos',
            columns: [
              TableColumn.primaryKey(name: 'id', type: ColumnType.integer),
              TableColumn.text(name: 'title'),
              TableColumn.boolean(name: 'isCompleted'),
            ],
            indexes: [
              Index(
                name: 'idx_todos_title',
                columns: ['title'],
              ),
            ],
          )
        ],
      ),
    ),
  );

  // Set user ID - In a real app, this would come from your auth system
  PocketSync.instance.setUserId('test-user');

  // Start syncing
  await PocketSync.instance.start();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Todo App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const TodoListView(),
    );
  }
}
