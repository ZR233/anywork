import 'package:anywork/src/app/app_bindings.dart';
import 'package:anywork/src/features/settings/accounts/view_models/account_editor_view_model.dart';
import 'package:anywork/src/features/settings/accounts/view_models/accounts_view_model.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/settings_accounts_fixture.dart';
import 'support/settings_usage_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Repository-owned account usage demand', () {
    test('visible first pass requests every identity concurrently once', () async {
      final fixture = await settingsUsageFixture({'a': 1, 'b': 1});
      fixture.usage.setVisibleAccounts({'a', 'b'});
      await fixture.usagePort.called(1);
      expect(fixture.usage.checks.value.keys, ['a', 'b']);
      expect(fixture.usagePort.calls.map((call) => call.accountId), ['a', 'b']);
      final tickets = [for (final check in fixture.usage.checks.value.values) check.ticket];
      fixture.usage.setVisibleAccounts({'a', 'b'});
      expect([for (final check in fixture.usage.checks.value.values) check.ticket], tickets);
      expect(fixture.usagePort.calls.map((call) => call.accountId), ['a', 'b']);
    });

    test('hidden identity changes wait until visible and only refresh self', () async {
      final fixture = await settingsUsageFixture({'a': 1, 'b': 1});
      fixture.usage.setVisibleAccounts({'a', 'b'});
      await fixture.usagePort.called(1);
      expect(fixture.usagePort.calls.map((call) => call.accountId), ['a', 'b']);
      await rejectSettingsUsageChecks(fixture);
      fixture.usage.setVisibleAccounts({});
      await fixture.configurationChanged({'a': 2, 'b': 1});
      expect(fixture.usagePort.calls.map((call) => call.accountId), ['a', 'b']);
      fixture.usage.setVisibleAccounts({'a', 'b'});
      final changed = await fixture.usagePort.called(2);
      expect((changed.accountId, changed.expectedUsageQueryRevision), ('a', 2));
      expect(fixture.usagePort.calls.map((call) => call.accountId), ['a', 'b', 'a']);

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
      expect(added.usagePort.calls.map((call) => (call.accountId, call.expectedUsageQueryRevision)),
        [('a', 1), ('a', 2), ('b', 1)]);
    });

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
      expect(fixture.usage.checks.value['b']?.ticket.id, isNot(removedTicket.id),
        reason: 'Recreated membership must not reuse the deleted account attempt');
      await fixture.usagePort.called(2);
      expect(fixture.usagePort.calls.map((call) => call.accountId), ['a', 'b', 'b']);
    });
  });

  test('old account save settlement cannot lock or unlock a newer add draft', () async {
    final fixture = SettingsAccountsFixture();
    await fixture.establish();
    final container = ProviderContainer(overrides: [
      configurationRepositoryProvider.overrideWithValue(fixture.configuration),
      modelsRepositoryProvider.overrideWithValue(fixture.models),
      accountUsageRepositoryProvider.overrideWithValue(fixture.usage),
    ]);
    addTearDown(() async {
      container.dispose();
      expect((await fixture.close()).unresolved, isEmpty);
      expect(fixture.budget.usage, isEmpty);
    });
    final list = container.read(accountsViewModelProvider.notifier);
    await container.read(accountsViewModelProvider.future);
    list.setVisible(false);
    await list.startCreate();
    final firstKey = container.read(accountsViewModelProvider).requireValue.editor!;
    final firstProvider = accountEditorViewModelProvider(firstKey);
    await container.read(firstProvider.future);
    final firstVm = container.read(firstProvider.notifier);
    final firstSave = firstVm.save();
    final first = await fixture.configurationPort.saved(0);
    expect(container.read(firstProvider).requireValue.saving, isTrue);
    firstVm.endEditing();
    list.closeEditor(firstKey);
    await list.startCreate();
    final secondKey = container.read(accountsViewModelProvider).requireValue.editor!;
    final secondProvider = accountEditorViewModelProvider(secondKey);
    await container.read(secondProvider.future);
    expect(container.read(secondProvider).requireValue.saving, isFalse);
    expect(secondKey, isNot(firstKey));
    final secondSave = container.read(secondProvider.notifier).save();
    first.beginReply.completeError(const CommandDispatchFailure.rejected(failure: settingsUsageFailure));
    expect(await firstSave, isFalse);
    final second = await fixture.configurationPort.saved(1);
    expect(container.read(secondProvider).requireValue.saving, isTrue);
    expect(container.read(accountsViewModelProvider).requireValue.editor, secondKey);
    // A stale completion cannot end the new list-owned editor either.
    list.closeEditor(firstKey, saved: true);
    expect(container.read(secondProvider).requireValue.saving, isTrue);
    expect(container.read(accountsViewModelProvider).requireValue.editor, secondKey);
    second.beginReply.completeError(const CommandDispatchFailure.rejected(failure: settingsUsageFailure));
    expect(await secondSave, isFalse);
    expect(container.read(secondProvider).requireValue.saving, isFalse);
    expect(container.read(secondProvider).requireValue.saveAction!.error, settingsUsageFailure);
  });
}
