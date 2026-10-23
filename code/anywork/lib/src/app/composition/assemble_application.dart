import 'dart:async';

import 'package:anywork_client/account_usage.dart';
import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/drafts.dart';
import 'package:anywork_client/lsp.dart';
import 'package:anywork_client/mcp.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/modes.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/persistence.dart';
import 'package:anywork_client/recovery.dart';
import 'package:anywork_client/remote.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/resources_ports.dart' show ResourceBudget;
import 'package:anywork_client/skills.dart';
import 'package:anywork_client/updates_ports.dart';
import 'package:anywork_client/workspace_ports.dart';

import '../../features/conversation/presentation_api.dart' show TimelineCoordinator;
import '../app_graph.dart';
import '../bootstrap/application_bootstrap.dart';
import '../bootstrap/automatic_updates_startup.dart';
import '../lifecycle/application_exit_coordinator.dart';
import '../lifecycle/exit_notice.dart';
import '../lifecycle/exit_participant.dart';
import '../lifecycle/native_exit_host.dart';
import 'workspace_conversation_binding.dart';

/// Final assembly shared by production, demo and Driver. All inputs are real
/// owners from this application's factories; no default Repository, fake
/// success, provider mirror or cross-Graph resource is constructed here.
/// The caller retains inputs if construction fails before ownership transfer.
AppGraph assembleApplication({
  required ConfigurationRepository configuration,
  required ModelsRepository models,
  required ModesRepository modes,
  required AccountUsageRepository accountUsage,
  required StatisticsRepository statistics,
  required WorkspaceRepository workspace,
  required StartupRepository startup,
  required ConversationRepository conversation,
  required ConversationDemand conversationDemand,
  required DraftsRepository drafts,
  required RemoteRepository remote,
  required McpRepository mcp,
  required LspRepository lsp,
  required SkillsRepository skills,
  required RecoveryRepository recovery,
  required PersistenceRepository persistence,
  required UpdatesRepository updates,
  required UpdatesLifecycle updatesLifecycle,
  required OperationRegistry operations,
  required ResourceBudget budget,
  required ApplicationLifecyclePort lifecycle,
  required NativeExitHost host,
  required bool automaticUpdatesEnabled,
  List<ApplicationCloseParticipant> additionalParticipants = const [],
  Future<void> Function()? releaseDesktopShell,
}) {
  // Capture before any constructor can call outward. A caller's mutable alias
  // cannot add or remove exit responsibilities after this assembly boundary.
  final additional = List<ApplicationCloseParticipant>.unmodifiable(additionalParticipants);
  final selection = WorkspaceConversationBinding(workspace: workspace, demand: conversationDemand);
  final automaticUpdates = AutomaticUpdatesStartup(updates: updates,
    lifecycle: updatesLifecycle, enabled: automaticUpdatesEnabled);
  final bootstrap = ApplicationBootstrap(startup: startup, attachDomains: (ready) async {
    // This binding retains a successful registration across a later gate/read
    // failure; its transactional start is idempotent on explicit attach retry.
    selection.start();
    // One owner registers the observer before loadValue, gates on the complete
    // current canonical value, and joins both the gate and its original reads.
    // Disabled local capability neither reads nor writes canonical state.
    await automaticUpdates.startAfterRuntimeReady(ready);
  });
  final producers = ApplicationEditProducerRegistry();
  final timeline = TimelineCoordinator(conversations: conversation);
  Future<CloseReport>? detachedTimeline;
  void detachTimeline() {
    if (detachedTimeline != null) return;
    detachedTimeline = Future<CloseReport>.sync(timeline.close);
    // The exact Future is retained and returned to the participant below. This
    // observer prevents an unhandled error before native arming completes; it
    // does not erase the original failure or replace its close/join report.
    unawaited(detachedTimeline!.then<void>((_) {}, onError: (Object _, StackTrace __) {}));
  }
  final exit = ApplicationExitCoordinator(
    lifecycle: lifecycle, host: host, editProducers: producers,
    sealOperations: operations.seal, detachPresentation: detachTimeline,
    readyUpdateVersion: () {
      final value = updates.state.value;
      if (value.projection.sync.phase != ResourceSyncPhase.ready ||
          value.projection.header?.brief is! ReadyUpdatesBrief) return null;
      return switch (value.value) {
        ReadyReadValue<UpdatesValue, UpdatesReadRef>(current: final current)
            when current.origin == value.projection.stamp?.origin &&
                current.reference == value.projection.header?.reference => switch (current.value) {
          ReadyUpdatesValue(:final update) => update.version,
          _ => null,
        },
        _ => null,
      };
    },
    releaseDesktopShell: releaseDesktopShell,
    presentNotice: presentApplicationExitNotice,
    participants: [
      // Seal injected observers before domain seals can publish their final
      // values. Their actual close/join runs with every other original owner.
      ...additional,
      ApplicationCloseParticipant(name: 'workspace-conversation-binding', seal: selection.seal,
        close: selection.close, retryCleanup: selection.retryCleanup),
      ApplicationCloseParticipant(name: 'application-bootstrap', seal: bootstrap.seal,
        close: bootstrap.close, retryCleanup: bootstrap.retryCleanup),
      ApplicationCloseParticipant(name: 'automatic-updates-startup', seal: automaticUpdates.seal,
        close: automaticUpdates.close, retryCleanup: automaticUpdates.retryCleanup),
      ApplicationCloseParticipant(name: 'timeline-presentation', seal: detachTimeline,
        close: ({deadline}) => detachedTimeline ?? timeline.close(deadline: deadline),
        retryCleanup: timeline.retryCleanup),
      ApplicationCloseParticipant(name: 'startup', seal: startup.seal,
        close: startup.close, retryCleanup: startup.retryCleanup),
      ApplicationCloseParticipant(name: 'workspace', seal: workspace.seal,
        close: workspace.close, retryCleanup: workspace.retryCleanup),
      ApplicationCloseParticipant(name: 'conversation', seal: conversation.seal,
        close: conversation.close, retryCleanup: conversation.retryCleanup),
      ApplicationCloseParticipant(name: 'drafts', seal: drafts.seal,
        close: drafts.close, retryCleanup: drafts.retryCleanup),
      ApplicationCloseParticipant(name: 'configuration', seal: configuration.seal,
        close: configuration.close, retryCleanup: configuration.retryCleanup),
      ApplicationCloseParticipant(name: 'models', seal: models.seal,
        close: models.close, retryCleanup: models.retryCleanup),
      ApplicationCloseParticipant(name: 'modes', seal: modes.seal,
        close: modes.close, retryCleanup: modes.retryCleanup),
      ApplicationCloseParticipant(name: 'account-usage', seal: accountUsage.seal,
        close: accountUsage.close, retryCleanup: accountUsage.retryCleanup),
      ApplicationCloseParticipant(name: 'statistics', seal: statistics.seal,
        close: statistics.close, retryCleanup: statistics.retryCleanup),
      ApplicationCloseParticipant(name: 'remote', seal: remote.seal,
        close: remote.close, retryCleanup: remote.retryCleanup),
      ApplicationCloseParticipant(name: 'mcp', seal: mcp.seal,
        close: mcp.close, retryCleanup: mcp.retryCleanup),
      ApplicationCloseParticipant(name: 'lsp', seal: lsp.seal,
        close: lsp.close, retryCleanup: lsp.retryCleanup),
      ApplicationCloseParticipant(name: 'skills', seal: skills.seal,
        close: skills.close, retryCleanup: skills.retryCleanup),
      ApplicationCloseParticipant(name: 'recovery', seal: recovery.seal,
        close: recovery.close, retryCleanup: recovery.retryCleanup),
      ApplicationCloseParticipant(name: 'persistence', seal: persistence.seal,
        close: persistence.close, retryCleanup: persistence.retryCleanup),
      ApplicationCloseParticipant(name: 'updates', seal: updates.seal,
        close: updates.close, retryCleanup: updates.retryCleanup),
    ],
  );
  return AppGraph.assembled(
    configuration: configuration, models: models, modes: modes,
    accountUsage: accountUsage, statistics: statistics,
    workspace: workspace, startup: startup, conversation: conversation,
    drafts: drafts, remote: remote, mcp: mcp, lsp: lsp, skills: skills,
    recovery: recovery, persistence: persistence, updates: updates,
    operations: operations.observations, budget: budget, timeline: timeline,
    editProducers: producers, bootstrap: bootstrap, automaticUpdates: automaticUpdates,
    exitCoordinator: exit, host: host,
  );
}
