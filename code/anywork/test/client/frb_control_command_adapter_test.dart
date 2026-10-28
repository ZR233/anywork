import 'package:anywork/src/infrastructure/frb/conversation/command_port.dart';
import 'package:anywork/src/rust/api/studio/types/command.dart' as wire;
import 'package:anywork/src/rust/api/studio/types/error.dart' as errors;
import 'package:anywork/src/rust/api/studio/types/thread_stream.dart' as stream;
import 'package:anywork/src/rust/frb_generated.dart';
import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter_test/flutter_test.dart';

const _operation = OperationId('control-op');
CommitReceipt _expectedReceipt() => CommitReceipt(
  operationId: _operation,
  disposition: CommitDisposition.applied,
  targets: const [],
  effect: EffectPoint.immediate,
  effective: false,
  durable: false,
  requiresIdentityObservation: true,
);
wire.BridgeStudioCommandReceipt _receipt() =>
    const wire.BridgeStudioCommandReceipt(
      operationId: 'control-op',
      disposition: wire.BridgeCommandDisposition.applied,
      targets: [],
      effect: wire.BridgeCommandEffectPoint.immediate,
      effective: false,
      durable: false,
      requiresIdentityObservation: true,
    );

errors.BridgeError _error({
  errors.BridgeErrorCode code = errors.BridgeErrorCode.busy,
  String reason = 'continuationAccepted',
  errors.BridgeControlFailureFacts? facts,
}) => errors.BridgeError(
  code: code,
  message: 'opaque native message',
  retryable: false,
  correlationId: 'control-native',
  details: facts == null
      ? null
      : errors.BridgeErrorDetails.control(reason: reason, facts: facts),
);

final class _Api implements RustLibApi {
  Object? continueError;
  wire.BridgeContinueThreadReply? continueReply;
  Object? queryError;
  wire.BridgeContinuationOperationView? queryReply;
  wire.BridgeInteractionCommandReply? interactionReply;
  final continues =
      <({String thread, String operation, String point, BigInt route})>[];
  final queries = <({String thread, String operation})>[];
  final responses =
      <
        ({
          String host,
          String operation,
          BigInt revision,
          String id,
          stream.BridgeInteractionResolution resolution,
        })
      >[];
  final stops = <({String thread, String operation, String execution})>[];
  @override
  Future<wire.BridgeContinueThreadReply>
  crateApiStudioHandlersPromptContinueThread({
    required String operationId,
    required String threadId,
    required String expectedContinuationId,
    required BigInt expectedModelRouteRevision,
  }) async {
    continues.add((
      thread: threadId,
      operation: operationId,
      point: expectedContinuationId,
      route: expectedModelRouteRevision,
    ));
    if (continueError case final error?) throw error;
    return continueReply!;
  }

  @override
  Future<wire.BridgeContinuationOperationView>
  crateApiStudioHandlersPromptReadContinuationOperation({
    required String threadId,
    required String operationId,
  }) async {
    queries.add((thread: threadId, operation: operationId));
    if (queryError case final error?) throw error;
    return queryReply!;
  }

  @override
  Future<wire.BridgeStopThreadReply> crateApiStudioHandlersPromptStopThread({
    required String operationId,
    required String threadId,
    required String expectedExecutionId,
  }) async {
    stops.add((
      thread: threadId,
      operation: operationId,
      execution: expectedExecutionId,
    ));
    return wire.BridgeStopThreadReply(
      threadId: threadId,
      executionId: expectedExecutionId,
      stopped: true,
      receipt: _receipt(),
    );
  }

  @override
  Future<wire.BridgeInteractionCommandReply>
  crateApiStudioHandlersPromptRespondInteraction({
    required String operationId,
    required String hostThreadId,
    required BigInt expectedRevision,
    required String interactionId,
    required stream.BridgeInteractionResolution resolution,
  }) async {
    responses.add((
      host: hostThreadId,
      operation: operationId,
      revision: expectedRevision,
      id: interactionId,
      resolution: resolution,
    ));
    return interactionReply!;
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected control native call ${invocation.memberName}',
  );
}

