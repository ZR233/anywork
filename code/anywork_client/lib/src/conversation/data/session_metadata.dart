import 'dart:async';

import '../../../resources_ports.dart';
import '../../../workspace.dart'
    show ThreadMetadata, ThreadMetadataState, WorkspaceThreadRecord;
import 'connection_owner.dart';

/// The Session's existing metadata registration, including unstarted admitted
/// preparation. Clean values may be reused without reviving their resources.
final class ConversationSessionMetadata {
  ConversationSessionMetadata({
    required this.threadId,
    required this.budget,
    required this.nextAttempt,
    required this.open,
    required this.onValue,
  });
  final String threadId;
  final ResourceBudget budget;
  final AttemptId Function() nextAttempt;
  final ThreadMetadata Function() open;
  final void Function(WorkspaceThreadRecord) onValue;
  final Map<AttemptId, ConversationMetadataRead> _owned = {};
  ConversationMetadataRead? _current;
  bool _sealed = false;

  ConversationMetadataRead _register() {
    final attempt = nextAttempt();
    final read = ConversationMetadataRead(
      threadId: threadId,
      attemptId: attempt,
      budget: budget,
      open: open,
      onValue: onValue,
      onReleased: (owner) {
        if (identical(_owned[attempt], owner)) _owned.remove(attempt);
      },
    );
    _owned[attempt] = read;
    _current = read;
    return read;
  }

  Future<WorkspaceThreadRecord> readForUi() {
    if (_sealed) throw conversationCancelled;
    final previous = _current;
    final read = previous != null && !previous.failed && !previous.released
        ? previous
        : _register();
    read.startForUi();
    return read.value;
  }

  ConversationMetadataBorrow? reserve({required bool allowNew}) {
    final previous = _current;
    final closed = _sealed || !allowNew;
    if (previous != null &&
        !previous.failed &&
        (!closed || previous._started || previous.result != null))
      return previous.borrow();
    if (closed) return null;
    return _register().borrow();
  }

  void seal() {
    _sealed = true;
    for (final read in List.of(_owned.values)) {
      read.requestClose();
    }
  }

  Future<CloseReport> close({DateTime? deadline, bool retry = false}) async {
    seal();
    final reports = await Future.wait([
      for (final read in List.of(_owned.values))
        read.close(deadline: deadline, retry: retry),
    ]);
    return conversationCloseReport([
      for (final report in reports) ...report.unresolved,
    ]);
  }

  Future<CloseReport> retryCleanup({DateTime? deadline}) async {
    // Finishing the original pure read starts its cleanup independently of
    // Session closure. Never cancel a still-needed metadata read to retry it.
    final reads = [
      for (final read in _owned.values)
        if (read._value.isCompleted && !read.released) read,
    ];
    final reports = await Future.wait([
      for (final read in reads)
        read.observeCleanup(deadline: deadline, retry: true),
    ]);
    return conversationCloseReport([
      for (final report in reports) ...report.unresolved,
    ]);
  }
}

/// One original pure metadata read, registered in its Session before any call out.
/// Its value and its actual directory owner's cleanup are separate completions.
final class ConversationMetadataRead {
  ConversationMetadataRead({
    required this.threadId,
    required this.attemptId,
    required ResourceBudget budget,
    required ThreadMetadata Function() open,
    required void Function(WorkspaceThreadRecord) onValue,
    required void Function(ConversationMetadataRead) onReleased,
  }) : _budget = budget,
       _open = open,
       _onValue = onValue,
       _onReleased = onReleased {
    _value.future.ignore();
  }

