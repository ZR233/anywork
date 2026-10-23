import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/domain/models/agent_workspace_view.dart';
import 'package:anywork/src/domain/models/timeline_commands.dart';
import 'package:anywork/src/features/interaction/composer_view.dart';
import 'package:anywork/src/features/shell/shell_view.dart';
import 'package:anywork/src/features/status/status_view.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork/src/shared/studio_driver_projection.dart';
import 'package:anywork/src/shared/studio_driver_state.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_driver/timeline_observation.dart';
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
    // 正文经唯一 consumer 的可等待回调交付：领域 baseline 就绪先于展示代次发布，
    // Driver 快照要等 owner 真实 adopt 完成后再读。
    await graph.timeline.source.waitFor((state) => state?.generation != 0);
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
    final status = container.listen(
      statusBarViewProvider('thread-main'),
      (_, _) {},
    );
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

  test(
    'attachment facts keep canonical modality for user and tool items',
    () async {
      final transport = _ScriptedTimelineTransport(
        baseline: _attachmentBaseline,
      );
      final client = AnyworkClient(
        transport: transport,
        clientId: 'attachments',
      );
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
      final opensBefore = transport.opens;
      final facts = StudioDriverState.readFacts();
      expect(facts.timeline, isNotNull);
      final items = facts.timeline!.items;
      TimelineItemFacts itemOf(String id) =>
          items.firstWhere((item) => item.id == id);

      // 用户文本条目的附件：canonical enum 名、真实文件名与字节数，且不冒充工具产出。
      final userItem = itemOf('user');
      expect(userItem.tool, isNull);
      expect(userItem.attachments.map((attachment) => attachment.id), [
        'user-image',
        'user-file',
      ]);
      expect(userItem.attachments.map((attachment) => attachment.modality), [
        'image',
        'file',
      ]);
      expect(userItem.attachments.map((attachment) => attachment.filename), [
        'chart.png',
        'notes.txt',
      ]);
      expect(userItem.attachments.map((attachment) => attachment.byteSize), [
        2048,
        15,
      ]);
      expect(userItem.attachments.map((attachment) => attachment.source), [
        null,
        null,
      ]);

      // 工具条目的顶层附件行带工具来源标记；nested 工具诊断给同一批附件的原始事实。
      final toolItem = itemOf('tool-output');
      expect(toolItem.attachments.map((attachment) => attachment.id), [
        'tool-image',
        'tool-video',
      ]);
      expect(toolItem.attachments.map((attachment) => attachment.modality), [
        'image',
        'video',
      ]);
      expect(toolItem.attachments.map((attachment) => attachment.filename), [
        'shot.png',
        'clip.mp4',
      ]);
      expect(toolItem.attachments.map((attachment) => attachment.byteSize), [
        4096,
        8192,
      ]);
      expect(toolItem.attachments.map((attachment) => attachment.source), [
        'tool',
        'tool',
      ]);
      final tool = toolItem.tool!;
      expect(tool.name, 'bash');
      expect(tool.attachments.map((attachment) => attachment.id), [
        'tool-image',
        'tool-video',
      ]);
      expect(tool.attachments.map((attachment) => attachment.modality), [
        'image',
        'video',
      ]);
      expect(tool.attachments.map((attachment) => attachment.filename), [
        'shot.png',
        'clip.mp4',
      ]);
      expect(tool.attachments.map((attachment) => attachment.byteSize), [
        4096,
        8192,
      ]);
      expect(tool.attachments.map((attachment) => attachment.source), [
        null,
        null,
      ]);
      // 用户与工具附件身份不串：两侧 id 无交集。
      expect(
        toolItem.attachments
            .map((attachment) => attachment.id)
            .toSet()
            .intersection(
              userItem.attachments.map((attachment) => attachment.id).toSet(),
            ),
        isEmpty,
      );

      // 序列化诊断给同一批 canonical 值，键名保持不变。
      final json =
          jsonDecode(StudioDriverState.snapshotJson()) as Map<String, dynamic>;
      final jsonItems =
          ((json['timeline'] as Map<String, dynamic>)['items'] as List)
              .cast<Map<String, dynamic>>();
      Map<String, dynamic> jsonItemOf(String id) =>
          jsonItems.firstWhere((item) => item['id'] == id);
      expect(jsonItemOf('user')['attachments'], [
        {
          'id': 'user-image',
          'modality': 'image',
          'filename': 'chart.png',
          'byteSize': 2048,
        },
        {
          'id': 'user-file',
          'modality': 'file',
          'filename': 'notes.txt',
          'byteSize': 15,
        },
      ]);
      final jsonTool =
          jsonItemOf('tool-output')['tool'] as Map<String, dynamic>;
      expect(jsonItemOf('tool-output')['attachments'], [
        {
          'id': 'tool-image',
          'modality': 'image',
          'filename': 'shot.png',
          'byteSize': 4096,
          'source': 'tool',
        },
        {
          'id': 'tool-video',
          'modality': 'video',
          'filename': 'clip.mp4',
          'byteSize': 8192,
          'source': 'tool',
        },
      ]);
      expect(jsonTool['attachments'], [
        {
          'id': 'tool-image',
          'modality': 'image',
          'filename': 'shot.png',
          'byteSize': 4096,
        },
        {
          'id': 'tool-video',
          'modality': 'video',
          'filename': 'clip.mp4',
          'byteSize': 8192,
        },
      ]);
      final history =
          ((json['workspace'] as Map<String, dynamic>)['historyAttachments']
                  as List)
              .cast<Map<String, dynamic>>();
      expect(history.map((attachment) => attachment['id']), [
        'user-image',
        'user-file',
        'tool-image',
        'tool-video',
      ]);
      // 读诊断不制造新的内容订阅或 transport demand。
      expect(transport.opens, opensBefore);

      // 释放展示后诊断读不到上一代附件。
      await timeline.close(
        deadline: DateTime.now().add(const Duration(seconds: 5)),
      );
      expect(timeline.lease('thread'), isNull);
      final retired = StudioDriverState.readFacts();
      expect(retired.timeline, isNull);
      final retiredJson =
          jsonDecode(StudioDriverState.snapshotJson()) as Map<String, dynamic>;
      expect(retiredJson['timeline'], isNull);
      expect(
        ((retiredJson['workspace']
                    as Map<String, dynamic>)['historyAttachments']
                as List)
            .isEmpty,
        isTrue,
      );
      expect(transport.opens, opensBefore);
    },
  );

  test('workspace 模型诊断按已解析 route 的 accountId 与 modelId 选账号，不按裸 model id 猜', () {
    Map<String, dynamic> workspaceJsonFor(ThreadModelRouteView? route) {
      final json = jsonDecode(
        StudioDriverState.snapshotJson(
          observed: StudioDriverFacts(
            workspace: _identityWorkspace(route: route),
          ),
        ),
      ) as Map<String, dynamic>;
      return json['workspace'] as Map<String, dynamic>;
    }

    // 两个账号共用同一 modelId；只有 route 能说明当前模型属于哪个账号。
    final routed = workspaceJsonFor(_sharedModelRoute(accountId: 'acct-b'));
    expect(routed['modelAccount'], {
      'id': 'acct-b',
      'hasBearerToken': true,
      'credentialEnv': 'ACCT_B_KEY',
    });
    expect(routed['modelCapabilities'], ['text', 'image']);

    // 路由暂不可用仍保留身份：可用性不是身份选择依据。
    final unavailable = workspaceJsonFor(
      _sharedModelRoute(accountId: 'acct-b', available: false),
    );
    expect(
      (unavailable['modelAccount'] as Map<String, dynamic>)['id'],
      'acct-b',
    );
    expect(unavailable['modelCapabilities'], ['text', 'image']);

    // 路由缺失：保持 unknown，不按裸 model id 猜任意账号。
    final unrouted = workspaceJsonFor(null);
    expect(unrouted['modelAccount'], isNull);
    expect(unrouted['modelCapabilities'], isEmpty);

    // 未知账号：保持 unknown。
    final unknownAccount = workspaceJsonFor(
      _sharedModelRoute(accountId: 'acct-missing'),
    );
    expect(unknownAccount['modelAccount'], isNull);
    expect(unknownAccount['modelCapabilities'], isEmpty);

    // 路由指向的账号不含该模型：保持 unknown，不借用另一账号的同名模型。
    final crossAccount = workspaceJsonFor(
      _sharedModelRoute(accountId: 'acct-a'),
    );
    expect(crossAccount['modelAccount'], isNull);
    expect(crossAccount['modelCapabilities'], isEmpty);
  });

  test('初始连接失败保留安全 typed 诊断，不需要展示 lease', () async {
    final transport = _ScriptedTimelineTransport(
      failure: const StudioFailure(
        code: StudioFailureCode.unavailable,
        message: 'sentinel-message-must-not-leak',
        retryable: false,
        correlationId: 'corr-a1',
        detailsJson: '{"sentinel":"details-must-not-leak"}',
      ),
    );
    final client = AnyworkClient(
      transport: transport,
      clientId: 'connection-failure',
    );
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
    // 首基线前的真实失败：连接 failed、代次 0、没有展示 lease、没有条目。
    final failed = await timeline.source.waitFor(
      (state) => state?.connection == TimelineConnectionPhase.failed,
    );
    expect(failed!.generation, 0);
    expect(failed.connectionError, isNotNull);
    expect(timeline.lease('thread'), isNull);

    bindStudioDriver(client, timeline: timeline);
    final opens = transport.opens;
    final json =
        jsonDecode(StudioDriverState.snapshotJson()) as Map<String, dynamic>;
    final plain = json['timeline'] as Map<String, dynamic>;
    // 四个键在 timeline 对象存在时始终存在，缺键不是合法 null。
    for (final key in _connectionErrorKeys) {
      expect(plain.containsKey(key), isTrue, reason: '$key 必须在 timeline 中始终存在');
    }
    expect(plain['connection'], 'failed');
    expect(plain['generation'], 0);
    expect(plain['ready'], isFalse);
    expect(plain['itemCount'], 0);
    expect(plain['connectionErrorType'], 'StudioFailure');
    expect(plain['connectionErrorCode'], 'unavailable');
    expect(plain['connectionErrorRetryable'], isFalse);
    expect(plain['connectionErrorCorrelationId'], 'corr-a1');
    // 隐私边界：message 与 detailsJson 不进入诊断。
    final encoded = jsonEncode(plain);
    expect(encoded.contains('sentinel-message-must-not-leak'), isFalse);
    expect(encoded.contains('details-must-not-leak'), isFalse);
    // 同一份真实快照进入严格 Driver parser，不另建 facts 回读。
    final observation = TimelineObservation.parse(json);
    expect(observation.ready, isFalse);
    expect(observation.connection, 'failed');
    expect(observation.generation, 0);
    expect(observation.itemCount, 0);
    // typed 身份原样来自当前 error：false 不降级为 null，correlation 不重新发明。
    expect(observation.connectionErrorType, 'StudioFailure');
    expect(observation.connectionErrorCode, 'unavailable');
    expect(observation.connectionErrorRetryable, isFalse);
    expect(observation.connectionErrorCorrelationId, 'corr-a1');

    // 读诊断不制造 transport demand 或会话。
    StudioDriverState.readFacts();
    expect(transport.opens, opens);

    // 选择离开当前 Thread 后诊断不残留上一次失败。
    client.selection.beginNewThread();
    final cleared =
        jsonDecode(StudioDriverState.snapshotJson()) as Map<String, dynamic>;
    expect(cleared['timeline'], isNull);
  });

  test('未知连接异常只保留运行时类型，不调用其 toString 或替身 typed 身份', () async {
    final transport = _ScriptedTimelineTransport(
      failure: _UnprintableTimelineFailure(),
    );
    final client = AnyworkClient(
      transport: transport,
      clientId: 'connection-unknown',
    );
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
    // 未知异常不是 typed 失败：通道按可重试收束，最终仍以同一对象 failed。
    final failed = await timeline.source.waitFor(
      (state) => state?.connection == TimelineConnectionPhase.failed,
    );
    expect(failed!.connectionError, isA<_UnprintableTimelineFailure>());
    expect(timeline.lease('thread'), isNull);

    bindStudioDriver(client, timeline: timeline);
    final json =
        jsonDecode(StudioDriverState.snapshotJson()) as Map<String, dynamic>;
    final plain = json['timeline'] as Map<String, dynamic>;
    // 运行时类型名来自 Dart 类型元数据；异常自身的 toString 必须不被调用。
    expect(plain['connectionErrorType'], '_UnprintableTimelineFailure');
    expect(plain['connectionErrorCode'], isNull);
    expect(plain['connectionErrorRetryable'], isNull);
    expect(plain['connectionErrorCorrelationId'], isNull);
    final observation = TimelineObservation.parse(json);
    expect(observation.connection, 'failed');
    expect(observation.connectionErrorType, '_UnprintableTimelineFailure');
    expect(observation.connectionErrorCode, isNull);
    expect(observation.connectionErrorRetryable, isNull);
    expect(observation.connectionErrorCorrelationId, isNull);
  });

  test('无连接错误时四项为 null，parser 拒绝缺键与类型错误并接受 null', () async {
    final transport = _ScriptedTimelineTransport();
    final client = AnyworkClient(transport: transport, clientId: 'no-error');
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
    final opens = transport.opens;
    final json =
        jsonDecode(StudioDriverState.snapshotJson()) as Map<String, dynamic>;
    final plain = json['timeline'] as Map<String, dynamic>;
    for (final key in _connectionErrorKeys) {
      expect(plain.containsKey(key), isTrue, reason: '$key 必须在 timeline 中始终存在');
      expect(plain[key], isNull, reason: '无错误时 $key 是未知，不是 internal');
    }

    // 同一份真实快照的负向矩阵：缺键与错误类型都是观测失败。
    final missing = Map<String, dynamic>.from(plain)
      ..remove('connectionErrorCode');
    expect(
      () => TimelineObservation.parse(_withTimeline(json, missing)),
      throwsStateError,
      reason: '缺键不能静默当作 null',
    );
    final mismatched = <String, Object?>{
      'connectionErrorType': 7,
      'connectionErrorCode': 5,
      'connectionErrorRetryable': 'false',
      'connectionErrorCorrelationId': 1.5,
    };
    for (final entry in mismatched.entries) {
      final mutated = Map<String, dynamic>.from(plain)
        ..[entry.key] = entry.value;
      expect(
        () => TimelineObservation.parse(_withTimeline(json, mutated)),
        throwsStateError,
        reason: '${entry.key} 的类型不符必须拒绝',
      );
    }
    // 合法 null 被接受：未知或无错误不等于缺键。
    final nulled = Map<String, dynamic>.from(plain)
      ..['connectionErrorType'] = null
      ..['connectionErrorCode'] = null
      ..['connectionErrorRetryable'] = null
      ..['connectionErrorCorrelationId'] = null;
    final parsed = TimelineObservation.parse(_withTimeline(json, nulled));
    expect(parsed.connection, 'ready');
    expect(parsed.ready, isTrue);
    expect(parsed.connectionErrorType, isNull);
    expect(parsed.connectionErrorCode, isNull);
    expect(parsed.connectionErrorRetryable, isNull);
    expect(parsed.connectionErrorCorrelationId, isNull);
    expect(transport.opens, opens);
  });
}