void main() {
  late _Api api;
  late FrbConversationCommandPort port;
  setUp(() {
    api = _Api();
    port = FrbConversationCommandPort();
    RustLib.initMock(api: api);
  });
  tearDown(RustLib.dispose);

  test('invalid expected route fails before native dispatch rather than becoming Unknown', () {
    expect(
      () => port.continueThread(
        'host',
        operationId: _operation,
        expectedContinuationId: 'point',
        expectedModelRouteRevision: -1,
      ),
      throwsA(isA<RejectedCommandDispatchFailure>()),
    );
    expect(api.continues, isEmpty);
  });

  test('true accepted plus exact thread/op without receipt is confirmedWithoutUsableReceipt, never rejected', () async {
    api.continueError = _error(
      facts: const errors.BridgeControlFailureFacts.continuationAccepted(
        threadId: 'host',
        operationId: 'control-op',
        accepted: true,
      ),
    );
    await expectLater(
      port.continueThread(
        'host',
        operationId: _operation,
        expectedContinuationId: 'point',
        expectedModelRouteRevision: 13,
      ),
      throwsA(
        isA<ConfirmedWithoutUsableReceiptCommandDispatchFailure>().having(
          (failure) => failure.failure.details,
          'all typed acceptance facts',
          const StudioFailureDetails.control(
            reason: 'continuationAccepted',
            facts: ControlFailureFacts.continuationAccepted(
              threadId: 'host',
              operationId: 'control-op',
              accepted: true,
            ),
          ),
        ),
      ),
    );
    expect(api.continues.single, (
      thread: 'host',
      operation: 'control-op',
      point: 'point',
      route: BigInt.from(13),
    ));
    expect(
      api.queries,
      isEmpty,
      reason:
          'The original SDK operation, not this adapter, owns recovery queries',
    );
  });

  test('foreign identities, accepted=false and ordinary Busy never confirm acceptance', () async {
    for (final error in [
      _error(
        facts: const errors.BridgeControlFailureFacts.continuationAccepted(
          threadId: 'foreign',
          operationId: 'control-op',
          accepted: true,
        ),
      ),
      _error(
        facts: const errors.BridgeControlFailureFacts.continuationAccepted(
          threadId: 'host',
          operationId: 'foreign-op',
          accepted: true,
        ),
      ),
      _error(
        facts: const errors.BridgeControlFailureFacts.continuationAccepted(
          threadId: 'host',
          operationId: 'control-op',
          accepted: false,
        ),
      ),
      _error(),
    ]) {
      api.continueError = error;
      await expectLater(
        port.continueThread(
          'host',
          operationId: _operation,
          expectedContinuationId: 'point',
          expectedModelRouteRevision: 13,
        ),
        throwsA(
          isA<UnknownOutcomeCommandDispatchFailure>().having(
            (failure) => failure.failure.code,
            'native Busy remains visible',
            StudioFailureCode.busy,
          ),
        ),
      );
    }
    expect(api.continues, hasLength(4));
    expect(api.queries, isEmpty);
  });

  test('a converted receipt survives invalid success fields as committedButUnobserved; no fabricated receipt', () async {
    for (final (thread, point, cursor) in [
      ('wrong-thread', 'point', BigInt.from(7)),
      ('host', 'wrong-point', BigInt.from(7)),
      ('host', 'point', BigInt.one << 64),
    ]) {
      api.continueReply = wire.BridgeContinueThreadReply(
        threadId: thread,
        inputId: 'control-op',
        continuationId: point,
        cursor: cursor,
        receipt: _receipt(),
      );
      await expectLater(
        port.continueThread(
          'host',
          operationId: _operation,
          expectedContinuationId: 'point',
          expectedModelRouteRevision: 13,
        ),
        throwsA(
          isA<CommittedButUnobservedCommandDispatchFailure>().having(
            (failure) => failure.receipt,
            'the exact native receipt',
            _expectedReceipt(),
          ),
        ),
      );
    }
    expect(api.continues, hasLength(3));
    expect(api.queries, isEmpty);
  });

  test('only exact NotFound+Control continuationUnavailable+ContinuationOperation is null; other errors remain errors', () async {
    final exactFacts =
        const errors.BridgeControlFailureFacts.continuationOperation(
          threadId: 'host',
          operationId: 'control-op',
        );
    api.queryError = _error(
      code: errors.BridgeErrorCode.notFound,
      reason: 'continuationUnavailable',
      facts: exactFacts,
    );
    expect(await port.readContinuationOperation('host', _operation), isNull);
    for (final error in [
      _error(code: errors.BridgeErrorCode.notFound),
      _error(
        code: errors.BridgeErrorCode.notFound,
        reason: 'otherReason',
        facts: exactFacts,
      ),
      _error(
        code: errors.BridgeErrorCode.busy,
        reason: 'continuationUnavailable',
        facts: exactFacts,
      ),
      _error(
        code: errors.BridgeErrorCode.notFound,
        reason: 'continuationUnavailable',
        facts: const errors.BridgeControlFailureFacts.continuationOperation(
          threadId: 'other-host',
          operationId: 'control-op',
        ),
      ),
      _error(
        code: errors.BridgeErrorCode.notFound,
        reason: 'continuationUnavailable',
        facts: const errors.BridgeControlFailureFacts.continuationOperation(
          threadId: 'host',
          operationId: 'other-op',
        ),
      ),
      _error(
        code: errors.BridgeErrorCode.notFound,
        reason: 'continuationUnavailable',
        facts: const errors.BridgeControlFailureFacts.continuationAccepted(
          threadId: 'host',
          operationId: 'control-op',
          accepted: true,
        ),
      ),
    ]) {
      api.queryError = error;
      await expectLater(
        port.readContinuationOperation('host', _operation),
        throwsA(
          isA<StudioFailure>().having(
            (failure) => failure.correlationId,
            'native error preserved',
            'control-native',
          ),
        ),
      );
    }
    expect(
      api.queries,
      everyElement((thread: 'host', operation: 'control-op')),
    );
  });

  test('typed continuation Pending/Consumed/Discarded preserve receipt, sequence, durability and exact IDs', () async {
    for (final (native, expected) in [
      (
        const wire.BridgeContinuationOperationState.pending(),
        const ContinuationOperationState.pending(),
      ),
      (
        const wire.BridgeContinuationOperationState.consumed(
          turnId: 'turn-new',
        ),
        const ContinuationOperationState.consumed(turnId: 'turn-new'),
      ),
      (
        const wire.BridgeContinuationOperationState.discarded(),
        const ContinuationOperationState.discarded(),
      ),
    ]) {
      api.queryReply = wire.BridgeContinuationOperationView(
        threadId: 'host',
        operationId: 'control-op',
        inputId: 'control-op',
        continuationId: 'point',
        acceptedSequence: BigInt.from(19),
        state: native,
        durable: true,
        receipt: _receipt(),
      );
      final value = await port.readContinuationOperation('host', _operation);
      expect(
        value,
        ContinuationOperationView(
          threadId: 'host',
          operationId: _operation,
          inputId: 'control-op',
          continuationId: 'point',
          acceptedSequence: 19,
          state: expected,
          durable: true,
          receipt: _expectedReceipt(),
        ),
      );
    }
  });

  test('native host/op/revision/id/resolution stay frozen; true target in reply is not rewritten to host', () async {
    api.interactionReply = wire.BridgeInteractionCommandReply(
      interaction: stream.BridgeInteractionRequest(
        interactionId: 'qa',
        scope: const stream.BridgeInteractionScope(
          threadId: 'child',
          turnId: 'child-turn',
          agentPath: 'root/child',
        ),
        revision: BigInt.from(6),
        content: const stream.BridgeInteractionContent.userInput(
          questions: [],
          state: stream.BridgeUserInputInteractionState.resolved(
            operationId: 'native-tool-op',
            resolvedAt: 1767225600,
            answers: [],
          ),
        ),
        createdAt: 1767225500,
        updatedAt: 1767225600,
      ),
      receipt: _receipt(),
    );
    final resolution = InteractionResolutionCommand.userInput(
      answers: [
        UserInputAnswerCommand(questionId: 'q', answers: ['yes']),
      ],
    );
    final result = await port.respondInteraction(
      'host',
      'qa',
      operationId: _operation,
      expectedInteractionRevision: 5,
      resolution: resolution,
    );
    expect(api.responses.single.host, 'host');
    expect(api.responses.single.operation, 'control-op');
    expect(api.responses.single.revision, BigInt.from(5));
    expect(api.responses.single.id, 'qa');
    expect(
      api.responses.single.resolution,
      const stream.BridgeInteractionResolution.userInput(
        answers: [
          stream.BridgeUserInputAnswer(questionId: 'q', answers: ['yes']),
        ],
      ),
    );
    expect(result.interaction.scope.threadId, 'child');
    expect(result.interaction.scope.agentPath, 'root/child');
    final stop = await port.stopExecution(
      'child',
      'preparing-execution',
      operationId: _operation,
    );
    expect(api.stops.single, (
      thread: 'child',
      operation: 'control-op',
      execution: 'preparing-execution',
    ));
    expect(stop.executionId, 'preparing-execution');
  });
}
