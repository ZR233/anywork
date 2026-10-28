import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/features/conversation/state/timeline_view_state.dart';
import 'package:anywork/src/features/conversation/view_models/conversation_view_model.dart';
import 'package:anywork/src/features/workspace/view_models/sidebar_view_model.dart';
import 'package:anywork/src/features/workspace/view_models/workspace_view_model.dart';
import 'package:anywork/src/shared/driver_projection.dart'
    show currentDriverRows;
import 'package:anywork/src/shared/driver_snapshot.dart';
import 'package:anywork/src/shared/driver_snapshot_json.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace_ports.dart';
import 'package:anywork_client/statistics_ports.dart';
import 'package:anywork_client/recovery_ports.dart';

import '../../../../anywork_client/test/support/timeline_transport.dart';
import '../../../test_driver/driver_inspection.dart';
import 'application_environment.dart';
import 'selector_directory_port.dart';
import 'selector_environment.dart' show waitLatest;

/// Real application assembly. Native fixtures declare immutable material; all
/// facts below are captured by the production Driver projection, never a
/// replacement Client facade or a test-maintained business mirror.
final class DriverTestEnvironment {
  DriverTestEnvironment({StatisticsPort? statisticsPort})
    : application = ApplicationTestEnvironment(statisticsPort: statisticsPort)
        ..installHost();
  final ApplicationTestEnvironment application;
  final _subscriptions = <void Function()>[];

  Future<void> establish({
    required List<WorkspaceThreadRecord> threads,
    List<AgentDirectoryEntry>? agents,
    List<RecoveryIssueRead> recoveryIssues = const [],
  }) async {
    final native = application.domains.directory;
    native.threads
      ..clear()
      ..addAll(threads);
    native.agents =
        agents ??
        [
          for (final thread in threads)
            SelectorDirectoryPort.agentEntry(thread),
        ];
    application.domains.recoveryPort.preparedIssues = recoveryIssues;
    await application.domains.establish(catalog: false);
    await application.graph.workspace.loadAgents();
  }

  Future<void> mountDirectory({String projectId = 'project'}) async {
    final container = application.container;
    final workspace = container.listen(workspaceViewModelProvider, (_, _) {});
    final sidebar = container.listen(sidebarViewModelProvider, (_, _) {});
    _subscriptions.addAll([workspace.close, sidebar.close]);
    await container.read(workspaceViewModelProvider.future);
    await container.read(sidebarViewModelProvider.future);
    if (!container
        .read(sidebarViewModelProvider)
        .requireValue
        .expandedProjectIds
        .contains(projectId)) {
      container
          .read(sidebarViewModelProvider.notifier)
          .toggleExpanded(projectId);
    }
    await container.read(sidebarViewModelProvider.notifier).loadMore(projectId);
  }

  Future<void> openContent(
    StudioTimelineBaseline baseline, {
    String threadId = 'thread',
  }) async {
    await application.domains.selectThread(threadId);
    final opening = await application.domains.timeline.opened(0);
    opening.result.complete(TestTimelineConnection(initial: baseline));
    await timelineWhere((state) => state?.ready == true);
  }

  Future<void> failOpening(Object error, {String threadId = 'thread'}) async {
    await application.domains.selectThread(threadId);
    final opening = await application.domains.timeline.opened(0);
    opening.result.completeError(error);
    await timelineWhere(
      (state) => state?.connectionPhase == TimelineConnectionPhase.failed,
    );
  }

  Future<TimelineViewState?> timelineWhere(
    bool Function(TimelineViewState?) matches,
  ) {
    final result = Completer<TimelineViewState?>();
    final timeline = application.graph.timeline;
    final observation = timeline.changes.listen((value) {
      if (!result.isCompleted && matches(value)) result.complete(value);
    });
    final current = timeline.value;
    if (matches(current) && !result.isCompleted) result.complete(current);
    return result.future.whenComplete(observation.cancel);
  }

  DriverSnapshot capture() => DriverInspection(
    graph: application.graph,
    container: application.container,
  ).capture();

  String snapshotJson() => jsonEncode(capture().toJson());

