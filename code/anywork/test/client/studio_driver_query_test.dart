import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/features/interaction/composer_view.dart';
import 'package:anywork/src/features/shell/shell_view.dart';
import 'package:anywork/src/features/status/status_view.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork/src/shared/studio_driver_projection.dart';
import 'package:anywork/src/shared/studio_driver_state.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_demo_transport.dart';

final class _UnusedTransport implements StudioTransport {
  var calls = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    throw UnsupportedError(
      'Driver query attempted transport: ${invocation.memberName}',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('workspace and Driver join current directory identity after a Turn', () async {
    final graph = AppGraph(
      transport: RecordingDemoTransport(),
      clientId: 'directory-identity',
    );
    addTearDown(
      () =>
          graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
    );
    final client = graph.client;
    await client.bootstrap();
    await client.directoryCommands.selectThread('thread-main');
    final session = client.existingSession('thread-main')!;
    await session.timeline.state.waitFor(
      (state) => state.snapshot is StudioTimelineBaselineFrame,
    );
    final initial = session.state.workspace!;
    // A runtime baseline may predate the directory's terminal/title/mode frame.
    session.applySnapshot(
      initial.copyWith(
        thread: initial.thread.copyWith(status: ThreadStatusView.running),
      ),
    );
    final container = ProviderContainer(
      overrides: [appGraphProvider.overrideWithValue(graph)],
    );
    addTearDown(container.dispose);
    final workspace = container.listen(
      shellComposerWorkspaceProvider,
      (_, _) {},
    );
    final status = container.listen(statusBarViewProvider, (_, _) {});
    final composer = container.listen(
      composerDockViewProvider('thread-main'),
      (_, _) {},
    );
    addTearDown(workspace.close);
    addTearDown(status.close);
    addTearDown(composer.close);
    final canonical = initial.thread.copyWith(
      title: 'Completed canonical title',
      mode: ThreadModeId.task,
      status: ThreadStatusView.idle,
      updatedAt: initial.thread.updatedAt,
    );
    client.threadDirectory.applyDelta(
      revision: client.threadDirectory.state.revision + 1,
      upserted: [canonical],
      removed: const [],
    );
    // The directory frame can arrive before an already captured runtime
    // baseline. Unix-second timestamps cannot order these resource domains.
    session.applySnapshot(
      initial.copyWith(
        thread: initial.thread.copyWith(status: ThreadStatusView.running),
      ),
    );
    expect(client.findThread('thread-main'), same(canonical));
    final timeline = graph.timeline;
    final facts = queryStudioDriverFacts(client, timeline: timeline);
    final json =
        jsonDecode(StudioDriverState.snapshotJson(observed: facts)) as Map;
    expect((json['workspace'] as Map)['threadStatus'], 'idle');
    // 展示事实来自当前展示代次的真实消息集合，不从状态流猜测。
    expect(facts.timeline, isNotNull);
    expect(facts.timeline!.threadId, 'thread-main');
    expect(
      (json['timeline'] as Map)['itemCount'],
      facts.timeline!.items.length,
    );
    // 只读滚动几何：诊断请求现场读取，本测试没有挂载 Timeline 子树，因此几何是
    // nullable 空值而不是猜数或上一代快照。
    expect(facts.timeline!.ready, isTrue);
    expect(facts.timelineScroll, isNotNull);
    expect(facts.timelineScroll!.threadId, 'thread-main');
    expect(facts.timelineScroll!.generation, facts.timeline!.generation);
    expect(facts.timelineScroll!.pixels, isNull);
    expect(facts.timelineScroll!.maxScrollExtent, isNull);
    expect(facts.timelineScroll!.atLiveEdge, isFalse);
    expect(facts.timelineScroll!.isScrolling, isFalse);
    expect((json['timelineScroll'] as Map)['isScrolling'], isFalse);
    final generation = facts.timeline!.generation;
    await timeline.returnToLive('thread-main');
    final switched = queryStudioDriverFacts(client, timeline: timeline);
    expect(switched.timeline!.generation, greaterThan(generation));
    expect(switched.timeline!.threadId, 'thread-main');
    // 切代次后诊断仍读当前 lease 的真实身份，不残留上一代几何。
    expect(switched.timelineScroll, isNotNull);
    expect(switched.timelineScroll!.generation, switched.timeline!.generation);
    expect(switched.timelineScroll!.threadId, 'thread-main');
    expect(facts.workspace!.thread, same(canonical));
    expect(workspace.read()!.thread, same(canonical));
    expect(status.read()!.thread, same(canonical));
    expect(composer.read().thread, same(canonical));
  });

  test(
    'Driver reads current Client facts without creating any owner or lease',
    () async {
      final transport = _UnusedTransport();
      final client = AnyworkClient(
        transport: transport,
        clientId: 'driver-query',
      );
      final thread = StudioThread(
        id: 'thread',
        projectId: 'project',
        title: 'Original title',
        mode: ThreadModeId.simple,
        updatedAt: DateTime.utc(2026),
        workspacePath: '/tmp/thread',
      );
      client.threadDirectory.applyWindow(
        ThreadDirectoryWindow(threads: [thread], revision: 1),
      );
      final timeline = TimelineSessionOwner(client: client);
      addTearDown(timeline.close);
      bindStudioDriver(client, timeline: timeline);
      final usageBefore = client.budget.usage.length;
      final original = StudioDriverState.readFacts();
      expect(original.rootThreads.single.title, 'Original title');
      // 读诊断不建立展示 lease，也不打开会话。
      expect(original.timeline, isNull);
      expect(
        original.timelineScroll,
        isNull,
        reason: '没有展示 lease 就没有几何，也不回放上一代',
      );
      expect(timeline.lease('thread'), isNull);
      expect(client.sessionStates, isEmpty);
      expect(client.composerState('thread'), isNull);
      expect(client.ownedSkills, isEmpty);
      expect(client.ownedSessionCosts, isEmpty);
      expect(transport.calls, 0);

      client.threadDirectory.applyDelta(
        revision: 2,
        upserted: [thread.copyWith(title: 'Updated canonical title')],
        removed: const [],
      );
      final current = StudioDriverState.readFacts();
      expect(current.rootThreads.single.title, 'Updated canonical title');
      expect(original.rootThreads.single.title, 'Original title');
      expect(() => current.rootThreads.add(thread), throwsUnsupportedError);
      final json =
          jsonDecode(StudioDriverState.snapshotJson()) as Map<String, dynamic>;
      expect(json.containsKey('timelineScroll'), isTrue);
      expect(json['timelineScroll'], isNull);
      final directory = json['sidebarDirectory'] as Map<String, dynamic>;
      expect(directory['titles'], {'thread': 'Updated canonical title'});
      studioDriverTopicDiagnostics(client);
      expect(client.sessionStates, isEmpty);
      expect(client.composerState('thread'), isNull);
      expect(client.budget.usage.length, usageBefore);
      expect(
        transport.calls,
        0,
        reason: 'snapshot queries never create transport demand',
      );
      expect((await client.close()).complete, isTrue);
    },
  );

  test('timeline facts expose authoritative text channel and plan-confirmation bool', () async {
    final transport = _ScriptedTimelineTransport();
    final client = AnyworkClient(transport: transport, clientId: 'facts');
    addTearDown(
      () => client.close(
        deadline: DateTime.now().add(const Duration(seconds: 5)),
      ),
    );
    client.selection.markOpened();
    client.threadDirectory.applyBaseline(
      ThreadDirectoryPage(threads: [_factsThread()], revision: 1),
      revision: 1,
    );
    final timeline = TimelineSessionOwner(client: client);
    addTearDown(
      () => timeline.close(
        deadline: DateTime.now().add(const Duration(seconds: 5)),
      ),
    );
    client.workspace.selectThread('thread', projectId: 'project');
    await timeline.source.waitFor((state) => state?.generation != 0);

    bindStudioDriver(client, timeline: timeline);
    final json =
        jsonDecode(StudioDriverState.snapshotJson()) as Map<String, dynamic>;
    final items = (json['timeline'] as Map<String, dynamic>)['items'] as List;
    Map<String, dynamic> itemOf(String id) => items
        .cast<Map<String, dynamic>>()
        .firstWhere((item) => item['id'] == id);
    Map<String, dynamic>? userInputOf(String id) =>
        itemOf(id)['userInput'] as Map<String, dynamic>?;

    // 文本频道是权威判别事实：commentary 与 finalAnswer 不混，非文本为 null。
    expect(itemOf('cm')['channel'], 'commentary');
    expect(itemOf('fa')['channel'], 'finalAnswer');
    expect(itemOf('cm')['channel'], isNot(itemOf('fa')['channel']));
    expect(itemOf('tool')['channel'], isNull);
    // 两个文本条目的 kind 相同也必须靠 channel 区分，不能从 kind/文本推测。
    expect(itemOf('cm')['kind'], itemOf('fa')['kind']);

    // 普通问答：false + 无决定。
    expect(userInputOf('qa-normal')!['isPlanConfirmation'], isFalse);
    expect(userInputOf('qa-normal')!['planDecision'], isNull);
    // 待确认的计划同样是计划确认，且决定来自权威 getter。
    expect(userInputOf('qa-plan-pending')!['isPlanConfirmation'], isTrue);
    expect(userInputOf('qa-plan-pending')!['planDecision'], 'pending');
    // cancelled / approved 按权威 getter 直出。
    expect(userInputOf('qa-plan-cancelled')!['isPlanConfirmation'], isTrue);
    expect(userInputOf('qa-plan-cancelled')!['planDecision'], 'cancelled');
    expect(userInputOf('qa-plan-approved')!['isPlanConfirmation'], isTrue);
    expect(userInputOf('qa-plan-approved')!['planDecision'], 'approved');
    // 每个问答条目都始终输出该键（固定 schema）。
    for (final id in const [
      'qa-normal',
      'qa-plan-pending',
      'qa-plan-cancelled',
      'qa-plan-approved',
    ]) {
      expect(userInputOf(id)!.containsKey('isPlanConfirmation'), isTrue);
      expect(userInputOf(id)!.containsKey('planDecision'), isTrue);
    }

    await timeline.close(
      deadline: DateTime.now().add(const Duration(seconds: 5)),
    );
    await client.close(
      deadline: DateTime.now().add(const Duration(seconds: 5)),
    );
  });
}

StudioThread _factsThread() => StudioThread(
  id: 'thread',
  projectId: 'project',
  title: 'Thread',
  mode: ThreadModeId.simple,
  updatedAt: DateTime.utc(2026),
  workspacePath: '/tmp/thread',
);

/// 受控最小 content connection：只交付一份首帧基线，尾部保持静默。
final class _FactsConnection implements StudioTimelineConnection {
  final Completer<StudioTimelineUpdate?> _pending = Completer();
  int closeCalls = 0;
  bool closed = false;

