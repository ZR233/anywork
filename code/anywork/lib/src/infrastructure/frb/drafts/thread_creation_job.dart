part of 'new_thread_creation_port.dart';

final class _FrbThreadCreation implements NewThreadCreation {
  _FrbThreadCreation(
    this._expected, {
    String? projectId,
    String? inputId,
    bool isBegin = false,
    required Future<native.BridgeThreadCreation?> Function() open,
  }) : _expectedProject = projectId,
       _expectedInput = inputId {
    _opening.future.ignore();
    _owner = AdapterResourceOwner(
      resource: 'thread-creation',
      requestNativeClose: () {
        _handle?.requestClose();
      },
      closeNative: () => _closeNative(retry: false),
      retryNativeClose: () => _closeNative(retry: true),
      disposeNative: () {
        _source?.dispose();
        _handle!.dispose();
      },
      cancelNativeStream: _progress.cancel,
      mapFailure: draftCommandFailure,
      expectedIdentity: () => _identity?.operationId ?? '',
    );
    final finish = _owner.registerOpening();
    _progress.start(_owner, _opening.future, _checkIdentity);
    Future<native.BridgeThreadCreation?>.sync(open)
        .then<void>(
          (handle) {
            _handle = handle;
            if (handle != null) {
              try {
                _rememberIdentity(handle);
              } on Object catch (error, stack) {
                _descriptorFailure = (
                  failure: _owner.failure(error, stack, source: 'identity'),
                  stack: stack,
                );
              }
              if (_owner.isClosing) {
                try {
                  handle.requestClose();
                } on Object catch (error, stack) {
                  _owner.failure(error, stack, source: 'late-open-close');
                }
              }
            }
            _opening.complete(handle);
          },
          onError: (Object error, StackTrace stack) {
            _owner.failure(error, stack, source: 'open');
            _opening.completeError(
              isBegin ? draftBeginFailure(error) : draftCommandFailure(error),
              stack,
            );
          },
        )
        .whenComplete(finish)
        .ignore();
  }

  final OperationId _expected;
  final String? _expectedProject;
  final String? _expectedInput;
  final _opening = Completer<native.BridgeThreadCreation?>();
  final _progress = _CreationProgress();
  late final AdapterResourceOwner _owner;
  native.BridgeThreadCreation? _handle;
  wire.BridgeThreadCreationIdentity? _identity;
  ({StudioFailure failure, StackTrace stack})? _descriptorFailure;
  wire.BridgeThreadCreationOutcome? _outcome;
  Future<wire.BridgeThreadCreationOutcome>? _resultQuery;
  bool _resultSealed = false;
  _FrbCreatedInputExecutionSource? _source;
  Future<CreatedInputExecutionSource>? _sourceQuery;

  Future<bool> get opened => _opening.future.then((handle) => handle != null);

  void _rememberIdentity(native.BridgeThreadCreation handle) {
    final actual = handle.identity();
    if (actual.operationId.isEmpty ||
        _identity != null &&
            (actual.operationId != _identity!.operationId ||
                actual.projectId != _identity!.projectId ||
                actual.inputId != _identity!.inputId)) {
      throw adapterProtocol('thread-creation-identity');
    }
    _identity ??= actual;
  }

  wire.BridgeThreadCreationIdentity get _descriptor {
    if (_identity case final identity?) return identity;
    if (_descriptorFailure case final failure?) {
      Error.throwWithStackTrace(failure.failure, failure.stack);
    }
    throw adapterProtocol('thread-creation-identity-unavailable');
  }

  wire.BridgeThreadCreationIdentity _checkIdentity(
    native.BridgeThreadCreation handle,
  ) {
    _rememberIdentity(handle);
    final identity = _descriptor;
    if (identity.operationId != _expected.value ||
        identity.projectId.isEmpty ||
        identity.inputId.isEmpty ||
        _expectedProject != null && identity.projectId != _expectedProject ||
        _expectedInput != null && identity.inputId != _expectedInput) {
      throw adapterProtocol('thread-creation-target');
    }
    return identity;
  }

  @override
  OperationId get operationId => OperationId(_descriptor.operationId);
  @override
  String get projectId => _descriptor.projectId;
  @override
  String get inputId => _descriptor.inputId;
  @override
  ReadonlyLatestValue<ThreadPreparationProgress?> get progress {
    _owner.ensureOpen();
    return _progress.readonly;
  }

  Future<wire.BridgeThreadCreationOutcome> _rawResult() {
    if (_outcome case final outcome?) return Future.value(outcome);
    if (_resultQuery case final pending?) return pending;
    if (_resultSealed || _owner.isDisposed) {
      throw adapterCancelled('thread-creation-result');
    }
    final completion = Completer<wire.BridgeThreadCreationOutcome>();
    final pending = _resultQuery = completion.future;
    pending.ignore(); // Observe failure before awaiting the independent closer.
    unawaited(
      Future<wire.BridgeThreadCreationOutcome>.sync(() async {
            final handle = await _opening.future;
            if (handle == null) {
              throw adapterProtocol('thread-creation-missing');
            }
            final outcome = await handle.result();
            _outcome = outcome;
            return outcome;
          })
          .then<void>(
            completion.complete,
            onError: (Object error, StackTrace stack) {
              _owner.failure(error, stack, source: 'result');
              completion.completeError(
                CommandDispatchFailure.unknownOutcome(
                  failure: draftCommandFailure(error),
                ),
                stack,
              );
            },
          )
          .whenComplete(() {
            if (identical(_resultQuery, pending)) _resultQuery = null;
          }),
    );
    return pending;
  }

