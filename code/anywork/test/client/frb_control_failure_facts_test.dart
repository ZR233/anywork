import 'package:anywork/src/infrastructure/frb/shared/bridge_failure.dart';
import 'package:anywork/src/rust/api/studio/types/error.dart' as wire;
import 'package:anywork_client/resources.dart';
import 'package:flutter_test/flutter_test.dart';

StudioFailure _convert(wire.BridgeControlFailureFacts facts) => bridgeFailure(wire.BridgeError(
  code: wire.BridgeErrorCode.conflict, message: 'not a serialized facts payload',
  retryable: false, correlationId: 'typed-control',
  details: wire.BridgeErrorDetails.control(reason: 'preserve-reason', facts: facts),
));

void main() {
  // These are wire-shape contracts, not 21 copies of a business scenario. The
  // independent expected domain values catch dropped/swapped nullable fields.
  test('control identity/string facts remain a closed typed value, including optional IDs', () {
    final cases = <(wire.BridgeControlFailureFacts, ControlFailureFacts)>[
      (const wire.BridgeControlFailureFacts.unspecified(), const ControlFailureFacts.unspecified()),
      (const wire.BridgeControlFailureFacts.childThreadAction(threadId: 'child', action: 'send', parentThreadId: 'parent'), const ControlFailureFacts.childThreadAction(threadId: 'child', action: 'send', parentThreadId: 'parent')),
      (const wire.BridgeControlFailureFacts.childThreadAction(threadId: 'orphan', action: 'continue', parentThreadId: null), const ControlFailureFacts.childThreadAction(threadId: 'orphan', action: 'continue', parentThreadId: null)),
      (const wire.BridgeControlFailureFacts.threadAction(threadId: 't', action: 'stop'), const ControlFailureFacts.threadAction(threadId: 't', action: 'stop')),
      (const wire.BridgeControlFailureFacts.expectedExecution(threadId: 't', expectedExecutionId: 'e-old'), const ControlFailureFacts.expectedExecution(threadId: 't', expectedExecutionId: 'e-old')),
      (const wire.BridgeControlFailureFacts.executing(threadId: 't', executionId: 'e-new', phase: 'preparing'), const ControlFailureFacts.executing(threadId: 't', executionId: 'e-new', phase: 'preparing')),
      (const wire.BridgeControlFailureFacts.expectedContinuation(threadId: 't', expectedContinuationId: 'c-old'), const ControlFailureFacts.expectedContinuation(threadId: 't', expectedContinuationId: 'c-old')),
      (const wire.BridgeControlFailureFacts.continuationOperation(threadId: 't', operationId: 'op'), const ControlFailureFacts.continuationOperation(threadId: 't', operationId: 'op')),
      (const wire.BridgeControlFailureFacts.continuationPointConflict(threadId: 't', operationId: 'op', expectedContinuationId: 'c-old', acceptedContinuationId: 'c-new'), const ControlFailureFacts.continuationPointConflict(threadId: 't', operationId: 'op', expectedContinuationId: 'c-old', acceptedContinuationId: 'c-new')),
      (const wire.BridgeControlFailureFacts.staleContinuation(threadId: 't', expectedContinuationId: 'old', currentContinuationId: 'new'), const ControlFailureFacts.staleContinuation(threadId: 't', expectedContinuationId: 'old', currentContinuationId: 'new')),
      (const wire.BridgeControlFailureFacts.claimedContinuation(threadId: 't', continuationId: 'c'), const ControlFailureFacts.claimedContinuation(threadId: 't', continuationId: 'c')),
      (const wire.BridgeControlFailureFacts.childInteraction(interactionId: 'qa', interactionThreadId: 'child'), const ControlFailureFacts.childInteraction(interactionId: 'qa', interactionThreadId: 'child')),
      (const wire.BridgeControlFailureFacts.interactionOperation(operationId: 'op', interactionId: 'qa'), const ControlFailureFacts.interactionOperation(operationId: 'op', interactionId: 'qa')),
      (const wire.BridgeControlFailureFacts.interactionHost(hostThreadId: 'host', interactionThreadId: 'child'), const ControlFailureFacts.interactionHost(hostThreadId: 'host', interactionThreadId: 'child')),
      (const wire.BridgeControlFailureFacts.unreadableDecision(threadId: 'child', interactionId: 'qa'), const ControlFailureFacts.unreadableDecision(threadId: 'child', interactionId: 'qa')),
    ];
    for (final (native, expected) in cases) {
      expect(_convert(native).details, StudioFailureDetails.control(reason: 'preserve-reason', facts: expected));
    }
  });

  test('control booleans are not inferred from code/message or treated as always true', () {
    for (final value in [false, true]) {
      for (final (native, expected) in <(wire.BridgeControlFailureFacts, ControlFailureFacts)>[
        (wire.BridgeControlFailureFacts.continuationAccepted(threadId: 't', operationId: 'op', accepted: value), ControlFailureFacts.continuationAccepted(threadId: 't', operationId: 'op', accepted: value)),
        (wire.BridgeControlFailureFacts.childHost(hostThreadId: 'host', hostIsChild: value), ControlFailureFacts.childHost(hostThreadId: 'host', hostIsChild: value)),
        (wire.BridgeControlFailureFacts.decisionDurability(interactionId: 'qa', decisionSaved: value), ControlFailureFacts.decisionDurability(interactionId: 'qa', decisionSaved: value)),
        (wire.BridgeControlFailureFacts.decisionIdentity(interactionId: 'qa', currentRevision: BigInt.from(23), operationIdentityRecorded: value), ControlFailureFacts.decisionIdentity(interactionId: 'qa', currentRevision: 23, operationIdentityRecorded: value)),
      ]) {
        expect(_convert(native).details, StudioFailureDetails.control(reason: 'preserve-reason', facts: expected));
      }
    }
  });

  test('revision-shaped facts preserve unequal exact u64 fields and reject overflow rather than dropping them', () {
    final cases = <(wire.BridgeControlFailureFacts, ControlFailureFacts)>[
      (wire.BridgeControlFailureFacts.continuationRouteConflict(threadId: 't', operationId: 'op', expectedModelRouteRevision: BigInt.from(17), acceptedModelRouteRevision: BigInt.from(31)), const ControlFailureFacts.continuationRouteConflict(threadId: 't', operationId: 'op', expectedModelRouteRevision: 17, acceptedModelRouteRevision: 31)),
      (wire.BridgeControlFailureFacts.interactionRevision(interactionId: 'qa', expectedRevision: BigInt.from(19), currentRevision: BigInt.from(37)), const ControlFailureFacts.interactionRevision(interactionId: 'qa', expectedRevision: 19, currentRevision: 37)),
      (wire.BridgeControlFailureFacts.interactionTerminal(interactionId: 'qa', currentRevision: BigInt.from(41)), const ControlFailureFacts.interactionTerminal(interactionId: 'qa', currentRevision: 41)),
    ];
    for (final (native, expected) in cases) {
      expect(_convert(native).details, StudioFailureDetails.control(reason: 'preserve-reason', facts: expected));
    }
    for (final invalid in [-BigInt.one, BigInt.one << 64, BigInt.one << 63]) {
      expect(() => _convert(wire.BridgeControlFailureFacts.interactionRevision(interactionId: 'qa', expectedRevision: invalid, currentRevision: BigInt.one)), throwsA(isA<StudioFailure>().having((error) => error.correlationId, 'exact number failure', 'adapter-integer-range')));
    }
  });
}
