import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/routing/application_router.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/settings/statistics/view_models/statistics_repository_provider.dart';
import 'package:anywork/src/l10n/studio_l10n.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/platform/host_app_icons.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../../anywork_client/test/support/directory_feed.dart';
import '../support/pump_client_future.dart';
import '../support/recording_demo_transport.dart';
import '../support/test_statistics_feed.dart';

const _longTitle = '侧栏长会话名称在狭窄窗口与大字号下保持单行省略，目录内容不会被布局裁剪';

final class _ShellTransport extends RecordingDemoTransport
    with DirectoryFeedFixture {}

Future<AppGraph> _mount(WidgetTester tester, {double scale = 1}) async {
  final transport = _ShellTransport();
  final graph = AppGraph(
    transport: transport,
    statisticsFeed: const TestStatisticsFeedPort(),
  );
  final router = createApplicationRouter();
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(hostAppsChannel, (_) async => null);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    final report = await pumpClientFuture(
      tester,
      graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
      'close sidebar shell',
    );
    expect(report.complete, isTrue, reason: '${report.unresolved}');
    messenger.setMockMethodCallHandler(hostAppsChannel, null);
    expect(tester.takeException(), isNull);
  });
  await pumpClientFuture(
    tester,
    graph.initialize(),
    'initialize sidebar shell',
  );
  final project = graph.client.project.state.projects!.values.firstWhere(
    (project) => !project.isStandalone,
  );
  transport.seedThread(
    SessionDirectoryRow(
      sessionId: 'layout-session',
      agentId: 'layout-agent',
      threadId: 'layout-thread',
      workspaceId: project.id,
      title: _longTitle,
      mode: ThreadModeId.simple,
      delegationMode: DelegationMode.automatic,
      delegationPreference: DelegationPreference.balanced,
      workspacePath: project.path,
      updatedAt: DateTime.utc(2026),
      backend: const NativeAgentBackendView(
        config: NativeAgentConfigView(),
        status: ThreadStatusView.idle,
      ),
    ),
  );
  graph.client.selection.selectProject(project.id);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appGraphProvider.overrideWithValue(graph),
        statisticsRepositoryProvider.overrideWithValue(
          graph.statisticsRepository,
        ),
      ],
      child: MaterialApp.router(
        theme: pureStudioTheme(),
        locale: const Locale('zh'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    ),
  );
  await pumpClientUntil(
    tester,
    () => find.byKey(StudioDriverKeys.shell).evaluate().isNotEmpty,
    'shell ready',
  );
  return graph;
}

void main() {
  testWidgets('侧栏拖动边界、双击复位及无障碍调整使用同一生产组件', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final graph = await _mount(tester);
    final shell = find.byKey(StudioDriverKeys.shell);
    final divider = find.byKey(StudioDriverKeys.sidebarResize);
    expect(shell, findsOneWidget);
    expect(divider, findsOneWidget);

    double width() =>
        tester.getTopLeft(divider).dx - tester.getTopLeft(shell).dx;
    int? canonicalWidth() => graph
        .client
        .settings
        .state
        .canonical
        ?.state
        .value
        ?.general
        .sidebarWidth;

    final initial = width();
    await pumpClientUntil(
      tester,
      () => canonicalWidth() != null,
      'initial default width is available in canonical settings',
    );
    final defaultWidth = canonicalWidth()!;
    expect(initial, closeTo(defaultWidth, 1));
    Future<void> expectSaved(String action) async {
      final rendered = width().round();
      await pumpClientUntil(
        tester,
        () => canonicalWidth() == rendered,
        '$action: rendered width $rendered reaches canonical Client settings',
      );
    }

    await tester.drag(divider, const Offset(64, 0));
    await pumpClientUntil(
      tester,
      () => width() > initial,
      'drag changes the production sidebar width',
    );
    final dragged = width();
    await expectSaved('drag');

    await tester.drag(divider, const Offset(-1000, 0));
    await pumpClientUntil(
      tester,
      () => width() < initial && width() < dragged,
      'large negative drag reaches a lower width',
    );
    final lowerBoundary = width();
    await expectSaved('lower boundary');
    await tester.drag(divider, const Offset(-64, 0));
    await tester.pump();
    expect(
      width(),
      closeTo(lowerBoundary, 1),
      reason: 'further outward drag cannot cross the lower boundary',
    );
    await expectSaved('repeated lower-boundary drag');
    await tester.drag(divider, const Offset(1000, 0));
    await pumpClientUntil(
      tester,
      () => width() > initial && width() > lowerBoundary,
      'large positive drag reaches an upper width',
    );
    final upperBoundary = width();
    await expectSaved('upper boundary');
    await tester.drag(divider, const Offset(64, 0));
    await tester.pump();
    expect(
      width(),
      closeTo(upperBoundary, 1),
      reason: 'further outward drag cannot cross the upper boundary',
    );
    await expectSaved('repeated upper-boundary drag');

    // Advance the framework's double-tap gesture clock, then settle its
    // recognizer and layout before exercising the independent semantics action.
    await tester.tap(divider);
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(divider);
    await tester.pumpAndSettle();
    await pumpClientUntil(
      tester,
      () => (width() - defaultWidth).abs() <= 1,
      'double tap restores the initial default in the UI',
    );
    await expectSaved('double-tap default restoration');

    // 应用自定义按键已移除；无障碍用户仍可通过官方语义动作调整宽度。
    final resizeSemantics = find.semantics.byLabel(
      tester.element(divider).l10n.sidebarResize,
    );
    tester.semantics.increase(resizeSemantics);
    await pumpClientUntil(
      tester,
      () => width() > defaultWidth,
      'accessibility increase widens the sidebar in the UI',
    );
    final increasedWidth = width();
    await expectSaved('accessibility increase');
    tester.semantics.decrease(resizeSemantics);
    await pumpClientUntil(
      tester,
      () => width() < increasedWidth,
      'accessibility decrease narrows the sidebar in the UI',
    );
    expect(
      width(),
      closeTo(defaultWidth, 1),
      reason: 'inverse accessibility actions restore the original width',
    );
    await expectSaved('accessibility decrease');
    expect(tester.takeException(), isNull);
  }, semanticsEnabled: true);

  testWidgets('窄窗大字侧栏抽屉可达且保留目录内容', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(820, 760);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mount(tester, scale: 1.6);
    expect(find.byKey(StudioDriverKeys.sidebar), findsNothing);
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-toggle')));
    await tester.pumpAndSettle();
    final sidebar = find.byKey(StudioDriverKeys.sidebar);
    expect(sidebar.hitTestable(), findsOneWidget);
    expect(tester.getRect(sidebar).left, greaterThanOrEqualTo(0));
    expect(tester.getRect(sidebar).right, lessThanOrEqualTo(820));
    expect(
      MediaQuery.textScalerOf(tester.element(sidebar)).scale(14),
      closeTo(22.4, .001),
    );
    expect(
      find.byKey(const ValueKey('sidebar-search')).hitTestable(),
      findsOneWidget,
    );
    await pumpClientUntil(
      tester,
      () => find
          .byKey(StudioDriverKeys.threadRow('layout-thread'))
          .evaluate()
          .isNotEmpty,
      'directory row in compact drawer',
    );
    expect(find.text(_longTitle), findsOneWidget);
    expect(tester.widget<Text>(find.text(_longTitle)).maxLines, 1);
    expect(tester.takeException(), isNull);
  });
}
