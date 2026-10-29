/// SDK-only conversation domain. No transport or data implementation exports.
library;

export 'src/conversation/domain/conversation_models.dart';
export 'src/conversation/domain/activity_content.dart';
export 'src/conversation/domain/conversation_descriptor.dart';
export 'src/conversation/domain/conversation_state.dart';
export 'src/conversation/domain/content_state.dart';
export 'src/conversation/domain/conversation_repository.dart';
export 'src/observation/latest_value.dart'
    show ValueObservation, Observation, LatestWatch;
export 'src/conversation/domain/content_lifecycle.dart';
export 'src/conversation/domain/conversation_watermark.dart';
export 'src/conversation/domain/conversation_errors.dart';
export 'src/conversation/domain/user_input_reading.dart';
