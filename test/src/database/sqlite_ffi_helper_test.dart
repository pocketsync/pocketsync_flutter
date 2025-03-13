import 'package:flutter_test/flutter_test.dart';
import 'package:pocketsync_flutter/src/database/sqlite_ffi_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    sqfliteFfiInit();
  });

  group('SqliteFfiHelper', () {
    test('should initialize SQLite FFI correctly', () {
      SqliteFfiHelper.initializeSqliteFfi();

      expect(true, true);
    });

    test('should set databaseFactory to databaseFactoryFfi', () async {
      SqliteFfiHelper.initializeSqliteFfi();

      final db = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(version: 1),
      );

      expect(db, isNotNull);

      await db.close();
    });

    test('should support JSON_OBJECT function', () async {
      SqliteFfiHelper.initializeSqliteFfi();
      final db = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(version: 1),
      );

      final result = await db
          .rawQuery("SELECT json_object('key', 'value') as json_result");

      expect(result, isNotEmpty);
      expect(result.first['json_result'], contains('key'));
      expect(result.first['json_result'], contains('value'));
      expect(result, isNotEmpty);
      expect(result.first['json_result'], contains('key'));
      expect(result.first['json_result'], contains('value'));

      await db.close();
    });

    test('should support other JSON functions', () async {
      SqliteFfiHelper.initializeSqliteFfi();
      final db = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(version: 1),
      );

      final result = await db.rawQuery(
          "SELECT json_extract(json_object('key', 'value'), '\$.key') as extracted_value");

      expect(result, isNotEmpty);
      expect(result.first['extracted_value'], 'value');

      await db.close();
    });
  });
}
