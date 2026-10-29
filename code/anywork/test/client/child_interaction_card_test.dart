import 'dart:async';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/composer/connectors/composer_dock_connector.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pump_client_future.dart';
import 'support/recording_demo_transport.dart';
import 'support/test_statistics_feed.dart';

const _rootId = 'thread-main';
const _questionChild = 'thread-child-q';
const _approvalChild = 'thread-child-a';
const _staleChild = 'thread-child-s';
const _alternateChild = 'thread-alt-child';

const _question = PendingInteraction(
  id: 'interaction-q',
  threadId: _questionChild,
  turnId: 'child-turn-q',
  kind: InteractionKind.userInput,
  title: 'Choose the next step',
  body: 'Which module should change first?',
  payload: UserInputInteractionPayload(
    questions: [
      UserQuestionView(
        id: 'q1',
        header: 'Scope',
        question: 'Which module should change first?',
        isOther: false,
        isSecret: false,
        options: [
          UserQuestionOptionView(
            label: 'Runtime',
            description: 'Change the runtime module',
          ),
          UserQuestionOptionView(
            label: 'Client',
            description: 'Change the client module',
          ),
        ],
      ),
    ],
  ),
  revision: 4,
);

const _approval = PendingInteraction(
  id: 'interaction-a',
  threadId: _approvalChild,
  turnId: 'child-turn-a',
  kind: InteractionKind.toolApproval,
  title: 'Run the shell command',
  body: 'The child agent wants to run a command',
  payload: ToolApprovalInteractionPayload(
    toolName: 'shell',
    arguments: {'command': 'ls'},
    workingDirectory: '/tmp',
  ),
  revision: 7,
);

const _stale = PendingInteraction(
  id: 'interaction-s',
  threadId: _staleChild,
  turnId: 'child-turn-s',
  kind: InteractionKind.toolApproval,
  title: 'Run the tests',
  body: 'The child agent wants to run the tests',
  payload: ToolApprovalInteractionPayload(
    toolName: 'shell',
    arguments: {'command': 'flutter test'},
    workingDirectory: '/tmp',
  ),
  revision: 2,
);

const _alternate = PendingInteraction(
  id: 'interaction-alt',
  threadId: _alternateChild,
  turnId: 'child-turn-alt',
  kind: InteractionKind.toolApproval,
  title: 'Run in alternate host',
  body: 'The alternate member wants to run a command',
  payload: ToolApprovalInteractionPayload(
    toolName: 'shell',
    arguments: {'command': 'pwd'},
    workingDirectory: '/tmp',
  ),
  revision: 9,
);

const _alternateSummary = ChildInteractionSummary(
  childThreadId: _alternateChild,
  interactionId: 'interaction-alt',
  kind: InteractionKind.toolApproval,
  revision: 9,
  interaction: _alternate,
);

/// 子会话的计划请求：它是子会话自身的诊断事实，不进入主会话的可决议投影。
const _childPlan = PendingInteraction(
  id: 'interaction-p',
  threadId: _staleChild,
  turnId: 'child-turn-p',
  kind: InteractionKind.userInput,
  title: 'Plan',
  body: 'Child plan document',
  payload: UserInputInteractionPayload(
    questions: [
      UserQuestionView(
        id: agentSessionPlanConfirmationQuestionId,
        header: 'Plan',
        question: 'Child plan document',
        isOther: true,
        isSecret: false,
        options: [
          UserQuestionOptionView(
            label: agentSessionPlanApproveAnswer,
            description: 'Approve this plan.',
          ),
        ],
      ),
    ],
  ),
  revision: 1,
);

/// 主会话可见的 child 待决交互由这里按脚本发布与决议。
final class _ChildCardTransport extends RecordingDemoTransport {
  _ChildCardTransport()
    : summaries = [
        const ChildInteractionSummary(
          childThreadId: _questionChild,
          interactionId: 'interaction-q',
          kind: InteractionKind.userInput,
          revision: 4,
          interaction: _question,
        ),
        const ChildInteractionSummary(
          childThreadId: _approvalChild,
          interactionId: 'interaction-a',
          kind: InteractionKind.toolApproval,
          revision: 7,
          interaction: _approval,
        ),
        const ChildInteractionSummary(
          childThreadId: _staleChild,
          interactionId: 'interaction-s',
          kind: InteractionKind.toolApproval,
          revision: 2,
          interaction: _stale,
        ),
      ];

