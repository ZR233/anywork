import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';

import '../app/app_graph.dart';
import '../diagnostics/contracts/timeline_diagnostics.dart';
import '../features/conversation/state/composer_view_state.dart';
import '../features/conversation/state/conversation_view_state.dart';
import '../features/conversation/state/editor_keys.dart';
import '../features/conversation/state/plan_view_state.dart';
import '../features/conversation/state/thread_status_state.dart';
import '../features/workspace/state/sidebar_view_state.dart';
import '../features/workspace/state/workspace_view_state.dart';
import 'driver_snapshot.dart';

/// Borrow only values of already mounted presentation owners. A Driver request
/// must not instantiate a provider, create a draft, query a directory or open a
/// Session just to improve diagnostics.
final class DriverViewFacts {
  const DriverViewFacts({
    this.workspace,
    this.sidebar,
    this.startComposer,
    this.threadComposer,
    this.conversation,
    this.status,
    this.plan,
  });
  final WorkspaceViewState? workspace;
  final SidebarViewState? sidebar;
  final ComposerViewState? startComposer;
  final ComposerViewState? threadComposer;
  final ConversationViewState? conversation;
  final ThreadStatusViewState? status;
  final PlanViewState? plan;
}

/// Synchronous request-local capture of this graph's canonical mirrors.
/// AppGraph is only the composition input; none of its owners escape in values.
DriverSnapshot captureDriverSnapshot(
  AppGraph graph, {
  required DriverViewFacts visible,
  required DriverBotsObservation bots,
}) {
  final selection = graph.workspace.state.value.selection;
  final selected = selection.threadId;
  final active = graph.conversation.active.value;
  final session = !selection.needsOpen && active?.threadId == selected
      ? active
      : null;
  final metadata = visible.workspace?.selectedMetadata;
  final thread = metadata?.projection.sync.phase == ResourceSyncPhase.ready
      ? currentDriverRead(metadata?.value, metadata?.projection.stamp?.origin)
      : null;
  final currentThread = thread?.id == selected ? thread : null;
  final project = visible.workspace?.selectedProject;
  final agentDirectory = graph.workspace.agents.value;
  String? root;
  List<AgentDirectoryEntry>? agents;
  StudioFailure? directoryError;
  if (selected != null) {
    try {
      root = AgentDirectoryQueries.rootThreadId(
        threadId: selected,
        directory: agentDirectory,
      );
      if (root != null) {
        agents = AgentDirectoryQueries.forRoot(
          rootThreadId: root,
          directory: agentDirectory,
        );
      }
    } on StudioFailure catch (error) {
      // An incomplete/stale directory is Unknown, never a reconstructed tree
      // from Thread windows or hot Sessions. Preserve the typed failure.
      directoryError = error;
    }
  }
  final page = visible.sidebar?.pages[selection.projectId]?.directory;
  final display = graph.timelineDiagnostics.capture();
  final displayMatches =
      selected != null &&
      !selection.needsOpen &&
      session != null &&
      display.timeline?.threadId == selected;
  return DriverSnapshot(
    selection: selection,
    project: project?.id == selection.projectId ? project : null,
    thread: currentThread,
    rootThreadId: root,
    directory: page?.projection.sync.phase == ResourceSyncPhase.ready
        ? currentDriverRows(page!.threads, page.projection.stamp?.origin)
        : null,
    directoryHasMore: page?.projection.sync.phase == ResourceSyncPhase.ready
        ? page?.projection.header?.hasMore
        : null,
    agents: agents,
    agentDirectoryError: directoryError,
    execution: session?.execution.value,
    metrics: session?.metrics.value,
    context: session?.context.value,
    threadConfiguration: session?.configuration.value,
    authoring: session?.authoring.value,
    interactions: session?.interactions.value,
    startDraft:
        selection.projectId != null &&
            visible.startComposer?.key ==
                ComposerKey.start(projectId: selection.projectId!)
        ? visible.startComposer?.startDraft
        : null,
    composer:
        session != null &&
            visible.threadComposer?.key ==
                ComposerKey.thread(threadId: session.threadId)
        ? visible.threadComposer?.draft
        : null,
    configuration: graph.configuration.state.value,
    models: graph.models.state.value,
    operations: graph.operations.records.value,
    persistence: graph.persistence.state.value,
    recovery: graph.recovery.state.value,
    updates: graph.updates.state.value,
    startup: graph.startup.state.value,
    display: displayMatches
        ? display
        : const TimelineDiagnosticsSnapshot(
            timeline: null,
            timelineScroll: null,
          ),
    conversation:
        session != null &&
            visible.conversation?.threadId == selected &&
            visible.conversation?.execution?.stamp ==
                session.execution.value.stamp
        ? visible.conversation
        : null,
    status:
        session != null &&
            visible.status?.threadId == selected &&
            visible.status?.execution?.stamp == session.execution.value.stamp
        ? visible.status
        : null,
    plan:
        session != null &&
            visible.plan?.threadId == selected &&
            visible.plan?.origin == session.authoring.value.stamp
        ? visible.plan
        : null,
    bots: bots,
  );
}

/// Never promote `previous` material to current evidence. Callers additionally
/// validate the owning projection/reference when a header provides one.
T? currentDriverRead<T, R>(
  ReadValue<T, R>? value,
  ProductReadOrigin? origin, {
  R? reference,
}) => switch (value) {
  ReadyReadValue<T, R>(:final current)
      when origin != null &&
          current.origin == origin &&
          (reference == null || current.reference == reference) =>
    current.value,
  _ => null,
};

/// A current partial page remains partial; unavailable/incomplete rows are not
/// converted to a successful empty page. There is no last-known fallback.
List<T>? currentDriverRows<T>(
  CollectionMirror<T> mirror,
  ProductReadOrigin? origin,
) {
  if (mirror is! CurrentCollectionMirror<T> ||
      origin == null ||
      mirror.window.origin != origin) {
    return null;
  }
  final window = mirror.window;
  final rows = <T>[];
  for (final reference in window.entries) {
    final row = window.rows[reference.entry];
    if (row is! ReadyReadValue<T, ProductEntityRef> ||
        row.current.origin != origin ||
        row.current.reference != reference) {
      return null;
    }
    rows.add(row.current.value);
  }
  return List.unmodifiable(rows);
}