  Future<void> waitAgents() async {
    // The native event contains refs, whereas the old fixture injected a fully
    // materialized aggregate. Finish that same public read before capturing.
    await application.graph.workspace.loadAgents();
    await waitLatest(application.graph.workspace.agents, (state) {
      final mirror = state.agents;
      return state.projection.sync.phase == ResourceSyncPhase.ready &&
          mirror is CurrentCollectionMirror<AgentDirectoryEntry> &&
          mirror.window.complete &&
          currentDriverRows(mirror, state.projection.stamp?.origin)?.length ==
              mirror.window.reference.total;
    });
  }

  /// Native delivery ACK precedes the independent immutable entity reads.
  /// Wait for the actual mounted presentation to contain those current rows.
  Future<void> waitDirectory(bool Function(DriverSnapshot) matches) async {
    final container = application.container;
    if (!container.exists(workspaceViewModelProvider) ||
        !container.exists(sidebarViewModelProvider)) {
      throw StateError('Only already-mounted Driver owners may be observed');
    }
    await container.read(sidebarViewModelProvider.notifier).loadMore('project');
    final done = Completer<void>();
    void check() {
      if (!done.isCompleted && matches(capture())) done.complete();
    }

    final workspace = container.listen(
      workspaceViewModelProvider,
      (_, _) => check(),
    );
    final sidebar = container.listen(
      sidebarViewModelProvider,
      (_, _) => check(),
    );
    final selected = application.graph.workspace.state.value.selection.threadId;
    final conversation =
        selected != null &&
            container.exists(conversationViewModelProvider(selected))
        ? container.listen(
            conversationViewModelProvider(selected),
            (_, _) => check(),
          )
        : null;
    check();
    await done.future.whenComplete(() {
      workspace.close();
      sidebar.close();
      conversation?.close();
    });
  }

  Iterable<ConversationSession> get knownSessions =>
      {
            for (final thread in application.domains.directory.threads)
              thread.id,
            for (final agent in application.domains.directory.agents)
              agent.threadId,
          }
          .map(application.graph.conversation.existingSession)
          .whereType<ConversationSession>();

  /// A real native delta removes only the directory entity. Agent membership
  /// remains the independent AgentDirectory source, exactly as in production.
  Future<void> removeDirectoryThread(String threadId) async {
    final page = application.container
        .read(sidebarViewModelProvider)
        .requireValue
        .pages['project']!
        .directory!;
    final window =
        (page.threads as CurrentCollectionMirror<WorkspaceThreadRecord>).window;
    final reference = window.entries.firstWhere(
      (ref) =>
          (window.rows[ref.entry]
                  as ReadyReadValue<WorkspaceThreadRecord, ProductEntityRef>)
              .current
              .value
              .id ==
          threadId,
    );
    final opening = application.domains.directory.threadFeeds.firstWhere(
      (open) => open.scope is! SingleThreadDirectoryScope,
    );
    final feed = opening.connection.feed;
    final revision = page.projection.stamp!.revision + 1;
    feed.emit(
      ThreadDirectoryFrame.data(
        deliverySequence: 2,
        event: ThreadDirectoryEvent.change(
          stamp: page.projection.stamp!.copyWith(revision: revision),
          baseRevision: revision - 1,
          value: ThreadDirectoryChange(
            header: page.projection.header!.copyWith(
              directoryRevision: revision,
            ),
            baseCollectionRevision: window.reference.revision,
            collection: window.reference.copyWith(
              revision: revision,
              total: window.reference.total - 1,
            ),
            upserted: const [],
            removedEntries: [reference.entry],
          ),
        ),
      ),
    );
    await feed.acknowledged(2);
  }

  /// Observable native activity, not a transport implementation. Captures before
  /// and after a Driver request must be equal, including cold metadata opens.
  Object get nativeActivity {
    final domains = application.domains;
    return (
      domains.directory.threadFeeds.length,
      domains.directory.metadataReads.length,
      domains.timeline.requests.length,
      application.skillsPort.openedProjects.length,
      domains.conversationPort.facets.execution.length,
      domains.conversationPort.facets.configuration.length,
    );
  }

  Future<void> close() async {
    for (final close in _subscriptions.reversed) {
      close();
    }
    _subscriptions.clear();
    await application.close();
  }
}
