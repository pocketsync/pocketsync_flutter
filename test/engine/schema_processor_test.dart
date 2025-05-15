import 'package:flutter_test/flutter_test.dart';
import 'package:pocketsync_flutter/pocketsync_flutter.dart';
import 'package:pocketsync_flutter/src/engine/schema_processor.dart';
import 'package:pocketsync_flutter/src/utils/sync_config.dart';

void main() {
  group('SchemaProcessor Tests', () {
    test('validateSchema should return true for valid schema', () {
      // Arrange - Create a valid schema
      final validSchema = DatabaseSchema(
        tables: [
          TableSchema(
            name: 'users',
            columns: [
              TableColumn.primaryKey(name: 'id', type: ColumnType.integer),
              TableColumn.text(name: 'name', isNullable: false),
              TableColumn.text(name: 'email'),
            ],
          ),
        ],
      );

      // Act
      final isValid = SchemaProcessor.validateSchema(validSchema);

      // Assert
      expect(isValid, isTrue);
    });

    test('validateSchema should return false for schema without tables', () {
      // Arrange - Create an empty schema
      final emptySchema = DatabaseSchema(tables: []);

      // Act
      final isValid = SchemaProcessor.validateSchema(emptySchema);

      // Assert
      expect(isValid, isFalse);
    });

    test('validateSchema should return false for table without primary key',
        () {
      // Arrange - Create a schema with a table that has no primary key
      final invalidSchema = DatabaseSchema(
        tables: [
          TableSchema(
            name: 'users',
            columns: [
              TableColumn.text(name: 'name'),
              TableColumn.text(name: 'email'),
            ],
          ),
        ],
      );

      // Act
      final isValid = SchemaProcessor.validateSchema(invalidSchema);

      // Assert
      expect(isValid, isFalse);
    });

    test('validateSchema should return false for table with reserved name', () {
      // Arrange - Create a schema with a table that has a reserved name
      final invalidSchema = DatabaseSchema(
        tables: [
          TableSchema(
            name: '__pocketsync_test',
            columns: [
              TableColumn.primaryKey(name: 'id', type: ColumnType.integer),
              TableColumn.text(name: 'name'),
            ],
          ),
        ],
      );

      // Act
      final isValid = SchemaProcessor.validateSchema(invalidSchema);

      // Assert
      expect(isValid, isFalse);
    });

    test('validateSchema should return false for duplicate column names', () {
      // Arrange - Create a schema with duplicate column names (case insensitive)
      final invalidSchema = DatabaseSchema(
        tables: [
          TableSchema(
            name: 'users',
            columns: [
              TableColumn.primaryKey(name: 'id', type: ColumnType.integer),
              TableColumn.text(name: 'name'),
              TableColumn.text(name: 'Name'), // Duplicate (case insensitive)
            ],
          ),
        ],
      );

      // Act
      final isValid = SchemaProcessor.validateSchema(invalidSchema);

      // Assert
      expect(isValid, isFalse);
    });

    test('validateSchema should return false for duplicate index names', () {
      // Arrange - Create a schema with duplicate index names
      final invalidSchema = DatabaseSchema(
        tables: [
          TableSchema(
            name: 'users',
            columns: [
              TableColumn.primaryKey(name: 'id', type: ColumnType.integer),
              TableColumn.text(name: 'name'),
              TableColumn.text(name: 'email'),
            ],
            indexes: [
              Index(name: 'idx_users_name', columns: ['name']),
              Index(
                  name: 'idx_users_NAME',
                  columns: ['email']), // Duplicate name (case insensitive)
            ],
          ),
        ],
      );

      // Act
      final isValid = SchemaProcessor.validateSchema(invalidSchema);

      // Assert
      expect(isValid, isFalse);
    });

    test('addChangeTracking should add global ID column to tables', () {
      // Arrange
      final originalSchema = DatabaseSchema(
        tables: [
          TableSchema(
            name: 'users',
            columns: [
              TableColumn.primaryKey(name: 'id', type: ColumnType.integer),
              TableColumn.text(name: 'name'),
            ],
          ),
        ],
      );

      // Act
      final enhancedSchema = SchemaProcessor.addChangeTracking(originalSchema);

      // Assert
      final userTable = enhancedSchema.getTable('users');
      expect(userTable, isNotNull);

      final hasGlobalId = userTable!.columns
          .any((col) => col.name == SyncConfig.defaultGlobalIdColumnName);
      expect(hasGlobalId, isTrue);

      // Should also have internal tables
      expect(enhancedSchema.tables.length,
          greaterThan(originalSchema.tables.length));
      expect(enhancedSchema.getTable('__pocketsync_changes'), isNotNull);
    });
  });
}
