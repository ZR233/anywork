import 'package:anywork/src/features/conversation/acp/connectors/acp_workspace_connector.dart';
import 'package:anywork/src/features/conversation/acp/view_models/acp_session_view_model.dart';
import 'package:anywork/src/features/conversation/acp/views/acp_conversation_composer_view.dart';
import 'package:anywork/src/presentation/providers/client_provider.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/acp_sessions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'acp_components_support.dart';

void main() {
  testWidgets('ACP child is readable without offering a direct prompt', (
    tester,
  ) async {
    final harness = await AcpComponentHarness.create(child: true);
    addTearDown(() => harness.close(tester));
    await tester.pumpWidget(
      harness.scope(const AcpWorkspaceConnector(threadId: 'thread')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(StudioDriverKeys.agentReadOnlyPanel), findsOneWidget);
    expect(find.text('子智能体会话（只读）'), findsOneWidget);
    expect(find.byType(AcpConversationComposerView), findsNothing);
    expect(harness.port.calls.where((call) => call.$1 == 'prompt'), isEmpty);
    expect(harness.port.calls.where((call) => call.$1 == 'open'), hasLength(1));

    final permissionId = AcpPermissionIdView(
      instance: BigInt.one,
      sequence: BigInt.one,
    );
    harness.emit(
      AcpPermissionEventView(
        id: permissionId,
        request: AcpPermissionRequestView(
          sessionId: acpRemoteFixture,
          toolCall: AcpToolCallUpdateView(
            toolCallId: const AcpToolCallId('child-tool'),
            fields: AcpToolCallUpdateFieldsView(title: '读取文件'),
          ),
          options: const [
            AcpPermissionOptionView(
              optionId: AcpPermissionOptionId('allow-once'),
              name: '仅此次允许',
              kind: AcpPermissionOptionKindView.allowOnce,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final option = find.text('仅此次允许');
    expect(option, findsOneWidget);
    await tester.ensureVisible(option);
    await tester.tap(option);
    await tester.pumpAndSettle();
    final answer = harness.port.calls.last.$2 as AcpPermissionAnswerRequestView;
    expect(answer.permissionId, permissionId);
    expect(answer.optionId, const AcpPermissionOptionId('allow-once'));
    expect(harness.port.calls.where((call) => call.$1 == 'prompt'), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ACP root retains its existing composer', (tester) async {
    final harness = await AcpComponentHarness.create();
    addTearDown(() => harness.close(tester));
    await tester.pumpWidget(
      harness.scope(const AcpWorkspaceConnector(threadId: 'thread')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(StudioDriverKeys.agentReadOnlyPanel), findsNothing);
    expect(find.byType(AcpConversationComposerView), findsOneWidget);
    expect(harness.port.calls.where((call) => call.$1 == 'open'), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('unknown member identity never exposes a root composer', (
    tester,
  ) async {
    final harness = await AcpComponentHarness.create();
    addTearDown(() => harness.close(tester));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          anyworkClientProvider.overrideWithValue(harness.client),
          acpChildReadOnlyViewModelProvider('thread')
              .overrideWith((ref) => null),
        ],
        child: acpTestApp(const AcpWorkspaceConnector(threadId: 'thread')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AcpConversationComposerView), findsNothing);
    expect(find.byKey(StudioDriverKeys.agentReadOnlyPanel), findsNothing);
    expect(harness.port.calls.where((call) => call.$1 == 'prompt'), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
