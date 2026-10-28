import 'dart:async';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/interaction/child_interaction_dock.dart';
import 'package:anywork/src/features/interaction/composer_dock.dart';
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
    if (failure != null && from != null && readHosts.length >= from) {
      throw failure;
    }
    final gate = readGate;
    if (gate != null) await gate.future;
    completedReads[hostThreadId] = (completedReads[hostThreadId] ?? 0) + 1;
    return List.of(summaries);
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
      resolution: resolution,
    ));
    final error = respondError;
    final gate = decisionGate;
    if (gate != null) await gate.future;
    respondCompletions++;
    if (error != null) throw error;
    final summary = summaries.firstWhere(
      (item) => item.interactionId == interactionId,
    );
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
    graph.client.directoryCommands.selectThread(_rootId),
    'select root for cards',
  );
  graph.client.project.applyAgentDirectory(
    AgentDirectoryState(revision: 1, values: _members()),
  );
  return _Fixture(graph, transport);
}

Future<void> _pump(WidgetTester tester, _Fixture fixture) async {
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
            child: ComposerDock(threadId: _rootId),
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
      expect(fixture.graph.client.existingComposer(childId), isNull);
      expect(
        fixture.graph.client.sessionStates.map((state) => state.threadId),
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
    await tester.tap(
      find.descendant(
        of: find.byKey(StudioDriverKeys.childInteractionCard('interaction-a')),
        matching: find.byKey(StudioDriverKeys.toolApprove),
      ),
    );
    await pumpClientUntil(
      tester,
      () => transport.decisions.isNotEmpty,
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

  testWidgets('切换主会话时旧读取结束仍会列举新宿主', (tester) async {
    final fixture = await _fixture(tester);
    final transport = fixture.transport;
    final gate = Completer<void>();
    transport.readGate = gate;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appGraphProvider.overrideWithValue(fixture.graph)],
        child: MaterialApp(
          theme: pureStudioTheme(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SizedBox(
              width: 900,
              height: 900,
              child: ChildInteractionDock(
                hostThreadId: 'root-a',
                items: [],
                sources: {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await pumpClientUntil(
      tester,
      () => transport.readHosts.isNotEmpty,
      'first host read starts',
    );
    expect(transport.readHosts, ['root-a']);

    // 旧读取仍在途时切到新宿主：请求不能被 _reading 丢弃。
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appGraphProvider.overrideWithValue(fixture.graph)],
        child: MaterialApp(
          theme: pureStudioTheme(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SizedBox(
              width: 900,
              height: 900,
              child: ChildInteractionDock(
                hostThreadId: 'root-b',
                items: [],
                sources: {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    transport.readGate = null;
    gate.complete();
    await pumpClientUntil(
      tester,
      () => transport.readHosts.contains('root-b'),
      'new host listed after the old read finished',
    );
    expect(transport.readHosts, ['root-a', 'root-b']);
    await _close(tester, fixture);
  });

  testWidgets('迟到的决议回调不污染已切换的主会话', (tester) async {
    final fixture = await _fixture(tester);
    final transport = fixture.transport;
    final gate = Completer<void>();
    transport.decisionGate = gate;
    const hostA = 'root-a';
    const hostB = 'root-b';
    const aSummary = ChildInteractionSummary(
      childThreadId: 'child-a',
      interactionId: 'interaction-a-host',
      kind: InteractionKind.toolApproval,
      revision: 5,
      interaction: PendingInteraction(
        id: 'interaction-a-host',
        threadId: 'child-a',
        turnId: 'turn-a',
        kind: InteractionKind.toolApproval,
        title: 'Run in A',
        body: 'Child A wants to run a command',
        payload: ToolApprovalInteractionPayload(
          toolName: 'shell',
          arguments: {'command': 'ls'},
          workingDirectory: '/tmp',
        ),
        revision: 5,
      ),
    );
    const bSummary = ChildInteractionSummary(
      childThreadId: 'child-b',
      interactionId: 'interaction-b-host',
      kind: InteractionKind.toolApproval,
      revision: 9,
      interaction: PendingInteraction(
        id: 'interaction-b-host',
        threadId: 'child-b',
        turnId: 'turn-b',
        kind: InteractionKind.toolApproval,
        title: 'Run in B',
        body: 'Child B wants to run a command',
        payload: ToolApprovalInteractionPayload(
          toolName: 'shell',
          arguments: {'command': 'pwd'},
          workingDirectory: '/tmp',
        ),
        revision: 9,
      ),
    );
    Widget dock(String host, List<ChildInteractionSummary> items) {
      return ProviderScope(
        overrides: [appGraphProvider.overrideWithValue(fixture.graph)],
        child: MaterialApp(
          theme: pureStudioTheme(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 900,
              height: 1200,
              child: ChildInteractionDock(
                hostThreadId: host,
                items: items,
                sources: const {'child-a': 'Member A', 'child-b': 'Member B'},
              ),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(dock(hostA, [aSummary]));
    await tester.pump();
    await tester.tap(find.byKey(StudioDriverKeys.toolApprove));
    await pumpClientUntil(
      tester,
      () => transport.decisions.length == 1,
      'host A decision started',
    );

    // 切到主会话 B：A 的决定仍未返回。
    await tester.pumpWidget(dock(hostB, [bSummary]));
    await tester.pump();
    await pumpClientUntil(
      tester,
      () => transport.completedReadsFor(hostB) > 0,
      'host B listing completed',
    );

    final bCompletionsBefore = transport.completedReadsFor(hostB);
    expect(
      bCompletionsBefore,
      greaterThan(0),
      reason: 'B 的列举必须已完成，才能判定 A 的迟到结果',
    );

    // A 的回调此时才到达：不得进入 B 的已受理/成功状态，也不得据 A 摘要做确认。
    // 用 runAsync 放行真实异步，让挂起的决议请求真正恢复。
    await tester.runAsync(() async {
      gate.complete();
      await Future<void>.delayed(Duration.zero);
    });
    await pumpClientUntil(
      tester,
      () => transport.completedReadsFor(hostB) > bCompletionsBefore,
      'host B relisted after the stale callback '
      'hosts=${transport.readHosts} completed=${transport.completedReads} '
      'respondCompletions=${transport.respondCompletions}',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('child-interaction-notice-interaction-a-host')),
      findsNothing,
      reason: 'A 的成功通知不得出现在 B 页面',
    );
    expect(
      find.byKey(
        const ValueKey('child-interaction-accepted-interaction-a-host'),
      ),
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
    // B 按自己的 canonical 投影重新列举（完成次数已在上面增加）。
    expect(transport.readHosts.last, hostB);
    expect(transport.completedReadsFor(hostB), greaterThan(bCompletionsBefore));
    expect(
      find.byKey(StudioDriverKeys.childInteractionCard('interaction-b-host')),
      findsOneWidget,
      reason: 'B 的卡片不受 A 的迟到结果影响',
    );

    // B 自己的决议仍能正常确认。
    transport.decisionGate = null;
    transport.keepAfterDecision = false;
    transport.summaries = [aSummary, bSummary];
    await tester.tap(
      find.descendant(
        of: find.byKey(
          StudioDriverKeys.childInteractionCard('interaction-b-host'),
        ),
        matching: find.byKey(StudioDriverKeys.toolApprove),
      ),
    );
    await pumpClientUntil(
      tester,
      () => transport.decisions.length == 2,
      'host B decision submitted',
    );
    await tester.pumpWidget(dock(hostB, const []));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('child-interaction-notice-interaction-b-host')),
      findsOneWidget,
      reason: 'B 自己的决议在 canonical 确认后显示成功通知',
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
