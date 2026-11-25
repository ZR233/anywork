import 'package:anywork/src/infrastructure/frb/studio_api.dart';
import 'package:anywork/src/rust/api/studio/types/product_topic.dart'
    as topic_dto;
import 'package:anywork/src/rust/api/studio/types/response.dart'
    as response_dto;
import 'package:anywork/src/rust/api/studio/types/thread_stream.dart'
    as thread_dto;
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('session cost mapping preserves known amounts and independent completeness flags', () {
    const amount = thread_dto.BridgeRuntimeCostAmount(
      currency: 'USD',
      amount: 0.25,
    );
    for (final (incomplete, unpriced) in [(true, false), (false, true)]) {
      const rootThreadId = 'root-thread';
      const topic = topic_dto.BridgeProductTopic.sessionCosts(
        rootThreadId: rootThreadId,
      );
      final frame = productTopicFrameFromEnvelope(
        const SessionCostsTopic(rootThreadId: rootThreadId),
        topic_dto.BridgeProductTopicStreamEnvelope.baseline(
          topic: topic,
          revision: BigInt.one,
          state: topic_dto.BridgeProductBaseline.sessionCosts(
            response_dto.BridgeSessionCostsState(
              rootThreadId: rootThreadId,
              revision: BigInt.one,
              updatedAt: 0,
              statisticsPending: false,
              statisticsGap: false,
              readFailed: false,
              cost: response_dto.BridgeSessionCostSnapshot(
                rootThreadId: rootThreadId,
                purposeCosts: [
                  response_dto.BridgePurposeCostSnapshot(
                    purpose: 'main',
                    estimatedCosts: const [amount],
                    hasUnpricedUsage: unpriced,
                  ),
                ],
                estimatedCosts: const [amount],
                hasUnpricedUsage: unpriced,
                hasIncompleteUsage: incomplete,
              ),
            ),
          ),
        ),
      ) as ProductTopicBaselineFrame;
      final costs = (frame.state as SessionCostsBaseline).state;
      expect(costs.cost!.rootThreadId, rootThreadId);
      expect(costs.cost!.estimatedCosts, const [
        RuntimeCostView(currency: 'USD', amount: 0.25),
      ]);
      expect(costs.cost!.hasIncompleteUsage, incomplete);
      expect(costs.cost!.hasUnpricedUsage, unpriced);
      expect(costs.cost!.purposeCosts.single.purpose, 'main');
      expect(
        costs.cost!.purposeCosts.single.estimatedCosts,
        costs.cost!.estimatedCosts,
      );
      expect(costs.cost!.purposeCosts.single.hasUnpricedUsage, unpriced);
    }
  });
}
