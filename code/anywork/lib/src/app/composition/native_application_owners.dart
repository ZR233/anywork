import 'dart:async';

import 'package:anywork_client/account_usage_ports.dart';
import 'package:anywork_client/bots_ports.dart';
import 'package:anywork_client/configuration_ports.dart';
import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/drafts_ports.dart';
import 'package:anywork_client/lsp_ports.dart';
import 'package:anywork_client/mcp_ports.dart';
import 'package:anywork_client/models_ports.dart';
import 'package:anywork_client/modes_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/persistence_ports.dart';
import 'package:anywork_client/recovery_ports.dart';
import 'package:anywork_client/remote_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/skills_ports.dart';
import 'package:anywork_client/updates_ports.dart';
import 'package:anywork_client/workspace_ports.dart';

import '../../infrastructure/frb/conversation/command_port.dart';
import '../../infrastructure/frb/conversation/timeline_port.dart';
import '../../infrastructure/frb/demo/demo_timeline_content.dart';
import '../../infrastructure/frb/drafts/attachment_admission_port.dart';
import '../../infrastructure/frb/drafts/attachment_binary_port.dart';
import '../../infrastructure/frb/drafts/new_thread_creation_port.dart';
import '../../infrastructure/frb/products/account_usage/account_usage_port.dart';
import '../../infrastructure/frb/products/bots/bots_port.dart';
import '../../infrastructure/frb/products/configuration/configuration_port.dart';
import '../../infrastructure/frb/products/lsp/lsp_port.dart';
import '../../infrastructure/frb/products/mcp/mcp_port.dart';
import '../../infrastructure/frb/products/models/models_port.dart';
import '../../infrastructure/frb/products/modes/modes_port.dart';
import '../../infrastructure/frb/products/persistence/persistence_port.dart';
import '../../infrastructure/frb/products/recovery/recovery_port.dart';
import '../../infrastructure/frb/products/remote/remote_port.dart';
import '../../infrastructure/frb/products/skills/skills_port.dart';
import '../../infrastructure/frb/products/startup/startup_port.dart';
import '../../infrastructure/frb/products/statistics/statistics_port.dart';
import '../../infrastructure/frb/products/updates/updates_port.dart';
import '../../infrastructure/frb/products/workspace/workspace_port.dart';
import '../../infrastructure/frb/workspace/application_lifecycle_port.dart';
import '../../platform/desktop_tray.dart';
import '../../platform/error_log.dart';
import '../../platform/studio_platform.dart';
import '../app_graph.dart';
import '../bootstrap/application_assembly_failure.dart';
import '../bootstrap/automatic_updates_startup.dart';
import '../lifecycle/exit_participant.dart';
import '../lifecycle/native_exit_host.dart';
import 'assemble_application.dart';
import 'conversation_context.dart';
import 'native_clipboard_staging.dart';
import 'native_conversation_observation.dart';
import 'workspace_archive_binding.dart';

/// Composition owners only. Domain actions remain on their own repositories;
/// this result cannot serve as a writable Client or a second business mirror.
final class NativeApplication {
  NativeApplication._({
    required this.graph,
    required this.bots,
    required this.tray,
    required this._constructing,
  });

  final AppGraph graph;
  final BotsRepository bots;
  final DesktopTrayController tray;
  final _ConstructingOwners _constructing;

  /// Launch retains rollback until widget handoff. Join these same concrete
  /// owners without arming the normal native host-exit coordinator.
  Future<CloseReport> rollback({void Function()? disposeContainer}) {
    if (disposeContainer != null) {
      _constructing.retainContainer(disposeContainer);
    }
    return _constructing.release();
  }

  /// Only a successful synchronous widget handoff transfers responsibility to
  /// the graph's runtime exit coordinator.
  void completeLaunch() => _constructing.transfer();
}

