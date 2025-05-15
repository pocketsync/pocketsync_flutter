import 'package:collection/collection.dart';

/// Represents the type of a database column.
enum ColumnType {
  /// Text data type.
  text,

  /// Integer data type.
  integer,

  /// Real (floating point) data type.
  real,

  /// Binary large object data type.
  blob,

  /// Boolean data type (stored as INTEGER in SQLite).
  boolean,

  /// Date time data type (stored as INTEGER timestamp in SQLite).
  datetime,
}

/// Represents a reference to another table and column.
class TableReference {
  /// The name of the referenced table.
  final String table;

  /// The name of the referenced column.
  final String column;

  /// The on delete action for the foreign key.
  final String? onDelete;

  /// The on update action for the foreign key.
  final String? onUpdate;

  /// Creates a new table reference.
  const TableReference({
    required this.table,
    required this.column,
    this.onDelete,
    this.onUpdate,
  });

  /// @nodoc
  String toSql() {
    final buffer = StringBuffer('REFERENCES $table($column)');

    if (onDelete != null) {
      buffer.write(' ON DELETE $onDelete');
    }

    if (onUpdate != null) {
      buffer.write(' ON UPDATE $onUpdate');
    }

    return buffer.toString();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TableReference &&
        other.table == table &&
        other.column == column &&
        other.onDelete == onDelete &&
        other.onUpdate == onUpdate;
  }

  @override
  int get hashCode =>
      table.hashCode ^ column.hashCode ^ onDelete.hashCode ^ onUpdate.hashCode;
}

/// Represents a column in a database table.
class TableColumn {
  /// The name of the column.
  final String name;

  /// The type of the column.
  final ColumnType type;

  /// Whether the column can be null.
  final bool isNullable;

  /// Whether the column is a primary key.
  final bool isPrimaryKey;

  /// Whether the column auto-increments.
  final bool isAutoIncrement;

  /// Whether the column is unique.
  final bool isUnique;

  /// The default value for the column.
  final dynamic defaultValue;

  /// The check constraint for the column.
  final String? check;

  /// The collation for the column.
  final String? collate;

  /// The reference to another table and column.
  final TableReference? references;

  /// Creates a new column.
  const TableColumn._({
    required this.name,
    required this.type,
    this.isNullable = true,
    this.isPrimaryKey = false,
    this.isAutoIncrement = false,
    this.isUnique = false,
    this.defaultValue,
    this.check,
    this.collate,
    this.references,
  });

  /// Creates a primary key column.
  factory TableColumn.primaryKey({
    required String name,
    required ColumnType type,
    bool isAutoIncrement = false,
    bool isNullable = false,
    dynamic defaultValue,
    String? check,
    String? collate,
  }) {
    return TableColumn._(
      name: name,
      type: type,
      isPrimaryKey: true,
      isAutoIncrement: isAutoIncrement,
      isNullable: isNullable,
      defaultValue: defaultValue,
      check: check,
      collate: collate,
    );
  }

  /// Creates a text column.
  factory TableColumn.text({
    required String name,
    bool isNullable = true,
    bool isUnique = false,
    String? defaultValue,
    String? check,
    String? collate,
  }) {
    return TableColumn._(
      name: name,
      type: ColumnType.text,
      isNullable: isNullable,
      isUnique: isUnique,
      defaultValue: defaultValue,
      check: check,
      collate: collate,
    );
  }

  /// Creates an integer column.
  factory TableColumn.integer({
    required String name,
    bool isNullable = true,
    bool isUnique = false,
    int? defaultValue,
    String? check,
  }) {
    return TableColumn._(
      name: name,
      type: ColumnType.integer,
      isNullable: isNullable,
      isUnique: isUnique,
      defaultValue: defaultValue,
      check: check,
    );
  }

  /// Creates a real column.
  factory TableColumn.real({
    required String name,
    bool isNullable = true,
    bool isUnique = false,
    double? defaultValue,
    String? check,
  }) {
    return TableColumn._(
      name: name,
      type: ColumnType.real,
      isNullable: isNullable,
      isUnique: isUnique,
      defaultValue: defaultValue,
      check: check,
    );
  }

  /// Creates a boolean column.
  factory TableColumn.boolean({
    required String name,
    bool isNullable = true,
    bool? defaultValue,
    String? check,
  }) {
    return TableColumn._(
      name: name,
      type: ColumnType.boolean,
      isNullable: isNullable,
      defaultValue: defaultValue,
      check: check,
    );
  }

  /// Creates a blob column.
  factory TableColumn.blob({
    required String name,
    bool isNullable = true,
    String? check,
  }) {
    return TableColumn._(
      name: name,
      type: ColumnType.blob,
      isNullable: isNullable,
      check: check,
    );
  }

