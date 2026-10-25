import 'dart:async';

import 'package:anywork/src/app/lifecycle/application_exit_coordinator.dart';
import 'package:anywork/src/app/lifecycle/exit_participant.dart';
import 'package:anywork/src/app/lifecycle/native_exit_host.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace_ports.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('test.anywork/exit-coordinator');
final _clean = StudioShutdownReport(
  outcome: ShutdownOutcome.clean,
  issues: [],
  persistence: PendingPersistence.drained(),
);
final _ordinaryExit = StudioExitReport(
  shutdown: _clean,
  updateHandoff: UpdateHandoff.notRequested(),
);
const _closeFailure = StudioShutdownIssue(
  stage: 'conversation',
  code: 'cancelFailed',
  message: 'Native cleanup did not finish',
  retryable: true,
  correlationId: 'exit-original-owner',
);

final class _Lifecycle implements ApplicationLifecyclePort {
  final begun = Completer<int>();
  final finalizing = Completer<void>();
  final result = Completer<StudioExitReport>();
  final finishingDiagnostics = Completer<void>();
  final diagnosticsReceipt = Completer<void>();
  final intents = <ExitIntent>[];
  final finalizerBudgets = <int>[];
  final externalReports = <List<StudioShutdownIssue>>[];
  int beginCalls = 0;
  int diagnosticsCalls = 0;

  @override
  Future<void> beginRuntimeExit({required int remainingMs}) async {
    beginCalls++;
    begun.complete(remainingMs);
  }

  @override
  Future<StudioExitReport> shutdownRuntime({
    required int remainingMs,
    required List<StudioShutdownIssue> externalIssues,
    required ExitIntent intent,
  }) {
    intents.add(intent);
    finalizerBudgets.add(remainingMs);
    externalReports.add(List.of(externalIssues));
    finalizing.complete();
    return result.future;
  }

  @override
  Future<void> finishShutdownDiagnostics() {
    diagnosticsCalls++;
    finishingDiagnostics.complete();
    return diagnosticsReceipt.future;
  }
}

final class _CloseOwner {
  _CloseOwner(this.name);
  final String name;
  final entered = Completer<DateTime?>();
  final receipt = Completer<CloseReport>();
  int seals = 0;
  int calls = 0;

  ApplicationCloseParticipant get participant => ApplicationCloseParticipant(
    name: name,
    seal: () => seals++,
    close: ({DateTime? deadline}) {
      calls++;
      entered.complete(deadline);
      return receipt.future;
    },
    retryCleanup: ({DateTime? deadline}) => receipt.future,
  );
}

final class _EditProducer implements ApplicationEditProducer {
  _EditProducer(this.handoff);
  final void Function() handoff;
  @override
  void sealAndHandoff() => handoff();
}

final class _HostCalls {
  final methods = <String>[];
  final exitCodes = <int>[];
  final armEntered = Completer<void>();
  final armReceipt = Completer<int>();

  void install() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      methods.add(call.method);
      if (call.method == 'beginExit') {
        armEntered.complete();
        return armReceipt.future;
      }
      if (call.method == 'finishExit') {
        exitCodes.add((call.arguments as Map)['exitCode'] as int);
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));
  }
}

ApplicationExitCoordinator _coordinator(
  _Lifecycle lifecycle, {
  List<ApplicationCloseParticipant> participants = const [],
  List<ApplicationEditProducer> producers = const [],
  void Function()? sealOperations,
  void Function()? detach,
  Future<void> Function()? releaseShell,
  String? Function()? updateVersion,
  Future<void> Function(Duration, bool)? notice,
}) => ApplicationExitCoordinator(
  lifecycle: lifecycle,
  host: NativeExitHost(channel: _channel),
  editProducers: _registeredProducers(producers),
  participants: participants,
  sealOperations: sealOperations ?? () {},
  detachPresentation: detach ?? () {},
  readyUpdateVersion: updateVersion ?? () => null,
  releaseDesktopShell: releaseShell,
  presentNotice: notice,
);

