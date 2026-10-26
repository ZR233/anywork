import 'package:anywork_client/configuration_ports.dart';

import '../../../../rust/api/studio/products/read/profile_values.dart'
    as native;
import '../../shared/read_converters.dart';
import 'scalar_values.dart';

AgentProfilesReadHeader profilesReadHeaderFromBridge(
  native.BridgeAgentProfilesReadHeader value,
) => AgentProfilesReadHeader(
  profiles: typedListFromBridge(value.profiles),
  diagnostics: typedListFromBridge(value.diagnostics),
);

AgentProfileRead profileReadFromBridge(native.BridgeAgentProfileRead value) =>
    AgentProfileRead(
      profileId: readTextFromBridge(value.profileId),
      displayName: readTextFromBridge(value.displayName),
      description: readTextFromBridge(value.description),
      whenToUse: readTextFromBridge(value.whenToUse),
      systemInstructions: readTextFromBridge(value.systemInstructions),
      accountId: readTextFromBridge(value.accountId),
      modelId: readTextFromBridge(value.modelId),
      effort: nullableReadText(value.effort),
      source: readTextFromBridge(value.source),
      revision: readTextFromBridge(value.revision),
      contentHash: readTextFromBridge(value.contentHash),
      system: value.system,
      enabled: value.enabled,
      workspaceMode: profileWorkspaceFromBridge(value.workspaceMode),
    );

ProfileDiagnosticRead profileDiagnosticFromBridge(
  native.BridgeProfileDiagnosticRead value,
) => ProfileDiagnosticRead(
  path: readTextFromBridge(value.path),
  message: readTextFromBridge(value.message),
);