const _connectionErrorKeys = <String>[
  'connectionErrorType',
  'connectionErrorCode',
  'connectionErrorRetryable',
  'connectionErrorCorrelationId',
];

/// 替换诊断快照里的 `timeline` 对象，用于严格 parser 的负向矩阵。
Map<String, dynamic> _withTimeline(
  Map<String, dynamic> snapshot,
  Map<String, dynamic> timeline,
) => Map<String, dynamic>.from(snapshot)..['timeline'] = timeline;

/// 非 typed 连接异常：任何对它的 `toString()` 都是正文泄漏或额外推断。
final class _UnprintableTimelineFailure implements Exception {
  @override
  String toString() => throw StateError('sentinel-message-must-not-be-read');
}

StudioThread _factsThread() => StudioThread(
  id: 'thread',
  projectId: 'project',
  title: 'Thread',
  mode: ThreadModeId.simple,
  updatedAt: DateTime.utc(2026),
  workspacePath: '/tmp/thread',
);

ThreadModelRouteView _sharedModelRoute({
  required String accountId,
  bool available = true,
}) => ThreadModelRouteView(
  accountId: accountId,
  modelId: 'shared-model',
  effort: 'high',
  revision: 3,
  available: available,
);

/// 同名模型同时存在于两个账号：能力与凭据环境不同，展示诊断只能按已解析的
/// `(accountId, modelId)` 路由取账号，不能按裸 model id 取第一个命中。
AgentWorkspaceView _identityWorkspace({required ThreadModelRouteView? route}) {
  final thread = _factsThread();
  return AgentWorkspaceView(
    thread: thread,
    rootThread: thread,
    syncState: AgentWorkspaceSyncState.ready,
    loadError: null,
    todo: null,
    runtime: ThreadRuntimeView(
      modelId: 'shared-model',
      contextTokens: 0,
      contextWindow: 128000,
      totalTokens: 0,
      costLabel: '',
      activeSkills: const [],
      activeMcpServers: const [],
      activeLspServers: const [],
      modelRoute: route,
    ),
    turn: null,
    lastTurn: null,
    activeInteraction: null,
    composer: const ComposerThreadState.idle(),
    composerMode: AgentComposerMode.editable,
    accounts: const [
      AccountSettingsView(
        id: 'acct-a',
        name: 'Account A',
        baseUrl: 'http://a.invalid',
        credentialEnv: 'ACCT_A_KEY',
        defaultModelId: 'a-only',
        models: [
          AccountModelView(
            modelId: 'a-only',
            displayName: 'A Only',
            reasoningEfforts: ['medium'],
            inputCapabilities: [
              ModelInputCapabilityView(
                modality: ModelModalityView.text,
                sources: [ModelInputSourceView.local],
              ),
            ],
          ),
        ],
        status: 'ready',
        usageLabel: '',
      ),
      AccountSettingsView(
        id: 'acct-b',
        name: 'Account B',
        baseUrl: 'http://b.invalid',
        hasBearerToken: true,
        credentialEnv: 'ACCT_B_KEY',
        defaultModelId: 'shared-model',
        models: [
          AccountModelView(
            modelId: 'shared-model',
            displayName: 'Shared Model',
            reasoningEfforts: ['high'],
            inputCapabilities: [
              ModelInputCapabilityView(
                modality: ModelModalityView.text,
                sources: [ModelInputSourceView.local],
              ),
              ModelInputCapabilityView(
                modality: ModelModalityView.image,
                sources: [ModelInputSourceView.local],
              ),
            ],
          ),
        ],
        status: 'ready',
        usageLabel: '',
      ),
    ],
    roles: const [],
    agents: const [],
  );
}