ApplicationEditProducerRegistry _registeredProducers(
  List<ApplicationEditProducer> producers,
) {
  final registry = ApplicationEditProducerRegistry();
  for (final producer in producers) {
    registry.register(producer);
  }
  return registry;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final firstIntent in ExitIntent.values) {
    test('competition preserves first intent, deadline and real cleanup joins: '
        '${firstIntent.name}', () async {
      final host = _HostCalls()..install();
      final lifecycle = _Lifecycle();
      final conversation = _CloseOwner('conversation');
      final updates = _CloseOwner('updates');
      final order = <String>[];
      final notices = <(Duration, bool)>[];
      final coordinator = _coordinator(
        lifecycle,
        participants: [conversation.participant, updates.participant],
        producers: [_EditProducer(() => order.add('handoff'))],
        sealOperations: () => order.add('operations-sealed'),
        detach: () => order.add('detached'),
        updateVersion: () => '2.0.0',
        notice: (remaining, allowReading) async {
          notices.add((remaining, allowReading));
        },
      );
      final first = coordinator.requestHostExit(firstIntent);
      final competing = coordinator.requestHostExit(
        firstIntent == ExitIntent.exit ? ExitIntent.updateRestart : ExitIntent.exit,
      );
      expect(competing, same(first));
      expect(order, ['handoff', 'operations-sealed', 'detached']);
      expect(conversation.seals, 1);
      expect(updates.seals, 1);
      await host.armEntered.future;
      host.armReceipt.complete(30000);
      final earlyBudget = await lifecycle.begun.future;
      final deadlines = await Future.wait([
        conversation.entered.future,
        updates.entered.future,
      ]);
      expect(earlyBudget, inInclusiveRange(1, 28000));
      for (final deadline in deadlines) {
        expect(deadline, isNotNull);
        expect(deadline!.difference(DateTime.now()).inMilliseconds,
            inInclusiveRange(1, 28000));
      }
      expect(lifecycle.intents, isEmpty,
          reason: 'Both independent close owners must finish before finalizer');
      conversation.receipt.complete(CloseReport(unresolved: []));
      await Future<void>.value();
      expect(lifecycle.intents, isEmpty);
      updates.receipt.complete(CloseReport(unresolved: []));
      await lifecycle.finalizing.future;
      expect(lifecycle.intents, [firstIntent]);
      expect(lifecycle.externalReports.single, isEmpty);
      expect(lifecycle.finalizerBudgets.single, lessThanOrEqualTo(earlyBudget));
      expect(host.methods.where((method) => method == 'showMainWindow'), hasLength(1),
          reason: 'A tray-hidden update notice must be shown before finalization');
      expect(notices.single.$2, isFalse);
      lifecycle.result.complete(_ordinaryExit);
      await lifecycle.finishingDiagnostics.future;
      expect(host.exitCodes, isEmpty,
          reason: 'Diagnostic finalization is a separate real join');
      lifecycle.diagnosticsReceipt.complete();
      await first;
      expect(lifecycle.beginCalls, 1);
      expect(lifecycle.diagnosticsCalls, 1);
      expect(conversation.calls, 1);
      expect(updates.calls, 1);
      expect(host.methods.where((method) => method == 'beginExit'), hasLength(1));
      expect(host.exitCodes, [0]);
    });
  }

  test('external unresolved issues reach the unique native finalizer before Clean',
      () async {
    final host = _HostCalls()..install();
    host.armReceipt.complete(30000);
    final lifecycle = _Lifecycle();
    final owner = _CloseOwner('conversation');
    final coordinator = _coordinator(lifecycle, participants: [owner.participant]);
    final exit = coordinator.exit(ExitIntent.exit);
    await owner.entered.future;
    final unresolved = UnresolvedResource(
      owner: 'original-session',
      attemptId: const AttemptId(7),
      issues: const [FeedCloseIssue(
        diagnostic: _closeFailure,
        recovery: CleanupRecovery.retryClose,
      )],
    );
    owner.receipt.complete(CloseReport(unresolved: [unresolved]));
    await lifecycle.finalizing.future;
    expect(lifecycle.externalReports.single, [_closeFailure]);
    expect(coordinator.state.value.unresolved, [unresolved]);
    lifecycle.result.complete(_ordinaryExit);
    await lifecycle.finishingDiagnostics.future;
    lifecycle.diagnosticsReceipt.complete();
    final report = await exit;
    expect(report.shutdown.outcome, ShutdownOutcome.degraded,
        reason: 'A violating native Clean cannot hide Dart unresolved resources');
    expect(report.shutdown.issues, contains(_closeFailure));
    expect(coordinator.state.value.unresolved, [unresolved]);
    expect(coordinator.exit(ExitIntent.updateRestart), same(exit));
    expect(lifecycle.intents, [ExitIntent.exit]);
  });

  for (final failure in [
    StudioExitReport(
      shutdown: _clean,
      updateHandoff: UpdateHandoff.failed(error: SourceStateError(
        code: 'installerLaunchFailed', message: 'Launch denied', retryable: false,
      )),
    ),
    StudioExitReport(
      shutdown: StudioShutdownReport(
        outcome: ShutdownOutcome.degraded,
        issues: [_closeFailure],
        persistence: PendingPersistence.pending(count: 1),
      ),
      updateHandoff: UpdateHandoff.notRequested(),
    ),
  ]) {
    test('${failure.shutdown.outcome.name} and installer result remain independent '
        'and host waits for visible failure notice', () async {
      final host = _HostCalls()..install();
      host.armReceipt.complete(30000);
      final lifecycle = _Lifecycle();
      final noticeEntered = Completer<Duration>();
      final noticeReceipt = Completer<void>();
      final coordinator = _coordinator(lifecycle, notice: (remaining, allowReading) {
        expect(allowReading, isTrue);
        noticeEntered.complete(remaining);
        return noticeReceipt.future;
      });
      final exit = coordinator.requestHostExit(ExitIntent.updateRestart);
      await lifecycle.finalizing.future;
      lifecycle.result.complete(failure);
      await lifecycle.finishingDiagnostics.future;
      lifecycle.diagnosticsReceipt.complete();
      final remaining = await noticeEntered.future;
      expect(remaining.inMilliseconds, inInclusiveRange(1, 30000));
      expect(coordinator.state.value.report, failure);
      expect(coordinator.state.value.failed, isTrue);
      expect(host.exitCodes, isEmpty,
          reason: 'Failure rendering/read interval cannot be bypassed by exit');
      noticeReceipt.complete();
      await exit;
      expect(host.exitCodes, [1]);
      expect(host.methods.last, 'finishExit');
      expect(lifecycle.intents, [ExitIntent.updateRestart]);
    });
  }

  test('failed edit handoff and shell release cannot block other seals or cancellation',
      () async {
    final host = _HostCalls()..install();
    host.armReceipt.complete(30000);
    final lifecycle = _Lifecycle();
    final owner = _CloseOwner('conversation');
    final calls = <String>[];
    final coordinator = _coordinator(
      lifecycle,
      producers: [
        _EditProducer(() {
          calls.add('failed-handoff');
          throw const StudioFailure(
            code: StudioFailureCode.internal,
            message: 'handoff failed', retryable: false, correlationId: 'handoff',
          );
        }),
        _EditProducer(() => calls.add('second-handoff')),
      ],
      participants: [owner.participant],
      sealOperations: () => calls.add('operations-sealed'),
      detach: () => calls.add('detached'),
      releaseShell: () async {
        calls.add('shell-release');
        throw const StudioFailure(
          code: StudioFailureCode.internal,
          message: 'shell failed', retryable: false, correlationId: 'shell',
        );
      },
    );
    final exit = coordinator.exit(ExitIntent.exit);
    expect(calls, ['failed-handoff', 'second-handoff', 'operations-sealed', 'detached']);
    expect(owner.seals, 1);
    await owner.entered.future;
    await lifecycle.begun.future;
    owner.receipt.complete(CloseReport(unresolved: []));
    await lifecycle.finalizing.future;
    expect(calls, contains('shell-release'));
    expect(lifecycle.externalReports.single.map((issue) => issue.correlationId),
        containsAll(['handoff', 'shell']));
    lifecycle.result.complete(StudioExitReport(
      shutdown: StudioShutdownReport(
        outcome: ShutdownOutcome.degraded,
        issues: lifecycle.externalReports.single,
        persistence: const PendingPersistence.drained(),
      ),
      updateHandoff: const UpdateHandoff.notRequested(),
    ));
    await lifecycle.finishingDiagnostics.future;
    lifecycle.diagnosticsReceipt.complete();
    final report = await exit;
    expect(report.shutdown.outcome, ShutdownOutcome.degraded);
    expect(lifecycle.intents, [ExitIntent.exit]);
  });
}
