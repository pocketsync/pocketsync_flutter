<p align="center">
  <img src="logo_full.svg" alt="PocketSync Logo" width="200">
  <p align="center">Seamless SQLite synchronization for Flutter applications</p>
</p>

<p align="center">
  <a href="https://pocketsync.dev">Website</a> ·
  <a href="https://docs.pocketsync.dev">Documentation</a> ·
  <a href="https://github.com/pocketsync/pocketsync_flutter/issues">Report Bug</a>
</p>

---

PocketSync enables seamless data synchronization across devices without managing your own backend infrastructure. It works with SQLite databases and handles all the complexities of data synchronization for you.

> **Note:** PocketSync is currently in alpha. The system is under active development and should not be considered reliable for production use. Features and APIs are quite stable now, but may change without notice.

## Features

- **Offline-first architecture**: Continue working with your data even when offline
- **Automatic synchronization**: Changes are automatically synchronized when connectivity is restored
- **Conflict resolution**: Multiple built-in strategies for handling conflicts
- **Optimized change tracking**: Efficiently tracks and batches changes to minimize network usage
- **SQLite integration**: Built on top of SQLite for reliable local data storage
- **Customizable**: Flexible configuration options to suit your specific needs

## Installation

```yaml
dependencies:
  pocketsync_flutter: ^0.3.0
```

Then run:

```bash
flutter pub get
```

## Quick start

You'll need to create a PocketSync project in the [PocketSync dashboard](https://pocketsync.dev) and get your project ID, auth token, and server URL.

### 1. Initialize PocketSync

```dart
import 'package:pocketsync_flutter/pocketsync_flutter.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

Future<void> initPocketSync() async {
  // Get the database path
  String dbPath = join(await getDatabasesPath(), 'my_app_database.db');
  
  // Initialize PocketSync
  await PocketSync.initialize(
    options: PocketSyncOptions(
      projectId: 'YOUR_PROJECT_ID',
      authToken: 'YOUR_AUTH_TOKEN',
      serverUrl: 'https://api.pocketsync.dev',
      // Optional configurations
      conflictResolutionStrategy: ConflictResolutionStrategy.lastWriteWins,
      verbose: true,
    ),
    databaseOptions: DatabaseOptions(
      dbPath: dbPath,
      version: 1,
      onCreate: (db, version) async {
        // Create your database tables
        await db.execute('''
          CREATE TABLE todos (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT,
            isCompleted INTEGER
          )
        ''');
      },
    ),
  );
  
  // Start the sync engine
  await PocketSync.instance.start();
}
```

### 2. Use the PocketSync database

```dart
// Get a reference to the database
final db = PocketSync.instance.database;

// Insert data
await db.insert('todos', {
  'title': 'Buy groceries',
  'isCompleted': 0,
});

// Query data
List<Map<String, dynamic>> todos = await db.query('todos');

// Update data
await db.update(
  'todos',
  {'isCompleted': 1},
  where: 'id = ?',
  whereArgs: [1],
);

// Delete data
await db.delete('todos', where: 'id = ?', whereArgs: [1]);

// Watch database changes
final stream = db.watch('SELECT * FROM todos');
stream.listen((event) {
  print(event);
});
```

Read more: [PocketSync Database](https://docs.pocketsync.dev/pocket-sync/database)

### 3. Manual sync control

```dart
// Manually trigger sync
await PocketSync.instance.scheduleSync();

// Pause synchronization
await PocketSync.instance.stop();

// Resume synchronization
await PocketSync.instance.start();
```

### 4. Conflict resolution

PocketSync provides several strategies for resolving conflicts:

- **Last Write Wins**: The most recent change based on timestamp wins (default)
- **Server Wins**: Server changes always take precedence
- **Client Wins**: Local changes always take precedence
- **Custom**: Provide your own conflict resolution logic

```dart
// Using a custom conflict resolver
await PocketSync.initialize(
  options: PocketSyncOptions(
    // ... other options
    conflictResolutionStrategy: ConflictResolutionStrategy.custom,
    customResolver: (localChange, remoteChange) async {
      // Your custom logic to decide which change wins
      return localChange.timestamp > remoteChange.timestamp
          ? localChange
          : remoteChange;
    },
  ),
  // ... database options
);
```

### 5. Advanced usage

#### User authentication

Set the user ID for multi-user scenarios:

```dart
PocketSync.instance.setUserId('user123');
```

#### Reset sync state

Clear all sync tracking data (use with caution):

```dart
await PocketSync.instance.reset();
```

> **Note:** Call `PocketSync.instance.reset()` before calling `PocketSync.instance.start()` to reset the sync engine (for existing apps. Be cautious when using this method as it will clear all change tracking data). It runs once per plugin version (the goal is to provide a smooth transition for people that were using the sdk prior to version 0.3.0)

### Dispose Resources

Clean up resources when the app is closing:

```dart
await PocketSync.instance.dispose();
```

## Migration

### From 0.2.0 to 0.3.0

- PocketSync now uses SQLite FFI to fix issues with JSON_OBJECT function not being available on some Android devices
- The implementation uses sqflite_common_ffi and sqlite3_flutter_libs packages to provide a more recent version of SQLite with JSON function support
- A SqliteFfiHelper class was created to initialize the FFI implementation before database operations
- Call `PocketSync.instance.reset()` before calling `PocketSync.instance.start()` to reset the sync engine.

## Best practices

1. **Initialize early**: Initialize PocketSync during app startup
2. **Handle conflicts**: Choose an appropriate conflict resolution strategy for your app
3. **Batch operations**: Group related database operations to optimize sync performance
4. **User authentication**: Set the user ID when the user logs in (sync will not work without a user ID)

## Support

If you have any questions or need help, please open an issue on the [GitHub repository](https://github.com/pocketsync/pocketsync_flutter). 

If you need to talk to the PocketSync team, please reach out to [hello@pocketsync.dev](mailto:hello@pocketsync.dev).

## License

This project is licensed under the MIT License - see the LICENSE file for details.