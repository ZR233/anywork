import 'dart:async';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/routing/app_route.dart';
import 'package:anywork/src/app/routing/application_router.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/settings/accounts/connectors/account_editor_connector.dart';
import 'package:anywork/src/features/settings/accounts/state/account_presentations.dart';
import 'package:anywork/src/features/settings/accounts/state/account_view_state.dart';
import 'package:anywork/src/features/settings/accounts/state/account_view_key_values.dart';
import 'package:anywork/src/features/settings/accounts/view_models/account_editor_session_view_model.dart';
import 'package:anywork/src/features/settings/accounts/view_models/account_editor_view_model.dart';
import 'package:anywork/src/features/settings/accounts/view_models/account_models_view_model.dart';
import 'package:anywork/src/features/settings/accounts/view_models/accounts_view_model.dart';
import 'package:anywork/src/features/settings/accounts/views/account_dialogs.dart';
import 'package:anywork/src/features/settings/accounts/views/account_details_view.dart';
import 'package:anywork/src/features/settings/accounts/views/native_account_editor_view.dart';
import 'package:anywork/src/features/settings/settings_section.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/platform/host_app_icons.dart';
import 'package:anywork/src/presentation/providers/account_domains.dart';
import 'package:anywork/src/presentation/providers/account_operation_observation.dart';
import 'package:anywork/src/features/settings/statistics/view_models/statistics_repository_provider.dart';
import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/model_directory.dart';
import 'package:anywork_client/studio_client.dart'
    show OperationPhase, OperationState, ResourceStamp;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'accounts_view_models_test.dart';
import 'support/pump_client_future.dart';
import 'support/recording_demo_transport.dart';
import 'support/test_statistics_feed.dart';

