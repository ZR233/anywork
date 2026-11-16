import 'dart:async';
import 'dart:io';

import 'package:anywork/src/app/studio_shutdown.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:anywork_client/lifecycle.dart';
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
  final contentResult = Completer<DartResourceCloseResult>();
  final progressResult = Completer<void>();
  final finalized = Completer<List<StudioShutdownIssue>>();
  int? beginBudget, contentBudget, finalBudget;
  bool? externalDartResourcesReported;
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
  Future<DartResourceCloseResult> cancelDartSubscriptions({
    required ClientCloseBudget budget,
  }) {
    contentBudget = budget.remaining.inMilliseconds;
    contentStarted.complete();
    return contentResult.future;
  }

  @override
  Future<DartResourceCloseResult> closeShutdownProgress({
    required ClientCloseBudget budget,
  }) async => DartResourceCloseResult();

  @override
  Future<StudioExitReport> shutdownRuntime({
    required int remainingMs,
    List<StudioShutdownIssue> externalIssues = const [],
    bool externalDartResourcesReported = false,
    StudioExitIntent intent = StudioExitIntent.exit,
  }) async {
    this.externalDartResourcesReported = externalDartResourcesReported;
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

      transport.contentResult.complete(
        DartResourceCloseResult(issues: [_contentIssue]),
      );
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
        transport.contentResult.complete(
          DartResourceCloseResult(issues: [_contentIssue]),
        );
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

  test(
    'root shares the app budget and joins before native finalization',
    () async {
      final transport = _Transport();
      final appDone = Completer<CloseReport>();
      final rootStarted = Completer<void>();
      final rootDone = Completer<CloseReport>();
      ClientCloseBudget? appBudget;
      final closing = runStudioShutdown(
        transport,
        (_) {},
        remainingMs: 10000,
        closeClient: (budget) {
          appBudget = budget;
          return appDone.future;
        },
        closeRoot: (budget) {
          expect(budget, same(appBudget));
          expect(transport.contentResult.isCompleted, isTrue);
          expect(transport.progressResult.isCompleted, isTrue);
          expect(appDone.isCompleted, isTrue);
          rootStarted.complete();
          return rootDone.future;
        },
      );
      await Future.wait([
        transport.contentStarted.future,
        transport.progressStarted.future,
      ]);
      transport.contentResult.complete(DartResourceCloseResult());
      transport.progressResult.complete();
      appDone.complete(CloseReport());
      await rootStarted.future;
      expect(transport.finalized.isCompleted, isFalse);
      rootDone.complete(CloseReport());
      await closing;
      expect(transport.finalized.isCompleted, isTrue);
      expect(transport.externalDartResourcesReported, isTrue);
    },
  );

  test(
    'one resource reported by content, app and root is merged once',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'anywork-close-identity-',
      );
      addTearDown(() => temp.delete(recursive: true));
      final logs = Directory('${temp.path}/logs')..createSync();
      final log = File('${logs.path}/errors.log');
      await IOOverrides.runZoned(
        () async {
          final transport = _Transport();
          const id = ClientResourceId('synthetic-resource', 1);
          final failure = StateError('native close failed');
          CloseReport report(String owner) => CloseReport(
            unresolved: [
              UnresolvedResource(
                resourceId: id,
                owner: owner,
                attemptId: const AttemptId(1),
                reason: failure,
              ),
            ],
          );

          final closing = runStudioShutdown(
            transport,
            (_) {},
            remainingMs: 10000,
            closeClient: (_) async => report('client-proxy'),
            closeRoot: (_) async => report('native-owner'),
          );
          await Future.wait([
            transport.contentStarted.future,
            transport.progressStarted.future,
          ]);
          transport.contentResult.complete(
            DartResourceCloseResult(resources: report('content-owner')),
          );
          transport.progressResult.complete();
          await closing;
          final issues = await transport.finalized.future;
          expect(issues, hasLength(1));
          expect(issues.single.code, 'cancelFailed');
        },
        createDirectory: (_) => logs,
        createFile: (_) => log,
      );
    },
  );

  test(
    'app and root close failures share their issue correlation with logs',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'anywork-close-errors-',
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
            closeClient: (_) => Future.error(StateError('app close failed')),
            closeRoot: (_) => Future.error(StateError('root close failed')),
          );
          await Future.wait([
            transport.contentStarted.future,
            transport.progressStarted.future,
          ]);
          transport.contentResult.complete(DartResourceCloseResult());
          transport.progressResult.complete();
          await closing;
          final issues = await transport.finalized.future;
          final client = issues.singleWhere((issue) => issue.stage == 'client');
          final root = issues.singleWhere(
            (issue) => issue.stage == 'lifecycle-root',
          );
          final contents = await log.readAsString();
          expect(contents, contains('correlation=${client.correlationId}'));
          expect(contents, contains('correlation=${root.correlationId}'));
          expect(contents, contains('app close failed'));
          expect(contents, contains('root close failed'));
        },
        createDirectory: (_) => logs,
        createFile: (_) => log,
      );
    },
  );

  test(
    'late app failure remains logged after the bounded wait expires',
    () async {
      final temp = await Directory.systemTemp.createTemp('anywork-late-close-');
      addTearDown(() => temp.delete(recursive: true));
      final logs = Directory('${temp.path}/logs')..createSync();
      final log = File('${logs.path}/errors.log');
      await IOOverrides.runZoned(
        () async {
          final transport = _Transport();
          final client = Completer<CloseReport>();
          transport.contentResult.complete(DartResourceCloseResult());
          transport.progressResult.complete();
          final report = await runStudioShutdown(
            transport,
            (_) {},
            remainingMs: 0,
            closeClient: (_) => client.future,
            closeRoot: (_) async => CloseReport(),
          );
          expect(report.shutdown.outcome, StudioShutdownOutcome.degraded);
          final issue = (await transport.finalized.future).singleWhere(
            (item) => item.stage == 'client',
          );
          client.completeError(
            StateError('late app failure'),
            StackTrace.current,
          );
          await Future<void>.delayed(Duration.zero);
          final contents = await log.readAsString();
          expect(contents, contains('stage=client-close-late'));
          expect(contents, contains('correlation=${issue.correlationId}'));
          expect(contents, contains('late app failure'));
        },
        createDirectory: (_) => logs,
        createFile: (_) => log,
      );
    },
  );
}
