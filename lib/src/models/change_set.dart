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

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Row) return false;

    return primaryKey == other.primaryKey &&
        timestamp == other.timestamp &&
        version == other.version &&
        _mapsAreEqual(data, other.data);
  }

  bool _mapsAreEqual(Map<String, dynamic> map1, Map<String, dynamic> map2) {
    if (identical(map1, map2)) return true;
    if (map1.length != map2.length) return false;

    for (final key in map1.keys) {
      if (!map2.containsKey(key)) return false;
      if (map1[key] != map2[key]) return false;
    }

    return true;
  }

  @override
  int get hashCode => Object.hash(primaryKey, timestamp, version, data);

  @override
  String toString() {
    return 'Row{primaryKey: $primaryKey, timestamp: $timestamp, version: $version, data: $data}';
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

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! TableRows) return false;
    if (rows.length != other.rows.length) return false;

    for (var i = 0; i < rows.length; i++) {
      if (rows[i] != other.rows[i]) return false;
    }

    return true;
  }

  @override
  int get hashCode => Object.hashAll(rows);

  @override
  String toString() {
    return 'TableRows{rows: $rows}';
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

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! TableChanges) return false;
    if (changes.length != other.changes.length) return false;

    for (final key in changes.keys) {
      if (!other.changes.containsKey(key) ||
          changes[key] != other.changes[key]) {
        return false;
      }
    }

    return true;
  }

  @override
  int get hashCode => changes.hashCode;
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

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChangeSet &&
        other.timestamp == timestamp &&
        other.version == version &&
        other.insertions == insertions &&
        other.updates == updates &&
        other.deletions == deletions &&
        other.localChangeIds == localChangeIds &&
        other.serverChangeIds == serverChangeIds;
  }

  @override
  int get hashCode => Object.hash(
        timestamp,
        version,
        insertions,
        updates,
        deletions,
        localChangeIds,
        serverChangeIds,
      );

  ChangeSet copyWith({
    int? timestamp,
    int? version,
    TableChanges? insertions,
    TableChanges? updates,
    TableChanges? deletions,
    List<int>? localChangeIds,
    List<int>? serverChangeIds,
  }) {
    return ChangeSet(
      timestamp: timestamp ?? this.timestamp,
      version: version ?? this.version,
      insertions: insertions ?? this.insertions,
      updates: updates ?? this.updates,
      deletions: deletions ?? this.deletions,
      localChangeIds: localChangeIds ?? this.localChangeIds,
      serverChangeIds: serverChangeIds ?? this.serverChangeIds,
    );
  }
}