// Production route table, onEnter/onExit, connectors and resource owners.
// Only domain publications and the non-native host environment are supplied.
// This is an adapter contract, not a widget-layout or native-GUI gate.
void main() {
  testWidgets(
    'model tabs and typed parents retain the account draft; leaving the account asks once',
    (tester) async {
      final h = await _mountRouter(tester);
      Object? caseFailure;
      StackTrace? caseStack;
      try {
        const details = AccountDetailsRoute(
          kind: AccountKind.native,
          accountId: 'native',
        );
        h.router.go(details.location);
        await _at(tester, h.router, details.location);
        final provider = accountModelsViewModelProvider(nativeKey);
        await pumpClientUntil(
          tester,
          () =>
              h.container.exists(provider) &&
              h.container.read(provider).hasValue,
          'details model owner',
        );
        final models = h.container.read(provider.notifier);
        models.changeCompact('model', '1250');
        final token = models.compactLeaveToken();
        const model = AccountModelRoute(
          kind: AccountKind.native,
          accountId: 'native',
          modelId: 'model',
        );
        h.router.go(model.location);
        await _at(tester, h.router, model.location);
        final pageKey = h.router.state.pageKey;
        final depth =
            h.router.routerDelegate.currentConfiguration.matches.length;
        for (final tab in [
          AccountModelTab.pricing,
          AccountModelTab.evaluations,
        ]) {
          final destination = AccountModelRoute(
            kind: AccountKind.native,
            accountId: 'native',
            modelId: 'model',
            tab: tab,
          );
          h.router.replace(destination.location);
          await _at(tester, h.router, destination.location);
          expect(h.router.state.pageKey, pageKey);
          expect(
            h.router.routerDelegate.currentConfiguration.matches,
            hasLength(depth),
          );
          expect(h.container.read(provider.notifier), same(models));
          expect(models.matchesCompactLeaveToken(token), isTrue);
          expect(find.byType(AccountUnsavedChangesDialog), findsNothing);
        }
        await tester.tap(find.byKey(const ValueKey('account-model-back')));
        await _at(tester, h.router, details.location);
        expect(h.container.read(provider.notifier), same(models));
        expect(models.hasCompactDrafts(), isTrue);
        await tester.tap(find.byKey(const ValueKey('account-back')));
        await _accountDialog(tester);
        expect(h.router.state.uri.toString(), details.location);
        await _chooseAccount(tester, AccountLeaveChoice.cancel);
        await tester.pumpAndSettle();
        expect(h.router.state.uri.toString(), details.location);
        expect(models.matchesCompactLeaveToken(token), isTrue);
        await tester.tap(find.byKey(const ValueKey('account-back')));
        await _accountDialog(tester);
        await _chooseAccount(tester, AccountLeaveChoice.discard);
        await _at(tester, h.router, const SettingsRoute().location);
        expect(find.byType(AccountUnsavedChangesDialog), findsNothing);
        expect(h.models.compactCalls, isEmpty);
      } catch (error, stack) {
        caseFailure = error;
        caseStack = stack;
        rethrow;
      } finally {
        await _closeAfterCase(h.close, caseFailure, caseStack);
      }
    },
  );

  testWidgets(
    'edit query hints do not replace a draft; one joint exit decision covers edit and details',
    (tester) async {
      final h = await _mountRouter(tester);
      Object? caseFailure;
      StackTrace? caseStack;
      try {
        const edit = AccountEditRoute(
          kind: AccountKind.native,
          accountId: 'native',
        );
        const focusFirst = AccountEditRoute(
          kind: AccountKind.native,
          accountId: 'native',
          focusModelId: 'focus-one',
        );
        const focusSecond = AccountEditRoute(
          kind: AccountKind.native,
          accountId: 'native',
          focusModelId: 'focus-two',
        );
        const staleLoadingRequest = AccountEditRoute(
          kind: AccountKind.native,
          accountId: 'native',
          focusModelId: 'focus-one',
          addModel: true,
        );
        const query = AccountEditRoute(
          kind: AccountKind.native,
          accountId: 'native',
          focusModelId: 'focus-two',
          addModel: true,
        );
        // Keep the canonical detail pending while an obsolete add request is
        // replaced by current focus-only props. Loading must not queue old hints.
        h.accounts.slots[const NativeAccountIdentity('native')]!.publish(
          const AccountResource<AccountDetails>(),
        );
        for (final destination in [edit, staleLoadingRequest, focusSecond]) {
          h.router.go(destination.location);
          await _committed(tester, h.router, destination.location);
          // Render each pending destination; do not merely overwrite three
          // unbuilt route requests before the canonical detail becomes ready.
          await tester.pump();
        }
        final routePageKey = h.router.state.pageKey;
        final entry = _actualEditorEntry(tester);
        final provider = accountEditorSessionViewModelProvider(entry);
        await pumpClientUntil(
          tester,
          () =>
              h.container.exists(provider) &&
              h.container.read(provider).asData?.value.editor != null,
          'loading edit session',
        );
        final session = _captureMountedOwner(h.container, entry);
        final key = session.currentEditor!;
        final editorProvider = accountEditorViewModelProvider(key);
        final editor = h.container.read(editorProvider.notifier);
        h.accounts.put(
          vmNative(
            manual: const [
              AccountModelCommand(
                modelId: 'focus-one',
                displayName: 'First row',
                wireApi: 'chat_completions',
                contextWindow: null,
                maxOutputTokens: null,
              ),
              AccountModelCommand(
                modelId: 'focus-two',
                displayName: 'Second row',
                wireApi: 'chat_completions',
                contextWindow: null,
                maxOutputTokens: null,
              ),
            ],
          ),
        );
        await _at(tester, h.router, focusSecond.location);
        AccountEditorViewState current() =>
            h.container.read(editorProvider).requireValue;
        expect(session.currentEditor, key);
        expect(editor.addModelEntryEditorKey(), isNull);
        expect(current().native!.manualModels, hasLength(2));
        final firstRow = current().native!.manualModels.first.editorKey;
        final secondRow = current().native!.manualModels.last.editorKey;
        await _focusedManualInput(tester, secondRow, 'name');
        editor.changeField(NativeAccountField.name, 'Unsubmitted route draft');
        editor.changeField(
          NativeAccountField.credential,
          'retained-query-secret',
        );
        editor.changeModel(
          firstRow,
          field: ManualModelField.name,
          raw: 'Local first row',
        );
        final retainedRows = current().native!.manualModels;
        void expectRetained() {
          expect(h.router.state.pageKey, routePageKey);
          expect(
            h.container.read(provider.notifier).currentOwner(),
            same(session),
          );
          expect(
            h.container.read(provider).requireValue.ownerId,
            session.ownerId,
          );
          expect(session.currentEditor, key);
          expect(current().native!.name.raw, 'Unsubmitted route draft');
          expect(current().native!.credential.raw, 'retained-query-secret');
          expect(
            current().native!.manualModels
                .where(
                  (row) =>
                      row.editorKey == firstRow || row.editorKey == secondRow,
                )
                .toList(),
            retainedRows,
          );
        }

        final focusRevision = current().draftRevision;
        for (final destination in [focusFirst, focusSecond]) {
          h.router.go(destination.location);
          await _at(tester, h.router, destination.location);
          await _focusedManualInput(
            tester,
            destination == focusFirst ? firstRow : secondRow,
            'name',
          );
          expectRetained();
          expect(current().draftRevision, focusRevision);
          expect(current().native!.manualModels, hasLength(2));
        }
        h.router.go(query.location);
        await _at(tester, h.router, query.location);
        await pumpClientUntil(
          tester,
          () => editor.addModelEntryEditorKey() != null,
          'current add-model query consumed',
        );
        final addedRow = editor.addModelEntryEditorKey()!;
        await _focusedManualInput(tester, addedRow, 'id');
        expectRetained();
        expect(current().native!.manualModels, hasLength(3));
        final addedRevision = current().draftRevision;
        await tester.pumpWidget(_routerApp(h.container, h.router));
        await _at(tester, h.router, query.location);
        for (final destination in [focusSecond, query, focusSecond, query]) {
          h.router.go(destination.location);
          await _at(tester, h.router, destination.location);
          expectRetained();
          expect(editor.addModelEntryEditorKey(), addedRow);
          expect(current().native!.manualModels, hasLength(3));
          expect(current().draftRevision, addedRevision);
        }
        final rowWidget = find.byKey(
          ValueKey(AccountViewKeyValues.manualItem(addedRow)),
        );
        final remove = find.descendant(
          of: rowWidget,
          matching: find.text(
            AppLocalizations.of(tester.element(rowWidget)).settingsRemoveModel,
          ),
        );
        await tester.ensureVisible(remove);
        await tester.tap(remove);
        await pumpClientUntil(
          tester,
          () => current().native!.manualModels.length == 2,
          'entry row removed by production callback',
        );
        final removedRevision = current().draftRevision;
        for (final destination in [focusSecond, query]) {
          h.router.go(destination.location);
          await _at(tester, h.router, destination.location);
          expectRetained();
          expect(current().native!.manualModels, hasLength(2));
          expect(current().draftRevision, removedRevision);
          expect(editor.addModelEntryEditorKey(), addedRow);
        }
        expect(h.accounts.patches, isEmpty);
        expect(h.models.removed, isEmpty);
        final models = h.container.read(
          accountModelsViewModelProvider(nativeKey).notifier,
        );
        models.changeCompact('model', '1400');
        expect(find.byType(AccountUnsavedChangesDialog), findsNothing);
        final editorToken = editor.leaveToken();
        h.router.go(const SettingsRoute().location);
        await _accountDialog(tester);
        expect(session.isActive, isTrue);
        expect(editor.matchesLeaveToken(editorToken), isTrue);
        expect(models.hasCompactDrafts(), isTrue);
        await _chooseAccount(tester, AccountLeaveChoice.cancel);
        await tester.pumpAndSettle();
        expect(h.router.state.uri.toString(), query.location);
        expect(session.isEditorCurrent(key), isTrue);
        expect(models.hasCompactDrafts(), isTrue);
        h.router.go(const SettingsRoute().location);
        await _accountDialog(tester);
        await _chooseAccount(tester, AccountLeaveChoice.discard);
        await _at(tester, h.router, const SettingsRoute().location);
        expect(
          find.byType(AccountUnsavedChangesDialog),
          findsNothing,
          reason: 'parent Details must reuse the exact old Edit resolution',
        );
        expect(session.isActive, isFalse);
        expect(h.accounts.patches, isEmpty);
        expect(h.models.compactCalls, isEmpty);
      } catch (error, stack) {
        caseFailure = error;
        caseStack = stack;
        rethrow;
      } finally {
        await _closeAfterCase(h.close, caseFailure, caseStack);
      }
    },
  );

  testWidgets(
    'covering Edit retains its owner; replacing the same pattern with another typed account requires exit permission',
    (tester) async {
      final h = await _mountRouter(tester);
      Object? caseFailure;
      StackTrace? caseStack;
      try {
        h.accounts.put(vmNative(id: 'other'));
        const source = AccountEditRoute(
          kind: AccountKind.native,
          accountId: 'native',
        );
        h.router.go(source.location);
        await _at(tester, h.router, source.location);
        final entry = _actualEditorEntry(tester);
        final provider = accountEditorSessionViewModelProvider(entry);
        await pumpClientUntil(
          tester,
          () =>
              h.container.exists(provider) &&
              h.container.read(provider).asData?.value.editor != null,
          'source session',
        );
        final session = _captureMountedOwner(h.container, entry);
        final key = session.currentEditor!;
        final editor = h.container.read(
          accountEditorViewModelProvider(key).notifier,
        );
        editor.changeField(NativeAccountField.name, 'Retained while covered');
        final token = editor.leaveToken();
        final covering = h.router.push<void>(const StudioRoute().location);
        await _at(tester, h.router, const StudioRoute().location);
        expect(find.byType(AccountUnsavedChangesDialog), findsNothing);
        expect(session.isEditorCurrent(key), isTrue);
        expect(
          h.container.read(provider).requireValue.ownerId,
          session.ownerId,
        );
        expect(editor.matchesLeaveToken(token), isTrue);
        h.router.pop();
        await pumpClientFuture(tester, covering, 'pop covering route');
        await _at(tester, h.router, source.location);
        expect(session.isEditorCurrent(key), isTrue);
        expect(
          h.container.read(provider.notifier).currentOwner(),
          same(session),
        );
        expect(editor.matchesLeaveToken(token), isTrue);
        const destination = AccountEditRoute(
          kind: AccountKind.native,
          accountId: 'other',
        );
        h.router.go(destination.location);
        await _accountDialog(tester);
        expect(h.router.state.uri.toString(), source.location);
        await _chooseAccount(tester, AccountLeaveChoice.cancel);
        await tester.pumpAndSettle();
        expect(session.isEditorCurrent(key), isTrue);
        h.router.go(destination.location);
        await _accountDialog(tester);
        await _chooseAccount(tester, AccountLeaveChoice.discard);
        await _at(tester, h.router, destination.location);
        expect(session.isActive, isFalse);
        final nextEntry = _actualEditorEntry(tester);
        final nextProvider = accountEditorSessionViewModelProvider(nextEntry);
        await pumpClientUntil(
          tester,
          () =>
              h.container.exists(nextProvider) &&
              h.container.read(nextProvider).asData?.value.editor != null,
          'destination session',
        );
        final nextSession = _captureMountedOwner(h.container, nextEntry);
        expect(nextSession.ownerId, isNot(session.ownerId));
        final next = nextSession.currentEditor!;
        expect(next.target.id, 'other');
        expect(next.editorId, isNot(key.editorId));
        expect(find.byType(AccountUnsavedChangesDialog), findsNothing);
        expect(h.accounts.patches, isEmpty);
      } catch (error, stack) {
        caseFailure = error;
        caseStack = stack;
        rethrow;
      } finally {
        await _closeAfterCase(h.close, caseFailure, caseStack);
      }
    },
  );

  testWidgets(
    'a delete dialog result cannot admit a command from a mounted but covered source',
    (tester) async {
      final h = await _mountRouter(tester);
      Object? caseFailure;
      StackTrace? caseStack;
      try {
        const details = AccountDetailsRoute(
          kind: AccountKind.native,
          accountId: 'native',
        );
        h.router.go(details.location);
        await _at(tester, h.router, details.location);
        final sourceElement = tester.element(find.byType(AccountDetailsView));
        final sourceRoute = ModalRoute.of(sourceElement)!;
        expect(sourceRoute.isCurrent, isTrue);
        await tester.tap(find.byKey(const ValueKey('account-details-delete')));
        await pumpClientUntil(
          tester,
          () => find.byType(AccountDeleteDialog).evaluate().isNotEmpty,
          'real account delete confirmation',
        );
        await tester.pumpAndSettle();
        final dialogRoute = ModalRoute.of(
          tester.element(find.byType(AccountDeleteDialog)),
        )!;
        final covering = h.router.push<void>(const StudioRoute().location);
        await _at(tester, h.router, const StudioRoute().location);
        expect(sourceElement.mounted, isTrue);
        expect(ModalRoute.of(sourceElement), same(sourceRoute));
        expect(sourceRoute.isCurrent, isFalse);
        expect(dialogRoute.isCurrent, isFalse);
        // Complete that actual dialog's Future, not a pop of the covering page.
        dialogRoute.navigator!.removeRoute<dynamic>(dialogRoute, true);
        await tester.pumpAndSettle();
        expect(h.accounts.removals, isEmpty);
        expect(
          h.accounts.state.value.account(const NativeAccountIdentity('native')),
          isNotNull,
        );
        expect(h.router.state.uri.toString(), const StudioRoute().location);
        h.router.pop();
        await pumpClientFuture(tester, covering, 'uncover delete source');
        await _at(tester, h.router, details.location);
        expect(sourceElement.mounted, isTrue);
        expect(sourceRoute.isCurrent, isTrue);
        expect(h.accounts.removals, isEmpty);
        // Positive admission control: the same real dialog is allowed to issue
        // the command once its source is current. A rejected domain response
        // preserves canonical data without inventing a successful deletion.
        h.accounts.write = () async => failedVmOperation(
          OperationPhase.rejected,
          id: 'current-source-delete-rejected',
          error: StateError('delete admission control rejected'),
        );
        await tester.tap(find.byKey(const ValueKey('account-details-delete')));
        await pumpClientUntil(
          tester,
          () => find.byType(AccountDeleteDialog).evaluate().isNotEmpty,
          'current source delete confirmation',
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(AccountDeleteDialog),
            matching: find.byType(FilledButton),
          ),
        );
        await pumpClientUntil(
          tester,
          () => h.accounts.removals.length == 1,
          'current source may admit delete',
        );
        await tester.pumpAndSettle();
        expect(h.accounts.removals, [const NativeAccountIdentity('native')]);
        expect(h.router.state.uri.toString(), details.location);
        expect(
          h.accounts.state.value.account(const NativeAccountIdentity('native')),
          isNotNull,
        );
      } catch (error, stack) {
        caseFailure = error;
        caseStack = stack;
        rethrow;
      } finally {
        await _closeAfterCase(h.close, caseFailure, caseStack);
      }
    },
  );

  testWidgets(
    'editor save navigates only for its still-current official source after confirmed completion',
    (tester) async {
      final h = await _mountRouter(tester);
      Object? caseFailure;
      StackTrace? caseStack;
      try {
        const edit = AccountEditRoute(
          kind: AccountKind.native,
          accountId: 'native',
        );
        const details = AccountDetailsRoute(
          kind: AccountKind.native,
          accountId: 'native',
        );
        const identity = NativeAccountIdentity('native');
        for (final covered in [false, true]) {
          h.router.go(edit.location);
          await _at(tester, h.router, edit.location);
          final entry = _actualEditorEntry(tester);
          final sessionProvider = accountEditorSessionViewModelProvider(entry);
          await pumpClientUntil(
            tester,
            () =>
                h.container.exists(sessionProvider) &&
                h.container.read(sessionProvider).asData?.value.editor != null,
            'save source session',
          );
          final session = _captureMountedOwner(h.container, entry);
          final key = session.currentEditor!;
          final editorProvider = accountEditorViewModelProvider(key);
          final editor = h.container.read(editorProvider.notifier);
          final name = covered
              ? 'Confirmed while covered'
              : 'Confirmed while current';
          await tester.enterText(_editorInput(key.editorId, 'name'), name);
          await tester.pump();
          expect(
            h.container.read(editorProvider).requireValue.native!.name.raw,
            name,
          );
          final token = editor.leaveToken();
          final sourceElement = tester.element(
            find.byType(NativeAccountEditorView),
          );
          final sourceRoute = ModalRoute.of(sourceElement)!;
          final admitted = Completer<void>();
          final completion = Completer<OperationState>();
          h.accounts.patchWrite = () {
            admitted.complete();
            return completion.future;
          };
          final save = find.byKey(const ValueKey('account-save'));
          await tester.ensureVisible(save);
          await tester.tap(save);
          await pumpClientFuture(
            tester,
            admitted.future,
            'real editor save admission',
          );
          expect(h.container.read(editorProvider).requireValue.saving, isTrue);
          expect((h.accounts.patches.last.name as AccountTextSet).value, name);
          Future<void>? covering;
          if (covered) {
            covering = h.router.push<void>(const StudioRoute().location);
            await _at(tester, h.router, const StudioRoute().location);
            expect(sourceElement.mounted, isTrue);
            expect(ModalRoute.of(sourceElement), same(sourceRoute));
            expect(sourceRoute.isCurrent, isFalse);
            expect(session.isEditorCurrent(key), isTrue);
            expect(
              h.container.read(sessionProvider).requireValue.ownerId,
              session.ownerId,
            );
          }
          // Supply the corresponding typed canonical frames and confirmed
          // operation, not a navigation result or a test-owned save classifier.
          final stamp = ResourceStamp(
            resourceKey: vmStamp.resourceKey,
            ownerEpoch: vmStamp.ownerEpoch,
            revision: covered ? 3 : 2,
          );
          h.accounts.slots[identity]!.publish(
            AccountResource(
              stamp: stamp,
              value: vmNative(name: name),
            ),
          );
          h.accounts.state.publish(
            AccountsState(
              stamp: stamp,
              accounts: [vmSummary(identity, name: name)],
              templates: h.accounts.state.value.templates,
            ),
          );
          completion.complete(
            savedVmOperation(
              covered ? 'covered-editor-save' : 'current-editor-save',
            ),
          );
          if (!covered) {
            await _at(tester, h.router, details.location);
            expect(session.isActive, isFalse);
          } else {
            await pumpClientUntil(
              tester,
              () =>
                  h.container.read(editorProvider).asData?.value.saving ==
                  false,
              'covered save settled',
            );
            await tester.pumpAndSettle();
            final state = h.container.read(editorProvider).requireValue;
            expect(
              (state.dirty, state.saving, state.error),
              (false, false, null),
            );
            expect(editor.matchesLeaveToken(token), isTrue);
            expect(session.isEditorCurrent(key), isTrue);
            expect(
              h.container.read(sessionProvider.notifier).currentOwner(),
              same(session),
            );
            expect(sourceElement.mounted, isTrue);
            expect(sourceRoute.isCurrent, isFalse);
            expect(h.router.state.uri.toString(), const StudioRoute().location);
            expect(h.accounts.state.value.account(identity)!.name, name);
            expect(h.accounts.patches, hasLength(2));
            h.router.pop();
            await pumpClientFuture(
              tester,
              covering!,
              'uncover completed editor',
            );
            await _at(tester, h.router, edit.location);
            expect(h.accounts.patches, hasLength(2));
          }
        }
      } catch (error, stack) {
        caseFailure = error;
        caseStack = stack;
        rethrow;
      } finally {
        await _closeAfterCase(h.close, caseFailure, caseStack);
      }
    },
  );

  testWidgets(
    'Mode query-only section change and true Settings exit each ask exactly once',
    (tester) async {
      final h = await _mountRouter(tester);
      Object? caseFailure;
      StackTrace? caseStack;
      try {
        const mode = SettingsRoute(section: SettingsSection.workModes);
        const accounts = SettingsRoute();
        for (final destination in [
          accounts.location,
          const StudioRoute().location,
        ]) {
          h.router.go(mode.location);
          await _at(tester, h.router, mode.location);
          final owner = h.graph.client.modeEditor;
          owner.create(
            id: 'route-contract-mode',
            displayName: 'Route contract',
          );
          expect(owner.state.dirty, isTrue);
          h.router.go(destination);
          await pumpClientUntil(
            tester,
            () => find
                .byKey(const ValueKey('mode-editor-unsaved-dialog'))
                .evaluate()
                .isNotEmpty,
            'Mode leave dialog',
          );
          expect(
            find.byKey(const ValueKey('mode-editor-unsaved-dialog')),
            findsOneWidget,
          );
          await tester.tap(
            find.byKey(const ValueKey('mode-editor-unsaved-cancel')),
          );
          await tester.pumpAndSettle();
          expect(h.router.state.uri.toString(), mode.location);
          expect(owner.state.dirty, isTrue);
          h.router.go(destination);
          await pumpClientUntil(
            tester,
            () => find
                .byKey(const ValueKey('mode-editor-unsaved-discard'))
                .evaluate()
                .isNotEmpty,
            'Mode discard',
          );
          await tester.tap(
            find.byKey(const ValueKey('mode-editor-unsaved-discard')),
          );
          await _at(tester, h.router, destination);
          expect(owner.state.dirty, isFalse);
          expect(
            find.byKey(const ValueKey('mode-editor-unsaved-dialog')),
            findsNothing,
            reason: 'onEnter for retained Settings and onExit for removal are exclusive',
          );
        }
      } catch (error, stack) {
        caseFailure = error;
        caseStack = stack;
        rethrow;
      } finally {
        await _closeAfterCase(h.close, caseFailure, caseStack);
      }
    },
  );

  testWidgets(
    'manual model deletion rechecks compact intent and blocks conflicts until settlement',
    (tester) async {
      final h = await _mountRouter(tester, manualModel: true);
      Object? caseFailure;
      StackTrace? caseStack;
      try {
        const details = AccountDetailsRoute(
          kind: AccountKind.native,
          accountId: 'native',
        );
        h.router.go(details.location);
        await _at(tester, h.router, details.location);
        final provider = accountModelsViewModelProvider(nativeKey);
        await pumpClientUntil(
          tester,
          () =>
              h.container.exists(provider) &&
              h.container.read(provider).hasValue,
          'manual deletion model owner',
        );
        var models = h.container.read(provider.notifier);
        compact() => h.container
            .read(provider)
            .requireValue
            .catalog
            .models
            .singleWhere((row) => row.key.modelId == 'model')
            .compact!;
        expect(_compactInput('model'), findsOneWidget);
        h.models.removeWrite = () async => failedVmOperation(
          OperationPhase.rejected,
          id: 'unsafe-manual-admission-rejected',
          error: StateError('Only the clean deletion may be admitted'),
        );
        await _openManualDelete(tester);
        models.changeCompact('model', '1350');
        final dirtyToken = models.compactLeaveToken();
        await tester.pump();
        await _confirmDeleteIfEnabled(tester);
        await tester.pumpAndSettle();
        expect(
          h.models.removed,
          isEmpty,
          reason:
              'New compact raw on another model invalidates the open deletion.',
        );
        expect(models.matchesCompactLeaveToken(dirtyToken), isTrue);
        expect(compact().raw, '1350');
        expect(find.byType(AccountUnsavedChangesDialog), findsNothing);
        await _cancelDeleteIfOpen(tester);
        await pumpClientFuture(
          tester,
          models.removeManual('manual'),
          'dirty remove denied',
        );
        expect(h.models.removed, isEmpty);

        final compactResult = Completer<OperationState>();
        h.models.compactWrite = () => compactResult.future;
        final saving = models.saveCompact('model');
        expect(models.compactLeaveBlocked(), isTrue);
        await pumpClientFuture(
          tester,
          models.removeManual('manual'),
          'inflight remove denied',
        );
        expect(h.models.removed, isEmpty);
        compactResult.complete(
          failedVmOperation(
            OperationPhase.unknownOutcome,
            id: 'manual-delete-compact-unknown',
            error: StateError('Compact outcome remains unconfirmed'),
          ),
        );
        await pumpClientFuture(
          tester,
          saving,
          'compact await returned unknown',
        );
        expect(models.compactLeaveBlocked(), isFalse);
        expect(models.hasUnconfirmedCompactSave(), isTrue);
        await pumpClientFuture(
          tester,
          models.removeManual('manual'),
          'unknown remove denied',
        );
        expect(h.models.removed, isEmpty);
        expect(compact().raw, '1350');

        h.router.go(const SettingsRoute().location);
        await _accountDialog(tester);
        final dialog = find.byType(AccountUnsavedChangesDialog);
        final l10n = AppLocalizations.of(tester.element(dialog));
        expect(
          find.descendant(
            of: dialog,
            matching: find.text(l10n.accountsUnconfirmedSaveDiscardWarning),
          ),
          findsOneWidget,
        );
        await _chooseAccount(tester, AccountLeaveChoice.discard);
        await _at(tester, h.router, const SettingsRoute().location);
        h.router.go(details.location);
        await _at(tester, h.router, details.location);
        models = h.container.read(provider.notifier);
        expect(models.hasCompactDrafts(), isFalse);
        expect(models.hasUnconfirmedCompactSave(), isFalse);

        final admitted = Completer<void>();
        final deletion = Completer<OperationState>();
        h.models.removeWrite = () {
          admitted.complete();
          return deletion.future;
        };
        await _openManualDelete(tester);
        await _confirmDeleteIfEnabled(tester);
        await pumpClientFuture(
          tester,
          admitted.future,
          'clean manual remove admitted',
        );
        expect(h.models.removed.map((target) => target.modelId), ['manual']);
        await tester.pump();
        await _expectDeletionBlocksModels(
          tester,
          h.container,
          h.models,
          models,
        );
        await pumpClientFuture(
          tester,
          models.removeManual('manual'),
          'duplicate remove denied',
        );
        expect(h.models.removed, hasLength(1));
        deletion.complete(savedVmOperation('clean-manual-delete'));
        final directory = h.models.state.value;
        final resource =
            directory.accounts[const NativeAccountIdentity('native')]!;
        h.models.state.publish(
          ModelDirectoryState(
            accounts: {
              ...directory.accounts,
              const NativeAccountIdentity('native'): AccountResource(
                stamp: resource.stamp,
                value: AccountModelCatalog(
                  identity: const NativeAccountIdentity('native'),
                  models: resource.value!.models
                      .where((model) => model.modelId != 'manual')
                      .toList(),
                  status: resource.value!.status,
                ),
              ),
            },
            configurations: directory.configurations,
          ),
        );
        h.accounts.put(vmNative());
        await tester.pumpAndSettle();
        expect(_accountModelRow('manual'), findsNothing);
        expect(_accountModelRow('model'), findsOneWidget);
        expect(h.models.removed, hasLength(1));
        expect(h.router.state.uri.toString(), details.location);
        models.changeCompact('model', '1450');
        expect(compact().raw, '1450');
      } catch (error, stack) {
        caseFailure = error;
        caseStack = stack;
        rethrow;
      } finally {
        await _closeAfterCase(h.close, caseFailure, caseStack);
      }
    },
  );

  testWidgets(
    'account deletion preserves compact drafts on blocked admission, cancellation and rejection',
    (tester) async {
      final h = await _mountRouter(tester);
      Object? caseFailure;
      StackTrace? caseStack;
      try {
        const details = AccountDetailsRoute(
          kind: AccountKind.native,
          accountId: 'native',
        );
        h.router.go(details.location);
        await _at(tester, h.router, details.location);
        final provider = accountModelsViewModelProvider(nativeKey);
        await pumpClientUntil(
          tester,
          () =>
              h.container.exists(provider) &&
              h.container.read(provider).hasValue,
          'account deletion model owner',
        );
        var models = h.container.read(provider.notifier);
        compact() => h.container
            .read(provider)
            .requireValue
            .catalog
            .models
            .single
            .compact!;
        await tester.tap(find.byKey(const ValueKey('account-details-delete')));
        await _deleteDialog(tester);
        await _cancelDeleteIfOpen(tester);
        expect(h.accounts.removals, isEmpty);
        expect(h.router.state.uri.toString(), details.location);
        h.accounts.write = () async => failedVmOperation(
          OperationPhase.rejected,
          id: 'unsafe-account-admission-rejected',
          error: StateError('Dirty account deletion must not be admitted'),
        );
        models.changeCompact('model', '1350');
        final dirtyToken = models.compactLeaveToken();
        await tester.pump();
        await _tryAccountDelete(tester);
        expect(
          h.accounts.removals,
          isEmpty,
          reason: 'Account deletion is clean-only, not delete before asking to leave.',
        );
        expect(h.router.state.uri.toString(), details.location);
        expect(h.container.read(provider.notifier), same(models));
        expect(models.matchesCompactLeaveToken(dirtyToken), isTrue);
        expect(compact().raw, '1350');
        expect(find.byType(AccountUnsavedChangesDialog), findsNothing);
        await _cancelDeleteIfOpen(tester);

        Future<void> leaveDraftAndReenter() async {
          h.router.go(const SettingsRoute().location);
          await _accountDialog(tester);
          await _chooseAccount(tester, AccountLeaveChoice.discard);
          await _at(tester, h.router, const SettingsRoute().location);
          h.router.go(details.location);
          await _at(tester, h.router, details.location);
          models = h.container.read(provider.notifier);
        }

        await leaveDraftAndReenter();
        await tester.tap(find.byKey(const ValueKey('account-details-delete')));
        await _deleteDialog(tester);
        models.changeCompact('model', '1400');
        await tester.pump();
        await _confirmDeleteIfEnabled(tester);
        await tester.pumpAndSettle();
        expect(h.accounts.removals, isEmpty);
        expect(compact().raw, '1400');
        expect(find.byType(AccountUnsavedChangesDialog), findsNothing);
        await _cancelDeleteIfOpen(tester);
        await leaveDraftAndReenter();
        final cleanRaw = compact().raw;
        expect(_compactInput('model'), findsOneWidget);
        final admitted = Completer<void>();
        final deletion = Completer<OperationState>();
        h.accounts.write = () {
          admitted.complete();
          return deletion.future;
        };
        await tester.tap(find.byKey(const ValueKey('account-details-delete')));
        await _deleteDialog(tester);
        await _confirmDeleteIfEnabled(tester);
        await pumpClientFuture(
          tester,
          admitted.future,
          'clean account remove admitted',
        );
        expect(h.accounts.removals, [const NativeAccountIdentity('native')]);
        await tester.pump();
        await _expectDeletionBlocksModels(
          tester,
          h.container,
          h.models,
          models,
        );
        expect(
          await h.container
              .read(accountsViewModelProvider.notifier)
              .remove(nativeKey),
          isFalse,
        );
        expect(h.accounts.removals, hasLength(1));
        deletion.complete(
          failedVmOperation(
            OperationPhase.rejected,
            id: 'account-delete-rejected',
            error: StateError('Removal rejected by the domain'),
          ),
        );
        await pumpClientUntil(
          tester,
          () => find
              .byKey(const ValueKey('account-details-delete'))
              .evaluate()
              .isNotEmpty,
          'rejected deletion releases its own blocking',
        );
        await tester.pumpAndSettle();
        expect(h.router.state.uri.toString(), details.location);
        expect(compact().raw, cleanRaw);
        expect(h.container.read(provider.notifier), same(models));
        expect(
          h.accounts.state.value.account(const NativeAccountIdentity('native')),
          isNotNull,
        );
        expect(h.accounts.removals, hasLength(1));
        expect(find.byType(AccountUnsavedChangesDialog), findsNothing);
        models.changeCompact('model', '1450');
        expect(compact().raw, '1450');
        expect(h.models.compactCalls, isEmpty);
      } catch (error, stack) {
        caseFailure = error;
        caseStack = stack;
        rethrow;
      } finally {
        await _closeAfterCase(h.close, caseFailure, caseStack);
      }
    },
  );

  testWidgets(
    'an unconfirmed compact save warns before leaving; Cancel retains the owner and Discard leaves without replay',
    (tester) async {
      final h = await _mountRouter(tester);
      Object? caseFailure;
      StackTrace? caseStack;
      try {
        const edit = AccountEditRoute(
          kind: AccountKind.native,
          accountId: 'native',
        );
        const destination = SettingsRoute();
        h.router.go(edit.location);
        await _at(tester, h.router, edit.location);
        final entry = _actualEditorEntry(tester);
        final owner = _captureMountedOwner(h.container, entry);
        final editor = owner.currentEditor!;
        final slot = accountEditorSessionViewModelProvider(entry);
        final provider = accountModelsViewModelProvider(nativeKey);
        await pumpClientUntil(
          tester,
          () =>
              h.container.exists(provider) &&
              h.container.read(provider).hasValue,
          'compact owner for the real leave warning',
        );
        final models = h.container.read(provider.notifier);
        models.changeCompact('model', '1350');
        final completion = Completer<OperationState>();
        h.models.compactWrite = () => completion.future;
        final saving = models.saveCompact('model');
        expect(models.compactLeaveBlocked(), isTrue);
        expect(h.models.compactCalls, hasLength(1));
        completion.complete(
          failedVmOperation(
            OperationPhase.unknownOutcome,
            id: 'route-unconfirmed-compact',
            error: StateError('No confirmed compact outcome'),
          ),
        );
        await pumpClientFuture(
          tester,
          saving,
          'local compact save await ended',
        );
        expect(models.compactLeaveBlocked(), isFalse);
        expect(models.hasUnconfirmedCompactSave(), isTrue);
        expect(models.hasCompactDrafts(), isTrue);
        expect(models.canSaveCompactDrafts(), isFalse);
        final compactToken = models.compactLeaveToken();
        final compact = h.container
            .read(provider)
            .requireValue
            .catalog
            .models
            .single
            .compact!;
        expect(
          (
            compact.raw,
            compact.dirty,
            compact.canSave,
            compact.canReset,
            compact.canRetry,
          ),
          ('1350', true, false, false, false),
        );
        expect(
          (h.models.compactCalls.single.$2 as SetAutoCompactLimit).limit,
          1350,
        );

        void expectProductionWarning() {
          final dialog = find.byType(AccountUnsavedChangesDialog);
          expect(dialog, findsOneWidget);
          final l10n = AppLocalizations.of(tester.element(dialog));
          expect(
            find.descendant(
              of: dialog,
              matching: find.text(l10n.accountsUnconfirmedSaveDiscardWarning),
            ),
            findsOneWidget,
          );
          final value = tester.widget<AccountUnsavedChangesDialog>(dialog);
          expect(value.canSave, isFalse);
          expect(value.canDiscard, isTrue);
        }

        h.router.go(destination.location);
        await _accountDialog(tester);
        expectProductionWarning();
        await _chooseAccount(tester, AccountLeaveChoice.cancel);
        await tester.pumpAndSettle();
        expect(h.router.state.uri.toString(), edit.location);
        expect(h.container.read(slot.notifier).currentOwner(), same(owner));
        expect(h.container.read(slot).requireValue.ownerId, owner.ownerId);
        expect(owner.isEditorCurrent(editor), isTrue);
        expect(models.matchesCompactLeaveToken(compactToken), isTrue);
        expect(models.hasCompactDrafts(), isTrue);
        expect(models.hasUnconfirmedCompactSave(), isTrue);
        expect(models.compactLeaveBlocked(), isFalse);
        expect(
          h.container
              .read(provider)
              .requireValue
              .catalog
              .models
              .single
              .compact!
              .raw,
          '1350',
        );
        await pumpClientFuture(
          tester,
          models.saveCompact('model'),
          'unconfirmed compact Save cannot replay',
        );
        expect(h.models.compactCalls, hasLength(1));
        expect(models.hasUnconfirmedCompactSave(), isTrue);

        h.router.go(destination.location);
        await _accountDialog(tester);
        expectProductionWarning();
        await _chooseAccount(tester, AccountLeaveChoice.discard);
        await _at(tester, h.router, destination.location);
        expect(find.byType(AccountUnsavedChangesDialog), findsNothing);
        expect(owner.isActive, isFalse);
        expect(h.models.compactCalls, hasLength(1));
        expect(h.accounts.patches, isEmpty);
      } catch (error, stack) {
        caseFailure = error;
        caseStack = stack;
        rethrow;
      } finally {
        await _closeAfterCase(h.close, caseFailure, caseStack);
      }
    },
  );

  for (final creating in [true, false]) {
    testWidgets(
      creating
          ? 'actual editor reentry with a retained session observer creates a fresh Create draft'
          : 'actual editor reentry with a retained session observer creates a fresh same-account Edit draft',
      (tester) async {
        final h = await _mountRouter(tester);
        Object? caseFailure;
        StackTrace? caseStack;
        void Function()? closeObserver;
        try {
          final location = creating
              ? const AccountCreateRoute().location
              : const AccountEditRoute(
                  kind: AccountKind.native,
                  accountId: 'native',
                ).location;
          h.router.go(location);
          await _at(tester, h.router, location);
          final entryFinder = find.byType(AccountEditorEntryConnector);
          expect(entryFinder, findsOneWidget);
          final oldState = tester.state<State<AccountEditorEntryConnector>>(
            entryFinder,
          );
          final entry = oldState.widget.entry;
          final slot = accountEditorSessionViewModelProvider(entry);
          await pumpClientUntil(
            tester,
            () => h.container.read(slot).asData?.value.editor != null,
            'initial actual editor mount',
          );
          final oldSession = _captureMountedOwner(h.container, entry);
          final oldEditor = oldSession.currentEditor!;
          final oldDraftProvider = accountEditorViewModelProvider(oldEditor);
          final initialName = h.container
              .read(oldDraftProvider)
              .requireValue
              .native!
              .name
              .raw;
          final observer = h.container.listen(slot, (_, _) {});
          closeObserver = observer.close;
          await tester.enterText(
            _editorInput(oldEditor.editorId, 'name'),
            'Retired mount raw',
          );
          await tester.enterText(
            _editorInput(oldEditor.editorId, 'credential'),
            'retired-mount-secret',
          );
          await tester.pump();
          final oldDraft = h.container.read(oldDraftProvider).requireValue;
          expect(oldDraft.dirty, isTrue);
          expect(oldDraft.native!.name.raw, 'Retired mount raw');
          expect(oldDraft.native!.credential.raw, 'retired-mount-secret');
          h.router.go(const SettingsRoute().location);
          await _accountDialog(tester);
          await _chooseAccount(tester, AccountLeaveChoice.discard);
          await _at(tester, h.router, const SettingsRoute().location);
          await h.container.pump();
          expect(oldState.mounted, isFalse);
          expect(oldSession.isActive, isFalse);
          expect(
            h.container.exists(slot),
            isTrue,
            reason: 'A legal public observer retains this finished family.',
          );

          h.router.go(location);
          await _at(tester, h.router, location);
          expect(entryFinder, findsOneWidget);
          final newState = tester.state<State<AccountEditorEntryConnector>>(
            entryFinder,
          );
          expect(newState, isNot(same(oldState)));
          expect(newState.mounted, isTrue);
          expect(newState.widget.entry, entry);
          final newSlot = accountEditorSessionViewModelProvider(
            newState.widget.entry,
          );
          final newSlotNotifier = h.container.read(newSlot.notifier);
          final newSession = newSlotNotifier.currentOwner();
          final publishedOwnerId = h.container
              .read(newSlot)
              .asData
              ?.value
              .ownerId;
          final publishedEditor = h.container
              .read(newSlot)
              .asData
              ?.value
              .editor;
          List<String> onstageEditorIds() => [
            for (final view in tester.widgetList<NativeAccountEditorView>(
              find.byType(NativeAccountEditorView, skipOffstage: true),
            ))
              view.value.editorId,
          ];
          final observation =
              'creating=$creating oldStateMounted=${oldState.mounted} '
              'newStateMounted=${newState.mounted} sameLocator=true '
              'active=${newSession?.isActive} '
              'ownerId=${newSession?.ownerId} publishedOwnerId=$publishedOwnerId '
              'retiredOwnerId=${oldSession.ownerId} '
              'currentEditor=${newSession?.currentEditor?.editorId} '
              'publishedEditor=${publishedEditor?.editorId} '
              'retiredEditor=${oldEditor.editorId} '
              'onstageEditorIds=${onstageEditorIds()}';
          debugPrint('actual_reentry: $observation');
          final acp = h.container.read(acpServiceProvider) as VmAcp;
          expect(h.accounts.creates, isEmpty);
          expect(h.accounts.patches, isEmpty);
          expect(h.accounts.mutationCalls, isEmpty);
          expect(acp.starts, isEmpty);
          expect(acp.authStarts, isEmpty);
          expect(acp.saves, isEmpty);
          expect(newSession, isNotNull, reason: observation);
          final newOwner = newSession!;
          expect(newOwner, isNot(same(oldSession)), reason: observation);
          expect(newOwner.ownerId, isNot(oldSession.ownerId));
          expect(newSlotNotifier.isCurrentOwner(newOwner), isTrue);
          expect(newSlotNotifier.isCurrentOwner(oldSession), isFalse);
          expect(oldSession.isActive, isFalse);
          expect(publishedOwnerId, newOwner.ownerId);
          expect(newOwner.isActive, isTrue, reason: observation);
          expect(newOwner.currentEditor, isNotNull, reason: observation);
          final newEditor = newOwner.currentEditor!;
          expect(newEditor.editorId, isNot(oldEditor.editorId));
          expect(newEditor.creating, creating);
          final newDraftProvider = accountEditorViewModelProvider(newEditor);
          await pumpClientUntil(
            tester,
            () => h.container.read(newDraftProvider).hasValue,
            'fresh reentered editor draft',
          );
          final newDraft = h.container.read(newDraftProvider).requireValue;
          expect(onstageEditorIds(), [newEditor.editorId]);
          expect(newDraft.native!.name.raw, initialName);
          expect(newDraft.native!.credential.raw, isEmpty);
          await tester.enterText(
            _editorInput(newEditor.editorId, 'name'),
            'Fresh mount input',
          );
          await tester.pump();
          expect(
            h.container.read(newDraftProvider).requireValue.native!.name.raw,
            'Fresh mount input',
          );
          expect(h.accounts.creates, isEmpty);
          expect(h.accounts.patches, isEmpty);
          expect(acp.starts, isEmpty);
        } catch (error, stack) {
          caseFailure = error;
          caseStack = stack;
          rethrow;
        } finally {
          try {
            closeObserver?.call();
          } finally {
            await _closeAfterCase(h.close, caseFailure, caseStack);
          }
        }
      },
    );
  }

  testWidgets(
    'declared enum query input defaults only when missing and rejects unknown or empty values',
    (tester) async {
      final h = await _mountRouter(tester);
      Object? caseFailure;
      StackTrace? caseStack;
      try {
        const settings = SettingsRoute();
        const mode = SettingsRoute(section: SettingsSection.workModes);
        const model = AccountModelRoute(
          kind: AccountKind.native,
          accountId: 'native',
          modelId: 'model',
        );
        const pricing = AccountModelRoute(
          kind: AccountKind.native,
          accountId: 'native',
          modelId: 'model',
          tab: AccountModelTab.pricing,
        );
        final acceptedInvalidInputs = <String>[];
        for (final (field, missing, valid) in [
          ('section', settings.location, mode.location),
          ('tab', model.location, pricing.location),
        ]) {
          h.router.go(missing);
          await _at(tester, h.router, missing);
          expect(h.router.routerDelegate.currentConfiguration.error, isNull);
          if (field == 'section') {
            expect(
              settingsSectionForMatchedRoute(h.router.state),
              SettingsSection.accounts,
            );
            expect(
              readAccountRouteIdentity(h.router)?.page,
              AccountRoutePage.list,
            );
          } else {
            expect(
              readAccountRouteIdentity(h.router)?.tab,
              AccountModelTab.specifications,
            );
          }
          h.router.go(valid);
          await _at(tester, h.router, valid);
          expect(h.router.routerDelegate.currentConfiguration.error, isNull);
          if (field == 'section') {
            expect(
              settingsSectionForMatchedRoute(h.router.state),
              SettingsSection.workModes,
            );
          } else {
            expect(
              readAccountRouteIdentity(h.router)?.tab,
              AccountModelTab.pricing,
            );
          }
          // External input intentionally cannot be represented by typed enums.
          // Only these declared fields are constrained, not unrelated query keys.
          for (final raw in ['not-a-$field', '']) {
            final input = '$missing?$field=$raw';
            h.router.go(input);
            await pumpClientUntil(
              tester,
              () =>
                  h.router.routerDelegate.currentConfiguration.uri.toString() ==
                  input,
              'external enum query $input',
            );
            await tester.pumpAndSettle();
            if (h.router.routerDelegate.currentConfiguration.error == null) {
              final identity = readAccountRouteIdentity(h.router);
              acceptedInvalidInputs.add(
                '$input => page=${identity?.page.name}, '
                'section=${settingsSectionForMatchedRoute(h.router.state)?.name}, '
                'tab=${identity?.tab?.name}',
              );
            }
          }
        }
        // Collect both declared fields before failing so one defaulting defect
        // cannot hide the other field's acceptance of external invalid input.
        expect(
          acceptedInvalidInputs,
          isEmpty,
          reason: 'Invalid declared enum query must produce an official Router error, not a default.',
        );
      } catch (error, stack) {
        caseFailure = error;
        caseStack = stack;
        rethrow;
      } finally {
        await _closeAfterCase(h.close, caseFailure, caseStack);
      }
    },
  );
}

