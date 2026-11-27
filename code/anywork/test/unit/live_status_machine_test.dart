import 'package:anywork/src/features/conversation/timeline/timeline_views.dart';
import 'package:anywork_client/models.dart' as feed;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('projects flat 8-state machine with strict priority arbitration', () {
    final now = DateTime.utc(2026);
    const approval = feed.PendingInteraction(
      id: 'int-1',
      threadId: 'thread-main',
      turnId: 'turn-1',
      kind: feed.InteractionKind.toolApproval,
      title: 'Run shell',
      body: 'cargo test',
      payload: feed.UnknownInteractionPayload(),
    );
    final workingSnapshot = feed.LiveStatusSnapshot(
      revision: 1,
      phase: feed.LiveStatusWorking(
        items: [
          feed.WorkGroupToolCall(
            id: 'call:1',
            seq: 1,
            callId: '1',
            toolName: 'exec',
            status: 'completed',
            summary: 'cargo test',
            payloadJson: '{}',
            bodies: const [],
            startedAtMs: 100,
            finishedAtMs: 250,
          ),
        ],
        reasoningPreview: '分析状态机边界',
        startedAtMs: 100,
      ),
      attentions: const [],
      suppressedByInteraction: false,
    );

    // 1. Root interaction suppresses status bar -> LiveStatusHidden(suppressed: true)
    final rootHidden = LiveStatusMachine.project(
      'thread-main',
      workingSnapshot,
      receivedAt: now,
      interaction: approval,
      isChildThread: false,
    );
    expect(rootHidden.state, const LiveStatusHidden(suppressed: true));

    // 2. Child interaction projects into LiveStatusChildInteractionState
    final childView = LiveStatusMachine.project(
      'thread-child',
      workingSnapshot,
      receivedAt: now,
      interaction: approval,
      isChildThread: true,
    );
    expect(
      childView.state,
      const LiveStatusChildInteractionState(
        interactionId: 'int-1',
        payload: feed.UnknownInteractionPayload(),
      ),
    );

    // 3. Stopping beats Working/Streaming/Reconnecting
    final stoppingView = LiveStatusMachine.project(
      'thread-main',
      feed.LiveStatusSnapshot(
        revision: 2,
        phase: const feed.LiveStatusStopping(startedAtMs: 500),
        attentions: const [],
        suppressedByInteraction: false,
      ),
      receivedAt: now,
    );
    expect(stoppingView.state, const LiveStatusStoppingState(startedAtMs: 500));

    // 4. Reconnecting retains retry delay and attempt counters
    final retryView = LiveStatusMachine.project(
      'thread-main',
      feed.LiveStatusSnapshot(
        revision: 3,
        phase: const feed.LiveStatusReconnecting(
          attemptId: 'retry-1',
          message: 'Request failed',
          retryAfterMs: 2500,
          attempt: 2,
          maxAttempts: 5,
        ),
        attentions: const [],
        suppressedByInteraction: false,
      ),
      receivedAt: now,
    );
    expect(
      retryView.state,
      const LiveStatusReconnectingState(
        attemptId: 'retry-1',
        message: 'Request failed',
        retryAfterMs: 2500,
        attempt: 2,
        maxAttempts: 5,
      ),
    );

    // 5. Working passes through WorkGroupMember items including finishedAtMs
    final workingView = LiveStatusMachine.project(
      'thread-main',
      workingSnapshot,
      receivedAt: now,
    );
    final working = workingView.state as LiveStatusWorkingState;
    final mappedTool = working.items.single as feed.WorkGroupToolCall;
    expect(mappedTool.finishedAtMs, 250);
    expect(mappedTool.status, 'completed');
    expect(working.hasRunningCommand, isFalse);
    expect(working.reasoningPreview, '分析状态机边界');

    // 6. Alert arbitration picks highest single priority: storage > disconnected > approval
    final alertView = LiveStatusMachine.project(
      'thread-main',
      feed.LiveStatusSnapshot(
        revision: 4,
        phase: const feed.LiveStatusIdle(),
        attentions: const [
          feed.LiveAttention(id: 'a1', kind: 'approval', summary: 'exec'),
          feed.LiveAttention(id: 'd1', kind: 'disconnected', summary: '离线'),
        ],
        suppressedByInteraction: false,
      ),
      receivedAt: now,
      storageState: const feed.ThreadStorageStateView(
        fault: feed.ThreadHistoryFault.writeFailed,
        faultGeneration: 1,
        execution: feed.ThreadStorageExecution.paused,
        lastError: '磁盘写入失败',
      ),
    );
    expect(
      alertView.state,
      const LiveStatusAlertState(
        kind: LiveAlertKind.storageFault,
        detail: '磁盘写入失败',
        storage: feed.ThreadStorageStateView(
          fault: feed.ThreadHistoryFault.writeFailed,
          faultGeneration: 1,
          execution: feed.ThreadStorageExecution.paused,
          lastError: '磁盘写入失败',
        ),
      ),
    );

    // 7. Plain idle without alerts or interaction -> LiveStatusHidden(suppressed: false)
    final idleView = LiveStatusMachine.project(
      'thread-main',
      feed.LiveStatusSnapshot(
        revision: 5,
        phase: const feed.LiveStatusIdle(),
        attentions: const [],
        suppressedByInteraction: false,
      ),
      receivedAt: now,
    );
    expect(idleView.state, const LiveStatusHidden(suppressed: false));
  });

  test('storage severity comes from typed flags', () {
    const paused = feed.ThreadStorageExecution.paused;
    for (final (storage, expected) in [
      (null, LiveStorageSeverity.fault),
      (
        const feed.ThreadStorageStateView(
          execution: paused,
          pressurePaused: true,
        ),
        LiveStorageSeverity.pressure,
      ),
      (
        const feed.ThreadStorageStateView(execution: paused),
        LiveStorageSeverity.paused,
      ),
      (
        const feed.ThreadStorageStateView(
          execution: paused,
          resumeRequired: true,
        ),
        LiveStorageSeverity.resumeRequired,
      ),
      (
        const feed.ThreadStorageStateView(
          execution: paused,
          resumeRequired: true,
          canResume: true,
        ),
        LiveStorageSeverity.resumeReady,
      ),
    ]) {
      expect(
        LiveStorageSeverity.fromStorage(storage),
        expected,
        reason: expected.name,
      );
    }
  });
}