/// The sole production/Driver assembly. Constructors install local owners only:
/// StartupRepository.start later loads the library through this real port.
/// No binding, platform call, feed or business command is started here.
Future<NativeApplication> createNativeApplicationOwners({
  bool driver = false,

  /// Demo run selection. Demo shares this single assembly and substitutes native
  /// port implementations only; it never bypasses a canonical Repository.
  bool demo = const bool.fromEnvironment('ANYWORK_DEMO'),
  StartupPort Function(StartupPort port)? decorateStartup,

  /// Decorates the real content-port implementation (native or demo) for Driver
  /// fault injection. It never replaces the source with a second one.
  TimelineTransport Function(TimelineTransport port)? decorateTimeline,
  List<ApplicationCloseParticipant> additionalParticipants = const [],
}) async {
  // Decoration happens before any Repository acquires local resources. It
  // decorates the real library-loading owner, never a second FRB initializer.
  final nativeStartup = createStartupPort();
  final startupPort = decorateStartup?.call(nativeStartup) ?? nativeStartup;
  final budget = ResourceBudget();
  final operations = OperationRegistry(
    clientId: 'native-${newStudioCorrelationId()}',
    budget: budget,
  );
  final constructing = _ConstructingOwners();
  constructing.retain(
    'operations',
    operations.seal,
    _closedConstructionOwner,
    _closedConstructionOwner,
  );
  try {
    // Accept each supplied capability before any further fallible constructor
    // or list access. Even partial snapshot failure retains accepted owners.
    final additional = <ApplicationCloseParticipant>[];
    for (final participant in additionalParticipants) {
      constructing.add(participant, sealFirst: true);
      additional.add(participant);
    }
    // The factories require this same budget/recorder. Models' target receiver
    // and Workspace's submission capability are borrowed from their owners.
    final models = createModelsRepository(
      port: const FrbModelsPort(),
      budget: budget,
    );
    constructing.retain(
      'models',
      models.repository.seal,
      models.repository.close,
      models.repository.retryCleanup,
    );
    final configuration = createConfigurationRepository(
      port: const FrbConfigurationPort(),
      budget: budget,
      operations: operations,
      modelTargets: models.targets,
    );
    constructing.retain(
      'configuration',
      configuration.seal,
      configuration.close,
      configuration.retryCleanup,
    );
    final modes = createModesRepository(
      port: createModesPort(),
      budget: budget,
      operations: operations,
    );
    constructing.retain('modes', modes.seal, modes.close, modes.retryCleanup);
    final accountUsage = createAccountUsageRepository(
      port: createAccountUsagePort(),
      budget: budget,
      operations: operations,
      configuration: configuration,
    );
    constructing.retain(
      'account-usage',
      accountUsage.seal,
      accountUsage.close,
      accountUsage.retryCleanup,
    );
    final statistics = createStatisticsRepository(
      port: createStatisticsPort(),
      budget: budget,
    );
    constructing.retain(
      'statistics',
      statistics.seal,
      statistics.close,
      statistics.retryCleanup,
    );
    final recovery = createRecoveryRepository(
      port: const FrbRecoveryPort(),
      budget: budget,
      operations: operations,
    );
    constructing.retain(
      'recovery',
      recovery.seal,
      recovery.close,
      recovery.retryCleanup,
    );
    final archive = WorkspaceArchiveBinding();
    final workspace = createWorkspaceRepository(
      port: createWorkspacePort(),
      budget: budget,
      operations: operations,
      recovery: recovery.state,
      archiveCapture: archive,
    );
    constructing.retain(
      'workspace',
      workspace.repository.seal,
      workspace.repository.close,
      workspace.repository.retryCleanup,
    );
    final startup = createStartupRepository(
      port: startupPort,
      budget: budget,
      operations: operations,
    );
    constructing.retain(
      'startup',
      startup.seal,
      startup.close,
      startup.retryCleanup,
    );
    final commands = FrbConversationCommandPort();
    // Demo runs substitute only this native port: the canonical Conversation
    // Repository, its demand, feeds and reducers stay exactly the production
    // ones. Decoration below wraps that same real owner.
    final nativeTimeline = demo
        ? DemoTimelineContent(seedDemoConversations: true)
        : const FrbTimelineTransport();
    final timelinePort =
        decorateTimeline?.call(nativeTimeline) ?? nativeTimeline;
    final conversation = createConversationRepository(
      port: const NativeConversationObservation(),
      context: WorkspaceConversationContext(
        workspace: workspace.repository,
        recovery: recovery,
      ),
      commands: commands,
      timeline: timelinePort,
      budget: budget,
      operations: operations,
    );
    constructing.retain(
      'conversation',
      conversation.repository.seal,
      conversation.repository.close,
      conversation.repository.retryCleanup,
    );
    final clipboard = NativeClipboardStaging();
    final drafts = createDraftsRepository(
      configuration: configuration,
      workspace: workspace.repository,
      submissionSelection: workspace.submissionSelection,
      conversations: conversation.repository,
      conversationDemand: conversation.demand,
      conversationCommands: commands,
      attachments: const FrbAttachmentAdmissionPort(),
      creations: const FrbNewThreadCreationPort(),
      binary: const FrbAttachmentBinaryPort(),
      budget: budget,
      operations: operations,
      clipboardImageStager: clipboard.stage,
      clipboardImageCleanup: clipboard.cleanup,
    );
    constructing.retain(
      'drafts',
      drafts.repository.seal,
      drafts.repository.close,
      drafts.repository.retryCleanup,
    );
    archive.bind(conversations: conversation.archive, drafts: drafts.archive);
    final remote = createRemoteRepository(
      port: const FrbRemotePort(),
      budget: budget,
      operations: operations,
    );
    constructing.retain(
      'remote',
      remote.seal,
      remote.close,
      remote.retryCleanup,
    );
    final mcp = createMcpRepository(
      port: const FrbMcpPort(),
      budget: budget,
      operations: operations,
    );
    constructing.retain('mcp', mcp.seal, mcp.close, mcp.retryCleanup);
    final lsp = createLspRepository(
      port: const FrbLspPort(),
      budget: budget,
      operations: operations,
    );
    constructing.retain('lsp', lsp.seal, lsp.close, lsp.retryCleanup);
    final skills = createSkillsRepository(
      port: const FrbSkillsPort(),
      budget: budget,
      operations: operations,
    );
    constructing.retain(
      'skills',
      skills.seal,
      skills.close,
      skills.retryCleanup,
    );
    final persistence = createPersistenceRepository(
      port: const FrbPersistencePort(),
      budget: budget,
      operations: operations,
    );
    constructing.retain(
      'persistence',
      persistence.seal,
      persistence.close,
      persistence.retryCleanup,
    );
    final bots = createBotsRepository(
      port: createBotsPort(),
      budget: budget,
      operations: operations,
    );
    // Bots 已是 assembleApplication 的一等参数（退出参与者由装配统一持有）；
    // 这里只保留装配失败时的回滚责任，不再重复加入 additionalParticipants。
    constructing.retain('bots', bots.seal, bots.close, bots.retryCleanup);
    final updatesEnabled =
        productionUpdatesEnabled ||
        (driver &&
            isWindowsPlatform &&
            !const bool.fromEnvironment('ANYWORK_DEMO'));
    final updates = createUpdatesRepository(
      port: createUpdatesPort(),
      budget: budget,
      operations: operations,
      controls: UpdateControls(enabled: updatesEnabled),
    );
    constructing.retain(
      'updates',
      updates.repository.seal,
      updates.repository.close,
      updates.repository.retryCleanup,
    );

    final lifecycle = const FrbApplicationLifecyclePort();
    final host = NativeExitHost();
    late final DesktopTrayController tray;
    final graph = assembleApplication(
      configuration: configuration,
      models: models.repository,
      modes: modes,
      accountUsage: accountUsage,
      statistics: statistics,
      workspace: workspace.repository,
      startup: startup,
      conversation: conversation.repository,
      conversationDemand: conversation.demand,
      drafts: drafts.repository,
      remote: remote,
      mcp: mcp,
      lsp: lsp,
      skills: skills,
      recovery: recovery,
      persistence: persistence,
      bots: bots,
      updates: updates.repository,
      updatesLifecycle: updates.lifecycle,
      operations: operations,
      budget: budget,
      lifecycle: lifecycle,
      host: host,
      automaticUpdatesEnabled: updatesEnabled,
      additionalParticipants: additional,
      retainForRollback: constructing.add,
      releaseDesktopShell: () => tray.dispose(),
    );
    tray = DesktopTrayController(
      host: host,
      requestExit: () => graph.exitCoordinator.requestHostExit(ExitIntent.exit),
    );
    Future<CloseReport> closeTray({DateTime? deadline}) async {
      await tray.dispose();
      return CloseReport(unresolved: const []);
    }

    constructing.retain('desktop-shell', () {}, closeTray, closeTray);
    return NativeApplication._(
      graph: graph,
      bots: bots,
      tray: tray,
      constructing: constructing,
    );
  } on Object catch (error, stack) {
    // Nothing native has opened. Join the original local owners (including
    // Drafts' configuration observation) instead of dropping partial assembly.
    // An unresolved close transfers responsibility to the startup attempt.
    final report = await constructing.release();
    if (!report.complete) {
      throw ApplicationAssemblyFailure(
        cause: error,
        stack: stack,
        report: report,
        retryCleanup: constructing.release,
      );
    }
    Error.throwWithStackTrace(error, stack);
  }
}

