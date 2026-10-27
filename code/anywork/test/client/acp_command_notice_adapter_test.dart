import 'package:anywork/src/features/settings/accounts/state/account_presentations.dart';
import 'package:anywork/src/features/settings/accounts/state/account_view_state.dart';
import 'package:anywork/src/features/settings/accounts/view_models/account_editor_view_model.dart';
import 'package:anywork/src/features/settings/accounts/view_models/acp_command_notice.dart';
import 'package:anywork_client/acp.dart';
import 'package:flutter_test/flutter_test.dart';

import 'accounts_view_models_test.dart';

void main() {
  AcpCommandNotice notice(AcpCommandNoticeKind kind, {String? operation}) =>
      AcpCommandNotice(
        kind: kind,
        summary: 'Configuration failed',
        accountId: 'acp',
        connectionRevision: 1,
        operationId: operation,
      );
  test('configuration/remove notices are target and connection scoped, not hidden by Verified', () {
    const verified = AcpVerifiedState(checkedAt: 1, server: null);
    for (final kind in [
      AcpCommandNoticeKind.configuration,
      AcpCommandNoticeKind.remove,
    ]) {
      final failure = notice(kind);
      expect(
        visibleAcpCommandNotice(failure, vmAcpAccount, verified),
        same(failure),
      );
      expect(
        visibleAcpCommandNotice(
          failure,
          vmAcpAccount.copyWith(connectionRevision: 2),
          verified,
        ),
        isNull,
      );
      expect(
        visibleAcpCommandNotice(
          failure,
          const AcpAccountSettingsView(
            accountId: 'other',
            name: 'Other',
            provider: AcpProviderView.antigravity,
            connectionRevision: 1,
          ),
          verified,
        ),
        isNull,
      );
    }
    final auth = notice(AcpCommandNoticeKind.authentication, operation: 'old');
    expect(
      visibleAcpCommandNotice(
        auth,
        vmAcpAccount,
        const AcpCheckingState(operationId: 'old'),
      ),
      same(auth),
    );
    expect(
      visibleAcpCommandNotice(
        auth,
        vmAcpAccount,
        const AcpCheckingState(operationId: 'new'),
      ),
      isNull,
    );
    expect(visibleAcpCommandNotice(auth, vmAcpAccount, verified), isNull);
  });
  test('actual editor failed configuration save remains visible with a Verified ACP panel', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    publishVmAcp(h, const AcpVerifiedState(checkedAt: 10, server: null));
    const key = AccountEditorKey(
      editorId: 'acp-edit',
      target: AccountDisplayKey(kind: AccountKind.acp, id: 'acp'),
      creating: false,
    );
    final owner = await h.editor(key);
    owner.changeName('Renamed');
    h.acp.write = () => Future.error(StateError('disk'));
    expect(await owner.save(), isFalse);
    final value = owner.presentation(
      panel: const AcpAccountPresentation(
        phase: AcpPresentationPhase.connected,
        status: 'Connected',
      ),
    );
    expect(value.dirty, isTrue);
    expect(value.acp!.name.raw, 'Renamed');
    expect(value.acp!.preparation.phase, AcpPresentationPhase.connected);
    expect(value.error, isNotNull);
    expect(value.acp!.error, value.error);
    expect(
      h.container.read(accountEditorViewModelProvider(key)).requireValue.saving,
      isFalse,
    );
  });
}
