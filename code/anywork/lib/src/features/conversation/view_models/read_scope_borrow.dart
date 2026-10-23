import 'dart:async';

import 'package:anywork_client/resources.dart';

/// A presentation borrowing lifetime, not a native owner. D1 retains the actual
/// scope/open/query/permit and all unresolved cleanup even after this VM dies.
/// No scope is put in a Freezed state or rebound after its first await.
final class ReadScopeBorrow<T> {
  ReadScopeBorrow({
    required Future<T> Function() open,
    required void Function(T) requestClose,
    required Future<CloseReport> Function(T) close,
    required Future<CloseReport> Function(T) retryCleanup,
  }) : _open = open, _requestClose = requestClose, _close = close, _retry = retryCleanup;

  final Future<T> Function() _open;
  final void Function(T) _requestClose;
  final Future<CloseReport> Function(T) _close;
  final Future<CloseReport> Function(T) _retry;
  Future<T>? _opening;
  T? _scope;
  Future<CloseReport>? _closing;
  CloseReport? closeReport;
  Object? closeCause;
  StackTrace? closeTrace;
  bool retired = false;

  Future<T> open() {
    if (retired) return Future<T>.error(const StudioFailure(
      code: StudioFailureCode.cancelled, message: 'The conversation read is retired',
      retryable: false, correlationId: 'conversation-read-retired'));
    final existing = _opening;
    if (existing != null) return existing;
    final result = Future<T>.sync(_open);
    _opening = result;
    result.then<void>((scope) {
      _scope = scope;
      if (retired) _requestClose(scope);
    }, onError: (Object _, StackTrace _) {});
    return result;
  }

  void retire() {
    if (retired) return;
    retired = true;
    final scope = _scope;
    if (scope != null) _requestClose(scope);
    // This starts D1's retained cleanup. Ignoring the observation does not drop
    // a native query or claim Clean; the original D1 supervisor owns its report.
    close().ignore();
  }

  Future<CloseReport> close({bool retry = false}) {
    retired = true;
    final running = _closing;
    if (running != null) return running;
    final work = _join(retry);
    _closing = work;
    work.whenComplete(() {
      if (identical(_closing, work)) _closing = null;
    }).ignore();
    return work;
  }

  Future<CloseReport> _join(bool retry) async {
    final opening = _opening;
    if (opening == null) return CloseReport(unresolved: []);
    T scope;
    try { scope = await opening; } catch (_) {
      // No scope capability was handed over. D1 still owns any failed opening.
      return CloseReport(unresolved: []);
    }
    _requestClose(scope);
    try {
      final result = await (retry ? _retry(scope) : _close(scope));
      closeReport = result;
      return result;
    } catch (error, stack) {
      closeCause = error;
      closeTrace = stack;
      // Do not turn a broken cleanup call into a successful observation.
      rethrow;
    }
  }
}
