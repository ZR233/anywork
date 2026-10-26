import 'dart:async';

import 'package:anywork/src/features/settings/accounts/state/account_presentations.dart';
import 'package:anywork/src/features/settings/accounts/state/account_view_state.dart';
import 'package:anywork/src/features/settings/accounts/view_models/acp_account_view_model.dart';
import 'package:anywork/src/features/settings/accounts/view_models/account_projection.dart';
import 'package:anywork/src/features/settings/accounts/connectors/account_strings.dart';
import 'package:anywork/src/l10n/app_localizations_en.dart';
import 'package:anywork/src/l10n/app_localizations_zh.dart';
import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/acp.dart';
import 'package:anywork_client/studio_client.dart'
    show StudioFailure, StudioFailureCode;
import 'package:flutter_test/flutter_test.dart';

import 'accounts_view_models_test.dart';

const release = AcpInstallReleaseView(
  version: '1.4.1',
  target: 'linux-x86_64',
  archiveUrl: 'https://dl.google.com/agy-extensions/release.zip',
);
const server = AcpInstalledServerView(
  installationId: 'installation',
  release: release,
  program: '/managed/program',
  readyAt: 100,
);
AcpInstallSnapshotView installSnapshot(AcpInstallStateView state) =>
    AcpInstallSnapshotView(
      revision: 1,
      updatedAt: 100,
      installations: [
        AcpInstallEntryView(
          provider: AcpProviderView.antigravity,
          state: state,
        ),
      ],
    );
void publishInstall(AccountsVmHarness h, AcpInstallStateView state) => h
    .acp
    .install
    .publish(AccountResource(stamp: vmStamp, value: installSnapshot(state)));
const creatingKey = AccountAcpKey(
  target: AccountDisplayKey(kind: AccountKind.acp, id: 'new'),
  providerId: 'antigravity',
  connectionRevision: 0,
  editorId: 'form-1',
  creating: true,
);

