import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/domain/models/studio_models.dart';
import 'package:anywork/src/features/settings/settings_mcp_tab.dart';
import 'package:anywork/src/features/settings/settings_scope.dart';
import 'package:anywork/src/features/status/thread_status_bar.dart';
import 'package:anywork/src/infrastructure/demo/studio_demo_api.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
            localizationsDelegates: AppLocalizations.localizationsDelegates,
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
    'ThreadStatusBar displays Thread-exclusive MCP lifecycle states and dispatches reconnect commands',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
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
      await pumpClientFuture(
        tester,
        graph.client.bootstrap(),
        'thread mcp bootstrap',
      );
      graph.client
          .threadMcp('thread-main')
          .apply(
            const ThreadMcpStateSnapshot(
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
                  executionLocation:
                      SshRemoteStreamableHttpMcpExecutionLocation(
                        sshAlias: 'gpu-box',
                      ),
                  transport: 'streamableHttp',
                  endpointSummary: 'http://127.0.0.1:9400/mcp',
                  lifecycle: ThreadMcpLifecycleKind.unavailable,
                  message: 'connection refused on 127.0.0.1:9400',
                ),
              ],
            ),
          );

      final row = SessionDirectoryRow(
        sessionId: 'session-main',
        agentId: 'agent-main',
        threadId: 'thread-main',
        workspaceId: 'proj-main',
        title: 'Main Thread',
        mode: ThreadModeId.simple,
        delegationMode: DelegationMode.profile,
        delegationPreference: DelegationPreference.balanced,
        updatedAt: DateTime.utc(2026, 11, 3),
        workspacePath: '/home/ubuntu/pure-lang',
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: pureStudioTheme(),
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 1000,
                  child: ThreadStatusBar(
                    threadId: 'thread-main',
                    row: row,
                    accounts: const [],
                    lspServers: const [],
                    activeMcpServers: const ['postgres_prod', 'dcgm_metrics'],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open the capabilities detail popover via mouse hover.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byIcon(Icons.tune_outlined)));
      await tester.pump(const Duration(milliseconds: 121));
      await tester.pumpAndSettle();

      expect(
        find.byKey(StudioDriverKeys.mcpServerRow('postgres_prod')),
        findsOneWidget,
      );
      expect(
        find.byKey(StudioDriverKeys.mcpServerRow('dcgm_metrics')),
        findsOneWidget,
      );
      expect(find.textContaining('4 tools'), findsOneWidget);
      expect(
        find.textContaining('connection refused on 127.0.0.1:9400'),
        findsOneWidget,
      );

      // Reconnect a single MCP server on this Thread.
      await tester.tap(
        find.byKey(StudioDriverKeys.mcpResetServer('dcgm_metrics')),
      );
      await tester.pumpAndSettle();
      expect(transport.reconnectCalls, [
        (threadId: 'thread-main', serverId: 'dcgm_metrics'),
      ]);

      // Reconnect all MCP servers on this Thread.
      await tester.tap(find.byKey(StudioDriverKeys.mcpResetAll));
      await tester.pumpAndSettle();
      expect(transport.reconnectCalls, [
        (threadId: 'thread-main', serverId: 'dcgm_metrics'),
        (threadId: 'thread-main', serverId: null),
      ]);

      await tester.pumpWidget(const SizedBox.shrink());
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

  @override
  Future<ThreadMcpStateSnapshot> reconnectThreadMcp({
    required String threadId,
    String? serverId,
  }) async {
    reconnectCalls.add((threadId: threadId, serverId: serverId));
    return super.reconnectThreadMcp(threadId: threadId, serverId: serverId);
  }
}
