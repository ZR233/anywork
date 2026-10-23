import 'package:anywork_client/workspace.dart';

import '../../../rust/api/studio/products/feed/agent_directory.dart' as agents;
import '../../../rust/api/studio/products/feed/project_directory.dart' as projects;
import '../../../rust/api/studio/products/feed/thread_directory.dart' as threads;
import '../shared/read_converters.dart';
import 'directory_references.dart';
import 'source_converters.dart';

ProjectDirectoryHeader projectHeaderFromBridge(projects.BridgeProjectDirectoryHeader value) => ProjectDirectoryHeader(
  source: observedHeaderFromBridge(value.source),
  reference: value.reference == null ? null : projectReadRefFromBridge(value.reference!),
);

ThreadDirectoryHeader threadDirectoryHeaderFromBridge(threads.BridgeThreadDirectoryHeader value) => ThreadDirectoryHeader(
  source: observedHeaderFromBridge(value.source),
  reference: value.reference == null ? null : threadDirectoryReadRefFromBridge(value.reference!),
  directoryRevision: nullableU64(value.directoryRevision, 'Thread directory revision'),
  searchProjectRevision: nullableU64(value.searchProjectRevision, 'Thread search Project revision'),
  hasMore: value.hasMore,
  nextCursor: nullableReadText(value.nextCursor),
);

AgentDirectoryHeader agentHeaderFromBridge(agents.BridgeAgentDirectoryHeader value) => AgentDirectoryHeader(
  source: observedHeaderFromBridge(value.source),
  reference: value.reference == null ? null : agentReadRefFromBridge(value.reference!),
);