Finder _accountModelRow(String id) => find.byKey(
  ValueKey(
    AccountViewKeyValues.modelItem(AccountKind.native.name, 'native', id),
  ),
);

Finder _compactInput(String id) => find.descendant(
  of: find.descendant(
    of: _accountModelRow(id),
    matching: find.byKey(const ValueKey('account-compact-input')),
  ),
  matching: find.byType(EditableText),
);

Future<void> _deleteDialog(WidgetTester tester) async {
  await pumpClientUntil(
    tester,
    () => find.byType(AccountDeleteDialog).evaluate().isNotEmpty,
    'real deletion confirmation',
  );
  await tester.pumpAndSettle();
  expect(find.byType(AccountDeleteDialog), findsOneWidget);
}

Future<void> _confirmDeleteIfEnabled(WidgetTester tester) async {
  final confirm = find.descendant(
    of: find.byType(AccountDeleteDialog),
    matching: find.byType(FilledButton),
  );
  expect(confirm, findsOneWidget);
  if (tester.widget<FilledButton>(confirm).onPressed != null) {
    await tester.tap(confirm);
    await tester.pump();
  }
}

Future<void> _cancelDeleteIfOpen(WidgetTester tester) async {
  final dialog = find.byType(AccountDeleteDialog);
  if (dialog.evaluate().isEmpty) return;
  await tester.tap(
    find.descendant(of: dialog, matching: find.byType(TextButton)),
  );
  await tester.pumpAndSettle();
}

