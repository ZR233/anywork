import 'dart:async';

import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';

/// Explicit application startup. Repository constructors and VM build methods
/// do not start native business work; start() owns that one explicit action.
final class ApplicationBootstrap {
  ApplicationBootstrap({
    required StartupRepository startup,
    required Future<void> Function(RuntimeReady ready) attachDomains,
  }) : _startup = startup,
       _attachDomains = attachDomains;

  final StartupRepository _startup;
  final Future<void> Function(RuntimeReady ready) _attachDomains;
  Future<CommandResult<RuntimeReady>>? _starting;
  CommandResult<RuntimeReady>? _runtimeResult;
  RuntimeReady? _attached;
  bool _sealed = false;

  Future<CommandResult<RuntimeReady>> start() {
    if (_sealed) return Future.error(const StudioFailure(
      code: StudioFailureCode.cancelled,
      message: 'Application startup is sealed.',
      retryable: false,
      correlationId: '',
    ));
    final pending = _starting;
    if (pending != null) return pending;
    final completion = Completer<CommandResult<RuntimeReady>>();
    final task = completion.future;
    _starting = task;
    // Registration precedes Startup.start, which can synchronously publish or
    // re-enter exit. All re-entrant start calls join this exact responsibility.
    unawaited(Future<CommandResult<RuntimeReady>>.sync(_completeStart)
      .then<void>((result) {
        completion.complete(result);
        if (identical(_starting, task)) _starting = null;
      }, onError: (Object error, StackTrace stack) {
        // The original attach/read work has joined before releasing this
        // responsibility. Only a later explicit start retries failed attach.
        completion.completeError(error, stack);
        if (identical(_starting, task)) _starting = null;
      }));
    return task;
  }

  Future<CommandResult<RuntimeReady>> _completeStart() async {
    var result = _runtimeResult;
    if (result == null) {
      // StartupRepository alone decides whether an unconfirmed native attempt
      // can retry. Once Ready is obtained, never ask it for another attempt.
      final ticket = _startup.start();
      result = await ticket.result;
    }
    final ready = switch (result) {
      AcknowledgedCommandResult<RuntimeReady>(:final value) => value,
      CommittedCommandResult<RuntimeReady>(:final value) => value,
      _ => null,
    };
    if (ready == null) return result;
    // Keep the exact command result, including its original Ready identity,
    // independently of whether this application's domain attachment succeeds.
    _runtimeResult = result;
    if (_sealed || _attached == ready) return result;
    await _attachDomains(ready);
    _attached = ready;
    return result;
  }

  void seal() {
    _sealed = true;
  }

  Future<CloseReport> close({DateTime? deadline}) async {
    seal();
    // Seal prevents another start. An in-flight original Future is kept until
    // all of its native/attach work settles; a cleared slot means it already
    // joined, not that a failed read was abandoned. Its caller keeps the exact
    // original result/error. Domain owners report native/feed/query cleanup.
    final original = _starting;
    if (original != null) {
      await original.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    }
    return CloseReport(unresolved: const []);
  }

  Future<CloseReport> retryCleanup({DateTime? deadline}) => close(deadline: deadline);
}
