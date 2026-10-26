import 'dart:async';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources_ports.dart';

import 'runtime_evidence_values.dart';

const runtimeEvidenceCancelled = StudioFailure(
  code: StudioFailureCode.cancelled,
  message: 'Runtime evidence read admission is sealed',
  retryable: false,
  correlationId: 'driver-runtime-evidence',
);
const runtimeEvidenceProtocol = StudioFailure(
  code: StudioFailureCode.protocol,
  message: 'Runtime evidence source identity is inconsistent',
  retryable: false,
  correlationId: 'driver-runtime-evidence',
);

final class RuntimeIdentityCleanupUnresolved implements Exception {}

/// One actually admitted original-Session read. This is Driver work, not a new
/// Session/resource registry. The Session remains the native scope supervisor.
final class RuntimeIdentityRead {
  RuntimeIdentityRead({required this.attempt, required this.origin});
  final AttemptId attempt;
  final ThreadFacetStamp origin;
  final _result = Completer<RuntimeObservedIdentity>();
  final _completion = Completer<void>();
  MetricsIdentityReadScope? _scope;
  CloseReport? _report;
  Future<CloseReport>? _retrying;
  bool _sealed = false;
  bool _done = false;
  bool get done => _done;
  Future<RuntimeObservedIdentity> get result => _result.future;
  Future<void> get completion => _completion.future;

  void start(Future<MetricsIdentityReadScope> Function() open) {
    // Both receipts are installed before open can synchronously reenter exit.
    _result.future.ignore();
    final opening = Future<MetricsIdentityReadScope>.sync(open);
    _run(opening)
        .then<void>(
          (identity) {
            _result.complete(identity);
          },
          onError: (Object error, StackTrace stack) {
            _result.completeError(error, stack);
          },
        )
        .whenComplete(() {
          _done = true;
          _completion.complete();
        })
        .ignore();
  }

  void seal() {
    _sealed = true;
    _scope?.requestClose();
  }

  void _admit() {
    if (_sealed) throw runtimeEvidenceCancelled;
  }

  Future<RuntimeObservedIdentity> _run(
    Future<MetricsIdentityReadScope> opening,
  ) async {
    Object? failure;
    StackTrace? failureStack;
    RuntimeObservedIdentity? identity;
    try {
      final scope = await opening;
      _scope = scope;
      if (_sealed) scope.requestClose();
      _admit();
      final header = await scope.header();
      _admit();
      if (header.scope.scopeId.isEmpty ||
          header.scope.runtimeEpoch != origin.runtimeEpoch ||
          header.scope.incarnation != origin.incarnation ||
          header.scope.sourceRevision != origin.revision ||
          origin.facet != ThreadFacet.metrics) {
        throw runtimeEvidenceProtocol;
      }
      Future<String> text(ReadText value) => materializeReadText(
        value,
        read: (field, offset) {
          _admit();
          return scope.text(field, offset: offset, maxBytes: 65536);
        },
      );
      final turn = await text(header.turnId);
      _admit();
      final attempt = header.attemptId == null
          ? null
          : await text(header.attemptId!);
      _admit();
      if (turn.isEmpty || attempt == null || attempt.isEmpty) {
        throw runtimeEvidenceProtocol;
      }
      identity = RuntimeObservedIdentity(turn, attempt);
    } catch (error, stack) {
      failure = error;
      failureStack = stack;
    }
    final scope = _scope;
    if (scope != null) {
      try {
        _report = await scope.close();
        if (!_report!.complete && failure == null) {
          failure = RuntimeIdentityCleanupUnresolved();
          failureStack = StackTrace.current;
        }
      } catch (error, stack) {
        // Original Session still owns this failed close. Preserve a terminal
        // local join issue, rather than losing it behind a pure read error.
        _report = CloseReport(
          unresolved: [
            UnresolvedResource(
              owner: 'driver-runtime-evidence:scope-close',
              attemptId: attempt,
              issues: [
                FeedCloseIssue(
                  diagnostic: StudioShutdownIssue(
                    stage: 'driver-runtime-evidence',
                    code: 'scopeCloseFailed',
                    message: 'The original evidence scope close did not return a report',
                    retryable: false,
                    correlationId: error is StudioFailure
                        ? error.correlationId
                        : '',
                  ),
                  recovery: CleanupRecovery.terminal,
                ),
              ],
            ),
          ],
        );
        failure ??= error;
        failureStack ??= stack;
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
    return identity!;
  }

  Future<CloseReport> observe({DateTime? deadline, bool retry = false}) async {
    if (!await observeEvidenceCompletion(completion, () => done, deadline)) {
      return CloseReport(
        unresolved: [
          UnresolvedResource(
            owner: 'driver-runtime-evidence:read',
            attemptId: attempt,
            issues: [
              const FeedCloseIssue(
                diagnostic: StudioShutdownIssue(
                  stage: 'driver-runtime-evidence',
                  code: 'readJoinPending',
                  message: 'The original admitted evidence read has not joined',
                  retryable: true,
                  correlationId: 'driver-runtime-evidence',
                ),
                recovery: CleanupRecovery.awaitCompletion,
              ),
            ],
          ),
        ],
      );
    }
    final running = _retrying;
    if (running != null) return running;
    final report = _report;
    final scope = _scope;
    if (!retry ||
        report == null ||
        report.complete ||
        scope == null ||
        report.unresolved.any(
          (resource) => resource.issues.any(
            (issue) => issue.recovery == CleanupRecovery.terminal,
          ),
        )) {
      return report ?? CloseReport(unresolved: const []);
    }
    // Explicit cleanup only. Never reopen or replay header/text after failure.
    final cleanup = Completer<CloseReport>();
    _retrying = cleanup.future;
    Future<CloseReport>.sync(
      () =>
          report.unresolved.any(
            (resource) => resource.issues.any(
              (issue) => issue.recovery == CleanupRecovery.retryClose,
            ),
          )
          ? scope.retryCleanup(deadline: deadline)
          : scope.close(deadline: deadline),
    ).then(
      (next) {
        _report = next;
        _retrying = null;
        cleanup.complete(next);
      },
      onError: (Object error, StackTrace _) {
        final next = CloseReport(
          unresolved: [
            ...report.unresolved,
            UnresolvedResource(
              owner: 'driver-runtime-evidence:scope-close',
              attemptId: attempt,
              issues: [
                FeedCloseIssue(
                  diagnostic: StudioShutdownIssue(
                    stage: 'driver-runtime-evidence',
                    code: 'scopeCloseFailed',
                    message: 'The original evidence scope cleanup did not return a report',
                    retryable: false,
                    correlationId: error is StudioFailure
                        ? error.correlationId
                        : '',
                  ),
                  recovery: CleanupRecovery.terminal,
                ),
              ],
            ),
          ],
        );
        _report = next;
        _retrying = null;
        cleanup.complete(next);
      },
    );
    return cleanup.future;
  }
}

Future<bool> observeEvidenceCompletion(
  Future<void> completion,
  bool Function() done,
  DateTime? deadline,
) async {
  if (done()) return true;
  if (deadline == null) {
    await completion;
    return true;
  }
  final expired = Completer<void>();
  final remaining = deadline.difference(DateTime.now());
  final timer = Timer(
    remaining.isNegative ? Duration.zero : remaining,
    () => expired.complete(),
  );
  try {
    await Future.any([completion, expired.future]);
  } finally {
    timer.cancel();
  }
  return done();
}
