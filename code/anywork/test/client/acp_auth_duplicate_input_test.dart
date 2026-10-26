import 'package:anywork/src/features/settings/accounts/view_models/acp_account_view_model.dart';
import 'package:anywork/src/features/settings/accounts/view_models/acp_command_notice.dart';
import 'package:anywork/src/features/settings/accounts/state/account_presentations.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:anywork_client/accounts.dart';
import 'package:flutter_test/flutter_test.dart';

import 'accounts_view_models_test.dart';

void main() {
  const busy = StudioFailure(
    code: StudioFailureCode.busy,
    message: 'Busy',
    retryable: true,
    correlationId: 'test',
  );
  const failed = StudioFailure(
    code: StudioFailureCode.unavailable,
    message: 'Start failed',
    retryable: true,
    correlationId: 'start',
  );
  test(
    'late authentication failure cannot bind a newer canonical operation',
    () async {
      final h = AccountsVmHarness();
      addTearDown(h.dispose);
      publishVmAcp(h, const AcpUncheckedState());
      final owner = await listenVmAcp(h, vmAcpKey);
      final checking = owner.authenticate();
      publishVmAcp(h, const AcpCheckingState(operationId: 'old'));
      publishVmAcp(h, const AcpCancelledState());
      publishVmAcp(h, const AcpCheckingState(operationId: 'new'));
      h.acp.authStarts.single.completeError(failed);
      await checking;
      final panel = h.container
          .read(acpAccountViewModelProvider(vmAcpKey))
          .requireValue
          .panel;
      expect(panel.error, isNull);
      expect(panel.phase, AcpPresentationPhase.checking);
      expect(
        panel.availableActions,
        contains(AcpAccountAction.cancelAuthentication),
      );
    },
  );
  test(
    'a replaced authentication attempt cannot clear a newer local start',
    () async {
      final h = AccountsVmHarness();
      addTearDown(h.dispose);
      publishVmAcp(h, const AcpUncheckedState());
      final owner = await listenVmAcp(h, vmAcpKey);
      final first = owner.authenticate();
      publishVmAcp(h, const AcpCheckingState(operationId: 'old'));
      publishVmAcp(h, const AcpCancelledState());
      publishVmAcp(h, const AcpCheckingState(operationId: 'replacement'));
      publishVmAcp(h, const AcpCancelledState());
      final second = owner.authenticate();
      expect(h.acp.authStarts, hasLength(2));
      h.acp.authStarts.first.completeError(failed);
      await first;
      var panel = h.container
          .read(acpAccountViewModelProvider(vmAcpKey))
          .requireValue
          .panel;
      expect(panel.error, isNull);
      expect(panel.availableActions, isNot(contains(AcpAccountAction.check)));
      publishVmAcp(h, const AcpCheckingState(operationId: 'current'));
      h.acp.authStarts.last.completeError(failed);
      await second;
      panel = h.container
          .read(acpAccountViewModelProvider(vmAcpKey))
          .requireValue
          .panel;
      expect(panel.error, failed.message);
    },
  );
  test('current authentication failures remain visible before and after its operation is observed', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    publishVmAcp(h, const AcpUncheckedState());
    final owner = await listenVmAcp(h, vmAcpKey);
    var checking = owner.authenticate();
    h.acp.authStarts.single.completeError(failed);
    await checking;
    expect(
      h.container
          .read(acpAccountViewModelProvider(vmAcpKey))
          .requireValue
          .panel
          .error,
      failed.message,
    );
    checking = owner.authenticate();
    publishVmAcp(h, const AcpCheckingState(operationId: 'current'));
    // A different account's snapshot revision cannot retire this target intent.
    h.acp.auth.publish(
      const AccountResource(
        stamp: vmStamp,
        value: AcpAuthSnapshotView(
          revision: 2,
          updatedAt: 2,
          accounts: [
            AcpAuthAccountView(
              accountId: 'acp',
              connectionRevision: 1,
              state: AcpCheckingState(operationId: 'current'),
            ),
            AcpAuthAccountView(
              accountId: 'another-account',
              connectionRevision: 2,
              state: AcpCheckingState(operationId: 'unrelated'),
            ),
          ],
        ),
      ),
    );
    h.acp.authStarts.last.completeError(failed);
    await checking;
    expect(
      h.container
          .read(acpAccountViewModelProvider(vmAcpKey))
          .requireValue
          .panel
          .error,
      failed.message,
    );
  });
  test(
    'only typed busy for this exact live account connection is duplicate input',
    () {
      for (final auth in <AcpAuthStateView>[
        const AcpCheckingState(operationId: 'check'),
        const AcpAuthenticatingState(operationId: 'auth', methodId: 'browser'),
        const AcpVerifyingState(operationId: 'verify'),
        const AcpCancellingState(operationId: 'cancel'),
        const AcpClosingState(operationId: 'close'),
      ]) {
        expect(
          isAcpAuthDuplicateWhileInFlight(
            error: busy,
            accountId: 'acp',
            requestConnectionRevision: 1,
            account: vmAcpAccount,
            auth: auth,
          ),
          isTrue,
        );
        expect(
          isAcpAuthDuplicateWhileInFlight(
            error: busy,
            accountId: 'other',
            requestConnectionRevision: 1,
            account: vmAcpAccount,
            auth: auth,
          ),
          isFalse,
        );
        expect(
          isAcpAuthDuplicateWhileInFlight(
            error: busy,
            accountId: 'acp',
            requestConnectionRevision: 2,
            account: vmAcpAccount,
            auth: auth,
          ),
          isFalse,
        );
      }
      for (final auth in <AcpAuthStateView>[
        const AcpUncheckedState(),
        const AcpCancelledState(),
        const AcpRequiredState(server: null),
        const AcpVerifiedState(checkedAt: 10, server: null),
      ]) {
        expect(
          isAcpAuthDuplicateWhileInFlight(
            error: busy,
            accountId: 'acp',
            requestConnectionRevision: 1,
            account: vmAcpAccount,
            auth: auth,
          ),
          isFalse,
        );
      }
      for (final error in <Object>[
        StateError('transport'),
        const StudioFailure(
          code: StudioFailureCode.conflict,
          message: 'Changed',
          retryable: false,
          correlationId: 'test',
        ),
        const StudioFailure(
          code: StudioFailureCode.cancellationTooLate,
          message: 'Closing',
          retryable: false,
          correlationId: 'test',
        ),
      ]) {
        expect(
          isAcpAuthDuplicateWhileInFlight(
            error: error,
            accountId: 'acp',
            requestConnectionRevision: 1,
            account: vmAcpAccount,
            auth: const AcpCheckingState(operationId: 'check'),
          ),
          isFalse,
        );
      }
      expect(
        isAcpAuthDuplicateWhileInFlight(
          error: busy,
          accountId: 'acp',
          requestConnectionRevision: 1,
          account: null,
          auth: const AcpCheckingState(operationId: 'check'),
        ),
        isFalse,
      );
    },
  );
  test('real ACP VM suppresses matching busy, exposes real failures and cancellation remains independent', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    publishVmAcp(h, const AcpUncheckedState());
    final owner = await listenVmAcp(h, vmAcpKey);
    final checking = owner.authenticate();
    publishVmAcp(h, const AcpCheckingState(operationId: 'new'));
    final cancelling = owner.cancelAuthentication();
    expect(h.acp.authCancels, hasLength(1));
    h.acp.authStarts.single.completeError(busy);
    await checking;
    expect(
      h.container
          .read(acpAccountViewModelProvider(vmAcpKey))
          .requireValue
          .panel
          .error,
      isNull,
    );
    h.acp.authCancels.single.completeError(
      const StudioFailure(
        code: StudioFailureCode.unavailable,
        message: 'Cancel failed',
        retryable: true,
        correlationId: 'test',
      ),
    );
    await cancelling;
    expect(
      h.container
          .read(acpAccountViewModelProvider(vmAcpKey))
          .requireValue
          .panel
          .error,
      'Cancel failed',
    );
  });
}