/// 受控最小 content connection：只交付一份首帧基线，尾部保持静默。
final class _FactsConnection implements StudioTimelineConnection {
  _FactsConnection(this._baseline);

  final StudioTimelineBaseline Function() _baseline;
  final StreamController<StudioTimelineFeedFrame> _frames =
      StreamController<StudioTimelineFeedFrame>();
  int closeCalls = 0;
  bool closed = false;
  bool _claimed = false;
  String _deliveredSubscriptionId = '';

  @override
  Stream<StudioTimelineFeedFrame> get events {
    if (_claimed) {
      throw const StudioFailure(
        code: StudioFailureCode.conflict,
        message: 'The facts feed stream was already claimed',
        retryable: false,
        correlationId: 'facts-stream-conflict',
      );
    }
    _claimed = true;
    final baseline = _baseline();
    _deliveredSubscriptionId = baseline.subscriptionId;
    _frames.add(
      StudioTimelineFeedFrame.data(
        deliverySequence: 1,
        event: StudioTimelineFeedEvent.baseline(baseline: baseline),
      ),
    );
    return _frames.stream;
  }

  @override
  Future<void> ackThrough(int deliverySequence) async {}

  @override
  Future<StudioTimelinePage> page({String? before, int? limit}) async =>
      StudioTimelinePage(items: [], before: null, hasOlder: false);

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
    if (closed) return;
    closed = true;
    if (!_frames.isClosed) scheduleMicrotask(_frames.close);
  }

  @override
  Future<StudioFeedCloseReport> close() async {
    closeCalls++;
    requestClose();
    return StudioFeedCloseReport(
      feedId: _deliveredSubscriptionId,
      outcome: const StudioFeedCloseOutcome.clean(),
    );
  }
}

