import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/timeline_transport.dart';

void main() {
  test(
    'completed wait preserves typed readiness independently of opaque output',
    () async {
      final fixture = ConversationFixture();
      final feed = await fixture.open();
      final item = ConversationItem(
        header: const ConversationItemHeader(
          id: 'wait',
          threadId: 'thread',
          appendSeq: 2,
        ),
        source: const ConversationContentSource(),
        descriptor: ConversationToolDescriptor(
          invocation: const ConversationToolInvocation(
            toolCallId: 'wait-call',
            name: 'wait',
          ),
          state: ConversationToolSucceeded(
            completedAt: DateTime.utc(2026),
            output: ConversationToolOutputDescriptor(attachments: const []),
          ),
          wait: ThreadWaitPresentationView(
            intent: ThreadWaitEventsIntentView(
              targets: const [
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
      await feed.deliver(
        ConversationUpdateEvent(
          update: ConversationBatch(
            subscriptionId: 'sub',
            timelineEpoch: 'epoch',
            fromSeq: 1,
            throughSeq: 2,
            items: [item],
          ),
        ),
      );
      final delivered =
          (fixture.consumers['thread']!.frames.last
                  as ConversationCompletedBatchFrame)
              .batch
              .items
              .single;
      final descriptor = delivered.descriptor as ConversationToolDescriptor;
      expect(descriptor.wait!.messagesReady, isTrue);
      expect(descriptor.wait!.state, ThreadWaitStateView.ready);
      expect(
        (descriptor.wait!.intent as ThreadWaitEventsIntentView)
            .targets
            .single
            .status,
        ThreadWaitTargetStatusView.running,
      );
      expect(
        delivered.fieldFor(const ThreadToolResultFieldView())!.text,
        '{opaque tool result}',
      );
      expect((await fixture.close()).complete, isTrue);
    },
  );

  test(
    'cancelled timer wait preserves its typed intent and terminal outcome',
    () async {
      final fixture = ConversationFixture();
      final feed = await fixture.open();
      final item = ConversationItem(
        header: const ConversationItemHeader(
          id: 'sleep',
          threadId: 'thread',
          appendSeq: 2,
        ),
        source: const ConversationContentSource(),
        descriptor: ConversationToolDescriptor(
          invocation: const ConversationToolInvocation(
            toolCallId: 'sleep-call',
            name: 'sleep',
          ),
          state: ConversationToolCancelled(
            cancelledAt: DateTime.utc(2026),
            reason: 'cancelled',
          ),
          wait: const ThreadWaitPresentationView(
            intent: ThreadWaitTimerIntentView(durationMs: 10),
            state: ThreadWaitStateView.cancelled,
          ),
        ),
        fields: const [],
      );
      await feed.deliver(
        ConversationUpdateEvent(
          update: ConversationBatch(
            subscriptionId: 'sub',
            timelineEpoch: 'epoch',
            fromSeq: 1,
            throughSeq: 2,
            items: [item],
          ),
        ),
      );
      final delivered =
          (fixture.consumers['thread']!.frames.last
                  as ConversationCompletedBatchFrame)
              .batch
              .items
              .single;
      final descriptor = delivered.descriptor as ConversationToolDescriptor;
      expect(descriptor.wait!.state, ThreadWaitStateView.cancelled);
      expect(
        (descriptor.wait!.intent as ThreadWaitTimerIntentView).durationMs,
        10,
      );
      expect(descriptor.state, isA<ConversationToolCancelled>());
      expect((await fixture.close()).complete, isTrue);
    },
  );
}
