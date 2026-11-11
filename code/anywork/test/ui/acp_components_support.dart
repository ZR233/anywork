import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/presentation/providers/client_provider.dart';
import 'package:anywork_client/acp_sessions.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../../anywork_client/test/support/acp_business_port.dart';
import '../../../anywork_client/test/support/timeline_transport.dart'
    show TestConversationTransport;
import '../support/pump_client_future.dart';

const acpRemoteFixture = AcpRemoteSessionId('remote');
const acpBooleanFixture = AcpSessionConfigOptionView(
  id: AcpConfigId('server/boolean'),
  name: '保留引用',
  description: '保留服务器提供的来源',
  category: AcpConfigCategoryView.other('vendor-specific'),
  kind: AcpBooleanConfigView(currentValue: false),
);

Widget acpTestApp(Widget child) => MaterialApp(
  theme: pureStudioTheme(),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

/// Only controls source frames and records calls. All reduction is production.
final class AcpComponentHarness {
  AcpComponentHarness(this.client, this.port, this.source, this.owner);
  final AnyworkClient client;
  final ControlledAcpBusinessPort port;
  final ControlledAcpObservation source;
  final AcpConversationSession owner;

  static Future<AcpComponentHarness> create({
    List<AcpSessionConfigOptionView>? options,
    AcpSessionModeStateView? modes,
    List<AcpSessionUpdateView> updates = const [],
    bool resume = false,
  }) async {
    final target = AcpSessionTargetView(
      sessionId: 'session',
      agentId: 'agent',
      threadId: 'thread',
      instance: BigInt.from(19),
    );
    final source = ControlledAcpObservation([
      AcpAcceptedFrameView(target: target, hasObservation: true),
      AcpEventFrameView(
        AcpReadyEventView(
          AcpNewSessionResponseView(
            sessionId: acpRemoteFixture,
            configOptions: options,
            modes: modes,
          ),
        ),
      ),
      for (final update in updates)
        AcpEventFrameView(
          AcpUpdateEventView(
            AcpSessionNotificationView(
              sessionId: acpRemoteFixture,
              update: update,
            ),
          ),
        ),
      const AcpSettledFrameView(AcpSuccessView<void>(null)),
    ]);
    final port = ControlledAcpBusinessPort()..sources.add(source);
    final transport = TestConversationTransport()
      ..seedThread(
        SessionDirectoryRow(
          sessionId: 'session',
          agentId: 'agent',
          threadId: 'thread',
          workspaceId: 'workspace',
          title: 'ACP 测试会话',
          mode: null,
          delegationMode: DelegationMode.profile,
          delegationPreference: DelegationPreference.balanced,
          workspacePath: '/project',
          role: 'root',
          backend: const AcpAgentBackendView(
            reference: AcpSessionReferenceView(
              accountId: 'account',
              acpSessionId: 'remote',
              cwd: '/project',
            ),
          ),
          updatedAt: DateTime.utc(2025),
        ),
      );
    final client = AnyworkClient(
      transport: transport,
      clientId: 'acp-components',
      acpBusinessPort: port,
    );
    client.project.applyProjectDirectory(
      ProjectDirectoryState(
        revision: 1,
        values: const [
          StudioProject(id: 'workspace', name: '本地项目', path: '/project'),
        ],
      ),
    );
    final owner = await client.acpSessions.openConversation(
      OpenAcpSessionRequestView(
        accountId: 'account',
        expectedConnectionRevision: BigInt.one,
        workspaceId: 'workspace',
        threadId: 'thread',
        intent: resume
            ? const AcpResumeIntentView(acpRemoteFixture)
            : const AcpLoadIntentView(acpRemoteFixture),
      ),
    );
    return AcpComponentHarness(client, port, source, owner);
  }

  Widget scope(Widget child) => ProviderScope(
    overrides: [anyworkClientProvider.overrideWithValue(client)],
    child: acpTestApp(child),
  );

  void emit(AcpSessionEventView event) {
    final frame = AcpEventFrameView(event);
    final pending = source.read;
    if (pending != null && !pending.isCompleted) {
      pending.complete(frame);
    } else {
      source.frames.add(frame);
    }
  }

  void update(AcpSessionUpdateView update) => emit(
    AcpUpdateEventView(
      AcpSessionNotificationView(sessionId: acpRemoteFixture, update: update),
    ),
  );

  Future<void> close(WidgetTester tester) async {
    final report = await pumpClientFuture(
      tester,
      client.close(),
      'close ACP component Client',
    );
    expect(report.complete, isTrue, reason: '${report.unresolved}');
  }
}
