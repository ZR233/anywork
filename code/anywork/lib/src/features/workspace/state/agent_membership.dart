import 'package:anywork_client/workspace.dart';

/// Presentation of the SDK's retired role rule, restricted to child members.
bool isRetiredAgentRow(AgentDirectoryEntry agent) =>
    agent.parentPath != null && isRetiredAgentRole(agent.role);