final class _ScriptedTimelineTransport implements StudioTransport {
  _ScriptedTimelineTransport({
    StudioTimelineBaseline Function()? baseline,
    this.failure,
  }) : _baseline = baseline ?? _factsBaseline;

  final StudioTimelineBaseline Function() _baseline;

  /// 打开连接的失败输入；为 null 时交付一份首帧基线。
  final Object? failure;
  int opens = 0;

  @override
  Future<StudioTimelineConnection> openTimeline(String threadId) async {
    opens++;
    final configured = failure;
    if (configured != null) throw configured;
    return _FactsConnection(_baseline);
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
  ThreadTextChannel channel, {
  List<ThreadAttachmentView> attachments = const [],
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
    state: ThreadTextItemStateView(
      channel: channel,
      text: 'body-$id',
      attachments: attachments,
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
  ThreadToolLifecycleView lifecycle = const RunningThreadToolView(''),
  StudioTimelineLifecycle itemLifecycle = StudioTimelineLifecycle.streaming,
  String name = 'ask_user',
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
        name: name,
        arguments: '{}',
      ),
      lifecycle: lifecycle,
      userInput: userInput,
    ),
  ),
  saved: true,
  lifecycle: itemLifecycle,
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

/// 用户输入附件与工具输出附件都用 SDK 的 typed DTO 准备，不做 dynamic 替身。
const _userImage = ThreadAttachmentView(
  id: 'user-image',
  modality: AttachmentModalityView.image,
  mediaType: 'image/png',
  byteSize: 2048,
  filename: 'chart.png',
);

const _userFile = ThreadAttachmentView(
  id: 'user-file',
  modality: AttachmentModalityView.file,
  mediaType: 'text/plain',
  byteSize: 15,
  filename: 'notes.txt',
);

const _toolImage = ThreadAttachmentView(
  id: 'tool-image',
  modality: AttachmentModalityView.image,
  mediaType: 'image/png',
  byteSize: 4096,
  filename: 'shot.png',
);

const _toolVideo = ThreadAttachmentView(
  id: 'tool-video',
  modality: AttachmentModalityView.video,
  mediaType: 'video/mp4',
  byteSize: 8192,
  filename: 'clip.mp4',
);

/// 用户条目带图片/文件附件，工具条目带真实成功输出附件：投影必须同时保留
/// 顶层附件行与 nested 工具附件，且 modality 是 canonical enum 名。
StudioTimelineBaseline _attachmentBaseline() => StudioTimelineBaseline(
  subscriptionId: 'attachments',
  version: 1,
  before: null,
  hasOlder: false,
  items: [
    _textItem(
      'user',
      1,
      ThreadTextChannel.user,
      attachments: const [_userImage, _userFile],
    ),
    _toolItem(
      'tool-output',
      2,
      name: 'bash',
      itemLifecycle: StudioTimelineLifecycle.terminal,
      lifecycle: SucceededThreadToolView(
        DateTime.utc(2026),
        const ThreadToolOutputView(
          result: 'ok',
          attachments: [_toolImage, _toolVideo],
          outputArtifacts: [],
        ),
      ),
    ),
  ],
);
