import 'dart:async';

import 'package:anywork/src/features/settings/accounts/state/account_presentations.dart';
import 'package:anywork/src/features/settings/accounts/state/account_view_state.dart';
import 'package:anywork/src/features/settings/accounts/view_models/account_editor_view_model.dart';
import 'package:anywork/src/features/settings/accounts/view_models/account_editor_session_view_model.dart';
import 'package:anywork/src/features/settings/accounts/view_models/account_models_view_model.dart';
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
    final oldSession = await h.session(
      const AccountEditorEntryKey.editing(
        routeEntryId: 'old',
        account: nativeKey,
      ),
    );
    final oldKey = oldSession.currentEditor!;
    final old = await h.editor(oldKey);
    old.changeField(NativeAccountField.name, 'Old');
    final first = Completer<OperationState>();
    h.accounts.write = () => first.future;
    final firstSave = old.save();
    h.releaseSession(oldSession);
    final nextSession = await h.session(
      const AccountEditorEntryKey.editing(
        routeEntryId: 'next',
        account: nativeKey,
      ),
    );
    final nextKey = nextSession.currentEditor!;
    expect(nextSession.ownerId, isNot(oldSession.ownerId));
    expect(nextKey.editorId, isNot(oldKey.editorId));
    h.releaseSession(oldSession);
    expect(nextSession.isActive, isTrue);
    expect(nextSession.isEditorCurrent(nextKey), isTrue);
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
    // Before-admission call errors still throw; old-finally isolation is the risk here.
    second.completeError(StateError('new before-admission failure'));
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
    final board = MutationBoard(clientId: 'editor-leave');
    final h = AccountsVmHarness(
      operationLookup: (id) => board.lookup(id)?.state,
    );
    addTearDown(h.dispose);
    h.accounts.put(vmNative());
    final accountsOwner = await h.listOwner();
    accountsOwner.search('Saved');
    final session = await h.session(
      const AccountEditorEntryKey.editing(
        routeEntryId: 'leave',
        account: nativeKey,
      ),
    );
    final key = session.currentEditor!;
    final owner = await h.editor(key);
    owner.changeField(NativeAccountField.name, 'First');
    expect(await owner.requestLeave(AccountLeaveChoice.cancel), isFalse);
    expect(session.currentEditor, key);
    final work = Completer<OperationState>();
    h.accounts.write = () => work.future;
    final decision = owner.requestLeave(AccountLeaveChoice.save);
    expect(owner.leaveBlocked(), isTrue);
    expect(await owner.requestLeave(AccountLeaveChoice.discard), isFalse);
    owner.changeField(NativeAccountField.name, 'Newer');
    work.complete(savedVmOperation());
    expect(await decision, isFalse);
    expect(h.editorState(key).native!.name.raw, 'Newer');
    // A before-admission exception is not an uncertain admitted mutation.
    h.accounts.write = () => Future.error(StateError('before admission'));
    expect(await owner.requestLeave(AccountLeaveChoice.save), isFalse);
    expect(session.isEditorCurrent(key), isTrue);
    expect(h.editorState(key).native!.name.raw, 'Newer');
    final operation = board.begin(target: 'editor');
    operation.unknownOutcome(StateError('no confirmation'));
    h.accounts.write = () async => operation.state.value;
    expect(await owner.requestLeave(AccountLeaveChoice.save), isFalse);
    expect((owner.leaveBlocked(), owner.hasUnconfirmedSave()), (false, true));
    final attempts = h.accounts.patches.length;
    expect(await owner.requestLeave(AccountLeaveChoice.save), isFalse);
    expect(h.accounts.patches, hasLength(attempts));
    expect(await owner.requestLeave(AccountLeaveChoice.discard), isTrue);
    expect(board.lookup(operation.id), same(operation));
    expect(operation.state.value.failurePhase, OperationPhase.unknownOutcome);
    expect(session.isEditorCurrent(key), isTrue);
    expect(h.editorState(key).native!.name.raw, 'Newer');
    h.releaseSession(session);
    expect(session.currentEditor, isNull);
    expect(
      h.container.read(accountsViewModelProvider).requireValue.list.search,
      'Saved',
    );
    final nextSession = await h.session(
      const AccountEditorEntryKey.editing(
        routeEntryId: 'reopen',
        account: nativeKey,
      ),
    );
    final next = nextSession.currentEditor!;
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
    final token = owner.leaveToken();
    listening.close();
    await h.container.pump();
    expect(h.container.exists(provider), isTrue);
    expect(owner.matchesLeaveToken(token), isTrue);
    expect(h.editorState(key).native!.name.raw, 'Discard');
    owner.finish();
    await h.container.pump();
    expect(h.container.exists(provider), isFalse);
    final next = editKey('fresh');
    await h.editor(next);
    expect(
      (h.editorState(next).draftRevision, h.editorState(next).native!.name.raw),
      (0, 'Saved name'),
    );
  });
  test('a joint leave resolution keeps both drafts until actual removal and rejects superseded decisions', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    h.accounts.put(vmNative());
    final session = await h.session(
      const AccountEditorEntryKey.editing(
        routeEntryId: 'joint',
        account: nativeKey,
      ),
    );
    final key = session.currentEditor!;
    final editor = await h.editor(key);
    final models = await h.modelOwner();
    editor.changeField(NativeAccountField.name, 'Local name');
    models.changeCompact('model', '1200');
    final cancelled = session.beginLeaveDecision();
    final editorToken = editor.leaveToken();
    final compactToken = models.compactLeaveToken();
    expect(await editor.requestLeave(AccountLeaveChoice.cancel), isFalse);
    expect(
      await models.requestLeaveCompact(AccountLeaveChoice.cancel),
      isFalse,
    );
    session.cancelLeaveDecision(cancelled);
    expect(session.isEditorCurrent(key), isTrue);
    expect(editor.matchesLeaveToken(editorToken), isTrue);
    expect(models.matchesCompactLeaveToken(compactToken), isTrue);

    final decision = session.beginLeaveDecision();
    expect(await editor.requestLeave(AccountLeaveChoice.discard), isTrue);
    expect(
      await models.requestLeaveCompact(AccountLeaveChoice.discard),
      isTrue,
    );
    expect(
      session.resolveLeaveDecision(
        decision,
        source: key,
        editorToken: editorToken,
        models: models,
        compactToken: compactToken,
        discardCompact: true,
      ),
      isTrue,
    );
    expect(session.hasCurrentLeaveDecision, isTrue);
    expect(h.editorState(key).native!.name.raw, 'Local name');
    expect(models.hasCompactDrafts(), isTrue);
    // A later request invalidates the old resolution without clearing anything.
    final later = session.beginLeaveDecision();
    session.cancelLeaveDecision(decision);
    expect(session.isLeaveDecisionCurrent(later), isTrue);
    expect(session.hasCurrentLeaveDecision, isFalse);
    expect(
      session.resolveLeaveDecision(
        later,
        source: key,
        editorToken: editorToken,
        models: models,
        compactToken: compactToken,
        discardCompact: true,
      ),
      isTrue,
    );
    models.changeCompact('model', '1300');
    expect(session.hasCurrentLeaveDecision, isFalse);
    expect(models.discardCompactDrafts(compactToken), isFalse);
    expect(models.hasCompactDrafts(), isTrue);
    final current = session.beginLeaveDecision();
    expect(
      session.resolveLeaveDecision(
        current,
        source: key,
        editorToken: editor.leaveToken(),
        models: models,
        compactToken: models.compactLeaveToken(),
        discardCompact: true,
      ),
      isTrue,
    );
    final retainedEditorToken = editor.leaveToken();
    h.releaseSession(session);
    h.releaseSession(session);
    expect(session.isActive, isFalse);
    expect(editor.matchesLeaveToken(retainedEditorToken), isFalse);
    expect(models.hasCompactDrafts(), isFalse);
    expect(h.accounts.patches, isEmpty);
    expect(h.models.compactCalls, isEmpty);
  });

  test(
    'even a clean existing model owner is part of the finite leave decision',
    () async {
      final h = AccountsVmHarness();
      addTearDown(h.dispose);
      h.accounts.put(vmNative());
      final session = await h.session(
        const AccountEditorEntryKey.editing(
          routeEntryId: 'clean-models',
          account: nativeKey,
        ),
      );
      final key = session.currentEditor!;
      final editor = await h.editor(key);
      final models = await h.modelOwner();
      final decision = session.beginLeaveDecision();
      expect(
        session.resolveLeaveDecision(
          decision,
          source: key,
          editorToken: editor.leaveToken(),
        ),
        isFalse,
      );
      expect(
        session.resolveLeaveDecision(
          decision,
          source: key,
          editorToken: editor.leaveToken(),
          models: models,
          compactToken: models.compactLeaveToken(),
        ),
        isTrue,
      );
      final work = Completer<OperationState>();
      h.models.compactWrite = () => work.future;
      final resetting = models.resetCompact('model');
      expect(models.compactLeaveBlocked(), isTrue);
      expect(session.hasCurrentLeaveDecision, isFalse);
      work.complete(savedVmOperation());
      await resetting;
      expect(models.compactLeaveBlocked(), isFalse);
      expect(models.hasCompactDrafts(), isFalse);
      expect(session.hasCurrentLeaveDecision, isFalse);
      expect(session.isEditorCurrent(key), isTrue);
    },
  );
  test('a same-revision compact save wait permanently retires an already resolved joint discard', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    h.accounts.put(vmNative());
    final session = await h.session(
      const AccountEditorEntryKey.editing(
        routeEntryId: 'same-revision-wait',
        account: nativeKey,
      ),
    );
    final key = session.currentEditor!;
    final editor = await h.editor(key);
    final models = await h.modelOwner();
    models.changeCompact('model', '1200');
    final compactToken = models.compactLeaveToken();
    final editorToken = editor.leaveToken();
    final decision = session.beginLeaveDecision();
    expect(await editor.requestLeave(AccountLeaveChoice.discard), isTrue);
    expect(
      await models.requestLeaveCompact(AccountLeaveChoice.discard),
      isTrue,
    );
    expect(
      session.resolveLeaveDecision(
        decision,
        source: key,
        editorToken: editorToken,
        models: models,
        compactToken: compactToken,
        discardCompact: true,
      ),
      isTrue,
    );
    expect(session.hasCurrentLeaveDecision, isTrue);

    final admitted = Completer<void>();
    final work = Completer<OperationState>();
    h.models.compactWrite = () {
      admitted.complete();
      return work.future;
    };
    // No reset, owner replacement or second raw edit can invalidate the token:
    // this await alone must permanently revoke the joint resolution.
    final saving = models.saveCompact('model');
    await admitted.future.timeout(const Duration(seconds: 5));
    await h.container.pump();
    expect(models.compactLeaveBlocked(), isTrue);
    expect(models.matchesCompactLeaveToken(compactToken), isTrue);
    expect(session.hasCurrentLeaveDecision, isFalse);
    expect(
      await models.requestLeaveCompact(AccountLeaveChoice.discard),
      isFalse,
    );
    work.complete(
      failedVmOperation(
        OperationPhase.rejected,
        id: 'same-revision-rejected',
        error: StateError('rejected without changing the raw draft'),
      ),
    );
    await saving;
    await h.container.pump();
    expect(models.compactLeaveBlocked(), isFalse);
    expect(models.matchesCompactLeaveToken(compactToken), isTrue);
    expect(models.hasCompactDrafts(), isTrue);
    expect(models.compactLeaveError(), isNotNull);
    expect(session.hasCurrentLeaveDecision, isFalse);
    expect(session.isLeaveDecisionCurrent(decision), isFalse);
    expect(
      session.resolveLeaveDecision(
        decision,
        source: key,
        editorToken: editorToken,
        models: models,
        compactToken: compactToken,
        discardCompact: true,
      ),
      isFalse,
    );
    h.releaseSession(session);
    await h.container.pump();
    expect(models.hasCompactDrafts(), isTrue);
    expect(
      h.container
          .read(accountModelsViewModelProvider(nativeKey))
          .requireValue
          .catalog
          .models
          .single
          .compact!
          .raw,
      '1200',
    );
    expect(h.models.compactCalls, hasLength(1));
    expect(h.accounts.patches, isEmpty);
  });

  test('add-model navigation waits for readiness and consumes once even after the entry row is removed', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    const key = AccountEditorKey(
      editorId: 'add-entry',
      target: nativeKey,
      creating: false,
    );
    final owner = await h.editor(key);
    expect(owner.consumeAddModelEntry(requested: false), isNull);
    expect(owner.consumeAddModelEntry(requested: true), isNull);
    expect(h.accounts.patches, isEmpty);
    h.accounts.put(vmNative());
    final initialRevision = h.editorState(key).draftRevision;
    expect(owner.consumeAddModelEntry(requested: false), isNull);
    expect(h.editorState(key).native!.manualModels, isEmpty);
    expect(h.editorState(key).draftRevision, initialRevision);
    final entry = owner.consumeAddModelEntry(requested: true);
    expect(entry, isNotNull);
    expect(
      h.editorState(key).native!.manualModels.map((row) => row.editorKey),
      [entry],
    );
    expect(h.editorState(key).draftRevision, greaterThan(initialRevision));
    final consumedRevision = h.editorState(key).draftRevision;
    expect(owner.consumeAddModelEntry(requested: true), entry);
    expect(owner.consumeAddModelEntry(requested: false), isNull);
    expect(owner.addModelEntryEditorKey(), entry);
    expect(h.editorState(key).native!.manualModels, hasLength(1));
    expect(h.editorState(key).draftRevision, consumedRevision);
    expect(await owner.removeModel(entry!), isTrue);
    final removedRevision = h.editorState(key).draftRevision;
    expect(owner.consumeAddModelEntry(requested: false), isNull);
    expect(owner.consumeAddModelEntry(requested: true), entry);
    expect(h.editorState(key).native!.manualModels, isEmpty);
    expect(h.editorState(key).draftRevision, removedRevision);
    owner.addModel();
    owner.addModel();
    final explicitRows = h.editorState(key).native!.manualModels;
    expect(explicitRows, hasLength(2));
    expect(explicitRows.map((row) => row.editorKey).toSet(), hasLength(2));
    expect(explicitRows.every((row) => row.editorKey != entry), isTrue);
    expect(owner.consumeAddModelEntry(requested: true), entry);
    expect(h.editorState(key).native!.manualModels, hasLength(2));
    expect(h.models.removed, isEmpty);
    expect(h.accounts.creates, isEmpty);
    expect(h.accounts.patches, isEmpty);
    expect(await owner.requestLeave(AccountLeaveChoice.discard), isTrue);
    expect(owner.consumeAddModelEntry(requested: true), entry);
    owner.finish();
    expect(owner.consumeAddModelEntry(requested: true), isNull);
    final ordinary = await h.editor(editKey('ordinary-add'));
    expect(ordinary.consumeAddModelEntry(requested: false), isNull);
    expect(
      h.editorState(editKey('ordinary-add')).native!.manualModels,
      isEmpty,
    );
  });
  test('template replacement commits a fresh owner only for the current same-page decision', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    const entry = AccountEditorEntryKey.creating(routeEntryId: 'templates');
    final provider = accountEditorSessionViewModelProvider(entry);
    final listening = h.container.listen(provider, (_, _) {});
    addTearDown(listening.close);
    await h.container.read(provider.future);
    final session = h.claimSession(entry);
    await session.initialize();
    final mountOwnerId = session.ownerId;
    expect(h.container.read(provider).requireValue.ownerId, mountOwnerId);
    const native = AccountTemplateKey(kind: AccountKind.native, id: 'native');
    const custom = AccountTemplateKey(kind: AccountKind.native, id: 'custom');
    final source = session.currentEditor!;
    final owner = await h.editor(source);
    owner.changeSetDefaultOnCreate(true);
    owner.changeField(NativeAccountField.credential, 'source-only-secret');
    owner.addModel();
    final row = h.editorState(source).native!.manualModels.single.editorKey;
    owner.changeModel(
      row,
      field: ManualModelField.id,
      raw: 'source-only-model',
    );
    final intent = session.beginTemplateReplacement(source)!;
    final token = owner.leaveToken();
    expect(await owner.requestLeave(AccountLeaveChoice.cancel), isFalse);
    expect(owner.matchesLeaveToken(token), isTrue);
    expect(session.isEditorCurrent(source), isTrue);
    session.cancelTemplateReplacement(intent);
    expect(
      session.replaceTemplate(source: source, template: custom, token: intent),
      isNull,
    );
    final replacement = session.beginTemplateReplacement(source)!;
    expect(await owner.requestLeave(AccountLeaveChoice.discard), isTrue);
    // Detach the display observer like a covered/unmounted source connector;
    // only actual entry removal, not observation lifetime, owns retirement.
    listening.close();
    await h.container.pump();
    expect(h.container.exists(provider), isTrue);
    expect(owner.matchesLeaveToken(token), isTrue);
    expect(session.isTemplateReplacementCurrent(source, replacement), isTrue);
    final next = session.replaceTemplate(
      source: source,
      template: custom,
      token: replacement,
    )!;
    final nextOwner = await h.editor(next);
    expect(next.editorId, isNot(source.editorId));
    expect(h.editorState(next).native!.credential.raw, isEmpty);
    expect(h.editorState(next).native!.manualModels, isEmpty);
    expect(h.editorState(next).native!.setDefaultOnCreate, isFalse);
    expect(owner.matchesLeaveToken(token), isFalse);
    expect(session.isTemplateReplacementCurrent(source, replacement), isFalse);
    // A continuation from the old selector cannot finish or replace the new one.
    session.cancelTemplateReplacement(replacement);
    expect(session.isEditorCurrent(next), isTrue);
    expect(h.container.read(provider).requireValue.ownerId, mountOwnerId);
    expect(
      session.replaceTemplate(
        source: source,
        template: native,
        token: replacement,
      ),
      isNull,
    );
    final delayedIntent = session.beginTemplateReplacement(next)!;
    expect(await nextOwner.requestLeave(AccountLeaveChoice.discard), isTrue);
    final leave = session.beginLeaveDecision();
    expect(session.isLeaveDecisionCurrent(leave), isTrue);
    expect(
      session.replaceTemplate(
        source: next,
        template: native,
        token: delayedIntent,
      ),
      isNull,
    );
    expect(session.isEditorCurrent(next), isTrue);
    h.releaseSession(session);
    expect(
      session.replaceTemplate(
        source: next,
        template: native,
        token: delayedIntent,
      ),
      isNull,
    );
    expect(session.currentEditor, isNull);
    expect(h.accounts.creates, isEmpty);
    expect(h.accounts.patches, isEmpty);
  });
  test('Add uses authoritative Native order, falls back to ACP without preparation, and retries a real empty directory', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    final original = h.accounts.state.value;
    final nativeSession = await h.session(
      const AccountEditorEntryKey.creating(routeEntryId: 'native'),
    );
    final native = nativeSession.currentEditor!;
    expect(
      native.template,
      const AccountTemplateKey(kind: AccountKind.native, id: 'native'),
    );
    final nativeOwner = await h.editor(native);
    expect(await nativeOwner.requestLeave(AccountLeaveChoice.discard), isTrue);
    expect(nativeSession.isEditorCurrent(native), isTrue);
    h.releaseSession(nativeSession);
    h.accounts.state.publish(
      AccountsState(stamp: vmStamp, accounts: original.accounts),
    );
    final acpSession = await h.session(
      const AccountEditorEntryKey.creating(routeEntryId: 'acp'),
    );
    final acp = acpSession.currentEditor!;
    expect(
      acp.template,
      const AccountTemplateKey(kind: AccountKind.acp, id: 'antigravity'),
    );
    final acpOwner = await h.editor(acp);
    expect(h.acp.starts, isEmpty);
    expect(h.acp.authStarts, isEmpty);
    expect(h.acp.saves, isEmpty);
    expect(await acpOwner.requestLeave(AccountLeaveChoice.discard), isTrue);
    h.releaseSession(acpSession);
    h.acp.templates.publish(const AcpAccountCatalogView.empty());
    const entry = AccountEditorEntryKey.creating(routeEntryId: 'empty');
    final emptySession = await h.session(entry);
    final empty = h.container
        .read(accountEditorSessionViewModelProvider(entry))
        .requireValue;
    expect(empty.editor, isNull);
    expect(emptySession.isActive, isTrue);
    expect(empty.templates, isEmpty);
    h.accounts.state.publish(original);
    await emptySession.loadTemplates();
    expect(emptySession.currentEditor!.template, native.template);
    expect(h.accounts.creates, isEmpty);
    expect(h.accounts.patches, isEmpty);
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
    h.models.connectionWrite = () async => failedVmOperation(
      OperationPhase.rejected,
      id: 'connection-rejected',
      error: const StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'Connection rejected',
        retryable: false,
        correlationId: 'connection',
      ),
    );
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
    final session = await h.session(
      const AccountEditorEntryKey.creating(routeEntryId: 'acp-create'),
    );
    final initial = session.currentEditor!;
    final key = session.replaceTemplate(
      source: initial,
      template: const AccountTemplateKey(
        kind: AccountKind.acp,
        id: 'antigravity',
      ),
      token: session.beginTemplateReplacement(initial)!,
    )!;
    final owner = await h.editor(key);
    expect(h.editorState(key).acp!.accountKey, isNull);
    expect(
      (h.editorState(key).acp!.saveAndConnect, h.editorState(key).dirty),
      (true, true),
    );
    final acpKey = h.editorState(key).acpKey!;
    owner.changeSetDefaultOnCreate(true);
    // Preparation is a separate explicit owner intent. This test supplies the
    // already-ready domain result and explicitly claims it via the real VM.
    final prep = await listenVmAcp(h, acpKey);
    publishVmAcpReady(h);
    expect(h.editorState(key).canSave, isFalse);
    prep.usePrepared();
    expect(h.editorState(key).canSave, isTrue);
    expect(h.editorState(key).acp!.accountKey, isNull);
    var connects = 0;
    final started = Completer<AcpAccountUpdateView>();
    final completion = Completer<AcpSaveAndConnectResult>();
    h.acp.connect = (command) {
      connects++;
      started.complete(command);
      return completion.future;
    };
    final saving = owner.save();
    final command = await started.future.timeout(const Duration(seconds: 5));
    expect(command.accountId, key.target.id);
    expect(
      (h.editorState(key).saving, h.editorState(key).acp!.saveAndConnect),
      (true, true),
    );
    expect(h.editorState(key).acp!.accountKey, isNull);
    expect(await owner.save(), isFalse);
    expect(connects, 1);
    final saved = AcpAccountSettingsView(
      accountId: command.accountId,
      name: command.name,
      provider: command.provider,
      connectionRevision: 7,
    );
    publishVmAcp(h, const AcpUncheckedState(), account: saved);
    completion.complete(
      AcpSaveAndConnectResult(
        operation: savedVmOperation('acp-lifecycle-created'),
        saved: saved,
        checkFailure: const StudioFailure(
          code: StudioFailureCode.unavailable,
          message: 'Check admission failed',
          retryable: true,
          correlationId: 'acp-lifecycle',
        ),
      ),
    );
    expect(await saving, isFalse);
    expect(h.editorState(key).key, key);
    expect(h.editorState(key).saving, isFalse);
    expect(h.editorState(key).dirty, isFalse);
    expect(h.editorState(key).acp!.accountKey, key.target);
    expect(h.editorState(key).acp!.saveAndConnect, isFalse);
    expect(h.editorState(key).error, contains('Check admission failed'));
    expect(
      h.editorState(key).acpKey,
      AccountAcpKey(
        target: key.target,
        providerId: 'antigravity',
        connectionRevision: 7,
        editorId: key.editorId,
        creating: false,
      ),
    );
    owner.changeName('Renamed after save');
    expect(await owner.save(), isTrue);
    expect(connects, 1);
    expect(h.acp.saves, hasLength(2));
    expect(
      (h.acp.saves.last.accountId, h.acp.saves.last.name),
      (key.target.id, 'Renamed after save'),
    );
    final renamed = AcpAccountSettingsView(
      accountId: saved.accountId,
      name: 'Renamed after save',
      provider: saved.provider,
      connectionRevision: saved.connectionRevision,
    );
    publishVmAcp(h, const AcpUncheckedState(), account: renamed);
    owner.finish();
    h.releaseSession(session);
    final editSession = await h.session(
      AccountEditorEntryKey.editing(
        routeEntryId: 'acp-reopen',
        account: key.target,
      ),
    );
    final edit = editSession.currentEditor!;
    final editOwner = await h.editor(edit);
    expect((edit.creating, edit.target), (false, key.target));
    expect(edit.editorId, isNot(key.editorId));
    expect(h.editorState(edit).acp!.accountKey, key.target);
    expect(h.editorState(edit).acp!.saveAndConnect, isFalse);
    expect(h.editorState(edit).acp!.name.raw, 'Renamed after save');
    editOwner.changeName('Rejected edit stays local');
    editOwner.setStrings(vmOperationStrings);
    h.acp.write = () async => failedVmOperation(
      OperationPhase.rejected,
      id: 'acp-name-rejected',
      error: const StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'Account name rejected',
        retryable: false,
        correlationId: 'acp-edit-rejected',
      ),
    );
    expect(await editOwner.save(), isFalse);
    expect(
      (h.editorState(edit).acp!.name.raw, h.editorState(edit).dirty),
      ('Rejected edit stays local', true),
    );
    expect(h.editorState(edit).key, edit);
    expect(h.editorState(edit).acp!.accountKey, key.target);
    expect(h.editorState(edit).error, 'Save failed');
    expect(editSession.isEditorCurrent(edit), isTrue);
    expect(connects, 1);
    expect(h.acp.saves, hasLength(3));
    expect(h.accounts.defaultCalls, isEmpty);
    expect(h.accounts.billing, isEmpty);
  });
  test('ACP unconfirmed creation stays local and frozen despite a newer confirmed observation', () async {
    for (final phase in [
      OperationPhase.unknownOutcome,
      OperationPhase.syncFailed,
    ]) {
      final id = OperationId('acp-create-${phase.name}');
      final operation = OperationState(
        id: id,
        target: 'test',
        failurePhase: phase,
        error: StateError('creation outcome unconfirmed'),
        receipt: phase == OperationPhase.syncFailed
            ? CommitReceipt(
                operationId: id,
                disposition: CommitDisposition.applied,
                targets: const [vmStamp],
                effect: EffectPoint.immediate,
                durable: true,
              )
            : null,
      );
      // This is an external observation, not a replay or a fake settlement rule.
      // The SDK result's frozen failure must win over this newer same-id value.
      final newer = LatestValue(savedVmOperation(id.value));
      final h = AccountsVmHarness(
        operationLookup: (requested) => requested == id ? newer : null,
      );
      addTearDown(h.dispose);
      final session = await h.session(
        const AccountEditorEntryKey.creating(routeEntryId: 'acp-create'),
      );
      final initial = session.currentEditor!;
      final key = session.replaceTemplate(
        source: initial,
        template: const AccountTemplateKey(
          kind: AccountKind.acp,
          id: 'antigravity',
        ),
        token: session.beginTemplateReplacement(initial)!,
      )!;
      final owner = await h.editor(key);
      final prep = await listenVmAcp(h, h.editorState(key).acpKey!);
      publishVmAcpReady(h);
      expect(h.editorState(key).canSave, isFalse);
      prep.usePrepared();
      expect(h.editorState(key).canSave, isTrue);
      owner.changeName('Unconfirmed ${phase.name} input');
      final raw = h.editorState(key).acp!.name.raw;
      var connects = 0;
      h.acp.connect = (command) async {
        connects++;
        expect(command.accountId, key.target.id);
        return AcpSaveAndConnectResult(operation: operation, saved: null);
      };
      expect(await owner.save(), isFalse);
      expect(
        (
          owner.hasUnconfirmedSave(),
          h.editorState(key).saving,
          h.editorState(key).canSave,
        ),
        (true, false, false),
      );
      expect(h.editorState(key).key, key);
      expect(h.editorState(key).acp!.accountKey, isNull);
      expect(h.editorState(key).acp!.saveAndConnect, isTrue);
      expect(h.editorState(key).acp!.name.raw, raw);
      expect(h.editorState(key).dirty, isTrue);
      expect(h.editorState(key).error, isNotNull);
      expect(session.isEditorCurrent(key), isTrue);
      expect(await owner.save(), isFalse);
      owner.changeName('New input cannot bypass ${phase.name}');
      expect(await owner.save(), isFalse);
      expect(
        h.editorState(key).acp!.name.raw,
        'New input cannot bypass ${phase.name}',
      );
      expect(h.editorState(key).acp!.accountKey, isNull);
      expect(h.editorState(key).dirty, isTrue);
      expect(connects, 1);
      expect(h.acp.saves, hasLength(1));
      expect(await owner.requestLeave(AccountLeaveChoice.cancel), isFalse);
      expect(session.isEditorCurrent(key), isTrue);
      expect(h.acp.cancels, isEmpty);
      expect(h.acp.authCancels, isEmpty);
      expect(await owner.requestLeave(AccountLeaveChoice.discard), isTrue);
      expect(session.isEditorCurrent(key), isTrue);
      expect(
        h.editorState(key).acp!.name.raw,
        'New input cannot bypass ${phase.name}',
      );
      h.releaseSession(session);
      expect(session.currentEditor, isNull);
      expect(connects, 1);
      expect(h.acp.saves, hasLength(1));
      expect(h.acp.cancels, isEmpty);
      expect(h.acp.authCancels, isEmpty);
    }
  });
}
