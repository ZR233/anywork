import 'dart:async';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/routing/application_router.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/shell/sidebar/sidebar_views.dart';
import 'package:anywork/src/features/shell/studio_shell.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/l10n/studio_l10n.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pump_client_future.dart';
import '../support/recording_demo_transport.dart';
import '../support/test_app_lifecycle.dart';
import '../support/test_statistics_feed.dart';

const _project = StudioProject(
  id: 'project',
  name: 'Project',
  path: '/project',
);

SessionDirectoryRow _thread({required String id}) => SessionDirectoryRow(
  backend: NativeAgentBackendView(
    config: const NativeAgentConfigView(),
    status: ThreadStatusView.idle,
  ),
  sessionId: 'session-$id',
  agentId: 'agent-$id',
  threadId: id,
  workspaceId: _project.id,
  title: 'Session $id',
  mode: ThreadModeId.simple,
  delegationMode: DelegationMode.automatic,
  delegationPreference: DelegationPreference.balanced,
  updatedAt: DateTime.utc(2026),
  workspacePath: _project.path,
);

Widget _sidebarRowHost(Widget row) => MaterialApp(
  theme: pureStudioTheme(),
  locale: const Locale('zh'),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Center(
      child: SizedBox(width: 560, child: Material(child: row)),
    ),
  ),
);

SidebarThreadRow _sidebarRow({
  required SessionDirectoryRow thread,
  required ValueChanged<SidebarThreadAction> onAction,
  bool archived = false,
}) => SidebarThreadRow(
  row: thread,
  project: _project,
  selected: false,
  pinned: false,
  hostApps: const SidebarHostApps(
    terminalUnavailableReason: 'Unavailable in this test.',
  ),
  onSelect: () {},
  onAction: onAction,
  archived: archived,
  touchMode: true,
);

class _GatedRemovalTransport extends RecordingDemoTransport {
  final cleanup = Completer<void>();
  final requests = <String>[];

  Future<void> seedArchivedThread() => super.archiveThread(
    'thread-alt',
    operationId: const OperationId('seed-archived-thread'),
  );

  @override
  Future<ArchiveThreadCommandReply> archiveThread(
    String threadId, {
    required OperationId operationId,
  }) async {
    requests.add('archive:$threadId');
    await cleanup.future;
    return super.archiveThread(threadId, operationId: operationId);
  }

  @override
  Future<DeleteThreadCommandReply?> deleteThread(
    String threadId, {
    required OperationId operationId,
  }) async {
    requests.add('delete:$threadId');
    await cleanup.future;
    return super.deleteThread(threadId, operationId: operationId);
  }
}

const _target = 'thread-main';
const _alternate = 'thread-alt';
const _targetTitle = 'Flutter + FRB 重构';

Future<AnyworkClient> _mountShell(
  WidgetTester tester,
  _GatedRemovalTransport transport,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final graph = testAppGraph(
    transport: transport,
    statisticsFeed: const TestStatisticsFeedPort(),
  );
  final router = createApplicationRouter();
  addTearDown(() async {
    if (!transport.cleanup.isCompleted) transport.cleanup.complete();
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    final report = await pumpClientFuture(
      tester,
      graph.close(budget: testCloseBudget()),
      'close sidebar shell',
    );
    expect(report.complete, isTrue, reason: describeTestCloseReport(report));
  });
  await pumpClientFuture(tester, graph.initialize(), 'initialize sidebar');
  await pumpClientFuture(
    tester,
    graph.client.directoryCommands.selectThread(_target),
    'select removal target',
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appGraphProvider.overrideWithValue(graph)],
      child: MaterialApp.router(
        theme: pureStudioTheme(),
        locale: const Locale('zh'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await pumpClientUntil(
    tester,
    () => find.byKey(StudioDriverKeys.threadRow(_target)).evaluate().isNotEmpty,
    'show target in sidebar',
  );
  return graph.client;
}

Future<void> _openTargetMenu(WidgetTester tester) async {
  final row = find.byKey(StudioDriverKeys.threadRow(_target));
  final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await pointer.addPointer(location: tester.getCenter(row));
  try {
    await pointer.moveTo(tester.getCenter(row));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byKey(StudioDriverKeys.threadMenu(_target)),
        matching: find.byType(IconButton),
      ),
    );
    await _pumpOverlayTransition(tester);
  } finally {
    await pointer.removePointer();
  }
}

