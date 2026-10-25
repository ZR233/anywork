import 'dart:async';

import 'package:anywork/main.dart' as entry;
import 'package:anywork/src/app/app_bindings.dart';
import 'package:anywork/src/app/bootstrap/application_bootstrap.dart';
import 'package:anywork/src/app/bootstrap/application_launch_boundary.dart';
import 'package:anywork/src/app/bootstrap/startup_view.dart';
import 'package:anywork/src/app/bootstrap/startup_view_model.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/workspace_ports.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../anywork_client/test/support/startup_port_fixture.dart';

void main() {
  testWidgets('before-graph constructor failures use the shared startup error state and explicit retries install the application', (tester) async {
    final constructionError = StateError('The original constructor failed before creating a graph.');
    const typedError = StudioFailure(code: StudioFailureCode.unavailable,
      message: 'The assembly dependency is unavailable.', retryable: true,
      correlationId: 'assembly-original-correlation');
    final release = Completer<void>();
    final installedContainer = ProviderContainer();
    addTearDown(installedContainer.dispose);
    var attempts = 0;
    await tester.pumpWidget(createApplicationLaunch(assemble: () async {
      final attempt = ++attempts;
      if (attempt <= 2) {
        // Exercise the actual production/Driver factory's constructor failure,
        // before it can allocate repositories or initialize the real FRB port.
        await entry.createApplicationForLaunch(decorateStartup: (_) {
          throw attempt == 1 ? constructionError : typedError;
        });
        fail('The failing constructor must not return a default application.');
      }
      await release.future;
      runApp(UncontrolledProviderScope(container: installedContainer,
        child: const MaterialApp(home: Scaffold(body: Text('assembled application')))));
    }));
    await tester.pump();
    await tester.pump();

    final failureFinder = find.byType(ApplicationStartupFailureView);
    expect(attempts, 1);
    expect(failureFinder, findsOneWidget,
      reason: 'A constructor failure before any graph exists must reach the existing retryable startup view.');
    var failure = tester.widget<ApplicationStartupFailureView>(failureFinder).failure;
    expect(failure.code, StudioFailureCode.internal);
    expect(failure.correlationId, isNotEmpty);
    final container = ProviderScope.containerOf(tester.element(failureFinder));
    expect(container.read(startupViewModelProvider).requireValue.bootstrapError, same(failure));
    expect(container.exists(startupRepositoryProvider), isFalse);
    expect(container.exists(applicationBootstrapProvider), isFalse);
    expect(find.textContaining('internal · ${failure.correlationId}'), findsOneWidget);
    expect(attempts, 1);
    await tester.pump();
    expect(attempts, 1, reason: 'A rebuild is not an implicit assembly retry.');

    final retry = find.byKey(const ValueKey('runtime-fatal-retry'));
    await tester.tap(retry);
    await tester.pump();
    await tester.pump();
    failure = tester.widget<ApplicationStartupFailureView>(failureFinder).failure;
    expect(failure, same(typedError));
    expect(find.textContaining('unavailable · assembly-original-correlation'), findsOneWidget);
    expect(container.read(startupViewModelProvider).requireValue.bootstrapError, same(typedError));
    expect(attempts, 2, reason: 'The explicit retry must invoke the original factory again.');

    await tester.tap(retry);
    await tester.pump();
    expect(attempts, 3);
    expect(container.read(startupViewModelProvider).requireValue.retryPending, isTrue);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await container.read(startupViewModelProvider.notifier).retry();
    expect(attempts, 3, reason: 'A pending attempt cannot start another factory call.');
    release.complete();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('assembled application'), findsOneWidget);
    expect(failureFinder, findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('after-graph startup keeps the original Ready result when the shared view model explicitly retries attach failure', () async {
    final budget = ResourceBudget();
    final operations = OperationRegistry(clientId: 'startup-view-model', budget: budget);
    final port = ScriptedStartupPort();
    final startup = createStartupRepository(port: port, budget: budget, operations: operations);
    const failure = StudioFailure(code: StudioFailureCode.unavailable,
      message: 'The original domain attachment failed.', retryable: true,
      correlationId: 'bootstrap-attach-original');
    var attachments = 0;
    final bootstrap = ApplicationBootstrap(startup: startup, attachDomains: (_) async {
      if (++attachments == 1) throw failure;
    });
    final container = ProviderContainer(overrides: [
      startupRepositoryProvider.overrideWithValue(startup),
      applicationBootstrapProvider.overrideWithValue(bootstrap),
    ]);
    addTearDown(() async {
      container.dispose();
      operations.seal();
      port.releasePending();
      expect((await bootstrap.close()).complete, isTrue);
      expect((await startup.close()).complete, isTrue);
      expect(budget.usage, isEmpty);
    });
    await container.read(startupViewModelProvider.future);
    final notifier = container.read(startupViewModelProvider.notifier);
    final starting = notifier.retry();
    await port.completeReady();
    await starting;
    var state = container.read(startupViewModelProvider).requireValue;
    expect(state.startup, isA<ReadyStartupState>());
    expect(state.bootstrapError, same(failure));
    expect(state.retryPending, isFalse);

    await notifier.retry();
    state = container.read(startupViewModelProvider).requireValue;
    expect(state.bootstrapError, isNull);
    expect((state.startup as ReadyStartupState).result, same(ScriptedStartupPort.ready));
    expect(attachments, 2);
    expect(port.initializeCalls, 1);
    expect(port.attempts, [41]);
  });
}
