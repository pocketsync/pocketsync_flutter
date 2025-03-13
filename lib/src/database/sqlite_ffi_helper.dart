import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class SqliteFfiHelper {
  static void initializeSqliteFfi() {
    if (_initialized) return;
    
    sqfliteFfiInit();
    
    try {
      databaseFactory = databaseFactoryFfi;
    } catch (e) {
      debugPrint('Failed to initialize SQLite FFI: $e');
    }
    
    _initialized = true;
  }
  
  static bool _initialized = false;
}