  List<ChildInteractionSummary> summaries;
  final List<
    ({
      String host,
      String interactionId,
      int revision,
      OperationId operationId,
      InteractionResolutionCommand resolution,
    })
  >
  decisions = [];
  Object? respondError;

  /// 受理后是否保留原摘要：用于观察「已受理但 canonical 未确认」。
  bool keepAfterDecision = false;

  /// 非空时从第 [failReadFrom] 次读取起失败（1 表示初次读取就失败）。
  Object? readError;
  int? failReadFrom;

  final List<String> readHosts = [];

  /// 每个 host 真正**完成**的列举次数（读入口记录不足以证明结果已交付）。
  final Map<String, int> completedReads = {};

  int completedReadsFor(String host) => completedReads[host] ?? 0;

  int get readCalls => readHosts.length;

  @override
  Future<List<ChildInteractionSummary>> readChildInteractions(
    String hostThreadId,
  ) async {
    readHosts.add(hostThreadId);
    final failure = readError;
    final from = failReadFrom;
    final result = List<ChildInteractionSummary>.of(summaries);
    final shouldFail =
        failure != null && from != null && readHosts.length >= from;
    final gate = readGate;
    if (gate != null) await gate.future;
    completedReads[hostThreadId] = (completedReads[hostThreadId] ?? 0) + 1;
    if (shouldFail) throw failure;
    return result;
  }

  Completer<void>? readGate;

  /// 非空时挂起决议，用于观察迟到回调与宿主切换。
  Completer<void>? decisionGate;

  /// 决议 API 真正返回（或抛出）的次数，用于区分「未恢复」与「回调未触发」。
  int respondCompletions = 0;

  @override
  Future<InteractionCommandReply> respondInteraction(
    String hostThreadId,
    String interactionId,
    int expectedRevision,
    InteractionResolutionCommand resolution, {
    required OperationId operationId,
  }) async {
    decisions.add((
      host: hostThreadId,
      interactionId: interactionId,
      revision: expectedRevision,
      operationId: operationId,
      resolution: resolution,
    ));
    final summary = summaries.firstWhere(
      (item) => item.interactionId == interactionId,
    );
    final error = respondError;
    final gate = decisionGate;
    if (gate != null) await gate.future;
    respondCompletions++;
    if (error != null) throw error;
    if (!keepAfterDecision) summariseDecided();
    return InteractionCommandReply(
      interaction: summary.interaction,
      receipt: StudioCommandReceipt(
        operationId: operationId,
        disposition: CommitDisposition.applied,
        targets: const [],
        effect: EffectPoint.immediate,
        effective: true,
        durable: false,
        requiresIdentityObservation: true,
      ),
    );
  }

  void summariseDecided() {
    summaries = [
      for (final item in summaries)
        if (decisions.last.interactionId != item.interactionId) item,
    ];
  }
}

List<StudioAgentView> _members() => [
  for (final entry in const [
    (_questionChild, 'QA member'),
    (_approvalChild, 'Approval member'),
    (_staleChild, 'Stale member'),
  ])
    StudioAgentView(
      id: entry.$1,
      threadId: entry.$1,
      path: 'root/${entry.$1}',
      parentPath: 'root',
      rootThreadId: _rootId,
      depth: 1,
      role: 'executor',
      delegationMode: DelegationMode.profile,
      delegationPreference: DelegationPreference.balanced,
      task: entry.$2,
      state: const WaitingInteractionStudioAgent('child-turn', 'interaction'),
      updatedAt: DateTime.utc(2026, 1, 1),
    ),
  StudioAgentView(
    id: _alternateChild,
    threadId: _alternateChild,
    path: 'root-alt/member',
    parentPath: 'root-alt',
    rootThreadId: 'thread-alt',
    depth: 1,
    role: 'executor',
    delegationMode: DelegationMode.profile,
    delegationPreference: DelegationPreference.balanced,
    task: 'Alternate member',
    state: const WaitingInteractionStudioAgent('child-turn', 'interaction'),
    updatedAt: DateTime.utc(2026, 1, 1),
  ),
];