Future<void> _openManualDelete(WidgetTester tester) async {
  final row = _accountModelRow('manual');
  expect(row, findsOneWidget);
  final l10n = AppLocalizations.of(tester.element(row));
  final remove = find.descendant(
    of: row,
    matching: find.text(l10n.settingsRemoveModel),
  );
  expect(remove, findsOneWidget);
  await tester.ensureVisible(remove);
  await tester.tap(remove);
  await _deleteDialog(tester);
}

Future<void> _tryAccountDelete(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('account-details-delete'));
  if (button.evaluate().isEmpty ||
      tester.widget<IconButton>(button).onPressed == null) {
    return;
  }
  await tester.tap(button);
  await tester.pumpAndSettle();
  if (find.byType(AccountDeleteDialog).evaluate().isNotEmpty) {
    await _confirmDeleteIfEnabled(tester);
    await tester.pumpAndSettle();
  }
}

Future<void> _expectDeletionBlocksModels(
  WidgetTester tester,
  ProviderContainer container,
  VmModels repository,
  AccountModelsViewModel owner,
) async {
  final provider = accountModelsViewModelProvider(nativeKey);
  expect(container.read(provider.notifier), same(owner));
  final raw = container
      .read(provider)
      .requireValue
      .catalog
      .models
      .singleWhere((row) => row.key.modelId == 'model')
      .compact!
      .raw;
  final compactCalls = repository.compactCalls.length;
  final connections = repository.connections.length;
  expect(
    find.descendant(
      of: _accountModelRow('model'),
      matching: find.byWidgetPredicate(
        (widget) => widget is EditableText && !widget.readOnly,
      ),
    ),
    findsNothing,
    reason: 'An admitted deletion closes the peer model input too.',
  );
  owner.changeCompact('model', '1550');
  owner.presetCompact('model', 75);
  await pumpClientFuture(
    tester,
    owner.saveCompact('model'),
    'delete blocks compact Save',
  );
  await pumpClientFuture(
    tester,
    owner.resetCompact('model'),
    'delete blocks compact CLEAR',
  );
  await pumpClientFuture(
    tester,
    owner.retryCompact('model'),
    'delete blocks compact retry',
  );
  await pumpClientFuture(
    tester,
    owner.setConnection('model', AccountConnection.http),
    'delete blocks peer model commands',
  );
  expect(
    container
        .read(provider)
        .requireValue
        .catalog
        .models
        .singleWhere((row) => row.key.modelId == 'model')
        .compact!
        .raw,
    raw,
  );
  expect(owner.hasCompactDrafts(), isFalse);
  expect(repository.compactCalls, hasLength(compactCalls));
  expect(repository.connections, hasLength(connections));
}

