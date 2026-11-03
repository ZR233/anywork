import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/routing/app_route.dart';
import 'package:anywork/src/app/routing/application_router.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/settings/accounts/connectors/account_editor_connector.dart';
import 'package:anywork/src/features/settings/accounts/state/account_presentations.dart';
import 'package:anywork/src/features/settings/accounts/state/account_view_key_values.dart';
import 'package:anywork/src/features/settings/accounts/views/account_details_view.dart';
import 'package:anywork/src/features/settings/accounts/views/native_account_editor_view.dart';
import 'package:anywork/src/features/settings/statistics/view_models/statistics_repository_provider.dart';
import 'package:anywork/src/infrastructure/demo/statistics/demo_statistics_feed.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/accounts.dart' as domain;
import 'package:anywork_client/account_usage.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/chatgpt_scene_transport.dart';
import 'support/observed.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  WidgetController.hitTestWarningShouldBeFatal = true;

  testWidgets(
    'ChatGPT auth, cancellation, account identity and quota journey',
    (tester) async {
      final transport = ChatGptSceneTransport();
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
      final summaries = graph.accounts.observeSummaries();
      tester.testTextInput.register();
      addTearDown(() async {
        // Release an intentionally held external reply even after an assertion fails.
        if (transport.pendingUsage != null) transport.completeUsage();
        await tester.pumpWidget(const SizedBox());
        router.dispose();
        await summaries.release();
        final closed = await graph.close(
          deadline: DateTime.now().add(const Duration(seconds: 30)),
        );
        expect(closed.unresolved, isEmpty);
        container.dispose();
        tester.testTextInput.unregister();
      });
      await graph.initialize();
      await untilObserved(graph.accounts.state, (value) => value.loaded);
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
      router.go(const SettingsRoute().location);
      await tester.pumpAndSettle();

      Future<void> tap(String key, {bool duplicate = false}) async {
        final finder = find.byKey(ValueKey(key));
        expect(finder, findsOneWidget, reason: key);
        await tester.ensureVisible(finder);
        await tester.pump();
        await tester.tap(finder);
        if (duplicate) await tester.tap(finder);
        await tester.pump();
      }

      NativeAccountEditorPresentation editor() => tester
          .widget<NativeAccountEditorView>(find.byType(NativeAccountEditorView))
          .value;
      Future<void> field(String key, String text) async {
        final finder = find.descendant(
          of: find.byKey(
            ValueKey(AccountViewKeyValues.editorField(editor().editorId, key)),
          ),
          matching: find.byType(TextField),
        );
        await tester.ensureVisible(finder);
        await tester.enterText(finder, text);
        await tester.pump();
      }

      Future<void> method(String label) async {
        await tester.ensureVisible(find.text(label));
        await tester.pump();
        await tester.tap(find.text(label));
        await tester.pump();
      }

      Future<void> login(domain.ChatGptLoginPhase phase) async {
        final id = transport.logins.keys.last;
        debugPrint(
          'CHATGPT_JOURNEY login expected=$phase '
          'observed=${graph.accounts.chatGptLogin(id).value.value?.phase}',
        );
        await untilObserved(graph.accounts.chatGptLogin(id), (resource) {
          if (resource.failure case final error?) throw error;
          return resource.value?.phase == phase;
        });
        await tester.pump();
      }

      Future<void> usagePhase(
        AccountUsagePhase phase,
        domain.NativeAccountIdentity identity,
      ) async {
        debugPrint('CHATGPT_JOURNEY quota expected=$phase');
        await untilObserved(graph.accountUsage.state, (resource) {
          if (resource.failure case final error?) throw error;
          return resource.value?[identity]?.phase == phase;
        });
        if (phase == AccountUsagePhase.querying) {
          await tester.pump();
        } else {
          await tester.pumpAndSettle();
        }
      }

      Future<void> openOpenAi() async {
        await tap('account-add');
        await untilObserved(
          graph.accounts.state,
          (value) => value.templates.isUsable,
        );
        await tester.pumpAndSettle();
        final selector = find.byKey(
          const ValueKey('account-template-selector'),
        );
        await tester.tap(
          find.descendant(of: selector, matching: find.byType(IconButton)),
        );
        await tester.pumpAndSettle();
        await tap(AccountViewKeyValues.template('native', 'openai'));
        await tester.pumpAndSettle();
        expect(find.text('放弃更改'), findsOneWidget);
        await tester.tap(find.text('放弃更改'));
        await tester.pumpAndSettle();
        expect(editor().isOpenAiTemplate, isTrue);
      }

      await openOpenAi();
      debugPrint('CHATGPT_JOURNEY OpenAI template selected');
      await field('name', '订阅账户');
      await field('endpoint', 'https://custom.example.test/v1');
      await field('credential', 'api-secret-must-not-survive');
      await method('ChatGPT 订阅');
      expect(editor().credential.raw, isEmpty);
      expect(editor().canSave, isFalse);
      expect(find.text('https://custom.example.test/v1'), findsNothing);
      final connector = tester.widget<AccountEditorConnector>(
        find.byType(AccountEditorConnector),
      );
      final identity = domain.NativeAccountIdentity(connector.editor.target.id);
      expect(identity.accountId, isNot('openai'));

      await tap('chatgpt-login-start', duplicate: true);
      await login(domain.ChatGptLoginPhase.awaitingBrowser);
      expect(transport.starts, 1);
      expect(editor().canSave, isFalse);
      await tap('chatgpt-login-cancel');
      await login(domain.ChatGptLoginPhase.cancelled);
      final cancelled = transport.logins.keys.last;
      transport.loginPhase(
        cancelled,
        domain.ChatGptLoginPhase.succeeded,
        revision: 1,
      );
      await tester.pumpAndSettle();
      expect(editor().chatGptLogin?.phase, ChatGptLoginPhase.cancelled);
      expect(editor().canSave, isFalse);

      await tap('chatgpt-login-start');
      await login(domain.ChatGptLoginPhase.awaitingBrowser);
      transport.loginPhase(
        transport.logins.keys.last,
        domain.ChatGptLoginPhase.failed,
        failure: const domain.ChatGptLoginFailure(
          code: domain.ChatGptLoginFailureCode.network,
          retryable: true,
        ),
      );
      await login(domain.ChatGptLoginPhase.failed);
      expect(editor().canSave, isFalse);
      expect(find.text('无法完成 ChatGPT 登录，请重试。'), findsOneWidget);

      await tap('chatgpt-login-start');
      await login(domain.ChatGptLoginPhase.awaitingBrowser);
      transport.loginPhase(
        transport.logins.keys.last,
        domain.ChatGptLoginPhase.succeeded,
      );
      await login(domain.ChatGptLoginPhase.succeeded);
      expect(editor().canSave, isTrue);
      await method('API 密钥');
      expect(editor().credential.raw, isEmpty);
      expect(editor().endpoint.raw, 'https://custom.example.test/v1');
      expect(
        editor().canSave,
        isFalse,
        reason: 'Switching authentication requires a fresh API key',
      );
      await method('ChatGPT 订阅');
      expect(editor().canSave, isFalse);
      await tap('chatgpt-login-start');
      await login(domain.ChatGptLoginPhase.awaitingBrowser);
      transport.loginPhase(
        transport.logins.keys.last,
        domain.ChatGptLoginPhase.succeeded,
      );
      await login(domain.ChatGptLoginPhase.succeeded);
      await tap('account-save', duplicate: true);
      debugPrint('CHATGPT_JOURNEY save submitted');
      await untilObserved(
        graph.accounts.state,
        (value) => value.account(identity)?.chatgptAccount != null,
      );
      expect(
        transport.created!.authentication,
        isA<domain.SelectChatGptAuthentication>(),
      );
      final intent =
          transport.created!.authentication
              as domain.SelectChatGptAuthentication;
      expect(transport.creates, 1);
      expect(intent.editorId, connector.editor.editorId);
      expect(intent.loginId, transport.logins.keys.last);
      expect(
        transport.created!.baseUrl,
        'https://chatgpt.com/backend-api/codex',
      );
      expect(transport.created!.secret.action, AccountSecretAction.preserve);
      expect(transport.created!.secret.value, isNull);

      final detailsLocation = AccountDetailsRoute(
        kind: AccountKind.native,
        accountId: identity.accountId,
      ).location;
      debugPrint('CHATGPT_JOURNEY account saved');
      router.go(detailsLocation);
      await usagePhase(AccountUsagePhase.querying, identity);
      expect(transport.queries, 1);
      await tap('account-usage-check', duplicate: true);
      expect(transport.queries, 1);
      transport.completeUsage();
      await usagePhase(AccountUsagePhase.succeeded, identity);
      final details = tester.widget<AccountDetailsView>(
        find.byType(AccountDetailsView),
      );
      final content =
          (details.value.content as NativeAccountDetailsContent).value;
      expect(content.identityLabel, 'subscriber@example.test');
      expect(content.usage.levelLabel, 'ChatGPT plus');
      expect(content.usage.quotas.map((quota) => quota.remaining), [
        '77.0%',
        '5.0%',
      ]);
      expect(
        content.usage.quotas.every((quota) => quota.resetLabel != null),
        isTrue,
      );
      expect(find.text('ChatGPT plus'), findsOneWidget);

      router.go(const StudioRoute().location);
      await tester.pumpAndSettle();
      router.go(const SettingsRoute().location);
      await tester.pumpAndSettle();
      expect(find.text('subscriber@example.test'), findsOneWidget);
      expect(find.text('ChatGPT plus'), findsOneWidget);
      router.go(detailsLocation);
      await tester.pumpAndSettle();
      expect(
        transport.queries,
        1,
        reason: 'Reentry observes the existing quota result',
      );
      await tap('account-usage-check');
      await usagePhase(AccountUsagePhase.querying, identity);
      transport.completeUsage(fail: true);
      await usagePhase(AccountUsagePhase.failed, identity);
      await tap('account-usage-check');
      await usagePhase(AccountUsagePhase.querying, identity);
      transport.completeUsage(empty: true);
      await usagePhase(AccountUsagePhase.succeeded, identity);
      final empty =
          (tester
                      .widget<AccountDetailsView>(
                        find.byType(AccountDetailsView),
                      )
                      .value
                      .content
                  as NativeAccountDetailsContent)
              .value
              .usage;
      expect(empty.quotas, isEmpty);
      expect(
        empty.emptyLabel,
        isNotEmpty,
        reason: 'Absent limits are not unlimited quota',
      );

      await tap('account-details-edit');
      await tester.pumpAndSettle();
      await field('name', '订阅账户改名');
      await tap('account-save');
      await untilObserved(
        graph.accounts.state,
        (value) => value.account(identity)?.name == '订阅账户改名',
      );
      expect(
        transport.patched!.authentication,
        isA<domain.KeepAccountAuthentication>(),
      );
      expect(transport.patched!.secret.action, AccountSecretAction.preserve);
      router.go(detailsLocation);
      await tester.pumpAndSettle();
      await tap('account-details-edit');
      await tester.pumpAndSettle();
      await method('API 密钥');
      expect(editor().credential.raw, isEmpty);
      expect(editor().endpoint.raw, 'https://api.openai.com/v1');
      expect(editor().canSave, isFalse);
      await field('credential', 'fresh-api-key');
      expect(editor().canSave, isTrue);
      await tap('account-save');
      await untilObserved(
        graph.accounts.details(identity),
        (resource) =>
            resource.value is domain.NativeAccountDetails &&
            (resource.value as domain.NativeAccountDetails).authentication ==
                domain.AccountAuthenticationMethod.apiKey,
      );
      expect(
        transport.patched!.authentication,
        isA<domain.SelectApiKeyAuthentication>(),
      );
      expect(transport.patched!.secret.action, AccountSecretAction.replace);
      expect(transport.patched!.secret.value, 'fresh-api-key');
      router.go(detailsLocation);
      await tester.pumpAndSettle();

      await tap('account-details-delete');
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(FilledButton),
        ),
      );
      await untilObserved(
        graph.accounts.state,
        (value) => value.account(identity) == null,
      );
      await tester.pumpAndSettle();
      expect(
        graph.accountUsage.state.value.value?.containsKey(identity),
        isFalse,
      );
      router.go(const SettingsRoute().location);
      await tester.pumpAndSettle();
      await openOpenAi();
      final next = tester.widget<AccountEditorConnector>(
        find.byType(AccountEditorConnector),
      );
      expect(
        next.editor.target.id,
        isNot(identity.accountId),
        reason: 'A new account must not reuse a protected credential alias',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