final class _Fixture {
  _Fixture(this.graph, this.transport);

  final AppGraph graph;
  final _ChildCardTransport transport;
}

Future<_Fixture> _fixture(WidgetTester tester) async {
  final transport = _ChildCardTransport();
  final graph = AppGraph(
    transport: transport,
    clientId: 'child-cards',
    statisticsFeed: const TestStatisticsFeedPort(),
  );
  addTearDown(() async {
    final readGate = transport.readGate;
    if (readGate != null && !readGate.isCompleted) readGate.complete();
    final decisionGate = transport.decisionGate;
    if (decisionGate != null && !decisionGate.isCompleted) {
      decisionGate.complete();
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpClientFuture(
      tester,
      graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
      'child cards teardown',
    );
  });
  await pumpClientFuture(tester, graph.client.bootstrap(), 'cards bootstrap');
  await pumpClientFuture(
    tester,
    (graph..setConversationPageVisible(true)).client.directoryCommands
        .selectThread(_rootId),
    'select root for cards',
  );
  graph.client.project.applyAgentDirectory(
    AgentDirectoryState(revision: 1, values: _members()),
  );
  return _Fixture(graph, transport);
}

Future<void> _pump(
  WidgetTester tester,
  _Fixture fixture, {
  String host = _rootId,
}) async {
  // 三张卡片同屏出现：测试画布按内容放大，避免把画布不足当成产品溢出。
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appGraphProvider.overrideWithValue(fixture.graph)],
      child: MaterialApp(
        theme: pureStudioTheme(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 2300,
            child: ComposerDockConnector(threadId: host),
          ),
        ),
      ),
    ),
  );
  // 卡片面板在首帧后发起一次显式只读列举。
  await tester.pumpAndSettle();
}

