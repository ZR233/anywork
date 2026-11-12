import 'dart:async';

import 'package:anywork/src/features/conversation/acp/acp_views.dart';
import 'package:anywork/src/features/conversation/acp/connectors/acp_workspace_connector.dart';
import 'package:anywork/src/features/conversation/acp/view_models/acp_session_view_model.dart';
import 'package:anywork_client/acp_sessions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../../anywork_client/test/support/acp_business_port.dart';
import 'acp_components_support.dart';

// Workspace interaction uses the production Client and widgets. Only external
// ACP frames are controlled; native window integration has its own small test.
void main() {
  WidgetController.hitTestWarningShouldBeFatal = true;

  testWidgets('ACP 工作区配置、权限和后台会话共享原 owner，中断等待完成事件', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    AcpSessionConfigOptionView select({
      required bool grouped,
      bool changed = false,
    }) {
      final values = [
        AcpSelectOptionView(
          value: AcpConfigValueId(grouped ? 'group/raw:1' : 'flat/raw:1'),
          name: grouped ? '标准深度' : '标准质量',
        ),
        AcpSelectOptionView(
          value: AcpConfigValueId(grouped ? 'group/raw:2' : 'flat/raw:2'),
          name: grouped ? '深入分析' : '请求高质量',
        ),
      ];
      return AcpSessionConfigOptionView(
        id: AcpConfigId(grouped ? 'vendor/grouped' : 'vendor/select'),
        name: grouped ? '分析深度' : '回答质量',
        kind: AcpSelectConfigView(
          currentValue: values[changed ? 1 : 0].value,
          options: grouped
              ? AcpGroupedOptionsView([
                  AcpSelectGroupView(
                    group: const AcpConfigGroupId('server/group'),
                    name: '服务端分组',
                    options: values,
                  ),
                ])
              : AcpUngroupedOptionsView(values),
        ),
      );
    }

    List<AcpSessionConfigOptionView> options({bool groupedChanged = false}) => [
      select(grouped: false),
      select(grouped: true, changed: groupedChanged),
      acpBooleanFixture,
    ];

    final harness = await AcpComponentHarness.create(
      options: options(),
      updates: [
        AcpPlanView(
          entries: const [
            AcpPlanEntryView(
              content: '核验服务端动态配置与权限停靠交互',
              priority: AcpPlanPriorityView.high,
              status: AcpPlanStatusView.inProgress,
            ),
            AcpPlanEntryView(
              content: '验证切换线程时后台流式内容持续归约',
              priority: AcpPlanPriorityView.medium,
              status: AcpPlanStatusView.pending,
            ),
          ],
        ),
      ],
    );
    final run = AcpRunIdView(
      instance: BigInt.from(19),
      sequence: BigInt.from(7),
    );
    harness.port.run = run;
    final gates = <Completer<void>>[];
    ControlledAcpObservation? otherSource;
    addTearDown(() async {
      for (final gate in gates) {
        if (!gate.isCompleted) gate.complete();
      }
      final admission = harness.port.promptResult;
      if (admission != null && !admission.isCompleted) {
        admission.complete(run);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await harness.close(tester);
      expect(harness.source.closeSignals, greaterThanOrEqualTo(1));
      expect(harness.source.closes, 1);
      if (otherSource case final source?) {
        expect(source.closeSignals, greaterThanOrEqualTo(1));
        expect(source.closes, 1);
      }
      expect(tester.takeException(), isNull);
      debugPrint(
        'ACP workspace cleanup: Client complete; observations closed; '
        'Flutter production widgets unmounted',
      );
    });

    Future<void> showPage(String threadId) async {
      await tester.pumpWidget(
        harness.scope(
          AcpWorkspaceConnector(key: ValueKey(threadId), threadId: threadId),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    await showPage('thread');
    await tester.enterText(find.byType(TextField), 'ACP 消息');
    await tester.pumpAndSettle();
    final draft = harness.client.drafts.composer('thread');
    expect(draft.state.draft, 'ACP 消息');

    Finder selectAnchorButton(bool grouped) => find.descendant(
      of: find.byKey(
        ValueKey(
          AcpViewKeyValues.configControl(
            grouped ? 'vendor/grouped' : 'vendor/select',
          ),
        ),
      ),
      matching: find.byType(TextButton),
    );
    Finder booleanPill() => find.byKey(
      ValueKey(AcpViewKeyValues.configControl(acpBooleanFixture.id.value)),
    );
    Finder primaryAction() =>
        find.byKey(ValueKey(AcpViewKeyValues.composerPrimaryAction('thread')));
    IconButton sendButton() => tester.widget<IconButton>(
      find.descendant(of: primaryAction(), matching: find.byType(IconButton)),
    );
    Future<void> flushUi() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    Future<void> configure({
      bool? grouped,
      required List<AcpSessionConfigOptionView> canonical,
    }) async {
      final gate = Completer<void>();
      gates.add(gate);
      harness.port.configureResult = gate;
      if (grouped == null) {
        await tester.tap(booleanPill());
      } else {
        await tester.tap(selectAnchorButton(grouped));
        await tester.pumpAndSettle();
        if (grouped) expect(find.text('服务端分组'), findsWidgets);
        await tester.tap(find.text(grouped ? '深入分析' : '请求高质量').last);
      }
      await flushUi();
      expect(harness.owner.state.configPending, isTrue);
      expect(sendButton().onPressed, isNull);
      // Tapping a disabled production button must not reach the port.
      await tester.tap(primaryAction());
      await flushUi();
      expect(harness.port.calls.where((call) => call.$1 == 'prompt'), isEmpty);
      final request = harness.port.calls.last.$2 as AcpConfigureRequestView;
      expect(request.target, same(harness.owner.state.target));
      expect(
        request.configId,
        grouped == null
            ? acpBooleanFixture.id
            : AcpConfigId(grouped ? 'vendor/grouped' : 'vendor/select'),
      );
      if (grouped == null) {
        expect((request.value as AcpBooleanConfigValueView).value, isTrue);
      } else {
        expect(
          (request.value as AcpSelectConfigValueView).value,
          AcpConfigValueId(grouped ? 'group/raw:2' : 'flat/raw:2'),
        );
      }
      gate.complete();
      await flushUi();
      expect(harness.owner.state.configPending, isTrue);
      expect(sendButton().onPressed, isNull);
      harness.emit(
        AcpConfiguredEventView(
          AcpConfiguredResponseView(configOptions: canonical),
        ),
      );
      await tester.pumpAndSettle();
      expect(harness.owner.state.configPending, isFalse);
      expect(sendButton().onPressed, isNotNull);
      expect(draft.state.draft, 'ACP 消息');
    }

    await configure(grouped: false, canonical: options());
    expect(find.textContaining('回答质量 · 标准质量'), findsOneWidget);
    await configure(grouped: true, canonical: options(groupedChanged: true));
    expect(find.textContaining('分析深度 · 深入分析'), findsOneWidget);
    await configure(canonical: options(groupedChanged: true));
    expect(
      tester
          .widget<InkWell>(
            find.descendant(of: booleanPill(), matching: find.byType(InkWell)),
          )
          .onTap,
      isNotNull,
    );
    expect(
      harness.port.calls.where((call) => call.$1 == 'configure'),
      hasLength(3),
    );

    // Keep admission in flight across a second actual tap.
    final admission = Completer<AcpRunIdView>();
    harness.port.promptResult = admission;
    await tester.tap(primaryAction());
    await flushUi();
    expect(sendButton().onPressed, isNull);
    await tester.tap(primaryAction());
    await flushUi();
    final prompts = harness.port.calls.where((call) => call.$1 == 'prompt');
    expect(prompts, hasLength(1));
    final prompt = prompts.single.$2 as AcpPromptRequestView;
    expect(prompt.target, same(harness.owner.state.target));
    expect((prompt.content.single as AcpTextContentView).text, 'ACP 消息');
    admission.complete(run);
    await tester.pumpAndSettle();
    expect(draft.state.draft, isEmpty);
    expect(draft.state.submissionRevision, greaterThan(0));
    expect(harness.owner.state.activeRun, run);

    // Generation and configuration are independent controls.
    final runningConfiguration = Completer<void>();
    gates.add(runningConfiguration);
    harness.port.configureResult = runningConfiguration;
    expect(
      tester
          .widget<InkWell>(
            find.descendant(of: booleanPill(), matching: find.byType(InkWell)),
          )
          .onTap,
      isNotNull,
    );
    await tester.tap(booleanPill());
    await flushUi();
    expect(harness.owner.state.activeRun, run);
    expect(harness.owner.state.sendPending, isFalse);
    expect(harness.owner.state.configPending, isTrue);
    expect(
      tester
          .widget<InkWell>(
            find.descendant(of: booleanPill(), matching: find.byType(InkWell)),
          )
          .onTap,
      isNull,
    );
    expect(
      tester.widget<TextButton>(selectAnchorButton(false)).onPressed,
      isNull,
    );
    final runningRequest =
        harness.port.calls.last.$2 as AcpConfigureRequestView;
    expect(runningRequest.target, same(harness.owner.state.target));
    expect(runningRequest.configId, acpBooleanFixture.id);
    expect((runningRequest.value as AcpBooleanConfigValueView).value, isTrue);
    harness.emit(
      AcpConfiguredEventView(
        AcpConfiguredResponseView(
          configOptions: [
            ...options(groupedChanged: true).take(2),
            AcpSessionConfigOptionView(
              id: acpBooleanFixture.id,
              name: acpBooleanFixture.name,
              description: acpBooleanFixture.description,
              category: acpBooleanFixture.category,
              kind: const AcpBooleanConfigView(currentValue: true),
            ),
          ],
        ),
      ),
    );
    await flushUi();
    expect(harness.owner.state.activeRun, run);
    expect(harness.owner.state.configPending, isTrue);
    runningConfiguration.complete();
    await tester.pumpAndSettle();
    expect(harness.owner.state.activeRun, run);
    expect(harness.owner.state.configPending, isFalse);
    expect(
      tester
          .widget<InkWell>(
            find.descendant(of: booleanPill(), matching: find.byType(InkWell)),
          )
          .onTap,
      isNotNull,
    );
    expect(
      tester.widget<TextButton>(selectAnchorButton(false)).onPressed,
      isNotNull,
    );
    expect(
      tester.widget<TextButton>(selectAnchorButton(true)).onPressed,
      isNotNull,
    );
    expect(prompts, hasLength(1));
    expect(
      harness.port.calls.where((call) => call.$1 == 'configure'),
      hasLength(4),
    );
    debugPrint('ACP running configuration applied; original run active');

    const permissions = [
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
    ];
    for (var index = 0; index < permissions.length; index++) {
      final id = AcpPermissionIdView(
        instance: run.instance,
        sequence: BigInt.from(index + 30),
      );
      final idKey = '${id.instance}:${id.sequence}';
      harness.emit(
        AcpPermissionEventView(
          id: id,
          request: AcpPermissionRequestView(
            sessionId: acpRemoteFixture,
            toolCall: AcpToolCallUpdateView(
              toolCallId: const AcpToolCallId('native/read'),
              fields: AcpToolCallUpdateFieldsView(
                title: '更新 src/features/conversation/acp/acp_views.dart',
                kind: AcpToolKindView.edit,
                locations: const [
                  AcpToolCallLocationView(
                    path: 'src/features/conversation/acp/acp_views.dart',
                    line: 1,
                  ),
                ],
                content: const [
                  AcpToolDiffView(
                    path: 'src/features/conversation/acp/acp_views.dart',
                    oldText: "export 'views/acp_conversation_content.dart';",
                    newText:
                        "export 'state/acp_view_state.dart';\n"
                        "export 'views/acp_conversation_content_view.dart';",
                  ),
                ],
              ),
            ),
            options: permissions,
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final option in permissions) {
        expect(find.text(option.name), findsOneWidget);
      }
      if (index == 0) {}
      final option = permissions[index];
      final button = find.byKey(
        ValueKey(
          AcpViewKeyValues.permissionOption(idKey, option.optionId.value),
        ),
      );
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      final answer =
          harness.port.calls.last.$2 as AcpPermissionAnswerRequestView;
      expect(answer.permissionId, same(id));
      expect(answer.optionId, option.optionId);
      expect(answer.target, same(harness.owner.state.target));
      expect(harness.owner.state.pendingPermissions, isEmpty);
    }
    expect(
      harness.port.calls.where((call) => call.$1 == 'answerPermission'),
      hasLength(4),
    );

    harness.update(
      const AcpUserMessageChunkView(
        AcpContentChunkView(content: AcpTextContentView(text: 'ACP 消息')),
      ),
    );
    harness.update(
      const AcpAgentThoughtChunkView(
        AcpContentChunkView(
          content: AcpTextContentView(text: '正在梳理会话生命周期与配置回执顺序…'),
        ),
      ),
    );
    harness.update(
      AcpToolCallSessionUpdateView(
        AcpToolCallView(
          toolCallId: const AcpToolCallId('tool-read-1'),
          title: '读取设计文档 19-studio-ui.md',
          kind: AcpToolKindView.read,
          status: AcpToolCallStatusView.completed,
          locations: const [
            AcpToolCallLocationView(path: 'design/19-studio-ui.md', line: 271),
          ],
        ),
      ),
    );
    harness.update(
      const AcpAgentMessageChunkView(
        AcpContentChunkView(content: AcpTextContentView(text: '流式回复')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '下一条草稿');
    await tester.pumpAndSettle();
    expect(find.text('流式回复'), findsOneWidget);

    // A -> B -> A replaces the real component subtree, allowing autoDispose
    // display watches to release; the Client owner must keep consuming A.
    final sourceB = ControlledAcpObservation([
      AcpAcceptedFrameView(
        target: AcpSessionTargetView(
          sessionId: 'session',
          agentId: 'agent-b',
          threadId: 'thread-b',
          instance: BigInt.from(20),
        ),
        hasObservation: true,
      ),
      AcpEventFrameView(
        AcpReadyEventView(
          AcpNewSessionResponseView(
            sessionId: const AcpRemoteSessionId('remote-b'),
          ),
        ),
      ),
      const AcpSettledFrameView(AcpSuccessView<void>(null)),
    ]);
    otherSource = sourceB;
    harness.port.sources.add(sourceB);
    final ownerB = await harness.client.acpSessions.openConversation(
      OpenAcpSessionRequestView(
        accountId: 'account',
        expectedConnectionRevision: BigInt.one,
        workspaceId: 'workspace',
        threadId: 'thread-b',
        intent: const AcpLoadIntentView(AcpRemoteSessionId('remote-b')),
      ),
    );
    await showPage('thread-b');
    expect(find.text('流式回复'), findsNothing);
    harness.update(
      const AcpAgentMessageChunkView(
        AcpContentChunkView(content: AcpTextContentView(text: '，后台继续')),
      ),
    );
    await tester.pumpAndSettle();
    expect(harness.source.closeSignals, 0);
    expect(ownerB.state.activeRun, isNull);
    await showPage('thread');
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AcpConversationContentView)),
    );
    expect(
      await container.read(acpConversationOwnerProvider('thread').future),
      same(harness.owner),
    );
    expect(find.text('流式回复，后台继续'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '下一条草稿',
    );
    expect(harness.client.drafts.composer('thread'), same(draft));
    expect(harness.port.calls.where((call) => call.$1 == 'open'), hasLength(2));
    expect(prompts, hasLength(1));

    expect(find.text('中断'), findsNothing);
    expect(find.byTooltip('中断'), findsOneWidget);
    await tester.tap(primaryAction());
    await tester.pumpAndSettle();
    final interrupt = harness.port.calls.last.$2 as AcpInterruptRequestView;
    expect(interrupt.target, same(harness.owner.state.target));
    expect(interrupt.run, run);
    expect(harness.owner.state.activeRun, run);
    harness.emit(
      AcpCompletedEventView(
        AcpCompletedRunView(
          run: run,
          completionSequence: BigInt.one,
          result: const AcpSuccessView(
            AcpPromptResponseView(stopReason: AcpStopReasonView.cancelled),
          ),
          summary: 'cancelled',
          truncated: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(harness.owner.state.activeRun, isNull);
    expect(find.byTooltip('中断'), findsNothing);
    expect(sendButton().onPressed, isNotNull);
    expect(draft.state.draft, '下一条草稿');
    expect(prompts, hasLength(1));
    expect(
      harness.port.calls.where((call) => call.$1 == 'interrupt'),
      hasLength(1),
    );
    expect(tester.takeException(), isNull);
  });
}
