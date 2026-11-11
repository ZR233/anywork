import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/shell/sidebar/sidebar_connectors.dart';
import 'package:anywork/src/features/shell/sidebar/sidebar_views.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/presentation/providers/client_provider.dart';
import 'package:anywork/src/presentation/providers/thread_directory_store.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../../anywork_client/test/support/directory_feed.dart';
import '../support/pump_client_future.dart';
import '../support/recording_demo_transport.dart';
import '../support/test_statistics_feed.dart';

const _project = StudioProject(id: 'p', name: 'Project', path: '/project');
const _apps = SidebarHostApps(terminalUnavailableReason: 'Unavailable');

SessionDirectoryRow _row(String id) => SessionDirectoryRow(
  backend: const NativeAgentBackendView(
    config: NativeAgentConfigView(),
    status: ThreadStatusView.idle,
  ),
  sessionId: 'session-$id',
  agentId: 'agent-$id',
  threadId: id,
  workspaceId: _project.id,
  title: 'Row $id',
  mode: ThreadModeId.simple,
  delegationMode: DelegationMode.automatic,
  delegationPreference: DelegationPreference.balanced,
  updatedAt: DateTime.utc(2026),
  workspacePath: '/project',
);

Widget _host(Widget child, {double scale = 1}) => MaterialApp(
  theme: pureStudioTheme(),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: SizedBox(width: 300, height: 420, child: child),
    ),
  ),
);

Widget _sidebar() => StudioSidebar(
  data: SidebarData(projectIds: [_project.id], selectedProjectId: _project.id),
  onQueryChanged: (_) {},
  projectStructureBuilder: (context, projectId, selection, builder) =>
      SidebarProjectConnector(
        key: ValueKey(projectId),
        projectId: projectId,
        selection: selection,
        builder: builder,
      ),
  threadBuilder:
      (context, project, threadId, touch, archived, select, action) =>
          SidebarThreadConnector(
            threadId: threadId,
            project: project,
            hostApps: _apps,
            touchMode: touch,
            archived: archived,
            onSelect: select,
            onAction: action,
          ),
  onNewSession: () {},
  onAddProject: () {},
  onSelectProject: (_) {},
  onNewProjectSession: (_) {},
  onSelectThread: (_) {},
  onProjectAction: (_, _) {},
  onThreadAction: (_, _, _) {},
  onSettings: () {},
);