/// Construction rollback only, never a runtime resource owner/registry. On
/// success assembleApplication captures these same domain close capabilities.
final class _ConstructingOwners {
  final List<_ConstructionOwner> _owners = [];
  Future<CloseReport>? _releasing;
  void Function()? _disposeContainer;
  UnresolvedResource? _containerIssue;
  bool _rollbackStarted = false;
  bool _transferred = false;
  int _sequence = 0;

  void add(ApplicationCloseParticipant participant, {bool sealFirst = false}) {
    if (_rollbackStarted || _transferred) {
      throw StateError('Construction ownership is sealed.');
    }
    _owners.add(
      _ConstructionOwner(participant, AttemptId(++_sequence), sealFirst),
    );
  }

  ApplicationCloseParticipant retain(
    String name,
    void Function() seal,
    Future<CloseReport> Function({DateTime? deadline}) close,
    Future<CloseReport> Function({DateTime? deadline}) retryCleanup,
  ) {
    final participant = ApplicationCloseParticipant(
      name: name,
      seal: seal,
      close: close,
      retryCleanup: retryCleanup,
    );
    add(participant);
    return participant;
  }

  void retainContainer(void Function() dispose) {
    if (_rollbackStarted || _transferred) {
      throw StateError('Construction ownership is sealed.');
    }
    _disposeContainer = dispose;
  }

