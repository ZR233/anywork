import '../../commands/mutation_board.dart';
import '../../observation/latest_value.dart';
import '../../conversation/data/input_turn_facts.dart';
import '../../../models.dart';
import 'drafts_dependencies.dart';

/// Register before dispatch. The conversation reducer supplies only minimal
/// facts for this input; neither a last patch nor a state cursor is a snapshot.
InputSubmissionObservation registerSubmittedInput({
  required DraftsDependencies dependencies,
  required OperationHandle operation,
  required String inputId,
  String? expectedThreadId,
}) {
  final observation = InputSubmissionObservation._(
    dependencies,
    operation,
    inputId,
    expectedThreadId,
  );
  try {
    observation._source = dependencies.inputFacts.watchInputFacts(
      inputId: inputId,
      expectedThreadId: expectedThreadId,
      onFact: observation._record,
    );
    return observation;
  } catch (_) {
    observation.cancel();
    rethrow;
  }
}

/// One identity and monotonic effect/save evidence, not a growing Turn list.
final class InputSubmissionObservation implements Observation {
  InputSubmissionObservation._(
    this.dependencies,
    this.operation,
    this.inputId,
    this.expectedThreadId,
  ) : _retainedOperation = operation.state.watch((_) {});
  final DraftsDependencies dependencies;
  final OperationHandle operation;
  final String inputId;
  final String? expectedThreadId;
  final Observation _retainedOperation;
  Observation? _source;
  ({String threadId, String itemId})? _identity;
  SubmitPromptReceipt? _receipt;
  Object? _conflict;
  bool _effective = false;
  bool _durable = false;
  bool _observed = false;
  bool _settling = false;
  bool _again = false;
  @override
  bool isCancelled = false;
  @override
  bool isPaused = false;

  void _record(InputTurnFact fact) {
    if (isCancelled) return;
    final identity = (threadId: fact.threadId, itemId: fact.itemId);
    if (fact.inputId != inputId ||
        expectedThreadId != null && fact.threadId != expectedThreadId ||
        _identity != null && _identity != identity ||
        _receipt != null && fact.threadId != _receipt!.threadId) {
      _conflict ??= StateError('Input Turn evidence identity conflicted');
    } else {
      _identity = identity;
      _effective |= fact.status != StudioTurnStatus.queued;
      _durable |= fact.saved;
    }
    _settle();
  }

  void accept(SubmitPromptReceipt receipt) {
    if (isCancelled)
      throw StateError('Input observation is no longer available');
    if (_receipt != null ||
        receipt.inputId != inputId ||
        expectedThreadId != null && receipt.threadId != expectedThreadId) {
      final error = StateError(
        'Input receipt did not match the submitted request',
      );
      operation.syncFailed(error);
      cancel();
      throw error;
    }
    // A new-thread receipt has already been checked against its result. Earlier
    // evidence for another thread is an observation conflict, not a reason to
    // discard this valid acceptance. Mark it sticky before accept publishes so
    // synchronous listeners cannot temporarily settle effects from that evidence.
    if (_identity != null && _identity!.threadId != receipt.threadId) {
      _conflict ??= StateError('Input Turn evidence identity conflicted');
    }
    _receipt = receipt;
    operation.accept(
      CommitReceipt(
        operationId: operation.id,
        disposition: CommitDisposition.applied,
        targets: [_stamp(receipt)],
        effect: EffectPoint.nextTurn,
      ),
    );
    final conflict = _conflict;
    _settle();
    if (conflict != null) throw conflict;
  }

  ResourceStamp _stamp(SubmitPromptReceipt receipt) => ResourceStamp(
    resourceKey: 'input:${receipt.threadId}:$inputId',
    ownerEpoch: receipt.threadId,
    revision: receipt.cursor,
  );

  void _settle() {
    if (isCancelled || isPaused || _receipt == null) return;
    if (_settling) {
      _again = true;
      return;
    }
    _settling = true;
    try {
      do {
        _again = false;
        if (_conflict case final error?) {
          operation.syncFailed(error);
          cancel();
          return;
        }
        if (_identity == null) return;
        if (!_observed) {
          _observed = true;
          dependencies.mutations.observe(_stamp(_receipt!));
        }
        if (_effective && !operation.state.value.effective)
          operation.markEffective();
        if (_durable && !operation.state.value.durable) operation.markDurable();
        if (operation.state.value.effective && operation.state.value.durable)
          cancel();
      } while (_again && !isCancelled);
    } finally {
      _settling = false;
    }
  }

  @override
  void pause() => isPaused = true;
  @override
  void resume() {
    isPaused = false;
    _settle();
  }

  @override
  void cancel() {
    if (isCancelled) return;
    isCancelled = true;
    _source?.cancel();
    _retainedOperation.cancel();
  }
}

bool isKnownSubmissionRejection(Object error) =>
    error is StudioFailure &&
    switch (error.code) {
      StudioFailureCode.invalidArgument ||
      StudioFailureCode.notFound ||
      StudioFailureCode.busy ||
      StudioFailureCode.conflict ||
      StudioFailureCode.staleRevision ||
      StudioFailureCode.permissionDenied ||
      StudioFailureCode.overloaded => true,
      _ => false,
    };
