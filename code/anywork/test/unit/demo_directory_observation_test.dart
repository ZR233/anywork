import 'dart:async';

import 'package:anywork/src/infrastructure/demo/studio_demo_api.dart';
import 'package:anywork_client/accounts_ports.dart';
import 'package:anywork_client/lifecycle.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/studio_ports.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Demo routes metadata by ID and publishes only changed structure', (
    tester,
  ) async {
    // The test clock keeps Demo's background prompt/title timers from racing
    // the explicit directory commands. No UI or replacement reducer is used.
    final root = ClientScope(owner: 'demo-directory-test');
    final sdkScope = root.child('sdk');
    final transport = DemoStudioTransport(
      contentScope: root.child('transport'),
    );
    final metadata = <ThreadObservationHandle>[];
    final directories = <ThreadsObservationHandle>[];

    try {
      final bootstrap = await transport.readBootstrap();
      await tester.pump(const Duration(seconds: 1));
      final b = bootstrap.threadDirectory.rows.firstWhere(
        (row) => row.isRootRow && !row.archived,
      );
      final events = await transport
          .startNewThread(
            b.workspaceId,
            const StudioPromptInput(
              inputId: 'demo-directory-input',
              text: 'Directory observation contract',
              attachmentDraftIds: [],
            ),
            ThreadModeId.auto,
            route: bootstrap.settingsState.modeModelRoutes.firstWhere(
              (route) => route.modeId == ThreadModeId.auto,
            ),
            delegationMode: DelegationMode.automatic,
            delegationPreference: DelegationPreference.balanced,
          )
          .toList();
      expect(events.whereType<NewThreadStartFailed>(), isEmpty);
      final a = events
          .whereType<NewThreadStartSucceeded>()
          .single
          .result
          .thread;
      final listEntry = sdkScope.open<ThreadsObservationHandle>(
        'directory',
        (op) => transport.openThreadsObservation(
          DirectoryQuery.withThreadIds(
            workspaceId: b.workspaceId,
            threadIds: [a.id, b.threadId],
          ),
          DirectoryWindow(limit: 1),
          resourceId: op.resourceId,
        ),
        ownership: ClientOwnership.proxy,
      );
      final list = await listEntry.ready;
      directories.add(list);
      final aEntry = sdkScope.open<ThreadObservationHandle>(
        'metadata-a',
        (op) =>
            transport.openThreadObservation(a.id, resourceId: op.resourceId),
        ownership: ClientOwnership.proxy,
      );
      final aMetadata = await aEntry.ready;
      metadata.add(aMetadata);
      final bEntry = sdkScope.open<ThreadObservationHandle>(
        'metadata-b',
        (op) => transport.openThreadObservation(
          b.threadId,
          resourceId: op.resourceId,
        ),
        ownership: ClientOwnership.proxy,
      );
      final bMetadata = await bEntry.ready;
      metadata.add(bMetadata);
      final initial = (await list.next())!;
      expect(initial.threadIds, [a.id]);
      expect(initial.nextCursor, isNotNull);
      expect((await aMetadata.next())!.row!.threadId, a.id);
      expect((await bMetadata.next())!.row!.threadId, b.threadId);

      var listCompleted = false;
      var bCompleted = false;
      final listPending = list.next().then((frame) {
        listCompleted = true;
        return frame;
      });
      final bPending = bMetadata.next().then((frame) {
        bCompleted = true;
        return frame;
      });
      final renamedPending = aMetadata.next();
      await transport.renameThread(
        a.id,
        'Renamed A',
        operationId: const OperationId('demo-directory-rename-a'),
      );
      final renamed = (await renamedPending)!;
      expect(renamed.threadId, a.id);
      expect(renamed.row!.title, 'Renamed A');
      expect(renamed.stamp.revision, greaterThan(initial.stamp.revision));
      await tester.pump();
      expect(bCompleted, isFalse, reason: 'A must not wake B metadata');
      expect(
        listCompleted,
        isFalse,
        reason: 'a revision/title change is not changed IDs or cursor',
      );

      // Removing the off-window B changes only pagination, not the visible IDs.
      // This catches a deduplicator that compares IDs but forgets nextCursor.
      var aCompleted = false;
      final aPending = aMetadata.next().then((frame) {
        aCompleted = true;
        return frame;
      });
      await transport.archiveThread(
        b.threadId,
        operationId: const OperationId('demo-directory-archive-b'),
      );
      final cursorChanged = (await listPending)!;
      expect(cursorChanged.threadIds, initial.threadIds);
      expect(cursorChanged.nextCursor, isNull);
      expect((await bPending)!.row!.archived, isTrue);
      await tester.pump();
      expect(aCompleted, isFalse, reason: 'B removal must not wake A metadata');

      // A real membership change completes the next structural demand as well.
      var bAfterArchiveCompleted = false;
      final bAfterArchive = bMetadata.next().then((frame) {
        bAfterArchiveCompleted = true;
        return frame;
      });
      final removedPending = list.next();
      await transport.archiveThread(
        a.id,
        operationId: const OperationId('demo-directory-archive-a'),
      );
      expect((await removedPending)!.threadIds, isEmpty);
      expect((await aPending)!.row!.archived, isTrue);
      await tester.pump();
      expect(bAfterArchiveCompleted, isFalse);

      final aClosing = aMetadata.next();
      final listClosing = list.next();
      for (final handle in metadata) {
        handle.requestClose();
      }
      list.requestClose();
      expect(await aClosing, isNull);
      expect(await bAfterArchive, isNull);
      expect(await listClosing, isNull);
      await Future.wait([
        for (final handle in metadata) handle.close(),
        list.close(),
      ]);
      expect(await aMetadata.next(), isNull);
      expect(await bMetadata.next(), isNull);
      expect(await list.next(), isNull);
    } finally {
      for (final handle in metadata) {
        handle.requestClose();
      }
      for (final handle in directories) {
        handle.requestClose();
      }
      await Future.wait([
        for (final handle in metadata) handle.close(),
        for (final handle in directories) handle.close(),
      ]);
      _expectCompleteDartClose(
        await transport.cancelDartSubscriptions(
          budget: ClientCloseBudget(const Duration(seconds: 5)),
        ),
      );
      expect(
        (await root.close(
          budget: ClientCloseBudget(const Duration(seconds: 5)),
        )).complete,
        isTrue,
      );
      // The automatic title's one-shot delay is not a directory demand.
      await tester.pump(const Duration(seconds: 1));
    }
  });

  testWidgets('Demo scope closes account, directory and topic consumers', (
    tester,
  ) async {
    final root = ClientScope(owner: 'demo-owned-resources');
    final sdk = root.child('sdk');
    final content = root.child('transport');
    final transport = DemoStudioTransport(contentScope: content);
    try {
      final bootstrap = await transport.readBootstrap();
      final threadId = bootstrap.threadDirectory.rows.first.threadId;
      final account = sdk.open<AccountDomainObservation>(
        'account',
        (op) => transport.openAccountObservation(
          const AccountSummariesTarget(),
          resourceId: op.resourceId,
        ),
        ownership: ClientOwnership.proxy,
      );
      final metadata = sdk.open<ThreadObservationHandle>(
        'metadata',
        (op) => transport.openThreadObservation(
          threadId,
          resourceId: op.resourceId,
        ),
        ownership: ClientOwnership.proxy,
      );
      final topic = sdk.open<ProductTopicObservation>(
        'topic',
        (op) => transport.openProductTopic(
          const LspTopic(),
          resourceId: op.resourceId,
        ),
        ownership: ClientOwnership.proxy,
      );
      final accountPort = await account.ready;
      final metadataPort = await metadata.ready;
      final topicPort = await topic.ready;
      expect(accountPort.resourceId, account.resourceId);
      expect(metadataPort.resourceId, metadata.resourceId);
      expect(topicPort.resourceId, topic.resourceId);
      expect(await accountPort.next(), isNotNull);
      expect(await metadataPort.next(), isNotNull);
      final frames = StreamIterator(topicPort.frames);
      expect(await frames.moveNext(), isTrue);
      expect(frames.current, isA<ProductTopicBaselineFrame>());
      final pendingAccount = accountPort.next();
      final pendingMetadata = metadataPort.next();
      final pendingTopic = frames.moveNext();

      // Reject a second actual owner before its factory can create anything.
      await expectLater(
        transport.openProductTopic(
          const LspTopic(),
          resourceId: topic.resourceId,
        ),
        throwsStateError,
      );
      content.requestClose();
      expect(await pendingAccount, isNull);
      expect(await pendingMetadata, isNull);
      expect(await pendingTopic, isFalse);
      final close = topicPort.close();
      expect(identical(close, topicPort.close()), isTrue);
      await close;
      await topicPort.retryClose();
      expect(await accountPort.next(), isNull);
      expect(await metadataPort.next(), isNull);
      expect(
        (await root.close(
          budget: ClientCloseBudget(const Duration(seconds: 5)),
        )).complete,
        isTrue,
      );
    } finally {
      _expectCompleteDartClose(
        await transport.cancelDartSubscriptions(
          budget: ClientCloseBudget(const Duration(seconds: 5)),
        ),
      );
      expect(
        (await root.close(
          budget: ClientCloseBudget(const Duration(seconds: 5)),
        )).complete,
        isTrue,
      );
      await tester.pump(const Duration(seconds: 1));
    }
  });

  testWidgets('Demo directory retains its late internal topic until ACK', (
    tester,
  ) async {
    final root = ClientScope(owner: 'demo-late-topic');
    final sdk = root.child('sdk');
    final content = root.child('transport');
    final transport = _DelayedTopicTransport(contentScope: content);
    try {
      final bootstrap = await transport.readBootstrap();
      final entry = sdk.open<ThreadObservationHandle>(
        'metadata',
        (op) => transport.openThreadObservation(
          bootstrap.threadDirectory.rows.first.threadId,
          resourceId: op.resourceId,
        ),
        ownership: ClientOwnership.proxy,
      );
      final port = await entry.ready;
      final pending = port.next();
      final actualTopic = await transport.created.future;
      port.requestClose();
      expect(await pending, isNull);
      final unresolved = await root.close(
        budget: ClientCloseBudget(Duration.zero),
      );
      expect(unresolved.complete, isFalse);
      expect(
        unresolved.unresolved.map((resource) => resource.resourceId),
        contains(actualTopic.resourceId),
      );
      transport.deliver.complete();
      await entry.close();
      // The late port is closed through its original entry, with no listener
      // and no baseline producer ever started. A fake must not bypass owner.
      await actualTopic.close();
      expect(
        (await root.close(
          budget: ClientCloseBudget(const Duration(seconds: 5)),
        )).complete,
        isTrue,
      );
    } finally {
      if (!transport.deliver.isCompleted) transport.deliver.complete();
      _expectCompleteDartClose(
        await transport.cancelDartSubscriptions(
          budget: ClientCloseBudget(const Duration(seconds: 5)),
        ),
      );
      expect(
        (await root.close(
          budget: ClientCloseBudget(const Duration(seconds: 5)),
        )).complete,
        isTrue,
      );
      await tester.pump(const Duration(seconds: 1));
    }
  });

  testWidgets(
    'Demo directory caches failed ACK and retries the original topic',
    (tester) async {
      final root = ClientScope(owner: 'demo-topic-failed-ack');
      final sdk = root.child('sdk');
      final transport = _ControlledTopicTransport(
        contentScope: root.child('transport'),
      );
      try {
        final bootstrap = await transport.readBootstrap();
        transport.baseline = ProductTopicBaselineFrame(
          topic: const ThreadDirectoryTopic(),
          revision: bootstrap.threadDirectory.revision,
          state: ThreadDirectoryBaseline(bootstrap.threadDirectory),
        );
        final entry = sdk.open<ThreadObservationHandle>(
          'metadata',
          (op) => transport.openThreadObservation(
            bootstrap.threadDirectory.rows.first.threadId,
            resourceId: op.resourceId,
          ),
          ownership: ClientOwnership.proxy,
        );
        final port = await entry.ready;
        expect(await port.next(), isNotNull);
        final raw = await transport.created.future;
        final pending = port.next();
        port.requestClose();
        expect(await pending, isNull);
        final close = entry.close();
        final failure = StateError('controlled topic close ACK failure');
        final failed = expectLater(close, throwsA(same(failure)));
        await raw.closeStarted.future;
        raw.closeAck.completeError(failure);
        await failed;
        expect(identical(entry.close(), close), isTrue);
        await expectLater(port.close(), throwsA(same(failure)));
        expect(raw.closeCalls, 1);
        expect(raw.retryCalls, 0);

        final retry = root.retryCleanup(
          budget: ClientCloseBudget(const Duration(seconds: 5)),
        );
        await raw.retryStarted.future;
        expect(raw.retryCalls, 1);
        raw.retryAck.complete();
        expect((await retry).complete, isTrue);
        expect(raw.closeCalls, 1);
        expect(raw.retryCalls, 1);
        expect(await port.next(), isNull);
      } finally {
        if (transport.created.isCompleted) {
          final raw = await transport.created.future;
          if (!raw.closeAck.isCompleted) raw.closeAck.complete();
          if (!raw.retryAck.isCompleted) raw.retryAck.complete();
        }
        transport.sealForShutdown();
        expect(
          (await root.retryCleanup(
            budget: ClientCloseBudget(const Duration(seconds: 5)),
          )).complete,
          isTrue,
        );
        _expectCompleteDartClose(
          await transport.cancelDartSubscriptions(
            budget: ClientCloseBudget(const Duration(seconds: 5)),
          ),
        );
        expect(
          (await root.close(
            budget: ClientCloseBudget(const Duration(seconds: 5)),
          )).complete,
          isTrue,
        );
        await tester.pump(const Duration(seconds: 1));
      }
    },
  );
  testWidgets('Demo coordinated shutdown reuses expired budget and issues', (
    tester,
  ) async {
    final root = ClientScope(owner: 'demo-coordinated-shutdown');
    final sdk = root.child('sdk');
    final transport = _ControlledTopicTransport(
      contentScope: root.child('transport'),
    );
    final (entry, raw) = await _openControlledTopic(transport, sdk);
    try {
      final budget = ClientCloseBudget(Duration.zero);
      final closing = transport.cancelDartSubscriptions(budget: budget);
      final own = await closing;
      expect(own.resources.unresolved, hasLength(1));
      expect(own.resources.unresolved.single.resourceId, entry.resourceId);
      expect(own.issues, isEmpty);
      expect(
        identical(
          closing,
          transport.cancelDartSubscriptions(
            budget: ClientCloseBudget(const Duration(seconds: 5)),
          ),
        ),
        isTrue,
      );
      await raw.closeStarted.future;
      const external = StudioShutdownIssue(
        stage: 'test-external',
        code: 'unrelatedFailure',
        message: 'Independent external problem',
        retryable: false,
        correlationId: 'independent-external-problem',
      );
      // This is the explicit coordinator boundary: one final diagnostic for
      // the merged identity, regardless of how many scopes reference it.
      final resourceIssue = StudioShutdownIssue(
        stage: 'coordinator-resource',
        code: 'unresolvedResource',
        message: own.resources.unresolved.single.reason.toString(),
        retryable: true,
        correlationId: 'merged-${entry.resourceId}',
      );
      const nonResourceIssue = StudioShutdownIssue(
        stage: 'demo-business',
        code: 'taskFailed',
        message: 'Coordinator has also reported non-resource cleanup',
        retryable: false,
        correlationId: 'coordinator-business',
      );
      final externalIssues = [external, resourceIssue, nonResourceIssue];
      final shutdown = transport.shutdownRuntime(
        remainingMs: 5000,
        externalIssues: externalIssues,
        externalDartResourcesReported: true,
      );
      expect(
        identical(shutdown, transport.shutdownRuntime(remainingMs: 5000)),
        isTrue,
      );
      var finished = false;
      final result = shutdown.then((report) {
        finished = true;
        return report;
      });
      await tester.pump();
      expect(
        finished,
        isTrue,
        reason: 'Expired original budget must not restart phase delay timers',
      );
      final report = (await result).shutdown;
      expect(report.outcome, StudioShutdownOutcome.degraded);
      expect(report.issues, externalIssues);
      expect(
        report.issues.where((issue) => identical(issue, resourceIssue)),
        hasLength(1),
      );
      expect(raw.closeCalls, 1);
      expect(raw.retryCalls, 0);

      // Returning unresolved must not discard the still-running original ACK.
      raw.closeAck.complete();
      await entry.close();
      expect(await closing, same(own));
      expect(own.resources.unresolved, hasLength(1));
    } finally {
      if (!raw.closeAck.isCompleted) raw.closeAck.complete();
      if (!raw.retryAck.isCompleted) raw.retryAck.complete();
      expect(
        (await root.close(
          budget: ClientCloseBudget(const Duration(seconds: 5)),
        )).complete,
        isTrue,
      );
      await tester.pump(const Duration(seconds: 1));
    }
  });

  for (final cancelFirst in [false, true]) {
    testWidgets(
      'Demo direct shutdown reports failed ACK${cancelFirst ? ' after standalone cancel' : ''}',
      (tester) async {
        final root = ClientScope(owner: 'demo-direct-shutdown');
        final sdk = root.child('sdk');
        final transport = _ControlledTopicTransport(
          contentScope: root.child('transport'),
          shutdownDelay: Duration.zero,
        );
        final (entry, raw) = await _openControlledTopic(transport, sdk);
        try {
          final precedingCancel = cancelFirst
              ? transport.cancelDartSubscriptions(
                  budget: ClientCloseBudget(const Duration(seconds: 5)),
                )
              : null;
          final shutdown = cancelFirst
              ? null
              : transport.shutdownRuntime(remainingMs: 5000);
          await raw.closeStarted.future;
          const sensitiveCause =
              'synthetic-private-body token=fake-test-secret';
          final failure = StateError(sensitiveCause);
          raw.closeAck.completeError(failure);
          if (precedingCancel != null) await precedingCancel;
          final report =
              (await (shutdown ?? transport.shutdownRuntime(remainingMs: 5000)))
                  .shutdown;
          expect(report.outcome, StudioShutdownOutcome.degraded);
          expect(report.issues, hasLength(1));
          expect(
            report.issues.single.message,
            'a Dart-owned resource has not confirmed cleanup',
          );
          expect(report.issues.single.message, isNot(contains(sensitiveCause)));
          final cached = await transport.cancelDartSubscriptions(
            budget: ClientCloseBudget(Duration.zero),
          );
          expect(cached.issues, isEmpty);
          expect(cached.resources.unresolved, hasLength(1));
          expect(
            cached.resources.unresolved.single.resourceId,
            entry.resourceId,
          );
          expect(cached.resources.unresolved.single.reason, same(failure));
          if (precedingCancel != null) {
            expect(await precedingCancel, same(cached));
          }
          expect(
            report.issues.single.correlationId,
            'demo-resource-${entry.resourceId}',
          );
          expect(raw.closeCalls, 1);
          await expectLater(entry.close(), throwsA(same(failure)));
        } finally {
          if (!raw.closeAck.isCompleted) raw.closeAck.complete();
          if (!raw.retryAck.isCompleted) raw.retryAck.complete();
          root.requestClose();
          // Join the cached ordinary failure before starting management cleanup.
          await entry.close().then<void>(
            (_) {},
            onError: (Object _, StackTrace _) {},
          );
          expect(
            (await root.retryCleanup(
              budget: ClientCloseBudget(const Duration(seconds: 5)),
            )).complete,
            isTrue,
          );
          expect(raw.retryCalls, 1);
          await tester.pump(const Duration(seconds: 1));
        }
      },
    );
  }
}

