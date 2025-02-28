import 'package:pocketsync_flutter/src/models/change_log.dart';

import 'change_set_fixtures.dart';

class ChangeLogFixtures {
  static final insert = ChangeLog(
    id: 1,
    deviceId: 'device_id',
    receivedAt: DateTime(2020, 1, 1),
    processedAt: DateTime(2020, 1, 1),
    userIdentifier: 'user_identifier',
    changeSet: ChangeSetFixtures.withInsertions,
  );

  static final update = ChangeLog(
    id: 2,
    deviceId: 'device_id',
    receivedAt: DateTime(2020, 1, 1),
    processedAt: DateTime(2020, 1, 1),
    userIdentifier: 'user_identifier',
    changeSet: ChangeSetFixtures.withUpdates,
  );

  static updateWithTimestamp(int remoteTimestamp) {
    return ChangeLog(
      id: 2,
      deviceId: 'device_id',
      receivedAt: DateTime(2020, 1, 1),
      processedAt: DateTime(2020, 1, 1),
      userIdentifier: 'user_identifier',
      changeSet: ChangeSetFixtures.withUpdates.copyWith(
        timestamp: remoteTimestamp,
      ),
    );
  }
}
