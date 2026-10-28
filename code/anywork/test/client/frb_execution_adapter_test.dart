import 'dart:async';

import 'package:anywork/src/infrastructure/frb/conversation/execution_connection.dart';
import 'package:anywork/src/infrastructure/frb/conversation/execution_converters.dart';
import 'package:anywork/src/infrastructure/frb/shared/exact_numbers.dart';
import 'package:anywork/src/rust/api/studio/conversation/execution.dart'
    as wire;
import 'package:anywork/src/rust/api/studio/conversation/execution_feed.dart'
    as native;
import 'package:anywork/src/rust/api/studio/conversation/identity.dart'
    as identity_wire;
import 'package:anywork/src/rust/api/studio/types/chat.dart' as lifecycle;
import 'package:anywork/src/rust/api/studio/types/runtime.dart' as runtime;
import 'package:anywork/src/rust/api/studio/types/thread_stream.dart' as stream;
import 'package:anywork/src/rust/frb_generated.dart';
import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter_test/flutter_test.dart';

final _identity = identity_wire.BridgeThreadFeedIdentity(
  feedId: 'native-execution',
  runtimeEpoch: 'native-runtime',
  incarnation: BigInt.from(3),
  facet: identity_wire.BridgeThreadFacet.execution,
  mode: identity_wire.BridgeThreadObservationMode.live,
);
final _stamp = identity_wire.BridgeThreadFacetStamp(
  runtimeEpoch: 'native-runtime',
  incarnation: BigInt.from(3),
  facet: identity_wire.BridgeThreadFacet.execution,
  revision: BigInt.from(11),
);
const _execution = runtime.BridgeAgentExecution(
  id: 'preparing-exec',
  phase: runtime.BridgeAgentExecutionPhase.preparing,
  turnId: null,
);
const _continuation = stream.BridgeContinuationView(
  id: 'point',
  sourceTurnId: null,
  reason: stream.BridgeContinuationReason.processInterrupted,
  createdAt: -42,
  claimed: false,
);

wire.BridgeExecutionBaseline _baseline({
  runtime.BridgeAgentExecution? execution = _execution,
  stream.BridgeContinuationView? continuation = _continuation,
}) => wire.BridgeExecutionBaseline(
  status: stream.BridgeThreadStatus.idle,
  execution: execution,
  continuation: continuation,
  activeTurn: null,
  recentTerminalTurn: null,
  activity: null,
  storage: null,
  interactions: wire.BridgeInteractionIndexHeader(
    reference: identity_wire.BridgeInteractionIndexRef(
      entry: BigInt.from(10),
      revision: BigInt.one,
    ),
    total: BigInt.zero,
    pending: BigInt.zero,
  ),
);
wire.BridgeExecutionFrame _frame({BigInt? delivery}) =>
    wire.BridgeExecutionFrame.data(
      deliverySequence: delivery ?? BigInt.from(5),
      event: wire.BridgeExecutionEvent.baseline(
        identity: _identity,
        stamp: _stamp,
        value: _baseline(),
      ),
    );

final class _Handle implements native.BridgeThreadExecution {
  final listened = Completer<void>();
  late final controller = StreamController<wire.BridgeExecutionFrame>(
    sync: true,
    onListen: () => listened.complete(),
  );
  final acknowledgements = <BigInt>[];
  int requestCloses = 0;
  bool disposed = false;
  @override
  identity_wire.BridgeThreadFeedIdentity identity() => _identity;
  @override
  Stream<wire.BridgeExecutionFrame> stream() => controller.stream;
  @override
  Future<void> ackThrough({required BigInt deliverySequence}) async =>
      acknowledgements.add(deliverySequence);
  @override
  void requestClose() => requestCloses++;
  @override
  Future<lifecycle.BridgeFeedCloseReport> close() async {
    unawaited(controller.close());
    return const lifecycle.BridgeFeedCloseReport(
      feedId: 'native-execution',
      outcome: lifecycle.BridgeFeedCloseOutcome.clean(),
    );
  }

  @override
  Future<lifecycle.BridgeFeedCloseReport> retryClose() => close();
  @override
  void dispose() => disposed = true;
  @override
  bool get isDisposed => disposed;
  @override
  Never noSuchMethod(Invocation invocation) => throw StateError(
    'Unscripted native execution handle ${invocation.memberName}',
  );
}

final class _Api implements RustLibApi {
  _Api(this.handle);
  final _Handle handle;
  @override
  Future<native.BridgeThreadExecution>
  crateApiStudioConversationExecutionFeedOpenThreadExecution({
    required String threadId,
    required identity_wire.BridgeThreadObservationMode mode,
  }) async {
    expect(
      (threadId, mode),
      ('thread', identity_wire.BridgeThreadObservationMode.live),
    );
    return handle;
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected execution native API ${invocation.memberName}',
  );
}