  @override
  Future<StudioTimelineBaseline> initial() async => _factsBaseline();

  @override
  Future<StudioTimelineUpdate?> next() => _pending.future;

  @override
  Future<StudioTimelinePage> page({String? before, int? limit}) async =>
      const StudioTimelinePage(items: [], before: null, hasOlder: false);

  @override
  Future<StudioTimelineDetailChunk> readDetail({
    required String itemId,
    required StudioTimelineDetailQuery query,
  }) async => StudioTimelineDetailChunk(
    itemId: itemId,
    field: query.field,
    revision: query.revision,
    text: '',
    totalBytes: 0,
    continuation: null,
  );

  @override
  void requestClose() {
    closed = true;
    if (!_pending.isCompleted) _pending.complete(null);
  }

  @override
  Future<void> close() async {
    closeCalls++;
    requestClose();
  }
}

final class _ScriptedTimelineTransport implements StudioTransport {
  int opens = 0;

  @override
  Future<StudioTimelineConnection> openTimeline(String threadId) async {
    opens++;
    return _FactsConnection();
  }

  @override
  Stream<ThreadStreamFrame> subscribeThread(String threadId) =>
      const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unused transport capability: ${invocation.memberName}',
  );
}

UserQuestionView _factsQuestion({required String id, String text = 'Q'}) =>
    UserQuestionView(
      id: id,
      header: 'Header',
      question: text,
      isOther: false,
      isSecret: false,
      options: const [],
    );

