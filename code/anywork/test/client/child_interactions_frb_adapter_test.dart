import 'package:anywork/src/infrastructure/frb/studio_api.dart';
import 'package:anywork/src/rust/api/studio/types/event.dart' as event_dto;
import 'package:anywork/src/rust/api/studio/types/product_topic.dart'
    as topic_dto;
import 'package:anywork/src/rust/api/studio/types/thread_stream.dart'
    as interaction_dto;
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('child collection FRB baseline and events retain host and frozen payload', () {
    const topic = ChildInteractionsTopic(hostThreadId: 'root');
    final snapshot = topic_dto.BridgeChildInteractionsState(
      hostThreadId: 'root',
      revision: BigInt.from(7),
      updatedAt: 43,
      items: [
        interaction_dto.BridgeChildInteractionSummary(
          childThreadId: 'child',
          interactionId: 'interaction',
          kind: 'userInput',
          revision: BigInt.from(23),
          interaction: interaction_dto.BridgeInteractionRequest(
            interactionId: 'interaction',
            scope: const interaction_dto.BridgeInteractionScope(
              threadId: 'child',
              turnId: 'turn',
              itemId: 'item',
              toolId: 'tool',
              agentPath: 'root/child',
            ),
            revision: BigInt.from(23),
            createdAt: 41,
            updatedAt: 43,
            content: interaction_dto.BridgeInteractionContent.userInput(
              questions: const [
                interaction_dto.BridgeUserQuestion(
                  id: 'question',
                  header: 'Credential',
                  question: 'Provide the test credential',
                  isOther: true,
                  isSecret: true,
                  options: null,
                ),
              ],
              state:
                  const interaction_dto.BridgeUserInputInteractionState.pending(
                    operationId: 'interaction',
                  ),
            ),
          ),
        ),
      ],
    );
    final baseline =
        productTopicFrameFromEnvelope(
              topic,
              topic_dto.BridgeProductTopicStreamEnvelope.baseline(
                topic: const topic_dto.BridgeProductTopic.childInteractions(
                  hostThreadId: 'root',
                ),
                revision: BigInt.from(7),
                state: topic_dto.BridgeProductBaseline.childInteractions(
                  snapshot,
                ),
              ),
            )!
            as ProductTopicBaselineFrame;
    final data =
        productTopicFrameFromEnvelope(
              topic,
              topic_dto.BridgeProductTopicStreamEnvelope.data(
                event: event_dto.BridgeProductEventEnvelope(
                  eventId: 'event',
                  sequence: BigInt.from(101),
                  createdAt: 47,
                  payload:
                      event_dto
                          .BridgeProductEventPayload.childInteractionsChanged(
                        snapshot,
                      ),
                ),
              ),
            )!
            as ProductTopicDataFrame;
    expect(baseline.topic, topic);
    expect(data.topic, topic);
    expect(baseline.revision, 7);
    expect(data.event.sequence, BigInt.from(101));
    final fromBaseline = (baseline.state as ChildInteractionsBaseline).state;
    final fromEvent =
        (data.event.payload as ChildInteractionsChangedPayload).state;
    expect(fromEvent, fromBaseline);
    expect(fromEvent.hostThreadId, 'root');
    expect(fromEvent.revision, 7);
    expect(fromEvent.updatedAt!.millisecondsSinceEpoch, 43000);
    final item = fromEvent.items.single;
    expect(item.childThreadId, 'child');
    expect(item.interactionId, 'interaction');
    expect(item.revision, 23);
    expect(item.interaction.threadId, 'child');
    expect(item.interaction.turnId, 'turn');
    final question = (item.interaction.payload as UserInputInteractionPayload)
        .questions
        .single;
    expect(question.id, 'question');
    expect(question.question, 'Provide the test credential');
    expect(question.isSecret, isTrue);

    final cleared =
        productTopicFrameFromEnvelope(
              topic,
              topic_dto.BridgeProductTopicStreamEnvelope.data(
                event: event_dto.BridgeProductEventEnvelope(
                  eventId: 'cleared',
                  sequence: BigInt.from(109),
                  createdAt: 49,
                  payload:
                      event_dto
                          .BridgeProductEventPayload.childInteractionsChanged(
                        topic_dto.BridgeChildInteractionsState(
                          hostThreadId: 'root',
                          revision: BigInt.from(8),
                          updatedAt: 49,
                          items: const [],
                        ),
                      ),
                ),
              ),
            )!
            as ProductTopicDataFrame;
    final empty =
        (cleared.event.payload as ChildInteractionsChangedPayload).state;
    expect(empty.hostThreadId, 'root');
    expect(empty.revision, 8);
    expect(empty.items, isEmpty);
    expect(fromBaseline.items, hasLength(1));
  });
}
