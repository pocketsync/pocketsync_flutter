import 'package:pocketsync_flutter/src/models/pocket_sync_options.dart';

class PocketSyncOptionsFixtures {
  static final defaultOptions = PocketSyncOptions(
    serverUrl: 'https://api.example.com',
    projectId: 'test_project',
    authToken: 'test_auth_token',
  );
}