StudioTimelineItem _textItem(
  String id,
  int ordinal,
  ThreadTextChannel channel,
) => StudioTimelineItem(
  item: ThreadItemView(
    id: id,
    threadId: 'thread',
    turnId: 'turn',
    ordinal: ordinal,
    revision: 1,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    saved: true,
    executionTerminal: true,
    state: ThreadTextItemStateView(
      channel: channel,
      text: 'body-$id',
      attachments: const [],
      lifecycle: CompletedThreadContentView(DateTime.utc(2026)),
    ),
  ),
  saved: true,
  lifecycle: StudioTimelineLifecycle.terminal,
  omittedBytes: 0,
  details: const [],
);

StudioTimelineItem _toolItem(
  String id,
  int ordinal, {
  ThreadToolUserInputView? userInput,
}) => StudioTimelineItem(
  item: ThreadItemView(
    id: id,
    threadId: 'thread',
    turnId: 'turn',
    ordinal: ordinal,
    revision: 1,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    saved: true,
    executionTerminal: true,
    state: ThreadToolItemStateView(
      invocation: ThreadToolInvocationView(
        toolCallId: id,
        callId: id,
        name: 'ask_user',
        arguments: '{}',
      ),
      lifecycle: const RunningThreadToolView(''),
      userInput: userInput,
    ),
  ),
  saved: true,
  lifecycle: StudioTimelineLifecycle.streaming,
  omittedBytes: 0,
  details: const [],
);

