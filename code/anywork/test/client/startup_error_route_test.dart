import 'package:anywork/src/app/anywork_app.dart';
import 'package:anywork/src/app/bootstrap/startup_view_model.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/diagnostics/studio_driver_keys.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pump_client_future.dart';
import 'support/application_environment.dart';

void main() {
  testWidgets('startup failure renders an explicit retry', (tester) async {
    final failure = StudioFailure(
      code: StudioFailureCode.internal,
      message: 'startup failed before any baseline',
      retryable: true,
      correlationId: 'startup-route-failure',
    );
    final environment = ApplicationTestEnvironment();
    environment.startupPort.initializeFailure = failure;
    environment.installHost();
    final graph = environment.graph;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpClientFuture(
        tester,
        environment.close(),
        'startup failure teardown',
      );
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: environment.container,
        child: AnyworkApp(
          graph: graph,
          desktopHostBuilder: (_, child) => child,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );
    expect(find.text(l10n.runtimeFatalTitle), findsOneWidget);
    expect(environment.startupPort.initializeCalls, 1);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    final retry = find.byKey(const ValueKey('runtime-fatal-retry'));
    expect(retry, findsOneWidget);
    await pumpClientFuture(
      tester,
      environment.domains.establish(catalog: false),
      'domain baselines after failed startup',
    );
    await pumpClientFuture(
      tester,
      environment.domains.selectStart(),
      'Start preparation',
    );
    await tester.tap(retry);
    await pumpClientUntil(
      tester,
      () =>
          environment.container.read(startupViewModelProvider).value?.startup
              is ReadyStartupState,
      'explicit startup retry',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(StudioDriverKeys.startPage), findsOneWidget);
    expect(environment.startupPort.initializeCalls, 2);
    expect(tester.takeException(), isNull);
    environment.releaseNativeReads();
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpClientFuture(
      tester,
      environment.close(),
      'successful startup close',
    );
  });
}