  final String threadId;
  final AttemptId attemptId;
  final ResourceBudget _budget;
  final ThreadMetadata Function() _open;
  final void Function(WorkspaceThreadRecord) _onValue;
  final void Function(ConversationMetadataRead) _onReleased;
  final Completer<WorkspaceThreadRecord> _value = Completer();
  final Completer<void> _openSettled = Completer();
  final Completer<void> _readSettled = Completer();
  final List<FeedCloseIssue> _issues = [];
  final List<UnresolvedResource> _terminalNative = [];
  final List<({Object cause, StackTrace stack})> _causes = [];
  ThreadMetadata? _owner;
  Observation? _watch;
  ResourcePermit? _permit;
  ProductReadOrigin? _origin;
  Future<void>? _query;
  Future<void>? _joining;
  Future<void>? _nativeJoining;
  CloseReport? _nativeReport;
  FeedCloseIssue? _nativeError;
  WorkspaceThreadRecord? result;
  bool failed = false;
  bool _started = false;
  bool _uiNeeded = false;
  bool _closing = false;
  bool _watchCancelled = false;
  bool _nativeRequested = false;
  bool _nativeDone = false;
  bool _released = false;
  int _borrowers = 0;

  bool get released => _released;
  Future<WorkspaceThreadRecord> get value => _value.future;

  ConversationMetadataBorrow borrow() {
    final reserved = !_value.isCompleted;
    if (reserved) _borrowers++;
    return ConversationMetadataBorrow._(this, reserved);
  }

  void startForUi() {
    if (_closing && !_value.isCompleted) throw conversationCancelled;
    _uiNeeded = !_value.isCompleted;
    _start();
  }

  void _start() {
    if (_started || _value.isCompleted) return;
    _started = true;
    // PROBE
    print(
      '[M] start metadata $threadId\n${StackTrace.current.toString().split('\n').take(10).join('\n')}',
    );
    try {
      _permit = _budget.acquire(
        ResourceKind.pendingOperation,
        owner: 'conversation-metadata:$threadId',
      );
      if (_value.isCompleted) return;
      final owner = _open();
      _owner = owner;
      if (owner.threadId != threadId)
        throw const StudioFailure(
          code: StudioFailureCode.protocol,
          message: 'The metadata owner belongs to another Thread.',
          retryable: false,
          correlationId: 'conversation-metadata-identity',
        );
      if (_value.isCompleted) return;
      // Registration precedes the current read, including synchronous callbacks.
      final source = owner.state;
      final watched = source.watchLatest(_considerSafely);
      _watch = watched.observation;
      _considerSafely(source.value);
      if (!_value.isCompleted) {
        final done = Completer<void>();
        _query = done.future;
        unawaited(
          Future<void>.sync(owner.retry).then(
            (_) {
              _query = null;
              done.complete();
            },
            onError: (Object error, StackTrace stack) {
              _remember(error, stack);
              _fail(error, stack);
              _query = null;
              done.complete();
            },
          ),
        );
      }
    } catch (error, stack) {
      _remember(error, stack);
      _fail(error, stack);
    } finally {
      _openSettled.complete();
      if (_value.isCompleted) _startCleanup();
    }
  }