void _expectCompleteDartClose(DartResourceCloseResult result) {
  expect(result.resources.complete, isTrue);
  expect(result.issues, isEmpty);
}

Future<(ClientAcquisition<ProductTopicObservation>, _ControlledTopicResource)>
_openControlledTopic(
  _ControlledTopicTransport transport,
  ClientScope sdk,
) async {
  final bootstrap = await transport.readBootstrap();
  transport.baseline = ProductTopicBaselineFrame(
    topic: const ThreadDirectoryTopic(),
    revision: bootstrap.threadDirectory.revision,
    state: ThreadDirectoryBaseline(bootstrap.threadDirectory),
  );
  final baselineReady = Completer<ProductTopicFrame>();
  final entry = sdk.open<ProductTopicObservation>(
    'topic',
    (op) => transport.openProductTopic(
      const ThreadDirectoryTopic(),
      resourceId: op.resourceId,
    ),
    ownership: ClientOwnership.proxy,
    consume: (port, op) async {
      await for (final frame in port.frames) {
        if (op.closeRequested) break;
        if (!baselineReady.isCompleted) baselineReady.complete(frame);
      }
    },
  );
  await entry.ready;
  final first = await baselineReady.future;
  expect(first, isA<ProductTopicBaselineFrame>());
  return (entry, await transport.created.future);
}

