/// SDK-only conversation domain. No transport or data implementation exports.
library;

export 'src/models/chat_models.dart';
export 'src/models/presentation_models.dart';
export 'src/conversation/domain/conversation_state.dart';
export 'src/conversation/domain/content_state.dart';
export 'src/conversation/domain/conversation_repository.dart';
export 'src/observation/latest_value.dart'
    show ValueObservation, Observation, LatestWatch;
export 'src/conversation/domain/content_lifecycle.dart';
export 'src/conversation/domain/conversation_watermark.dart';
export 'src/conversation/domain/conversation_errors.dart';

export 'conversation_ports.dart' show TimelineReader, TimelineTransport;
export 'src/conversation/data/conversation_read_scope.dart'
    show ConversationReadScope;
