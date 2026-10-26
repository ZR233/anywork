import 'package:anywork/src/app/app_bindings.dart';
import 'package:anywork/src/features/settings/accounts/view_models/account_editor_view_model.dart';
import 'package:anywork/src/features/settings/accounts/view_models/accounts_view_model.dart';
import 'package:anywork_client/acp_ports.dart';
import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../anywork_client/test/support/acp_port_fixture.dart';
import 'support/settings_accounts_fixture.dart';
import 'support/settings_usage_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Repository-owned account usage demand', () {
    test(
      'visible first pass requests every identity concurrently once',
      () async {
        final fixture = await settingsUsageFixture({'a': 1, 'b': 1});
        fixture.usage.setVisibleAccounts({'a', 'b'});
        await fixture.usagePort.called(1);
        expect(fixture.usage.checks.value.keys, ['a', 'b']);
        expect(fixture.usagePort.calls.map((call) => call.accountId), [
          'a',
          'b',
        ]);
        final tickets = [
          for (final check in fixture.usage.checks.value.values) check.ticket,
        ];
        fixture.usage.setVisibleAccounts({'a', 'b'});
        expect([
          for (final check in fixture.usage.checks.value.values) check.ticket,
        ], tickets);
        expect(fixture.usagePort.calls.map((call) => call.accountId), [
          'a',
          'b',
        ]);
      },
    );

    test(
      'hidden identity changes wait until visible and only refresh self',
      () async {
        final fixture = await settingsUsageFixture({'a': 1, 'b': 1});
        fixture.usage.setVisibleAccounts({'a', 'b'});
        await fixture.usagePort.called(1);
        expect(fixture.usagePort.calls.map((call) => call.accountId), [
          'a',
          'b',
        ]);
        await rejectSettingsUsageChecks(fixture);
        fixture.usage.setVisibleAccounts({});
        await fixture.configurationChanged({'a': 2, 'b': 1});
        expect(fixture.usagePort.calls.map((call) => call.accountId), [
          'a',
          'b',
        ]);
        fixture.usage.setVisibleAccounts({'a', 'b'});
        final changed = await fixture.usagePort.called(2);
        expect(
          (changed.accountId, changed.expectedUsageQueryRevision),
          ('a', 2),
        );
        expect(fixture.usagePort.calls.map((call) => call.accountId), [
          'a',
          'b',
          'a',
        ]);

        // Also retain the old added-account case. The existing native fixture
        // intentionally has only two stable entity IDs, so a second environment
        // makes b newly added while the first one above proves b is unchanged.
        final added = await settingsUsageFixture({'a': 1});
        added.usage.setVisibleAccounts({'a'});
        await added.usagePort.called(0);
        await rejectSettingsUsageChecks(added);
        added.usage.setVisibleAccounts({});
        await added.configurationChanged({'a': 2, 'b': 1});
        expect(added.usagePort.calls.map((call) => call.accountId), ['a']);
        added.usage.setVisibleAccounts({'a', 'b'});
        await added.usagePort.called(2);
        expect(
          added.usagePort.calls.map(
            (call) => (call.accountId, call.expectedUsageQueryRevision),
          ),
          [('a', 1), ('a', 2), ('b', 1)],
        );
      },
    );

    test('failed identity is not retried by visibility rebuilds, only a new revision or explicit retry', () async {
      final fixture = await settingsUsageFixture({'a': 3});
      fixture.usage.setVisibleAccounts({'a'});
      await fixture.usagePort.called(0);
      expect(fixture.usagePort.calls.map((call) => call.accountId), ['a']);
      await rejectSettingsUsageChecks(fixture);
      final failed = fixture.usage.checks.value['a']!.ticket;
      expect(failed.state.value.error, settingsUsageFailure);
      fixture.usage.setVisibleAccounts({});
      fixture.usage.setVisibleAccounts({'a'});
      expect(fixture.usagePort.calls, hasLength(1));
      expect(fixture.usage.checks.value['a']!.ticket, same(failed));
      final retry = fixture.usage.check('a');
      await fixture.usagePort.called(1);
      expect(retry.id, isNot(failed.id));
      expect(fixture.usagePort.calls.map((call) => call.accountId), ['a', 'a']);
    });

    test('deleted accounts drop attempted identity', () async {
      final fixture = await settingsUsageFixture({'a': 1, 'b': 1});
      fixture.usage.setVisibleAccounts({'a', 'b'});
      await fixture.usagePort.called(1);
      expect(fixture.usagePort.calls.map((call) => call.accountId), ['a', 'b']);
      final removedTicket = fixture.usage.checks.value['b']!.ticket;
      await rejectSettingsUsageChecks(fixture);
      fixture.usage.setVisibleAccounts({'a'});
      await fixture.configurationChanged({'a': 1});
      expect(fixture.usagePort.calls, hasLength(2));
      expect(fixture.usage.checks.value.containsKey('b'), isFalse);
      fixture.usage.setVisibleAccounts({});
      await fixture.configurationChanged({'a': 1, 'b': 1});
      fixture.usage.setVisibleAccounts({'a', 'b'});
      expect(
        fixture.usage.checks.value['b']?.ticket.id,
        isNot(removedTicket.id),
        reason:
            'Recreated membership must not reuse the deleted account attempt',
      );
      await fixture.usagePort.called(2);
      expect(fixture.usagePort.calls.map((call) => call.accountId), [
        'a',
        'b',
        'b',
      ]);
    });
  });

  test(
    'old account save settlement cannot lock or unlock a newer add draft',
    () async {
      final fixture = SettingsAccountsFixture();
      // 本用例不涉及 ACP 目录：显式声明真实空目录并委托 base 的原生账号实体，
      // 声明早于任何 Settings 读取（读取不会回退成伪空目录）。
      fixture.configurationPort.declareAcpMaterial(
        revision: 1,
        rows: const [],
        delegateBase: true,
      );
      await fixture.establish();
      // 生产组合根总会装配 ACP owner（app_bindings 的 provider 未注入即抛错），本用例
      // 消费同一个 AccountsViewModel，因此同样注入真实 AcpAuthRepository：只脚本化
      // native 端口，不伪造 ACP 成功、不靠 VM 隐藏依赖绕过注入。
      final acp = AcpPortFixture();
      final container = ProviderContainer(
        overrides: [
          configurationRepositoryProvider.overrideWithValue(
            fixture.configuration,
          ),
          modelsRepositoryProvider.overrideWithValue(fixture.models),
          accountUsageRepositoryProvider.overrideWithValue(fixture.usage),
          acpAuthRepositoryProvider.overrideWithValue(acp.auth),
        ],
      );
      addTearDown(() async {
        container.dispose();
        expect((await fixture.close()).unresolved, isEmpty);
        expect(fixture.budget.usage, isEmpty);
        // 注入的 ACP owner 也必须真实关闭，且自己的 budget 归零。
        final reports = await Future.wait([
          acp.auth.close(),
          acp.install.close(),
        ]);
        expect(reports.expand((report) => report.unresolved), isEmpty);
        expect(acp.budget.usage, isEmpty);
      });
      final list = container.read(accountsViewModelProvider.notifier);
      // 装配 ACP owner 后 build 会真实 await 一次 ACP 模板目录读取：等它发出后给出
      // 脚本化原生端口的真实答案（后端没有模板），不是伪造成功。
      final accountsReady = container.read(accountsViewModelProvider.future);
      for (var turn = 0; turn < 100 && acp.port.catalogReads.isEmpty; turn++) {
        await pumpEventQueue();
      }
      acp.port.answerCatalogRead(0, AcpAccountCatalog.empty);
      await accountsReady;
      final choice = AccountTemplateChoice.native(
        container
            .read(accountsViewModelProvider)
            .requireValue
            .templates!
            .templates
            .first,
      );
      list.setVisible(false);
      await list.startCreate(choice);
      final firstKey = container
          .read(accountsViewModelProvider)
          .requireValue
          .editor!;
      final firstProvider = accountEditorViewModelProvider(firstKey);
      await container.read(firstProvider.future);
      final firstVm = container.read(firstProvider.notifier);
      final firstSave = firstVm.save();
      final first = await fixture.configurationPort.saved(0);
      expect(container.read(firstProvider).requireValue.saving, isTrue);
      firstVm.endEditing();
      list.closeEditor(firstKey);
      await list.startCreate(choice);
      final secondKey = container
          .read(accountsViewModelProvider)
          .requireValue
          .editor!;
      final secondProvider = accountEditorViewModelProvider(secondKey);
      await container.read(secondProvider.future);
      expect(container.read(secondProvider).requireValue.saving, isFalse);
      expect(secondKey, isNot(firstKey));
      final secondSave = container.read(secondProvider.notifier).save();
      first.beginReply.completeError(
        const CommandDispatchFailure.rejected(failure: settingsUsageFailure),
      );
      expect(await firstSave, isFalse);
      final second = await fixture.configurationPort.saved(1);
      expect(container.read(secondProvider).requireValue.saving, isTrue);
      expect(
        container.read(accountsViewModelProvider).requireValue.editor,
        secondKey,
      );
      // A stale completion cannot end the new list-owned editor either.
      list.closeEditor(firstKey, saved: true);
      expect(container.read(secondProvider).requireValue.saving, isTrue);
      expect(
        container.read(accountsViewModelProvider).requireValue.editor,
        secondKey,
      );
      second.beginReply.completeError(
        const CommandDispatchFailure.rejected(failure: settingsUsageFailure),
      );
      expect(await secondSave, isFalse);
      expect(container.read(secondProvider).requireValue.saving, isFalse);
      expect(
        container.read(secondProvider).requireValue.saveAction!.error,
        settingsUsageFailure,
      );
    },
  );
}
