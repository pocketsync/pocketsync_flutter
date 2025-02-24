import 'package:pocketsync_flutter/src/models/change_processing_response.dart';

class ChangeProcessingResponseFixtures {
  static final success = ChangeProcessingResponse(
    message: 'Changes processed successfully',
    processed: true,
    status: 'success',
  );
}
