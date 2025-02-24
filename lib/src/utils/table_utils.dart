Set<String> extractAffectedTables(String sql) {
  final Set<String> tables = {};
  final Set<String> tempTables = {};

  // Convert to lowercase for easier matching
  sql = sql.toLowerCase();

  // Extract temporary table names from WITH clauses
  final withPattern = RegExp(r'with\s+([a-zA-Z_][a-zA-Z0-9_]*)\s+as\s*\(', caseSensitive: false);
  for (final match in withPattern.allMatches(sql)) {
    if (match.group(1) != null) {
      tempTables.add(match.group(1)!);
    }
  }

  // Regular expressions for common SQL patterns
  final patterns = [
    // From clauses
    RegExp(r'from\s+([a-zA-Z_][a-zA-Z0-9_]*)', caseSensitive: false),
    // Join clauses
    RegExp(r'join\s+([a-zA-Z_][a-zA-Z0-9_]*)', caseSensitive: false),
    // Update statements
    RegExp(r'update\s+([a-zA-Z_][a-zA-Z0-9_]*)', caseSensitive: false),
    // Insert or replace into statements
    RegExp(
      r'(?:insert\s+or\s+replace\s+into|insert\s+into)\s+([a-zA-Z_][a-zA-Z0-9_]*)',
      caseSensitive: false,
    ),
    // Delete statements
    RegExp(r'delete\s+from\s+([a-zA-Z_][a-zA-Z0-9_]*)', caseSensitive: false),
  ];

  // Helper function to extract table names
  void extractTables(RegExp pattern) {
    for (final match in pattern.allMatches(sql)) {
      if (match.group(1) != null) {
        final tableName = match.group(1)!;
        // Only add if it's not a temporary table
        if (!tempTables.contains(tableName)) {
          tables.add(tableName);
        }
      }
    }
  }

  // Apply the helper function for each pattern
  for (final pattern in patterns) {
    extractTables(pattern);
  }

  return tables;
}