  void _considerSafely(ThreadMetadataState state) {
    if (_value.isCompleted) return;
    try {
      if (state.readError case final error?) throw error;
      final projection = state.projection;
      if (projection.sync.error case final error?) throw error;
      if (projection.sync.phase == ResourceSyncPhase.failed)
        throw const StudioFailure(
          code: StudioFailureCode.protocol,
          message: 'Failed metadata has no typed source error.',
          retryable: false,
          correlationId: 'conversation-metadata-failure',
        );
      if (projection.sync.phase == ResourceSyncPhase.closed)
        throw conversationCancelled;
      if (projection.stamp case final stamp?) {
        if (_origin != null && _origin != stamp.origin)
          throw const StudioFailure(
            code: StudioFailureCode.superseded,
            message: 'The original metadata source was replaced.',
            retryable: false,
            correlationId: 'conversation-metadata-source',
          );
        _origin ??= stamp.origin;
      }
      final read = state.value;
      if (read is FailedReadValue<WorkspaceThreadRecord, ProductEntityRef>)
        throw read.error;
      if (projection.sync.phase != ResourceSyncPhase.ready) return;
      if (projection.header?.reference == null)
        throw const StudioFailure(
          code: StudioFailureCode.unavailable,
          message: 'The original Thread metadata is unavailable.',
          retryable: true,
          correlationId: 'conversation-metadata-unavailable',
        );
      if (read is! ReadyReadValue<WorkspaceThreadRecord, ProductEntityRef>)
        return;
      final current = read.current;
      if (projection.stamp == null ||
          current.origin != projection.stamp!.origin ||
          current.value.id != threadId ||
          current.reference.entry < 0 ||
          current.reference.revision < 0) {
        throw const StudioFailure(
          code: StudioFailureCode.protocol,
          message:
              'The metadata value contradicts its original source or Thread.',
          retryable: false,
          correlationId: 'conversation-metadata-value',
        );
      }
      _onValue(current.value);
      result = current.value;
      _value.complete(current.value);
      _finishRead();
    } catch (error, stack) {
      _remember(error, stack);
      _fail(error, stack);
    }
  }

  void _fail(Object error, StackTrace stack) {
    if (_value.isCompleted) return;
    failed = true;
    _value.completeError(conversationFailure(error), stack);
    _finishRead();
  }

  void _finishRead() {
    _uiNeeded = false;
    if (!_readSettled.isCompleted) _readSettled.complete();
    if (!_started && !_openSettled.isCompleted) _openSettled.complete();
    _startCleanup();
  }

  void _releaseBorrow(bool reserved) {
    if (reserved) _borrowers--;
    if (!_value.isCompleted && !_uiNeeded && _borrowers == 0) {
      _fail(conversationCancelled, StackTrace.current);
    }
  }

  void requestClose() {
    _closing = true;
    _uiNeeded = false;
    // Pre-admitted archive preparation can continue across Session seal. Only
    // the pure read is retained, never the whole capture/native archive wait.
    if (_borrowers == 0 && !_value.isCompleted)
      _fail(conversationCancelled, StackTrace.current);
    if (_value.isCompleted) _startCleanup();
  }

  Future<CloseReport> close({DateTime? deadline, bool retry = false}) {
    requestClose();
    return observeCleanup(deadline: deadline, retry: retry);
  }

  Future<CloseReport> observeCleanup({
    DateTime? deadline,
    bool retry = false,
  }) async {
    await observeConversationCompletion(_readSettled.future, deadline);
    if (_value.isCompleted) {
      _startCleanup(retry: retry);
      if (_joining case final work?)
        await observeConversationCompletion(work, deadline);
    }
    return report();
  }

  void _startCleanup({bool retry = false}) {
    if (_released || !_value.isCompleted || _joining != null) return;
    final done = Completer<void>();
    _joining = done.future;
    unawaited(
      Future<void>.sync(() async {
        await _openSettled.future;
        _cancelWatch();
        final owner = _owner;
        if (owner != null) {
          if (!_nativeRequested) {
            _nativeRequested = true;
            try {
              owner.requestClose();
            } catch (error, stack) {
              _remember(error, stack);
              _nativeError = conversationIssue(
                'metadataRequestClose',
                error,
                CleanupRecovery.retryClose,
              );
            }
          }
          if (_nativeJoining == null || retry && _nativeDone && _canRetry)
            _startNative(owner, retry: retry);
        }
        // Native cancellation is already running before we await the original read.
        if (_query case final query?) await query;
        if (_nativeJoining case final native?) await native;
        if (_issues.isEmpty &&
            _terminalNative.isEmpty &&
            _nativeError == null &&
            (owner == null || _nativeReport?.complete == true)) {
          try {
            _permit?.release();
            _released = true;
          } catch (error, stack) {
            _released = false;
            _remember(error, stack);
            _issues.add(
              conversationIssue(
                'metadataPermit',
                error,
                CleanupRecovery.terminal,
              ),
            );
          }
          if (_released) _onReleased(this);
        }
        if (!_released && _permit?.isReleased == false)
          _permit!.mark(ResourcePhase.unresolved);
      }).then(
        (_) {
          _joining = null;
          done.complete();
        },
        onError: (Object error, StackTrace stack) {
          _released = false;
          _remember(error, stack);
          _issues.add(
            conversationIssue('metadataJoin', error, CleanupRecovery.terminal),
          );
          _joining = null;
          done.complete();
        },
      ),
    );
  }

