import 'dart:async';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/settings/settings_mcp_tab.dart';
import 'package:anywork/src/features/settings/settings_scope.dart';
import 'package:anywork/src/features/status/thread_status_bar.dart';
import 'package:anywork/src/features/status/status_view.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:anywork/src/infrastructure/demo/studio_demo_api.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';

import '../support/pump_client_future.dart';
import '../support/test_statistics_feed.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'McpTab manages Host and SSH single-file TOML catalogs without runtime probe actions',
    (tester) async {
      final transport = DemoStudioTransport(lspActivityLoop: false);
      await transport.saveSshServer(
        const SaveSshServerCommand(
          alias: 'gpu-box',
          hostName: '10.0.0.12',
          port: 22,
          username: 'ubuntu',
        ),
      );
      final graph = AppGraph(
        statisticsFeed: const TestStatisticsFeedPort(),
        transport: transport,
        clientId: 'mcp-settings-ui',
      );
      final container = ProviderContainer(
        overrides: [appGraphProvider.overrideWithValue(graph)],
      );
      container.read(settingsVisibleTabProvider.notifier).select(4);
      await pumpClientFuture(
        tester,
        graph.client.bootstrap(),
        'mcp settings bootstrap',
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: pureStudioTheme(),
            locale: const Locale('zh'),
            localizationsDelegates: [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: SizedBox(
                width: 1100,
                height: 800,
                child: McpTab(tabIndex: 4),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Settings MCP tab shows static desired config without runtime reconnect buttons.
      expect(find.byKey(StudioDriverKeys.mcpResetAll), findsNothing);
      expect(find.byKey(StudioDriverKeys.mcpServerRow('dart')), findsOneWidget);
      expect(find.byKey(StudioDriverKeys.mcpResetServer('dart')), findsNothing);

      // Create a new Host MCP single-file TOML document.
      await tester.tap(
        find.byKey(const ValueKey<String>('mcp-create-document')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey<String>('mcp-create-id-input')),
        'git_tools',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('mcp-create-toml-input')),
        'id = "git_tools"\nkind = "server"\ntransport = "stdio"\ncommand = "uvx"\nargs = ["mcp-server-git"]\n',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('mcp-create-confirm')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(StudioDriverKeys.mcpServerRow('git_tools')),
        findsOneWidget,
      );

      // Switch to SSH · gpu-box scope and disable remote_pg with a tombstone.
      await tester.tap(
        find.byKey(const ValueKey<String>('mcp-scope-selector')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('SSH · gpu-box').last);
      await tester.pumpAndSettle();

      await pumpClientFuture(
        tester,
        graph.client.directoryCommands.readMcpCatalog(
          const SshMcpScope(sshAlias: 'gpu-box'),
        ),
        'read ssh mcp catalog',
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('mcp-create-document')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey<String>('mcp-create-id-input')),
        'remote_pg',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('mcp-create-toml-input')),
        'id = "remote_pg"\nkind = "server"\ntransport = "stdio"\ncommand = "uvx"\nargs = ["mcp-server-postgres"]\n',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('mcp-create-confirm')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(StudioDriverKeys.mcpServerRow('remote_pg')),
        findsOneWidget,
      );

      // Disable remote_pg in SSH scope -> becomes sshDisabledTombstone.
      await tester.tap(
        find.byKey(const ValueKey<String>('mcp-disable-remote_pg')),
      );
      await tester.pumpAndSettle();
      final sshSnapshot = graph.client
          .mcpCatalog(const SshMcpScope(sshAlias: 'gpu-box'))
          .state
          .value!;
      final disabledEntry = sshSnapshot.entries.firstWhere(
        (entry) => entry.id == 'remote_pg',
      );
      expect(
        disabledEntry.effectiveSource,
        McpEffectiveSource.sshDisabledTombstone,
      );

      // Delete SSH tombstone document.
      await tester.tap(
        find.byKey(const ValueKey<String>('mcp-delete-remote_pg')),
      );
      await tester.pumpAndSettle();
      final afterDelete = graph.client
          .mcpCatalog(const SshMcpScope(sshAlias: 'gpu-box'))
          .state
          .value!;
      expect(
        afterDelete.entries.any((entry) => entry.id == 'remote_pg'),
        isFalse,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      final report = await pumpClientFuture(
        tester,
        graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
        'mcp settings teardown',
      );
      expect(report.complete, isTrue);
    },
  );

  testWidgets(
    'started items follow product baselines and events while open without rebuilding chrome',
    (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final transport = _RecordingMcpReconnectTransport();
      final graph = AppGraph(
        statisticsFeed: const TestStatisticsFeedPort(),
        transport: transport,
        clientId: 'thread-mcp-status-ui',
      );
      final container = ProviderContainer(
        overrides: [appGraphProvider.overrideWithValue(graph)],
      );
      transport.mcpSnapshot = const ThreadMcpStateSnapshot(
        threadId: 'thread-main',
        scope: SshMcpScope(sshAlias: 'gpu-box'),
        generation: 3,
        servers: [
          ThreadMcpServerState(
            id: 'postgres_prod',
            effectiveSource: McpEffectiveSource.sshOverrideServer,
            executionLocation: SshRemoteMcpExecutionLocation(
              sshAlias: 'gpu-box',
            ),
            transport: 'stdio',
            endpointSummary: 'uvx mcp-server-postgres',
            lifecycle: ThreadMcpLifecycleKind.available,
            toolCount: 4,
          ),
          ThreadMcpServerState(
            id: 'dcgm_metrics',
            effectiveSource: McpEffectiveSource.sshOverrideServer,
            executionLocation: SshRemoteStreamableHttpMcpExecutionLocation(
              sshAlias: 'gpu-box',
            ),
            transport: 'streamableHttp',
            endpointSummary: 'http://127.0.0.1:9400/mcp',
            lifecycle: ThreadMcpLifecycleKind.unavailable,
            message: 'connection refused on 127.0.0.1:9400',
          ),
        ],
      );
      await pumpClientFuture(
        tester,
        graph.client.bootstrap(),
        'thread mcp bootstrap',
      );
      transport.setThreadLspSnapshot(
        ThreadLspStateSnapshot(
          threadId: 'thread-other',
          revision: 1,
          bindingId: 'binding-other',
          servers: [
            _lspServer(
              'dart',
              const LspUnavailableState(
                checkedAt: 1,
                code: 'other-thread',
                message: 'other thread only',
                retryable: true,
              ),
            ),
          ],
        ),
      );
      final otherLspLease = graph.client.channels.acquireThreadLsp(
        'thread-other',
      );
      await tester.pumpAndSettle();
      expect(
        graph.client
            .existingThreadLsp('thread-other')
            ?.state
            .value
            ?.servers
            .single
            .state,
        isA<LspUnavailableState>(),
      );
      expect(
        (await graph.client.directoryCommands.readThreadLspState(
          'thread-unknown',
        )).servers,
        isEmpty,
        reason: 'unknown demo threads must not borrow the global LSP list',
      );
      await pumpClientFuture(
        tester,
        (graph..setConversationPageVisible(true)).client.directoryCommands
            .selectThread('thread-main'),
        'select thread and attach original MCP owner',
      );
      await pumpClientUntil(
        tester,
        () =>
            graph.client.conversations
                .existingSession('thread-main')
                ?.state
                .hasSnapshot ==
            true,
        'status session baseline',
      );
      transport.seedConversationState(
        'thread-main',
        ThreadRuntimeUpdate(
          runtime: graph.client.conversations
              .existingSession('thread-main')!
              .state
              .runtime!
              .copyWith(
                activeSkills: const ['skill-a'],
                activeMcpServers: const ['stale-active-id'],
                activeLspServers: const [],
              ),
          todo: null,
          modelRoute: null,
        ),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: pureStudioTheme(),
            locale: const Locale('zh'),
            localizationsDelegates: [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 320,
                  child: ThreadStatusConnector(threadId: 'thread-main'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final chrome = tester.widget<ThreadStatusBar>(
        find.byType(ThreadStatusBar),
      );
      expect(
        find.descendant(
          of: find.byType(ThreadStatusBar),
          matching: find.byType(Text),
        ),
        findsNothing,
      );
      await tester.tap(find.byKey(StudioDriverKeys.statusStartedItems));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      print('DIAG initial popover closed');
      final mainBaselinesBeforeReopen = transport.threadLspMainBaselineCount;
      transport.setThreadLspSnapshot(
        ThreadLspStateSnapshot(
          threadId: 'thread-main',
          revision: 2,
          bindingId: 'binding-main',
          servers: transport.threadLspSnapshot.servers,
        ),
      );
      expect(
        find.byKey(StudioDriverKeys.mcpServerRow('postgres_prod')),
        findsNothing,
      );
      tester
          .widget<IconButton>(find.byKey(StudioDriverKeys.statusStartedItems))
          .focusNode!
          .requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      print(
        'DIAG first reopen baseline count ${transport.threadLspMainBaselineCount}',
      );
      await pumpClientUntil(
        tester,
        () =>
            transport.threadLspMainBaselineCount > mainBaselinesBeforeReopen &&
            graph.client
                    .existingThreadLsp('thread-main')
                    ?.state
                    .value
                    ?.revision ==
                2 &&
            container
                .read(startedItemsViewModelProvider('thread-main'))
                .requireValue
                .lsp
                .any((server) => server.id == 'dart'),
        'new thread LSP baseline accepted after popover reopen',
      );
      print('DIAG first reopen accepted');

      expect(
        find.byKey(StudioDriverKeys.mcpServerRow('postgres_prod')),
        findsOneWidget,
      );
      expect(
        find.byKey(StudioDriverKeys.mcpServerRow('dcgm_metrics')),
        findsOneWidget,
      );
      expect(find.text('skill-a'), findsOneWidget);
      expect(find.textContaining('4 tools'), findsNothing);
      expect(
        find.textContaining('connection refused on 127.0.0.1:9400'),
        findsNothing,
      );
      expect(
        find.byTooltip('connection refused on 127.0.0.1:9400'),
        findsOneWidget,
      );
      expect(find.byTooltip('other thread only'), findsNothing);
      expect(
        find.byKey(StudioDriverKeys.statusLspServer('dart')),
        findsOneWidget,
      );
      expect(
        find.byKey(StudioDriverKeys.statusLspServer('rust')),
        findsOneWidget,
      );
      expect(find.text('索引中 12%'), findsOneWidget);
      expect(find.text('就绪'), findsNWidgets(2));
      expect(find.text('/secret/dart.toml'), findsNothing);

      transport.emitThreadLsp(
        ThreadLspStateSnapshot(
          threadId: 'thread-main',
          revision: 3,
          bindingId: 'binding-main',
          servers: [
            _lspServer(
              'dart',
              const LspAvailableState(
                checkedAt: 1,
                diagnosticCount: 0,
                activity: LspIndexingActivity(percentage: 78),
              ),
            ),
            _lspServer(
              'python',
              const LspCheckingState(message: 'initialize handshake'),
            ),
            _lspServer(
              'off',
              const LspDisabledState(message: 'disabled by config'),
            ),
            _lspServer(
              'busy',
              const LspAvailableState(
                checkedAt: 1,
                diagnosticCount: 0,
                activity: LspBusyActivity(title: 'analyzing files'),
              ),
            ),
            _lspServer(
              'bad',
              const LspUnavailableState(
                checkedAt: 1,
                code: 'launch',
                message: 'compiler executable not found',
                retryable: true,
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('索引中 78%'), findsOneWidget);
      expect(
        find.byKey(StudioDriverKeys.statusLspServer('rust')),
        findsNothing,
      );
      expect(
        find.byKey(StudioDriverKeys.statusLspServer('python')),
        findsOneWidget,
      );
      expect(find.text('初始化中'), findsOneWidget);
      expect(find.text('已禁用'), findsOneWidget);
      expect(find.byTooltip('analyzing files'), findsOneWidget);
      expect(find.byTooltip('compiler executable not found'), findsOneWidget);
      for (final id in ['dart', 'python', 'off', 'busy', 'bad']) {
        final row = find.byKey(StudioDriverKeys.statusLspServer(id));
        expect(tester.getSize(row).height, 32);
        for (final text in tester.widgetList<Text>(
          find.descendant(of: row, matching: find.byType(Text)),
        )) {
          expect(
            text.maxLines,
            1,
            reason: 'service rows must remain single-line',
          );
        }
      }
      expect(find.byKey(StudioDriverKeys.lspResetServer('off')), findsNothing);
      expect(
        tester.widget<ThreadStatusBar>(find.byType(ThreadStatusBar)),
        same(chrome),
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'narrow menu and footer must not overflow',
      );

      // A failed command remains visible and never erases canonical members.
      transport.reconnectGate = Completer<ThreadMcpStateSnapshot>();
      await tester.tap(
        find.byKey(StudioDriverKeys.mcpResetServer('dcgm_metrics')),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.descendant(
                of: find.byKey(StudioDriverKeys.mcpResetServer('dcgm_metrics')),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNull,
      );
      // Dismissal and a new product frame must not cancel or duplicate an
      // admitted reconnect; reopening still reflects the same pending command.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      print('DIAG pending MCP popover closed');
      final mainBaselinesBeforePendingReopen =
          transport.threadLspMainBaselineCount;
      transport.emitMcp(transport.mcpSnapshot);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(StudioDriverKeys.statusStartedItems));
      await tester.pump();
      print(
        'DIAG second reopen baseline wait start ${transport.threadLspMainBaselineCount}',
      );
      await pumpClientUntil(
        tester,
        () =>
            transport.threadLspMainBaselineCount >
            mainBaselinesBeforePendingReopen,
        'thread LSP observation re-established after pending MCP reopen',
      );
      print('DIAG second reopen baseline accepted');
      print('DIAG before pending MCP button check');
      expect(
        tester
            .widget<IconButton>(
              find.descendant(
                of: find.byKey(StudioDriverKeys.mcpResetServer('dcgm_metrics')),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNull,
      );
      print('DIAG before complete MCP gate');
      expect(transport.reconnectCalls, hasLength(1));
      transport.reconnectGate!.completeError(StateError('reconnect rejected'));
      await tester.pumpAndSettle();
      print('DIAG after MCP gate settled');
      expect(
        container
            .read(startedItemsViewModelProvider('thread-main'))
            .requireValue
            .errors['mcp:dcgm_metrics'],
        contains('reconnect rejected'),
      );
      expect(
        find.byTooltip('失败: Bad state: reconnect rejected'),
        findsOneWidget,
      );
      expect(find.textContaining('reconnect rejected'), findsNothing);
      expect(
        find.byKey(StudioDriverKeys.mcpServerRow('dcgm_metrics')),
        findsOneWidget,
      );
      transport.reconnectGate = null;

      // Reconnect a single MCP server on this Thread.
      await tester.tap(
        find.byKey(StudioDriverKeys.mcpResetServer('dcgm_metrics')),
      );
      await tester.pumpAndSettle();
      print('DIAG after second MCP reset');
      expect(transport.reconnectCalls, [
        (threadId: 'thread-main', serverId: 'dcgm_metrics'),
        (threadId: 'thread-main', serverId: 'dcgm_metrics'),
      ]);

      // Reconnect all MCP servers on this Thread.
      await tester.tap(find.byKey(StudioDriverKeys.mcpResetAll));
      await tester.pumpAndSettle();
      print('DIAG after MCP reset all');
      expect(transport.reconnectCalls, [
        (threadId: 'thread-main', serverId: 'dcgm_metrics'),
        (threadId: 'thread-main', serverId: 'dcgm_metrics'),
        (threadId: 'thread-main', serverId: null),
      ]);
      expect(
        container
            .read(startedItemsViewModelProvider('thread-main'))
            .requireValue
            .errors,
        isEmpty,
      );

      transport.lspResetGate = Completer<ThreadLspStateSnapshot>();
      await tester.tap(find.byKey(StudioDriverKeys.lspResetServer('dart')));
      await tester.pump();
      print('DIAG after LSP reset admitted');
      transport.emitThreadLsp(
        ThreadLspStateSnapshot(
          threadId: 'thread-main',
          revision: transport.threadLspSnapshot.revision + 1,
          bindingId: 'binding-replaced',
          servers: transport.threadLspSnapshot.servers,
        ),
      );
      await tester.pumpAndSettle();
      transport.lspResetGate!.completeError(
        StateError('late result from retired binding'),
      );
      await tester.pumpAndSettle();
      print('DIAG after late LSP result');
      expect(
        container
            .read(startedItemsViewModelProvider('thread-main'))
            .requireValue
            .errors['lsp:dart'],
        isNull,
      );
      expect(
        find.byTooltip('失败: Bad state: late result from retired binding'),
        findsNothing,
      );
      transport.lspResetGate = null;

      print('DIAG before rejected LSP reset');
      transport.lspResetGate = Completer<ThreadLspStateSnapshot>();
      await tester.tap(find.byKey(StudioDriverKeys.lspResetServer('dart')));
      await tester.pump();
      print('DIAG rejected LSP reset pending');
      expect(
        container
            .read(startedItemsViewModelProvider('thread-main'))
            .requireValue
            .pending,
        contains('lsp:dart'),
      );
      expect(
        find.descendant(
          of: find.byKey(StudioDriverKeys.statusLspServer('dart')),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<IconButton>(
              find.descendant(
                of: find.byKey(StudioDriverKeys.lspResetServer('dart')),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNull,
      );
      transport.lspResetGate!.completeError(
        StateError('LSP reconnect rejected'),
      );
      await tester.pumpAndSettle();
      print('DIAG rejected LSP reset settled');
      expect(
        container
            .read(startedItemsViewModelProvider('thread-main'))
            .requireValue
            .errors['lsp:dart'],
        contains('LSP reconnect rejected'),
      );
      expect(
        tester
            .widget<IconButton>(
              find.descendant(
                of: find.byKey(StudioDriverKeys.lspResetServer('dart')),
                matching: find.byType(IconButton),
              ),
            )
            .tooltip,
        contains('LSP reconnect rejected'),
      );
      expect(
        find.byKey(StudioDriverKeys.statusLspServer('dart')),
        findsOneWidget,
      );
      transport.lspResetGate = null;
      await tester.tap(find.byKey(StudioDriverKeys.lspResetServer('dart')));
      await tester.pumpAndSettle();
      expect(transport.lspResetCalls, ['dart', 'dart', 'dart']);
      expect(transport.lspResetRequests, [
        (threadId: 'thread-main', bindingId: 'binding-main', serverId: 'dart'),
        (
          threadId: 'thread-main',
          bindingId: 'binding-replaced',
          serverId: 'dart',
        ),
        (
          threadId: 'thread-main',
          bindingId: 'binding-replaced',
          serverId: 'dart',
        ),
      ]);
      expect(
        container
            .read(startedItemsViewModelProvider('thread-main'))
            .requireValue
            .errors,
        isEmpty,
      );

      // A real, empty canonical MCP update must not revive old active IDs.
      transport.emitMcp(
        const ThreadMcpStateSnapshot(
          threadId: 'thread-main',
          scope: SshMcpScope(sshAlias: 'gpu-box'),
          generation: 99,
          servers: [],
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(StudioDriverKeys.mcpServerRow('postgres_prod')),
        findsNothing,
      );
      expect(find.text('stale-active-id'), findsNothing);
      expect(find.text('没有 MCP 服务器'), findsOneWidget);

      transport.emitThreadLsp(
        ThreadLspStateSnapshot(
          threadId: 'thread-main',
          revision: 99,
          bindingId: 'binding-main',
          servers: [
            _lspServer(
              'broken',
              const LspUnavailableState(
                checkedAt: 1,
                code: 'config',
                message: 'invalid server configuration',
                retryable: true,
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('invalid server configuration'), findsOneWidget);
      expect(
        find.text('没有语言服务器'),
        findsNothing,
        reason: 'failure is not a healthy empty list',
      );
      expect(
        tester.widget<ThreadStatusBar>(find.byType(ThreadStatusBar)),
        same(chrome),
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await otherLspLease.release();
      container.dispose();
      final report = await pumpClientFuture(
        tester,
        graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
        'thread mcp teardown',
      );
      expect(report.complete, isTrue);
    },
  );
}

final class _RecordingMcpReconnectTransport extends DemoStudioTransport {
  _RecordingMcpReconnectTransport() : super(lspActivityLoop: false);

  final List<({String threadId, String? serverId})> reconnectCalls = [];
  Completer<ThreadMcpStateSnapshot>? reconnectGate;
  final lspResetCalls = <String>[];
  final lspResetRequests =
      <({String threadId, String bindingId, String serverId})>[];
  Completer<ThreadLspStateSnapshot>? lspResetGate;
  ThreadMcpStateSnapshot mcpSnapshot = const ThreadMcpStateSnapshot(
    threadId: 'thread-main',
    scope: HostMcpScope(),
  );
  ThreadLspStateSnapshot threadLspSnapshot = ThreadLspStateSnapshot(
    threadId: 'thread-main',
    revision: 1,
    bindingId: 'binding-main',
    servers: [
      _lspServer(
        'dart',
        const LspAvailableState(
          checkedAt: 1,
          diagnosticCount: 0,
          activity: LspIndexingActivity(percentage: 12),
        ),
      ),
      _lspServer(
        'rust',
        const LspAvailableState(
          checkedAt: 1,
          diagnosticCount: 0,
          activity: LspIdleActivity(),
        ),
      ),
    ],
  );
  final Map<String, ThreadLspStateSnapshot> _threadLspSnapshots = {};
  final _topics = <ProductTopic, StreamController<ProductTopicFrame>>{};
  int _sequence = 0;
  int threadLspMainBaselineCount = 0;

  @override
  Stream<ProductTopicFrame> subscribeProductTopic(ProductTopic topic) {
    if (topic is! ThreadLspTopic && topic is! ThreadMcpTopic) {
      return super.subscribeProductTopic(topic);
    }
    late final StreamController<ProductTopicFrame> controller;
    controller = StreamController<ProductTopicFrame>(
      onListen: () {
        if (topic is ThreadLspTopic && topic.threadId == 'thread-main') {
          threadLspMainBaselineCount++;
        }
        final baseline = ProductTopicBaselineFrame(
          topic: topic,
          revision: topic is ThreadLspTopic
              ? _threadLspSnapshot(topic.threadId).revision
              : mcpSnapshot.generation,
          state: topic is ThreadLspTopic
              ? ThreadLspBaseline(_threadLspSnapshot(topic.threadId))
              : ThreadMcpBaseline(mcpSnapshot),
        );
        controller.add(baseline);
      },
      onCancel: () {
        if (identical(_topics[topic], controller)) {
          _topics.remove(topic);
        }
      },
    );
    _topics[topic] = controller;
    return controller.stream;
  }

  void emitThreadLsp(ThreadLspStateSnapshot snapshot) {
    setThreadLspSnapshot(snapshot);
    _emit(
      ThreadLspTopic(threadId: snapshot.threadId),
      ThreadLspStateChangedPayload(snapshot),
    );
  }

  void setThreadLspSnapshot(ThreadLspStateSnapshot snapshot) {
    _threadLspSnapshots[snapshot.threadId] = snapshot;
    if (snapshot.threadId == 'thread-main') threadLspSnapshot = snapshot;
  }

  ThreadLspStateSnapshot _threadLspSnapshot(String threadId) =>
      _threadLspSnapshots[threadId] ??
      (threadId == 'thread-main'
          ? threadLspSnapshot
          : ThreadLspStateSnapshot(
              threadId: threadId,
              revision: 1,
              bindingId: null,
            ));

  void emitMcp(ThreadMcpStateSnapshot snapshot) {
    mcpSnapshot = snapshot;
    _emit(
      ThreadMcpTopic(threadId: snapshot.threadId),
      ThreadMcpStateChangedPayload(snapshot),
    );
  }

  void _emit(ProductTopic topic, ProductTopicEventPayload payload) {
    _topics[topic]!.add(
      ProductTopicDataFrame(
        topic: topic,
        event: ProductTopicEventEnvelope(
          eventId: 'status-event-${++_sequence}',
          sequence: BigInt.from(_sequence),
          createdAt: DateTime.utc(2026, 11, 3),
          payload: payload,
        ),
      ),
    );
  }

  @override
  Future<ThreadMcpStateSnapshot> reconnectThreadMcp({
    required String threadId,
    String? serverId,
  }) async {
    reconnectCalls.add((threadId: threadId, serverId: serverId));
    return reconnectGate == null ? mcpSnapshot : reconnectGate!.future;
  }

  @override
  Future<ThreadLspStateSnapshot> readThreadLspState(String threadId) async =>
      _threadLspSnapshot(threadId);

  @override
  Future<ThreadLspStateSnapshot> resetThreadLspServer({
    required String threadId,
    required String bindingId,
    required String serverId,
  }) async {
    lspResetCalls.add(serverId);
    lspResetRequests.add((
      threadId: threadId,
      bindingId: bindingId,
      serverId: serverId,
    ));
    final gate = lspResetGate;
    if (gate != null) return gate.future;
    final snapshot = ThreadLspStateSnapshot(
      threadId: threadId,
      revision: _threadLspSnapshot(threadId).revision + 1,
      bindingId: bindingId,
      servers: _threadLspSnapshot(threadId).servers,
    );
    setThreadLspSnapshot(snapshot);
    return snapshot;
  }
}

LspServerStateView _lspServer(String id, LspServerState state) =>
    LspServerStateView(
      id: id,
      displayName: id,
      configurationPath: '/secret/$id.toml',
      phase: state is LspCheckingState ? 'initializing' : 'ready',
      state: state,
    );
