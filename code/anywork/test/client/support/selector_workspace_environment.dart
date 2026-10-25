import 'package:anywork/src/app/app_bindings.dart';
import 'package:anywork/src/app/bootstrap/application_bootstrap.dart';
import 'package:anywork/src/app/lifecycle/application_exit_coordinator.dart';
import 'package:anywork/src/app/lifecycle/exit_participant.dart';
import 'package:anywork/src/app/lifecycle/native_exit_host.dart';
import 'package:anywork/src/features/conversation/presentation_api.dart';
import 'package:anywork_client/account_usage_ports.dart';
import 'package:anywork_client/persistence_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/updates_ports.dart';
import 'package:anywork_client/workspace_ports.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../anywork_client/test/support/profile_native_pin.dart';
import '../../../../anywork_client/test/support/startup_port_fixture.dart';
import 'selector_environment.dart';

/// WorkspaceScreen's real auxiliary owners. Unrelated native services are
/// explicitly unavailable, not successful empty mirrors or mocked ViewModels.
/// All shutdown runs through the existing application exit coordinator.
final class SelectorWorkspaceEnvironment {
  SelectorWorkspaceEnvironment() {
    startup = createStartupRepository(port: startupPort, budget: core.budget, operations: core.operations);
    bootstrap = ApplicationBootstrap(startup: startup, attachDomains: (_) async => core.binding.start());
    updates = createUpdatesRepository(port: const _UpdatesPort(), budget: core.budget,
      operations: core.operations, controls: const UpdateControls(enabled: false)).repository;
    persistence = createPersistenceRepository(port: const _PersistencePort(), budget: core.budget, operations: core.operations);
    statistics = createStatisticsRepository(port: const _StatisticsPort(), budget: core.budget);
    timeline = TimelineCoordinator(conversations: core.conversations);
    exit = ApplicationExitCoordinator(lifecycle: const _LifecyclePort(), host: NativeExitHost(), editProducers: core.edits,
      sealOperations: core.operations.seal, detachPresentation: () { timeline.close(); }, readyUpdateVersion: () => null,
      participants: [
        ApplicationCloseParticipant(name: 'selector-workspace', seal: () {
          bootstrap.seal(); core.binding.seal(); core.workspace.seal(); core.conversations.seal(); core.drafts.seal();
          updates.seal(); persistence.seal(); statistics.seal(); startup.seal();
        }, close: ({deadline}) => _closeDomains(), retryCleanup: ({deadline}) => _closeDomains()),
      ]);
    container = ProviderContainer(retry: (_, _) => null, overrides: [
      ...core.domainOverrides,
      startupRepositoryProvider.overrideWithValue(startup), applicationBootstrapProvider.overrideWithValue(bootstrap),
      updatesRepositoryProvider.overrideWithValue(updates), persistenceRepositoryProvider.overrideWithValue(persistence),
      statisticsRepositoryProvider.overrideWithValue(statistics), applicationExitCoordinatorProvider.overrideWithValue(exit),
      timelineActionsProvider.overrideWithValue(timeline), timelineCoordinatorProvider.overrideWithValue(timeline),
    ]);
  }
  final core = SelectorEnvironment();
  final startupPort = _StartupPort();
  late final StartupRepository startup;
  late final ApplicationBootstrap bootstrap;
  late final UpdatesRepository updates;
  late final PersistenceRepository persistence;
  late final StatisticsRepository statistics;
  late final TimelineCoordinator timeline;
  late final ApplicationExitCoordinator exit;
  late final ProviderContainer container;
  bool _closed = false;
  Future<void> establish() async {
    await core.establish();
    final work = bootstrap.start();
    await startupPort.base.completeReady();
    await work;
  }
  Future<CloseReport> _closeDomains() async {
    final extra = await Future.wait([bootstrap.close(), startup.close(), updates.close(), persistence.close(), statistics.close(), timeline.close()]);
    await core.close();
    return CloseReport(unresolved: [for (final report in extra) ...report.unresolved]);
  }
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    container.dispose();
    await _closeDomains();
  }
}

const _unavailable = StudioFailure(code: StudioFailureCode.unavailable,
  message: 'Unrelated native service is unavailable in this directory scenario',
  retryable: false, correlationId: 'selector-unrelated-native');
final class _UpdatesPort implements UpdatesPort {
  const _UpdatesPort();
  @override
  Never noSuchMethod(Invocation invocation) => throw _unavailable;
}
final class _PersistencePort implements PersistencePort {
  const _PersistencePort();
  @override
  Never noSuchMethod(Invocation invocation) => throw _unavailable;
}
final class _StatisticsPort implements StatisticsPort {
  const _StatisticsPort();
  @override
  Never noSuchMethod(Invocation invocation) => throw _unavailable;
}
final class _StartupPort implements StartupPort {
  final base = ScriptedStartupPort();
  @override
  Future<void> initializeLibrary() => base.initializeLibrary();
  @override
  Future<int> prepareStartupAttempt() => base.prepareStartupAttempt();
  @override
  Future<FeedConnection<StartupProgressFrame>> openStartupProgress(int attemptId) => base.openStartupProgress(attemptId);
  @override
  Future<RuntimeReady> startStudioRuntime(int attemptId) => base.startStudioRuntime(attemptId);
  @override
  Future<RuntimeStartupReadConnection> openStartupRead(RuntimeStartupReadRef reference) async => _StartupRead();
}
final class _StartupRead extends ProfileNativePin implements RuntimeStartupReadConnection {
  _StartupRead() : super('selector-startup-read');
  @override
  Future<RuntimeStartupReadHeader> header() async => const RuntimeStartupReadHeader(
    scope: RuntimeStartupScopeIdentity(scopeId: 'selector-startup-read', ownerEpoch: 'selector-native', attemptId: 41, revision: 7),
    reference: RuntimeStartupReadRef(entry: 11, revision: 7), revision: 7, state: RuntimeStateRead.ready(at: 70), startupRecovery: null, activeTurnCount: 0);
}
final class _LifecyclePort implements ApplicationLifecyclePort {
  const _LifecyclePort();
  @override
  Future<void> beginRuntimeExit({required int remainingMs}) async {}
  @override
  Future<StudioExitReport> shutdownRuntime({required int remainingMs, required List<StudioShutdownIssue> externalIssues,
    required ExitIntent intent}) async => StudioExitReport(shutdown: StudioShutdownReport(
      outcome: externalIssues.isEmpty ? ShutdownOutcome.clean : ShutdownOutcome.degraded,
      issues: externalIssues, persistence: const PendingPersistence.drained()), updateHandoff: const UpdateHandoff.notRequested());
  @override
  Future<void> finishShutdownDiagnostics() async {}
}
