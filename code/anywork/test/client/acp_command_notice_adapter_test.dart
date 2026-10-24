import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/settings/settings_account_list.dart';
import 'package:anywork/src/features/settings/settings_acp_account_details.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 命令失败通知的目标账号绑定与取代规则（真实 Client 模型 + 真实列表行 widget）。
///
/// 说明：完整 `AccountsTab` 需要整套设置页壳层/provider 装配（settings shell + 权限
/// scope），本文件用同一份生产规则函数 [visibleAcpCommandNotice] 与生产行 widget 做
/// 定向回归；tab 只把 `_acpNotices[entry.id]` 委托给该函数，不再重复规则。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AcpAccountEntryView entry(String id, {int connectionRevision = 1}) =>
      AccountDirectoryView.from(
        acpAccounts: [
          AcpAccountSettingsView(
            accountId: id,
            name: id.toUpperCase(),
            provider: AcpProviderView.antigravity,
            connectionRevision: connectionRevision,
          ),
        ],
        auth: AcpAuthSnapshotView(
          revision: 1,
          updatedAt: 1,
          accounts: [
            AcpAuthAccountView(
              accountId: id,
              connectionRevision: connectionRevision,
              state: const AcpVerifiedState(
                checkedAt: 90,
                server: AcpServerInfoView(
                  name: 'antigravity',
                  version: '1.2.3',
                ),
              ),
            ),
          ],
        ),
      ).acpEntries.single;

  AcpCommandNotice notice(
    String accountId, {
    required AcpCommandNoticeKind kind,
    int connectionRevision = 1,
    String? operationId,
  }) => AcpCommandNotice(
    kind: kind,
    summary: 'summary-$accountId',
    detail: 'safe backend detail',
    accountId: accountId,
    connectionRevision: connectionRevision,
    operationId: operationId,
  );

  test(
    'a removal failure stays on its account even when that account is Verified',
    () {
      final a = entry('a');
      final b = entry('b');
      final removeNotice = notice('b', kind: AcpCommandNoticeKind.remove);

      // 目标账号：即使已 Verified 也必须继续显示（配置类不被认证成功掩盖）。
      expect(visibleAcpCommandNotice(removeNotice, b), same(removeNotice));
      // 另一个账号绝不显示它。
      expect(visibleAcpCommandNotice(removeNotice, a), isNull);

      // 身份失效（新 connectionRevision）才是它过时的条件。
      expect(
        visibleAcpCommandNotice(
          removeNotice,
          entry('b', connectionRevision: 2),
        ),
        isNull,
      );
    },
  );

  test('only authentication notices are superseded by later auth progress', () {
    final required = AccountDirectoryView.from(
      acpAccounts: [
        const AcpAccountSettingsView(
          accountId: 'a',
          name: 'A',
          provider: AcpProviderView.antigravity,
          connectionRevision: 1,
        ),
      ],
      auth: const AcpAuthSnapshotView(
        revision: 2,
        updatedAt: 2,
        accounts: [
          AcpAuthAccountView(
            accountId: 'a',
            connectionRevision: 1,
            state: AcpRequiredState(server: null),
          ),
        ],
      ),
    ).acpEntries.single;
    final authNotice = notice(
      'a',
      kind: AcpCommandNoticeKind.authentication,
      operationId: 'op-old',
    );
    // 在途操作已被取代：旧的认证拒绝不再呈现。
    expect(visibleAcpCommandNotice(authNotice, required), isNull);
    // 没有绑定在途操作的认证拒绝，在该账号进入正轨后也不再呈现。
    final verified = entry('a');
    expect(
      visibleAcpCommandNotice(
        notice('a', kind: AcpCommandNoticeKind.authentication),
        verified,
      ),
      isNull,
    );
    // 但同样的规则下配置类仍然保留。
    expect(
      visibleAcpCommandNotice(
        notice('a', kind: AcpCommandNoticeKind.configuration),
        verified,
      ),
      isNotNull,
    );
  });

  testWidgets('the list row renders only its own notice', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final a = entry('a');
    final b = entry('b');
    final removeNotice = notice('b', kind: AcpCommandNoticeKind.remove);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: pureStudioTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: AccountList(
            accounts: const [],
            acpEntries: [a, b],
            acpNotices: {b.id: removeNotice},
            selectedAcpAccountId: null,
            onSelectAcp: (_) {},
            onEditAcp: (_) {},
            onRemoveAcp: (_) {},
            defaultAccountId: null,
            filtering: false,
            usageByAccount: const {},
            loadingAccountIds: const {},
            usageErrorsByAccountId: const {},
            onQueryChanged: (_) {},
            onAdd: () {},
            onSelect: (_) {},
            onSetDefault: (_) async {},
            onRefreshAll: ({String? accountId}) async {},
            onRefreshProvider: (_) {},
            onEdit: (_) {},
            onDelete: null,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(StudioDriverKeys.acpAccountNotice('b')), findsOneWidget);
    expect(find.byKey(StudioDriverKeys.acpAccountNotice('a')), findsNothing);
    expect(find.text('summary-b'), findsOneWidget);
    expect(find.text('safe backend detail'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'removal failure reaches the command caller as a typed failure',
    () async {
      final transport = _RemoveFailingTransport();
      final client = AnyworkClient(transport: transport, clientId: 'notice');
      addTearDown(
        () => client.close(
          deadline: DateTime.now().add(const Duration(seconds: 3)),
        ),
      );
      client.settings.merge(
        SettingsStateSnapshot(
          revision: 1,
          acpAccounts: [
            const AcpAccountSettingsView(
              accountId: 'b',
              name: 'B',
              provider: AcpProviderView.antigravity,
              connectionRevision: 1,
            ),
          ],
        ),
      );
      await expectLater(
        client.acpCommands.removeAccount('b'),
        throwsA(
          isA<StudioFailure>().having(
            (failure) => failure.code,
            'code',
            StudioFailureCode.permissionDenied,
          ),
        ),
      );
      expect(transport.removeCalls, 1);
    },
  );
}

final class _RemoveFailingTransport implements StudioTransport {
  int removeCalls = 0;

  @override
  Future<SettingsCommandReply> removeAcpAccount(
    int expectedSettingsRevision,
    String accountId, {
    required OperationId operationId,
  }) async {
    removeCalls += 1;
    throw const StudioFailure(
      code: StudioFailureCode.permissionDenied,
      message: 'backend safe message',
      retryable: false,
      correlationId: 'fixture-remove',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unused transport: ${invocation.memberName}');
}