StudioTimelineBaseline _factsBaseline() => StudioTimelineBaseline(
  subscriptionId: 'facts',
  version: 1,
  before: null,
  hasOlder: false,
  items: [
    _textItem('cm', 1, ThreadTextChannel.commentary),
    _textItem('fa', 2, ThreadTextChannel.finalAnswer),
    _toolItem('tool', 3),
    _toolItem(
      'qa-normal',
      4,
      userInput: ThreadToolUserInputView(
        interactionId: 'normal',
        questions: [_factsQuestion(id: 'q1')],
        state: const ResolvedThreadToolUserInputView([
          ThreadUserInputAnswerView(questionId: 'q1', answers: ['A']),
        ]),
      ),
    ),
    _toolItem(
      'qa-plan-pending',
      5,
      userInput: ThreadToolUserInputView(
        interactionId: 'plan-pending',
        questions: [
          _factsQuestion(
            id: agentSessionPlanConfirmationQuestionId,
            text: '# Plan',
          ),
        ],
        state: const PendingThreadToolUserInputView(),
      ),
    ),
    _toolItem(
      'qa-plan-cancelled',
      6,
      userInput: ThreadToolUserInputView(
        interactionId: 'plan-cancelled',
        questions: [
          _factsQuestion(
            id: agentSessionPlanConfirmationQuestionId,
            text: '# Plan',
          ),
        ],
        state: const CancelledThreadToolUserInputView(),
      ),
    ),
    _toolItem(
      'qa-plan-approved',
      7,
      userInput: ThreadToolUserInputView(
        interactionId: 'plan-approved',
        questions: [
          _factsQuestion(
            id: agentSessionPlanConfirmationQuestionId,
            text: '# Plan',
          ),
        ],
        state: const ResolvedThreadToolUserInputView([
          ThreadUserInputAnswerView(
            questionId: agentSessionPlanConfirmationQuestionId,
            answers: [agentSessionPlanApproveAnswer],
          ),
        ]),
      ),
    ),
  ],
);
