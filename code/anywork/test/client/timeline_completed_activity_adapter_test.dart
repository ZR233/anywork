import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_group_adapter.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_group_models.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final completedAt = DateTime.utc(2026, 10, 29);
  ConversationItem atom({int? sealedAt, ConversationDescriptor? descriptor}) =>
      ConversationItem(
        header: ConversationItemHeader(
          id: 'completed',
          threadId: 'thread',
          turnId: 'turn',
          appendSeq: 7,
          sourceEffectSeq: 999,
          sealedAt: sealedAt,
        ),
        descriptor:
            descriptor ??
            ConversationThinkingDescriptor(
              outcome: ConversationContentCompleted(
                CompletedThreadContentView(completedAt),
              ),
            ),
        source: const ConversationContentSource(),
        fields: const [],
      );

  test('unknown seal time does not reject a completed thinking atom', () {
    final conversion = TimelineActivityGroupAdapter.convertItem(atom());
    expect(conversion, isA<TimelineActivityConverted>());
    final message = (conversion as TimelineActivityConverted).message;
    expect(message.createdAt, isNull);
    expect(message.completedAt, completedAt);
    expect(message.duration, isNull);
  });

  test(
    'completion sequence and seal time do not fabricate an execution start',
    () {
      final conversion = TimelineActivityGroupAdapter.convertItem(
        atom(sealedAt: 1_700_000_000),
      ) as TimelineActivityConverted;
      final message = conversion.message;
      expect(message.createdAt, isNull);
      expect(message.completedAt, completedAt);
      final group = TimelineActivityGroupController(initialMessages: [message]);
      expect(group.elapsedDuration, isNull);
      group.dispose();
    },
  );

  test('background receipt is a completed standalone receipt, not a running member', () {
    final conversion = TimelineActivityGroupAdapter.convertItem(
      atom(
        descriptor: ConversationToolDescriptor(
          invocation: const ConversationToolInvocation(
            toolCallId: 'call',
            name: 'exec',
            taskId: 'task',
          ),
          state: ConversationToolBackgroundStarted(startedAt: completedAt),
        ),
      ),
    );
    expect(conversion, isA<TimelineActivityConversionRejected>());
    expect(
      (conversion as TimelineActivityConversionRejected).reason,
      TimelineActivityRejectionReason.standaloneToolItem,
    );
  });
}