void main() {
  test('baseline execution and continuation preserve null/value and source/sequence identities', () {
    final frame = executionFrameFromBridge(_frame()) as ThreadExecutionData;
    expect(frame.deliverySequence, 5);
    final baseline = frame.event as ThreadExecutionBaselineEvent;
    expect(
      (
        baseline.identity.feedId,
        baseline.identity.runtimeEpoch,
        baseline.identity.incarnation,
        baseline.stamp.revision,
      ),
      ('native-execution', 'native-runtime', 3, 11),
    );
    expect(
      baseline.value.execution,
      const AgentExecution(
        id: 'preparing-exec',
        phase: AgentExecutionPhase.preparing,
        turnId: null,
      ),
    );
    expect(
      baseline.value.continuation,
      const ContinuationView(
        id: 'point',
        sourceTurnId: null,
        reason: ContinuationReason.processInterrupted,
        createdAt: -42,
        claimed: false,
      ),
    );
    final cleared = executionBaselineFromBridge(
      _baseline(execution: null, continuation: null),
    );
    expect((cleared.execution, cleared.continuation), (null, null));
  });

  test('delta Unchanged, Replace(null), Replace(value) remain distinct closed unions', () {
    for (final (
          execution,
          continuation,
          expectedExecution,
          expectedContinuation,
        )
        in <
          (
            wire.BridgeExecutionReplacement,
            wire.BridgeContinuationReplacement,
            ExecutionReplacement,
            ContinuationReplacement,
          )
        >[
          (
            const wire.BridgeExecutionReplacement.unchanged(),
            const wire.BridgeContinuationReplacement.unchanged(),
            const ExecutionReplacement.unchanged(),
            const ContinuationReplacement.unchanged(),
          ),
          (
            const wire.BridgeExecutionReplacement.replace(value: null),
            const wire.BridgeContinuationReplacement.replace(value: null),
            const ExecutionReplacement.replace(value: null),
            const ContinuationReplacement.replace(value: null),
          ),
          (
            const wire.BridgeExecutionReplacement.replace(value: _execution),
            const wire.BridgeContinuationReplacement.replace(
              value: _continuation,
            ),
            const ExecutionReplacement.replace(
              value: AgentExecution(
                id: 'preparing-exec',
                phase: AgentExecutionPhase.preparing,
                turnId: null,
              ),
            ),
            const ContinuationReplacement.replace(
              value: ContinuationView(
                id: 'point',
                sourceTurnId: null,
                reason: ContinuationReason.processInterrupted,
                createdAt: -42,
                claimed: false,
              ),
            ),
          ),
        ]) {
      final value = executionChangeFromBridge(
        wire.BridgeExecutionChange(
          status: null,
          execution: execution,
          continuation: continuation,
          turns: null,
          interactions: null,
          activity: const wire.BridgeActivityReplacement.unchanged(),
          storage: const wire.BridgeStorageReplacement.unchanged(),
        ),
      );
      expect(value.execution, expectedExecution);
      expect(value.continuation, expectedContinuation);
    }
  });

  test('forwarding is not consume: a paused consumer owns the ACK barrier; native close/dispose still join', () async {
    final handle = _Handle();
    RustLib.initMock(api: _Api(handle));
    addTearDown(RustLib.dispose);
    final connection = FrbThreadExecutionConnection.open(
      threadId: 'thread',
      mode: ThreadObservationMode.live,
    );
    await connection.opened;
    final delivered = Completer<ThreadExecutionFrame>();
    final resume = Completer<void>();
    final subscription = connection.events.listen(delivered.complete);
    subscription.pause(resume.future);
    await handle.listened.future;
    handle.controller.add(_frame());
    expect(
      handle.acknowledgements,
      isEmpty,
      reason: 'Native forwarding cannot ACK an unhanded frame',
    );
    expect(delivered.isCompleted, isFalse);
    resume.complete();
    final frame = await delivered.future as ThreadExecutionData;
    expect(
      handle.acknowledgements,
      isEmpty,
      reason: 'Only the consumer hands over its consumed prefix',
    );
    await connection.ackThrough(frame.deliverySequence);
    expect(handle.acknowledgements, [BigInt.from(5)]);
    await subscription.cancel();
    expect((await connection.close()).outcome, isA<CleanFeedCloseOutcome>());
    expect(handle.requestCloses, greaterThan(0));
    expect(handle.disposed, isTrue);
  });

  test('u64 overflow emits a typed failure without ACK; i64 conversion rejects its true signed bounds', () async {
    final handle = _Handle();
    RustLib.initMock(api: _Api(handle));
    addTearDown(RustLib.dispose);
    final connection = FrbThreadExecutionConnection.open(
      threadId: 'thread',
      mode: ThreadObservationMode.live,
    );
    await connection.opened;
    final failure = Completer<ThreadExecutionFrame>();
    final subscription = connection.events.listen(failure.complete);
    await handle.listened.future;
    handle.controller.add(_frame(delivery: BigInt.one << 64));
    final event = await failure.future;
    expect(
      event,
      isA<ThreadExecutionFailure>().having(
        (frame) => frame.error.correlationId,
        'number error not swallowed',
        'adapter-integer-range',
      ),
    );
    expect(handle.acknowledgements, isEmpty);
    await subscription.cancel();
    expect((await connection.close()).outcome, isA<CleanFeedCloseOutcome>());
    for (final value in [-(BigInt.one << 63) - BigInt.one, BigInt.one << 63]) {
      expect(
        () => exactI64(value, 'native timestamp'),
        throwsA(
          isA<StudioFailure>().having(
            (error) => error.code,
            'signed protocol range',
            StudioFailureCode.protocol,
          ),
        ),
      );
    }
    expect(exactI64(BigInt.from(-42), 'native timestamp'), -42);
  });
}