  /// Creates a datetime column.
  factory TableColumn.datetime({
    required String name,
    bool isNullable = true,
    bool isUnique = false,
    DateTime? defaultValue,
    String? check,
  }) {
    return TableColumn._(
      name: name,
      type: ColumnType.datetime,
      isNullable: isNullable,
      isUnique: isUnique,
      defaultValue: defaultValue?.millisecondsSinceEpoch,
      check: check,
    );
  }

  /// Creates a foreign key column.
  factory TableColumn.foreignKey({
    required String name,
    required ColumnType type,
    required TableReference references,
    bool isNullable = true,
    bool isUnique = false,
    dynamic defaultValue,
    String? check,
    String? collate,
  }) {
    return TableColumn._(
      name: name,
      type: type,
      isNullable: isNullable,
      isUnique: isUnique,
      defaultValue: defaultValue,
      check: check,
      collate: collate,
      references: references,
    );
  }

  /// @nodoc
  String _typeToSql() {
    switch (type) {
      case ColumnType.text:
        return 'TEXT';
      case ColumnType.integer:
        return 'INTEGER';
      case ColumnType.real:
        return 'REAL';
      case ColumnType.blob:
        return 'BLOB';
      case ColumnType.boolean:
        return 'INTEGER'; // SQLite stores booleans as integers
      case ColumnType.datetime:
        return 'INTEGER'; // SQLite stores datetimes as integers (timestamps)
    }
  }

  /// @nodoc
  String? _defaultValueToSql() {
    if (defaultValue == null) return null;

    if (defaultValue is String) {
      return "'$defaultValue'";
    } else if (defaultValue is bool) {
      return defaultValue ? '1' : '0';
    } else {
      return defaultValue.toString();
    }
  }

  /// @nodoc
  String toSql() {
    final buffer = StringBuffer('$name ${_typeToSql()}');

    if (isPrimaryKey) {
      buffer.write(' PRIMARY KEY');
      if (isAutoIncrement) {
        buffer.write(' AUTOINCREMENT');
      }
    }

    if (!isNullable) {
      buffer.write(' NOT NULL');
    }

    if (isUnique && !isPrimaryKey) {
      buffer.write(' UNIQUE');
    }

    final defaultSql = _defaultValueToSql();
    if (defaultSql != null) {
      buffer.write(' DEFAULT $defaultSql');
    }

    if (collate != null) {
      buffer.write(' COLLATE $collate');
    }

    if (check != null) {
      buffer.write(' CHECK ($check)');
    }

    if (references != null) {
      buffer.write(' ${references!.toSql()}');
    }

    return buffer.toString();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TableColumn &&
        other.name == name &&
        other.type == type &&
        other.isNullable == isNullable &&
        other.isPrimaryKey == isPrimaryKey &&
        other.isAutoIncrement == isAutoIncrement &&
        other.isUnique == isUnique &&
        other.defaultValue == defaultValue &&
        other.check == check &&
        other.collate == collate &&
        other.references == references;
  }

  @override
  int get hashCode {
    return name.hashCode ^
        type.hashCode ^
        isNullable.hashCode ^
        isPrimaryKey.hashCode ^
        isAutoIncrement.hashCode ^
        isUnique.hashCode ^
        defaultValue.hashCode ^
        check.hashCode ^
        collate.hashCode ^
        references.hashCode;
  }
}

/// Represents an index on a database table.
class Index {
  /// The name of the index.
  final String name;

  /// The columns included in the index.
  final List<String> columns;

  /// Whether the index is unique.
  final bool isUnique;

  /// The where clause for the index.
  final String? where;

  /// Creates a new index.
  const Index({
    required this.name,
    required this.columns,
    this.isUnique = false,
    this.where,
  });

  /// Creates a unique index.
  factory Index.unique({
    required String name,
    required List<String> columns,
    String? where,
  }) {
    return Index(
      name: name,
      columns: columns,
      isUnique: true,
      where: where,
    );
  }

  /// @nodoc
  String toSql(String tableName) {
    final buffer = StringBuffer('CREATE');

    if (isUnique) {
      buffer.write(' UNIQUE');
    }

    buffer.write(
        ' INDEX IF NOT EXISTS $name ON $tableName (${columns.join(', ')})');

    if (where != null) {
      buffer.write(' WHERE $where');
    }

    return buffer.toString();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Index &&
        other.name == name &&
        const ListEquality().equals(other.columns, columns) &&
        other.isUnique == isUnique &&
        other.where == where;
  }

  @override
  int get hashCode {
    return name.hashCode ^
        const ListEquality().hash(columns) ^
        isUnique.hashCode ^
        where.hashCode;
  }
}

/// Represents a schema for a database table.
class TableSchema {
  /// The name of the table.
  final String name;

  /// The columns in the table.
  final List<TableColumn> columns;

  /// The indexes on the table.
  final List<Index> indexes;

  /// Whether this is an internal PocketSync table.
  final bool isInternalTable;

  /// Whether the table is a virtual table.
  final bool isVirtual;

  /// The module for the virtual table.
  final String? module;

  /// The module arguments for the virtual table.
  final List<String>? moduleArgs;