AccountEditorEntryKey _actualEditorEntry(WidgetTester tester) {
  final finder = find.byType(AccountEditorEntryConnector);
  expect(finder, findsOneWidget);
  return tester.widget<AccountEditorEntryConnector>(finder).entry;
}

AccountEditorSessionOwner _captureMountedOwner(
  ProviderContainer container,
  AccountEditorEntryKey entry,
) {
  final provider = accountEditorSessionViewModelProvider(entry);
  final slot = container.read(provider.notifier);
  final owner = slot.currentOwner();
  expect(owner, isNotNull);
  final captured = owner!;
  expect(captured.isActive, isTrue);
  expect(slot.isCurrentOwner(captured), isTrue);
  expect(container.read(provider).requireValue.ownerId, captured.ownerId);
  return captured;
}

Future<void> _accountDialog(WidgetTester tester) async {
  await pumpClientUntil(
    tester,
    () => find.byType(AccountUnsavedChangesDialog).evaluate().isNotEmpty,
    'account leave dialog',
  );
  await tester.pumpAndSettle();
  expect(find.byType(AccountUnsavedChangesDialog), findsOneWidget);
}

Future<void> _chooseAccount(
  WidgetTester tester,
  AccountLeaveChoice choice,
) async {
  final dialog = find.byType(AccountUnsavedChangesDialog);
  final l10n = AppLocalizations.of(tester.element(dialog));
  final label = switch (choice) {
    AccountLeaveChoice.cancel => l10n.accountsKeepEditing,
    AccountLeaveChoice.discard => l10n.accountsDiscard,
    AccountLeaveChoice.save => l10n.commonSave,
  };
  await tester.tap(find.descendant(of: dialog, matching: find.text(label)));
}

