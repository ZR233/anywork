import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';

import '../state/thread_status_state.dart';

enum ModelRouteEditBlock { unavailable, frozen, botManaged, running, inactive }

/// Immutable presentation and typed intent only; no Session/read handle crosses
/// this feature's public connector boundary.
typedef ConversationModelRouteProps = ({
  ({String? runtimeEpoch, int? incarnation, int generation}) source,
  WorkspaceThreadRecord? thread,
  ThreadModelRoute? route,
  ModelRouteEditBlock? blocked,
  bool reading,
  StudioFailure? error,
});

typedef ThreadModelRouteWriter =
    OperationTicket<ThreadModelRouteCommandReply> Function(
      ModelSelection selection,
    );

WorkspaceThreadRecord? currentRouteThread(
  ThreadMetadataState? metadata,
  String threadId,
) {
  final read = metadata?.value;
  return metadata?.projection.sync.phase == ResourceSyncPhase.ready &&
          read is ReadyReadValue<WorkspaceThreadRecord, ProductEntityRef> &&
          read.current.origin == metadata?.projection.stamp?.origin &&
          read.current.value.id == threadId
      ? read.current.value
      : null;
}

ThreadModelRoute? currentModelRoute(ThreadStatusViewState state) {
  final configuration = state.configuration;
  final origin = configuration?.stamp;
  final material = state.configurationRead;
  final header = material.header;
  final route = header?.route;
  if (origin == null ||
      route == null ||
      material.error != null ||
      configuration?.sync.phase != FacetSyncPhase.ready ||
      origin.facet != ThreadFacet.configuration ||
      header?.scope.runtimeEpoch != origin.runtimeEpoch ||
      header?.scope.incarnation != origin.incarnation ||
      route.revision != configuration?.value?.modelRoute?.revision) {
    return null;
  }
  final accountId = material.textOf(route.accountId);
  final modelId = material.textOf(route.modelId);
  final botId = material.textOf(route.botId);
  final effort = material.textOf(route.effort);
  final reason = material.textOf(route.unavailableReason);
  // An unread/failed nullable field is not evidence of its absence, especially
  // bot ownership. Never infer ordinary edit permission from a partial read.
  if (accountId == null ||
      modelId == null ||
      route.botId != null && botId == null ||
      route.effort != null && effort == null ||
      route.unavailableReason != null && reason == null) {
    return null;
  }
  return ThreadModelRoute(
    botId: botId,
    accountId: accountId,
    modelId: modelId,
    effort: effort,
    revision: route.revision,
    available: route.available,
    unavailableReason: reason,
  );
}

ModelRouteEditBlock? modelRouteEditBlock(
  ThreadStatusViewState state,
  WorkspaceThreadRecord? thread,
  ThreadModelRoute? route,
) {
  if (thread == null) return ModelRouteEditBlock.unavailable;
  if (!thread.isRoot) return ModelRouteEditBlock.frozen;
  if (route == null) return ModelRouteEditBlock.unavailable;
  if (route.botId != null) return ModelRouteEditBlock.botManaged;
  final execution = state.execution;
  final origin = state.configuration?.stamp;
  if (execution?.sync.phase != FacetSyncPhase.ready ||
      execution?.value == null ||
      execution?.stamp?.runtimeEpoch != origin?.runtimeEpoch ||
      execution?.stamp?.incarnation != origin?.incarnation ||
      state.configuration?.value?.sources.closing != false) {
    return ModelRouteEditBlock.unavailable;
  }
  if (const {
    ThreadStatus.closing,
    ThreadStatus.closed,
    ThreadStatus.faulted,
  }.contains(execution?.value?.status)) {
    return ModelRouteEditBlock.inactive;
  }
  if (execution?.value?.status != ThreadStatus.idle ||
      execution?.value?.activeTurn != null ||
      execution?.value?.interactions.pending != 0) {
    return ModelRouteEditBlock.running;
  }
  // Authoring/workflow activity is deliberately not an additional restriction.
  return null;
}
