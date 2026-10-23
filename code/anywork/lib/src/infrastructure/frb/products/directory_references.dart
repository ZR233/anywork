import 'package:anywork_client/workspace.dart';

import '../../../rust/api/studio/products/references.dart' as native;
import '../shared/exact_numbers.dart';
import 'identity_converters.dart';

ProjectDirectoryReadRef projectReadRefFromBridge(native.BridgeProjectDirectoryReadRef value) => ProjectDirectoryReadRef(
  entry: exactU64(value.entry, 'project directory read entry'), revision: exactU64(value.revision, 'project directory read revision'),
);
ThreadDirectoryReadRef threadDirectoryReadRefFromBridge(native.BridgeThreadDirectoryReadRef value) => ThreadDirectoryReadRef(
  entry: exactU64(value.entry, 'Thread directory read entry'), revision: exactU64(value.revision, 'Thread directory read revision'),
);
AgentDirectoryReadRef agentReadRefFromBridge(native.BridgeAgentDirectoryReadRef value) => AgentDirectoryReadRef(
  entry: exactU64(value.entry, 'Agent directory read entry'), revision: exactU64(value.revision, 'Agent directory read revision'),
);

native.BridgeProjectDirectoryReadRef projectReadRefToBridge(ProjectDirectoryReadRef value) => native.BridgeProjectDirectoryReadRef(
  entry: nativeU64(value.entry, 'project directory read entry'), revision: nativeU64(value.revision, 'project directory read revision'),
);
native.BridgeThreadDirectoryReadRef threadDirectoryReadRefToBridge(ThreadDirectoryReadRef value) => native.BridgeThreadDirectoryReadRef(
  entry: nativeU64(value.entry, 'Thread directory read entry'), revision: nativeU64(value.revision, 'Thread directory read revision'),
);
native.BridgeAgentDirectoryReadRef agentReadRefToBridge(AgentDirectoryReadRef value) => native.BridgeAgentDirectoryReadRef(
  entry: nativeU64(value.entry, 'Agent directory read entry'), revision: nativeU64(value.revision, 'Agent directory read revision'),
);

ProjectDirectoryReadTarget projectTargetFromBridge(native.BridgeProjectDirectoryReadTarget value) => ProjectDirectoryReadTarget(
  origin: productOriginFromBridge(value.origin), reference: projectReadRefFromBridge(value.reference),
);
ThreadDirectoryReadTarget threadDirectoryTargetFromBridge(native.BridgeThreadDirectoryReadTarget value) => ThreadDirectoryReadTarget(
  origin: productOriginFromBridge(value.origin), reference: threadDirectoryReadRefFromBridge(value.reference),
);
AgentDirectoryReadTarget agentTargetFromBridge(native.BridgeAgentDirectoryReadTarget value) => AgentDirectoryReadTarget(
  origin: productOriginFromBridge(value.origin), reference: agentReadRefFromBridge(value.reference),
);
