import 'dart:io';
import 'dart:ui' as ui;

import 'package:anywork/src/app/app_composition.dart';
import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/routing/app_route.dart';
import 'package:anywork/src/app/routing/application_router.dart';
import 'package:anywork/src/app/studio_shutdown.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/settings/accounts/state/account_presentations.dart';
import 'package:anywork/src/features/settings/accounts/state/account_view_key_values.dart';
import 'package:anywork/src/features/settings/accounts/views/account_details_view.dart';
import 'package:anywork/src/features/settings/accounts/views/account_dialogs.dart';
import 'package:anywork/src/features/settings/accounts/views/acp_account_editor_view.dart';
import 'package:anywork/src/features/settings/statistics/view_models/statistics_repository_provider.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/acp.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/observed.dart';

// Opt-in real provider acceptance. The official desktop integration_test runner
// owns the native process; WidgetTester operates the production routes and FRB.
// Google account selection/consent is performed by the human in their browser.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  final phase = Platform.environment['ANYWORK_ACP_ACCEPTANCE'];
  final output = Platform.environment['ANYWORK_ACP_EVIDENCE'];
  final captureKey = GlobalKey();

  testWidgets(
    'official Antigravity login, quota and persisted restart',
    (tester) async {
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
      final summaries = graph.accounts.observeSummaries();
      final auth = graph.acp.observeAuth();
      final install = graph.acp.observeInstall();
      tester.testTextInput.register();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        router.dispose();
        await summaries.release();
        await auth.release();
        await install.release();
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
          debugPrint('ACP_ACCEPTANCE_SHUTDOWN completed clean drained');
        } finally {
          container.dispose();
          tester.testTextInput.unregister();
        }
      });

      await graph.initialize();
      expect(graph.client.bootstrapState.value.failure, isNull);
      await tester.pumpWidget(
        RepaintBoundary(
          key: captureKey,
          child: UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(
              theme: pureStudioTheme(),
              locale: const Locale('zh'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: router,
            ),
          ),
        ),
      );
      router.go(const SettingsRoute().location);
      await untilObserved(graph.accounts.state, (state) {
        if (state.failure case final failure?) throw failure;
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

      AcpAuthStateView stateOf(String id, int revision) =>
          graph.acp.auth.value.value?.stateOf(
            id,
            connectionRevision: revision,
          ) ??
          const AcpUncheckedState();

      Future<AcpAuthStateView> waitAuth(
        String id,
        int revision,
        bool Function(AcpAuthStateView) predicate,
      ) async {
        await untilObserved(graph.acp.auth, (resource) {
          if (resource.failure case final failure?) throw failure;
          final state = resource.value?.stateOf(
            id,
            connectionRevision: revision,
          );
          if (state is AcpFailedState) {
            throw StateError(
              'ACP failed: ${state.failure.code} at ${state.failure.stage}',
            );
          }
          return state != null && predicate(state);
        });
        await tester.pump();
        return stateOf(id, revision);
      }

      Future<void> screenshot(String name) async {
        if (output == null) return;
        await tester.pumpAndSettle();
        final boundary =
            captureKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        ui.Image? redacted;
        try {
          final program = graph.acp.install.value.value
              ?.stateOf(AcpProviderView.antigravity)
              .server
              ?.program;
          if (program != null) {
            final field = find.byWidgetPredicate(
              (widget) => widget is SelectableText && widget.data == program,
            );
            expect(field, findsOneWidget);
            final rect = tester
                .getRect(field)
                .shift(-tester.getTopLeft(find.byKey(captureKey)));
            // Export only a redacted capture: the installation path contains the
            // Windows username. Authentication, version and quota stay intact.
            final recorder = ui.PictureRecorder();
            final canvas = Canvas(recorder)
              ..drawImage(image, Offset.zero, Paint());
            canvas.drawRect(rect, Paint()..color = const Color(0xff333333));
            final label = TextPainter(
              text: const TextSpan(
                text: '本机安装路径已遮蔽',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
              textDirection: TextDirection.ltr,
            )..layout(maxWidth: rect.width);
            label.paint(canvas, rect.topLeft);
            label.dispose();
            final picture = recorder.endRecording();
            try {
              redacted = await picture.toImage(image.width, image.height);
            } finally {
              picture.dispose();
            }
          }
          final bytes = await (redacted ?? image).toByteData(
            format: ui.ImageByteFormat.png,
          );
          await Directory(output).create(recursive: true);
          await File('$output/$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
        } finally {
          redacted?.dispose();
          image.dispose();
        }
      }

      Future<void> openDetails(String id) async {
        router.go(
          AccountDetailsRoute(kind: AccountKind.acp, accountId: id).location,
        );
        await tester.pump();
        await untilObserved(graph.accounts.details(AcpAccountIdentity(id)), (
          resource,
        ) {
          if (resource.failure case final failure?) throw failure;
          return resource.loaded;
        });
        await tester.pumpAndSettle();
      }

      String id;
      final existing = graph.accounts.state.value.accounts
          .where((account) => account.identity is AcpAccountIdentity)
          .toList();
      if (phase == 'restart' || existing.isNotEmpty) {
        id = graph.accounts.state.value.accounts
            .where((account) => account.identity is AcpAccountIdentity)
            .single
            .identity
            .accountId;
        await openDetails(id);
        await tapKey(AccountViewKeyValues.acpAction('check'));
        debugPrint('ACP_ACCOUNT_REUSED phase=$phase');
      } else {
        await tapKey('account-add');
        await untilObserved(graph.acp.templates, (catalog) => catalog.isUsable);
        await untilObserved(
          graph.accounts.state,
          (state) => state.templates.isUsable,
        );
        await tester.pumpAndSettle();
        final selector = find.byKey(
          const ValueKey('account-template-selector'),
        );
        await tester.ensureVisible(selector);
        await tester.pump();
        await tester.tap(
          find.descendant(of: selector, matching: find.byType(IconButton)),
        );
        await tester.pumpAndSettle();
        await tapKey(AccountViewKeyValues.template('acp', 'antigravity'));
        await tester.pumpAndSettle();
        final discard = find.byType(AccountUnsavedChangesDialog);
        if (discard.evaluate().isNotEmpty) {
          final l10n = AppLocalizations.of(tester.element(discard));
          await tester.tap(
            find.descendant(
              of: discard,
              matching: find.widgetWithText(TextButton, l10n.accountsDiscard),
            ),
          );
          await tester.pumpAndSettle();
        }
        debugPrint('ACP_PREPARATION_REQUESTED');
        await untilObserved(graph.acp.install, (resource) {
          if (resource.failure case final failure?) throw failure;
          final state = resource.value?.stateOf(AcpProviderView.antigravity);
          if (state is AcpInstallFailedState) {
            throw StateError('Official preparation failed: ${state.failure}');
          }
          return state is AcpInstallReadyState;
        });
        debugPrint('ACP_PREPARATION_VERIFIED');
        await tester.pumpAndSettle();
        final editor = tester.widget<AcpAccountEditorView>(
          find.byType(AcpAccountEditorView),
        );
        final nameField = find.descendant(
          of: find.byKey(
            ValueKey(
              AccountViewKeyValues.editorField(editor.value.editorId, 'name'),
            ),
          ),
          matching: find.byType(TextField),
        );
        await tester.enterText(nameField, 'Antigravity 验收');
        await tester.pump();
        if (!tester
            .widget<AcpAccountEditorView>(find.byType(AcpAccountEditorView))
            .value
            .canSave) {
          await tapKey(AccountViewKeyValues.acpAction('usePrepared'));
          await tester.pump();
        }
        await tapKey('account-save');
        await untilObserved(
          graph.accounts.state,
          (state) => state.accounts.any(
            (account) => account.identity is AcpAccountIdentity,
          ),
        );
        id = graph.accounts.state.value.accounts
            .where((account) => account.identity is AcpAccountIdentity)
            .single
            .identity
            .accountId;
        await tester.pumpAndSettle();
        debugPrint('ACP_ACCOUNT_CREATED');
      }

      final account = graph.accounts.state.value.account(
        AcpAccountIdentity(id),
      )!;
      final revision = account.acpConnectionRevision!;
      var state = await waitAuth(
        id,
        revision,
        (s) => s is AcpRequiredState || s is AcpVerifiedState,
      );
      if (phase != 'restart') {
        // Existing credentials cannot count as browser-login proof. Official
        // logout belongs to the human; never remove or rewrite credential files.
        if (state is AcpVerifiedState) {
          debugPrint(
            'ACP_RELOGIN_REQUIRED: sign out using the official Antigravity application, then press Check in this window.',
          );
          final before = graph.acp.auth.value.value!.revision;
          await untilObserved(
            graph.acp.auth,
            (resource) =>
                resource.value!.revision > before &&
                resource.value!.stateOf(id, connectionRevision: revision)
                    is AcpRequiredState,
          );
          state = stateOf(id, revision);
        }
        final operation = (state as AcpRequiredState).operationId;
        expect(state.agentMethods, isNotEmpty);
        await screenshot('login-required');
        // Leave the full settings route, release its display demand, then return.
        router.go(const StudioRoute().location);
        await tester.pumpAndSettle();
        expect(stateOf(id, revision).operationId, operation);
        await openDetails(id);
        expect(stateOf(id, revision).operationId, operation);
        await tapKey(AccountViewKeyValues.acpAction('login'));
        debugPrint(
          'ACP_BROWSER_AUTHORIZATION_REQUIRED: complete Google account selection and consent in your browser.',
        );
        await waitAuth(id, revision, (s) => s is AcpVerifiedState);
      } else {
        expect(state, isA<AcpVerifiedState>());
      }
      final verified = stateOf(id, revision) as AcpVerifiedState;
      expect(verified.server?.version, '1.4.5');
      await tester.pumpAndSettle();
      final details = tester.widget<AccountDetailsView>(
        find.byType(AccountDetailsView),
      );
      final panel = (details.value.content as AcpAccountDetailsContent).value;
      expect(panel.phase, AcpPresentationPhase.connected);
      await screenshot('verified-$phase');
      debugPrint('ACP_SESSION_NEW_VERIFIED version=1.4.5 phase=$phase');

      await tapKey(AccountViewKeyValues.acpAction('queryUsage'));
      await untilObserved(graph.acp.auth, (resource) {
        final entry = resource.value?.account(id, connectionRevision: revision);
        if (entry?.state is AcpFailedState) {
          throw StateError('Usage authentication failed');
        }
        return entry?.state is AcpVerifiedState && entry?.usage != null;
      });
      final usage = graph.acp.auth.value.value!
          .account(id, connectionRevision: revision)!
          .usage!
          .state;
      expect(usage, isA<AcpUsageReadyView>());
      expect((usage as AcpUsageReadyView).groups, isNotEmpty);
      await screenshot('quota-$phase');
      debugPrint('ACP_USAGE_VERIFIED groups=${usage.groups.length}');
    },
    skip: phase != 'login' && phase != 'restart',
    timeout: Timeout.none,
  );
}