void main() {
  test('a saved account can explicitly check again after preparing its required installation', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    publishVmAcp(
      h,
      const AcpFailedState(
        failure: AcpAuthFailureView(
          code: AcpAuthFailureCodeView.preparationRequired,
          stage: AcpAuthStageView.prepare,
          message: 'Prepare first',
          retryable: true,
        ),
      ),
    );
    final owner = await listenVmAcp(h, vmAcpKey);
    final preparing = owner.prepare();
    publishInstall(
      h,
      const AcpInstallReadyState(operationId: 'ready', server: server),
    );
    h.acp.starts.single.complete(
      installSnapshot(
        const AcpInstallReadyState(operationId: 'ready', server: server),
      ),
    );
    await preparing;
    expect(
      h.container
          .read(acpAccountViewModelProvider(vmAcpKey))
          .requireValue
          .panel
          .availableActions,
      contains(AcpAccountAction.check),
    );
    final checking = owner.authenticate();
    publishVmAcp(h, const AcpCheckingState(operationId: 'check'));
    publishInstall(h, const AcpResolvingState(operationId: 'shared-operation'));
    expect(
      h.container
          .read(acpAccountViewModelProvider(vmAcpKey))
          .requireValue
          .panel
          .availableActions,
      contains(AcpAccountAction.cancelAuthentication),
    );
    publishInstall(
      h,
      const AcpInstallReadyState(operationId: 'ready', server: server),
    );
    publishVmAcp(h, const AcpVerifiedState(checkedAt: 100, server: null));
    h.acp.authStarts.single.complete(h.acp.auth.value.value!);
    await checking;
    expect(
      h.container
          .read(acpAccountViewModelProvider(vmAcpKey))
          .requireValue
          .panel
          .phase,
      AcpPresentationPhase.connected,
    );
  });
  test('selecting an ACP template waits for baseline and never implicitly claims shared Ready', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    h.acp.install.publish(const AccountResource());
    const key = AccountEditorKey(
      editorId: 'selected-template',
      target: AccountDisplayKey(kind: AccountKind.acp, id: 'new'),
      creating: true,
      template: AccountTemplateKey(kind: AccountKind.acp, id: 'antigravity'),
    );
    final editor = await h.editor(key);
    final acpKey = h.editorState(key).acpKey!;
    final selected = editor.prepareSelectedTemplate();
    expect(h.acp.starts, isEmpty);
    expect(h.editorState(key).canSave, isFalse);
    publishInstall(
      h,
      const AcpInstallReadyState(operationId: 'shared', server: server),
    );
    await selected;
    expect(h.acp.starts, isEmpty);
    expect(
      h.container
          .read(acpAccountViewModelProvider(acpKey))
          .requireValue
          .claimedOperationId,
      isNull,
    );
    expect(h.editorState(key).canSave, isFalse);
    h.container
        .read(acpAccountViewModelProvider(acpKey).notifier)
        .usePrepared();
    expect(
      h.container
          .read(acpAccountViewModelProvider(acpKey))
          .requireValue
          .claimedOperationId,
      'shared',
    );
    expect(h.editorState(key).canSave, isTrue);
    h.acp.install.publish(
      const AccountResource(
        failure: StudioFailure(
          code: StudioFailureCode.unavailable,
          message: 'Install baseline unavailable',
          retryable: true,
          correlationId: 'baseline',
        ),
      ),
    );
    final failedKey = key.copyWith(editorId: 'failed-selection');
    final failed = await h.editor(failedKey);
    await failed.prepareSelectedTemplate();
    final failedAcp = h.editorState(failedKey).acpKey!;
    expect(
      h.container
          .read(acpAccountViewModelProvider(failedAcp))
          .requireValue
          .panel
          .error,
      'Install baseline unavailable',
    );
    expect(h.acp.starts, isEmpty);
    expect(h.editorState(failedKey).canSave, isFalse);
  });
  test('late baseline for a finished editor cannot prepare or claim for its replacement', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    h.acp.install.publish(const AccountResource());
    const key = AccountEditorKey(
      editorId: 'old-selection',
      target: AccountDisplayKey(kind: AccountKind.acp, id: 'new'),
      creating: true,
      template: AccountTemplateKey(kind: AccountKind.acp, id: 'antigravity'),
    );
    final old = await h.editor(key);
    final oldSelected = old.prepareSelectedTemplate();
    expect(h.acp.starts, isEmpty);
    old.finish();
    await oldSelected;
    final nextKey = key.copyWith(editorId: 'new-selection');
    final next = await h.editor(nextKey);
    final started = Completer<void>();
    h.acp.prepareStarted = started;
    final nextSelected = next.prepareSelectedTemplate();
    expect(h.acp.starts, isEmpty);
    publishInstall(h, const AcpInstallIdleState());
    await started.future;
    expect(h.acp.starts, hasLength(1));
    publishInstall(
      h,
      const AcpInstallReadyState(operationId: 'new', server: server),
    );
    h.acp.starts.single.complete(
      installSnapshot(
        const AcpInstallReadyState(operationId: 'new', server: server),
      ),
    );
    await nextSelected;
    final nextAcp = h.editorState(nextKey).acpKey!;
    expect(
      h.container
          .read(acpAccountViewModelProvider(nextAcp))
          .requireValue
          .claimedOperationId,
      'new',
    );
    expect(h.editorState(nextKey).canSave, isTrue);
  });
  test('canonical preparation retry count and reused installation are visibly localized facts', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    final owner = await listenVmAcp(h, creatingKey);
    for (final l10n in [AppLocalizationsEn(), AppLocalizationsZh()]) {
      owner.setStrings(accountStrings(l10n));
      publishInstall(
        h,
        const AcpDownloadingState(
          operationId: 'download',
          release: release,
          progress: AcpInstallProgressView(completedBytes: 5, totalBytes: 10),
          retryCount: 3,
        ),
      );
      var facts = h.container
          .read(acpAccountViewModelProvider(creatingKey))
          .requireValue
          .panel
          .facts;
      expect(
        facts
            .where((fact) => fact.label == l10n.acpInstallFactRetries)
            .single
            .value,
        l10n.acpInstallRetryValue(3),
      );
      publishInstall(
        h,
        const AcpDownloadingState(
          operationId: 'download',
          release: release,
          progress: AcpInstallProgressView(completedBytes: 5, totalBytes: 10),
        ),
      );
      facts = h.container
          .read(acpAccountViewModelProvider(creatingKey))
          .requireValue
          .panel
          .facts;
      expect(
        facts
            .where((fact) => fact.label == l10n.acpInstallFactRetries)
            .single
            .value,
        l10n.acpInstallRetryValue(0),
      );
      publishInstall(
        h,
        const AcpInstallReadyState(
          operationId: 'reused',
          server: AcpInstalledServerView(
            installationId: 'reused',
            release: release,
            program: '/managed/program',
            readyAt: 100,
            reused: true,
          ),
        ),
      );
      facts = h.container
          .read(acpAccountViewModelProvider(creatingKey))
          .requireValue
          .panel
          .facts;
      expect(
        facts.any((fact) => fact.value == l10n.acpInstallReusedBadge),
        isTrue,
      );
      publishInstall(
        h,
        const AcpInstallReadyState(operationId: 'fresh', server: server),
      );
      facts = h.container
          .read(acpAccountViewModelProvider(creatingKey))
          .requireValue
          .panel
          .facts;
      expect(
        facts.any((fact) => fact.value == l10n.acpInstallReusedBadge),
        isFalse,
      );
    }
  });
  test('build never prepares, explicit start owns its operation, 100 percent is not Ready', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    final owner = await listenVmAcp(h, creatingKey);
    expect(h.acp.starts, isEmpty);
    final preparing = owner.prepare();
    publishInstall(
      h,
      const AcpDownloadingState(
        operationId: 'mine',
        release: release,
        progress: AcpInstallProgressView(completedBytes: 100, totalBytes: 100),
      ),
    );
    expect(
      h.container
          .read(acpAccountViewModelProvider(creatingKey))
          .requireValue
          .preparedForEditor,
      isFalse,
    );
    expect(
      h.container
          .read(acpAccountViewModelProvider(creatingKey))
          .requireValue
          .panel
          .availableActions,
      contains(AcpAccountAction.cancelPreparation),
    );
    h.acp.starts.single.complete(
      installSnapshot(const AcpResolvingState(operationId: 'mine')),
    );
    await preparing;
    publishInstall(
      h,
      const AcpInstallReadyState(operationId: 'mine', server: server),
    );
    final ready = h.container
        .read(acpAccountViewModelProvider(creatingKey))
        .requireValue;
    expect(ready.preparedForEditor, isTrue);
    expect(ready.claimedOperationId, 'mine');
  });
  test('same provider Ready is not inherited; usePrepared explicitly claims it and cannot race start', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    publishInstall(
      h,
      const AcpInstallReadyState(operationId: 'other', server: server),
    );
    final owner = await listenVmAcp(h, creatingKey);
    await owner.prepare();
    expect(h.acp.starts, isEmpty);
    expect(
      h.container
          .read(acpAccountViewModelProvider(creatingKey))
          .requireValue
          .preparedForEditor,
      isFalse,
    );
    owner.usePrepared();
    expect(
      h.container
          .read(acpAccountViewModelProvider(creatingKey))
          .requireValue
          .claimedOperationId,
      'other',
    );
    publishInstall(h, const AcpInstallIdleState());
    final starting = owner.prepare();
    publishInstall(
      h,
      const AcpInstallReadyState(operationId: 'another', server: server),
    );
    owner.usePrepared();
    expect(
      h.container
          .read(acpAccountViewModelProvider(creatingKey))
          .requireValue
          .claimedOperationId,
      isNull,
    );
    h.acp.starts.single.complete(
      installSnapshot(const AcpResolvingState(operationId: 'own')),
    );
    await starting;
    expect(
      h.container
          .read(acpAccountViewModelProvider(creatingKey))
          .requireValue
          .claimedOperationId,
      'own',
    );
    expect(
      h.container
          .read(acpAccountViewModelProvider(creatingKey))
          .requireValue
          .preparedForEditor,
      isFalse,
    );
  });
  test('late start response/error cannot claim a new editor with the same account id', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    final old = await listenVmAcp(h, creatingKey);
    final pending = old.prepare();
    old.finish();
    final freshKey = creatingKey.copyWith(editorId: 'form-2');
    final fresh = await listenVmAcp(h, freshKey);
    final next = fresh.prepare();
    h.acp.starts[0].completeError(StateError('old failure'));
    await pending;
    expect(
      h.container
          .read(acpAccountViewModelProvider(freshKey))
          .requireValue
          .panel
          .error,
      isNull,
    );
    publishInstall(
      h,
      const AcpInstallReadyState(operationId: 'fresh', server: server),
    );
    h.acp.starts[1].complete(
      installSnapshot(
        const AcpInstallReadyState(operationId: 'fresh', server: server),
      ),
    );
    await next;
    expect(
      h.container
          .read(acpAccountViewModelProvider(freshKey))
          .requireValue
          .claimedOperationId,
      'fresh',
    );
  });
  test('cancel is independent of pending start and old cancel finally does not clear a new operation attempt', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    final owner = await listenVmAcp(h, creatingKey);
    owner.setStrings(const AccountStrings({'failed': 'Failed'}));
    final starting = owner.prepare();
    publishInstall(h, const AcpResolvingState(operationId: 'first'));
    final first = owner.cancelPreparation();
    final duplicate = owner.cancelPreparation();
    await duplicate;
    expect(h.acp.cancels, hasLength(1));
    publishInstall(h, const AcpResolvingState(operationId: 'second'));
    final second = owner.cancelPreparation();
    expect(h.acp.cancels, hasLength(2));
    h.acp.cancels[0].completeError(StateError('old'));
    await first;
    final current = h.container
        .read(acpAccountViewModelProvider(creatingKey))
        .requireValue
        .panel;
    expect(current.error, isNull);
    expect(
      current.availableActions,
      isNot(contains(AcpAccountAction.cancelPreparation)),
    );
    h.acp.cancels[1].complete(
      installSnapshot(const AcpInstallCancelledState(operationId: 'second')),
    );
    await second;
    h.acp.starts.single.complete(
      installSnapshot(const AcpResolvingState(operationId: 'first')),
    );
    await starting;
  });
  test(
    'unsupported typed template cannot start automatic preparation',
    () async {
      final h = AccountsVmHarness();
      addTearDown(h.dispose);
      h.acp.templates.publish(
        const AcpAccountCatalogView(
          templates: [
            AcpAccountTemplateView(
              provider: AcpProviderView.antigravity,
              displayName: 'Unsupported',
              supportedVersion: 'future',
            ),
          ],
        ),
      );
      final owner = await listenVmAcp(h, creatingKey);
      await owner.prepare();
      expect(h.acp.starts, isEmpty);
      expect(
        h.container
            .read(acpAccountViewModelProvider(creatingKey))
            .requireValue
            .panel
            .availableActions,
        isNot(contains(AcpAccountAction.prepare)),
      );
    },
  );
}
