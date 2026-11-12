import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/routing/app_route.dart';
import 'package:anywork/src/app/routing/application_router.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/app/theme/studio_semantic_colors.dart';
import 'package:anywork/src/features/settings/accounts/state/account_presentations.dart';
import 'package:anywork/src/features/settings/accounts/state/account_view_key_values.dart';
import 'package:anywork/src/features/settings/accounts/views/account_details_view.dart';
import 'package:anywork/src/features/settings/accounts/views/acp_account_editor_view.dart';
import 'package:anywork/src/features/settings/accounts/widgets/account_models_view.dart';
import 'package:anywork/src/features/settings/accounts/widgets/account_usage_metrics.dart';
import 'package:anywork/src/features/settings/statistics/view_models/statistics_repository_provider.dart';
import 'package:anywork/src/infrastructure/demo/statistics/demo_statistics_feed.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/acp.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/acp_scene_transport.dart';
import '../support/pump_client_future.dart';

void main() {
  testWidgets('renders all ACP quota groups without inventing unknown values', (
    tester,
  ) async {
    const presentation = AcpUsagePresentation(
      queried: true,
      updatedLabel: 'checked recently',
      groups: [
        AccountQuotaGroupPresentation(
          name: 'Gemini',
          quotas: [
            AccountQuotaPresentation(
              label: 'Fast',
              remaining: '37%',
              remainingFraction: .37,
              resetLabel: 'resets soon',
            ),
            AccountQuotaPresentation(label: 'Pro', remaining: 'unknown'),
          ],
        ),
        AccountQuotaGroupPresentation(
          name: 'Claude',
          quotas: [
            AccountQuotaPresentation(label: 'Requests', remaining: '12'),
          ],
        ),
        AccountQuotaGroupPresentation(
          name: 'Other model family',
          emptyLabel: 'no active limits',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
          extensions: const [
            StudioSemanticColors(
              eyeAccent: Colors.blue,
              activeIndicator: Colors.green,
              success: Colors.green,
              successContainer: Colors.green,
              warning: Colors.orange,
              warningContainer: Colors.orange,
            ),
          ],
        ),
        home: const Scaffold(body: AcpUsageMetrics(value: presentation)),
      ),
    );

    expect(find.text('Gemini'), findsOneWidget);
    expect(find.text('Claude'), findsOneWidget);
    expect(find.text('Fast'), findsOneWidget);
    expect(find.text('Pro'), findsOneWidget);
    expect(find.text('Requests'), findsOneWidget);
    expect(find.text('Other model family'), findsOneWidget);
    expect(find.text('no active limits'), findsOneWidget);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(AcpUsageMetrics)),
    );
    expect(find.text('${l10n.accountsRemaining} 37%'), findsOneWidget);
    expect(find.text('${l10n.accountsRemaining} 12'), findsOneWidget);
    expect(find.text('${l10n.accountsRemaining} unknown'), findsOneWidget);
    expect(
      find.text(l10n.settingsUsageUpdated('checked recently')),
      findsOneWidget,
    );
    expect(find.text(l10n.settingsUsageReset('resets soon')), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('distinguishes unqueried and failed observations', (
    tester,
  ) async {
    Future<void> pump(AcpUsagePresentation usage) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AcpUsageMetrics(value: usage)),
        ),
      );
    }

    await pump(
      const AcpUsagePresentation(status: 'state not queried', queried: false),
    );
    expect(find.text('state not queried'), findsOneWidget);

    await pump(
      const AcpUsagePresentation(status: 'invalid response', queried: true),
    );
    expect(find.text('invalid response'), findsOneWidget);
    expect(find.text('state not queried'), findsNothing);
  });

  testWidgets(
    'managed ACP editor renders preparation state and save-and-connect action',
    (tester) async {
      AcpAccountAction? triggeredAction;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            extensions: const [
              StudioSemanticColors(
                eyeAccent: Colors.blue,
                activeIndicator: Colors.green,
                success: Colors.green,
                successContainer: Colors.green,
                warning: Colors.orange,
                warningContainer: Colors.orange,
              ),
            ],
          ),
          home: Scaffold(
            body: AcpAccountEditorView(
              value: const AcpAccountEditorPresentation(
                editorId: 'editor-1',
                templateName: 'Google Antigravity',
                name: AccountTextPresentation(raw: 'Google Antigravity'),
                source: AcpAccountSource.managed,
                prepared: true,
                dirty: true,
                canSave: true,
                saveAndConnect: true,
                preparation: AcpAccountPresentation(
                  phase: AcpPresentationPhase.ready,
                  status: '受管服务器已准备',
                  subtitle: '已准备好项目托管的官方 ACP 服务器。',
                  availableActions: [AcpAccountAction.openGuide],
                  facts: [
                    AccountDisplayFact(
                      label: '路径',
                      value: '/managed/antigravity',
                    ),
                  ],
                ),
              ),
              onNameChanged: (_) {},
              onAction: (action) => triggeredAction = action,
              onLoginMethodChanged: (_) {},
              onSave: () {},
              onCancel: () {},
            ),
          ),
        ),
      );

      final l10n = AppLocalizations.of(
        tester.element(find.byType(AcpAccountEditorView)),
      );
      expect(find.text('受管服务器已准备'), findsOneWidget);
      expect(find.text('/managed/antigravity'), findsOneWidget);
      expect(find.text(l10n.acpAccountSaveAndConnect), findsOneWidget);
      expect(
        find.byKey(
          ValueKey<String>(
            AccountViewKeyValues.editorField('editor-1', 'name'),
          ),
        ),
        findsOneWidget,
      );
      final guideButton = find.byKey(
        ValueKey<String>(AccountViewKeyValues.acpAction('openGuide')),
      );
      expect(guideButton, findsOneWidget);
      await tester.ensureVisible(guideButton);
      await tester.pumpAndSettle();
      await tester.tap(guideButton);
      expect(triggeredAction, AcpAccountAction.openGuide);
    },
  );

  testWidgets(
    'AccountDetailsView renders ACP quota card, deduplicated queryUsage key, and login methods',
    (tester) async {
      AcpAccountAction? triggeredAction;
      String? selectedMethod;
      const programPath = '/managed/antigravity/1.4.5/antigravity.exe';
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            extensions: const [
              StudioSemanticColors(
                eyeAccent: Colors.blue,
                activeIndicator: Colors.green,
                success: Colors.green,
                successContainer: Colors.green,
                warning: Colors.orange,
                warningContainer: Colors.orange,
              ),
            ],
          ),
          home: Scaffold(
            body: AccountDetailsView(
              value: const AccountDetailsPresentation(
                key: AccountDisplayKey(kind: AccountKind.acp, id: 'acp-1'),
                name: 'Google Antigravity',
                canEdit: true,
                canDelete: true,
                content: AccountDetailsContent.acp(
                  AcpAccountPresentation(
                    phase: AcpPresentationPhase.connected,
                    status: '已登录',
                    subtitle: '本地受管服务运行正常，已通过 Google Antigravity 登录验证。',
                    usage: AcpUsagePresentation(
                      queried: true,
                      groups: [
                        AccountQuotaGroupPresentation(
                          name: 'Gemini',
                          quotas: [
                            AccountQuotaPresentation(
                              label: 'Gemini 2.5 Pro',
                              remaining: '80%',
                              remainingFraction: 0.8,
                            ),
                          ],
                        ),
                      ],
                    ),
                    availableActions: [
                      AcpAccountAction.queryUsage,
                      AcpAccountAction.check,
                    ],
                    primaryAction: AcpAccountAction.check,
                    loginMethods: [
                      AcpLoginMethodPresentation(
                        id: 'oauth-personal',
                        label: 'Sign in with Google',
                        description: '使用个人 Google 账号在浏览器中完成登录授权',
                        recommended: true,
                      ),
                      AcpLoginMethodPresentation(
                        id: 'other',
                        label: 'Other browser',
                      ),
                    ],
                    selectedLoginMethod: 'oauth-personal',
                    canSelectLoginMethod: true,
                    facts: [
                      AccountDisplayFact(label: '路径', value: programPath),
                    ],
                  ),
                ),
              ),
              onBack: () {},
              onEdit: () {},
              onDelete: () {},
              onSetDefault: () {},
              onRefreshUsage: () {},
              onBillingChanged: (_) {},
              onResetBilling: () {},
              onSyncModels: () {},
              modelActions: AccountModelActions(
                onEnabledChanged: (_, _) {},
                onConnectionChanged: (_, _) {},
                onCompactChanged: (_, _) {},
                onCompactPreset: (_, _) {},
                onAction: (_, _) {},
              ),
              onAcpAction: (action) => triggeredAction = action,
              onLoginMethodChanged: (id) => selectedMethod = id,
              onRetry: () {},
            ),
          ),
        ),
      );

      final l10n = AppLocalizations.of(
        tester.element(find.byType(AccountDetailsView)),
      );
      expect(find.text(l10n.acpAccountProviderChip), findsOneWidget);
      expect(find.text('已登录'), findsOneWidget);
      expect(find.text('Gemini 2.5 Pro'), findsOneWidget);
      expect(find.text(l10n.acpAuthRecommendedBadge), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is SelectableText && widget.data == programPath,
        ),
        findsOneWidget,
      );

      final queryUsageFinder = find.byKey(
        ValueKey<String>(AccountViewKeyValues.acpAction('queryUsage')),
      );
      expect(queryUsageFinder, findsOneWidget);
      await tester.tap(queryUsageFinder);
      expect(triggeredAction, AcpAccountAction.queryUsage);

      final otherMethodFinder = find.text('Other browser');
      expect(otherMethodFinder, findsOneWidget);
      await tester.ensureVisible(otherMethodFinder);
      await tester.pumpAndSettle();
      await tester.tap(otherMethodFinder);
      expect(selectedMethod, 'other');
    },
  );

  testWidgets(
    'same login flow survives navigation, duplicate input, cancellation and deletion',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

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
      var closed = false;
      Future<void> closeGraph() async {
        if (closed) return;
        closed = true;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        router.dispose();
        container.dispose();
        final report = await pumpClientFuture(
          tester,
          graph.close(
            deadline: DateTime.now().add(const Duration(seconds: 30)),
          ),
          'close ACP scene graph',
        );
        expect(report.unresolved, isEmpty);
      }

      addTearDown(closeGraph);
      try {
        await pumpClientFuture(tester, graph.initialize(), 'init ACP graph');
        final summaries = graph.accounts.observeSummaries();
        await pumpClientFuture(
          tester,
          graph.accounts.state.waitFor((state) => state.loaded),
          'accounts loaded',
        );
        await pumpClientFuture(
          tester,
          graph.acp.save(
            const AcpAccountUpdateView(
              accountId: 'antigravity-test',
              name: 'Antigravity',
              template: AcpProviderView.antigravity,
            ),
            expectedDocumentRevision: null,
          ),
          'save ACP account',
        );
        const identity = AcpAccountIdentity('antigravity-test');
        await pumpClientFuture(
          tester,
          graph.accounts.state.waitFor(
            (state) => state.account(identity) != null,
          ),
          'account observed',
        );
        final revision = graph.accounts.state.value
            .account(identity)!
            .acpConnectionRevision!;
        await pumpClientFuture(
          tester,
          summaries.release(),
          'release summaries',
        );
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
              localizationsDelegates: [
                AppLocalizations.delegate,
                ...GlobalMaterialLocalizations.delegates,
              ],
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

        Future<void> canonical(
          bool Function(AcpAuthStateView) predicate,
        ) async {
          await pumpClientFuture(
            tester,
            graph.acp.auth.waitFor(
              (resource) => predicate(
                resource.value?.stateOf(
                      identity.accountId,
                      connectionRevision: revision,
                    ) ??
                    const AcpUncheckedState(),
              ),
            ),
            'wait for ACP auth state',
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
        router.go(const SettingsRoute().location);
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
        await tester.pumpAndSettle();
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
          const AcpVerifiedState(
            checkedAt: 1,
            server: AcpSceneTransport.server,
          ),
        );
        await canonical((state) => state is AcpVerifiedState);
        expect(panel().phase, AcpPresentationPhase.connected);
        expect(transport.starts, 2);
      } finally {
        await closeGraph();
      }
    },
  );
}
