/// Independent ACP business payloads, commands and borrowed observations.
///
/// Payloads mirror the stable v1 types in agent-client-protocol-schema 1.16.0.
/// This library does not decode JSON-RPC or materialize Native conversation data.
library;

export 'src/acp_sessions/domain/acp_values.dart';
export 'src/acp_sessions/domain/acp_content.dart';
export 'src/acp_sessions/domain/acp_session_payloads.dart';
export 'src/acp_sessions/domain/acp_updates.dart';
export 'src/acp_sessions/domain/acp_business_models.dart';
export 'src/acp_sessions/domain/acp_business_port.dart';
export 'src/acp_sessions/data/acp_session_client.dart';
export 'src/models/acp_models.dart' show AcpAuthMethodKindView;
