import 'package:pocketsync_flutter/src/types.dart';

Set<String> extractAffectedTables(String sql) {
  final Set<String> tables = {};
  final Set<String> tempTables = {};

  sql = sql.toLowerCase();

  final withPattern = RegExp(r'with\s+([a-zA-Z_][a-zA-Z0-9_]*)\s+as\s*\(',
      caseSensitive: false);
  for (final match in withPattern.allMatches(sql)) {
    if (match.group(1) != null) {
      tempTables.add(match.group(1)!);
    }
  }

  final patterns = [
    RegExp(r'from\s+([a-zA-Z_][a-zA-Z0-9_]*)', caseSensitive: false),
    RegExp(r'join\s+([a-zA-Z_][a-zA-Z0-9_]*)', caseSensitive: false),
    RegExp(r'update\s+([a-zA-Z_][a-zA-Z0-9_]*)', caseSensitive: false),
    RegExp(
      r'(?:insert\s+or\s+replace\s+into|insert\s+into)\s+([a-zA-Z_][a-zA-Z0-9_]*)',
      caseSensitive: false,
    ),
    RegExp(r'delete\s+from\s+([a-zA-Z_][a-zA-Z0-9_]*)', caseSensitive: false),
  ];

  void extractTables(RegExp pattern) {
    for (final match in pattern.allMatches(sql)) {
      if (match.group(1) != null) {
        final tableName = match.group(1)!;
        if (!tempTables.contains(tableName)) {
          tables.add(tableName);
        }
      }
    }
  }

  for (final pattern in patterns) {
    extractTables(pattern);
  }

  return tables;
}

ChangeType? determineChangeType(String sql) {
  sql = sql.toLowerCase();
  if (sql.contains('insert') || sql.contains('replace')) {
    return ChangeType.insert;
  } else if (sql.contains('update')) {
    return ChangeType.update;
  } else if (sql.contains('delete')) {
    return ChangeType.delete;
  }

  return null;
}
