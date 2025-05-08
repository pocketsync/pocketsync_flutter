## 0.4.0
- Split changes into batches to prevent server overload
- Properly handle connection and disconnection events (and avoid unnecessary syncs)
- Add support for in memory database

## 0.3.0
- Complete refactoring of the engine

### Breaking Changes
- Renamed `pause` method to `stop`
- Renamed `syncPreExistingRecords` option to `syncExistingData`
- Internal: Completely redefined the engine architecture

## 0.2.0
- Fix: Some sqlite functions were not available on some Android versions, preventing sync to work and database mutations to happen

## 0.1.2
- Fix: Pre-existing record option was triggering sync for already synced records

## 0.1.1
- Fix: Last sync timestamp was not properly calculated, leading to server sending data in the wrong order.
- Fix: Invalid columns were present in the sync data
- Fix: Prevent sync operations on engine start to block the main thread

- Dev: Add more unit test

## 0.1.0
- Dev: Add more unit tests (to the main pocketsync orchestrator)

### Breaking Changes
- Initialize PocketSync with `PocketSync.initialize()` instead of `PocketSync.instance.initialize()`


## 0.0.18
- Fix: Logs were too noisy

## 0.0.17
- Fix: `syncPreExistingRecords` option was not working properly
- Fix:  Conflict resolution was not properly working properly (we previously could experience data loss in some scenarios where recent changes were squashed by older changes from the server). A proper conflict resolution algorithm was implemented to handle this scenario.
- Dev: Add more unit tests (especially to the ChangesProcessor)

## 0.0.16
- Fix: syncPreExistingRecords algo to work with tables not having an id column

## 0.0.15
- Add: New `syncPreExistingRecords` option to `PocketSyncOptions` to sync existing records on startup with default value `true`
- Dev: Add more unit tests

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