  void transfer() {
    if (_rollbackStarted) {
      throw StateError('A failed construction cannot be installed.');
    }
    _transferred = true;
    _owners.clear();
  }

  Future<CloseReport> release() {
    if (_transferred) {
      throw StateError('Construction ownership was transferred.');
    }
    final running = _releasing;
    if (running != null) {
      return running;
    }
    _rollbackStarted = true;
    final completion = Completer<CloseReport>();
    _releasing = completion.future;
    unawaited(
      _release().then(
        (report) {
          _releasing = null;
          completion.complete(report);
        },
        onError: (Object error, StackTrace stack) {
          _releasing = null;
          completion.completeError(error, stack);
        },
      ),
    );
    return completion.future;
  }

  Future<CloseReport> _release() async {
    // Before handoff, Provider disposal stops local observations; the real
    // domain/presentation joins below remain independent cleanup obligations.
    try {
      _disposeContainer?.call();
      _disposeContainer = null;
      _containerIssue = null;
    } on Object catch (error, stack) {
      _containerIssue = _constructionIssue(
        'provider-container',
        AttemptId(0),
        error,
        stack,
      );
    }
    // As with runtime exit, injected observers seal before domain publication.
    // Newly constructed presentation owners detach before Repository closes.
    for (final owner in [
      ..._owners.where((owner) => owner.sealFirst),
      ..._owners.reversed.where((owner) => !owner.sealFirst),
    ]) {
      owner.seal();
    }
    await Future.wait([for (final owner in _owners.reversed) owner.close()]);
    // Only an actual complete report AND a successful admission seal release
    // the capability. Unresolved owners keep their full report and retry.
    _owners.removeWhere((owner) => owner.complete);
    return CloseReport(
      unresolved: [
        ?_containerIssue,
        for (final owner in _owners) ...owner.unresolved,
      ],
    );
  }
}

Future<CloseReport> _closedConstructionOwner({DateTime? deadline}) async =>
    CloseReport(unresolved: const []);

final class _ConstructionOwner {
  _ConstructionOwner(this.participant, this.id, this.sealFirst);

  final ApplicationCloseParticipant participant;
  final AttemptId id;
  final bool sealFirst;
  CloseReport? _report;
  UnresolvedResource? _sealIssue;
  UnresolvedResource? _closeIssue;
  bool _sealed = false;
  bool _started = false;

  bool get complete =>
      _sealed && _closeIssue == null && _report?.complete == true;
  List<UnresolvedResource> get unresolved => [
    ?_sealIssue,
    ...?_report?.unresolved,
    ?_closeIssue,
  ];

  void seal() {
    if (_sealed) return;
    try {
      participant.seal();
      _sealed = true;
      _sealIssue = null;
    } on Object catch (error, stack) {
      _sealIssue = _constructionIssue(participant.name, id, error, stack);
    }
  }

  Future<void> close() async {
    final close = _started ? participant.retryCleanup : participant.close;
    _started = true;
    try {
      _report = await close();
      _closeIssue = null;
    } on Object catch (error, stack) {
      // A thrown retry is not a new report superseding the original issues.
      _closeIssue = _constructionIssue(participant.name, id, error, stack);
    }
  }
}

UnresolvedResource _constructionIssue(
  String owner,
  AttemptId id,
  Object error,
  StackTrace stack,
) {
  final failure = error is StudioFailure ? error : null;
  final correlation = failure?.correlationId.isNotEmpty == true
      ? failure!.correlationId
      : newStudioCorrelationId();
  recordDartError(
    error,
    stack,
    stage: 'application-assembly-cleanup',
    correlationId: correlation,
  );
  return UnresolvedResource(
    owner: owner,
    attemptId: id,
    issues: [
      FeedCloseIssue(
        diagnostic: StudioShutdownIssue(
          stage: 'application-assembly-cleanup',
          code: failure?.code.name ?? 'cleanupFailed',
          message:
              failure?.message ??
              'Application construction cleanup did not confirm.',
          retryable: failure?.retryable ?? true,
          correlationId: correlation,
        ),
        recovery: failure?.retryable == false
            ? CleanupRecovery.terminal
            : CleanupRecovery.retryClose,
      ),
    ],
  );
}