Future<void> _pumpOverlayTransition(WidgetTester tester) async {
  await tester.pump();
  // Advance the menu/dialog animation without waiting on the shell's spinners.
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('active session menu deletes with a text-only item', (
    tester,
  ) async {
    final actions = <SidebarThreadAction>[];
    final thread = _thread(id: 'active');
    await tester.pumpWidget(
      _sidebarRowHost(_sidebarRow(thread: thread, onAction: actions.add)),
    );
    final menuTrigger = find.descendant(
      of: find.byKey(StudioDriverKeys.threadMenu(thread.threadId)),
      matching: find.byType(IconButton),
    );
    await tester.tap(menuTrigger);
    await tester.pumpAndSettle();

    expect(
      find.byKey(StudioDriverKeys.deleteThread(thread.threadId)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(StudioDriverKeys.deleteThread(thread.threadId)),
        matching: find.byType(Icon),
      ),
      findsNothing,
    );
    expect(
      find.byKey(StudioDriverKeys.archiveThread(thread.threadId)),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(StudioDriverKeys.deleteThread(thread.threadId)),
    );
    await tester.pumpAndSettle();

    expect(actions, [SidebarThreadAction.delete]);
  });

  testWidgets(
    'active session workspace submenu exposes host application entries',
    (tester) async {
      final actions = <SidebarThreadAction>[];
      final thread = _thread(id: 'submenu');
      await tester.pumpWidget(
        _sidebarRowHost(_sidebarRow(thread: thread, onAction: actions.add)),
      );
      final menuTrigger = find.descendant(
        of: find.byKey(StudioDriverKeys.threadMenu(thread.threadId)),
        matching: find.byType(IconButton),
      );
      await tester.tap(menuTrigger);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(StudioDriverKeys.openThreadWorkspace(thread.threadId)),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(StudioDriverKeys.openThreadVsCode(thread.threadId)),
        findsOneWidget,
      );
      expect(
        find.byKey(StudioDriverKeys.openThreadZed(thread.threadId)),
        findsOneWidget,
      );
      expect(
        find.byKey(StudioDriverKeys.openThreadTerminal(thread.threadId)),
        findsOneWidget,
      );
      expect(actions, isEmpty);
    },
  );

  testWidgets(
    'archived session has a delete button without replacing restore',
    (tester) async {
      final actions = <SidebarThreadAction>[];
      final thread = _thread(id: 'archived');
      await tester.pumpWidget(
        _sidebarRowHost(
          _sidebarRow(thread: thread, archived: true, onAction: actions.add),
        ),
      );

      final deleteButton = StudioDriverKeys.deleteThread(thread.threadId);
      final restoreButton = ValueKey<String>(
        'thread-restore-${thread.threadId}',
      );
      expect(find.byKey(deleteButton), findsOneWidget);
      expect(find.byKey(restoreButton), findsOneWidget);
      expect(
        find.byKey(StudioDriverKeys.threadMenu(thread.threadId)),
        findsNothing,
      );
      await tester.tap(find.byKey(deleteButton));
      await tester.pump();

      expect(actions, [SidebarThreadAction.delete]);
      expect(find.byKey(restoreButton), findsOneWidget);
    },
  );

  testWidgets('cancel leaves the selected session and issues no command', (
    tester,
  ) async {
    final transport = _GatedRemovalTransport();
    final client = await _mountShell(tester, transport);
    await _openTargetMenu(tester);
    await tester.tap(find.byKey(StudioDriverKeys.archiveThread(_target)));
    await _pumpOverlayTransition(tester);

    final dialog = find.byType(ThreadDestructiveActionDialog);
    final l10n = tester.element(dialog).l10n;
    expect(find.text(l10n.sidebarArchiveSessionConfirmBody), findsOneWidget);
    expect(find.text(l10n.sidebarDeleteSessionConfirmBody), findsNothing);
    await tester.tap(find.text(l10n.commonCancel));
    await _pumpOverlayTransition(tester);

    expect(transport.requests, isEmpty);
    expect(client.selection.state.selectedThreadId, _target);
    expect(dialog, findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  for (final (deleting, succeeds) in [
    (true, true),
    (true, false),
    (false, false),
  ]) {
    testWidgets(
      '${deleting ? 'delete' : 'archive'} switches while cleanup is pending '
      'and reports ${succeeds ? 'success' : 'failure'} after it settles',
      (tester) async {
        final transport = _GatedRemovalTransport();
        final client = await _mountShell(tester, transport);
        await _openTargetMenu(tester);
        final delete = find.byKey(StudioDriverKeys.deleteThread(_target));
        final archive = find.byKey(StudioDriverKeys.archiveThread(_target));
        await tester.tap(deleting ? delete : archive);
        await _pumpOverlayTransition(tester);

        final dialog = find.byType(ThreadDestructiveActionDialog);
        final l10n = tester.element(dialog).l10n;
        if (deleting) {
          expect(
            find.text(l10n.sidebarDeleteSessionConfirmTitle(_targetTitle)),
            findsOneWidget,
          );
          expect(
            find.text(l10n.sidebarDeleteSessionConfirmBody),
            findsOneWidget,
          );
          expect(
            find.text(l10n.sidebarArchiveSessionConfirmBody),
            findsNothing,
          );
        }
        await tester.tap(
          find.byKey(
            deleting
                ? StudioDriverKeys.deleteThreadConfirm(_target)
                : StudioDriverKeys.archiveThreadConfirm,
          ),
        );
        await pumpClientUntil(
          tester,
          () => transport.requests.isNotEmpty,
          'start the gated cleanup',
        );
        await _pumpOverlayTransition(tester);

        expect(dialog, findsNothing);
        expect(client.selection.state.selectedThreadId, _alternate);
        expect(find.byType(SnackBar), findsNothing);
        final row = find.byKey(StudioDriverKeys.threadRow(_target));
        expect(row, findsOneWidget);
        await _openTargetMenu(tester);
        expect(tester.widget<MenuItemButton>(delete).onPressed, isNull);
        expect(tester.widget<MenuItemButton>(archive).onPressed, isNull);
        await tester.tapAt(const Offset(650, 450));
        await _pumpOverlayTransition(tester);

        const failure = StudioFailure(
          code: StudioFailureCode.permissionDenied,
          message: 'Cleanup refused',
          retryable: true,
          correlationId: 'test-removal',
        );
        if (succeeds) {
          transport.cleanup.complete();
        } else {
          transport.cleanup.completeError(failure);
        }
        final message = succeeds
            ? l10n.sidebarDeleteSessionSucceeded(_targetTitle)
            : (deleting
                  ? l10n.sidebarDeleteSessionResultFailed
                  : l10n.sidebarArchiveSessionResultFailed)(
                _targetTitle,
                failure.toString(),
              );
        await pumpClientUntil(
          tester,
          () => find.text(message).evaluate().isNotEmpty,
          'show the actual cleanup outcome',
        );
        final snackBar = find.byType(SnackBar);
        expect(snackBar, findsOneWidget);
        final close = find.descendant(
          of: snackBar,
          matching: find.byTooltip(
            MaterialLocalizations.of(tester.element(snackBar))
                .closeButtonTooltip,
          ),
        );
        expect(close, findsOneWidget);
        expect(transport.requests, [
          '${deleting ? 'delete' : 'archive'}:$_target',
        ]);
        expect(client.selection.state.selectedThreadId, _alternate);
        if (succeeds) {
          await pumpClientUntil(
            tester,
            () => row.evaluate().isEmpty,
            'committed directory removal',
          );
        } else {
          expect(row, findsOneWidget);
          await _openTargetMenu(tester);
          expect(tester.widget<MenuItemButton>(archive).onPressed, isNotNull);
          await tester.tapAt(const Offset(650, 450));
          await _pumpOverlayTransition(tester);
        }

        await _pumpOverlayTransition(tester);
        if (!deleting) {
          final archiveToggle = find.byKey(const ValueKey('sidebar-archived'));
          expect(archiveToggle.hitTestable(), findsOneWidget);
          await tester.tap(archiveToggle);
          await _pumpOverlayTransition(tester);
          expect(
            find.widgetWithText(SidebarSectionHeading, l10n.sidebarArchived),
            findsOneWidget,
          );
          expect(snackBar, findsOneWidget);
        }
        if (deleting && !succeeds) {
          await tester.tap(close);
        } else {
          await tester.pump(Duration(seconds: succeeds ? 4 : 7));
          expect(snackBar, findsOneWidget);
          await tester.pump(const Duration(seconds: 1));
        }
        await _pumpOverlayTransition(tester);
        expect(snackBar, findsNothing);
        expect(client.selection.state.selectedThreadId, _alternate);
      },
    );
  }

  testWidgets('confirming an archived deletion returns to the active list', (
    tester,
  ) async {
    final transport = _GatedRemovalTransport();
    await pumpClientFuture(
      tester,
      transport.seedArchivedThread(),
      'archive fixture',
    );
    final client = await _mountShell(tester, transport);
    final activeRow = find.byKey(StudioDriverKeys.threadRow(_target));
    await tester.tap(find.byKey(const ValueKey('sidebar-archived')));
    final delete = find.byKey(StudioDriverKeys.deleteThread(_alternate));
    await pumpClientUntil(
      tester,
      () => delete.hitTestable().evaluate().isNotEmpty,
      'show archived delete action',
    );
    expect(activeRow, findsNothing);
    await tester.tap(delete);
    await _pumpOverlayTransition(tester);
    await tester.tap(
      find.byKey(StudioDriverKeys.deleteThreadConfirm(_alternate)),
    );
    await pumpClientUntil(
      tester,
      () => transport.requests.isNotEmpty && activeRow.evaluate().isNotEmpty,
      'return to active sessions during cleanup',
    );
    expect(client.selection.state.selectedThreadId, _target);
    expect(delete, findsNothing);
    expect(transport.cleanup.isCompleted, isFalse);
    transport.cleanup.complete();
  });
}
