import 'dart:async';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/routing/app_route.dart';
import 'package:anywork/src/app/routing/application_router.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/settings/accounts/state/account_presentations.dart';
import 'package:anywork/src/features/settings/accounts/state/account_view_key_values.dart';
import 'package:anywork/src/features/settings/accounts/views/account_details_view.dart';
import 'package:anywork/src/features/settings/statistics/view_models/statistics_repository_provider.dart';
import 'package:anywork/src/infrastructure/demo/statistics/demo_statistics_feed.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/acp.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/acp_scene_transport.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  WidgetController.hitTestWarningShouldBeFatal = true;

  testWidgets(
    'same login flow survives navigation, duplicate input, cancellation and deletion',
    (tester) async {
      final transport = AcpSceneTransport();
      final graph = AppGraph(
        transport: transport,
        statisticsFeed: DemoStatisticsFeedPort(),
      );
      final container = ProviderContainer(
        overrides: [
          appGraphProvider.overrideWithValue(graph),
          statisticsRepositoryProvider.overrideWithValue(
            graph.statisticsRepository,
          ),
        ],
      );
      final router = createApplicationRouter();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        router.dispose();
        final report = await graph.close(
          deadline: DateTime.now().add(const Duration(seconds: 30)),
        );
        expect(report.unresolved, isEmpty);
        container.dispose();
      });
      await graph.initialize();
      final summaries = graph.accounts.observeSummaries();
      await graph.accounts.state.waitFor((state) => state.loaded);
      await graph.acp.save(
        const AcpAccountUpdateView(
          accountId: 'antigravity-test',
          name: 'Antigravity',
          provider: AcpProviderView.antigravity,
        ),
      );
      const identity = AcpAccountIdentity('antigravity-test');
      await graph.accounts.state.waitFor(
        (state) => state.account(identity) != null,
      );
      final revision = graph.accounts.state.value
          .account(identity)!
          .acpConnectionRevision!;
      await summaries.release();
      router.go(
        const AccountDetailsRoute(
          kind: AccountKind.acp,
          accountId: 'antigravity-test',
        ).location,
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: pureStudioTheme(),
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> action(String name, {bool duplicate = false}) async {
        final finder = find.byKey(
          ValueKey(AccountViewKeyValues.acpAction(name)),
        );
        expect(finder, findsOneWidget);
        await tester.ensureVisible(finder);
        await tester.pump();
        await tester.tap(finder);
        if (duplicate) await tester.tap(finder);
        await tester.pump();
      }

      Future<void> canonical(bool Function(AcpAuthStateView) predicate) async {
        await graph.acp.auth.waitFor(
          (resource) => predicate(
            resource.value?.stateOf(
                  identity.accountId,
                  connectionRevision: revision,
                ) ??
                const AcpUncheckedState(),
          ),
        );
        await tester.pump();
      }

      AcpAccountPresentation panel() =>
          (tester
                      .widget<AccountDetailsView>(
                        find.byType(AccountDetailsView),
                      )
                      .value
                      .content
                  as AcpAccountDetailsContent)
              .value;

      await action('check');
      await canonical((state) => state is AcpRequiredState);
      final first = transport.target;
      expect(panel().phase, AcpPresentationPhase.needsLogin);
      expect(panel().usage.busy, isFalse);
      expect(
        panel().availableActions,
        contains(AcpAccountAction.cancelAuthentication),
      );
      router.go(const StudioRoute().location);
      await tester.pumpAndSettle();
      router.go(
        const AccountDetailsRoute(
          kind: AccountKind.acp,
          accountId: 'antigravity-test',
        ).location,
      );
      await tester.pumpAndSettle();
      expect(transport.starts, 1);
      expect(panel().phase, AcpPresentationPhase.needsLogin);
      await tester.ensureVisible(find.text('Other browser'));
      await tester.tap(find.text('Other browser'));
      await tester.pump();
      await action('login', duplicate: true);
      await canonical((state) => state is AcpAuthenticatingState);
      expect(transport.target, first);
      expect(transport.continuations, 1);
      expect(transport.method, 'other');
      expect(
        find.byKey(ValueKey(AccountViewKeyValues.acpAction('login'))),
        findsNothing,
      );
      // Completion is an external event, never a timer or inferred browser close.
      transport.publish(
        identity.accountId,
        revision,
        AcpRequiredState(
          operationId: first!,
          server: AcpSceneTransport.server,
          methods: AcpSceneTransport.methods,
        ),
      );
      await canonical((state) => state is AcpRequiredState);
      expect(panel().phase, AcpPresentationPhase.needsLogin);
      await action('login');
      transport.publish(
        identity.accountId,
        revision,
        AcpVerifyingState(operationId: first),
      );
      await canonical((state) => state is AcpVerifyingState);
      await action('cancelAuthentication');
      await canonical((state) => state is AcpCancelledState);
      expect(transport.cancels, 1);
      expect(panel().phase, isNot(AcpPresentationPhase.connected));
      // A cancelled flow cannot be continued through the production Client.
      await expectLater(
        graph.acp.login(identity, methodId: 'browser'),
        throwsA(
          isA<StudioFailure>().having(
            (error) => error.code,
            'code',
            StudioFailureCode.conflict,
          ),
        ),
      );
      expect(transport.continuations, 2);
      await action('check');
      await canonical((state) => state is AcpRequiredState);
      expect(transport.starts, 2);
      await action('login');
      transport.publish(
        identity.accountId,
        revision,
        const AcpVerifiedState(checkedAt: 1, server: AcpSceneTransport.server),
      );
      await canonical((state) => state is AcpVerifiedState);
      expect(panel().phase, AcpPresentationPhase.connected);
      expect(transport.starts, 2);
      final delete = find.byKey(const ValueKey('account-details-delete'));
      await tester.ensureVisible(delete);
      await tester.pump();
      await tester.tap(delete);
      await tester.pumpAndSettle();
      final returned = Completer<void>();
      void observeRoute() {
        if (!returned.isCompleted &&
            router.state.topRoute?.name == SettingsRoute.name) {
          returned.complete();
        }
      }

      router.routerDelegate.addListener(observeRoute);
      try {
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(FilledButton),
          ),
        );
        await graph.accounts.state.waitFor(
          (state) => state.account(identity) == null,
        );
        // Canonical absence can precede the removal receipt and its navigation.
        // The live binding drives frames while the Router completes its event.
        observeRoute();
        await returned.future;
      } finally {
        router.routerDelegate.removeListener(observeRoute);
      }
      await tester.pumpAndSettle();
      expect(graph.accounts.state.value.account(identity), isNull);
      expect(find.byType(AccountDetailsView), findsNothing);
    },
  );
}
