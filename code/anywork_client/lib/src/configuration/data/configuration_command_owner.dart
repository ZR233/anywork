import 'dart:async';

import '../../../operations.dart';
import '../../../operations_ports.dart'
    show
        CommandDispatchFailure,
        RejectedCommandDispatchFailure,
        UnknownOutcomeCommandDispatchFailure,
        CommittedButUnobservedCommandDispatchFailure,
        ConfirmedWithoutUsableReceiptCommandDispatchFailure;
import '../../../resources.dart';
import '../../../resources_ports.dart'
    show
        ResourceLifetime,
        ResourceOwner,
        resourceCleanupIssue,
        resourcePendingIssue;
import 'configuration_read_fields.dart';
import 'configuration_write_context.dart';

/// Domain-private bindings of a real, typed native call. Bound methods retain
/// that original handle; no wrapper opens, owns or releases another resource.
typedef ConfigurationCallBinding<R extends Object> = ({
  String Function() callId,
  OperationId Function() operationId,
  Future<R> Function() result,
  void Function() requestClose,
  Future<FeedCloseReport> Function() close,
  Future<FeedCloseReport> Function() retryClose,
});

/// The original job can join evidence/cleanup without erasing a public result
/// into dynamic or a nullable public payload. This capability is not exported.
abstract interface class ConfigurationCallOwner implements ResourceOwner {
  String? get callId;
  bool get needsReadDependencies;
  Future<ConfigurationWriteReply> readReply();
  void synchronized(CommitReceipt? receipt);
  void observe(OperationState state);
}

