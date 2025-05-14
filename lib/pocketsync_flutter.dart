// External dependencies
export 'package:sqflite/sqflite.dart'
    show getDatabasesPath, ConflictAlgorithm, inMemoryDatabasePath, Database;

// Core API
export 'src/pocket_sync.dart';
export 'src/database/pocket_sync_database.dart';

// Configuration types
export 'src/models/types.dart'
    show
        DatabaseOptions,
        PocketSyncOptions,
        ConflictResolutionStrategy,
        ConflictResolver;
export 'src/models/sync_change.dart';

// Schema API - only expose what developers need to define schemas
export 'src/models/schema.dart'
    show 
        // Core schema classes
        TableSchema,
        DatabaseSchema,
        
        // Column definition
        TableColumn,
        ColumnType,
        
        // Constraints and indexes
        TableReference,
        Index;
