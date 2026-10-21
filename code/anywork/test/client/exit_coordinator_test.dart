import 'dart:async';

import 'package:anywork/src/app/studio_host_lifecycle.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_demo_transport.dart';

final class _ExitTransport extends RecordingDemoTransport {
  final entered = Completer<void>();
  final result = Completer<StudioExitReport>();
  StudioExitIntent? intent;
  int shutdownCalls = 0;

  @override
  Future<StudioExitReport> shutdownRuntime({
    required int remainingMs,
    List<StudioShutdownIssue> externalIssues = const [],
    StudioExitIntent intent = StudioExitIntent.exit,
  }) {
    this.intent = intent;
    shutdownCalls++;
    expect(externalIssues, isEmpty);
    entered.complete();
    return result.future;
  }
}

const _clean = StudioShutdownReport(
  outcome: StudioShutdownOutcome.clean,
  issues: [],
  persistence: DrainedStudioPendingPersistence(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final firstIntent in StudioExitIntent.values) {
    test(
      'exit competition keeps the first intent: ${firstIntent.name}',
      () async {
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        var arms = 0;
        int? exitCode;
        messenger.setMockMethodCallHandler(StudioHostLifecycle.channel, (
          call,
        ) async {
          if (call.method == 'beginExit') {
            arms++;
            return 30000;
          }
          if (call.method == 'finishExit') {
            exitCode = (call.arguments as Map)['exitCode'] as int;
          }
          return null;
        });
        addTearDown(
          () => messenger.setMockMethodCallHandler(
            StudioHostLifecycle.channel,
            null,
          ),
        );
        final transport = _ExitTransport();
        final notices = <(String?, bool)>[];
        var closes = 0;
        var before = 0;
        StudioExitCoordinator.beforeExit = () async {
          before++;
        };
        addTearDown(() => StudioExitCoordinator.beforeExit = null);
        StudioExitCoordinator.install(
          StudioExitCoordinator(
            transport,
            (_) {},
            readyUpdateVersion: () => '2.0.0',
            onBeginExit: (version, restart) => notices.add((version, restart)),
            closeClient: (_) async {
              closes++;
              return CloseReport();
            },
          ),
        );
        final first = StudioExitCoordinator.requestExit(intent: firstIntent);
        expect(notices, [
          ('2.0.0', firstIntent == StudioExitIntent.updateRestart),
        ]);
        final competing = StudioExitCoordinator.requestExit(
          intent: firstIntent == StudioExitIntent.exit
              ? StudioExitIntent.updateRestart
              : StudioExitIntent.exit,
        );
        expect(competing, same(first));
        await transport.entered.future;
        expect(transport.intent, firstIntent);
        transport.result.complete(
          const StudioExitReport(
            shutdown: _clean,
            updateHandoff: LaunchedStudioUpdateHandoff(version: '2.0.0'),
          ),
        );
        await first;
        expect(arms, 1);
        expect(before, 1);
        expect(closes, 1);
        expect(transport.shutdownCalls, 1);
        expect(exitCode, 0);
      },
    );
  }

  for (final failure in const [
    StudioExitReport(
      shutdown: _clean,
      updateHandoff: FailedStudioUpdateHandoff(
        code: 'installerLaunchFailed',
        message: 'Launch denied',
      ),
    ),
    StudioExitReport(
      shutdown: StudioShutdownReport(
        outcome: StudioShutdownOutcome.degraded,
        issues: [
          StudioShutdownIssue(
            stage: 'persistence',
            code: 'shutdownTimeout',
            message: 'Saving did not finish',
            retryable: false,
            correlationId: 'exit-save-timeout',
          ),
        ],
        persistence: PendingStudioPendingPersistence(count: 1),
      ),
    ),
  ]) {
    test(
      '${failure.shutdown.outcome.name} update exit failure remains readable within the first deadline',
      () async {
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final methods = <String>[];
        int? exitCode;
        messenger.setMockMethodCallHandler(StudioHostLifecycle.channel, (
          call,
        ) async {
          methods.add(call.method);
          if (call.method == 'beginExit') return 30000;
          if (call.method == 'finishExit') {
            exitCode = (call.arguments as Map)['exitCode'] as int;
          }
          return null;
        });
        addTearDown(
          () => messenger.setMockMethodCallHandler(
            StudioHostLifecycle.channel,
            null,
          ),
        );
        final transport = _ExitTransport();
        final failures = <Object>[];
        DateTime? failedAt;
        StudioExitCoordinator.install(
          StudioExitCoordinator(
            transport,
            (_) {},
            onFailure: (error) {
              failedAt = DateTime.now();
              failures.add(error);
            },
          ),
        );
        final exit = StudioExitCoordinator.requestExit(
          intent: StudioExitIntent.updateRestart,
          updateVersion: '2.0.0',
        );
        await transport.entered.future;
        transport.result.complete(failure);
        await exit.timeout(const Duration(seconds: 4));
        expect(failures, hasLength(1));
        expect(
          DateTime.now().difference(failedAt!),
          greaterThanOrEqualTo(const Duration(seconds: 1)),
          reason: 'The error needs a visible interval before the process exits',
        );
        expect(exitCode, 1);
        expect(methods.where((method) => method == 'beginExit'), hasLength(1));
        expect(methods.last, 'finishExit');
      },
    );
  }

  test('repeated exit joins the first native deadline and all custom cleanup owners', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final arming = Completer<void>();
    final armed = Completer<int>();
    var beginCalls = 0;
    messenger.setMockMethodCallHandler(StudioHostLifecycle.channel, (
      call,
    ) async {
      if (call.method == 'beginExit') {
        beginCalls++;
        arming.complete();
        return armed.future;
      }
      return null;
    });
    addTearDown(
      () =>
          messenger.setMockMethodCallHandler(StudioHostLifecycle.channel, null),
    );
    final custom = Completer<void>();
    final client = Completer<CloseReport>();
    final clientEntered = Completer<DateTime>();
    var closes = 0;
    final coordinator = StudioExitCoordinator(
      RecordingDemoTransport(),
      (_) {},
      shutdownOverride: () => custom.future,
      closeClient: (deadline) {
        closes++;
        clientEntered.complete(deadline);
        return client.future;
      },
    );
    final first = coordinator.cleanupOnly();
    await arming.future;
    expect(coordinator.cleanupOnly(), same(first));
    armed.complete(30000);
    final deadline = await clientEntered.future;
    expect(deadline.isAfter(DateTime.now()), isTrue);
    expect(
      deadline.difference(DateTime.now()) <= const Duration(seconds: 28),
      isTrue,
    );
    var finished = false;
    unawaited(
      first.then((_) {
        finished = true;
      }),
    );
    custom.complete();
    await Future<void>.value();
    expect(
      finished,
      isFalse,
      reason: 'Custom cleanup cannot bypass the Client owner',
    );
    client.complete(CloseReport());
    expect((await first).isClean, isTrue);
    expect(coordinator.cleanupOnly(), same(first));
    expect(beginCalls, 1);
    expect(closes, 1);
  });

  test(
    'beforeExit runs before cleanup and its failure does not block exit',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(StudioHostLifecycle.channel, (
        call,
      ) async {
        if (call.method == 'beginExit') return 30000;
        return null;
      });
      var hookCalls = 0;
      StudioExitCoordinator.beforeExit = () async {
        hookCalls++;
        throw StateError('tray dispose failed');
      };
      addTearDown(() {
        StudioExitCoordinator.beforeExit = null;
        return messenger.setMockMethodCallHandler(
          StudioHostLifecycle.channel,
          null,
        );
      });

      final coordinator = StudioExitCoordinator(
        RecordingDemoTransport(),
        (_) {},
        shutdownOverride: () async {},
        closeClient: (_) async => CloseReport(),
      );
      StudioExitCoordinator.install(coordinator);
      await StudioExitCoordinator.requestExit().timeout(
        const Duration(seconds: 5),
      );

      expect(hookCalls, 1);
    },
  );
}