void main() {
  testWidgets(
    'production per-ID content update leaves B, project, shell and local UI intact',
    (tester) async {
      final transport = _Transport();
      for (final id in ['A', 'B', for (var i = 0; i < 18; i++) 'extra-$i']) {
        transport.seedThread(_row(id));
      }
      final graph = AppGraph(
        transport: transport,
        statisticsFeed: const TestStatisticsFeedPort(),
      );
      graph.client.project.applyProjectDirectory(
        ProjectDirectoryState(revision: 1, values: const [_project]),
      );
      addTearDown(() async {
        final report = await pumpClientFuture(
          tester,
          graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
          'close the sidebar graph',
        );
        expect(
          report.complete,
          isTrue,
          reason: report.unresolved
              .map((value) => '${value.owner}: ${value.reason}')
              .join('; '),
        );
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appGraphProvider.overrideWithValue(graph)],
          child: _host(_sidebar()),
        ),
      );
      await pumpClientUntil(
        tester,
        () => find.text('Row A').evaluate().isNotEmpty,
        'initial rows',
      );
      final search = find.byKey(const ValueKey('sidebar-search'));
      final openedBefore = transport.openedDirectoryQueries.length;
      await tester.enterText(search, 'Row');
      await tester.pump(const Duration(milliseconds: 199));
      expect(transport.openedDirectoryQueries, hasLength(openedBefore));
      await tester.pump(const Duration(milliseconds: 1));
      await pumpClientUntil(
        tester,
        () => transport.openedDirectoryQueries.length > openedBefore,
        'debounced search',
      );
      await pumpClientUntil(
        tester,
        () => find.text('Row B').evaluate().isNotEmpty,
        'new query rows',
      );
      final field = tester.widget<TextField>(search);
      final editor = field.controller;
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      final focus = editable.focusNode;
      expect(focus.hasFocus, isTrue);
      final scroll = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('sidebar-project-tree')),
          )
          .controller!;
      scroll.jumpTo(100);
      await tester.pump();
      final builds = <String, int>{};
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        previous?.call(element, builtOnce);
        final widget = element.widget;
        final key = switch (widget) {
          SidebarThreadConnector() => widget.threadId,
          StudioSidebar() => 'shell',
          SidebarProjectConnector() => 'structure',
          SidebarProjectRow() => 'project',
          _ => null,
        };
        if (key != null) {
          builds.update(key, (value) => value + 1, ifAbsent: () => 1);
        }
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previous);
      transport.emitThread(
        _row('A').copyWith(title: 'Renamed A'),
        'A',
        revision: 2,
      );
      await pumpClientUntil(
        tester,
        () => find.text('Renamed A').evaluate().isNotEmpty,
        'A metadata update',
      );
      expect(builds['A'], greaterThan(0));
      for (final key in ['B', 'shell', 'project', 'structure']) {
        expect(
          builds[key] ?? 0,
          0,
          reason: '$key must not rebuild for A metadata',
        );
      }
      expect(tester.widget<TextField>(search).controller, same(editor));
      expect(editor!.text, 'Row');
      expect(focus.hasFocus, isTrue);
      expect(scroll.offset, 100);
      expect(
        transport.feeds,
        isEmpty,
        reason: 'directory rendering must not open history',
      );

      // Another consumer's borrow survives removal of the sidebar.
      final shared = graph.client.threadDirectory.observeThread('A');
      addTearDown(
        () => pumpClientFuture(
          tester,
          shared.release(),
          'release shared metadata on failure',
        ),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      transport.emitThread(
        _row('A').copyWith(title: 'Shared A'),
        'A',
        revision: 3,
      );
      await shared.state
          .waitFor((state) => state.frame?.row?.title == 'Shared A')
          .timeout(const Duration(seconds: 5));
      expect(shared.state.value.closed, isFalse);
      await pumpClientFuture(
        tester,
        shared.release(),
        'release shared metadata',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('long SSH Host stays bounded at narrow width and large text', (
    tester,
  ) async {
    const alias =
        'production-cluster-with-an-extremely-long-host-name.example.org';
    await tester.pumpWidget(
      _host(
        SidebarProjectRow(
          project: const StudioProject(
            id: 'p',
            name: 'Project',
            path: '/project',
            sshAlias: alias,
          ),
          selected: false,
          expanded: true,
          pinned: false,
          touchMode: true,
          onToggle: () {},
          onSelect: () {},
          onNewSession: () {},
          onAction: (_) {},
        ),
        scale: 1.7,
      ),
    );
    expect(find.text(alias), findsOneWidget);
    expect(find.byTooltip(alias), findsOneWidget);
    final nameRect = tester.getRect(find.text(_project.name));
    expect(nameRect.width, greaterThan(25));
    expect(tester.getRect(find.text(alias)).width, lessThanOrEqualTo(64));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'hovered row actions follow the pointer without changing selection',
    (tester) async {
      final first = _project;
      const second = StudioProject(
        id: 'second',
        name: 'Second project',
        path: '/second',
      );
      final selected = <String>[];
      Widget projectRow(StudioProject project) => SidebarProjectRow(
        project: project,
        selected: false,
        expanded: false,
        pinned: false,
        onToggle: () {},
        onSelect: () => selected.add(project.id),
        onNewSession: () {},
        onAction: (_) {},
      );
      await tester.pumpWidget(
        _host(Column(children: [projectRow(first), projectRow(second)])),
      );
      final firstMenu = find.byKey(StudioDriverKeys.projectMenu(first.id));
      final secondMenu = find.byKey(StudioDriverKeys.projectMenu(second.id));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer();
      expect(firstMenu, findsOneWidget);
      expect(secondMenu, findsOneWidget);
      expect(
        tester
            .widget<Visibility>(
              find
                  .ancestor(of: firstMenu, matching: find.byType(Visibility))
                  .first,
            )
            .visible,
        isFalse,
      );

      await mouse.moveTo(
        tester.getCenter(find.byKey(StudioDriverKeys.projectRow(first.id))),
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.text('/project'), findsOneWidget);
      expect(find.text('/second'), findsNothing);
      expect(
        tester
            .widget<Visibility>(
              find
                  .ancestor(of: firstMenu, matching: find.byType(Visibility))
                  .first,
            )
            .visible,
        isTrue,
      );
      await mouse.moveTo(
        tester.getCenter(find.byKey(StudioDriverKeys.projectRow(second.id))),
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.text('/project'), findsNothing);
      expect(find.text('/second'), findsOneWidget);
      expect(
        tester
            .widget<Visibility>(
              find
                  .ancestor(of: firstMenu, matching: find.byType(Visibility))
                  .first,
            )
            .visible,
        isFalse,
      );
      expect(
        tester
            .widget<Visibility>(
              find
                  .ancestor(of: secondMenu, matching: find.byType(Visibility))
                  .first,
            )
            .visible,
        isTrue,
      );
      expect(selected, isEmpty);
      await mouse.moveTo(const Offset(290, 400));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.text('/project'), findsNothing);
      expect(find.text('/second'), findsNothing);
      expect(
        tester
            .widget<Visibility>(
              find
                  .ancestor(of: secondMenu, matching: find.byType(Visibility))
                  .first,
            )
            .visible,
        isFalse,
      );
    },
  );

  testWidgets('archived row hover keeps its available restore action', (
    tester,
  ) async {
    final actions = <SidebarThreadAction>[];
    await tester.pumpWidget(
      _host(
        SidebarThreadRow(
          row: _row('archived'),
          project: _project,
          selected: false,
          pinned: false,
          hostApps: _apps,
          archived: true,
          onSelect: () => fail('archived row must not select'),
          onAction: actions.add,
        ),
      ),
    );
    final row = find.byKey(StudioDriverKeys.threadRow('archived'));
    final restore = find.byKey(const ValueKey('thread-restore-archived'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();
    expect(restore, findsOneWidget);
    expect(
      tester
          .widget<Visibility>(
            find.ancestor(of: restore, matching: find.byType(Visibility)).first,
          )
          .visible,
      isFalse,
    );
    await mouse.moveTo(tester.getCenter(row));
    await tester.pump(const Duration(milliseconds: 1));
    expect(
      tester
          .widget<Visibility>(
            find.ancestor(of: restore, matching: find.byType(Visibility)).first,
          )
          .visible,
      isTrue,
    );
    await tester.tap(restore);
    expect(actions, [SidebarThreadAction.restore]);
    expect(tester.takeException(), isNull);

    await mouse.moveTo(const Offset(290, 400));
    await tester.pumpAndSettle();
    actions.clear();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      _host(
        SidebarThreadRow(
          row: _row('archived'),
          project: _project,
          selected: false,
          pinned: false,
          hostApps: _apps,
          archived: true,
          touchMode: true,
          onSelect: () => fail('archived row must not select'),
          onAction: actions.add,
        ),
      ),
    );
    expect(
      tester
          .widget<Visibility>(
            find.ancestor(of: restore, matching: find.byType(Visibility)).first,
          )
          .visible,
      isTrue,
    );
    await tester.tap(restore);
    expect(actions, [SidebarThreadAction.restore]);
  });

  testWidgets('keyboard traversal activates the row and restores menu focus', (
    tester,
  ) async {
    var selections = 0;
    var toggles = 0;
    final nextFocus = FocusNode(debugLabel: 'after-sidebar-row');
    addTearDown(nextFocus.dispose);
    await tester.pumpWidget(
      _host(
        Column(
          children: [
            SidebarProjectRow(
              project: _project,
              selected: false,
              expanded: false,
              pinned: false,
              onToggle: () => toggles++,
              onSelect: () => selections++,
              onNewSession: () {},
              onAction: (_) {},
            ),
            TextButton(
              key: const ValueKey('after-sidebar-row'),
              focusNode: nextFocus,
              onPressed: () {},
              child: const Text('After sidebar'),
            ),
          ],
        ),
      ),
    );
    final expand = find.byKey(StudioDriverKeys.projectExpand(_project.id));
    final menuAnchor = tester.widget<MenuAnchor>(
      find.byKey(StudioDriverKeys.projectMenu(_project.id)),
    );
    final more = find.descendant(
      of: find.byKey(StudioDriverKeys.projectMenu(_project.id)),
      matching: find.byIcon(Icons.more_horiz),
    );
    final moreButton = tester.widget<IconButton>(
      find.ancestor(of: more, matching: find.byType(IconButton)).first,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(Focus.of(tester.element(expand)).hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(selections, 1);
    expect(toggles, 0);
    for (var i = 0; i < 5 && !moreButton.focusNode!.hasFocus; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(moreButton.focusNode!.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(menuAnchor.controller!.isOpen, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(menuAnchor.controller!.isOpen, isFalse);
    expect(moreButton.focusNode!.hasFocus, isTrue);
    expect(
      tester
          .widget<Visibility>(
            find.ancestor(of: more, matching: find.byType(Visibility)).first,
          )
          .visible,
      isTrue,
    );
    for (var i = 0; i < 5 && !nextFocus.hasPrimaryFocus; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(nextFocus.hasPrimaryFocus, isTrue);
    expect(
      tester
          .widget<Visibility>(
            find.ancestor(of: more, matching: find.byType(Visibility)).first,
          )
          .visible,
      isFalse,
    );
  });

  testWidgets(
    'production metadata retry retains only its identity and rebinds Client',
    (tester) async {
      final transport = _Transport()..seedThread(_row('A'));
      transport.failMetadataOpen = StateError('metadata offline');
      final first = AppGraph(
        transport: transport,
        statisticsFeed: const TestStatisticsFeedPort(),
      );
      final replacementTransport = _Transport();
      final replacement = AppGraph(
        transport: replacementTransport,
        statisticsFeed: const TestStatisticsFeedPort(),
      );
      final container = ProviderContainer(
        overrides: [anyworkClientProvider.overrideWithValue(first.client)],
      );
      addTearDown(() async {
        container.dispose();
        final firstReport = await pumpClientFuture(
          tester,
          first.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
          'close the retired Client graph',
        );
        final replacementReport = await pumpClientFuture(
          tester,
          replacement.close(
            deadline: DateTime.now().add(const Duration(seconds: 5)),
          ),
          'close the replacement Client graph',
        );
        expect(
          firstReport.complete,
          isTrue,
          reason: firstReport.unresolved
              .map((value) => '${value.owner}: ${value.reason}')
              .join('; '),
        );
        expect(
          replacementReport.complete,
          isTrue,
          reason: replacementReport.unresolved
              .map((value) => '${value.owner}: ${value.reason}')
              .join('; '),
        );
      });
      Widget row() => SidebarThreadConnector(
        threadId: 'A',
        project: _project,
        hostApps: _apps,
        onSelect: (_) {},
        onAction: (_, _) {},
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: _host(row())),
      );
      await pumpClientUntil(
        tester,
        () => find
            .byKey(const ValueKey('sidebar-thread-error-A'))
            .evaluate()
            .isNotEmpty,
        'initial metadata failure',
      );
      expect(find.text('Row A'), findsNothing);
      await tester.tap(find.byType(TextButton));
      await pumpClientUntil(
        tester,
        () => find.text('Row A').evaluate().isNotEmpty,
        'metadata retry',
      );
      transport.failMetadataOpen = StateError('refresh offline');
      await pumpClientFuture(
        tester,
        container.read(threadMetadataDemandProvider('A')).refresh(),
        'failed metadata refresh',
      );
      await pumpClientUntil(
        tester,
        () => find
            .byKey(const ValueKey('sidebar-thread-error-A'))
            .evaluate()
            .isNotEmpty,
        'retained metadata failure',
      );
      expect(find.text('Row A'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('sidebar-thread-error-A')),
        findsOneWidget,
      );

      // Same thread ID on a new Client must not read the retired Client's row.
      container.updateOverrides([
        anyworkClientProvider.overrideWithValue(replacement.client),
      ]);
      await tester.pump();
      await pumpClientUntil(
        tester,
        () => find
            .byKey(const ValueKey('sidebar-thread-missing-A'))
            .evaluate()
            .isNotEmpty,
        'replacement Client absence',
      );
      expect(find.text('Row A'), findsNothing);
      expect(
        find.byKey(const ValueKey('sidebar-thread-error-A')),
        findsNothing,
      );
      // The external container outlives the row. Keep its scheduling scope
      // mounted while autoDispose processes the last row listener.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const SizedBox.shrink(),
        ),
      );
      await pumpClientUntil(
        tester,
        () => replacementTransport.directoryCloseCalls == 1,
        'last replacement borrow released',
      );
      expect(transport.directoryCloseCalls, greaterThan(0));
      expect(replacementTransport.directoryCloseCalls, 1);
    },
  );

  testWidgets(
    'content distinguishes initial loading, absence and retained failure',
    (tester) async {
      var retries = 0;
      Widget content({
        SessionDirectoryRow? row,
        bool loading = false,
        bool loaded = false,
        String? error,
      }) => _host(
        SidebarThreadContent(
          threadId: 'A',
          row: row,
          loading: loading,
          loaded: loaded,
          error: error,
          onRetry: () => retries++,
          rowBuilder: (row) => Text(row.title),
        ),
      );
      await tester.pumpWidget(content(loading: true));
      expect(
        find.byKey(const ValueKey('sidebar-thread-loading-A')),
        findsOneWidget,
      );
      await tester.pumpWidget(content(loaded: true));
      expect(
        find.byKey(const ValueKey('sidebar-thread-missing-A')),
        findsOneWidget,
      );
      await tester.pumpWidget(
        content(row: _row('A'), loaded: true, error: 'metadata unavailable'),
      );
      expect(find.text('Row A'), findsOneWidget);
      expect(find.text('metadata unavailable'), findsOneWidget);
      await tester.tap(find.byType(TextButton));
      expect(retries, 1);
      expect(
        find.byKey(const ValueKey('sidebar-thread-missing-A')),
        findsNothing,
      );
    },
  );
}

final class _Transport extends RecordingDemoTransport
    with DirectoryFeedFixture {
  Object? failMetadataOpen;

  @override
  Future<ThreadObservationHandle> openThreadObservation(String threadId) {
    final failure = failMetadataOpen;
    failMetadataOpen = null;
    if (failure != null) return Future.error(failure);
    return super.openThreadObservation(threadId);
  }
}
