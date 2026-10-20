import 'package:test/test.dart';

import 'package:anywork_client/studio_client.dart';

/// Typed wait presentation must survive Client projection, preview merge and
/// field updates without Flutter parsing wait JSON.
void main() {
  final created = DateTime.fromMillisecondsSinceEpoch(1000);

  ThreadWaitPresentationView events({
    required ThreadWaitStateView state,
    bool? messagesReady,
    List<ThreadWaitTargetView>? targets,
  }) {
    return ThreadWaitPresentationView(
      intent: ThreadWaitEventsIntentView(
        targets:
            targets ??
            const [
              ThreadWaitTargetView(
                taskId: 'task:exec-1',
                toolName: 'exec',
                summary: 'cargo test',
                summaryTruncated: true,
                status: ThreadWaitTargetStatusView.running,
              ),
            ],
        timeoutMs: 60000,
      ),
      state: state,
      messagesReady: messagesReady,
    );
  }

  ThreadItemView toolItem({
    required ThreadWaitPresentationView? wait,
    int revision = 1,
    String arguments = '{"taskIds":["task:exec-1"],"timeoutMs":60000}',
    ThreadToolLifecycleView lifecycle = const RunningThreadToolView(''),
  }) {
    return ThreadItemView(
      id: 'tool:wait-1',
      threadId: 'thread-1',
      turnId: 'turn-1',
      ordinal: 4,
      revision: revision,
      createdAt: created,
      updatedAt: created,
      state: ThreadToolItemStateView(
        invocation: ThreadToolInvocationView(
          toolCallId: 'call-wait',
          name: 'wait',
          arguments: arguments,
        ),
        lifecycle: lifecycle,
        wait: wait,
      ),
    );
  }

  test('事件等待投影不把消息唤醒当成全部任务完成', () {
    final part = toolItem(
      wait: events(state: ThreadWaitStateView.ready, messagesReady: true),
      lifecycle: SucceededThreadToolView(
        created,
        const ThreadToolOutputView(
          result: '{"tasks":[],"messagesReady":true,"timedOut":false}',
          attachments: [],
          outputArtifacts: [],
        ),
      ),
    ).tool;

    expect(part?.wait, isNotNull);
    expect(part!.wait!.state, ThreadWaitStateView.ready);
    expect(part.wait!.messagesReady, isTrue);
    final intent = part.wait!.intent as ThreadWaitEventsIntentView;
    expect(intent.targets.single.taskId, 'task:exec-1');
    expect(intent.targets.single.status, ThreadWaitTargetStatusView.running);
  });

  test('权威条目修订保留轻量 wait DTO，不因参数预览裁剪丢失', () {
    final current = toolItem(
      wait: events(state: ThreadWaitStateView.waiting),
      arguments: '',
    );
    final incoming = toolItem(
      wait: events(
        state: ThreadWaitStateView.timedOut,
        targets: const [
          ThreadWaitTargetView(
            taskId: 'task:exec-1',
            toolName: 'exec',
            summary: 'cargo test',
            summaryTruncated: true,
            status: ThreadWaitTargetStatusView.running,
          ),
        ],
      ),
      revision: 1,
      arguments: '{"taskIds":["task:exec-1"],"timeoutMs":60000}',
      lifecycle: SucceededThreadToolView(
        created,
        const ThreadToolOutputView(
          result: '{"tasks":[],"messagesReady":false,"timedOut":true}',
          attachments: [],
          outputArtifacts: [],
        ),
      ),
    );

    final merged = current.convergeWith(incoming, omittedBytes: 0);
    expect(merged, isNotNull);
    expect(merged!.tool?.wait?.state, ThreadWaitStateView.timedOut);
    final intent = merged.tool!.wait!.intent as ThreadWaitEventsIntentView;
    expect(intent.timeoutMs, 60000);
    expect(intent.targets.single.summaryTruncated, isTrue);
  });

  test('字段更新只改参数正文，不丢 wait 身份', () {
    final current = toolItem(
      wait: events(state: ThreadWaitStateView.waiting),
      arguments: '',
    );
    final next = current.applyFieldUpdates(
      fields: const [
        ThreadFieldUpdateView(
          field: ThreadToolArgumentsFieldView(),
          change: ReplaceThreadFieldChangeView(
            '{"taskIds":["task:exec-1"],"timeoutMs":60000}',
          ),
        ),
      ],
      expectedRevision: 1,
      revision: 1,
      omittedUnits: 0,
      saved: true,
      terminal: false,
    );

    expect(next, isNotNull);
    expect(next!.tool?.wait?.state, ThreadWaitStateView.waiting);
    expect(next.tool?.arguments, contains('task:exec-1'));
  });
}