final class _DelayedTopicTransport extends DemoStudioTransport {
  _DelayedTopicTransport({required super.contentScope});

  final created = Completer<ProductTopicObservation>();
  final deliver = Completer<void>();

  @override
  Future<ProductTopicObservation> openProductTopic(
    ProductTopic topic, {
    required ClientResourceId resourceId,
  }) async {
    final port = await super.openProductTopic(topic, resourceId: resourceId);
    created.complete(port);
    await deliver.future;
    return port;
  }
}

// The controlled port follows the same boundary as Demo: the real resource is
// registered as owned, and the directory receives only its scope-backed proxy.
final class _ControlledTopicTransport extends DemoStudioTransport {
  _ControlledTopicTransport({
    required super.contentScope,
    this.shutdownDelay = const Duration(milliseconds: 80),
  });

  final Duration shutdownDelay;
  @override
  Duration get shutdownPhaseDelay => shutdownDelay;

  late final ProductTopicBaselineFrame baseline;
  final created = Completer<_ControlledTopicResource>();

  @override
  Future<ProductTopicObservation> openProductTopic(
    ProductTopic topic, {
    required ClientResourceId resourceId,
  }) async {
    final entry = contentScope.open<_ControlledTopicResource>(
      'controlled-topic-owner',
      (op) async {
        final raw = _ControlledTopicResource(op.resourceId, baseline);
        created.complete(raw);
        return raw;
      },
      identity: resourceId,
    );
    await entry.ready;
    return _ControlledTopicPort(entry);
  }
}

