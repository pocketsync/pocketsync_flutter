import 'package:flutter_test/flutter_test.dart';
import 'package:pocketsync_flutter/pocketsync_flutter.dart';
import 'package:pocketsync_flutter/src/engine/schema_manager.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Utility class for database testing that provides common setup and teardown
/// functionality for database-related tests.
class DatabaseTestUtils {
  /// Initializes the sqflite_ffi for testing.
  /// This should be called in the setUpAll method of the test suite.
  static void initializeSqfliteFfi() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  
  /// Creates an in-memory database with a test table.
  /// 
  /// Returns a Future that completes with the created database.
  static Future<Database> createInMemoryDatabase() async {
    return await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          // Create a test table
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
  
  /// Creates database options for testing with an in-memory database.
  /// 
  /// Returns the DatabaseOptions configured for testing.
  static DatabaseOptions createTestDatabaseOptions() {
    return DatabaseOptions(
      version: 1,
      dbPath: inMemoryDatabasePath,
      onCreate: (db, version) async {
        // Create a test table
        await db.execute('''
          CREATE TABLE users (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            email TEXT
          )
        ''');
      },
    );
  }
  
  /// Creates a SchemaManager instance for testing.
  /// 
  /// Returns a new SchemaManager instance.
  static SchemaManager createSchemaManager() {
    return SchemaManager();
  }
  
  /// Inserts test data into the users table.
  /// 
  /// [db] The database to insert data into.
  /// [count] The number of test users to insert.
  static Future<void> insertTestUsers(Database db, {int count = 5}) async {
    for (int i = 0; i < count; i++) {
      await db.insert('users', {
        'name': 'Test User $i',
        'email': 'user$i@example.com',
      });
    }
  }
}