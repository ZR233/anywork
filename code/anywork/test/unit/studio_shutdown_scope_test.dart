import 'dart:async';
import 'dart:io';

import 'package:anywork/src/app/studio_shutdown.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

const _contentIssue = StudioShutdownIssue(
  stage: 'product',
  code: 'cancelFailed',
  message: 'the original observation did not close',
  retryable: true,
  correlationId: 'content-cancel',
);

final class _Transport extends Fake implements StudioTransport {
  final contentStarted = Completer<void>();
  final progressStarted = Completer<void>();
  final contentResult = Completer<List<StudioShutdownIssue>>();
  final progressResult = Completer<void>();
  final finalized = Completer<List<StudioShutdownIssue>>();
  int? beginBudget, contentBudget, finalBudget;
  late final progress = StreamController<StudioShutdownProgress>(
    onCancel: () {
      progressStarted.complete();
      return progressResult.future;
    },
  );

  @override
  void sealForShutdown() {}

  @override
  Future<void> beginRuntimeExit({required int remainingMs}) async {
    beginBudget = remainingMs;
  }

  @override
  Stream<StudioShutdownProgress> subscribeShutdownProgress() => progress.stream;

  @override
  Future<List<StudioShutdownIssue>> cancelDartSubscriptions({
    required int budgetMs,
  }) {
    contentBudget = budgetMs;
    contentStarted.complete();
    return contentResult.future;
  }

  @override
  Future<StudioExitReport> shutdownRuntime({
    required int remainingMs,
    List<StudioShutdownIssue> externalIssues = const [],
    StudioExitIntent intent = StudioExitIntent.exit,
  }) async {
    finalBudget = remainingMs;
    finalized.complete(externalIssues);
    return StudioExitReport(
      shutdown: StudioShutdownReport(
        outcome: StudioShutdownOutcome.degraded,
        issues: externalIssues,
        persistence: const DrainedStudioPendingPersistence(),
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'content and progress cancel concurrently before the native finalizer',
    () async {
      final transport = _Transport();
      final closing = runStudioShutdown(transport, (_) {}, remainingMs: 10000);
      await Future.wait([
        transport.contentStarted.future,
        transport.progressStarted.future,
      ]);
      expect(transport.finalized.isCompleted, isFalse);

      transport.contentResult.complete([_contentIssue]);
      await Future<void>.value();
      expect(
        transport.finalized.isCompleted,
        isFalse,
        reason: 'The native finalizer must also wait for the progress ACK',
      );
      transport.progressResult.complete();
      final report = await closing;
      final issues = await transport.finalized.future;
      expect(issues, [_contentIssue]);
      expect(transport.beginBudget, lessThanOrEqualTo(10000));
      expect(
        transport.contentBudget,
        lessThanOrEqualTo(transport.beginBudget!),
      );
      expect(
        transport.finalBudget,
        lessThanOrEqualTo(transport.contentBudget!),
      );
      expect(report.shutdown.outcome, StudioShutdownOutcome.degraded);
      expect(report.shutdown.issues.single.correlationId, 'content-cancel');
    },
  );

  test('both cancellation failures reach the native finalizer', () async {
    final temp = await Directory.systemTemp.createTemp(
      'anywork-shutdown-test-',
    );
    addTearDown(() => temp.delete(recursive: true));
    final logs = Directory('${temp.path}/logs')..createSync();
    final log = File('${logs.path}/errors.log');
    await IOOverrides.runZoned(
      () async {
        final transport = _Transport();
        final closing = runStudioShutdown(
          transport,
          (_) {},
          remainingMs: 10000,
        );
        await Future.wait([
          transport.contentStarted.future,
          transport.progressStarted.future,
        ]);
        transport.contentResult.complete([_contentIssue]);
        transport.progressResult.completeError(
          StateError('progress cancel failed'),
        );
        final report = await closing;
        final issues = await transport.finalized.future;
        expect(issues, hasLength(2));
        expect(issues.first, _contentIssue);
        expect(issues.last.stage, 'progress');
        expect(issues.last.code, 'cancelFailed');
        expect(report.shutdown.outcome, StudioShutdownOutcome.degraded);
        expect(log.existsSync(), isTrue);
      },
      createDirectory: (_) => logs,
      createFile: (_) => log,
    );
  });
}
