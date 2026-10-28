import 'package:anywork/src/diagnostics/studio_driver_keys.dart';
import 'package:anywork/src/features/settings/accounts/state/acp_command_notice.dart';
import 'package:anywork/src/features/settings/accounts/view_models/accounts_view_model.dart';
import 'package:anywork/src/features/settings/accounts/widgets/acp_account_list_row.dart';
import 'package:anywork/src/features/settings/state/settings_action.dart';
import 'package:anywork_client/acp_ports.dart';
import 'package:anywork_client/configuration_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/acp_settings_environment.dart';
import 'support/pump_client_future.dart';

const _permission = StudioFailure(
  code: StudioFailureCode.permissionDenied,
  message: 'backend safe removal detail',
  retryable: false,
  correlationId: 'fixture-remove',
);

AcpAuthSnapshot _auth(int revision, AcpAuthState a, AcpAuthState b) =>
    AcpAuthSnapshot(
      revision: revision,
      updatedAt: revision,
      accounts: [
        AcpAuthAccount(accountId: 'a', connectionRevision: 1, state: a),
        AcpAuthAccount(accountId: 'b', connectionRevision: 1, state: b),
      ],
    );

Finder _row(String id) => find.byWidgetPredicate(
  (widget) =>
      widget is AcpAccountListRow && widget.entry.account.accountId == id,
);

void _notice(WidgetTester tester, String id, String summary) {
  final row = _row(id);
  expect(row, findsOneWidget);
  expect(
    find.descendant(
      of: row,
      matching: find.byKey(StudioDriverKeys.acpAccountNotice(id)),
    ),
    findsOneWidget,
  );
  expect(
    find.descendant(of: row, matching: find.text(summary)),
    findsOneWidget,
  );
}

