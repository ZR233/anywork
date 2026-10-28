import 'package:anywork/src/diagnostics/studio_driver_keys.dart';
import 'package:anywork/src/features/settings/accounts/state/acp_account_auth_state.dart';
import 'package:anywork/src/features/settings/accounts/state/acp_account_target.dart';
import 'package:anywork/src/features/settings/accounts/view_models/acp_account_auth_view_model.dart';
import 'package:anywork/src/features/settings/accounts/views/acp_account_details_view.dart';
import 'package:anywork/src/features/settings/state/settings_action.dart';
import 'package:anywork/src/features/settings/widgets/settings_feedback.dart';
import 'package:anywork_client/acp_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../anywork_client/test/support/acp_port_fixture.dart';
import 'support/acp_settings_environment.dart';
import 'support/pump_client_future.dart';

const _busy = StudioFailure(
  code: StudioFailureCode.busy,
  message: 'An ACP authentication operation is already active',
  retryable: false,
  correlationId: 'test-acp-busy',
);

AcpAccountTarget _target(AcpAccountSettings account) => AcpAccountTarget(
  accountId: account.accountId,
  connectionRevision: account.connectionRevision,
  provider: account.provider,
);
AcpAccountAuthViewState _state(
  AcpSettingsEnvironment env,
  AcpAccountSettings account,
) => env.container
    .read(acpAccountAuthViewModelProvider(_target(account)))
    .requireValue;
AcpAccountAuthViewModel _vm(
  AcpSettingsEnvironment env,
  AcpAccountSettings account,
) => env.container.read(
  acpAccountAuthViewModelProvider(_target(account)).notifier,
);

Future<ScriptedAcpAuthFeed> _open(
  WidgetTester tester,
  AcpSettingsEnvironment env,
  AcpAccountSettings account,
) async {
  await env.mountDetails(tester, account);
  return env.authBaseline(
    tester,
    acpAuthSnapshot(
      revision: 1,
      accountId: account.accountId,
      connectionRevision: account.connectionRevision,
      state: const AcpAuthState.unchecked(),
    ),
  );
}

