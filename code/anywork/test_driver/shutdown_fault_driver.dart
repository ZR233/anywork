import 'dart:async';

import 'package:anywork/src/app/lifecycle/exit_participant.dart';
import 'package:anywork_client/resources.dart';

import 'driver_main.dart' as driver;

/// Inject one actually faulty Driver resource into the original application
/// coordinator. The real native lifecycle port is never replaced, and these
/// external issues must reach shutdownRuntime before its sole finalizer.
Future<void> main() {
  final fault = DriverSubscriptionFault();
  return driver.runDriver(additionalParticipants: [fault.participant]);
}

final class DriverSubscriptionFault {
  StreamController<void>? _controller;
  StreamSubscription<void>? _subscription;
  Future<void>? _cancellation;
  Future<CloseReport>? _closing;
  Object? _streamError;
  StackTrace? _streamStack;

  ApplicationCloseParticipant get participant => ApplicationCloseParticipant(
    name: 'driver-subscription-fault',
    seal: seal,
    close: close,
    retryCleanup: retryCleanup,
  );

  void seal() {
    if (_controller != null) return;
    final controller = _controller = StreamController<void>(
      onCancel: () => Completer<void>().future,
    );
    _subscription = controller.stream.listen(
      null,
      onError: (Object error, StackTrace stack) {
        _streamError = error;
        _streamStack = stack;
      },
    );
    controller.addError(
      StateError('driver-injected subscription failure'),
      StackTrace.current,
    );
  }

  Future<CloseReport> close({DateTime? deadline}) =>
      _closing ??= _close(deadline);

  Future<CloseReport> _close(DateTime? deadline) async {
    seal();
    // Deliver the real stream error before cancellation enters the actual hang.
    await Future<void>.delayed(Duration.zero);
    _cancellation ??= _subscription!.cancel();
    final available = deadline?.difference(DateTime.now());
    final limit = available == null || available > const Duration(seconds: 2)
        ? const Duration(seconds: 2)
        : available;
    try {
      await _cancellation!.timeout(
        limit < Duration.zero ? Duration.zero : limit,
      );
      throw StateError('The injected cancellation unexpectedly completed');
    } on TimeoutException {
      return CloseReport(
        unresolved: [
          UnresolvedResource(
            owner: 'driver-subscription-fault',
            attemptId: const AttemptId(1),
            issues: [
              if (_streamError != null && _streamStack != null)
                const FeedCloseIssue(
                  diagnostic: StudioShutdownIssue(
                    stage: 'progress',
                    code: 'progress',
                    message: 'Driver subscription failed',
                    retryable: false,
                    correlationId: 'driver-subscription-fault',
                  ),
                  recovery: CleanupRecovery.terminal,
                ),
              const FeedCloseIssue(
                diagnostic: StudioShutdownIssue(
                  stage: 'subscriptions',
                  code: 'timeout',
                  message: 'Driver cancellation has not joined',
                  retryable: true,
                  correlationId: 'driver-subscription-fault',
                ),
                recovery: CleanupRecovery.awaitCompletion,
              ),
            ],
          ),
        ],
      );
    }
  }

  Future<CloseReport> retryCleanup({DateTime? deadline}) => _close(deadline);
}
