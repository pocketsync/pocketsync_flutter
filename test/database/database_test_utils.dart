import 'package:flutter_test/flutter_test.dart';
import 'package:pocketsync_flutter/pocketsync_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseTestUtils {
  static void initializeSqfliteFfi() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  static Future<Database> createInMemoryDatabase() async {
    return await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE users (
              id INTEGER PRIMARY KEY,
              name TEXT NOT NULL,
              email TEXT
            )
          ''');
        },
      ),
    );
  }

  static DatabaseOptions createTestDatabaseOptions() {
    return DatabaseOptions(
      version: 1,
      dbPath: inMemoryDatabasePath,
      schema: DatabaseSchema(tables: [
        TableSchema(
          name: 'users',
          columns: [
            TableColumn.primaryKey(name: 'id', type: ColumnType.integer),
            TableColumn.text(name: 'name', isNullable: false),
            TableColumn.text(name: 'email'),
          ],
        ),
      ]),
    );
  }

  static Future<void> insertTestUsers(Database db, {int count = 5}) async {
    for (int i = 0; i < count; i++) {
      await db.insert('users', {
        'name': 'Test User $i',
        'email': 'user$i@example.com',
      });
    }
  }
}
