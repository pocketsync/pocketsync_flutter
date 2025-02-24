Set<String> extractAffectedTables(String sql) {
  final Set<String> tables = {};

  // Convert to lowercase for easier matching
  sql = sql.toLowerCase();

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
        tables.add(match.group(1)!);
      }
    }
  }

  // Apply the helper function for each pattern
  for (final pattern in patterns) {
    extractTables(pattern);
  }

  return tables;
}