/// One original native attempt, registered before begin can run or reenter.
/// The write job retains its frozen request and observation until this owner is
/// released. The native call retains the original operation permit/materials;
/// this is not another read scope or another operation admission.
final class ConfigurationCommandOwner<R extends Object>
    implements ConfigurationCallOwner {
  ConfigurationCommandOwner({
    required this.lifetime,
    required this.operationId,
    required Set<String> priorCallIds,
    required this.cleanupAttempt,
    required this.project,
    required this.find,
    required this.reconcile,
    required this.changed,
  }) : priorCallIds = Set.unmodifiable(priorCallIds),
       attempt = lifetime.nextAttempt() {
    lifetime.register(this);
  }

  final ResourceLifetime lifetime;
  final OperationId operationId;
  // Only this live business job's bounded CAS attempts, not runtime history.
  final Set<String> priorCallIds;
  final Future<void>? Function() cleanupAttempt;
  final ConfigurationWriteReply Function(R) project;
  final Future<ConfigurationCallBinding<R>?> Function() find;
  final Future<void> Function(ConfigurationCallOwner) reconcile;
  final void Function() changed;
  @override
  final int attempt;
  @override
  String get owner => 'configuration:call:${operationId.value}:$attempt';
  final Completer<void> _settled = Completer();
  final Map<String, FeedCloseIssue> _faults = {};
  final Set<FeedCloseIssue> _terminal = {};
  ConfigurationCallBinding<R>? _call;
  String? _callId;
  R? _reply;
  FeedCloseReport? _report;
  Future<void>? _cleaning;
  Future<void>? _publicAttempt;
  Future<void>? _attemptCleanup;
  bool _started = false;
  bool _beginIssued = false;
  bool _admissionRejected = false;
  bool _identityValid = false;
  bool _closing = false;
  bool _rejected = false;
  bool _commitConfirmed = false;
  bool _targetsSynchronized = false;
  bool _observed = false;
  bool _closeAttempted = false;
  bool _released = false;
  bool _scheduled = false;

  @override
  String? get callId => _callId;
  @override
  bool get needsReadDependencies =>
      !_released && !_admissionRejected && !_rejected && !_observed;
  @override
  bool get released => _released;

  Future<R> start(Future<ConfigurationCallBinding<R>> Function() begin) {
    if (_started) throw StateError('A Configuration call can only begin once.');
    _started = true;
    final done = Completer<R>();
    Future<R> work;
    try {
      work = lifetime.accepted(this, () async {
        _beginIssued = true;
        ConfigurationCallBinding<R> call;
        try {
          call = await begin();
        } catch (error, stack) {
          if (error is RejectedCommandDispatchFailure) {
            // This is native call admission, not the admitted worker's CAS
            // result. In particular, never find/join an existing conflicting
            // request after an explicit rejection of this begin.
            _admissionRejected = true;
            rethrow;
          }
          _rememberCommit(error);
          remember('begin', error, stack);
          // A lost reply is never permission to begin again. A null lookup is
          // not proof that the original invocation was not registered.
          final ConfigurationCallBinding<R>? found;
          try {
            found = await _findOriginal();
          } catch (_) {
            Error.throwWithStackTrace(error, stack);
          }
          if (found == null) Error.throwWithStackTrace(error, stack);
          call = found;
        }
        _adopt(call);
        return readResult();
      });
    } catch (error, stack) {
      work = Future.error(error, stack);
    }
    unawaited(
      work.then<void>(
        (reply) {
          _settled.complete();
          done.complete(reply);
          changed();
        },
        onError: (Object error, StackTrace stack) {
          _settled.complete();
          done.completeError(
            _beginIssued
                ? error
                : RejectedCommandDispatchFailure(
                    failure: configurationFailure(error),
                  ),
            stack,
          );
          changed();
        },
      ),
    );
    return done.future;
  }

  void _rememberCommit(Object error) {
    if (error is CommittedButUnobservedCommandDispatchFailure ||
        error is ConfirmedWithoutUsableReceiptCommandDispatchFailure)
      _commitConfirmed = true;
  }

  Future<ConfigurationCallBinding<R>?> _findOriginal() async {
    try {
      return await find();
    } catch (error, stack) {
      remember('find', error, stack);
      // A rejected lookup is not rejection of the original mutation.
      Error.throwWithStackTrace(
        UnknownOutcomeCommandDispatchFailure(failure: _failure(error)),
        stack,
      );
    }
  }

  void _adopt(ConfigurationCallBinding<R> call) {
    // Retain even a malformed handoff; never operate on a foreign operation.
    _call = call;
    try {
      final id = call.callId();
      if (id.isEmpty ||
          call.operationId() != operationId ||
          priorCallIds.contains(id)) {
        throw configurationProtocol(
          'The Configuration call changed its original invocation identity.',
        );
      }
      _callId = id;
      _identityValid = true;
      _faults.remove('begin');
      _faults.remove('find');
    } catch (error, stack) {
      remember('identity', error, stack, CleanupRecovery.terminal);
      rethrow;
    }
  }

  /// Only joins the original call/result. It is also used to recover a lost
  /// result during cleanup; it never reads current targets or repeats begin.
  Future<R> readResult() async {
    if (_call == null) {
      final found = await _findOriginal();
      if (found == null)
        throw configurationProtocol(
          'The original Configuration call is not visible; its outcome remains unresolved.',
        );
      _adopt(found);
    }
    if (!_identityValid)
      throw configurationProtocol(
        'The original Configuration call has no verified identity.',
      );
    final cached = _reply;
    if (cached != null) return cached;
    try {
      final reply = await _call!.result();
      _commitConfirmed = true;
      _reply = reply;
      _faults.remove('result');
      return reply;
    } catch (error, stack) {
      if (error is RejectedCommandDispatchFailure) {
        if (_commitConfirmed) {
          final problem = configurationProtocol(
            'A known Configuration commit cannot later become a rejection.',
          );
          remember('result', problem, stack, CleanupRecovery.terminal);
          Error.throwWithStackTrace(problem, stack);
        }
        _rejected = true;
        _faults.remove('result');
        rethrow;
      }
      _rememberCommit(error);
      remember('result', error, stack);
      rethrow;
    }
  }

  @override
  Future<ConfigurationWriteReply> readReply() async =>
      project(await readResult());

  @override
  void synchronized(CommitReceipt? receipt) {
    final reply = _reply;
    if (reply == null ||
        project(reply).receipt != receipt ||
        receipt != null && receipt.operationId != operationId) {
      throw configurationProtocol(
        'Configuration call observation changed its original receipt.',
      );
    }
    // A null receipt is valid only for the cached, typed reload reply. The
    // caller reaches here after joining all of that reply's real targets.
    _targetsSynchronized = true;
  }

  @override
  void observe(OperationState state) {
    final reply = _reply;
    if (!_targetsSynchronized || reply == null) return;
    final receipt = project(reply).receipt;
    if (state.observed &&
        (receipt == null ? state.acknowledged : state.receipt == receipt)) {
      _observed = true;
      _scheduleCleanup();
    }
  }

  void _scheduleCleanup() {
    if (_scheduled || _released || _closeAttempted) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      cleanup(retry: false).ignore();
    });
  }

  @override
  void requestClose() {
    // Seal asks to join original work, not to cancel an admitted CAS or discard
    // the materials still needed by its Configuration and Models observations.
    _closing = true;
  }

  void remember(
    String stage,
    Object error,
    StackTrace stack, [
    CleanupRecovery recovery = CleanupRecovery.retryClose,
  ]) {
    lifetime.lastCause = error;
    lifetime.lastStack = stack;
    _faults[stage] = resourceCleanupIssue(_failure(error), recovery);
  }

  StudioFailure _failure(Object error) => error is CommandDispatchFailure
      ? error.failure
      : configurationFailure(error);

  @override
  Future<void> cleanup({required bool retry}) {
    final attempt = cleanupAttempt();
    if (attempt == null) return _cleanup(retry: retry);
    if (identical(_publicAttempt, attempt)) return _attemptCleanup!;
    final done = Completer<void>();
    _publicAttempt = attempt;
    _attemptCleanup = done.future;
    // Both write-lane joining and lifetime cleanup consume this one result,
    // including a failed native retry. Only a later public attempt can retry.
    // Publish before cleanup can synchronously reenter this owner.
    unawaited(
      Future<void>.sync(() => _cleanup(retry: retry)).then<void>(
        (_) {
          done.complete();
        },
        onError: (Object error, StackTrace stack) {
          done.completeError(error, stack);
        },
      ),
    );
    void forgetAttempt() {
      if (!identical(_publicAttempt, attempt)) return;
      _publicAttempt = null;
      _attemptCleanup = null;
    }

    unawaited(
      attempt.then<void>(
        (_) => forgetAttempt(),
        onError: (Object _, StackTrace __) => forgetAttempt(),
      ),
    );
    return done.future;
  }

  Future<void> _cleanup({required bool retry}) {
    if (_cleaning case final pending?) return pending;
    if (_released) return Future.value();
    final done = Completer<void>();
    _cleaning = done.future;
    unawaited(
      Future<void>.sync(() async {
        await _settled.future;
        if (!_beginIssued || _admissionRejected) {
          // Admission failed before creating a native call. No synthetic call
          // or FeedCloseReport is needed for that rejected admission.
          _faults.clear();
          _released = true;
          return;
        }
        if ((!_observed && !_rejected || _call == null) &&
            (_closing || retry)) {
          try {
            await reconcile(this);
            _faults.remove('reconcile');
          } catch (error, stack) {
            remember('reconcile', error, stack);
          }
        }
        if (!_identityValid || !_observed && !_rejected) return;
        final call = _call!;
        if (_closeAttempted && !retry) return;
        _closeAttempted = true;
        try {
          try {
            call.requestClose();
            _faults.remove('request');
          } catch (error, stack) {
            remember('request', error, stack);
          }
          final report = await (retry ? call.retryClose() : call.close());
          if (report.feedId != _callId)
            throw configurationProtocol(
              'The Configuration call close report changed its callId.',
            );
          _report = report;
          _faults.remove('close');
          if (report.outcome case UnresolvedFeedCloseOutcome(:final issues)) {
            _terminal.addAll(
              issues.where(
                (issue) => issue.recovery == CleanupRecovery.terminal,
              ),
            );
          } else {
            // Real close proves release, independently of earlier transport or
            // observation diagnostics. It does not rewrite the business result.
            _faults.removeWhere(
              (_, issue) => issue.recovery != CleanupRecovery.terminal,
            );
            _released = _terminal.isEmpty && _faults.isEmpty;
          }
        } catch (error, stack) {
          remember('close', error, stack);
        }
      }).then<void>(
        (_) {
          _cleaning = null;
          done.complete();
          changed();
        },
        onError: (Object error, StackTrace stack) {
          remember('cleanup', error, stack);
          _cleaning = null;
          done.complete();
          changed();
        },
      ),
    );
    return done.future;
  }

  @override
  List<FeedCloseIssue> get issues => [
    ..._faults.values,
    ..._terminal,
    if (_report?.outcome case UnresolvedFeedCloseOutcome(:final issues))
      ...issues,
    if (!_released && !_settled.isCompleted)
      resourcePendingIssue('configurationCallPending'),
    if (!_released &&
        _settled.isCompleted &&
        !_identityValid &&
        _beginIssued &&
        !_admissionRejected)
      resourcePendingIssue('originalConfigurationCallUnresolved'),
    if (!_released && _identityValid && !_rejected && !_observed)
      resourcePendingIssue('originalConfigurationTargetsUnobserved'),
    if (_cleaning != null)
      resourcePendingIssue('configurationCallCleanupPending'),
  ];
}
