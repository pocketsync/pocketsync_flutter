import 'dart:convert';

class Row {
  final String primaryKey;
  final int timestamp;
  final int version;
  final Map<String, dynamic> data;

  Row({
    required this.primaryKey,
    required this.timestamp,
    required this.version,
    required this.data,
  });

  Map<String, dynamic> toJson() => {
        'primaryKey': primaryKey,
        'timestamp': timestamp,
        'data': data,
      };

  factory Row.fromJson(Map<String, dynamic> json) {
    return Row(
      primaryKey: json['primaryKey'] as String,
      timestamp: json['timestamp'] as int,
      version: (json['version'] ?? 1) as int,
      data: json['data'] as Map<String, dynamic>,
    );
  }
}

class TableRows {
  final List<Row> rows;

  TableRows(this.rows);

  Map<String, dynamic> toJson() => {
        'rows': rows.map((row) => row.toJson()).toList(),
      };

  factory TableRows.fromJson(Map<String, dynamic> json) {
    return TableRows(
      List<Row>.from(
        (json['rows'] as List).map(
          (row) => Row.fromJson(
            row is String ? jsonDecode(row) : row as Map<String, dynamic>,
          ),
        ),
      ),
    );
  }
}

class TableChanges {
  final Map<String, TableRows> changes;

  TableChanges(this.changes);

  Map<String, dynamic> toJson() =>
      changes.map((key, value) => MapEntry(key, value.toJson()));

  factory TableChanges.fromJson(Map<String, dynamic> json) {
    return TableChanges(
      Map<String, TableRows>.fromEntries(
        json.entries.map(
          (e) => MapEntry(
            e.key,
            TableRows.fromJson(e.value as Map<String, dynamic>),
          ),
        ),
      ),
    );
  }
}

class ChangeSet {
  final int timestamp;
  final int version;
  final TableChanges insertions;
  final TableChanges updates;
  final TableChanges deletions;
  final List<int> localChangeIds;
  final List<int> serverChangeIds;

  ChangeSet({
    required this.timestamp,
    required this.version,
    required this.insertions,
    required this.updates,
    required this.deletions,
    this.localChangeIds = const [],
    this.serverChangeIds = const [],
  });

  factory ChangeSet.empty() {
    return ChangeSet(
      timestamp: 0,
      version: 0,
      insertions: TableChanges({}),
      updates: TableChanges({}),
      deletions: TableChanges({}),
      localChangeIds: [],
      serverChangeIds: [],
    );
  }

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp,
        'version': version,
        'insertions': insertions.toJson(),
        'updates': updates.toJson(),
        'deletions': deletions.toJson(),
      };

  factory ChangeSet.fromJson(Map<String, dynamic> json) {
    return ChangeSet(
      timestamp: json['timestamp'],
      version: json['version'],
      insertions: TableChanges.fromJson(json['insertions']),
      updates: TableChanges.fromJson(json['updates']),
      deletions: TableChanges.fromJson(json['deletions']),
    );
  }

  int get length =>
      insertions.changes.length +
      updates.changes.length +
      deletions.changes.length;

  bool get isNotEmpty =>
      insertions.changes.isNotEmpty ||
      updates.changes.isNotEmpty ||
      deletions.changes.isNotEmpty;
}
