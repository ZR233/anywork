import 'package:anywork/src/infrastructure/frb/conversation/content_turn_converters.dart';
import 'package:anywork/src/rust/api/studio/types/thread_stream.dart' as wire;
import 'package:anywork/src/rust/api/studio/types/turn_failure.dart'
    as failure_wire;
import 'package:anywork_client/conversation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Timeline failure conversion preserves the typed retry alternatives without inventing a delay', () {
    // Exercise the complete production Timeline Turn converter, not a local
    // bool/delay reconstruction. The shared native retry union is the input;
    // unified FRB generation is deliberately deferred by the v5 plan.
    final cases = [
      (
        native: const failure_wire.BridgeRetryDisposition.retryable(
          retryAfterMs: null,
        ),
        expected: const RetryDisposition.retryable(retryAfterMs: null),
      ),
      (
        native: failure_wire.BridgeRetryDisposition.retryable(
          retryAfterMs: BigInt.zero,
        ),
        expected: const RetryDisposition.retryable(retryAfterMs: 0),
      ),
      (
        native: const failure_wire.BridgeRetryDisposition.permanent(),
        expected: const RetryDisposition.permanent(),
      ),
    ];

    for (final scenario in cases) {
      final converted = contentTurnFromBridge(
        wire.BridgeTurnState.failed(
          startedAt: 101,
          completedAt: 103,
          failure: wire.BridgeTurnFailureDto(
            category: failure_wire.BridgeTurnFailureCategory.providerCapacity,
            providerKind: failure_wire.BridgeProviderFailureKind.capacity,
            code: 'quota.exhausted',
            httpStatus: 429,
            message: 'The provider declined this attempt.',
            retry: scenario.native,
          ),
        ),
      );

      expect(
        converted,
        TurnState.failed(
          startedAt: 101,
          completedAt: 103,
          failure: TurnFailure(
            category: TurnFailureCategory.providerCapacity,
            providerKind: ProviderFailureKind.capacity,
            code: 'quota.exhausted',
            httpStatus: 429,
            message: 'The provider declined this attempt.',
            retry: scenario.expected,
          ),
        ),
      );
    }
  });
}
