import 'dart:async';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/features/conversation/acp/acp_views.dart';
import 'package:anywork/src/features/conversation/acp/connectors/acp_composer_connector.dart';
import 'package:anywork/src/features/conversation/acp/connectors/acp_permission_connector.dart';
import 'package:anywork/src/features/conversation/acp/connectors/acp_timeline_connector.dart';
import 'package:anywork/src/features/conversation/acp/connectors/acp_workspace_connector.dart';
import 'package:anywork/src/features/conversation/acp/view_models/acp_configuration_view_model.dart';
import 'package:anywork/src/features/conversation/acp/view_models/acp_plan_card_view_model.dart';
import 'package:anywork/src/platform/clipboard_image_reader.dart';
import 'package:anywork/src/shared/composer_configuration_bar.dart';
import 'package:anywork_client/acp_sessions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'acp_components_support.dart';

final class _DelayedClipboardReader implements ClipboardImageReader {
  var result = Completer<Uint8List?>();

  @override
  Future<Uint8List?> readImage() => result.future;
}

IconButton _sendButtonWidget(WidgetTester tester, String threadId) {
  final primary = find.byKey(
    ValueKey(AcpViewKeyValues.composerPrimaryAction(threadId)),
  );
  return tester.widget<IconButton>(primary);
}