  /// Creates a new table schema.
  const TableSchema({
    required this.name,
    required this.columns,
    this.indexes = const [],
    this.isInternalTable = false,
    this.isVirtual = false,
    this.module,
    this.moduleArgs,
  }) : assert(!isVirtual || (module != null),
            'Virtual tables must specify a module');

  /// Creates a virtual table schema.
  factory TableSchema.virtual({
    required String name,
    required String module,
    List<String> moduleArgs = const [],
    List<TableColumn> columns = const [],
    List<Index> indexes = const [],
    bool isInternalTable = false,
  }) {
    return TableSchema(
      name: name,
      columns: columns,
      indexes: indexes,
      isInternalTable: isInternalTable,
      isVirtual: true,
      module: module,
      moduleArgs: moduleArgs,
    );
  }

  /// Gets the primary key columns for this table.
  List<TableColumn> get primaryKeyColumns {
    return columns.where((column) => column.isPrimaryKey).toList();
  }

  /// Gets the foreign key columns for this table.
  List<TableColumn> get foreignKeyColumns {
    return columns.where((column) => column.references != null).toList();
  }

  /// @nodoc
  String toCreateTableSql() {
    if (isVirtual) {
      return _createVirtualTableSql();
    } else {
      return _createRegularTableSql();
    }
  }

  /// @nodoc
  String _createVirtualTableSql() {
    final buffer =
        StringBuffer('CREATE VIRTUAL TABLE IF NOT EXISTS $name USING $module');

    if (moduleArgs != null && moduleArgs!.isNotEmpty) {
      buffer.write('(${moduleArgs!.join(', ')})');
    }

    return buffer.toString();
  }

  /// @nodoc
  String _createRegularTableSql() {
    final buffer = StringBuffer('CREATE TABLE IF NOT EXISTS $name (\n');

    // Add columns
    final columnDefinitions =
        columns.map((column) => '  ${column.toSql()}').join(',\n');
    buffer.write(columnDefinitions);

    // Add table constraints if needed
    final primaryKeys = primaryKeyColumns;
    if (primaryKeys.length > 1) {
      // Composite primary key
      final primaryKeyColumns =
          primaryKeys.map((column) => column.name).join(', ');
      buffer.write(',\n  PRIMARY KEY ($primaryKeyColumns)');
    }

    buffer.write('\n)');

    return buffer.toString();
  }

  /// @nodoc
  List<String> toCreateIndexSql() {
    return indexes.map((index) => index.toSql(name)).toList();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TableSchema &&
        other.name == name &&
        const ListEquality().equals(other.columns, columns) &&
        const ListEquality().equals(other.indexes, indexes) &&
        other.isInternalTable == isInternalTable &&
        other.isVirtual == isVirtual &&
        other.module == module &&
        (other.moduleArgs == null && moduleArgs == null ||
            other.moduleArgs != null &&
                moduleArgs != null &&
                const ListEquality().equals(other.moduleArgs, moduleArgs));
  }

  @override
  int get hashCode {
    return name.hashCode ^
        const ListEquality().hash(columns) ^
        const ListEquality().hash(indexes) ^
        isInternalTable.hashCode ^
        isVirtual.hashCode ^
        module.hashCode ^
        (moduleArgs != null ? const ListEquality().hash(moduleArgs!) : 0);
  }
}

/// Represents a schema for a database.
class DatabaseSchema {
  /// The tables in the database.
  final List<TableSchema> tables;

  /// Creates a new database schema.
  const DatabaseSchema({
    required this.tables,
  });

  /// Gets a table schema by name.
  TableSchema? getTable(String name) {
    return tables.firstWhereOrNull((table) => table.name == name);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DatabaseSchema &&
        const ListEquality().equals(other.tables, tables);
  }

  @override
  int get hashCode => const ListEquality().hash(tables);
}

/// Represents a database trigger.
class Trigger {
  /// The name of the trigger.
  final String name;

  /// The table the trigger is associated with.
  final String tableName;

  /// The event that activates the trigger (INSERT, UPDATE, DELETE).
  final String event;

  /// The timing of the trigger (BEFORE, AFTER, INSTEAD OF).
  final String timing;

  /// Optional condition for the trigger.
  final String? when;

  /// The SQL statements to execute when the trigger is activated.
  final List<String> statements;

  /// Creates a new trigger.
  const Trigger({
    required this.name,
    required this.tableName,
    required this.event,
    required this.timing,
    this.when,
    required this.statements,
  });

  /// Converts the trigger to SQL.
  String toSql() {
    final buffer = StringBuffer('CREATE TRIGGER IF NOT EXISTS $name\n');
    buffer.write('$timing $event ON $tableName\n');

    if (when != null && when!.isNotEmpty) {
      buffer.write('WHEN $when\n');
    }

    buffer.write('BEGIN\n');
    for (final statement in statements) {
      buffer.write('  $statement\n');
    }
    buffer.write('END;');

    return buffer.toString();
  }
}
