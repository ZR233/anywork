import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:anywork/src/app/app_composition.dart';
import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/routing/app_route.dart';
import 'package:anywork/src/app/routing/application_router.dart';
import 'package:anywork/src/app/studio_shutdown.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/settings/accounts/connectors/account_editor_connector.dart';
import 'package:anywork/src/features/settings/accounts/state/account_presentations.dart';
import 'package:anywork/src/features/settings/accounts/state/account_view_key_values.dart';
import 'package:anywork/src/features/settings/accounts/view_models/account_editor_view_model.dart';
import 'package:anywork/src/features/settings/accounts/views/account_details_view.dart';
import 'package:anywork/src/features/settings/accounts/views/accounts_list_view.dart';
import 'package:anywork/src/features/settings/accounts/views/native_account_editor_view.dart';
import 'package:anywork/src/features/settings/statistics/view_models/statistics_repository_provider.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/accounts.dart' as domain;
import 'package:anywork_client/account_usage.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/observed.dart';

// Opt-in acceptance through Flutter's official desktop runner. The human only
// operates OpenAI's browser page; WidgetTester drives the production application.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  WidgetController.hitTestWarningShouldBeFatal = true;
  final phase = Platform.environment['ANYWORK_CHATGPT_ACCEPTANCE'];
  final output = Platform.environment['ANYWORK_CHATGPT_EVIDENCE'];
  if (phase != 'login' && phase != 'restart') {
    throw StateError('Supply ANYWORK_CHATGPT_ACCEPTANCE=login or restart');
  }

  testWidgets('real Codex login, usage and persisted restart', (tester) async {
    final graph = createProductionAppGraph();
    final container = ProviderContainer(
      overrides: [
        appGraphProvider.overrideWithValue(graph),
        statisticsRepositoryProvider.overrideWithValue(
          graph.statisticsRepository,
        ),
      ],
    );
    final router = createApplicationRouter();
    final capture = GlobalKey();
    final summaries = graph.accounts.observeSummaries();
    final sensitive = <String>{};
    tester.testTextInput.register();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      await summaries.release();
      try {
        final report = await runStudioShutdown(
          graph.client.transport,
          (_) {},
          remainingMs: 30000,
          closeClient: (deadline) => graph.close(deadline: deadline),
        );
        expect(report.shutdown.isClean, isTrue);
        expect(report.shutdown.issues, isEmpty);
        expect(
          report.shutdown.persistence,
          isA<DrainedStudioPendingPersistence>(),
        );
        debugPrint('CHATGPT_ACCEPTANCE_SHUTDOWN completed clean drained');
      } finally {
        container.dispose();
        tester.testTextInput.unregister();
      }
    });
    await graph.initialize();
    expect(graph.client.bootstrapState.value.failure, isNull);
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: UncontrolledProviderScope(
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
      ),
    );
    router.go(const SettingsRoute().location);
    await untilObserved(graph.accounts.state, (state) {
      if (state.failure case final error?) throw error;
      return state.loaded;
    });
    await tester.pumpAndSettle();

    Future<void> tapKey(String key) async {
      final finder = find.byKey(ValueKey(key));
      expect(finder, findsOneWidget, reason: key);
      await tester.ensureVisible(finder);
      await tester.pump();
      await tester.tap(finder);
      await tester.pump();
    }

    Future<void> screenshot(String name) async {
      if (output == null) return;
      await tester.pumpAndSettle();
      final boundary =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..drawImage(image, Offset.zero, Paint());
      final offset = tester.getTopLeft(find.byKey(capture));
      for (final element in find.byWidgetPredicate((widget) {
        final text = widget is Text
            ? widget.data
            : widget is SelectableText
            ? widget.data
            : null;
        return text != null &&
            sensitive.any((value) => value.isNotEmpty && text.contains(value));
      }).evaluate()) {
        final box = element.renderObject;
        if (box is RenderBox && box.hasSize) {
          canvas.drawRect(
            (box.localToGlobal(Offset.zero) - offset) & box.size,
            Paint()..color = const Color(0xffd5d5d5),
          );
        }
      }
      final picture = recorder.endRecording();
      final redacted = await picture.toImage(image.width, image.height);
      try {
        final bytes = await redacted.toByteData(format: ui.ImageByteFormat.png);
        await File('$output/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
      } finally {
        redacted.dispose();
        picture.dispose();
        image.dispose();
      }
    }

    domain.NativeAccountIdentity identity;
    if (phase == 'restart') {
      final saved = graph.accounts.state.value.accounts
          .where((account) => account.chatgptAccount?.codex != null)
          .single;
      identity = saved.identity as domain.NativeAccountIdentity;
    } else {
      await tapKey('account-add');
      await untilObserved(
        graph.accounts.state,
        (state) => state.templates.isUsable,
      );
      await tester.pumpAndSettle();
      final selector = find.byKey(const ValueKey('account-template-selector'));
      await tester.ensureVisible(selector);
      await tester.pump();
      await tester.tap(
        find.descendant(of: selector, matching: find.byType(IconButton)),
      );
      await tester.pumpAndSettle();
      await tapKey(AccountViewKeyValues.template('native', 'openai'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('ChatGPT 订阅'));
      await tester.pump();
      await tester.tap(find.text('ChatGPT 订阅'));
      await tester.pumpAndSettle();
      final editor = tester.widget<NativeAccountEditorView>(
        find.byType(NativeAccountEditorView),
      );
      final field = find.descendant(
        of: find.byKey(
          ValueKey(
            AccountViewKeyValues.editorField(editor.value.editorId, 'name'),
          ),
        ),
        matching: find.byType(TextField),
      );
      await tester.enterText(field, 'ChatGPT 验收');
      await tester.pump();
      final connector = tester.widget<AccountEditorConnector>(
        find.byType(AccountEditorConnector),
      );
      final provider = accountEditorViewModelProvider(connector.editor);
      identity = domain.NativeAccountIdentity(connector.editor.target.id);
      final authorized = Completer<void>();
      final observation = container.listen(provider, (_, next) {
        if (authorized.isCompleted) return;
        if (next.hasError) {
          authorized.completeError(next.error!, next.stackTrace);
          return;
        }
        if (next.value?.native?.error case final error?) {
          authorized.completeError(StateError(error));
          return;
        }
        final login = next.value?.native?.chatGptLogin;
        if (authorized.isCompleted || login == null) return;
        if (login.phase == ChatGptLoginPhase.awaitingBrowser) {
          debugPrint('CHATGPT_BROWSER_AUTHORIZATION_REQUIRED');
        }
        if (login.phase == ChatGptLoginPhase.failed ||
            login.phase == ChatGptLoginPhase.cancelled) {
          authorized.completeError(
            StateError('ChatGPT authorization failed: ${login.failure}'),
          );
        } else if (login.phase == ChatGptLoginPhase.succeeded) {
          if (login.account?.email case final email?) {
            sensitive.add(email);
          }
          if (login.account?.workspaceId case final workspace?) {
            sensitive.add(workspace);
          }
          authorized.complete();
        }
      });
      try {
        await screenshot('before-login');
        await tapKey('chatgpt-login-start');
        await authorized.future;
      } finally {
        observation.close();
      }
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<NativeAccountEditorView>(
              find.byType(NativeAccountEditorView),
            )
            .value
            .canSave,
        isTrue,
      );
      await screenshot('authorized');
      final saved = Completer<void>();
      void observeSave() {
        if (saved.isCompleted) return;
        final editor = container.read(provider);
        final error = editor.error ?? editor.value?.native?.error;
        if (error != null) {
          saved.completeError(StateError('$error'));
          return;
        }
        final draft = editor.value?.native;
        if (graph.accounts.state.value
                    .account(identity)
                    ?.chatgptAccount
                    ?.codex !=
                null &&
            draft != null &&
            !draft.saving &&
            !draft.dirty) {
          saved.complete();
        }
      }

      final editorWatch = container.listen(provider, (_, _) => observeSave());
      final accountWatch = graph.accounts.state.watchLatest(
        (_) => observeSave(),
      );
      try {
        await tapKey('account-save');
        await saved.future;
      } catch (_) {
        for (final operation in graph.client.mutations.operations) {
          if (operation.error case final StudioFailure failure) {
            debugPrint(
              'CHATGPT_SAVE_FAILURE code=${failure.code} message=${failure.message}',
            );
          }
        }
        await screenshot('save-failed');
        rethrow;
      } finally {
        editorWatch.close();
        accountWatch.observation.cancel();
      }
      debugPrint('CHATGPT_ACCOUNT_SAVED');
    }

    final saved = graph.accounts.state.value.account(identity)!;
    final account = saved.chatgptAccount!;
    expect(account.codex, isNotNull);
    if (account.email case final email?) sensitive.add(email);
    sensitive.add(account.codex!.accountId);
    router.go(
      AccountDetailsRoute(
        kind: AccountKind.native,
        accountId: identity.accountId,
      ).location,
    );
    await untilObserved(
      graph.accounts.details(identity),
      (resource) => resource.loaded,
    );
    await tester.pumpAndSettle();
    await tapKey('account-usage-check');
    await untilObserved(graph.accountUsage.state, (resource) {
      if (resource.failure case final error?) throw error;
      final usage = resource.value?[identity];
      if (usage?.phase == AccountUsagePhase.failed ||
          usage?.phase == AccountUsagePhase.missingCredential ||
          usage?.phase == AccountUsagePhase.unsupported) {
        throw StateError('ChatGPT quota failed: ${usage?.failure?.code}');
      }
      return usage?.phase == AccountUsagePhase.succeeded;
    });
    final usage = graph.accountUsage.state.value.value![identity]!;
    expect(usage.lastGood!.value, isA<AccountSubscription>());
    final quota = usage.lastGood!.value as AccountSubscription;
    expect(quota.quotas, isNotEmpty);
    await tester.pumpAndSettle();
    final details = tester.widget<AccountDetailsView>(
      find.byType(AccountDetailsView),
    );
    expect(
      (details.value.content as NativeAccountDetailsContent).value.usage.phase,
      AccountQueryPhase.ready,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('account-back')),
      -400,
      scrollable: find
          .descendant(
            of: find.byType(AccountDetailsView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await screenshot('quota-$phase');
    await tapKey('account-model-sync');
    await untilObserved(graph.models.state, (state) {
      final resource = state.accounts[identity];
      if (resource?.failure case final error?) throw error;
      final catalog = resource?.value;
      if (catalog?.status.error case final error?) {
        throw StateError(
          'ChatGPT models failed: ${error.kind} HTTP ${error.httpStatus}',
        );
      }
      return catalog?.status.source == ModelCatalogSource.online &&
          catalog!.status.probing == false;
    });
    final models = graph.models.state.value.accounts[identity]!.value!.models;
    expect(models, isNotEmpty);
    debugPrint('CHATGPT_MODELS_VERIFIED models=${models.length} phase=$phase');
    router.go(const SettingsRoute().location);
    await tester.pumpAndSettle();
    final search = find.descendant(
      of: find.byKey(const ValueKey('accounts-search')),
      matching: find.byType(TextField),
    );
    await tester.enterText(search, saved.name);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AccountsListView>(find.byType(AccountsListView))
          .value
          .rows
          .single
          .key
          .id,
      identity.accountId,
    );
    await screenshot('accounts-$phase');
    debugPrint(
      'CHATGPT_USAGE_VERIFIED windows=${quota.quotas.length} phase=$phase',
    );
  }, timeout: Timeout.none);
}
