import 'dart:async';
import 'dart:collection';
import 'dart:ui';

import 'package:anywork/main.dart' as entry;
import 'package:anywork/src/app/app_bindings.dart';
import 'package:anywork/src/app/bootstrap/application_assembly_failure.dart';
import 'package:anywork/src/app/bootstrap/startup_view.dart';
import 'package:anywork/src/app/bootstrap/startup_view_model.dart';
import 'package:anywork/src/app/composition/application_container.dart';
import 'package:anywork/src/app/lifecycle/exit_participant.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pump_client_future.dart';

const _assemblyFailure = StudioFailure(
  code: StudioFailureCode.unavailable,
  message: 'The application dependency failed during construction.',
  retryable: true,
  correlationId: 'assembly-original-dependency',
);
const _cleanupFailure = StudioFailure(
  code: StudioFailureCode.unavailable,
  message: 'The original cleanup owner is still unavailable.',
  retryable: true,
  correlationId: 'assembly-original-cleanup',
);

final _unresolved = UnresolvedResource(
  owner: 'retained-construction-owner',
  attemptId: AttemptId(17),
  issues: const [
    FeedCloseIssue(
      diagnostic: StudioShutdownIssue(
        stage: 'construction-owner',
        code: 'closePending',
        message: 'The original owner has not confirmed close.',
        retryable: true,
        correlationId: 'assembly-close-pending',
      ),
      recovery: CleanupRecovery.retryClose,
    ),
    FeedCloseIssue(
      diagnostic: StudioShutdownIssue(
        stage: 'construction-owner',
        code: 'joinPending',
        message: 'The original accepted task has not ended.',
        retryable: true,
        correlationId: 'assembly-join-pending',
      ),
      recovery: CleanupRecovery.awaitCompletion,
    ),
  ],
);
final _pending = CloseReport(unresolved: [_unresolved]);
final _clean = CloseReport(unresolved: const []);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'container validation and construction failures roll back real factory owners before an explicit retry can construct again',
    (tester) async {
      final hostCalls = <String>[];
      const hostChannel = MethodChannel(
        'io.github.zr233.anywork/host_lifecycle',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(hostChannel, (call) async {
        hostCalls.add(call.method);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(hostChannel, null));

      final applications = <entry.NativeApplication>[];
      final containers = <ProviderContainer>[];
      final events = <String>[];
      final firstClose = Completer<CloseReport>();
      var factoryCalls = 0;
      var cleanupRetries = 0;
      var allowCleanup = false;
      var timelineClosed = false;
      final marker = Provider<void>((ref) {
        ref.onDispose(() => events.add('container-disposed'));
      });
      addTearDown(() async {
        if (!firstClose.isCompleted) firstClose.complete(_clean);
        allowCleanup = true;
        for (final container in containers) {
          if (!events.contains('container-disposed')) container.dispose();
        }
        for (final application in applications) {
          expect(
            (await pumpClientFuture(
              tester,
              application.rollback(),
              'construction fixture cleanup',
            )).complete,
            isTrue,
          );
        }
      });

      // Keep Flutter test's error hooks: the production bootstrap still executes
      // its real same-Zone binding, beforeRun and runApp boundary.
      final flutterError = FlutterError.onError;
      final platformError = PlatformDispatcher.instance.onError;
      try {
        entry.runApplication(
          () async {
            final attempt = ++factoryCalls;
            if (attempt > 1) {
              expect(
                timelineClosed,
                isTrue,
                reason: 'The old real presentation owner must have joined.',
              );
              expect(
                applications.single.graph.conversation.active.observerCount,
                0,
              );
              expect(
                applications.single.graph.configuration.state.observerCount,
                0,
              );
              expect(applications.single.graph.budget.usage, isEmpty);
              expect(
                allowCleanup,
                isTrue,
                reason: 'Unresolved cleanup cannot admit a second factory.',
              );
            }
            final application = await entry.createApplicationForLaunch(
              additionalParticipants: [
                if (attempt == 1)
                  ApplicationCloseParticipant(
                    name: 'retained-construction-owner',
                    seal: () => events.add('owner-sealed'),
                    close: ({DateTime? deadline}) {
                      events.add('owner-close');
                      return firstClose.future;
                    },
                    retryCleanup: ({DateTime? deadline}) async {
                      cleanupRetries++;
                      return allowCleanup ? _clean : _pending;
                    },
                  ),
              ],
            );
            applications.add(application);
            expect(
              application.graph.conversation.active.observerCount,
              greaterThan(0),
              reason:
                  'The real factory has installed its timeline observation.',
            );
            if (attempt == 1) {
              application.graph.timeline.changes.listen(
                (_) {},
                onDone: () => timelineClosed = true,
              );
            }
            return application;
          },
          createContainer: (application) {
            if (factoryCalls > 1) throw _assemblyFailure;
            final parent = createApplicationContainer(application.graph);
            final container = ProviderContainer(
              parent: parent,
              overrides: [
                // All real owners match except this identity, so validation itself
                // must reject the supplied container rather than a constructor stub.
                applicationEditProducerRegistryProvider.overrideWithValue(
                  ApplicationEditProducerRegistry(),
                ),
                marker.overrideWith((ref) {
                  ref.onDispose(() {
                    events.add('container-disposed');
                    parent.dispose();
                  });
                }),
              ],
            );
            container.read(marker);
            containers.add(container);
            return container;
          },
        );
      } finally {
        FlutterError.onError = flutterError;
        PlatformDispatcher.instance.onError = platformError;
      }
      await pumpClientUntil(
        tester,
        () => events.contains('owner-close'),
        'first owner close admission',
      );
      expect(factoryCalls, 1);
      expect(events, ['container-disposed', 'owner-sealed', 'owner-close']);
      expect(() => containers.single.read(marker), throwsStateError);
      final launchContainer = ProviderScope.containerOf(
        tester.element(find.byType(ApplicationStartupView)),
      );
      expect(
        launchContainer
            .read(startupViewModelProvider)
            .requireValue
            .retryPending,
        isTrue,
      );
      await launchContainer.read(startupViewModelProvider.notifier).retry();
      expect(
        factoryCalls,
        1,
        reason: 'A pending rollback is still the first attempt.',
      );

      firstClose.complete(_pending);
      final failureFinder = find.byType(ApplicationStartupFailureView);
      await pumpClientUntil(
        tester,
        () => failureFinder.evaluate().isNotEmpty,
        'unresolved rollback presentation',
      );
      var failure = tester
          .widget<ApplicationStartupFailureView>(failureFinder)
          .failure;
      expect(failure.code, StudioFailureCode.internal);
      expect(failure.correlationId, isNotEmpty);
      expect(
        find.textContaining('internal · ${failure.correlationId}'),
        findsOneWidget,
      );
      expect(timelineClosed, isTrue);
      expect(applications.single.graph.conversation.active.observerCount, 0);

      final retry = find.byKey(const ValueKey('runtime-fatal-retry'));
      await tester.tap(retry);
      await pumpClientUntil(
        tester,
        () => !launchContainer
            .read(startupViewModelProvider)
            .requireValue
            .retryPending,
        'explicit unresolved cleanup retry',
      );
      expect(cleanupRetries, 1);
      expect(
        factoryCalls,
        1,
        reason: 'An incomplete retry retains the old owner, not a second application.',
      );
      expect(failureFinder, findsOneWidget);

      allowCleanup = true;
      await tester.tap(retry);
      await pumpClientUntil(
        tester,
        () => !launchContainer
            .read(startupViewModelProvider)
            .requireValue
            .retryPending,
        'clean rollback followed by the second factory',
      );
      expect(cleanupRetries, 2);
      expect(factoryCalls, 2);
      failure = tester
          .widget<ApplicationStartupFailureView>(failureFinder)
          .failure;
      expect(failure, same(_assemblyFailure));
      expect(
        find.textContaining('unavailable · assembly-original-dependency'),
        findsOneWidget,
      );
      expect(applications.last.graph.conversation.active.observerCount, 0);
      expect(applications.last.graph.configuration.state.observerCount, 0);
      expect(applications.last.graph.budget.usage, isEmpty);
      expect(
        hostCalls,
        isEmpty,
        reason:
            'Construction rollback must not arm or finish normal host exit.',
      );
      expect(tester.takeException(), isNull);
    },
  );

  test('partial construction retains unresolved owners and all issues through thrown and shared explicit cleanup retries', () async {
    var seals = 0;
    var closes = 0;
    var retries = 0;
    final retryReceipt = Completer<CloseReport>();
    final retryEntered = Completer<void>();
    final participant = ApplicationCloseParticipant(
      name: 'retained-construction-owner',
      seal: () => seals++,
      close: ({DateTime? deadline}) async {
        closes++;
        return _pending;
      },
      retryCleanup: ({DateTime? deadline}) async {
        retries++;
        if (retries == 1) throw _cleanupFailure;
        if (retries == 2) {
          retryEntered.complete();
          return retryReceipt.future;
        }
        return _clean;
      },
    );
    ApplicationAssemblyFailure? retained;
    try {
      await entry.createApplicationForLaunch(
        additionalParticipants: _FailingParticipants(participant),
      );
      fail(
        'A partial construction cannot return a default or Clean application.',
      );
    } on ApplicationAssemblyFailure catch (failure) {
      retained = failure;
    }
    final failure = retained;
    addTearDown(() async {
      if (!retryReceipt.isCompleted) retryReceipt.complete(_clean);
      // Complete even if an earlier assertion fails; no retained fake task or
      // real Repository is allowed to outlive this test.
      for (var attempt = 0; attempt < 3; attempt++) {
        if ((await failure.retryCleanup()).complete) return;
      }
      fail('The original construction fixture did not finish cleanup.');
    });
    expect(failure.cause, same(_assemblyFailure));
    expect(failure.report.complete, isFalse);
    expect(failure.report.unresolved, [_unresolved]);
    expect((seals, closes, retries), (1, 1, 0));

    final thrownRetry = await failure.retryCleanup();
    expect(thrownRetry.complete, isFalse);
    expect(
      thrownRetry.unresolved.first,
      _unresolved,
      reason: 'A thrown retry cannot discard the original complete typed issue set.',
    );
    final diagnostic = thrownRetry.unresolved.last.issues.single.diagnostic;
    expect(diagnostic.code, 'unavailable');
    expect(diagnostic.correlationId, 'assembly-original-cleanup');

    final firstRetry = failure.retryCleanup();
    await retryEntered.future;
    final sharedRetry = failure.retryCleanup();
    expect(
      retries,
      2,
      reason: 'Concurrent observers join the same original owner cleanup.',
    );
    expect(
      failure.report.complete,
      isFalse,
      reason: 'An in-flight retry is not Clean.',
    );
    retryReceipt.complete(_pending);
    expect((await firstRetry).unresolved, [_unresolved]);
    expect((await sharedRetry).unresolved, [_unresolved]);
    expect((seals, closes, retries), (1, 1, 2));

    expect((await failure.retryCleanup()).complete, isTrue);
    expect(failure.report.unresolved, isEmpty);
    expect((seals, closes, retries), (1, 1, 3));
    expect((await failure.retryCleanup()).complete, isTrue);
    expect(
      retries,
      3,
      reason:
          'Only truly completed owners are released and never retried again.',
    );
  });
}

/// The existing additionalParticipants seam fails only after handing over one
/// close capability. The partially accepted owner belongs to the real factory's
/// construction transaction, without adding a production test-only hook.
final class _FailingParticipants extends ListBase<ApplicationCloseParticipant> {
  _FailingParticipants(this.participant);
  final ApplicationCloseParticipant participant;

  @override
  int get length => 2;
  @override
  set length(int value) =>
      throw UnsupportedError('Read-only construction fixture');
  @override
  ApplicationCloseParticipant operator [](int index) {
    if (index == 0) return participant;
    throw _assemblyFailure;
  }

  @override
  void operator []=(int index, ApplicationCloseParticipant value) =>
      throw UnsupportedError('Read-only construction fixture');
}
