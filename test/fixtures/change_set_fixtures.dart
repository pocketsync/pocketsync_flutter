import 'package:pocketsync_flutter/src/models/change_set.dart';

class ChangeSetFixtures {
  static final empty = ChangeSet(
    timestamp: 1672527600000,
    version: 1,
    updates: TableChanges({}),
    insertions: TableChanges({}),
    deletions: TableChanges({}),
  );

  static final withUpdates = ChangeSet(
    timestamp: 1672527600000,
    version: 1,
    updates: TableChanges(
      {
        'test_table': TableRows(
          [
            Row(
              primaryKey: 'id1',
              data: {
                'ps_global_id': 'id1',
                'name': 'updated',
                'timestamp': 1672527600000,
              },
              timestamp: 1672527600000,
              version: 1,
            )
          ],
        )
      },
    ),
    insertions: TableChanges({}),
    deletions: TableChanges({}),
  );

  static final withInsertions = ChangeSet(
    timestamp: 1672527600000,
    version: 1,
    updates: TableChanges({}),
    insertions: TableChanges(
      {
        'test_table': TableRows(
          [
            Row(
              primaryKey: 'id1',
              data: {
                'ps_global_id': 'id1',
                'name': 'test1',
                'timestamp': 1672527600000,
              },
              timestamp: 1672527600000,
              version: 1,
            )
          ],
        )
      },
    ),
    deletions: TableChanges({}),
  );

  static final withDeletions = ChangeSet(
    timestamp: 1672527600000,
    version: 1,
    updates: TableChanges({}),
    insertions: TableChanges({}),
    deletions: TableChanges(
      {
        'test_table': TableRows(
          [
            Row(
              primaryKey: 'primary_key',
              data: {
                'column1': 'value1',
                'column2': 'value2',
              },
              timestamp: 1672527600000,
              version: 1,
            )
          ],
        )
      },
    ),
  );

  static final withMultipleChanges = ChangeSet(
    timestamp: 1672527600000,
    version: 1,
    updates: TableChanges(
      {
        'test_table': TableRows(
          [
            Row(
              primaryKey: 'primary_key',
              data: {
                'column1': 'value1',
                'column2': 'value2',
              },
              timestamp: 1672527600000,
              version: 1,
            )
          ],
        )
      },
    ),
    insertions: TableChanges(
      {
        'test_table': TableRows(
          [
            Row(
              primaryKey: 'primary_key',
              data: {
                'column1': 'value1',
                'column2': 'value2',
              },
              timestamp: 1672527600000,
              version: 1,
            )
          ],
        )
      },
    ),
    deletions: TableChanges(
      {
        'test_table': TableRows(
          [
            Row(
              primaryKey: 'primary_key',
              data: {
                'column1': 'value1',
                'column2': 'value2',
              },
              timestamp: 1672527600000,
              version: 1,
            )
          ],
        )
      },
    ),
  );
}