Future<void> _publish(
  WidgetTester tester,
  AcpSettingsEnvironment env,
  ScriptedAcpAuthFeed feed,
  AcpAccountSettings account,
  AcpAuthSnapshot snapshot,
  AcpAuthState expected,
) async {
  await pumpClientFuture(
    tester,
    feed.publishChanged(snapshot, baseRevision: 1),
    'real auth changed frame ACK',
  );
  await pumpClientUntil(
    tester,
    () => _state(env, account).auth == expected,
    'account+connection filtered auth observation',
  );
  await tester.pump();
  expect(
    tester
        .widget<AcpAccountDetailsView>(find.byType(AcpAccountDetailsView))
        .auth,
    expected,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('同账号同连接canonical在途的busy只是重复输入，实际详情不渲染失败或重发', (tester) async {
    for (final active in const <AcpAuthState>[
      AcpAuthState.checking(operationId: 'check-current'),
      AcpAuthState.authenticating(
        operationId: 'login-current',
        methodId: 'browser',
      ),
      AcpAuthState.verifying(operationId: 'verify-current'),
      AcpAuthState.cancelling(operationId: 'cancel-current'),
      AcpAuthState.closing(operationId: 'close-current', failure: null),
    ]) {
      final account = acpSettingsAccount('account-a');
      final env = await AcpSettingsEnvironment.open(
        tester,
        accounts: [account],
      );
      final feed = await _open(tester, env, account);
      final checking = _vm(env, account).check();
      final call = await pumpClientFuture(
        tester,
        env.acp.port.authStarted(0),
        'auth check reaches native before duplicate reply',
      );
      expect(
        (call.request.accountId, call.request.expectedConnectionRevision),
        ('account-a', 1),
      );
      await _publish(
        tester,
        env,
        feed,
        account,
        acpAuthSnapshot(
          revision: 2,
          accountId: account.accountId,
          connectionRevision: 1,
          state: active,
        ),
        active,
      );
      call.reject(const CommandDispatchFailure.rejected(failure: _busy));
      await pumpClientFuture(tester, checking, 'original busy reply settles');
      await tester.pump();
      expect(
        _state(env, account).checkAction!.error,
        _busy,
        reason: '原命令证据保留，不伪造成功',
      );
      expect(_state(env, account).notice, isNull);
      expect(
        find.byKey(StudioDriverKeys.acpAccountNotice(account.accountId)),
        findsNothing,
      );
      expect(
        find.byType(SettingsInlineError),
        findsNothing,
        reason: '重复输入不得绕过notice过滤又通过operation.error渲染红色失败',
      );
      expect(env.acp.port.authStarts, hasLength(1));
      expect(env.acp.port.authCancels, isEmpty);
      expect(env.acp.port.installStarts, isEmpty);
      await env.close(tester);
    }
  });

  testWidgets('连接前进、foreign账号或账号移除不吞busy，也不把旧错误带到新详情', (tester) async {
    final account = acpSettingsAccount('account-a');
    const busyOther = AcpAuthState.checking(operationId: 'another-current');
    for (final (snapshot, expected) in <(AcpAuthSnapshot, AcpAuthState)>[
      (
        acpAuthSnapshot(
          revision: 2,
          accountId: 'account-a',
          connectionRevision: 2,
          state: busyOther,
        ),
        const AcpAuthState.unchecked(),
      ),
      (
        acpAuthSnapshot(
          revision: 2,
          accountId: 'account-b',
          connectionRevision: 1,
          state: busyOther,
        ),
        const AcpAuthState.unchecked(),
      ),
      (
        const AcpAuthSnapshot(revision: 2, updatedAt: 2, accounts: []),
        const AcpAuthState.unchecked(),
      ),
    ]) {
      final env = await AcpSettingsEnvironment.open(
        tester,
        accounts: [account],
      );
      final feed = await _open(tester, env, account);
      final checking = _vm(env, account).check();
      final call = await pumpClientFuture(
        tester,
        env.acp.port.authStarted(0),
        'old identity check native request',
      );
      await _publish(tester, env, feed, account, snapshot, expected);
      call.reject(const CommandDispatchFailure.rejected(failure: _busy));
      await pumpClientFuture(
        tester,
        checking,
        'old busy is not a current duplicate',
      );
      await tester.pump();
      expect(_state(env, account).notice!.failure, _busy);
      expect(_state(env, account).visibleNotice!.connectionRevision, 1);
      expect(
        find.byKey(StudioDriverKeys.acpAccountNotice('account-a')),
        findsOneWidget,
      );
      expect(
        find.byKey(StudioDriverKeys.acpAccountNotice('account-b')),
        findsNothing,
      );
      final newAccount = snapshot.accounts.isEmpty
          ? acpSettingsAccount('account-b')
          : acpSettingsAccount(
              snapshot.accounts.single.accountId,
              revision: snapshot.accounts.single.connectionRevision,
            );
      await env.mountDetails(tester, newAccount);
      await pumpClientUntil(
        tester,
        () =>
            _state(env, newAccount).auth ==
            (snapshot.accounts.isEmpty
                ? const AcpAuthState.unchecked()
                : busyOther),
        'new details uses its own identity',
      );
      await tester.pump();
      expect(_state(env, newAccount).notice, isNull);
      expect(
        find.byKey(StudioDriverKeys.acpAccountNotice(newAccount.accountId)),
        findsNothing,
      );
      expect(env.acp.port.authStarts, hasLength(1), reason: '换详情只观察，不自动检查');
      await env.close(tester);
    }
  });

  testWidgets('没有canonical在途时busy保为真实失败；非busy typed拒绝即使在途也必须实际呈现', (
    tester,
  ) async {
    final account = acpSettingsAccount('account-a');
    final scenarios = <(AcpAuthState, StudioFailure, bool)>[
      (const AcpAuthState.unchecked(), _busy, true),
      (const AcpAuthState.cancelled(), _busy, true),
      (const AcpAuthState.required(server: null, methods: []), _busy, true),
      (const AcpAuthState.verified(checkedAt: 90, server: null), _busy, false),
      (
        const AcpAuthState.failed(
          failure: AcpAuthFailure(
            code: AcpAuthFailureCode.cleanup,
            stage: AcpAuthStage.cleanup,
            message: 'Process is still exiting',
            retryable: true,
          ),
        ),
        _busy,
        true,
      ),
      for (final code in [
        StudioFailureCode.unavailable,
        StudioFailureCode.conflict,
        StudioFailureCode.cancellationTooLate,
      ])
        (
          const AcpAuthState.checking(operationId: 'current'),
          StudioFailure(
            code: code,
            message: 'A typed native refusal',
            retryable: false,
            correlationId: 'acp-typed-refusal',
          ),
          true,
        ),
    ];
    for (final (canonical, failure, noticeVisible) in scenarios) {
      final env = await AcpSettingsEnvironment.open(
        tester,
        accounts: [account],
      );
      final feed = await _open(tester, env, account);
      final checking = _vm(env, account).check();
      final call = await pumpClientFuture(
        tester,
        env.acp.port.authStarted(0),
        'explicit check native call',
      );
      await _publish(
        tester,
        env,
        feed,
        account,
        acpAuthSnapshot(
          revision: 2,
          accountId: account.accountId,
          connectionRevision: 1,
          state: canonical,
        ),
        canonical,
      );
      call.reject(CommandDispatchFailure.rejected(failure: failure));
      await pumpClientFuture(
        tester,
        checking,
        'typed refusal retained by real VM',
      );
      await tester.pump();
      expect(
        _state(env, account).checkAction!.outcome,
        SettingsActionOutcome.rejected,
      );
      expect(_state(env, account).notice!.failure, failure);
      expect(
        find.byKey(StudioDriverKeys.acpAccountNotice(account.accountId)),
        noticeVisible ? findsOneWidget : findsNothing,
      );
      expect(
        find.byType(SettingsInlineError),
        findsWidgets,
        reason: '不是当前重复输入的失败必须由实际详情呈现；Verified仅过滤认证notice而不抹命令证据',
      );
      expect(env.acp.port.authStarts, hasLength(1));
      expect(tester.takeException(), isNull);
      await env.close(tester);
    }
  });

  testWidgets('普通native异常成为Unknown而不是重复busy，原失败可见且不重发认证', (tester) async {
    final account = acpSettingsAccount('account-a');
    for (final (error, canonical) in <(Object, AcpAuthState)>[
      (StateError('transport closed'), const AcpAuthState.unchecked()),
      (_busy, const AcpAuthState.checking(operationId: 'unconfirmed-current')),
    ]) {
      final env = await AcpSettingsEnvironment.open(
        tester,
        accounts: [account],
      );
      final feed = await _open(tester, env, account);
      final checking = _vm(env, account).check();
      final call = await pumpClientFuture(
        tester,
        env.acp.port.authStarted(0),
        'plain exception check reached native',
      );
      await _publish(
        tester,
        env,
        feed,
        account,
        acpAuthSnapshot(
          revision: 2,
          accountId: account.accountId,
          connectionRevision: 1,
          state: canonical,
        ),
        canonical,
      );
      env.expectedUnresolvedAuthOperations.add(call.request.operationId);
      // 这不是Rejected证据：普通Busy错误也不能伪装成已确认的重复输入。
      call.reply.completeError(error);
      await pumpClientFuture(tester, checking, 'Unknown auth outcome');
      await tester.pump();
      expect(
        _state(env, account).checkAction!.outcome,
        SettingsActionOutcome.unknownOutcome,
      );
      expect(_state(env, account).notice, isNotNull);
      expect(
        find.byKey(StudioDriverKeys.acpAccountNotice(account.accountId)),
        findsOneWidget,
      );
      expect(env.acp.port.authStarts, hasLength(1));
      expect(_state(env, account).checkAction!.operation!.receipt, isNull);
      await env.close(tester);
    }
  });
}
