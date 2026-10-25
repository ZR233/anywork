import 'dart:async';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/composition/application_container.dart';
import 'package:anywork/src/app/composition/assemble_application.dart';
import 'package:anywork/src/app/lifecycle/native_exit_host.dart';
import 'package:anywork_client/account_usage_ports.dart';
import 'package:anywork_client/bots_ports.dart';
import 'package:anywork_client/lsp_ports.dart';
import 'package:anywork_client/mcp_ports.dart';
import 'package:anywork_client/persistence_ports.dart';
import 'package:anywork_client/remote_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/skills_ports.dart';
import 'package:anywork_client/updates_ports.dart';
import 'package:anywork_client/workspace_ports.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../anywork_client/test/support/scripted_feed.dart';
import 'selector_environment.dart';

/// Real application assembly and all real repositories. Native ports provide
/// immutable material/gates only; no Client facade, reducer or VM is replaced.
/// Unused native capabilities throw rather than fabricating successful facts.
final class ApplicationTestEnvironment {
  ApplicationTestEnvironment({BotsPort? botsPort})
    : hostChannel = MethodChannel(
        'test.anywork/application-environment-${_nextHost++}',
      ) {
    final budget = domains.budget;
    final operations = domains.operations;
    startup = createStartupRepository(
      port: startupPort,
      budget: budget,
      operations: operations,
    );
    final usage = createAccountUsageRepository(
      port: _UnusedUsagePort(),
      budget: budget,
      operations: operations,
      configuration: domains.configuration,
    );
    final statistics = createStatisticsRepository(
      port: _UnusedStatisticsPort(),
      budget: budget,
    );
    final remote = createRemoteRepository(
      port: _UnusedRemotePort(),
      budget: budget,
      operations: operations,
    );
    final mcp = createMcpRepository(
      port: _UnusedMcpPort(),
      budget: budget,
      operations: operations,
    );
    final lsp = createLspRepository(
      port: _UnusedLspPort(),
      budget: budget,
      operations: operations,
    );
    skills = createSkillsRepository(
      port: skillsPort,
      budget: budget,
      operations: operations,
    );
    final persistence = createPersistenceRepository(
      port: _UnusedPersistencePort(),
      budget: budget,
      operations: operations,
    );
    final bots = createBotsRepository(
      port: botsPort ?? _UnusedBotsPort(),
      budget: budget,
      operations: operations,
    );
    final updates = createUpdatesRepository(
      port: _UnusedUpdatesPort(),
      budget: budget,
      operations: operations,
      controls: const UpdateControls(enabled: false),
    );
    graph = assembleApplication(
      configuration: domains.configuration,
      models: domains.models,
      modes: domains.modes,
      accountUsage: usage,
      statistics: statistics,
      workspace: domains.workspace,
      startup: startup,
      conversation: domains.conversations,
      conversationDemand: domains.demand,
      drafts: domains.drafts,
      remote: remote,
      mcp: mcp,
      lsp: lsp,
      skills: skills,
      bots: bots,
      recovery: domains.recovery,
      persistence: persistence,
      updates: updates.repository,
      updatesLifecycle: updates.lifecycle,
      operations: operations,
      budget: budget,
      lifecycle: lifecycle,
      host: NativeExitHost(channel: hostChannel),
      automaticUpdatesEnabled: false,
    );
    container = createApplicationContainer(graph);
  }

  static int _nextHost = 0;
  final MethodChannel hostChannel;
  final domains = SelectorEnvironment();
  final startupPort = ApplicationStartupPort();
  final skillsPort = RecordingSkillsPort();
  final lifecycle = ApplicationLifecycleFixture();
  final exitCodes = <int>[];
  final hostFinished = Completer<void>();
  late final StartupRepository startup;
  late final SkillsRepository skills;
  late final AppGraph graph;
  late final ProviderContainer container;
  bool _closed = false;

  void installHost() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(hostChannel, (call) async {
          if (call.method == 'beginExit') return 30000;
          if (call.method == 'finishExit') {
            exitCodes.add((call.arguments as Map)['exitCode'] as int);
            if (!hostFinished.isCompleted) hostFinished.complete();
          }
          return null;
        });
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    releaseNativeReads();
    await graph.exitCoordinator.requestHostExit(ExitIntent.exit);
    container.dispose();
    await domains.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(hostChannel, null);
  }

  /// Fixture-only settlement of externally held Start reads. Cancellation is
  /// not a successful route and cannot create a business acknowledgement.
  void releaseNativeReads() {
    const failure = StudioFailure(
      code: StudioFailureCode.cancelled,
      message: 'The application test native boundary is closing.',
      retryable: false,
      correlationId: 'application-test-cleanup',
    );
    for (final opening in domains.configurationPort.opens) {
      final pin = opening.native ?? opening.accept();
      for (final call in pin.calls) {
        if (!call.reply.isCompleted) call.reply.completeError(failure);
      }
    }
  }
}

