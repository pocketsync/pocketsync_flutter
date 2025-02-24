import 'package:flutter_test/flutter_test.dart';
import 'package:pocketsync_flutter/src/utils/table_utils.dart';

void main() {
  group('extractAffectedTables', () {
    test('should extract table from simple SELECT statement', () {
      final sql = 'SELECT * FROM users';
      final tables = extractAffectedTables(sql);
      expect(tables, equals({'users'}));
    });

    test('should extract table from INSERT statement', () {
      final sql = 'INSERT INTO products (name, price) VALUES ("test", 10)';
      final tables = extractAffectedTables(sql);
      expect(tables, equals({'products'}));
    });

    test('should extract table from INSERT OR REPLACE statement', () {
      final sql = 'INSERT OR REPLACE INTO orders (id, total) VALUES (1, 100)';
      final tables = extractAffectedTables(sql);
      expect(tables, equals({'orders'}));
    });

    test('should extract table from UPDATE statement', () {
      final sql = 'UPDATE customers SET name = "John" WHERE id = 1';
      final tables = extractAffectedTables(sql);
      expect(tables, equals({'customers'}));
    });

    test('should extract table from DELETE statement', () {
      final sql = 'DELETE FROM cart WHERE user_id = 5';
      final tables = extractAffectedTables(sql);
      expect(tables, equals({'cart'}));
    });

    test('should extract multiple tables from JOIN statement', () {
      final sql = 'SELECT o.id FROM orders o JOIN users u ON o.user_id = u.id';
      final tables = extractAffectedTables(sql);
      expect(tables, equals({'orders', 'users'}));
    });

    test('should handle case insensitive SQL statements', () {
      final sql = 'select * FROM Users JOIN Orders on Users.id = Orders.user_id';
      final tables = extractAffectedTables(sql);
      expect(tables, equals({'users', 'orders'}));
    });

    test('should handle multiple occurrences of same table', () {
      final sql = 'SELECT * FROM products WHERE id IN (SELECT product_id FROM products)';
      final tables = extractAffectedTables(sql);
      expect(tables, equals({'products'}));
    });

    test('should handle complex SQL with multiple operations', () {
      final sql = '''
        WITH temp AS (SELECT * FROM orders)
        INSERT INTO order_summary
        SELECT o.*, c.name 
        FROM temp o
        JOIN customers c ON o.customer_id = c.id
        ''';
      final tables = extractAffectedTables(sql);
      expect(tables, equals({'orders', 'order_summary', 'customers'}));
    });
  });
}