final class _ControlledTopicResource implements ClientResource {
  _ControlledTopicResource(
    this.resourceId,
    ProductTopicBaselineFrame baseline,
  ) {
    frames.add(baseline);
  }

  @override
  final ClientResourceId resourceId;
  final frames = StreamController<ProductTopicFrame>();
  final closeStarted = Completer<void>();
  final closeAck = Completer<void>();
  final retryStarted = Completer<void>();
  final retryAck = Completer<void>();
  Future<void>? _framesClosed;
  int closeCalls = 0;
  int retryCalls = 0;

  @override
  void requestClose() => _framesClosed ??= frames.close();

  @override
  Future<void> close() async {
    closeCalls++;
    if (!closeStarted.isCompleted) closeStarted.complete();
    requestClose();
    await _framesClosed;
    await closeAck.future;
  }

  @override
  Future<void> retryClose() async {
    retryCalls++;
    if (!retryStarted.isCompleted) retryStarted.complete();
    await _framesClosed;
    await retryAck.future;
  }
}

final class _ControlledTopicPort implements ProductTopicObservation {
  _ControlledTopicPort(this.entry);

  final ClientAcquisition<_ControlledTopicResource> entry;

  @override
  ClientResourceId get resourceId => entry.resourceId;
  @override
  late final Stream<ProductTopicFrame> frames = _frames();
  Stream<ProductTopicFrame> _frames() async* {
    yield* (await entry.ready).frames.stream;
  }

  @override
  void requestClose() => entry.requestClose();
  @override
  Future<void> close() => entry.close();
  @override
  Future<void> retryClose() => entry.retryClose();
}
