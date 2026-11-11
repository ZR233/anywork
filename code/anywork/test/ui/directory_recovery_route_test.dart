import '../support/chat_fixtures.dart';
import '../support/test_statistics_feed.dart';

import 'dart:async';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/shell/shell_view.dart';
import 'package:anywork/src/features/shell/studio_shell.dart';
import 'package:anywork/src/features/shell/sidebar/sidebar_views.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/presentation/providers/recovery_store.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pump_client_future.dart';
import '../support/recording_demo_transport.dart';
import '../../../anywork_client/test/support/directory_feed.dart';

void main() {
  test('production per-project recovery projection matches scope and prioritizes actual blockers', () async {
    final transport = RecordingDemoTransport();
    final bootstrap = await transport.readBootstrap();
    final root = bootstrap.threadDirectory.rows
        .where((row) => row.isRootRow)
        .first;

    readProductionView(List<StudioRecoveryIssue> issues) {
      const revision = 100;
      final container = ProviderContainer(
        overrides: [
          recoveryStoreProvider.overrideWithValue(
            CanonicalClockState<RecoveryStateSnapshot>(
              value: RecoveryStateSnapshot(revision: revision, values: issues),
              revision: revision,
              loaded: true,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      return <String, StudioRecoveryIssue>{
        for (final project in bootstrap.projectDirectory.values)
          project.id: ?container.read(sidebarRecoveryIssueProvider(project.id)),
      };
    }

    final childOnly = readProductionView([
      StudioRecoveryIssue(
        id: 'preserved-child-execution',
        scope: RecoveryIssueScope.thread,
        category: RecoveryIssueCategory.repository,
        impact: RecoveryIssueImpact.executionBlocked,
        availableActions: const [RecoveryIssueAction.retry],
        workspaceId: null,
        threadId: 'child-of-root',
        detail: 'Preserved child remains reviewable',
      ),
    ]);
    expect(childOnly, isEmpty);

    final threadOnlyAdvisory = readProductionView([
      StudioRecoveryIssue(
        id: 'thread-only-advisory',
        scope: RecoveryIssueScope.thread,
        category: RecoveryIssueCategory.toolCatalog,
        impact: RecoveryIssueImpact.advisory,
        availableActions: const [RecoveryIssueAction.retry],
        workspaceId: null,
        threadId: root.threadId,
        detail: 'Thread observation is being retried',
      ),
    ]);
    expect(threadOnlyAdvisory, isEmpty);

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
      workspaceId: root.workspaceId,
      detail: 'Project reminder',
    );
    final rootAdvisory = StudioRecoveryIssue(
      id: 'root-advisory',
      scope: RecoveryIssueScope.thread,
      category: RecoveryIssueCategory.repository,
      impact: RecoveryIssueImpact.advisory,
      availableActions: const [],
      workspaceId: root.workspaceId,
      threadId: root.threadId,
      detail: 'Root reminder',
    );
    final appWide = readProductionView([
      applicationAccess,
      projectAdvisory,
      rootAdvisory,
    ]);
    expect(appWide[root.workspaceId]?.id, applicationAccess.id);

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
      workspaceId: root.workspaceId,
      detail: 'Project execution is blocked',
    );
    final projectAdvisoryLater = StudioRecoveryIssue(
      id: 'project-advisory-later',
      scope: RecoveryIssueScope.project,
      category: RecoveryIssueCategory.repository,
      impact: RecoveryIssueImpact.advisory,
      availableActions: const [],
      workspaceId: root.workspaceId,
      detail: 'Later project advisory',
    );
    final prioritized = readProductionView([
      applicationAdvisory,
      projectExecution,
      projectAdvisoryLater,
      rootAdvisory,
    ]);
    expect(prioritized[root.workspaceId]?.id, projectExecution.id);
    final rootExecution = StudioRecoveryIssue(
      id: 'root-execution-block',
      scope: RecoveryIssueScope.thread,
      category: RecoveryIssueCategory.repository,
      impact: RecoveryIssueImpact.executionBlocked,
      availableActions: const [RecoveryIssueAction.retry],
      workspaceId: null,
      threadId: root.threadId,
      detail: 'The actual Thread resource is unavailable',
    );
    final exact = readProductionView([
      projectExecution,
      applicationAdvisory,
      rootAdvisory,
      rootExecution,
    ]);
    expect(exact[root.workspaceId]?.id, projectExecution.id);

    final foreignProject = readProductionView([
      StudioRecoveryIssue(
        id: 'same-thread-wrong-project',
        scope: RecoveryIssueScope.thread,
        category: RecoveryIssueCategory.storage,
        impact: RecoveryIssueImpact.accessBlocked,
        availableActions: const [],
        workspaceId: '${root.workspaceId}-different',
        threadId: root.threadId,
        detail: 'A mismatched non-null project cannot grant a match',
      ),
    ]);
    expect(foreignProject, isEmpty);
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
    final directoryDemand = client.threadDirectory.observeThreads(
      const DirectoryQuery(),
      DirectoryWindow(),
    );
    addTearDown(() async {
      await directoryDemand.release();
    });
    final directoryFrame = await directoryDemand.state
        .waitFor((state) => state.frame != null)
        .timeout(const Duration(seconds: 5));
    final rows = await Future.wait([
      for (final id in directoryFrame.frame!.threadIds) _readThread(client, id),
    ]);
    final healthy = rows.firstWhere((row) => row.isRootRow);
    final affected = rows.firstWhere(
      (row) =>
          row.isRootRow &&
          row.workspaceId == healthy.workspaceId &&
          row.threadId != healthy.threadId,
    );
    var revision = client.recovery.state.revision;
    final projectExecution = StudioRecoveryIssue(
      id: 'stored-project-unavailable',
      scope: RecoveryIssueScope.project,
      category: RecoveryIssueCategory.repository,
      impact: RecoveryIssueImpact.executionBlocked,
      availableActions: const [RecoveryIssueAction.retry],
      workspaceId: healthy.workspaceId,
      detail: 'The project preparation resource is unavailable',
    );
    final threadExecution = StudioRecoveryIssue(
      id: 'actual-thread-resource-unavailable',
      scope: RecoveryIssueScope.thread,
      category: RecoveryIssueCategory.repository,
      impact: RecoveryIssueImpact.executionBlocked,
      availableActions: const [],
      workspaceId: null,
      threadId: affected.threadId,
      detail: 'The existing Thread still depends on the unavailable resource',
    );
    client.recovery.apply(
      RecoveryStateSnapshot(
        revision: ++revision,
        values: [projectExecution, threadExecution],
      ),
    );

    await client.directoryCommands.selectThread(healthy.threadId);
    await client.directoryCommands.openSelectedThread();
    expect(client.selection.state.selectedThreadId, healthy.threadId);
    await client.threadCommands.readChildInteractions(healthy.threadId);
    await client.directoryCommands.resumeThreadHistory(healthy.threadId, 7);
    expect(transport.reads, [healthy.threadId]);
    expect(transport.resumes, [healthy.threadId]);
    expect(
      transport.activations,
      isEmpty,
      reason: 'Existing Thread navigation must not perform intermediate Project preparation',
    );
    await expectLater(
      client.directoryCommands.resumeThreadHistory(affected.threadId, 7),
      throwsA(
        isA<StudioFailure>()
            .having(
              (failure) => recoveryIssueFromFailure(failure)?.id,
              'issue',
              threadExecution.id,
            )
            .having(
              (failure) => recoveryIssueFromFailure(failure)?.workspaceId,
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
    expect(transport.resumes, [healthy.threadId]);

    final projectAccess = StudioRecoveryIssue(
      id: 'project-access-unavailable',
      scope: RecoveryIssueScope.project,
      category: RecoveryIssueCategory.storage,
      impact: RecoveryIssueImpact.accessBlocked,
      availableActions: const [RecoveryIssueAction.retry],
      workspaceId: healthy.workspaceId,
      detail: 'Only the Project access entry is unavailable',
    );
    final threadAccess = StudioRecoveryIssue(
      id: 'thread-access-unavailable',
      scope: RecoveryIssueScope.thread,
      category: RecoveryIssueCategory.storage,
      impact: RecoveryIssueImpact.accessBlocked,
      availableActions: const [],
      workspaceId: healthy.workspaceId,
      threadId: affected.threadId,
      detail: 'The affected Thread history is unreadable',
    );
    client.recovery.apply(
      RecoveryStateSnapshot(
        revision: ++revision,
        values: [projectAccess, threadAccess],
      ),
    );
    await client.directoryCommands.selectThread(healthy.threadId);
    await client.threadCommands.readChildInteractions(healthy.threadId);
    expect(transport.reads, [healthy.threadId, healthy.threadId]);
    await expectLater(
      client.directoryCommands.selectProject(healthy.workspaceId),
      throwsA(
        isA<StudioFailure>().having(
          (failure) => recoveryIssueFromFailure(failure)?.id,
          'Project owner',
          projectAccess.id,
        ),
      ),
    );
    await expectLater(
      client.directoryCommands.selectThread(affected.threadId),
      throwsA(
        isA<StudioFailure>().having(
          (failure) => recoveryIssueFromFailure(failure)?.id,
          'Thread owner',
          threadAccess.id,
        ),
      ),
    );
    expect(client.selection.state.selectedThreadId, healthy.threadId);
  });

  testWidgets(
    'closing the selected thread does not reopen content from shell',
    (tester) async {
      final transport = _DirectoryFailureTransport();
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
        (graph
              ..timeline.updateReadDemand(chatDemand)
              ..setConversationPageVisible(true))
            .client
            .directoryCommands
            .selectThread('thread-main'),
        'select closing thread',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appGraphProvider.overrideWithValue(graph)],
          child: MaterialApp(
            theme: pureStudioTheme(),
            localizationsDelegates: [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
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
      final transport = _SidebarStatusTransport();
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
      final bootstrap = await transport.readBootstrap();
      await pumpClientFuture(
        tester,
        graph.client.bootstrap(),
        'sidebar recovery status bootstrap',
      );
      final root = bootstrap.threadDirectory.rows.firstWhere(
        (row) => row.isRootRow,
      );
      transport.seedThread(root);
      final recoveryRevision = graph.client.recovery.state.revision;
      graph.client.recovery.apply(
        RecoveryStateSnapshot(
          revision: recoveryRevision + 1,
          values: [
            StudioRecoveryIssue(
              id: 'sidebar-project-advisory',
              scope: RecoveryIssueScope.project,
              category: RecoveryIssueCategory.repository,
              impact: RecoveryIssueImpact.advisory,
              availableActions: const [],
              workspaceId: root.workspaceId,
              detail: 'Project catalog observation is delayed',
            ),
            StudioRecoveryIssue(
              id: 'sidebar-running-advisory',
              scope: RecoveryIssueScope.thread,
              category: RecoveryIssueCategory.repository,
              impact: RecoveryIssueImpact.advisory,
              availableActions: const [],
              workspaceId: root.workspaceId,
              threadId: root.threadId,
              detail: 'Root repository is retrying',
            ),
            StudioRecoveryIssue(
              id: 'sidebar-foreign-child-access',
              scope: RecoveryIssueScope.thread,
              category: RecoveryIssueCategory.storage,
              impact: RecoveryIssueImpact.accessBlocked,
              availableActions: const [],
              workspaceId: root.workspaceId,
              threadId: 'unlisted-child',
              detail: 'An unlisted child has blocked access',
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
            localizationsDelegates: [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const StudioShell(),
          ),
        ),
      );
      final rootRow = find.byKey(StudioDriverKeys.threadRow(root.threadId));
      final projectRow = find.byKey(
        StudioDriverKeys.projectRow(root.workspaceId),
      );
      await pumpClientUntil(
        tester,
        () => rootRow.evaluate().isNotEmpty,
        'production sidebar renders root row',
      );
      final metadataDemand = graph.client.threadDirectory.observeThread(
        root.threadId,
      );
      addTearDown(
        () => pumpClientFuture(
          tester,
          metadataDemand.release(),
          'release sidebar metadata borrow',
        ),
      );
      await pumpClientUntil(
        tester,
        () => metadataDemand.state.value.frame != null,
        'borrow production row metadata',
      );
      // Let the shell's production topic observations pass their ten-second
      // stability windows before introducing the continuously animated badge.
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      var sidebarBuilds = 0;
      final projectBuilds = <String, int>{};
      final previousRebuild = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        previousRebuild?.call(element, builtOnce);
        final widget = element.widget;
        if (widget is StudioSidebar) sidebarBuilds++;
        if (widget is SidebarProjectRow) {
          projectBuilds.update(
            widget.project.id,
            (value) => value + 1,
            ifAbsent: () => 1,
          );
        }
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previousRebuild);
      transport.emitThread(
        root.copyWith(
          backend: (root.backend as NativeAgentBackendView).copyWith(
            status: ThreadStatusView.running,
          ),
        ),
        root.threadId,
        revision: transport.directoryRevision + 1,
      );
      await pumpClientUntil(
        tester,
        () =>
            (metadataDemand.state.value.frame?.row?.backend
                    as NativeAgentBackendView?)
                ?.status ==
            ThreadStatusView.running,
        'running root frame is accepted',
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        sidebarBuilds,
        0,
        reason: 'selected metadata must not rebuild the root sidebar through the shell header',
      );
      expect(projectBuilds, isEmpty);

      final statusSlot = find.byKey(
        ValueKey('thread-status-slot-${root.threadId}'),
      );
      expect(
        find.descendant(
          of: statusSlot,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
        reason: 'canonical running state renders its activity badge in the leading status slot',
      );
      final projectIconRect = tester.getRect(
        find.descendant(
          of: projectRow,
          matching: find.byIcon(Icons.folder_outlined),
        ),
      );
      final statusSlotRect = tester.getRect(statusSlot);
      expect(
        statusSlotRect.left,
        closeTo(projectIconRect.left, 0.5),
        reason: 'session status slot aligns vertically with the project icon',
      );
      expect(
        statusSlotRect.center.dx,
        closeTo(projectIconRect.center.dx, 0.5),
        reason: 'session status icon center aligns vertically with the project icon center',
      );
      final projectTitleRect = tester.getRect(
        find.descendant(of: projectRow, matching: find.byType(Text)).first,
      );
      final rootTitleRect = tester.getRect(
        find.descendant(of: rootRow, matching: find.text(root.title)),
      );
      expect(
        rootTitleRect.left,
        closeTo(projectTitleRect.left, 0.5),
        reason: 'session title left edge aligns vertically with project name',
      );
      expect(
        statusSlotRect.right,
        lessThanOrEqualTo(rootTitleRect.left),
        reason: 'session status icon sits in front of the session title',
      );
      expect(
        find.descendant(of: rootRow, matching: find.byIcon(Icons.info_outline)),
        findsOneWidget,
        reason: 'The exact root advisory is shown beside its running status',
      );
      expect(
        find.descendant(
          of: projectRow,
          matching: find.byIcon(Icons.info_outline),
        ),
        findsOneWidget,
        reason: 'Project-scoped advisory remains on its Project row',
      );

      final projects = graph.client.project.state.projects!;
      graph.client.project.applyProjectDirectory(
        ProjectDirectoryState(
          revision: projects.revision + 1,
          values: [
            for (final project in projects.values)
              StudioProject(
                id: project.id,
                name: project.id == root.workspaceId
                    ? 'Renamed project'
                    : project.name,
                path: project.path,
                kind: project.kind,
                sshAlias: project.sshAlias,
              ),
          ],
        ),
      );
      await pumpClientUntil(
        tester,
        () => find.text('Renamed project').evaluate().isNotEmpty,
        'target project content update',
      );
      expect(
        sidebarBuilds,
        0,
        reason: 'project content is not shell structure',
      );
      expect(projectBuilds[root.workspaceId], greaterThan(0));
      expect(projectBuilds.keys, everyElement(root.workspaceId));
      debugOnRebuildDirtyWidget = previousRebuild;

      graph.client.recovery.apply(
        RecoveryStateSnapshot(
          revision: graph.client.recovery.state.revision + 1,
          values: [
            StudioRecoveryIssue(
              id: 'sidebar-project-advisory',
              scope: RecoveryIssueScope.project,
              category: RecoveryIssueCategory.repository,
              impact: RecoveryIssueImpact.advisory,
              availableActions: const [],
              workspaceId: root.workspaceId,
              detail: 'Project catalog observation is delayed',
            ),
            StudioRecoveryIssue(
              id: 'sidebar-root-execution',
              scope: RecoveryIssueScope.thread,
              category: RecoveryIssueCategory.repository,
              impact: RecoveryIssueImpact.executionBlocked,
              availableActions: const [RecoveryIssueAction.retry],
              workspaceId: root.workspaceId,
              threadId: root.threadId,
              detail: 'Root execution is blocked',
            ),
            StudioRecoveryIssue(
              id: 'sidebar-foreign-child-access',
              scope: RecoveryIssueScope.thread,
              category: RecoveryIssueCategory.storage,
              impact: RecoveryIssueImpact.accessBlocked,
              availableActions: const [],
              workspaceId: root.workspaceId,
              threadId: 'unlisted-child',
              detail: 'An unlisted child has blocked access',
            ),
          ],
        ),
      );
      await tester.pump();
      expect(
        find.descendant(
          of: rootRow,
          matching: find.byIcon(Icons.error_outline),
        ),
        findsOneWidget,
        reason: 'Exact root execution block outranks the Project advisory',
      );
      expect(
        find.descendant(of: rootRow, matching: find.byIcon(Icons.info_outline)),
        findsNothing,
        reason: 'An unlisted child issue cannot override the root issue',
      );
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 30)),
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
            localizationsDelegates: [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
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
  Future<void> activateProject(String workspaceId) {
    activations.add(workspaceId);
    return super.activateProject(workspaceId);
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

final class _SidebarStatusTransport extends RecordingDemoTransport
    with DirectoryFeedFixture {}

Future<SessionDirectoryRow> _readThread(AnyworkClient client, String id) async {
  final demand = client.threadDirectory.observeThread(id);
  try {
    final state = await demand.state
        .waitFor((state) => state.frame != null || state.error != null)
        .timeout(const Duration(seconds: 5));
    if (state.error case final error?) throw error;
    return state.frame!.row!;
  } finally {
    await demand.release();
  }
}