Future<void> _waitAuth(
  WidgetTester tester,
  AcpSettingsEnvironment env,
  AcpAuthState a,
  AcpAuthState b,
) async {
  await pumpClientUntil(tester, () {
    final rows = env.container
        .read(accountsViewModelProvider)
        .value
        ?.directory
        ?.acpEntries;
    if (rows == null) return false;
    return rows
                .where((row) => row.account.accountId == 'a')
                .firstOrNull
                ?.auth ==
            a &&
        rows.where((row) => row.account.accountId == 'b').firstOrNull?.auth ==
            b;
  }, 'actual account list observes both auth identities');
  await tester.pump();
  expect(tester.widget<AcpAccountListRow>(_row('a')).entry.auth, a);
  expect(tester.widget<AcpAccountListRow>(_row('b')).entry.auth, b);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('typed删除失败回到真实调用VM且只渲染目标行；Verified/后续认证不抹除，连接换代才过时', (
    tester,
  ) async {
    final env = await AcpSettingsEnvironment.open(
      tester,
      accounts: [acpSettingsAccount('a'), acpSettingsAccount('b')],
    );
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    final verified = const AcpAuthState.verified(checkedAt: 90, server: null);
    final feed = await env.mountAccounts(tester, _auth(1, verified, verified));
    await _waitAuth(tester, env, verified, verified);
    final vm = env.container.read(accountsViewModelProvider.notifier);
    final removal = vm.removeAcp('b');
    final call = await pumpClientFuture(
      tester,
      env.settings.configurationPort.acpRemoved(0),
      'remove b reaches original managed native call',
    );
    expect(call.request.accountId, 'b');
    call.native.reject(
      const CommandDispatchFailure.rejected(failure: _permission),
    );
    await pumpClientFuture(
      tester,
      removal,
      'typed removal refusal reaches original VM',
    );
    await tester.pump();
    final state = env.container.read(accountsViewModelProvider).requireValue;
    expect(state.acpRemovals['b']!.outcome, SettingsActionOutcome.rejected);
    expect(state.acpRemovals['b']!.error, _permission);
    expect(
      state.acpRemovals['b']!.operation!.failurePhase,
      OperationFailurePhase.rejected,
    );
    expect(state.acpNotices['b']!.kind, AcpCommandNoticeKind.remove);
    expect(
      state.acpNotices['b']!.failure!.code,
      StudioFailureCode.permissionDenied,
    );
    expect(state.acpNotices['b']!.connectionRevision, 1);
    _notice(tester, 'b', 'The request was not accepted. Permission denied');
    expect(
      find.descendant(
        of: _row('a'),
        matching: find.byKey(StudioDriverKeys.acpAccountNotice('b')),
      ),
      findsNothing,
    );
    expect(find.byKey(StudioDriverKeys.acpAccountNotice('a')), findsNothing);
    expect(
      find.textContaining(_permission.message),
      findsNothing,
      reason: '列表不展开后端技术详情',
    );
    await pumpClientFuture(
      tester,
      feed.publishChanged(
        _auth(
          2,
          verified,
          const AcpAuthState.checking(operationId: 'b-recheck'),
        ),
        baseRevision: 1,
      ),
      'later auth progress ACK',
    );
    await _waitAuth(
      tester,
      env,
      verified,
      const AcpAuthState.checking(operationId: 'b-recheck'),
    );
    _notice(tester, 'b', 'The request was not accepted. Permission denied');
    await pumpClientFuture(
      tester,
      feed.publishChanged(_auth(3, verified, verified), baseRevision: 2),
      'later Verified ACK',
    );
    await _waitAuth(tester, env, verified, verified);
    _notice(tester, 'b', 'The request was not accepted. Permission denied');

    env.settings.configurationPort.declareAcpMaterial(
      revision: 2,
      delegateBase: true,
      rows: [
        const AcpAccountConfigurationRead(
          accountId: ReadText.inline(text: 'a'),
          name: ReadText.inline(text: 'A'),
          provider: AcpProvider.antigravity,
          connectionRevision: 1,
        ),
        const AcpAccountConfigurationRead(
          accountId: ReadText.inline(text: 'b'),
          name: ReadText.inline(text: 'B'),
          provider: AcpProvider.antigravity,
          connectionRevision: 2,
        ),
      ],
    );
    await pumpClientFuture(
      tester,
      env.settings.configurationPort.base.publishSettings(2),
      'new configuration watermark ACK',
    );
    final refresh = vm.refreshAcpAccounts('b');
    final page = await pumpClientFuture(
      tester,
      env.settings.configurationPort.acpPage(1),
      'new connection directory real page',
    );
    page.complete();
    final account = await pumpClientFuture(
      tester,
      refresh,
      'current connection identity re-read',
    );
    expect(account!.connectionRevision, 2);
    await tester.pump();
    expect(find.byKey(StudioDriverKeys.acpAccountNotice('b')), findsNothing);
    expect(
      env.container
          .read(accountsViewModelProvider)
          .requireValue
          .acpNotices['b']!
          .failure,
      _permission,
      reason: '旧失败不是被假清掉；呈现按真实新连接身份过滤',
    );
    expect(env.settings.configurationPort.acpRemovals, hasLength(1));
    expect(env.acp.port.authStarts, isEmpty);
    expect(env.acp.port.authCancels, isEmpty);
    expect(env.acp.port.installCancels, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('认证notice才被新认证进展取代；配置notice保留，错误账号身份不会串行呈现', (tester) async {
    final env = await AcpSettingsEnvironment.open(
      tester,
      accounts: [acpSettingsAccount('a'), acpSettingsAccount('b')],
    );
    final verified = const AcpAuthState.verified(checkedAt: 90, server: null);
    final feed = await env.mountAccounts(
      tester,
      _auth(1, const AcpAuthState.checking(operationId: 'auth-old'), verified),
    );
    await _waitAuth(
      tester,
      env,
      const AcpAuthState.checking(operationId: 'auth-old'),
      verified,
    );
    final vm = env.container.read(accountsViewModelProvider.notifier);
    const unavailable = StudioFailure(
      code: StudioFailureCode.unavailable,
      message: 'safe authentication technical detail',
      retryable: true,
      correlationId: 'auth-notice',
    );
    const auth = AcpCommandNotice(
      kind: AcpCommandNoticeKind.authentication,
      accountId: 'a',
      connectionRevision: 1,
      operationId: 'auth-old',
      failure: unavailable,
    );
    const configuration = AcpCommandNotice(
      kind: AcpCommandNoticeKind.configuration,
      accountId: 'b',
      connectionRevision: 1,
      failure: _permission,
    );
    vm.setAcpNotice('a', auth);
    vm.setAcpNotice('b', configuration);
    await tester.pump();
    _notice(tester, 'a', 'The request was not accepted. Unavailable');
    _notice(tester, 'b', 'The request was not accepted. Permission denied');
    expect(find.textContaining(unavailable.message), findsNothing);
    expect(find.textContaining(_permission.message), findsNothing);
    await pumpClientFuture(
      tester,
      feed.publishChanged(
        _auth(
          2,
          const AcpAuthState.required(server: null, methods: []),
          verified,
        ),
        baseRevision: 1,
      ),
      'new auth attempt replaces old operation',
    );
    await _waitAuth(
      tester,
      env,
      const AcpAuthState.required(server: null, methods: []),
      verified,
    );
    expect(find.byKey(StudioDriverKeys.acpAccountNotice('a')), findsNothing);
    _notice(tester, 'b', 'The request was not accepted. Permission denied');
    vm.setAcpNotice(
      'a',
      const AcpCommandNotice(
        kind: AcpCommandNoticeKind.authentication,
        accountId: 'a',
        connectionRevision: 1,
        failure: unavailable,
      ),
    );
    await tester.pump();
    _notice(tester, 'a', 'The request was not accepted. Unavailable');
    await pumpClientFuture(
      tester,
      feed.publishChanged(_auth(3, verified, verified), baseRevision: 2),
      'Verified supersedes authentication-only notice',
    );
    await _waitAuth(tester, env, verified, verified);
    expect(find.byKey(StudioDriverKeys.acpAccountNotice('a')), findsNothing);
    _notice(tester, 'b', 'The request was not accepted. Permission denied');
    vm.setAcpNotice('a', configuration);
    await tester.pump();
    expect(
      find.byKey(StudioDriverKeys.acpAccountNotice('a')),
      findsNothing,
      reason: '即使错误放在a的呈现槽里，b身份的notice也不能显示到a',
    );
    _notice(tester, 'b', 'The request was not accepted. Permission denied');
    expect(env.acp.port.authStarts, isEmpty);
    expect(env.settings.configurationPort.acpRemovals, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