Future<void> _committed(
  WidgetTester tester,
  GoRouter router,
  String location,
) async {
  RouteMatchList committedConfiguration() {
    final configuration = router.routerDelegate.currentConfiguration;
    final last = configuration.lastOrNull;
    // Imperative navigation keeps its destination in the top match's list.
    return last is ImperativeRouteMatch ? last.matches : configuration;
  }

  for (var frame = 0; frame < 128; frame++) {
    final configuration = committedConfiguration();
    if (configuration.uri.toString() == location) {
      if (configuration.error != null) {
        fail(
          'Official Router error while entering $location: ${configuration.error}',
        );
      }
      if (configuration.matches.isNotEmpty) return;
    }
    await tester.runAsync(() async {});
    await tester.pump(const Duration(milliseconds: 1));
  }
  final configuration = committedConfiguration();
  fail(
    'Client did not settle: route $location; '
    'committed URI=${configuration.uri}; error=${configuration.error}',
  );
}

Future<void> _at(WidgetTester tester, GoRouter router, String location) async {
  await _committed(tester, router, location);
  await tester.pumpAndSettle();
  expect(router.state.uri.toString(), location);
}

Finder _manualInput(String row, String field) => find.descendant(
  of: find.byKey(ValueKey(AccountViewKeyValues.manualField(row, field))),
  matching: find.byType(EditableText),
);

