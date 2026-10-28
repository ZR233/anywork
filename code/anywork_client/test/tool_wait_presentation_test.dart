import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/timeline_transport.dart';

void main() {
  test(
    'wait readiness is typed and not guessed from tool result text',
    () async {
      final fixture = ConversationFixture();
      final content = fixture.session().content;
      final item = ConversationItem(
        header: timelineItem(1).header,
        revision: 1,
        saved: false,
        lifecycle: ConversationLifecycle.terminal,
        descriptor: ConversationToolDescriptor(
          invocation: const ConversationToolInvocation(
            toolCallId: 'wait-call',
            name: 'wait',
          ),
          state: ConversationToolSucceeded(
            completedAt: DateTime.utc(2026),
            output: const ConversationToolOutputDescriptor(attachments: []),
          ),
          wait: const ThreadWaitPresentationView(
            intent: ThreadWaitEventsIntentView(
              targets: [
                ThreadWaitTargetView(
                  taskId: 'task:exec',
                  summary: 'still running',
                  status: ThreadWaitTargetStatusView.running,
                ),
              ],
              timeoutMs: 60000,
            ),
            state: ThreadWaitStateView.ready,
            messagesReady: true,
          ),
        ),
        fields: const [
          ConversationFieldPreview(
            field: ThreadToolResultFieldView(),
            text: '{opaque tool result}',
            totalBytes: 20,
          ),
        ],
      );
      final merged = content.mergeItem(item, item);
      final descriptor = merged.descriptor as ConversationToolDescriptor;
      expect(descriptor.wait!.messagesReady, isTrue);
      expect(descriptor.wait!.state, ThreadWaitStateView.ready);
      final intent = descriptor.wait!.intent as ThreadWaitEventsIntentView;
      expect(intent.targets.single.status, ThreadWaitTargetStatusView.running);
      expect(
        merged.fieldFor(const ThreadToolResultFieldView())!.text,
        '{opaque tool result}',
      );
      await fixture.close();
    },
  );

  test('timer and cancelled waits retain original typed state across saved acknowledgement', () async {
    final fixture = ConversationFixture();
    final content = fixture.session().content;
    final item = ConversationItem(
      header: timelineItem(1).header,
      revision: 1,
      descriptor: const ConversationToolDescriptor(
        invocation: ConversationToolInvocation(
          toolCallId: 'sleep-call',
          name: 'sleep',
        ),
        state: ConversationToolRunning(),
        wait: ThreadWaitPresentationView(
          intent: ThreadWaitTimerIntentView(durationMs: 10),
          state: ThreadWaitStateView.cancelled,
        ),
      ),
      saved: false,
      lifecycle: ConversationLifecycle.terminal,
      fields: const [],
    );
    final next = content.reduceItem(
      item,
      const ConversationUpdateItem(
        itemId: 'item',
        expectedRevision: 1,
        revision: 1,
        saved: true,
        lifecycle: ConversationLifecycle.terminal,
        fields: [],
      ),
    );
    final descriptor = next.descriptor as ConversationToolDescriptor;
    expect(descriptor.wait!.state, ThreadWaitStateView.cancelled);
    expect(
      (descriptor.wait!.intent as ThreadWaitTimerIntentView).durationMs,
      10,
    );
    expect(next.saved, isTrue);
    expect(descriptor.state, isA<ConversationToolRunning>());
    await fixture.close();
  });
}
