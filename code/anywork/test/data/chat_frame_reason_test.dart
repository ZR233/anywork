import 'package:flutter_test/flutter_test.dart';

import 'package:anywork/src/data/frb/studio_api.dart';
import 'package:anywork/src/data/stores/chat_view_events.dart';
import 'package:anywork/src/data/stores/thread_session_state.dart';
import 'package:anywork/src/domain/models/studio_models.dart';

/// 逐事件观测的缺陷敏感度：只看 `framesResync=20` 无法定位「哪条校验失败」，
/// 因此每种拒绝路径都必须给出自己的原因。
void main() {
  // 每个用例前清空事件缓冲：失败信息里只应出现本用例的记录。
  setUp(ChatViewEvents.reset);

  test('Reset 早于已交付版本按 resetOlderThanDelivered 拒收', () {
    final state = _state(version: 5);
    final result = applyChatFrameState(
      state,
      StudioChatReset(_snapshot(version: 4)),
    );
    expect(result.outcome, ChatFrameOutcome.irrelevant);
    expect(result.reason, ChatFrameRejectReason.resetOlderThanDelivered);
  });

  test('Patch 基线与本地不一致时区分已交付与缺口', () {
    final state = _state(version: 5, items: const ['item-1']);
    final delivered = applyChatFrameState(
      state,
      const StudioChatPatch(from: 3, to: 5, changes: [], hasNewer: false),
    );
    expect(delivered.outcome, ChatFrameOutcome.irrelevant);
    expect(delivered.reason, ChatFrameRejectReason.patchAlreadyDelivered);

    final gap = applyChatFrameState(
      state,
      const StudioChatPatch(from: 3, to: 7, changes: [], hasNewer: false),
    );
    expect(gap.outcome, ChatFrameOutcome.resync);
    expect(gap.reason, ChatFrameRejectReason.patchGap);

    final ahead = applyChatFrameState(
      state,
      const StudioChatPatch(from: 9, to: 10, changes: [], hasNewer: false),
    );
    expect(ahead.outcome, ChatFrameOutcome.resync);
    expect(ahead.reason, ChatFrameRejectReason.patchFromMismatch);
  });

  test('Patch 非递增版本按 patchNonIncreasing 拒收', () {
    final state = _state(version: 4);
    final result = applyChatFrameState(
      state,
      const StudioChatPatch(from: 4, to: 4, changes: [], hasNewer: false),
    );
    expect(result.outcome, ChatFrameOutcome.resync);
    expect(result.reason, ChatFrameRejectReason.patchNonIncreasing);
  });

  test('splice 越界与窗口外 item 各自给出原因', () {
    final state = _state(version: 3, items: const ['item-1']);
    final splice = applyChatFrameState(
      state,
      const StudioChatPatch(
        from: 3,
        to: 4,
        hasNewer: false,
        changes: [StudioViewSplice(index: 5, remove: 1, items: [])],
      ),
    );
    expect(splice.outcome, ChatFrameOutcome.resync);
    expect(splice.reason, ChatFrameRejectReason.spliceOutOfRange);

    final missing = applyChatFrameState(
      state,
      const StudioChatPatch(
        from: 3,
        to: 4,
        hasNewer: false,
        changes: [
          StudioViewItemUpdate(
            itemId: 'item-404',
            expectedRevision: 1,
            revision: 2,
            omittedUnits: 0,
            saved: true,
            fields: [],
          ),
        ],
      ),
    );
    expect(missing.outcome, ChatFrameOutcome.resync);
    expect(missing.reason, ChatFrameRejectReason.itemNotInWindow);
  });

  test('已交付版本之后仍有更高版本的 item 提交不匹配', () {
    final state = _state(version: 3, items: const ['item-1']);
    final mismatch = applyChatFrameState(
      state,
      const StudioChatPatch(
        from: 3,
        to: 4,
        hasNewer: false,
        changes: [
          StudioViewItemUpdate(
            itemId: 'item-1',
            expectedRevision: 99,
            revision: 100,
            omittedUnits: 0,
            saved: true,
            fields: [],
          ),
        ],
      ),
    );
    expect(mismatch.outcome, ChatFrameOutcome.resync);
    expect(mismatch.reason, ChatFrameRejectReason.itemCommitMismatch);
  });
}

ThreadSessionState _state({
  required int version,
  List<String> items = const ['item-1'],
}) {
  final now = DateTime.utc(2026, 1, 1);
  final thread = StudioThread(
    id: 'thread-main',
    projectId: 'project-local',
    title: 'Main',
    mode: ThreadModeId.simple,
    updatedAt: now,
    workspacePath: '/tmp/thread-main',
  );
  final workspace = ThreadWorkspace(
    thread: thread,
    revision: 1,
    items: [
      for (final id in items)
        ThreadItemView(
          id: id,
          threadId: thread.id,
          turnId: 'turn-1',
          ordinal: 0,
          revision: 1,
          createdAt: now,
          updatedAt: now,
          state: ThreadTextItemStateView(
            channel: ThreadTextChannel.user,
            text: 'hello',
            attachments: const [],
            lifecycle: CompletedThreadContentView(now),
          ),
        ),
    ],
    interactions: const [],
    runtime: const ThreadRuntimeView(
      model: 'fixture',
      contextTokens: 0,
      contextWindow: 128000,
      totalTokens: 0,
      costLabel: '-',
      activeSkills: [],
      activeMcpServers: [],
      activeLspServers: [],
    ),
  );
  return ThreadSessionState(
    threadId: thread.id,
    workspace: workspace,
    hasSnapshot: true,
    hasChatWindow: true,
    chatVersion: version,
  );
}

StudioChatSnapshot _snapshot({required int version}) {
  return StudioChatSnapshot(
    version: version,
    items: const [],
    hasOlder: false,
    hasNewer: false,
    canExtendLatest: false,
    focusedItemId: null,
  );
}
