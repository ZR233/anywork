import 'dart:async';

import 'package:anywork/src/features/settings/accounts/state/account_presentations.dart';
import 'package:anywork/src/features/settings/accounts/state/account_view_state.dart';
import 'package:anywork/src/features/settings/accounts/view_models/account_editor_view_model.dart';
import 'package:anywork/src/features/settings/accounts/view_models/accounts_view_model.dart';
import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'accounts_view_models_test.dart';

void main() {
  test('old save finally cannot unlock or clear a newer editor save for the same account', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    h.accounts.put(vmNative());
    final navigation = await h.navigation();
    navigation.edit(nativeKey);
    final oldKey = h.container
        .read(accountsViewModelProvider)
        .requireValue
        .editor!;
    final old = await h.editor(oldKey);
    old.changeField(NativeAccountField.name, 'Old');
    final first = Completer<OperationState>();
    h.accounts.write = () => first.future;
    final firstSave = old.save();
    old.finish();
    navigation.finishEditor(oldKey);
    navigation.edit(nativeKey);
    final nextKey = h.container
        .read(accountsViewModelProvider)
        .requireValue
        .editor!;
    final next = await h.editor(nextKey);
    next.changeField(NativeAccountField.name, 'New');
    final second = Completer<OperationState>();
    h.accounts.write = () => second.future;
    final secondSave = next.save();
    first.complete(savedVmOperation());
    expect(await firstSave, isFalse);
    expect(
      (h.editorState(nextKey).native!.name.raw, h.editorState(nextKey).saving),
      ('New', true),
    );
    second.completeError(StateError('new failure'));
    expect(await secondSave, isFalse);
    expect(
      (
        h.editorState(nextKey).native!.name.raw,
        h.editorState(nextKey).dirty,
        h.editorState(nextKey).saving,
      ),
      ('New', true, false),
    );
  });
  test('a returned operation waits for actual durability; receipt acceptance alone cannot clear the draft', () async {
    final mutations = MutationBoard(clientId: 'vm');
    final h = AccountsVmHarness(
      operationLookup: (id) => mutations.lookup(id)?.state,
    );
    addTearDown(h.dispose);
    h.accounts.put(vmNative());
    final key = editKey();
    final owner = await h.editor(key);
    owner.changeField(NativeAccountField.name, 'Saved after observation');
    final operation = mutations.begin(target: 'account');
    operation.accept(
      CommitReceipt(
        operationId: operation.id,
        disposition: CommitDisposition.applied,
        targets: const [],
        effect: EffectPoint.immediate,
      ),
    );
    h.accounts.write = () async => operation.state.value;
    final saving = owner.save();
    await h.container.pump();
    expect((h.editorState(key).dirty, h.editorState(key).saving), (true, true));
    operation.markDurable();
    expect(await saving, isTrue);
    expect(h.editorState(key).dirty, isFalse);
  });
  test('save/discard/cancel leave choices execute the real owner, never navigate past failure or newer input', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    h.accounts.put(vmNative());
    final navigation = await h.navigation();
    navigation.search('Saved');
    navigation.edit(nativeKey);
    final key = h.container
        .read(accountsViewModelProvider)
        .requireValue
        .editor!;
    final owner = await h.editor(key);
    owner.changeField(NativeAccountField.name, 'First');
    expect(await owner.requestLeave(AccountLeaveChoice.cancel), isFalse);
    expect(
      h.container.read(accountsViewModelProvider).requireValue.editor,
      key,
    );
    final work = Completer<OperationState>();
    h.accounts.write = () => work.future;
    final decision = owner.requestLeave(AccountLeaveChoice.save);
    owner.changeField(NativeAccountField.name, 'Newer');
    work.complete(savedVmOperation());
    expect(await decision, isFalse);
    expect(h.editorState(key).native!.name.raw, 'Newer');
    h.accounts.write = () => Future.error(StateError('offline'));
    expect(await owner.requestLeave(AccountLeaveChoice.save), isFalse);
    expect(() => navigation.edit(nativeKey), throwsStateError);
    expect(await owner.requestLeave(AccountLeaveChoice.discard), isTrue);
    navigation.finishEditor(key);
    navigation.back();
    expect(
      h.container.read(accountsViewModelProvider).requireValue.list.search,
      'Saved',
    );
    navigation.edit(nativeKey);
    final next = h.container
        .read(accountsViewModelProvider)
        .requireValue
        .editor!;
    expect(next.editorId, isNot(key.editorId));
    await h.editor(next);
    expect(h.editorState(next).native!.name.raw, 'Saved name');
  });
  test('finish closes editor keepAlive; reopening the same bare id has an independent raw revision', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    h.accounts.put(vmNative());
    final key = editKey('finite');
    final provider = accountEditorViewModelProvider(key);
    final listening = h.container.listen(provider, (_, _) {});
    await h.container.read(provider.future);
    final owner = h.container.read(provider.notifier);
    owner.changeField(NativeAccountField.name, 'Discard');
    expect(await owner.requestLeave(AccountLeaveChoice.discard), isTrue);
    listening.close();
    await h.container.pump();
    expect(h.container.exists(provider), isFalse);
    final next = editKey('fresh');
    await h.editor(next);
    expect(
      (h.editorState(next).draftRevision, h.editorState(next).native!.name.raw),
      (0, 'Saved name'),
    );
  });
  test('a second narrow step failure preserves the first saved configuration and retries only the remaining diff', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    h.accounts.put(
      vmNative(
        manual: [
          const AccountModelCommand(
            modelId: 'manual',
            displayName: 'Manual',
            wireApi: 'chat_completions',
            contextWindow: null,
            maxOutputTokens: null,
          ),
        ],
      ),
    );
    final key = editKey();
    final owner = await h.editor(key);
    owner.changeField(NativeAccountField.name, 'Saved first');
    final row = h.editorState(key).native!.manualModels.single.editorKey;
    owner.changeModel(row, connection: AccountConnection.http);
    h.models.connectionWrite = () =>
        Future.error(StateError('connection failed'));
    expect(await owner.save(), isFalse);
    expect(
      (h.accounts.patches.single.name as AccountTextSet).value,
      'Saved first',
    );
    expect(h.editorState(key).dirty, isTrue);
    h.models.connectionWrite = () async => savedVmOperation();
    expect(await owner.save(), isTrue);
    expect(h.accounts.patches.last.name, isA<AccountTextKeep>());
    expect(h.accounts.patches.last.customModels, isA<AccountModelsKeep>());
    expect(h.models.connections, hasLength(2));
  });
  test('ACP saveAndConnect failure is not rolled back or retried as a new creation', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    const key = AccountEditorKey(
      editorId: 'acp-new',
      target: AccountDisplayKey(kind: AccountKind.acp, id: 'new'),
      creating: true,
      template: AccountTemplateKey(kind: AccountKind.acp, id: 'antigravity'),
    );
    final owner = await h.editor(key);
    final acpKey = h.editorState(key).acpKey!;
    // Preparation is a separate explicit owner intent. This test supplies the
    // already-ready domain result and explicitly claims it via the real VM.
    final prep = await listenVmAcp(h, acpKey);
    h.acp.install.publish(
      AccountResource(
        stamp: vmStamp,
        value: AcpInstallSnapshotView(
          revision: 1,
          updatedAt: 1,
          installations: [
            const AcpInstallEntryView(
              provider: AcpProviderView.antigravity,
              state: AcpInstallReadyState(
                operationId: 'prepared',
                server: AcpInstalledServerView(
                  installationId: 'id',
                  release: AcpInstallReleaseView(
                    version: '1.4.1',
                    target: 'linux-x86_64',
                    archiveUrl: 'https://example.test/archive',
                  ),
                  program: '/managed/program',
                ),
              ),
            ),
          ],
        ),
      ),
    );
    prep.usePrepared();
    var connects = 0;
    h.acp.connect = (command) async {
      connects++;
      return AcpSaveAndConnectResult(
        saved: AcpAccountSettingsView(
          accountId: command.accountId,
          name: command.name,
          provider: command.provider,
          connectionRevision: 7,
        ),
        checkFailure: const StudioFailure(
          code: StudioFailureCode.unavailable,
          message: 'Check rejected',
          retryable: true,
          correlationId: 'test',
        ),
      );
    };
    expect(await owner.save(), isFalse);
    expect(h.editorState(key).dirty, isFalse);
    expect(h.editorState(key).error, contains('Check rejected'));
    owner.changeName('Renamed after save');
    expect(await owner.save(), isTrue);
    expect(connects, 1);
    expect(h.acp.saves, hasLength(2));
  });
}