  bool get _canRetry =>
      _nativeError != null ||
      (_nativeReport?.unresolved.any(
            (resource) => resource.issues.any(
              (issue) => issue.recovery != CleanupRecovery.terminal,
            ),
          ) ??
          false);

  void _startNative(ThreadMetadata owner, {required bool retry}) {
    final done = Completer<void>();
    _nativeJoining = done.future;
    _nativeDone = false;
    unawaited(
      Future<CloseReport>.sync(
        () => retry ? owner.retryCleanup() : owner.close(),
      ).then(
        (report) {
          _nativeReport = report;
          _nativeError = null;
          for (final resource in report.unresolved) {
            final terminal = resource.issues
                .where((issue) => issue.recovery == CleanupRecovery.terminal)
                .toList();
            if (terminal.isNotEmpty)
              _terminalNative.add(
                UnresolvedResource(
                  owner: resource.owner,
                  attemptId: resource.attemptId,
                  issues: terminal,
                ),
              );
          }
          _nativeDone = true;
          done.complete();
        },
        onError: (Object error, StackTrace stack) {
          _remember(error, stack);
          _nativeError = conversationIssue(
            'metadataClose',
            error,
            CleanupRecovery.retryClose,
          );
          _nativeDone = true;
          done.complete();
        },
      ),
    );
  }

  void _cancelWatch() {
    if (_watchCancelled) return;
    _watchCancelled = true;
    try {
      _watch?.cancel();
      _watch = null;
    } catch (error, stack) {
      _remember(error, stack);
      _issues.add(
        conversationIssue(
          'metadataObservation',
          error,
          CleanupRecovery.terminal,
        ),
      );
    }
  }

  void _remember(Object cause, StackTrace stack) =>
      _causes.add((cause: cause, stack: stack));

  CloseReport report() {
    if (_released) return CloseReport(unresolved: []);
    final issues = [
      ..._issues,
      if (_nativeError case final issue?) issue,
      if (!_readSettled.isCompleted ||
          !_openSettled.isCompleted ||
          _query != null ||
          _joining != null ||
          _owner != null && !_nativeDone)
        const FeedCloseIssue(
          diagnostic: StudioShutdownIssue(
            stage: 'conversationMetadata',
            code: 'metadataPending',
            message:
                'The original metadata read or cleanup is still in flight.',
            retryable: true,
            correlationId: 'conversation-metadata',
          ),
          recovery: CleanupRecovery.awaitCompletion,
        ),
    ];
    return conversationCloseReport([
      ..._terminalNative,
      ...?_nativeReport?.unresolved,
      if (issues.isNotEmpty)
        UnresolvedResource(
          owner: 'conversation-metadata:$threadId',
          attemptId: attemptId,
          issues: issues,
        ),
    ]);
  }
}

/// A reservation for this original pure task, not for a Session or UI lifetime.
final class ConversationMetadataBorrow {
  ConversationMetadataBorrow._(this.owner, this._reserved);
  final ConversationMetadataRead owner;
  final bool _reserved;
  bool _released = false;

  Future<WorkspaceThreadRecord> read() async {
    if (_released) throw conversationCancelled;
    try {
      owner._start();
      return await owner.value;
    } finally {
      release();
    }
  }

  void release() {
    if (_released) return;
    _released = true;
    owner._releaseBorrow(_reserved);
  }
}
