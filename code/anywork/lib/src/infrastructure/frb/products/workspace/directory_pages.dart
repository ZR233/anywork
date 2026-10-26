import 'package:anywork_client/workspace_ports.dart';

import '../../../../rust/api/studio/products/read/agent_directory.dart'
    as agents;
import '../../../../rust/api/studio/products/read/project_directory.dart'
    as projects;
import '../../../../rust/api/studio/products/read/thread_directory.dart'
    as threads;
import '../../shared/exact_numbers.dart';
import '../../shared/read_converters.dart';
import '../identity_converters.dart';
import 'directory_values.dart';

ProjectDirectoryEntryPage projectEntriesFromBridge(
  projects.BridgeProjectDirectoryEntryPage value,
) => ProjectDirectoryEntryPage(
  collection: collectionRefFromBridge(value.collection),
  offset: exactU64(value.offset, 'Project entry offset'),
  items: [for (final item in value.items) entityRefFromBridge(item)],
  nextOffset: nullableU64(value.nextOffset, 'Project entry next offset'),
);

ThreadDirectoryEntryPage threadEntriesFromBridge(
  threads.BridgeThreadDirectoryEntryPage value,
) => ThreadDirectoryEntryPage(
  collection: collectionRefFromBridge(value.collection),
  items: [for (final item in value.items) entityRefFromBridge(item)],
  nextCursor: nullableReadText(value.nextCursor),
  hasMore: value.hasMore,
);

AgentDirectoryEntryPage agentEntriesFromBridge(
  agents.BridgeAgentDirectoryEntryPage value,
) => AgentDirectoryEntryPage(
  collection: collectionRefFromBridge(value.collection),
  offset: exactU64(value.offset, 'Agent entry offset'),
  items: [for (final item in value.items) entityRefFromBridge(item)],
  nextOffset: nullableU64(value.nextOffset, 'Agent entry next offset'),
);

ProjectRecordReadPage projectRecordsFromBridge(
  projects.BridgeProjectRecordReadPage value,
) => ProjectRecordReadPage(
  listId: exactU64(value.listId, 'Project list identity'),
  offset: exactU64(value.offset, 'Project list offset'),
  total: exactU64(value.total, 'Project list total'),
  items: [for (final item in value.items) projectRecordReadFromBridge(item)],
  nextOffset: nullableU64(value.nextOffset, 'Project list next offset'),
);

WorkspaceThreadRecordReadPage threadRecordsFromBridge(
  threads.BridgeWorkspaceThreadRecordReadPage value,
) => WorkspaceThreadRecordReadPage(
  listId: exactU64(value.listId, 'Thread list identity'),
  offset: exactU64(value.offset, 'Thread list offset'),
  total: exactU64(value.total, 'Thread list total'),
  items: [for (final item in value.items) workspaceThreadReadFromBridge(item)],
  nextOffset: nullableU64(value.nextOffset, 'Thread list next offset'),
);

AgentDirectoryEntryReadPage agentRecordsFromBridge(
  agents.BridgeAgentDirectoryEntryReadPage value,
) => AgentDirectoryEntryReadPage(
  listId: exactU64(value.listId, 'Agent list identity'),
  offset: exactU64(value.offset, 'Agent list offset'),
  total: exactU64(value.total, 'Agent list total'),
  items: [for (final item in value.items) agentDirectoryReadFromBridge(item)],
  nextOffset: nullableU64(value.nextOffset, 'Agent list next offset'),
);
