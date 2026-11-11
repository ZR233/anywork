import 'dart:async';

import 'package:anywork/src/features/conversation/acp/acp_views.dart';
import 'package:anywork/src/features/conversation/acp/connectors/acp_composer_connector.dart';
import 'package:anywork/src/features/conversation/acp/connectors/acp_permission_connector.dart';
import 'package:anywork/src/features/conversation/acp/connectors/acp_timeline_connector.dart';
import 'package:anywork/src/features/conversation/acp/connectors/acp_workspace_connector.dart';
import 'package:anywork/src/features/conversation/acp/view_models/acp_configuration_view_model.dart';
import 'package:anywork/src/features/conversation/acp/view_models/acp_plan_card_view_model.dart';
import 'package:anywork_client/acp_sessions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'acp_components_support.dart';

IconButton _sendButtonWidget(WidgetTester tester, String threadId) {
  final primary = find.byKey(
    ValueKey(AcpViewKeyValues.composerPrimaryAction(threadId)),
  );
  return tester.widget<IconButton>(
    find.descendant(of: primary, matching: find.byType(IconButton)),
  );
}

void main() {
  testWidgets('仅音频能力不启用图片和文件附件入口', (tester) async {
    final harness = await AcpComponentHarness.create();
    addTearDown(() => harness.close(tester));
    await tester.pumpWidget(
      harness.scope(const AcpComposerConnector(threadId: 'thread')),
    );
    harness.emit(
      const AcpInitializedEventView(
        AcpAgentCapabilitiesView(
          image: false,
          audio: true,
          embeddedContext: false,
          loadSession: true,
          listSessions: false,
          resumeSession: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.attach_file),
          )
          .onPressed,
      isNull,
    );
    expect(harness.port.calls.where((call) => call.$1 == 'prompt'), isEmpty);
  });

  testWidgets('流式内容局部刷新，Plan/配置选择不随文本 chunk 通知', (tester) async {
    final harness = await AcpComponentHarness.create(
      options: [acpBooleanFixture],
      updates: [
        AcpPlanView(
          entries: const [
            AcpPlanEntryView(
              content: '读取项目',
              priority: AcpPlanPriorityView.high,
              status: AcpPlanStatusView.inProgress,
            ),
          ],
        ),
        const AcpAgentMessageChunkView(
          AcpContentChunkView(content: AcpTextContentView(text: '第一段')),
        ),
      ],
    );
    addTearDown(() => harness.close(tester));
    await tester.pumpWidget(
      harness.scope(const AcpTimelineConnector(threadId: 'thread')),
    );
    await tester.pumpAndSettle();
    expect(find.text('第一段'), findsOneWidget);
    expect(find.text('读取项目'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AcpTimelineConnector)),
    );
    var planChanges = 0;
    var configChanges = 0;
    final planWatch = container.listen(
      acpPlanCardViewModelProvider('thread'),
      (_, _) => planChanges++,
    );
    final configWatch = container.listen(
      acpConfigurationViewModelProvider('thread'),
      (_, _) => configChanges++,
    );
    addTearDown(planWatch.close);
    addTearDown(configWatch.close);
    harness.update(
      const AcpAgentMessageChunkView(
        AcpContentChunkView(content: AcpTextContentView(text: '后续')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('第一段后续'), findsOneWidget);
    expect(planChanges, 0);
    expect(configChanges, 0);
    expect(harness.port.calls.map((call) => call.$1), ['open']);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(
      harness.source.closeSignals,
      0,
      reason: 'Unmount cancels display watches, not the Client owner',
    );
  });

  testWidgets('权限显示全部真实选项，提交原 permission 和 optionId', (tester) async {
    final harness = await AcpComponentHarness.create();
    addTearDown(() => harness.close(tester));
    final permission = AcpPermissionIdView(
      instance: BigInt.from(3),
      sequence: BigInt.from(8),
    );
    harness.emit(
      AcpPermissionEventView(
        id: permission,
        request: AcpPermissionRequestView(
          sessionId: acpRemoteFixture,
          toolCall: AcpToolCallUpdateView(
            toolCallId: const AcpToolCallId('permission-tool'),
            fields: AcpToolCallUpdateFieldsView(title: '读取文件'),
          ),
          options: const [
            AcpPermissionOptionView(
              optionId: AcpPermissionOptionId('allow/server-once'),
              name: '仅此次允许',
              kind: AcpPermissionOptionKindView.allowOnce,
            ),
            AcpPermissionOptionView(
              optionId: AcpPermissionOptionId('allow/server-always'),
              name: '总是允许',
              kind: AcpPermissionOptionKindView.allowAlways,
            ),
            AcpPermissionOptionView(
              optionId: AcpPermissionOptionId('deny/server-once'),
              name: '仅此次拒绝',
              kind: AcpPermissionOptionKindView.rejectOnce,
            ),
            AcpPermissionOptionView(
              optionId: AcpPermissionOptionId('deny/server-always'),
              name: '总是拒绝',
              kind: AcpPermissionOptionKindView.rejectAlways,
            ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(
      harness.scope(
        const SingleChildScrollView(
          child: AcpPermissionConnector(threadId: 'thread'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final label in ['仅此次允许', '总是允许', '仅此次拒绝', '总是拒绝']) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text('总是拒绝'));
    await tester.pumpAndSettle();
    final answer = harness.port.calls.last.$2 as AcpPermissionAnswerRequestView;
    expect(answer.permissionId, same(permission));
    expect(answer.optionId, const AcpPermissionOptionId('deny/server-always'));
    expect(harness.owner.state.pendingPermissions, isEmpty);
    expect(find.text('总是拒绝'), findsNothing);
  });

  testWidgets('配置在途阻止旧配置发送；消息更新保留输入光标', (tester) async {
    final harness = await AcpComponentHarness.create(
      options: [acpBooleanFixture],
    );
    addTearDown(() => harness.close(tester));
    harness.client.drafts.composer('thread').updateDraft('保留我的草稿');
    await tester.pumpWidget(
      harness.scope(
        const SingleChildScrollView(
          child: AcpComposerConnector(threadId: 'thread', compact: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField));
    field.controller!.selection = const TextSelection.collapsed(offset: 2);
    final configuration = Completer<void>();
    harness.port.configureResult = configuration;
    await tester.tap(
      find.byKey(
        ValueKey(AcpViewKeyValues.configControl(acpBooleanFixture.id.value)),
      ),
    );
    await tester.pump();
    expect(_sendButtonWidget(tester, 'thread').onPressed, isNull);
    expect(find.text('正在应用配置，完成前不能发送消息'), findsOneWidget);
    harness.update(
      const AcpAgentMessageChunkView(
        AcpContentChunkView(content: AcpTextContentView(text: '异步内容')),
      ),
    );
    await tester.pump();
    expect(field.controller!.text, '保留我的草稿');
    expect(field.controller!.selection.baseOffset, 2);
    harness.emit(
      AcpConfiguredEventView(
        AcpConfiguredResponseView(configOptions: [acpBooleanFixture]),
      ),
    );
    configuration.complete();
    await tester.pumpAndSettle();
    expect(_sendButtonWidget(tester, 'thread').onPressed, isNotNull);
    expect(harness.port.calls.any((call) => call.$1 == 'prompt'), isFalse);
  });

  testWidgets('Resume 与观察缺口不宣称历史完整', (tester) async {
    final harness = await AcpComponentHarness.create(resume: true);
    addTearDown(() => harness.close(tester));
    await tester.pumpWidget(
      harness.scope(const AcpWorkspaceConnector(threadId: 'thread')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('不能据此认为历史完整'), findsOneWidget);
    expect(find.text('外部继续'), findsOneWidget);
    harness.emit(const AcpGapEventView(AcpObservationGapView.windowExceeded));
    await tester.pumpAndSettle();
    expect(find.textContaining('观察出现缺口'), findsOneWidget);
    expect(find.textContaining('当前内容可能缺失'), findsOneWidget);
  });

  testWidgets('发送走真实草稿 owner，冻结正文且受理后清空草稿', (tester) async {
    final harness = await AcpComponentHarness.create();
    addTearDown(() => harness.close(tester));
    harness.port.run = AcpRunIdView(
      instance: BigInt.from(5),
      sequence: BigInt.from(2),
    );
    final draft = harness.client.drafts.composer('thread');
    draft.updateDraft('从草稿发送');
    await tester.pumpWidget(
      harness.scope(
        const AcpComposerConnector(threadId: 'thread', compact: true),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey(AcpViewKeyValues.composerPrimaryAction('thread'))),
    );
    await tester.pumpAndSettle();
    final prompts = harness.port.calls.where((call) => call.$1 == 'prompt');
    expect(prompts, hasLength(1));
    final prompt = prompts.single.$2 as AcpPromptRequestView;
    expect(prompt.target, same(harness.owner.state.target));
    expect((prompt.content.single as AcpTextContentView).text, '从草稿发送');
    expect(draft.state.draft, isEmpty);
    expect(draft.state.submissionRevision, greaterThan(0));
    expect(find.text('中断'), findsOneWidget);
  });

  testWidgets('配置失败明确显示并保留草稿，不能按旧配置发送', (tester) async {
    final harness = await AcpComponentHarness.create(
      options: [acpBooleanFixture],
    );
    addTearDown(() => harness.close(tester));
    harness.client.drafts.composer('thread').updateDraft('不能丢失的输入');
    await tester.pumpWidget(
      harness.scope(
        const SingleChildScrollView(
          child: AcpComposerConnector(threadId: 'thread', compact: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    harness.port.commandError = StateError('server rejected config');
    await tester.tap(
      find.byKey(
        ValueKey(AcpViewKeyValues.configControl(acpBooleanFixture.id.value)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('配置失败：'), findsWidgets);
    expect(_sendButtonWidget(tester, 'thread').onPressed, isNull);
    expect(harness.client.drafts.composer('thread').state.draft, '不能丢失的输入');
    expect(harness.port.calls.any((call) => call.$1 == 'prompt'), isFalse);
  });

  testWidgets('ACP 输入不因相同草稿刷新而重置选择和输入法组合', (tester) async {
    Widget input() => acpTestApp(
      AcpConversationComposerView(
        state: const AcpComposerViewState(
          threadId: 'thread',
          draftText: '输入中的草稿',
          canSend: true,
        ),
        onDraftChanged: (_) {},
        onSubmit: () {},
        onInterrupt: () {},
        onPickLocalAttachments: (_) async {},
        onAddRemoteAttachment: (_) async {},
        onRemoveAttachment: (_) {},
      ),
    );
    await tester.pumpWidget(input());
    final controller = tester
        .widget<TextField>(find.byType(TextField))
        .controller!;
    controller.value = const TextEditingValue(
      text: '输入中的草稿',
      selection: TextSelection.collapsed(offset: 3),
      composing: TextRange(start: 1, end: 3),
    );
    await tester.pumpWidget(input());
    expect(controller.selection.baseOffset, 3);
    expect(controller.value.composing, const TextRange(start: 1, end: 3));
  });
}
