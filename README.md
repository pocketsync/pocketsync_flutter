<p align="center">
  <h1 align="center">PocketSync</h1>
  <p align="center">Seamless SQLite synchronization for Flutter applications</p>
</p>

<p align="center">
  <a href="https://pocketsync.dev">Website</a> ·
  <a href="https://docs.pocketsync.dev">Documentation</a> ·
  <a href="https://github.com/pocketsync/pocketsync_flutter/issues">Report Bug</a>
</p>

---

PocketSync is a powerful Flutter package that enables seamless data synchronization across devices without managing backend infrastructure. It works with SQLite databases and handles all the complexities of data synchronization for you.

> **Note:** PocketSync is currently in alpha. The system is under active development and should not be considered reliable for production use. Features and APIs may change without notice.

## Features

- **Automatic Sync** – Changes in your SQLite database sync seamlessly across devices
- **Offline Support** – Changes are queued and synced when the device reconnects
- **Last Write Wins** – Simple conflict resolution ensures predictable data handling
- **Zero Backend Setup** – No need to build or manage a backend—PocketSync does it for you
- **Change Tracking** – Monitor database changes in real-time with the watch API
- **Customizable** – Implement your own conflict resolution strategies

## Quick Start

### Installation

```yaml
dependencies:
  pocketsync_flutter: ^0.1.2
```

Or install via command line:

```bash
flutter pub add pocketsync_flutter
```

### Basic Setup

1. Create an account at [pocketsync.dev](https://pocketsync.dev)
2. Create a new project in the PocketSync console
3. Initialize PocketSync in your app:

```dart
import 'package:pocketsync_flutter/pocketsync_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final dbPath = join(await getDatabasesPath(), 'my_app.db');
  
  try {
    await PocketSync.initialize(
      dbPath: dbPath,
      options: PocketSyncOptions(
        projectId: 'your-project-id',
        authToken: 'your-auth-token',
        serverUrl: 'https://api.pocketsync.dev',
      ),
      databaseOptions: databaseOptions,
    );

    await PocketSync.instance.setUserId(userId: 'user-123');
    await PocketSync.instance.start();
  } catch (e) {
    print('Failed to initialize PocketSync: $e');
  }
}
```

## Database Operations

PocketSyncDatabase is a wrapper around the `sqflite` package, providing additional features for syncing data across devices. 

### CRUD Operations

```dart
final db = PocketSync.instance.database;

// Create
await db.insert('todos', {
  'id': 'todo-${DateTime.now().millisecondsSinceEpoch}',
  'title': 'Buy groceries',
  'is_completed': 0,
});

// Read
final todos = await db.query('todos',
  where: 'is_completed = ?',
  whereArgs: [0],
);

// Update
await db.update('todos',
  {'is_completed': 1},
  where: 'id = ?',
  whereArgs: ['todo-123'],
);

// Delete
await db.delete('todos',
  where: 'id = ?',
  whereArgs: ['todo-123'],
);
```

### Watch for Changes

```dart
// Watch all todos
final todosStream = db.watch('SELECT * FROM todos');

// Use in StreamBuilder
StreamBuilder<List<Map<String, dynamic>>>(
  stream: todosStream,
  builder: (context, snapshot) {
    if (snapshot.hasData) {
      return ListView.builder(
        itemCount: snapshot.data!.length,
        itemBuilder: (context, index) => TodoItem(todo: snapshot.data![index]),
      );
    }
    return const CircularProgressIndicator();
  },
);
```

## Advanced Features

### Custom Conflict Resolution

```dart
class CustomConflictResolver extends ConflictResolver {
  @override
  Future<Map<String, dynamic>> resolveConflict(
    String tableName,
    Map<String, dynamic> localData,
    Map<String, dynamic> remoteData,
  ) async {
    if (tableName == 'todos') {
      return {
        ...remoteData,
        'title': '${localData['title']} (merged)',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      };
    }
    return remoteData; // Default to last-write-wins
  }
}

// Register your custom resolver
await PocketSync.instance.setConflictResolver(CustomConflictResolver());
```

### Sync Control

```dart
// Start sync
await PocketSync.instance.start();

// Pause sync
await PocketSync.instance.pause();

// Clean up resources
await PocketSync.instance.dispose();
```

## Error Handling

```dart
try {
  // Your sync operations
} on NetworkError catch (e) {
  print('Network error: ${e.message}');
} on DatabaseError catch (e) {
  print('Database error: ${e.message}');
} on ConflictError catch (e) {
  print('Conflict error: ${e.message}');
} on SyncError catch (e) {
  print('General sync error: ${e.message}');
}
```

## Best Practices

### Use UUIDs Instead of Integer IDs

When designing your database schema for use with PocketSync, it's crucial to use UUIDs (or similar globally unique identifiers) instead of auto-incrementing integer IDs for your primary keys. Here's why:

- **Avoid Data Loss**: Auto-incrementing IDs can cause conflicts when syncing data from multiple devices, potentially leading to data loss or incorrect relationships.
- **Prevent Collisions**: UUIDs virtually eliminate the risk of ID collisions when multiple devices create records offline.
- **Simplify Conflict Resolution**: Unique IDs make it easier to track and merge changes from different sources.

Example of recommended schema and ID usage:

```dart
// In your database initialization (typically in onCreate)
await db.execute('''
  CREATE TABLE todos (
    id TEXT PRIMARY KEY NOT NULL, // UUID as primary key
    title TEXT NOT NULL,
    is_completed INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  )
''');

// When inserting records
import 'package:uuid/uuid.dart';

await db.insert('todos', {
  'id': const Uuid().v4(), // Generates a unique UUID
  'title': 'Buy groceries',
  'is_completed': 0,
  'created_at': DateTime.now().millisecondsSinceEpoch,
  'updated_at': DateTime.now().millisecondsSinceEpoch,
});
```

Key points about the schema:
- Use `TEXT` type for UUID columns instead of `INTEGER`
- Always declare the ID column as `NOT NULL` and `PRIMARY KEY`
- Include `created_at` and `updated_at` timestamps for better sync conflict resolution

## Known Limitations

- The SDK is in early alpha, breaking changes may occur
- Changes are synced in order of occurrence
- Service optimization for large-scale production use is ongoing

## Documentation

For complete documentation, visit [docs.pocketsync.dev](https://docs.pocketsync.dev)

## Contributing

PocketSync is in early alpha, and your feedback is invaluable. Feel free to:
- Report issues
- Suggest features
- Submit pull requests

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

<p align="center">
  Made with ❤️ by <a href="https://x.com/nossesteve">Steve NOSSE</a>
</p>
