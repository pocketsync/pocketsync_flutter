## 0.0.14
- Fix: Pause sync was not working properly
- Fix: Initialization lifecycle

## 0.0.13
- Fix: Starting sync was not working properly
- Change: Less noise from internal logging

## 0.0.12
- Add: Unit tests
- Change: Package is now moved to its own repository and open sourced

## 0.0.11
- Fix: Weird behaviour when using pocketsync on a project already using sqflite
- Fix: Changes insertion was causing an issue for some scenarios
- Fix: Resource cleanup (especially for hot reload/restart scenarios)  

## 0.0.10
- Fix: Better handling of schema lifecycle (hence better support for integration in existing apps)
- Some api cleanup

## 0.0.9
- Fix: error when opening an existing database with missing tables missing`ps_global_id` column
- Fix device state initialization

## 0.0.8
- Fix: Properly schema lifecycle

## 0.0.7
- Add missing wrapper methods around `Database` from sqflite
- Expose `Database` instance from `sqflite`

## 0.0.6
- Fix: Changes we sometimes sent twice to the server
- Fix readme

## 0.0.5
### New Features
- Add `silent` option to `PocketSyncOptions` to disable sync logs

### Breaking Changes
- Renamed `startSync` method to `start`
- Renamed `pauseSync` method to `pause`
- Removed `resumeSync` method (use `start` method instead)

### Performance Improvements
- Implemented batch processing for database operations
- Moved changes processing to a separate isolate for better performance
- Optimized sync queue management
- Enhanced conflict resolution handling
- Better retry management

## 0.0.4
- Optimize table extraction algo for watching queries
- Fix: Sometimes, remote changes application caused database locks, it's now fixed
- Fix: Watching queries was not working as expected.

## 0.0.3
- Support watching sql statements
- Fix bug where engine was looking for remote changing despite sync not being enabled

## 0.0.2

- Added dartdoc
- Cleaned up code

## 0.0.1

- Initial release.