/// Startup native stage ordering, not a bootstrap implementation. The real
/// StartupRepository consumes/ACKs progress and owns the typed Ready/error.
final class ApplicationStartupPort implements StartupPort {
  Object? initializeFailure;
  Completer<void>? initializeGate;
  final initializeEntered = Completer<void>();
  int initializeCalls = 0;
  final feeds = <int, ScriptedFeed<StartupProgressFrame>>{};
  @override
  Future<void> initializeLibrary() async {
    initializeCalls++;
    if (!initializeEntered.isCompleted) initializeEntered.complete();
    await initializeGate?.future;
    final failure = initializeFailure;
    initializeFailure = null;
    if (failure != null) throw failure;
  }

  @override
  Future<int> prepareStartupAttempt() async => initializeCalls;
  @override
  Future<FeedConnection<StartupProgressFrame>> openStartupProgress(
    int attemptId,
  ) async => feeds[attemptId] = ScriptedFeed<StartupProgressFrame>(
    feedId: 'application-startup-$attemptId',
    sequenceOf: (frame) =>
        frame is DataStartupProgressFrame ? frame.deliverySequence : null,
    isTerminal: (frame) => frame is! DataStartupProgressFrame,
  );
  @override
  Future<RuntimeReady> startStudioRuntime(int attemptId) async {
    final feed = feeds[attemptId]!;
    await feed.listened.future;
    feed.emit(
      const StartupProgressFrame.data(
        deliverySequence: 1,
        stage: StartupStage.ready,
      ),
    );
    await feed.acknowledged(1);
    feed.emit(
      const StartupProgressFrame.closed(reason: StartupCloseReason.completed),
    );
    feed.requestClose();
    return const RuntimeReady(
      revision: 7,
      readyAt: 70,
      details: RuntimeStartupReadRef(entry: 11, revision: 7),
    );
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unscripted startup read: ${invocation.memberName}',
  );
}

final class ApplicationLifecycleFixture implements ApplicationLifecyclePort {
  final externalReports = <List<StudioShutdownIssue>>[];
  @override
  Future<void> beginRuntimeExit({required int remainingMs}) async {}
  @override
  Future<StudioExitReport> shutdownRuntime({
    required int remainingMs,
    required List<StudioShutdownIssue> externalIssues,
    required ExitIntent intent,
  }) async {
    externalReports.add(List.of(externalIssues));
    return StudioExitReport(
      shutdown: StudioShutdownReport(
        outcome: externalIssues.isEmpty
            ? ShutdownOutcome.clean
            : ShutdownOutcome.degraded,
        issues: externalIssues,
        persistence: const PendingPersistence.drained(),
      ),
      updateHandoff: const UpdateHandoff.notRequested(),
    );
  }

  @override
  Future<void> finishShutdownDiagnostics() async {}
}

class _UnusedPort {
  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unscripted native capability: ${invocation.memberName}',
  );
}

final class _UnusedUsagePort extends _UnusedPort implements AccountUsagePort {}

final class _UnusedStatisticsPort extends _UnusedPort
    implements StatisticsPort {}

final class _UnusedRemotePort extends _UnusedPort implements RemotePort {}

final class _UnusedMcpPort extends _UnusedPort implements McpPort {}

final class _UnusedLspPort extends _UnusedPort implements LspPort {}

final class _UnusedPersistencePort extends _UnusedPort
    implements PersistencePort {}

final class _UnusedUpdatesPort extends _UnusedPort implements UpdatesPort {}

final class _UnusedBotsPort extends _UnusedPort implements BotsPort {}

final class RecordingSkillsPort extends _UnusedPort implements SkillsPort {
  final openedProjects = <String>[];
  @override
  Future<FeedConnection<SkillsFrame>> openSkills(String projectId) {
    openedProjects.add(projectId);
    return super.noSuchMethod(Invocation.method(#openSkills, [projectId]));
  }
}
