part of 'new_thread_creation_port.dart';

/// The original successful creation's actual source opaque. The creation owns
/// it until cleanup; feeds synchronously handed to callers retain independent
/// native pins and are removed from this source's pending-opening collection.
final class _FrbCreatedInputExecutionSource
    implements CreatedInputExecutionSource {
  _FrbCreatedInputExecutionSource(this._creation, this._handle, this._threadId);
  final _FrbThreadCreation _creation;
  final native.BridgeCreatedInputExecutionSource _handle;
  final String _threadId;
  wire.BridgeCreatedInputExecutionIdentity? _identity;
  int? _incarnation;
  ({StudioFailure failure, StackTrace stack})? _failure;
  final Set<_CreatedExecutionOpening> _openings = {};

  void initialize() {
    try {
      final identity = _handle.identity();
      if (identity.threadId != _threadId ||
          identity.inputId != _creation.inputId ||
          identity.threadId.isEmpty ||
          identity.runtimeEpoch.isEmpty) {
        throw adapterProtocol('created-input-execution-source');
      }
      _identity = identity;
      _incarnation = exactU64(
        identity.incarnation,
        'created input incarnation',
      );
    } on Object catch (error, stack) {
      _failure = (
        failure: _creation._owner.failure(
          error,
          stack,
          source: 'source-identity',
        ),
        stack: stack,
      );
    }
  }

  void requireIdentity() {
    if (_failure case final failure?) {
      Error.throwWithStackTrace(failure.failure, failure.stack);
    }
    if (_identity == null || _incarnation == null) {
      throw adapterProtocol('created-input-source-identity');
    }
  }

  void _checkStable() {
    requireIdentity();
    final actual = _handle.identity();
    final expected = _identity!;
    if (actual.threadId != expected.threadId ||
        actual.inputId != expected.inputId ||
        actual.runtimeEpoch != expected.runtimeEpoch ||
        actual.incarnation != expected.incarnation) {
      throw adapterProtocol('created-input-source-replaced');
    }
  }

  @override
  String get threadId {
    requireIdentity();
    return _identity!.threadId;
  }

  @override
  String get inputId {
    requireIdentity();
    return _identity!.inputId;
  }

  @override
  String get runtimeEpoch {
    requireIdentity();
    return _identity!.runtimeEpoch;
  }

  @override
  int get incarnation {
    requireIdentity();
    return _incarnation!;
  }

  @override
  Future<FeedConnection<ThreadExecutionFrame>> openExecution() {
    final owner = _creation._owner;
    owner.ensureOpen();
    _checkStable();
    final finish = owner.registerOpening();
    final opening = _CreatedExecutionOpening();
    _openings.add(opening);
    final pending = _openExecution(opening).whenComplete(() {
      opening.settled.complete();
      finish();
    });
    pending.ignore(); // The original owner retains the raw failure and cleanup.
    return pending;
  }

  Future<FeedConnection<ThreadExecutionFrame>> _openExecution(
    _CreatedExecutionOpening opening,
  ) async {
    final owner = _creation._owner;
    try {
      final handle = await _handle.openExecution();
      final connection = FrbThreadExecutionConnection.fromHandle(
        threadId: _threadId,
        handle: handle,
      );
      opening.connection =
          connection; // Adopt before any fallible identity work.
      await connection.opened;
      _checkStable();
      final identity = feedIdentityFromBridge(handle.identity());
      if (identity.facet != ThreadFacet.execution ||
          identity.runtimeEpoch != runtimeEpoch ||
          identity.incarnation != incarnation) {
        throw adapterProtocol('created-input-execution-feed');
      }
      owner.ensureOpen();
      // Last check and ownership transfer are one synchronous turn. There is no
      // generic query's post-await cancellation that could discard this feed.
      _openings.remove(opening);
      return connection;
    } on Object catch (error, stack) {
      final failure = owner.failure(
        error,
        stack,
        source: 'source-open-execution',
      );
      if (opening.connection == null) {
        _openings.remove(opening);
      } else {
        await _closeOpening(opening, retry: false);
      }
      Error.throwWithStackTrace(failure, stack);
    }
  }

  Future<void> _closeOpening(
    _CreatedExecutionOpening opening, {
    required bool retry,
  }) async {
    final connection = opening.connection!;
    try {
      connection.requestClose();
      final report = await (retry
          ? connection.retryClose()
          : connection.close());
      opening.report = report;
      opening.issue = null;
      if (report.outcome is CleanFeedCloseOutcome) _openings.remove(opening);
    } on Object catch (error, stack) {
      opening.issue = adapterCloseIssue(
        _creation._owner.failure(error, stack, source: 'late-feed-close'),
        stage: 'created-input-late-feed-close',
        recovery: CleanupRecovery.retryClose,
      );
    }
  }

  Future<List<FeedCloseIssue>> cleanup({required bool retry}) async {
    // No new opening can enter after the creation owner was synchronously
    // sealed. Wait for every original open and its first actual cleanup.
    final pending = _openings.toList(growable: false);
    await Future.wait(pending.map((opening) => opening.settled.future));
    for (final opening in _openings.toList(growable: false)) {
      if (opening.connection != null) {
        await _closeOpening(opening, retry: retry);
      }
    }
    return [
      for (final opening in _openings) ...[
        if (opening.report?.outcome case UnresolvedFeedCloseOutcome(
          :final issues,
        ))
          ...issues,
        ?opening.issue,
      ],
    ];
  }

  void dispose() => _handle.dispose();
}

/// Only one concrete in-progress source handoff, not a job registry/budget.
final class _CreatedExecutionOpening {
  final settled = Completer<void>();
  FrbThreadExecutionConnection? connection;
  FeedCloseReport? report;
  FeedCloseIssue? issue;
}
