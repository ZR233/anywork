import 'support/test_statistics_feed.dart';

import 'dart:async';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/shell/shell_view.dart';
import 'package:anywork/src/features/shell/studio_shell.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/presentation/providers/mode_catalog_store.dart';
import 'package:anywork/src/presentation/providers/project_store.dart';
import 'package:anywork/src/presentation/providers/recovery_store.dart';
import 'package:anywork/src/presentation/providers/selection_store.dart';
import 'package:anywork/src/presentation/providers/thread_directory_store.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pump_client_future.dart';
import 'support/recording_demo_transport.dart';

void main() {
  test('production sidebarViewProvider matches scope and prioritizes actual blockers', () async {
    final transport = RecordingDemoTransport();
    final bootstrap = await transport.readBootstrap();
    final root = bootstrap.threadDirectory.threads
        .where((thread) => thread.isRoot)
        .first;

    readProductionView(List<StudioRecoveryIssue> issues) {
      const revision = 100;
      final container = ProviderContainer(
        overrides: [
          projectStoreProvider.overrideWithValue(
            ProjectStoreState(
              projects: bootstrap.projectDirectory,
              agents: bootstrap.agentDirectory,
            ),
          ),
          threadDirectoryStoreProvider.overrideWithValue(
            ThreadDirectoryStoreState(
              window: bootstrap.threadDirectory,
              loaded: true,
            ),
          ),
          recoveryStoreProvider.overrideWithValue(
            CanonicalClockState<RecoveryStateSnapshot>(
              value: RecoveryStateSnapshot(revision: revision, values: issues),
              revision: revision,
              loaded: true,
            ),
          ),
          modeCatalogStoreProvider.overrideWithValue(
            CanonicalClockState<ThreadModeCatalogView>(
              value: bootstrap.threadModeCatalog,
              revision: bootstrap.threadModeCatalog.revision,
              loaded: true,
            ),
          ),
          selectionStoreProvider.overrideWithValue(
            SelectionStoreState(
              selectedProjectId: root.projectId,
              selectedThreadId: root.id,
              needsOpen: true,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container.read(sidebarViewProvider);
    }

    final childOnly = readProductionView([
      StudioRecoveryIssue(
        id: 'preserved-child-execution',
        scope: RecoveryIssueScope.thread,
        category: RecoveryIssueCategory.repository,
        impact: RecoveryIssueImpact.executionBlocked,
        availableActions: const [RecoveryIssueAction.retry],
        projectId: null,
        threadId: 'child-of-root',
        detail: 'Preserved child remains reviewable',
      ),
    ]);
    expect(
      childOnly.threadRecoveryIssues.containsKey(root.id),
      isFalse,
      reason: 'A child issue is not inherited by the root sidebar row',
    );

    final threadOnlyAdvisory = readProductionView([
      StudioRecoveryIssue(
        id: 'thread-only-advisory',
        scope: RecoveryIssueScope.thread,
        category: RecoveryIssueCategory.toolCatalog,
        impact: RecoveryIssueImpact.advisory,
        availableActions: const [RecoveryIssueAction.retry],
        projectId: null,
        threadId: root.id,
        detail: 'Thread observation is being retried',
      ),
    ]);
    expect(
      threadOnlyAdvisory.threadRecoveryIssues[root.id]?.id,
      'thread-only-advisory',
    );
    expect(
      threadOnlyAdvisory.threadRecoveryIssues[root.id]?.canRetry,
      isTrue,
      reason: 'A legal thread-only advisory remains visible and retryable',
    );

    final applicationAccess = StudioRecoveryIssue(
      id: 'application-access-block',
      scope: RecoveryIssueScope.application,
      category: RecoveryIssueCategory.storage,
      impact: RecoveryIssueImpact.accessBlocked,
      availableActions: const [RecoveryIssueAction.retry],
      detail: 'Application access is blocked',
    );
    final projectAdvisory = StudioRecoveryIssue(
      id: 'project-advisory',
      scope: RecoveryIssueScope.project,
      category: RecoveryIssueCategory.repository,
      impact: RecoveryIssueImpact.advisory,
      availableActions: const [],
      projectId: root.projectId,
      detail: 'Project reminder',
    );
    final rootAdvisory = StudioRecoveryIssue(
      id: 'root-advisory',
      scope: RecoveryIssueScope.thread,
      category: RecoveryIssueCategory.repository,
      impact: RecoveryIssueImpact.advisory,
      availableActions: const [],
      projectId: root.projectId,
      threadId: root.id,
      detail: 'Root reminder',
    );
    final appWide = readProductionView([
      applicationAccess,
      projectAdvisory,
      rootAdvisory,
    ]);
    expect(
      appWide.projectRecoveryIssues[root.projectId]?.id,
      applicationAccess.id,
    );
    expect(appWide.threadRecoveryIssues[root.id]?.id, applicationAccess.id);

    final applicationAdvisory = StudioRecoveryIssue(
      id: 'application-advisory',
      scope: RecoveryIssueScope.application,
      category: RecoveryIssueCategory.repository,
      impact: RecoveryIssueImpact.advisory,
      availableActions: const [],
      detail: 'Application reminder',
    );
    final projectExecution = StudioRecoveryIssue(
      id: 'project-execution-block',
      scope: RecoveryIssueScope.project,
      category: RecoveryIssueCategory.repository,
      impact: RecoveryIssueImpact.executionBlocked,
      availableActions: const [],
      projectId: root.projectId,
      detail: 'Project execution is blocked',
    );
    final projectAdvisoryLater = StudioRecoveryIssue(
      id: 'project-advisory-later',
      scope: RecoveryIssueScope.project,
      category: RecoveryIssueCategory.repository,
      impact: RecoveryIssueImpact.advisory,
      availableActions: const [],
      projectId: root.projectId,
      detail: 'Later project advisory',
    );
    final prioritized = readProductionView([
      applicationAdvisory,
      projectExecution,
      projectAdvisoryLater,
      rootAdvisory,
    ]);
    expect(
      prioritized.projectRecoveryIssues[root.projectId]?.id,
      projectExecution.id,
    );
    expect(
      prioritized.threadRecoveryIssues[root.id]?.id,
      rootAdvisory.id,
      reason: 'An existing Thread does not inherit its storage Project issue',
    );

    final rootExecution = StudioRecoveryIssue(
      id: 'root-execution-block',
      scope: RecoveryIssueScope.thread,
      category: RecoveryIssueCategory.repository,
      impact: RecoveryIssueImpact.executionBlocked,
      availableActions: const [RecoveryIssueAction.retry],
      projectId: null,
      threadId: root.id,
      detail: 'The actual Thread resource is unavailable',
    );
    final exact = readProductionView([
      projectExecution,
      applicationAdvisory,
      rootAdvisory,
      rootExecution,
    ]);
    expect(exact.threadRecoveryIssues[root.id]?.id, rootExecution.id);
    expect(
      exact.projectRecoveryIssues[root.projectId]?.id,
      projectExecution.id,
    );

    final foreignProject = readProductionView([
      StudioRecoveryIssue(
        id: 'same-thread-wrong-project',
        scope: RecoveryIssueScope.thread,
        category: RecoveryIssueCategory.storage,
        impact: RecoveryIssueImpact.accessBlocked,
        availableActions: const [],
        projectId: '${root.projectId}-different',
        threadId: root.id,
        detail: 'A mismatched non-null project cannot grant a match',
      ),
    ]);
    expect(foreignProject.threadRecoveryIssues, isEmpty);
  });

  test('Project recovery gates Project operations while exact Thread recovery gates only its owner', () async {
    final transport = _ScopedRecoveryTransport();
    final graph = AppGraph(
      statisticsFeed: const TestStatisticsFeedPort(),
      transport: transport,
      clientId: 'exact-recovery-owner',
    );
    addTearDown(
      () =>
          graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
    );
    final client = graph.client;
    await client.bootstrap();
    final healthy = client.threadDirectory.state.window.threads.firstWhere(
      (thread) => thread.isRoot,
    );
    final affected = client.threadDirectory.state.window.threads.firstWhere(
      (thread) =>
          thread.isRoot &&
          thread.projectId == healthy.projectId &&
          thread.id != healthy.id,
    );
    var revision = client.recovery.state.revision;
    final projectExecution = StudioRecoveryIssue(
      id: 'stored-project-unavailable',
      scope: RecoveryIssueScope.project,
      category: RecoveryIssueCategory.repository,
      impact: RecoveryIssueImpact.executionBlocked,
      availableActions: const [RecoveryIssueAction.retry],
      projectId: healthy.projectId,
      detail: 'The project preparation resource is unavailable',
    );
    final threadExecution = StudioRecoveryIssue(
      id: 'actual-thread-resource-unavailable',
      scope: RecoveryIssueScope.thread,
      category: RecoveryIssueCategory.repository,
      impact: RecoveryIssueImpact.executionBlocked,
      availableActions: const [],
      projectId: null,
      threadId: affected.id,
      detail: 'The existing Thread still depends on the unavailable resource',
    );
    client.recovery.apply(
      RecoveryStateSnapshot(
        revision: ++revision,
        values: [projectExecution, threadExecution],
      ),
    );

    await client.directoryCommands.selectThread(healthy.id);
    await client.directoryCommands.openSelectedThread();
    expect(client.selection.state.selectedThreadId, healthy.id);
    await client.threadCommands.readChildInteractions(healthy.id);
    await client.directoryCommands.resumeThreadHistory(healthy.id, 7);
    expect(transport.reads, [healthy.id]);
    expect(transport.resumes, [healthy.id]);
    expect(
      transport.activations,
      isEmpty,
      reason: 'Existing Thread navigation must not perform intermediate Project preparation',
    );
    await expectLater(
      client.directoryCommands.resumeThreadHistory(affected.id, 7),
      throwsA(
        isA<StudioFailure>()
            .having(
              (failure) => recoveryIssueFromFailure(failure)?.id,
              'issue',
              threadExecution.id,
            )
            .having(
              (failure) => recoveryIssueFromFailure(failure)?.projectId,
              'optional project',
              isNull,
            )
            .having(
              (failure) => recoveryIssueFromFailure(failure)?.detail,
              'detail',
              threadExecution.detail,
            ),
      ),
    );
    expect(transport.resumes, [healthy.id]);

    final projectAccess = StudioRecoveryIssue(
      id: 'project-access-unavailable',
      scope: RecoveryIssueScope.project,
      category: RecoveryIssueCategory.storage,
      impact: RecoveryIssueImpact.accessBlocked,
      availableActions: const [RecoveryIssueAction.retry],
      projectId: healthy.projectId,
      detail: 'Only the Project access entry is unavailable',
    );
    final threadAccess = StudioRecoveryIssue(
      id: 'thread-access-unavailable',
      scope: RecoveryIssueScope.thread,
      category: RecoveryIssueCategory.storage,
      impact: RecoveryIssueImpact.accessBlocked,
      availableActions: const [],
      projectId: healthy.projectId,
      threadId: affected.id,
      detail: 'The affected Thread history is unreadable',
    );
    client.recovery.apply(
      RecoveryStateSnapshot(
        revision: ++revision,
        values: [projectAccess, threadAccess],
      ),
    );
    await client.directoryCommands.selectThread(healthy.id);
    await client.threadCommands.readChildInteractions(healthy.id);
    expect(transport.reads, [healthy.id, healthy.id]);
    await expectLater(
      client.directoryCommands.selectProject(healthy.projectId),
      throwsA(
        isA<StudioFailure>().having(
          (failure) => recoveryIssueFromFailure(failure)?.id,
          'Project owner',
          projectAccess.id,
        ),
      ),
    );
    await expectLater(
      client.directoryCommands.selectThread(affected.id),
      throwsA(
        isA<StudioFailure>().having(
          (failure) => recoveryIssueFromFailure(failure)?.id,
          'Thread owner',
          threadAccess.id,
        ),
      ),
    );
    expect(client.selection.state.selectedThreadId, healthy.id);
  });

  testWidgets(
    'closing the selected thread does not reopen content from shell',
    (tester) async {
      final transport = RecordingDemoTransport();
      final graph = AppGraph(
        statisticsFeed: const TestStatisticsFeedPort(),
        transport: transport,
        clientId: 'closing-shell',
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await pumpClientFuture(
          tester,
          graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
          'closing shell teardown',
        );
      });
      await pumpClientFuture(
        tester,
        graph.client.bootstrap(),
        'shell bootstrap',
      );
      await pumpClientFuture(
        tester,
        (graph..setConversationPageVisible(true)).client.directoryCommands
            .selectThread('thread-main'),
        'select closing thread',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appGraphProvider.overrideWithValue(graph)],
          child: MaterialApp(
            theme: pureStudioTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const StudioShell(),
          ),
        ),
      );
      await pumpClientUntil(
        tester,
        () =>
            graph.client.conversations
                .existingSession('thread-main')!
                .content
                .state
                .value
                .snapshot !=
            null,
        'Client delivers the initial content baseline',
      );
      await tester.pumpAndSettle();
      final openedWindows = transport.feeds.length;
      await pumpClientFuture(
        tester,
        graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
        'close while shell remains mounted',
      );
      for (var frame = 0; frame < 4; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull);
      }
      expect(transport.feeds, hasLength(openedWindows));
      expect(
        transport.feeds.every((entry) => entry.joined.isCompleted),
        isTrue,
      );
    },
  );

  testWidgets(
    'shell sidebar keeps running status beside advisory recovery diagnostic',
    (tester) async {
      final transport = RecordingDemoTransport();
      final graph = AppGraph(
        statisticsFeed: const TestStatisticsFeedPort(),
        transport: transport,
        clientId: 'sidebar-recovery-status',
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await pumpClientFuture(
          tester,
          graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
          'sidebar recovery status teardown',
        );
      });
      await pumpClientFuture(
        tester,
        graph.client.bootstrap(),
        'sidebar recovery status bootstrap',
      );

      final root = graph.client.threadDirectory.state.window.threads
          .where((thread) => thread.isRoot)
          .first;
      final recoveryRevision = graph.client.recovery.state.revision;
      graph.client.recovery.apply(
        RecoveryStateSnapshot(
          revision: recoveryRevision + 1,
          values: [
            StudioRecoveryIssue(
              id: 'sidebar-running-advisory',
              scope: RecoveryIssueScope.thread,
              category: RecoveryIssueCategory.repository,
              impact: RecoveryIssueImpact.advisory,
              availableActions: const [],
              projectId: root.projectId,
              threadId: root.id,
              detail: 'Repository observation is retrying',
            ),
          ],
        ),
      );
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appGraphProvider.overrideWithValue(graph)],
          child: MaterialApp(
            theme: pureStudioTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const StudioShell(),
          ),
        ),
      );
      final rootRow = find.byKey(StudioDriverKeys.threadRow(root.id));
      await pumpClientUntil(
        tester,
        () => rootRow.evaluate().isNotEmpty,
        'production sidebar renders root row',
      );
      // Let the shell's production topic observations pass their ten-second
      // stability windows before introducing the continuously animated badge.
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      final directoryRevision =
          graph.client.threadDirectory.state.window.revision;
      graph.client.threadDirectory.applyDelta(
        revision: directoryRevision + 1,
        upserted: [root.copyWith(status: ThreadStatusView.running)],
        removed: const [],
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.descendant(
          of: rootRow,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
        reason: 'canonical running state keeps its activity badge',
      );
      expect(
        find.descendant(of: rootRow, matching: find.byIcon(Icons.info_outline)),
        findsOneWidget,
        reason: 'advisory Recovery diagnostic is shown beside the status',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'directory failure retains the shell and explicitly retries its topic',
    (tester) async {
      final transport = _DirectoryFailureTransport();
      final graph = AppGraph(
        statisticsFeed: const TestStatisticsFeedPort(),
        transport: transport,
        clientId: 'directory-recovery',
      );
      await graph.client.bootstrap();
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await pumpClientFuture(
          tester,
          graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
          'directory recovery close',
        );
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appGraphProvider.overrideWithValue(graph)],
          child: MaterialApp(
            theme: pureStudioTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const StudioShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final input = find.byKey(StudioDriverKeys.composerInput);
      await tester.enterText(input, 'draft survives directory outage');
      final project = graph.client.selection.state.selectedProjectId;
      transport.fail();
      // Release the production retry timers using Flutter's virtual clock.
      for (var attempt = 0; attempt < 8; attempt++) {
        if (graph.client.project.state.projectSync.phase ==
            DomainSyncPhase.failed) {
          break;
        }
        await tester.pump(const Duration(seconds: 5));
        await tester.runAsync(() async {});
      }
      expect(
        graph.client.project.state.projectSync.phase,
        DomainSyncPhase.failed,
      );
      expect(find.byKey(StudioDriverKeys.startPage), findsOneWidget);
      expect(find.byKey(const ValueKey('studio-startup')), findsNothing);
      expect(
        tester.widget<TextField>(input).controller!.text,
        'draft survives directory outage',
      );
      expect(graph.client.selection.state.selectedProjectId, project);
      final retry = find.byKey(const ValueKey('project-directory-retry'));
      expect(retry, findsOneWidget);
      transport.unavailable = false;
      await tester.tap(retry);
      await pumpClientUntil(
        tester,
        () => graph.client.project.state.projectSync.isReady,
        'project topic baseline after explicit retry',
      );
      await tester.pumpAndSettle();
      expect(retry, findsNothing);
      expect(
        tester.widget<TextField>(input).controller!.text,
        'draft survives directory outage',
      );
      expect(transport.bootstrapCalls, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpClientFuture(
        tester,
        graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
        'explicit directory recovery close',
      );
    },
  );
}

/// Records calls crossing Client admission. Demo replies are only the external
/// environment; these checks do not claim native execution or resource repair.
final class _ScopedRecoveryTransport extends RecordingDemoTransport {
  final reads = <String>[];
  final resumes = <String>[];
  final activations = <String>[];

  @override
  Future<List<ChildInteractionSummary>> readChildInteractions(String threadId) {
    reads.add(threadId);
    return super.readChildInteractions(threadId);
  }

  @override
  Future<PersistenceQueueSnapshot> resumeThreadHistory(
    String threadId,
    int faultGeneration,
  ) {
    resumes.add(threadId);
    return super.resumeThreadHistory(threadId, faultGeneration);
  }

  @override
  Future<void> activateProject(String projectId) {
    activations.add(projectId);
    return super.activateProject(projectId);
  }
}

final class _DirectoryFailureTransport extends RecordingDemoTransport {
  bool unavailable = false;
  MultiStreamController<ProductTopicFrame>? _directory;

  void fail() {
    unavailable = true;
    _directory!.addErrorSync(StateError('directory offline'));
  }

  @override
  Stream<ProductTopicFrame> subscribeProductTopic(ProductTopic topic) {
    if (topic is! ProjectDirectoryTopic) {
      return super.subscribeProductTopic(topic);
    }
    if (unavailable) return Stream.error(StateError('directory offline'));
    return Stream<ProductTopicFrame>.multi((controller) {
      _directory = controller;
      final source = super
          .subscribeProductTopic(topic)
          .listen(
            controller.addSync,
            onError: controller.addErrorSync,
            onDone: controller.closeSync,
          );
      controller.onCancel = source.cancel;
    });
  }
}