  void _requireReturnedTarget(
    wire.BridgeThreadCreationOutcome_Returned outcome,
  ) {
    final identity = _descriptor;
    final value = outcome.value;
    if (identity.operationId != _expected.value ||
        identity.projectId.isEmpty ||
        identity.inputId.isEmpty ||
        _expectedProject != null && identity.projectId != _expectedProject ||
        _expectedInput != null && identity.inputId != _expectedInput ||
        value.thread.id.isEmpty ||
        value.thread.projectId != identity.projectId ||
        value.receipt.threadId != value.thread.id ||
        value.receipt.inputId != identity.inputId) {
      throw adapterProtocol('thread-creation-returned-target');
    }
  }

  @override
  Future<StartNewThreadResult> result() async {
    final outcome = await _rawResult();
    switch (outcome) {
      case wire.BridgeThreadCreationOutcome_Returned(:final value):
        try {
          _requireReturnedTarget(outcome);
          return StartNewThreadResult(
            thread: createdThreadFromBridge(value.thread),
            receipt: submitReceiptFromBridge(value.receipt),
          );
        } on Object catch (error, stack) {
          final failure = _owner.failure(
            error,
            stack,
            source: 'returned-conversion',
          );
          // This disposition describes failure to map an actual Returned value,
          // not a fourth native variant or a made-up generic command receipt.
          Error.throwWithStackTrace(
            CommandDispatchFailure.confirmedWithoutUsableReceipt(
              failure: failure,
            ),
            stack,
          );
        }
      case wire.BridgeThreadCreationOutcome_Rejected(:final error):
        throw CommandDispatchFailure.rejected(
          failure: draftCommandFailure(error),
        );
      case wire.BridgeThreadCreationOutcome_UnknownOutcome(:final error):
        throw CommandDispatchFailure.unknownOutcome(
          failure: draftCommandFailure(error),
        );
    }
  }

  @override
  Future<CreatedInputExecutionSource> executionSource() {
    _owner.ensureOpen();
    if (_source case final source?) {
      source.requireIdentity();
      return Future.value(source);
    }
    if (_sourceQuery case final pending?) return pending;
    final query = _owner.query(() async {
      final handle = await _opening.future;
      if (handle == null) throw adapterProtocol('thread-creation-missing');
      _owner.ensureOpen();
      _checkIdentity(handle);
      final outcome = await _rawResult();
      if (outcome is! wire.BridgeThreadCreationOutcome_Returned) {
        // Preserve the real rejection/unknown classification, never fake a source.
        await result();
        throw adapterProtocol('thread-creation-source-without-returned');
      }
      _requireReturnedTarget(outcome);
      _owner.ensureOpen();
      final raw = await handle.executionSource();
      final source = _FrbCreatedInputExecutionSource(
        this,
        raw,
        outcome.value.thread.id,
      );
      _source =
          source; // Own the opaque before any descriptor conversion fails.
      source.initialize();
      source.requireIdentity();
      return source;
    });
    late final Future<CreatedInputExecutionSource> pending;
    pending = query.whenComplete(() {
      if (identical(_sourceQuery, pending)) _sourceQuery = null;
    });
    _sourceQuery = pending;
    pending.ignore();
    return pending;
  }

  Future<FeedCloseReport> _closeNative({required bool retry}) async {
    final handle = await _opening.future;
    if (handle == null) throw adapterProtocol('thread-creation-missing');
    if (_identity == null) {
      try {
        _rememberIdentity(handle);
      } on Object catch (error, stack) {
        _owner.failure(error, stack, source: 'close-identity');
      }
    }
    Future<wire.BridgeThreadCreationOutcome>? resultQuery;
    try {
      resultQuery = _rawResult();
    } on Object catch (error, stack) {
      _owner.failure(error, stack, source: 'result-join');
    }
    FeedCloseReport? report;
    Object? closeError;
    StackTrace? closeStack;
    try {
      report = feedCloseReportFromBridge(
        await (retry ? handle.retryClose() : handle.close()),
      );
    } on Object catch (error, stack) {
      closeError = error;
      closeStack = stack;
    }
    if (_identity != null &&
        report?.feedId == _identity!.operationId &&
        report?.outcome is CleanFeedCloseOutcome) {
      _resultSealed = true;
    }
    try {
      await resultQuery;
    } on Object catch (error, stack) {
      _owner.failure(error, stack, source: 'result-join');
    }
    try {
      await _sourceQuery;
    } on Object catch (error, stack) {
      _owner.failure(error, stack, source: 'source-join');
    }
    final sourceIssues =
        await _source?.cleanup(retry: retry) ?? const <FeedCloseIssue>[];
    if (closeError != null && _identity == null) {
      // There is no legitimate report envelope without the original ID. The
      // concrete source still retains any cleanup issues for the next retry.
      Error.throwWithStackTrace(closeError, closeStack!);
    }
    final issues = <FeedCloseIssue>[
      if (report?.outcome case UnresolvedFeedCloseOutcome(:final issues))
        ...issues,
      ...sourceIssues,
      if (closeError != null)
        adapterCloseIssue(
          _owner.failure(closeError, closeStack!, source: 'native-close'),
          stage: 'thread-creation-native-close',
          recovery: CleanupRecovery.retryClose,
        ),
    ];
    return FeedCloseReport(
      feedId: report?.feedId ?? _identity!.operationId,
      outcome: issues.isEmpty
          ? const FeedCloseOutcome.clean()
          : FeedCloseOutcome.unresolved(issues: List.unmodifiable(issues)),
    );
  }

  @override
  void requestClose() {
    _owner.requestClose();
    _progress.seal();
  }

  @override
  Future<FeedCloseReport> close() {
    requestClose();
    return _owner.close();
  }

  @override
  Future<FeedCloseReport> retryClose() {
    requestClose();
    return _owner.retryClose();
  }
}