Finder _editorInput(String editorId, String field) => find.descendant(
  of: find.byKey(ValueKey(AccountViewKeyValues.editorField(editorId, field))),
  matching: find.byType(EditableText),
);

Future<void> _focusedManualInput(
  WidgetTester tester,
  String row,
  String field,
) => pumpClientUntil(tester, () {
  final input = _manualInput(row, field);
  return input.evaluate().length == 1 &&
      tester.widget<EditableText>(input).focusNode.hasFocus;
}, 'production focus on manual $row/$field');

Widget _routerApp(ProviderContainer container, GoRouter router) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: pureStudioTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        routerConfig: router,
      ),
    );

Future<
  ({
    GoRouter router,
    ProviderContainer container,
    AppGraph graph,
    VmAccounts accounts,
    VmModels models,
    Future<void> Function() close,
  })
>
_mountRouter(WidgetTester tester, {bool manualModel = false}) async {
  final graph = AppGraph(
    transport: RecordingDemoTransport(),
    statisticsFeed: const TestStatisticsFeedPort(),
    clientId: 'typed-account-route-contract',
  );
  final accounts = VmAccounts()
    ..put(
      vmNative(
        manual: manualModel
            ? const [
                AccountModelCommand(
                  modelId: 'manual',
                  displayName: 'Manual model',
                  wireApi: 'chat_completions',
                  contextWindow: null,
                  maxOutputTokens: null,
                ),
              ]
            : const [],
      ),
    );
  final models = _RouteModels();
  if (manualModel) {
    const identity = NativeAccountIdentity('native');
    final directory = models.state.value;
    final catalog = directory.accounts[identity]!;
    models.state.publish(
      ModelDirectoryState(
        accounts: {
          ...directory.accounts,
          identity: AccountResource(
            stamp: catalog.stamp,
            value: AccountModelCatalog(
              identity: identity,
              models: [
                ...catalog.value!.models,
                const AccountModelView(
                  modelId: 'manual',
                  displayName: 'Manual model',
                  reasoningEfforts: [],
                  origin: ModelOrigin.manual,
                  context: ModelContextView(
                    unavailable: null,
                    contextWindow: 2000,
                    autoCompactLimit: 1000,
                  ),
                ),
              ],
              status: catalog.value!.status,
            ),
          ),
        },
        configurations: directory.configurations,
      ),
    );
  }
  final container = ProviderContainer(
    overrides: [
      appGraphProvider.overrideWithValue(graph),
      statisticsRepositoryProvider.overrideWithValue(
        graph.statisticsRepository,
      ),
      accountsRepositoryProvider.overrideWithValue(accounts),
      modelsRepositoryProvider.overrideWithValue(models),
      accountUsageRepositoryProvider.overrideWithValue(VmUsage()),
      acpServiceProvider.overrideWithValue(VmAcp()),
      accountOperationObservationProvider.overrideWithValue((_) => null),
    ],
  );
  final router = createApplicationRouter();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(hostAppsChannel, (_) async => null);
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  Future<void>? closing;
  var closeSettled = false;
  Future<void> closeOwnedResources() async {
    final failures = <String>[];
    Future<void> attempt(String stage, Future<void> Function() action) async {
      try {
        await action();
      } catch (error, stack) {
        failures.add('$stage: $error\n$stack');
      }
    }

    // Attempt every owned cleanup stage even if unmount/dispose itself fails.
    // A failure is retained and reported, never converted to successful close.
    await attempt('unmount route tree', () async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
    await attempt('dispose router', () async => router.dispose());
    await attempt('dispose container', () async => container.dispose());
    await attempt('close same AppGraph', () async {
      final report = await pumpClientFuture(
        tester,
        graph.close(deadline: DateTime.now().add(const Duration(seconds: 10))),
        'close route fixture',
      );
      expect(
        report.complete,
        isTrue,
        reason:
            'Unresolved route fixture resources: ${[for (final resource in report.unresolved) '${resource.owner}: ${resource.reason}']}',
      );
    });
    await attempt('release host mock', () async {
      messenger.setMockMethodCallHandler(hostAppsChannel, null);
    });
    if (failures.isNotEmpty) {
      throw TestFailure(
        'Route fixture cleanup failed:\n${failures.join('\n')}',
      );
    }
  }

  Future<void> close() => closing ??= closeOwnedResources().whenComplete(() {
    closeSettled = true;
  });
  // Setup-failure safety net only. Successful setup is closed by each callback's
  // awaited finally, before Flutter checks its pending-timer invariant.
  addTearDown(() async {
    if (!closeSettled) await close();
  });
  await pumpClientFuture(tester, graph.initialize(), 'bootstrap route fixture');
  await tester.pumpWidget(_routerApp(container, router));
  await tester.pumpAndSettle();
  return (
    router: router,
    container: container,
    graph: graph,
    accounts: accounts,
    models: models,
    close: close,
  );
}

Future<void> _closeAfterCase(
  Future<void> Function() close,
  Object? caseFailure,
  StackTrace? caseStack,
) async {
  try {
    await close();
  } catch (error, stack) {
    if (caseFailure != null) {
      Error.throwWithStackTrace(
        TestFailure(
          'Original route case failed: $caseFailure\n$caseStack\n'
          'Route fixture cleanup also failed: $error\n$stack',
        ),
        caseStack ?? stack,
      );
    }
    Error.throwWithStackTrace(error, stack);
  }
}

class _RouteModels extends VmModels {
  // The real Studio shell also observes the directory. Supplying its display
  // permit does not replace any Router, draft, query or ownership behavior.
  @override
  AccountDemand observeDirectory() => VmDemand();
}
