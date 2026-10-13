import 'package:flutter_test/flutter_test.dart';

import 'package:anywork/src/data/frb/studio_api.dart';
import 'package:anywork/src/data/stores/thread_session_state.dart';
import 'package:anywork/src/domain/models/studio_models.dart';

void main() {
  test('Patch 在 from 匹配时拒绝 to <= from', () {
    final state = _state(version: 4);
    final result = applyChatFrameState(
      state,
      const StudioChatPatch(from: 4, to: 4, changes: [], hasNewer: false),
    );
    expect(result.outcome, ChatFrameOutcome.resync);
    expect(result.state.chatVersion, 4);
    expect(identical(result.state.workspace, state.workspace), isTrue);
  });

  test('Patch from 落后且 to 不大于本地版本时丢弃', () {
    final state = _state(version: 4);
    final result = applyChatFrameState(
      state,
      const StudioChatPatch(from: 3, to: 4, changes: [], hasNewer: false),
    );
    expect(result.outcome, ChatFrameOutcome.irrelevant);
  });
}

ThreadSessionState _state({required int version}) {
  final now = DateTime.utc(2026, 1, 1);
  final thread = StudioThread(
    id: 'thread-main',
    projectId: 'project-local',
    title: 'Main',
    mode: ThreadModeId.simple,
    updatedAt: now,
    workspacePath: '/tmp/thread-main',
  );
  final item = ThreadItemView(
    id: 'item-1',
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
  );
  final workspace = ThreadWorkspace(
    thread: thread,
    revision: 1,
    items: [item],
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
