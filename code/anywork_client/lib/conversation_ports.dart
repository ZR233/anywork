/// Explicit conversation transport capabilities for Repository/adapter assembly.
library;

export 'conversation.dart';
export 'src/conversation/data/conversation_command_port.dart';
export 'src/conversation/domain/stop_execution_reply.dart'
    show StopExecutionReply;
export 'src/conversation/data/conversation_demand.dart'
    show ConversationDemand, SubmissionExecutionLease;
export 'src/conversation/data/conversation_observation_port.dart'
    show
        ConversationObservationPort,
        ConversationContextPort,
        CreatedInputExecutionSource;
export 'src/conversation/data/conversation_repository.dart'
    show createConversationRepository;
export 'src/conversation/data/read_connections.dart';
export 'src/conversation/data/timeline_port.dart'
    show TimelineTransport, StudioTimelineConnection;