void main() {
  testWidgets('ACP 回显丢失标注时仍展示真实提交的 hi，协议原文完整保留', (tester) async {
    final harness = await AcpComponentHarness.create();
    harness.port.run = AcpRunIdView(instance: BigInt.one, sequence: BigInt.one);
    addTearDown(() => harness.close(tester));
    await tester.pumpWidget(
      harness.scope(const AcpTimelineConnector(threadId: 'thread')),
    );
    await harness.owner.send([const AcpTextContentView(text: 'hi')]);
    harness.update(
      const AcpUserMessageChunkView(
        AcpContentChunkView(
          content: AcpTextContentView(text: 'Host instructions\n'),
        ),
      ),
    );
    harness.update(
      const AcpUserMessageChunkView(
        AcpContentChunkView(content: AcpTextContentView(text: 'hi')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('hi'), findsOneWidget);
    expect(find.textContaining('Host instructions'), findsNothing);
    final user = harness.owner.state.content
        .whereType<AcpConversationMessageItem>()
        .single;
    expect(
      user.chunks.map((chunk) => (chunk.content as AcpTextContentView).text),
      ['Host instructions\n', 'hi'],
    );
  });

  testWidgets('ACP 消息遵循受众标注，隐藏宿主上下文且保留原始协议块', (tester) async {
    final hidden = AcpContentChunkView(
      content: AcpTextContentView(
        text: 'Host instructions',
        annotations: AcpAnnotationsView(
          audience: [AcpContentRoleView.assistant],
        ),
      ),
    );
    final harness = await AcpComponentHarness.create(
      updates: [AcpUserMessageChunkView(hidden)],
    );
    addTearDown(() => harness.close(tester));
    await tester.pumpWidget(
      harness.scope(const AcpTimelineConnector(threadId: 'thread')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Host instructions'), findsNothing);
    expect(
      find.byType(AcpTimelineEntryView),
      findsNothing,
      reason: '仅助手可见的内容不能留下空白气泡',
    );
    harness.update(
      const AcpUserMessageChunkView(
        AcpContentChunkView(content: AcpTextContentView(text: 'hi')),
      ),
    );
    harness.update(
      AcpAgentMessageChunkView(
        AcpContentChunkView(
          content: AcpTextContentView(
            text: '你好！',
            annotations: AcpAnnotationsView(
              audience: [AcpContentRoleView.user, AcpContentRoleView.assistant],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('hi'), findsOneWidget);
    expect(find.text('你好！'), findsOneWidget);
    final user = harness.owner.state.content
        .whereType<AcpConversationMessageItem>()
        .first;
    expect(user.chunks, [same(hidden), isA<AcpContentChunkView>()]);
    harness.update(
      const AcpUserMessageChunkView(
        AcpContentChunkView(
          content: AcpTextContentView(text: 'Host instructions'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Host instructions'),
      findsOneWidget,
      reason: '用户输入相同文字仍原样显示，不按内容猜测是否为宿主指令',
    );
  });

  testWidgets('ACP 发送中提示仅保留无障碍图标，停止原位切换且错误不丢失', (tester) async {
    var submissions = 0;
    var interrupts = 0;
    Widget composer(AcpComposerViewState state) => acpTestApp(
      SizedBox(
        width: 300,
        child: AcpConversationComposerView(
          state: state,
          onDraftChanged: (_) {},
          onSubmit: () => submissions++,
          onInterrupt: () => interrupts++,
          onPickLocalAttachments: (_) async {},
          onAddRemoteAttachment: (_) async {},
          onRemoveAttachment: (_) {},
        ),
      ),
    );
    await tester.pumpWidget(
      composer(
        const AcpComposerViewState(
          threadId: 'thread',
          submitting: true,
          blocker: AcpComposerBlocker(kind: AcpComposerBlockerKind.sending),
          draftError: 'attachment could not be read',
        ),
      ),
    );
    final primary = find.byKey(
      ValueKey(AcpViewKeyValues.composerPrimaryAction('thread')),
    );
    final button = tester.widget<IconButton>(primary);
    expectAcpPrimaryGeometry(tester, primary);
    expect(button.onPressed, isNull);
    expect(find.text(button.tooltip!), findsNothing);
    expect(
      find.semantics.byPredicate(
        (node) => node.getSemanticsData().tooltip == button.tooltip,
      ),
      findsOne,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('attachment could not be read'), findsOneWidget);
    await tester.tap(primary);
    expect(submissions, 0);
    expect(interrupts, 0);
    final sendingRect = tester.getRect(primary);
    await tester.pumpWidget(
      composer(
        const AcpComposerViewState(
          threadId: 'thread',
          isRunning: true,
          canInterrupt: true,
        ),
      ),
    );
    final stop = tester.widget<IconButton>(primary);
    expectAcpPrimaryGeometry(tester, primary);
    expect(tester.getRect(primary).size, sendingRect.size);
    expect(tester.getRect(primary).left, sendingRect.left);
    expect(find.text(stop.tooltip!), findsNothing);
    expect(
      find.semantics.byPredicate(
        (node) => node.getSemanticsData().tooltip == stop.tooltip,
      ),
      findsOne,
    );
    await tester.tap(primary);
    expect(interrupts, 1);
    await tester.pumpWidget(
      composer(
        const AcpComposerViewState(
          threadId: 'thread',
          isRunning: true,
          canInterrupt: true,
          interrupting: true,
        ),
      ),
    );
    expectAcpPrimaryGeometry(tester, primary);
    expect(tester.widget<IconButton>(primary).onPressed, isNull);
    await tester.tap(primary);
    expect(interrupts, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('ACP 异步粘贴与换行沿官方编辑动作更新原草稿', (tester) async {
    final harness = await AcpComponentHarness.create();
    addTearDown(() => harness.close(tester));
    final reader = _DelayedClipboardReader();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => switch (call.method) {
        'Clipboard.getData' => {'text': 'pasted'},
        'Clipboard.hasStrings' => {'value': true},
        _ => null,
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    Widget host(String threadId) => ProviderScope(
      overrides: [
        appGraphProvider.overrideWithValue(harness.graph),
        clipboardImageReaderProvider.overrideWithValue(reader),
      ],
      child: acpTestApp(AcpComposerConnector(threadId: threadId)),
    );
    await tester.pumpWidget(host('thread'));
    await tester.pumpAndSettle();
    final input = find.byKey(
      ValueKey(AcpViewKeyValues.composerInput('thread')),
    );
    await tester.enterText(input, 'abcd');
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'abcd',
        selection: TextSelection(baseOffset: 1, extentOffset: 3),
      ),
    );
    await tester.pump();
    Actions.invoke(
      tester
          .state<EditableTextState>(find.byType(EditableText))
          .widget
          .focusNode
          .context!,
      const PasteTextIntent(SelectionChangedCause.keyboard),
    );
    await tester.pump();
    final draft = harness.client.drafts.composer('thread');
    expect(draft.state.draft, 'abcd');
    reader.result.complete(null);
    await tester.pumpAndSettle();
    expect(draft.state.draft, 'apastedd');
    final controller = tester.widget<TextField>(input).controller!;
    expect(controller.selection, const TextSelection.collapsed(offset: 7));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(draft.state.draft, 'apasted\nd');
    for (final staleImage in [null, Uint8List(1)]) {
      reader.result = Completer<Uint8List?>();
      Actions.invoke(
        tester
            .state<EditableTextState>(find.byType(EditableText))
            .widget
            .focusNode
            .context!,
        const PasteTextIntent(SelectionChangedCause.keyboard),
      );
      await tester.pump();
      await tester.pumpWidget(host('other-thread'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(host('thread'));
      await tester.pumpAndSettle();
      reader.result.complete(staleImage);
      await tester.pumpAndSettle();
      expect(draft.state.draft, 'apasted\nd');
      expect(draft.state.failure, isNull);
      expect(draft.state.attachments, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.tap(input);
    }
    expect(harness.port.calls.where((call) => call.$1 == 'prompt'), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

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
      harness.scope(const AcpWorkspaceConnector(threadId: 'thread')),
    );
    await tester.pumpAndSettle();
    expect(find.text('第一段'), findsOneWidget);
    expect(find.byKey(const ValueKey('acp-plan-status-pill')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('acp-plan-status-pill')));
    await tester.pumpAndSettle();
    expect(find.text('读取项目'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AcpWorkspaceConnector)),
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
    field.controller!.value = const TextEditingValue(
      text: '保留我的草稿',
      selection: TextSelection.collapsed(offset: 2),
      composing: TextRange(start: 1, end: 3),
    );
    final configuration = Completer<void>();
    harness.port.configureResult = configuration;
    await tester.tap(find.byKey(ComposerConfigurationBar.moreKey));
    await tester.pumpAndSettle();
    final booleanControl = find.byKey(
      ValueKey(AcpViewKeyValues.configControl(acpBooleanFixture.id.value)),
    );
    final booleanOption = find.descendant(
      of: booleanControl,
      matching: find.byType(CheckboxMenuButton),
    );
    expect(booleanOption, findsOneWidget);
    await tester.tap(booleanOption);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(harness.owner.state.configPending, isTrue);
    expect(_sendButtonWidget(tester, 'thread').onPressed, isNull);
    expect(find.byTooltip('正在应用配置，完成前不能发送消息'), findsOneWidget);
    expect(find.text('正在应用配置，完成前不能发送消息'), findsNothing);
    await tester.tap(
      find.byKey(ValueKey(AcpViewKeyValues.composerPrimaryAction('thread'))),
    );
    await tester.pump();
    expect(harness.port.calls.any((call) => call.$1 == 'prompt'), isFalse);
    harness.update(
      const AcpAgentMessageChunkView(
        AcpContentChunkView(content: AcpTextContentView(text: '异步内容')),
      ),
    );
    await tester.pump();
    expect(field.controller!.text, '保留我的草稿');
    expect(field.controller!.selection.baseOffset, 2);
    expect(
      field.controller!.value.composing,
      const TextRange(start: 1, end: 3),
    );
    await tester.tap(find.byKey(ComposerConfigurationBar.moreKey));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CheckboxMenuButton>(booleanOption).onChanged,
      isNull,
      reason: '配置请求在途时，真实菜单选项必须不可交互',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
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
    expect(find.text('中断'), findsNothing);
    expect(find.byTooltip('中断'), findsOneWidget);
  });

  for (final completionFirst in [false, true]) {
    testWidgets('发送和停止期间继续编辑，${completionFirst ? '运行先结束' : '中断先返回'}仍等真实双边完成', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(300, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final harness = await AcpComponentHarness.create(
        options: [acpBooleanFixture],
      );
      addTearDown(() => harness.close(tester));
      final run = AcpRunIdView(instance: BigInt.one, sequence: BigInt.one);
      harness.port.run = run;
      final sending = Completer<AcpRunIdView>();
      harness.port.promptResult = sending;
      final interrupting = Completer<void>();
      harness.port.interruptResult = interrupting;
      final draft = harness.client.drafts.composer('thread');
      draft.updateDraft('本次发送');
      await tester.pumpWidget(
        harness.scope(const AcpComposerConnector(threadId: 'thread')),
      );
      await tester.pumpAndSettle();
      final input = find.byKey(
        ValueKey(AcpViewKeyValues.composerInput('thread')),
      );
      final action = find.byKey(
        ValueKey(AcpViewKeyValues.composerPrimaryAction('thread')),
      );
      final originalRect = tester.getRect(action);
      expect(originalRect.size, const Size(34, 34));
      final moreAction = find.byKey(ComposerConfigurationBar.moreKey);
      final moreRect = tester.getRect(moreAction);
      await tester.tap(action);
      await tester.pump();
      expect(tester.widget<TextField>(input).enabled, isNot(false));
      expect(_sendButtonWidget(tester, 'thread').onPressed, isNull);
      await tester.enterText(input, '下一条草稿');
      await tester.pump();
      final controller = tester.widget<TextField>(input).controller!;
      controller.value = const TextEditingValue(
        text: '下一条草稿',
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange(start: 1, end: 3),
      );
      sending.complete(run);
      await tester.pump();
      expect(harness.owner.state.activeRun, run);
      expect(draft.state.draft, '下一条草稿');
      expect(controller.value.composing, const TextRange(start: 1, end: 3));
      expect(controller.selection.baseOffset, 3);
      expect(tester.getRect(action), originalRect);
      expect(tester.getRect(moreAction), moreRect);
      await tester.testTextInput.receiveAction(TextInputAction.send);
      expect(
        harness.port.calls.where((call) => call.$1 == 'prompt'),
        hasLength(1),
      );
      await tester.tap(action);
      await tester.pump();
      expect(find.byTooltip('正在中断'), findsWidgets);
      expect(_sendButtonWidget(tester, 'thread').onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // A second stop intent must not escape while the first is pending.
      await tester.tap(action);
      await tester.pump();
      expect(
        harness.port.calls.where((call) => call.$1 == 'interrupt'),
        hasLength(1),
      );
      await tester.enterText(input, '停止时继续编辑');
      await tester.pump();
      void completeRun() => harness.emit(
        AcpCompletedEventView(
          AcpCompletedRunView(
            run: run,
            completionSequence: BigInt.one,
            result: const AcpSuccessView(
              AcpPromptResponseView(stopReason: AcpStopReasonView.cancelled),
            ),
            summary: '',
            truncated: false,
          ),
        ),
      );
      if (completionFirst) {
        completeRun();
      } else {
        interrupting.complete();
      }
      await tester.pump();
      expect(_sendButtonWidget(tester, 'thread').onPressed, isNull);
      expect(tester.getRect(action), originalRect);
      expect(tester.getRect(moreAction), moreRect);
      if (completionFirst) {
        interrupting.complete();
      } else {
        completeRun();
      }
      await tester.pumpAndSettle();
      expect(harness.owner.state.activeRun, isNull);
      expect(_sendButtonWidget(tester, 'thread').onPressed, isNotNull);
      expect(tester.getRect(moreAction), moreRect);
      expect(draft.state.draft, '停止时继续编辑');
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        harness.port.calls.where((call) => call.$1 == 'prompt'),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    });
  }

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
    await tester.tap(find.byKey(ComposerConfigurationBar.moreKey));
    await tester.pumpAndSettle();
    final booleanOption = find.descendant(
      of: find.byKey(
        ValueKey(AcpViewKeyValues.configControl(acpBooleanFixture.id.value)),
      ),
      matching: find.byType(CheckboxMenuButton),
    );
    expect(booleanOption, findsOneWidget);
    await tester.tap(booleanOption);
    await tester.pumpAndSettle();
    expect(find.textContaining('配置失败：'), findsWidgets);
    expect(_sendButtonWidget(tester, 'thread').onPressed, isNull);
    expect(harness.client.drafts.composer('thread').state.draft, '不能丢失的输入');
    expect(
      harness.port.calls.where((call) => call.$1 == 'configure'),
      hasLength(1),
    );
    await tester.tap(
      find.byKey(ValueKey(AcpViewKeyValues.composerPrimaryAction('thread'))),
    );
    await tester.pump();
    expect(harness.port.calls.any((call) => call.$1 == 'prompt'), isFalse);
  });

  testWidgets('ACP 输入保留编辑值并遵循平台提交与焦点行为', (tester) async {
    var submissions = 0;
    Widget input() => acpTestApp(
      AcpConversationComposerView(
        state: const AcpComposerViewState(
          threadId: 'thread',
          draftText: '输入中的草稿',
          canSend: true,
        ),
        onDraftChanged: (_) {},
        onSubmit: () => submissions++,
        onInterrupt: () {},
        onPickLocalAttachments: (_) async {},
        onAddRemoteAttachment: (_) async {},
        onRemoveAttachment: (_) {},
      ),
    );
    await tester.pumpWidget(input());
    await tester.showKeyboard(find.byType(TextField));
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
    // The platform confirms composition before reporting a send action.
    tester.testTextInput.updateEditingValue(
      controller.value.copyWith(composing: TextRange.empty),
    );
    await tester.testTextInput.receiveAction(TextInputAction.send);
    expect(submissions, 1);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isFalse,
    );
    await tester.showKeyboard(find.byType(TextField));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(controller.text, '输入中\n的草稿');
    expect(submissions, 1);
  });
}
