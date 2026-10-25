import 'dart:convert';

import 'package:anywork/src/diagnostics/contracts/timeline_diagnostics.dart';
import 'package:anywork/src/features/conversation/state/read_material.dart';
import 'package:anywork/src/features/conversation/state/thread_status_state.dart';
import 'package:anywork/src/features/conversation/view_models/conversation_view_model.dart';
import 'package:anywork/src/features/conversation/view_models/thread_status_view_model.dart';
import 'package:anywork/src/features/workspace/view_models/workspace_view_model.dart';
import 'package:anywork/src/shared/driver_snapshot.dart';
import 'package:anywork/src/shared/driver_snapshot_json.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/drafts.dart' show AttachmentModality;
import 'package:anywork_client/models.dart';
import 'package:anywork_client/modes.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../anywork_client/test/support/conversation_fixture.dart'
    show fixtureThread;
import '../../../anywork_client/test/support/timeline_transport.dart';
import '../../test_driver/timeline_observation.dart';
import 'support/driver_environment.dart';
import 'support/selector_conversation_port.dart';
import 'support/selector_directory_port.dart';

Future<DriverTestEnvironment> _environment({
  List<WorkspaceThreadRecord>? threads,
  List<AgentDirectoryEntry>? agents,
}) async {
  final env = DriverTestEnvironment();
  addTearDown(env.close);
  await env.establish(threads: threads ?? [_factsThread()], agents: agents);
  return env;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('canonical cold and closed members survive a root-only Thread page and cold selection', () async {
    final root = _factsThread();
    final other = root.copyWith(
      id: 'other-root',
      rootThreadId: 'other-root',
      projectId: 'foreign-project',
      title: 'Other project',
      workspacePath: '/other',
    );
    AgentDirectoryEntry agent(
      String id, {
      required String rootId,
      String? parent,
      AgentState state = const AgentState.idle(budgetPause: null),
      int depth = 0,
    }) => AgentDirectoryEntry(
      id: id,
      threadId: id,
      path: 'path-$id',
      parentPath: parent,
      rootThreadId: rootId,
      depth: depth,
      role: parent == null ? 'planner' : 'reviewer',
      task: 'Task $id',
      summary: null,
      state: state,
      updatedAt: root.updatedAt,
      delegationMode: DelegationMode.automatic,
      delegationPreference: DelegationPreference.economy,
      frozenModel: parent == null
          ? null
          : const ModelSelection(
              model: AccountModelKey(
                accountId: 'saved-account',
                modelId: 'saved-model',
              ),
              effort: 'high',
            ),
    );
    final members = [
      agent(root.id, rootId: root.id),
      agent(
        'cold-executor',
        rootId: root.id,
        parent: 'path-${root.id}',
        depth: 1,
        state: const AgentState.running(turnId: 'executor-turn'),
      ),
      agent(
        'cold-closed',
        rootId: root.id,
        parent: 'path-${root.id}',
        depth: 1,
        state: const AgentState.closed(),
      ),
      // The new native directory supplies the canonical root explicitly, while
      // preserving the exact opaque parent link and the original expected order.
      agent(
        'nested',
        rootId: root.id,
        parent: 'path-cold-closed',
        depth: 2,
        state: const AgentState.running(turnId: 'nested-turn'),
      ),
      agent(
        'faulted',
        rootId: root.id,
        parent: 'path-${root.id}',
        depth: 1,
        state: const AgentState.faulted(
          error: SourceStateError(
            code: 'saved-failure',
            message: 'Saved failure',
            retryable: false,
          ),
          turnId: null,
          classification: AgentFaultClassification.legacyUnknown,
        ),
      ),
      // Waiting for the SDK fix: this duplicate remains in the native input and
      // the old unique-member expectations below are not weakened or skipped.
      agent(
        'cold-closed',
        rootId: root.id,
        parent: 'path-${root.id}',
        depth: 1,
        state: const AgentState.closed(),
      ),
      agent(other.id, rootId: other.id),
      agent(
        'other-child',
        rootId: other.id,
        parent: 'path-${other.id}',
        depth: 1,
      ),
    ];
    final env = await _environment(threads: [root, other], agents: members);
    final graph = env.application.graph;
    graph.workspace.restoreSelection(
      WorkspaceSelection(
        projectId: root.projectId,
        threadId: root.id,
        needsOpen: true,
      ),
    );
    await env.mountDirectory();
    final before = env.nativeActivity;
    final facts = env.capture();
    expect(
      facts.agents?.map((a) => a.threadId),
      [root.id, 'cold-executor', 'cold-closed', 'nested', 'faulted'],
      reason: 'Waiting for SDK duplicate-member recovery; do not report Unknown as a successful empty directory',
    );
    expect(
      facts.directory!.where((t) => t.rootThreadId == root.id).map((t) => t.id),
      [root.id],
      reason: 'Member enumeration never fabricates missing Thread metadata',
    );
    expect(facts.agents!.first.frozenModel, isNull);
    expect(facts.agents![1].frozenModel?.model.modelId, 'saved-model');
    expect(
      AgentDirectoryQueries.menuOrder(facts.agents!).map((a) => a.threadId),
      ['cold-executor', 'nested', 'faulted', root.id, 'cold-closed'],
      reason: 'Status grouping keeps stable canonical order inside each group',
    );
    expect(env.capture().agents!.map((a) => a.threadId), [
      root.id,
      'cold-executor',
      'cold-closed',
      'nested',
      'faulted',
    ]);
    graph.workspace.restoreSelection(
      WorkspaceSelection(
        projectId: root.projectId,
        threadId: 'cold-closed',
        needsOpen: true,
      ),
    );
    final cold = env.capture();
    expect(
      cold.directory!.where((t) => t.id == cold.rootThreadId).single.id,
      root.id,
      reason: 'Typed agent root identity is sufficient even before child Thread metadata arrives',
    );
    expect(cold.selection.threadId, 'cold-closed');
    expect(
      AgentDirectoryQueries.rootThreadId(
        threadId: cold.selection.threadId,
        directory: graph.workspace.agents.value,
      ),
      root.id,
    );
    expect(cold.agents!.map((a) => a.threadId), [
      root.id,
      'cold-executor',
      'cold-closed',
      'nested',
      'faulted',
    ]);
    expect(env.knownSessions, isEmpty);
    expect(
      env.nativeActivity,
      before,
      reason:
          'Enumeration and cold navigation restore cannot load child sessions',
    );
    graph.workspace.restoreSelection(
      WorkspaceSelection(
        projectId: other.projectId,
        threadId: other.id,
        needsOpen: true,
      ),
    );
    expect(env.capture().agents!.map((a) => a.threadId), [
      other.id,
      'other-child',
    ]);
    graph.workspace.restoreSelection(
      WorkspaceSelection(
        projectId: root.projectId,
        threadId: 'cold-closed',
        needsOpen: true,
      ),
    );
    await env.removeDirectoryThread(root.id);
    final removed = env.capture();
    expect(removed.directory!.where((t) => t.id == root.id), isEmpty);
    expect(removed.directory!.where((t) => t.rootThreadId == root.id), isEmpty);
    expect(removed.agents!.map((a) => a.threadId), [
      root.id,
      'cold-executor',
      'cold-closed',
      'nested',
      'faulted',
    ], reason: 'Even root metadata availability is not a membership condition');
    expect(removed.rootThreadId, root.id);
    expect(env.knownSessions, isEmpty);
    expect(env.nativeActivity, before);
  });

  test(
    'canonical saved agent routes retain selection without activating children',
    () async {
      const frozen = ModelSelection(
        model: AccountModelKey(accountId: 'account-b', modelId: 'shared'),
        effort: 'high',
      );
      final root = _factsThread();
      final child =
          fixtureThread(
            'child',
            parentThreadId: root.id,
            role: 'reviewer',
          ).copyWith(
            title: 'Review final changes',
            mode: ThreadModeId.task,
            delegationMode: DelegationMode.automatic,
            delegationPreference: DelegationPreference.economy,
            frozenModel: frozen,
            workspacePath: '/project',
          );
      final savedRoot = SelectorDirectoryPort.agentEntry(root);
      AgentDirectoryEntry saved(AgentState state) =>
          SelectorDirectoryPort.agentEntry(
            child,
          ).copyWith(path: child.id, parentPath: root.agentPath, state: state);
      final env = await _environment(
        threads: [root, child],
        agents: [savedRoot, saved(const AgentState.idle(budgetPause: null))],
      );
      final graph = env.application.graph;
      graph.workspace.restoreSelection(
        WorkspaceSelection(
          projectId: root.projectId,
          threadId: child.id,
          needsOpen: true,
        ),
      );
      final before = env.nativeActivity;
      final facts = env.capture();
      expect(
        facts.agents!.where((a) => a.threadId == child.id).single.frozenModel,
        frozen,
      );
      expect(graph.conversation.existingSession(child.id), isNull);
      final cold = AgentDirectoryQueries.forRoot(
        rootThreadId: root.id,
        directory: graph.workspace.agents.value,
      ).where((a) => a.threadId == child.id).single;
      await env.application.domains.directory.publishAgents([
        savedRoot,
        saved(const AgentState.running(turnId: 'turn')),
      ]);
      await env.waitAgents();
      expect(
        AgentDirectoryQueries.forRoot(
          rootThreadId: root.id,
          directory: graph.workspace.agents.value,
        ).where((a) => a.threadId == child.id).single.frozenModel,
        frozen,
      );
      await env.application.domains.directory.publishAgents([
        savedRoot,
        saved(const AgentState.closed()),
      ]);
      await env.waitAgents();
      final closed = AgentDirectoryQueries.forRoot(
        rootThreadId: root.id,
        directory: graph.workspace.agents.value,
      ).where((a) => a.threadId == child.id).single;
      expect(cold.frozenModel, frozen);
      expect(closed.frozenModel, frozen);
      expect(closed.delegationPreference, DelegationPreference.economy);
      expect(graph.workspace.state.value.selection.threadId, child.id);
      expect(
        env.nativeActivity,
        before,
        reason: 'Fallback/Driver reads cannot fetch or activate a cold child',
      );
      expect(
        AgentDirectoryQueries.forRoot(
          rootThreadId: root.id,
          directory: graph.workspace.agents.value,
        ).first.frozenModel,
        isNull,
        reason: 'No saved model remains genuinely unknown, never filled from a current Profile',
      );
    },
  );

  test(
    'workspace and Driver join current directory identity after a Turn',
    () async {
      final thread = _factsThread().copyWith(
        id: 'thread-main',
        rootThreadId: 'thread-main',
      );
      final env = await _environment(threads: [thread]);
      final domains = env.application.domains;
      final graph = env.application.graph;
      domains.conversationPort.initialStatus = ThreadStatus.running;
      await env.openContent(
        baseline(1, items: [timelineItem(1, threadId: thread.id)]),
        threadId: thread.id,
      );
      await env.mountDirectory();
      final container = env.application.container;
      final conversation = container.listen(
        conversationViewModelProvider(thread.id),
        (_, _) {},
      );
      final status = container.listen(
        threadStatusViewModelProvider(thread.id),
        (_, _) {},
      );
      addTearDown(conversation.close);
      addTearDown(status.close);
      await container.read(conversationViewModelProvider(thread.id).future);
      await container.read(threadStatusViewModelProvider(thread.id).future);
      final canonical = thread.copyWith(
        title: 'Completed canonical title',
        mode: ThreadModeId.task,
        status: ThreadStatus.idle,
        updatedAt: thread.updatedAt,
      );
      await domains.directory.publishThread(canonical);
      await env.waitDirectory(
        (facts) =>
            facts.thread?.title == canonical.title &&
            facts.thread?.mode == canonical.mode &&
            facts.conversation?.thread == canonical,
      );
      await domains.conversationPort.publishExecution(
        selectorExecution(status: ThreadStatus.running),
      );
      final workspaceRead =
          (container
                      .read(workspaceViewModelProvider)
                      .requireValue
                      .selectedMetadata!
                      .value!
                  as ReadyReadValue<WorkspaceThreadRecord, ProductEntityRef>)
              .current;
      final conversationRead =
          (conversation.read().requireValue.metadata!.value!
                  as ReadyReadValue<WorkspaceThreadRecord, ProductEntityRef>)
              .current;
      final current = workspaceRead.value;
      expect(
        current,
        canonical,
        reason: 'The canonical immutable native read has all original values',
      );
      expect(
        (
          conversationRead.origin,
          conversationRead.reference,
          conversationRead.value,
        ),
        (workspaceRead.origin, workspaceRead.reference, workspaceRead.value),
        reason: 'Independent metadata borrows retain the same current source, entity revision and full value',
      );
      final facts = env.capture();
      final json = jsonDecode(env.snapshotJson()) as Map;
      expect((json['workspace'] as Map)['threadStatus'], 'idle');
      expect(facts.display.timeline, isNotNull);
      expect(facts.display.timeline!.threadId, 'thread-main');
      expect(
        (json['timeline'] as Map)['itemCount'],
        facts.display.timeline!.items.length,
      );
      expect(facts.display.timeline!.ready, isTrue);
      expect(facts.display.timelineScroll, isNotNull);
      expect(facts.display.timelineScroll!.threadId, 'thread-main');
      expect(
        facts.display.timelineScroll!.generation,
        facts.display.timeline!.generation,
      );
      expect(facts.display.timelineScroll!.pixels, isNull);
      expect(facts.display.timelineScroll!.maxScrollExtent, isNull);
      expect(facts.display.timelineScroll!.atLiveEdge, isFalse);
      expect(facts.display.timelineScroll!.isScrolling, isFalse);
      expect((json['timelineScroll'] as Map)['isScrolling'], isFalse);
      final generation = facts.display.timeline!.generation;
      final returning = graph.timeline.returnLive(thread.id);
      final replacement = await domains.timeline.opened(1);
      replacement.result.complete(
        TestTimelineConnection(
          initial: baseline(
            2,
            subscriptionId: 'replacement',
            items: [timelineItem(2, threadId: thread.id)],
          ),
        ),
      );
      await returning;
      final switched = env.capture();
      expect(switched.display.timeline!.generation, greaterThan(generation));
      expect(switched.display.timeline!.threadId, 'thread-main');
      expect(switched.display.timelineScroll, isNotNull);
      expect(
        switched.display.timelineScroll!.generation,
        switched.display.timeline!.generation,
      );
      expect(switched.display.timelineScroll!.threadId, 'thread-main');
      expect(facts.thread, same(current));
      expect(
        (container
                    .read(workspaceViewModelProvider)
                    .requireValue
                    .selectedMetadata!
                    .value!
                as ReadyReadValue<WorkspaceThreadRecord, ProductEntityRef>)
            .current
            .value,
        same(current),
      );
      expect(
        container
            .read(threadStatusViewModelProvider(thread.id).notifier)
            .modelRouteProps(conversation.read().requireValue.metadata)
            .thread,
        same(conversationRead.value),
      );
      // ConversationInputConnector now owns metadata; ComposerVM intentionally
      // owns only its Draft. Its actual ConversationVM input must use this same
      // current metadata rather than an execution snapshot's stale Thread copy.
      expect(
        conversation.read().requireValue.thread,
        same(conversationRead.value),
      );
    },
  );

  test(
    'Driver reads current Client facts without creating any owner or lease',
    () async {
      final thread = _factsThread().copyWith(title: 'Original title');
      final env = await _environment(threads: [thread]);
      final graph = env.application.graph;
      graph.workspace.restoreSelection(
        const WorkspaceSelection(
          projectId: 'project',
          threadId: 'thread',
          needsOpen: true,
        ),
      );
      await env.mountDirectory();
      await pumpEventQueue();
      final usageBefore = graph.budget.usage.length;
      final nativeBefore = env.nativeActivity;
      final original = env.capture();
      expect(original.directory!.single.title, 'Original title');
      expect(original.display.timeline, isNull);
      expect(
        original.display.timelineScroll,
        isNull,
        reason: '没有展示 lease 就没有几何，也不回放上一代',
      );
      expect(graph.timeline.display('thread'), isNull);
      expect(env.knownSessions, isEmpty);
      expect(
        graph.budget.usage.where((usage) => usage.kind == ResourceKind.draft),
        isEmpty,
      );
      expect(env.application.skillsPort.openedProjects, isEmpty);
      expect(
        graph.budget.usage.where(
          (usage) => usage.owner.contains('session-cost'),
        ),
        isEmpty,
      );
      expect(env.nativeActivity, nativeBefore);
      await env.application.domains.directory.publishThread(
        thread.copyWith(title: 'Updated canonical title'),
      );
      await env.waitDirectory(
        (facts) =>
            facts.directory?.singleOrNull?.title == 'Updated canonical title',
      );
      await pumpEventQueue();
      final currentNativeBefore = env.nativeActivity;
      final current = env.capture();
      expect(current.directory!.single.title, 'Updated canonical title');
      expect(original.directory!.single.title, 'Original title');
      expect(() => current.directory!.add(thread), throwsUnsupportedError);
      final json = jsonDecode(env.snapshotJson()) as Map<String, dynamic>;
      expect(json.containsKey('timelineScroll'), isTrue);
      expect(json['timelineScroll'], isNull);
      final directory = json['sidebarDirectory'] as Map<String, dynamic>;
      expect(directory['titles'], {'thread': 'Updated canonical title'});
      env.capture();
      expect(env.knownSessions, isEmpty);
      expect(
        graph.budget.usage.where((usage) => usage.kind == ResourceKind.draft),
        isEmpty,
      );
      expect(graph.budget.usage.length, usageBefore);
      expect(
        env.nativeActivity,
        currentNativeBefore,
        reason: 'snapshot queries never create transport demand',
      );
      await env.close();
      expect(graph.budget.usage, isEmpty);
    },
  );

  test('timeline facts expose authoritative text channel and plan-confirmation bool', () async {
    final env = await _environment();
    await env.openContent(_factsBaseline());
    final timeline = env.application.graph.timeline;
    final json = jsonDecode(env.snapshotJson()) as Map<String, dynamic>;
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
  });

  test(
    'attachment facts keep canonical modality for user and tool items',
    () async {
      final env = await _environment();
      await env.openContent(_attachmentBaseline());
      final timeline = env.application.graph.timeline;
      final opensBefore = env.application.domains.timeline.requests.length;
      final facts = env.capture();
      expect(facts.display.timeline, isNotNull);
      final items = facts.display.timeline!.items;
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
      final json = jsonDecode(env.snapshotJson()) as Map<String, dynamic>;
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
      expect(env.application.domains.timeline.requests.length, opensBefore);

      // 释放展示后诊断读不到上一代附件。
      await timeline.close(
        deadline: DateTime.now().add(const Duration(seconds: 5)),
      );
      expect(timeline.display('thread'), isNull);
      final retired = env.capture();
      expect(retired.display.timeline, isNull);
      final retiredJson =
          jsonDecode(env.snapshotJson()) as Map<String, dynamic>;
      expect(retiredJson['timeline'], isNull);
      expect(
        ((retiredJson['workspace']
                    as Map<String, dynamic>)['historyAttachments']
                as List)
            .isEmpty,
        isTrue,
      );
      expect(env.application.domains.timeline.requests.length, opensBefore);
    },
  );

  test(
    'workspace 模型诊断按已解析 route 的 accountId 与 modelId 选账号，不按裸 model id 猜',
    () async {
      final env = await _environment();
      final base = env.capture();
      Map<String, dynamic> workspaceJsonFor(ModelRouteReadValue? route) =>
          jsonDecode(
                jsonEncode(_identitySnapshot(base, route).toJson()),
              )['workspace']
              as Map<String, dynamic>;

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
    },
  );

  test('初始连接失败保留安全 typed 诊断，不需要展示 lease', () async {
    final env = await _environment();
    final timeline = env.application.graph.timeline;
    await env.failOpening(
      const StudioFailure(
        code: StudioFailureCode.unavailable,
        message: 'sentinel-message-must-not-leak',
        retryable: false,
        correlationId: 'corr-a1',
        details: StudioFailureDetails.reason(reason: 'details-must-not-leak'),
      ),
    );
    // 首基线前的真实失败：连接 failed、代次 0、没有展示 lease、没有条目。
    final failed = await env.timelineWhere(
      (state) => state?.connectionPhase == TimelineConnectionPhase.failed,
    );
    expect(failed!.generation, 0);
    expect(failed.connectionError, isNotNull);
    expect(timeline.display('thread'), isNull);

    final opens = env.application.domains.timeline.requests.length;
    final json = jsonDecode(env.snapshotJson()) as Map<String, dynamic>;
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
    env.capture();
    expect(env.application.domains.timeline.requests.length, opens);

    // 选择离开当前 Thread 后诊断不残留上一次失败。
    env.application.graph.workspace.restoreSelection(
      const WorkspaceSelection(
        projectId: 'project',
        threadId: null,
        needsOpen: false,
      ),
    );
    final cleared = jsonDecode(env.snapshotJson()) as Map<String, dynamic>;
    expect(cleared['timeline'], isNull);
  });

  test('未知连接异常只保留运行时类型，不调用其 toString 或替身 typed 身份', () async {
    final env = await _environment();
    final timeline = env.application.graph.timeline;
    final original = _UnprintableTimelineFailure();
    await env.failOpening(original);
    // 未知异常不是 typed 失败：通道按可重试收束，最终仍以同一对象 failed。
    final failed = await env.timelineWhere(
      (state) => state?.connectionPhase == TimelineConnectionPhase.failed,
    );
    expect(failed!.connectionError, isA<_UnprintableTimelineFailure>());
    expect(failed.connectionError, same(original));
    expect(timeline.display('thread'), isNull);

    final json = jsonDecode(env.snapshotJson()) as Map<String, dynamic>;
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
    final env = await _environment();
    await env.openContent(_factsBaseline());
    final opens = env.application.domains.timeline.requests.length;
    final json = jsonDecode(env.snapshotJson()) as Map<String, dynamic>;
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
    expect(env.application.domains.timeline.requests.length, opens);
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

WorkspaceThreadRecord _factsThread() => fixtureThread('thread').copyWith(
  title: 'Thread',
  delegationMode: DelegationMode.profile,
  workspacePath: '/thread',
);

ModelRouteReadValue _sharedModelRoute({
  required String accountId,
  bool available = true,
}) => ModelRouteReadValue(
  botId: null,
  accountId: ReadText.inline(text: accountId),
  modelId: const ReadText.inline(text: 'shared-model'),
  effort: const ReadText.inline(text: 'high'),
  revision: 3,
  available: available,
  unavailableReason: null,
);

/// Immutable published input to the production Driver serializer, just as the
/// old identity test supplied a value projection rather than a fake Repository.
/// Unrelated values are borrowed from a fully real application assembly.
DriverSnapshot _identitySnapshot(
  DriverSnapshot base,
  ModelRouteReadValue? route,
) {
  final account = base.configuredAccounts!.first;
  final catalog = base.catalogAccounts!.first;
  final model = catalog.effectiveModels.first;
  final textInput = ModelInputCapability(
    modality: ModelModality.text,
    sources: const [ModelInputSource.local],
    maxCount: null,
    maxBytes: null,
    maxTotalBytes: null,
    maxWidth: null,
    maxHeight: null,
    mediaTypes: const [],
  );
  final imageInput = textInput.copyWith(modality: ModelModality.image);
  final configuration = base.configuration.copyWith(
    accounts: _publishedRows([
      account.copyWith(
        accountId: 'acct-a',
        name: 'Account A',
        bearerTokenEnv: 'ACCT_A_KEY',
      ),
      account.copyWith(
        accountId: 'acct-b',
        name: 'Account B',
        bearerTokenEnv: 'ACCT_B_KEY',
        hasBearerToken: true,
      ),
    ], base.configuration.projection.stamp!.origin),
  );
  final models = base.models.copyWith(
    accounts: _publishedRows([
      catalog.copyWith(
        accountId: 'acct-a',
        effectiveModels: [
          model.copyWith(
            modelId: 'a-only',
            capabilities: model.capabilities.copyWith(input: [textInput]),
          ),
        ],
      ),
      catalog.copyWith(
        accountId: 'acct-b',
        effectiveModels: [
          model.copyWith(
            modelId: 'shared-model',
            capabilities: model.capabilities.copyWith(
              input: [textInput, imageInput],
            ),
          ),
        ],
      ),
    ], base.models.projection.stamp!.origin),
  );
  final status = ThreadStatusViewState(
    threadId: 'thread',
    configurationRead: ReadMaterial(
      header: ThreadConfigurationReadHeader(
        scope: const ReadScopeIdentity(
          scopeId: 'driver-route',
          runtimeEpoch: 'driver-native',
          incarnation: 1,
          sourceRevision: 3,
        ),
        route: route,
        activeSkillCount: 0,
      ),
    ),
  );
  return DriverSnapshot(
    selection: const WorkspaceSelection(
      projectId: 'project',
      threadId: 'thread',
      needsOpen: false,
    ),
    project: base.project,
    thread: _factsThread(),
    rootThreadId: 'thread',
    directory: base.directory,
    directoryHasMore: base.directoryHasMore,
    agents: base.agents,
    agentDirectoryError: base.agentDirectoryError,
    execution: base.execution,
    metrics: base.metrics,
    context: base.context,
    threadConfiguration: base.threadConfiguration,
    authoring: base.authoring,
    interactions: base.interactions,
    startDraft: base.startDraft,
    composer: base.composer,
    configuration: configuration,
    models: models,
    operations: base.operations,
    persistence: base.persistence,
    recovery: base.recovery,
    updates: base.updates,
    startup: base.startup,
    display: base.display,
    conversation: base.conversation,
    status: status,
    plan: base.plan,
    bots: base.bots,
  );
}

CollectionMirror<T> _publishedRows<T>(
  List<T> values,
  ProductReadOrigin origin,
) {
  final references = [
    for (var index = 0; index < values.length; index++)
      ProductEntityRef(entry: index + 1, revision: 1),
  ];
  return CollectionMirror.current(
    window: CollectionWindow(
      origin: origin,
      reference: ProductCollectionRef(
        entry: 1,
        revision: 1,
        total: values.length,
      ),
      entries: references,
      rows: {
        for (var index = 0; index < values.length; index++)
          references[index].entry: ReadValue.ready(
            current: Materialized(
              origin: origin,
              reference: references[index],
              value: values[index],
            ),
          ),
      },
      continuation: const CollectionContinuation.end(),
      complete: true,
      loading: false,
      error: null,
    ),
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
    createdAt: 1767225600,
    updatedAt: 1767225600,
    saved: true,
    executionTerminal: true,
    state: ThreadTextItemStateView(
      channel: channel,
      text: 'body-$id',
      attachments: attachments,
      lifecycle: CompletedThreadContentView(1767225600),
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
    createdAt: 1767225600,
    updatedAt: 1767225600,
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
        state: ResolvedThreadToolUserInputView([
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
        state: ResolvedThreadToolUserInputView([
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
  modality: AttachmentModality.image,
  mediaType: 'image/png',
  byteSize: 2048,
  filename: 'chart.png',
);

const _userFile = ThreadAttachmentView(
  id: 'user-file',
  modality: AttachmentModality.file,
  mediaType: 'text/plain',
  byteSize: 15,
  filename: 'notes.txt',
);

const _toolImage = ThreadAttachmentView(
  id: 'tool-image',
  modality: AttachmentModality.image,
  mediaType: 'image/png',
  byteSize: 4096,
  filename: 'shot.png',
);

const _toolVideo = ThreadAttachmentView(
  id: 'tool-video',
  modality: AttachmentModality.video,
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
        1767225600,
        ThreadToolOutput(
          result: 'ok',
          attachments: [_toolImage, _toolVideo],
          outputArtifacts: [],
        ),
      ),
    ),
  ],
);
