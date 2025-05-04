import 'package:flutter_test/flutter_test.dart';
import 'package:pocketsync_flutter/src/models/types.dart';
import 'package:pocketsync_flutter/src/utils/sql_utils.dart';

void main() {
  group('extractAffectedTables', () {
    test('extracts table names from SELECT queries', () {
      final sql = 'SELECT * FROM users WHERE id = 1';
      final tables = extractAffectedTables(sql);
      expect(tables, contains('users'));
      expect(tables.length, 1);
    });

    test('extracts table names from INSERT queries', () {
      final sql = 'INSERT INTO users (name, email) VALUES ("John", "john@example.com")';
      final tables = extractAffectedTables(sql);
      expect(tables, contains('users'));
      expect(tables.length, 1);
    });

    test('extracts table names from UPDATE queries', () {
      final sql = 'UPDATE users SET name = "John" WHERE id = 1';
      final tables = extractAffectedTables(sql);
      expect(tables, contains('users'));
      expect(tables.length, 1);
    });

    test('extracts table names from DELETE queries', () {
      final sql = 'DELETE FROM users WHERE id = 1';
      final tables = extractAffectedTables(sql);
      expect(tables, contains('users'));
      expect(tables.length, 1);
    });

    test('extracts multiple table names from JOIN queries', () {
      final sql = 'SELECT u.name, p.title FROM users u JOIN posts p ON u.id = p.user_id';
      final tables = extractAffectedTables(sql);
      expect(tables, containsAll(['users', 'posts']));
      expect(tables.length, 2);
    });

    test('ignores temporary tables in WITH clauses', () {
      final sql = 'WITH temp_users AS (SELECT * FROM users) SELECT * FROM temp_users JOIN posts ON temp_users.id = posts.user_id';
      final tables = extractAffectedTables(sql);
      expect(tables, containsAll(['users', 'posts']));
      expect(tables, isNot(contains('temp_users')));
      expect(tables.length, 2);
    });

    test('handles case insensitivity', () {
      final sql = 'SELECT * FROM Users WHERE ID = 1';
      final tables = extractAffectedTables(sql);
      expect(tables, contains('users'));
      expect(tables.length, 1);
    });

    test('handles complex queries with multiple operations', () {
      final sql = '''
        WITH archived_posts AS (
          SELECT * FROM posts WHERE status = 'archived'
        )
        INSERT INTO post_archives (id, title, content)
        SELECT id, title, content FROM archived_posts
        WHERE created_at < datetime('now', '-1 year')
      ''';
      
      final tables = extractAffectedTables(sql);
      expect(tables, containsAll(['posts', 'post_archives']));
      expect(tables, isNot(contains('archived_posts')));
      expect(tables.length, 2);
    });
  });

  group('determineChangeType', () {
    test('identifies INSERT operations', () {
      final sql = 'INSERT INTO users (name, email) VALUES ("John", "john@example.com")';
      final changeType = determineChangeType(sql);
      expect(changeType, ChangeType.insert);
    });

    test('identifies INSERT OR REPLACE operations as inserts', () {
      final sql = 'INSERT OR REPLACE INTO users (id, name) VALUES (1, "John")';
      final changeType = determineChangeType(sql);
      expect(changeType, ChangeType.insert);
    });

    test('identifies UPDATE operations', () {
      final sql = 'UPDATE users SET name = "John" WHERE id = 1';
      final changeType = determineChangeType(sql);
      expect(changeType, ChangeType.update);
    });

    test('identifies DELETE operations', () {
      final sql = 'DELETE FROM users WHERE id = 1';
      final changeType = determineChangeType(sql);
      expect(changeType, ChangeType.delete);
    });

    test('returns null for SELECT operations', () {
      final sql = 'SELECT * FROM users WHERE id = 1';
      final changeType = determineChangeType(sql);
      expect(changeType, isNull);
    });

    test('handles case insensitivity', () {
      final sql = 'Update Users SET name = "John" WHERE id = 1';
      final changeType = determineChangeType(sql);
      expect(changeType, ChangeType.update);
    });

    test('handles complex queries with comments', () {
      final sql = '''
        -- This is a comment
        UPDATE users 
        /* This is another comment */
        SET name = "John" 
        WHERE id = 1
      ''';
      final changeType = determineChangeType(sql);
      expect(changeType, ChangeType.update);
    });
  });
}