Future<void> _close(WidgetTester tester, _Fixture fixture) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await pumpClientFuture(
    tester,
    fixture.graph.close(
      deadline: DateTime.now().add(const Duration(seconds: 5)),
    ),
    'child cards close',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('root 展示来源明确的 child 待决交互并按类型提交决定', (tester) async {
    final fixture = await _fixture(tester);
    await _pump(tester, fixture);
    final transport = fixture.transport;
    await pumpClientUntil(
      tester,
      () => find
          .byKey(StudioDriverKeys.childInteractionCard('interaction-a'))
          .evaluate()
          .isNotEmpty,
      'child interaction cards render',
    );

    // 来源成员与 revision 来自 canonical 摘要，不被本地推断补齐。
    expect(find.text('From Approval member'), findsOneWidget);
    expect(find.text('From QA member'), findsOneWidget);
    expect(find.text('Revision 7'), findsOneWidget);
    expect(find.text('Revision 4'), findsOneWidget);
    expect(transport.readCalls, 1, reason: '页面重建不重复列举');

    // 审批：决定经主会话提交，host/revision 原样来自投影。
    await tester.tap(
      find.descendant(
        of: find.byKey(StudioDriverKeys.childInteractionCard('interaction-a')),
        matching: find.byKey(StudioDriverKeys.toolApprove),
      ),
    );
    await pumpClientUntil(
      tester,
      () => transport.decisions.isNotEmpty,
      'approve',
    );
    final approvalDecision = transport.decisions.last;
    expect(approvalDecision.host, _rootId);
    expect(approvalDecision.interactionId, 'interaction-a');
    expect(approvalDecision.revision, 7);
    expect(approvalDecision.resolution, isA<ToolApprovalResolutionCommand>());
    await pumpClientUntil(
      tester,
      () => find
          .byKey(const ValueKey('child-interaction-notice-interaction-a'))
          .evaluate()
          .isNotEmpty,
      'approval notice',
    );
    expect(
      find.text(
        'The original permission wait is decided. The original call may continue when it was approved, and is not executed when it was denied.',
      ),
      findsOneWidget,
      reason: '审批文案必须区分原权限已决议与原调用可能继续',
    );
    expect(
      find.textContaining('waiting for the main agent to schedule'),
      findsNothing,
      reason: '审批不得写成等待重新调度',
    );
    // canonical 确认后才从“已受理、等待确认”切换为成功通知。
    expect(
      find.byKey(const ValueKey('child-interaction-accepted-interaction-a')),
      findsNothing,
    );
    expect(
      find.text(
        'The decision was accepted. Waiting for the session to confirm it.',
      ),
      findsNothing,
    );
    expect(
      find.byKey(StudioDriverKeys.childInteractionCard('interaction-a')),
      findsNothing,
    );

    // 普通问题：答案保存，是否继续由主智能体决定。
    await tester.tap(find.byKey(StudioDriverKeys.userInputSubmit));
    await pumpClientUntil(
      tester,
      () => transport.decisions.length == 2,
      'answer question',
    );
    final questionDecision = transport.decisions.last;
    expect(questionDecision.host, _rootId);
    expect(questionDecision.interactionId, 'interaction-q');
    expect(questionDecision.revision, 4);
    expect(questionDecision.resolution, isA<UserInputResolutionCommand>());
    await pumpClientUntil(
      tester,
      () => find
          .byKey(const ValueKey('child-interaction-notice-interaction-q'))
          .evaluate()
          .isNotEmpty,
      'answer notice',
    );
    expect(
      find.text(
        'The answer is saved. The main agent decides whether this member continues.',
      ),
      findsOneWidget,
    );

    // 列举与决议都不激活 child 会话，也不为它建立草稿。
    for (final childId in [_questionChild, _approvalChild, _staleChild]) {
      expect(fixture.graph.client.drafts.existingComposer(childId), isNull);
      expect(
        fixture.graph.client.conversations.sessionStates.map(
          (state) => state.threadId,
        ),
        isNot(contains(childId)),
      );
    }
    await _close(tester, fixture);
  });

  testWidgets('决定被拒绝时显示 typed 原因并保留卡片', (tester) async {
    final fixture = await _fixture(tester);
    fixture.transport.respondError = const StudioFailure(
      code: StudioFailureCode.conflict,
      message: 'raw interaction conflict',
      retryable: false,
      correlationId: 'child-interaction-stale',
      reason: StudioFailureReason.staleInteraction,
    );
    await _pump(tester, fixture);
    final transport = fixture.transport;
    await pumpClientUntil(
      tester,
      () => find
          .byKey(StudioDriverKeys.childInteractionCard('interaction-s'))
          .evaluate()
          .isNotEmpty,
      'stale card renders',
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(StudioDriverKeys.childInteractionCard('interaction-s')),
        matching: find.byKey(StudioDriverKeys.toolApprove),
      ),
    );
    await pumpClientUntil(
      tester,
      () => find
          .byKey(const ValueKey('child-interaction-failure-interaction-s'))
          .evaluate()
          .isNotEmpty,
      'stale failure visible',
    );
    expect(
      find.text(
        'The decision was not accepted: This interaction was already updated. Open it again.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(StudioDriverKeys.childInteractionCard('interaction-s')),
      findsOneWidget,
      reason: '未被接受的决定不清除原卡片',
    );
    expect(
      transport.readCalls,
      greaterThan(1),
      reason: '失败后按 canonical 事实重新列举',
    );
    await _close(tester, fixture);
  });

  testWidgets('受理但 canonical 未确认时不宣告已保存或已决议', (tester) async {
    final fixture = await _fixture(tester);
    fixture.transport.keepAfterDecision = true;
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    fixture.transport.decisionGate = gate;
    await _pump(tester, fixture);
    final transport = fixture.transport;
    final currentApprove = find.descendant(
      of: find.byKey(StudioDriverKeys.childInteractionCard('interaction-a')),
      matching: find.byKey(StudioDriverKeys.toolApprove),
    );
    final otherApprove = find.descendant(
      of: find.byKey(StudioDriverKeys.childInteractionCard('interaction-s')),
      matching: find.byKey(StudioDriverKeys.toolApprove),
    );
    final currentDeny = find.descendant(
      of: find.byKey(StudioDriverKeys.childInteractionCard('interaction-a')),
      matching: find.byKey(StudioDriverKeys.toolDeny),
    );
    final otherDeny = find.descendant(
      of: find.byKey(StudioDriverKeys.childInteractionCard('interaction-s')),
      matching: find.byKey(StudioDriverKeys.toolDeny),
    );
    await pumpClientUntil(
      tester,
      () => find
          .byKey(StudioDriverKeys.childInteractionCard('interaction-a'))
          .evaluate()
          .isNotEmpty,
      'approval card renders',
    );
    expect(
      find.byKey(StudioDriverKeys.childInteractionCard('interaction-s')),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(otherApprove).onPressed, isNotNull);
    await tester.tap(currentApprove);
    await pumpClientUntil(
      tester,
      () =>
          transport.decisions.length == 1 &&
          find
              .byKey(const ValueKey('child-interaction-awaiting-interaction-a'))
              .evaluate()
              .isNotEmpty,
      'approval pending before transport response',
    );
    expect(
      find.byKey(const ValueKey('child-interaction-accepted-interaction-a')),
      findsNothing,
    );
    expect(tester.widget<FilledButton>(currentApprove).onPressed, isNull);
    expect(tester.widget<FilledButton>(otherApprove).onPressed, isNull);
    expect(tester.widget<TextButton>(currentDeny).onPressed, isNull);
    expect(tester.widget<TextButton>(otherDeny).onPressed, isNull);
    await tester.tap(currentApprove);
    await tester.tap(otherApprove);
    await tester.pump();
    expect(transport.decisions.length, 1, reason: '在途期间不能重复派发或派发其他交互');
    gate.complete();
    await pumpClientUntil(
      tester,
      () =>
          fixture.graph.client.mutations
              .latest('interaction:$_rootId')
              ?.state
              .value
              .receipt !=
          null,
      'decision receipt received',
    );
    final operation = fixture.graph.client.mutations
        .latest('interaction:$_rootId')!
        .state
        .value;
    expect(operation.id, transport.decisions.single.operationId);
    expect(operation.receipt!.operationId, operation.id);
    expect(operation.receipt!.requiresIdentityObservation, isTrue);
    expect(operation.observed, isFalse);
    expect(operation.failurePhase, isNull);
    expect(
      fixture
          .graph
          .client
          .threadCommands
          .state
          .commands['interaction:$_rootId']
          ?.accepted,
      isTrue,
      reason: '真实回执已受理而 canonical 尚未确认，命令看板必须发布受理事实',
    );
    await pumpClientUntil(
      tester,
      () => find
          .byKey(const ValueKey('child-interaction-accepted-interaction-a'))
          .evaluate()
          .isNotEmpty,
      'approval accepted',
    );
    // 受理回执到达，但 root 投影仍是同一 pending 触：不显示成功说明。
    await pumpClientUntil(
      tester,
      () => find
          .byKey(const ValueKey('child-interaction-awaiting-interaction-a'))
          .evaluate()
          .isNotEmpty,
      'awaiting canonical confirmation',
    );
    await pumpClientUntil(
      tester,
      () => transport.readCalls >= 2,
      'reread after acceptance',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('child-interaction-notice-interaction-a')),
      findsNothing,
      reason: '命令受理不等于已保存/已决议',
    );
    expect(
      find.textContaining('The original permission wait is decided'),
      findsNothing,
    );
    expect(
      find.byKey(StudioDriverKeys.childInteractionCard('interaction-a')),
      findsOneWidget,
      reason: '未确认前保留卡片',
    );
    // 中间态同时有文字与进度指示，且文字只表达“已受理、等待确认”。
    expect(
      find.byKey(const ValueKey('child-interaction-accepted-interaction-a')),
      findsOneWidget,
    );
    expect(
      find.text(
        'The decision was accepted. Waiting for the session to confirm it.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('saved'),
      findsNothing,
      reason: '等待确认期间不出现“已保存”',
    );
    expect(
      tester
          .widget<FilledButton>(
            find.descendant(
              of: find.byKey(
                StudioDriverKeys.childInteractionCard('interaction-a'),
              ),
              matching: find.byKey(StudioDriverKeys.toolApprove),
            ),
          )
          .onPressed,
      isNull,
      reason: '等待确认期间禁止重复提交',
    );
    expect(
      tester.widget<FilledButton>(otherApprove).onPressed,
      isNull,
      reason: '受理但未确认期间同一宿主的其他决定仍被阻塞',
    );
    expect(tester.widget<TextButton>(otherDeny).onPressed, isNull);
    await tester.tap(otherApprove);
    await tester.pump();
    expect(transport.decisions.length, 1);
    await _close(tester, fixture);
  });

  testWidgets('决议后 canonical 读取失败也不宣告成功', (tester) async {
    final fixture = await _fixture(tester);
    await _pump(tester, fixture);
    final transport = fixture.transport;
    await pumpClientUntil(
      tester,
      () => find
          .byKey(StudioDriverKeys.childInteractionCard('interaction-a'))
          .evaluate()
          .isNotEmpty,
      'approval card renders',
    );
    // 决议之后的第二次读取失败：canonical 无法确认，界面不得宣称已保存。
    transport.failReadFrom = 2;
    transport.readError = StateError('child interactions unavailable');
    await tester.tap(
      find.descendant(
        of: find.byKey(StudioDriverKeys.childInteractionCard('interaction-a')),
        matching: find.byKey(StudioDriverKeys.toolApprove),
      ),
    );
    await pumpClientUntil(
      tester,
      () => transport.readCalls >= 2,
      'failed reread after acceptance',
    );
    final operation = fixture.graph.client.mutations
        .latest('interaction:$_rootId')!
        .state
        .value;
    expect(operation.id, transport.decisions.single.operationId);
    expect(operation.receipt!.operationId, operation.id);
    expect(operation.receipt!.requiresIdentityObservation, isTrue);
    expect(operation.observed, isFalse);
    expect(operation.failurePhase, isNull);
    expect(
      fixture
          .graph
          .client
          .threadCommands
          .state
          .commands['interaction:$_rootId']
          ?.accepted,
      isTrue,
      reason: '读取失败不能抹去已受理回执',
    );
    // 等待确认的进度指示是持续动画，用固定帧推进而不是 pumpAndSettle。
    await tester.pump();
    expect(
      find.byKey(const ValueKey('child-interaction-load-failure')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('child-interaction-notice-interaction-a')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('child-interaction-awaiting-interaction-a')),
      findsOneWidget,
      reason: '未确认的决定保持等待状态',
    );
    expect(
      find.text(
        'The decision was accepted. Waiting for the session to confirm it.',
      ),
      findsOneWidget,
    );
    await _close(tester, fixture);
  });

  testWidgets('初次读取失败后可在页面内重试', (tester) async {
    final fixture = await _fixture(tester);
    fixture.transport.failReadFrom = 1;
    fixture.transport.readError = StateError('child interactions unavailable');
    await _pump(tester, fixture);
    final transport = fixture.transport;
    await pumpClientUntil(
      tester,
      () => find
          .byKey(const ValueKey('child-interaction-load-failure'))
          .evaluate()
          .isNotEmpty,
      'initial read failure',
    );
    expect(
      find.byKey(const ValueKey('child-interaction-retry')),
      findsOneWidget,
    );
    expect(
      find.textContaining('Child interactions could not be read'),
      findsOneWidget,
    );

    transport.failReadFrom = null;
    await tester.tap(find.byKey(const ValueKey('child-interaction-retry')));
    await pumpClientUntil(
      tester,
      () => find
          .byKey(StudioDriverKeys.childInteractionCard('interaction-a'))
          .evaluate()
          .isNotEmpty,
      'retry lists interactions',
    );
    expect(
      find.byKey(const ValueKey('child-interaction-load-failure')),
      findsNothing,
    );
    expect(transport.readHosts, [_rootId, _rootId]);
    await _close(tester, fixture);
  });

  for (final oldFails in [false, true]) {
    testWidgets(oldFails ? '旧读取失败不覆盖新代次错误' : '旧读取成功不覆盖新代次重试卡片', (tester) async {
      final fixture = await _fixture(tester);
      final transport = fixture.transport;
      final client = fixture.graph.client;
      const hostB = 'thread-alt';
      final alternate = await transport.readThread(hostB);
      client.threadDirectory.mergeOverlayThreads([alternate]);
      await _pump(tester, fixture);
      await pumpClientUntil(
        tester,
        () => transport.completedReadsFor(_rootId) == 1,
        'initial A read',
      );

      // A1 的响应和错误在请求入口冻结，直到 gate 放行才完成。
      client.conversations.setVisibleThread(null);
      await tester.pump();
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      transport.readGate = gate;
      transport.readError = oldFails ? StateError('old A1 failure') : null;
      transport.failReadFrom = oldFails ? 2 : null;
      client.conversations.setVisibleThread(_rootId);
      await pumpClientUntil(
        tester,
        () => transport.readCalls == 2,
        'A1 started',
      );
      expect(transport.completedReadsFor(_rootId), 1);
      expect(
        find.byKey(StudioDriverKeys.childInteractionCard('interaction-a')),
        findsNothing,
      );

      transport.readGate = null;
      transport.readError = null;
      transport.failReadFrom = null;
      transport.summaries = const [_alternateSummary];
      client.conversations.setVisibleThread(hostB);
      await _pump(tester, fixture, host: hostB);
      await pumpClientUntil(
        tester,
        () => transport.completedReadsFor(hostB) == 1,
        'B read completed',
      );
      expect(transport.readHosts, [_rootId, _rootId, hostB]);
      expect(
        find.byKey(StudioDriverKeys.childInteractionCard('interaction-alt')),
        findsOneWidget,
      );
      expect(find.text('From Alternate member'), findsOneWidget);

      transport.readError = StateError('current A2 failure');
      transport.failReadFrom = 4;
      client.conversations.setVisibleThread(_rootId);
      await _pump(tester, fixture);
      await pumpClientUntil(
        tester,
        () => find
            .byKey(const ValueKey('child-interaction-load-failure'))
            .evaluate()
            .isNotEmpty,
        'A2 failure',
      );
      expect(transport.readHosts, [_rootId, _rootId, hostB, _rootId]);
      expect(
        transport.completedReadsFor(_rootId),
        2,
        reason: 'A2 已完成，A1 仍被 gate 阻塞',
      );
      expect(
        find.text(
          'Child interactions could not be read: Bad state: current A2 failure',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(StudioDriverKeys.childInteractionCard('interaction-a')),
        findsNothing,
      );

      if (oldFails) {
        gate.complete();
        await pumpClientUntil(
          tester,
          () => transport.completedReadsFor(_rootId) == 3,
          'old A1 failure completed',
        );
        await tester.pump();
        expect(
          find.text(
            'Child interactions could not be read: Bad state: current A2 failure',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('old A1 failure'), findsNothing);
        expect(transport.readCalls, 4);
      }

      transport.failReadFrom = null;
      transport.summaries = const [
        ChildInteractionSummary(
          childThreadId: _staleChild,
          interactionId: 'interaction-s',
          kind: InteractionKind.toolApproval,
          revision: 2,
          interaction: _stale,
        ),
      ];
      await tester.tap(find.byKey(const ValueKey('child-interaction-retry')));
      await pumpClientUntil(
        tester,
        () => find
            .byKey(StudioDriverKeys.childInteractionCard('interaction-s'))
            .evaluate()
            .isNotEmpty,
        'A2 retry card',
      );
      expect(find.text('From Stale member'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('child-interaction-load-failure')),
        findsNothing,
      );
      expect(
        find.byKey(StudioDriverKeys.childInteractionCard('interaction-a')),
        findsNothing,
      );
      expect(transport.readCalls, 5);
      if (!oldFails) {
        gate.complete();
        await pumpClientUntil(
          tester,
          () => transport.completedReadsFor(_rootId) == 4,
          'old A1 success completed',
        );
        await tester.pump();
        expect(
          find.byKey(StudioDriverKeys.childInteractionCard('interaction-s')),
          findsOneWidget,
        );
        expect(find.text('From Stale member'), findsOneWidget);
        expect(
          find.byKey(StudioDriverKeys.childInteractionCard('interaction-a')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('child-interaction-load-failure')),
          findsNothing,
        );
        expect(transport.readCalls, 5);
      }
      expect(transport.decisions, isEmpty);
      await _close(tester, fixture);
    });
  }

  testWidgets('迟到的决议回调不污染已切换的主会话', (tester) async {
    final fixture = await _fixture(tester);
    final transport = fixture.transport;
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    transport.decisionGate = gate;
    const hostA = _rootId;
    const hostB = 'thread-alt';
    const aSummary = ChildInteractionSummary(
      childThreadId: _approvalChild,
      interactionId: 'interaction-a',
      kind: InteractionKind.toolApproval,
      revision: 7,
      interaction: _approval,
    );
    const bSummary = _alternateSummary;
    final client = fixture.graph.client;
    final alternate = await transport.readThread(hostB);
    client.threadDirectory.mergeOverlayThreads([alternate]);
    transport.summaries = [aSummary];
    await _pump(tester, fixture);
    await pumpClientUntil(
      tester,
      () => find
          .byKey(StudioDriverKeys.childInteractionCard('interaction-a'))
          .evaluate()
          .isNotEmpty,
      'host A canonical card',
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(StudioDriverKeys.childInteractionCard('interaction-a')),
        matching: find.byKey(StudioDriverKeys.toolApprove),
      ),
    );
    await pumpClientUntil(
      tester,
      () => transport.decisions.length == 1,
      'host A decision started',
    );
    expect(transport.decisions.single.host, hostA);

    // B 的列表和卡片来自生产 dock 所观察的 SDK canonical，而非手工传入。
    transport.summaries = [bSummary];
    client.conversations.setVisibleThread(hostB);
    await _pump(tester, fixture, host: hostB);
    await pumpClientUntil(
      tester,
      () => find
          .byKey(StudioDriverKeys.childInteractionCard('interaction-alt'))
          .evaluate()
          .isNotEmpty,
      'host B canonical card',
    );
    expect(transport.completedReadsFor(hostB), 1);
    final approveB = find.descendant(
      of: find.byKey(StudioDriverKeys.childInteractionCard('interaction-alt')),
      matching: find.byKey(StudioDriverKeys.toolApprove),
    );
    expect(tester.widget<FilledButton>(approveB).onPressed, isNotNull);
    final bReadsBefore = transport.readHosts
        .where((host) => host == hostB)
        .length;

    gate.complete();
    await pumpClientUntil(
      tester,
      () => transport.respondCompletions == 1,
      'host A decision completes',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('child-interaction-notice-interaction-a')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('child-interaction-accepted-interaction-a')),
      findsNothing,
    );
    expect(
      find.textContaining('Waiting for the session to confirm'),
      findsNothing,
    );
    expect(
      find.textContaining('The original permission wait is decided'),
      findsNothing,
    );
    expect(
      transport.readHosts.where((host) => host == hostB).length,
      bReadsBefore,
    );
    expect(
      find.byKey(StudioDriverKeys.childInteractionCard('interaction-alt')),
      findsOneWidget,
    );

    transport.decisionGate = null;
    transport.keepAfterDecision = false;
    transport.summaries = [bSummary];
    await tester.tap(approveB);
    await pumpClientUntil(
      tester,
      () => transport.decisions.length == 2,
      'host B decision submitted',
    );
    expect(transport.decisions.last.host, hostB);
    expect(transport.decisions.last.interactionId, 'interaction-alt');
    expect(transport.decisions.last.revision, 9);
    await pumpClientUntil(
      tester,
      () => find
          .byKey(const ValueKey('child-interaction-notice-interaction-alt'))
          .evaluate()
          .isNotEmpty,
      'host B canonical confirmation',
    );
    expect(
      find.byKey(const ValueKey('child-interaction-notice-interaction-alt')),
      findsOneWidget,
    );
    await _close(tester, fixture);
  });

  testWidgets('child 计划请求不作为主会话可决议卡片出现', (tester) async {
    final fixture = await _fixture(tester);
    fixture.transport.summaries = const [
      ChildInteractionSummary(
        childThreadId: _staleChild,
        interactionId: 'interaction-p',
        kind: InteractionKind.userInput,
        revision: 1,
        interaction: _childPlan,
      ),
    ];
    await _pump(tester, fixture);
    await pumpClientUntil(
      tester,
      () => fixture.transport.readCalls > 0,
      'child plan read',
    );
    expect(
      find.byKey(StudioDriverKeys.childInteractionCard('interaction-p')),
      findsNothing,
      reason: '子计划是诊断事实，不能转成可决议卡片',
    );
    expect(fixture.transport.decisions, isEmpty);
    await _close(tester, fixture);
  });
}
