import 'package:anywork/src/app/app_bindings.dart';
import 'package:anywork/src/features/settings/agents/state/profile_editor_state.dart';
import 'package:anywork/src/features/settings/agents/view_models/agent_profile_editor_view_model.dart';
import 'package:anywork/src/features/settings/state/editor_keys.dart';
import 'package:anywork_client/configuration_ports.dart';
import 'package:anywork_client/models_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../anywork_client/test/support/profile_configuration_port.dart';
import '../../../anywork_client/test/support/profile_editor_fixture.dart';

const _rejected = StudioFailure(code: StudioFailureCode.invalidArgument,
  message: 'The native validator rejected this exact raw route.', retryable: false,
  correlationId: 'profile-save-rejected');

final class _Editor {
  _Editor(this.fixture, this.key)
    : container = ProviderContainer(overrides: [
        configurationRepositoryProvider.overrideWithValue(fixture.configuration),
        modelsRepositoryProvider.overrideWithValue(fixture.models),
      ]) {
    fixtures.add(fixture);
    subscription = container.listen(provider, (_, next) {
      if (next.asData?.value case final value?) publications.add(value);
    }, fireImmediately: true);
  }
  final ProfileEditorFixture fixture;
  final ProfileEditorKey key;
  final ProviderContainer container;
  final fixtures = <ProfileEditorFixture>[];
  final publications = <ProfileEditorViewState>[];
  late final ProviderSubscription<AsyncValue<ProfileEditorViewState>> subscription;
  bool disposed = false;

  late final provider = agentProfileEditorViewModelProvider(key);
  ProfileEditorViewState get state => container.read(provider).requireValue;
  AgentProfileEditorViewModel get vm => container.read(provider.notifier);

  Future<void> rebind(ProfileEditorFixture replacement) async {
    fixtures.add(replacement);
    container.updateOverrides([
      configurationRepositoryProvider.overrideWithValue(replacement.configuration),
      modelsRepositoryProvider.overrideWithValue(replacement.models),
    ]);
    await container.read(provider.future);
  }

  void disposeEditor() {
    if (disposed) return;
    disposed = true;
    subscription.close();
    container.dispose();
  }

  Future<void> close() async {
    disposeEditor();
    // Release environment barriers even after a failed assertion; no native
    // reply or shared Repository is abandoned by the test harness itself.
    for (final fixture in fixtures) {
      for (final call in fixture.modelPort.firstCalls) {
        if (!call.reply.isCompleted) call.reply.complete(null);
      }
      for (final call in fixture.modelPort.effortCalls) {
        if (!call.reply.isCompleted) call.reply.complete(null);
      }
      for (final call in fixture.configurationPort.saves) {
        if (!call.reply.isCompleted) call.reply.completeError(const CommandDispatchFailure.rejected(failure: _rejected));
      }
      final report = await fixture.close(deadline: DateTime.now().add(const Duration(seconds: 3)));
      expect(report.unresolved, isEmpty, reason: 'Real Repository owners must join all admitted work');
      expect(fixture.budget.usage, isEmpty);
    }
  }
}

Future<_Editor> _editor({AgentProfileSnapshot? profile, int accountCount = 2,
  Set<String>? textEligibleAccounts}) async {
  final fixture = ProfileEditorFixture(profile: profile, accountCount: accountCount,
    textEligibleAccounts: textEligibleAccounts);
  final editor = _Editor(fixture, ProfileEditorKey(editorId: 1, profileId: profile?.profileId));
  addTearDown(editor.close);
  // Start build before publishing the environment's baselines, retaining the
  // real synchronous observation registration and async loading behavior.
  final building = editor.container.read(editor.provider.future);
  await fixture.establish();
  await building;
  return editor;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('explicit initial suggestion uses native first beyond page 32 and preserves text edited while waiting', () async {
    final editor = await _editor(accountCount: 33, textEligibleAccounts: {'account-32'});
    final port = editor.fixture.modelPort;
    expect(editor.state.models, hasLength(32));
    expect(editor.state.models.any((account) => account.accountId == 'account-32'), isFalse);
    expect(port.firstCalls, isEmpty, reason: 'build must not supply a default route');
    expect(port.effortCalls, isEmpty);
    final suggesting = editor.vm.suggestInitialRoute();
    final call = await port.firstCalled(0);
    expect(call.catalog, ModelCatalogReadTarget(origin: editor.fixture.origin,
      reference: const ModelCatalogReadRef(entry: 1, revision: 1)));
    editor.vm.setDescription('  raw description during native query  ');
    final revision = editor.state.revision;
    expect(await editor.vm.save(), isFalse, reason: 'A pending suggestion is not a save-time default');
    expect(editor.fixture.configurationPort.saves, isEmpty);
    call.reply.complete(const ModelSelection(
      model: AccountModelKey(accountId: 'account-32', modelId: 'text'), effort: 'high'));
    await suggesting;
    expect((editor.state.accountId, editor.state.modelId, editor.state.effort), ('account-32', 'text', 'high'));
    expect(editor.state.description, '  raw description during native query  ');
    expect(editor.state.dirty, isTrue);
    expect(editor.state.revision, revision + 1);
    expect(editor.state.routeModel!.catalog, call.catalog);
    expect(editor.state.routeModel!.descriptor.modelId, 'text');
    expect(port.lookupCalls, [(catalog: call.catalog, accountId: 'account-32')],
      reason: 'An exact native key supplies display details, not a new selection policy');
    expect(port.pageCalls.map((call) => (call.offset, call.limit)), [(0, 32)]);
    expect(editor.state.models, hasLength(32), reason: 'A detail read does not fabricate another catalog page');
    await editor.vm.suggestInitialRoute();
    expect(port.firstCalls, hasLength(1), reason: 'The explicit new-editor suggestion is single-shot');
    expect(port.effortCalls, isEmpty, reason: 'Native first already returned its own effort');
  });

  test('existing unsupported, unresolved and explicit-null routes survive build and save without repair', () async {
    final scenarios = [
      profileSnapshot(effort: 'UNSUPPORTED_RAW'),
      profileSnapshot(accountId: 'removed-account', modelId: 'removed-model', effort: 'old-raw'),
      profileSnapshot(effort: null),
    ];
    for (final original in scenarios) {
      final editor = await _editor(profile: original);
      final port = editor.fixture.modelPort;
      expect(editor.state.canonical, original);
      expect((editor.state.accountId, editor.state.modelId, editor.state.effort),
        (original.accountId, original.modelId, original.effort));
      await editor.vm.suggestInitialRoute();
      editor.vm.setDescription('edited description');
      final saving = editor.vm.save();
      final call = await editor.fixture.configurationPort.saved(0);
      expect(call.request.expectedSettingsRevision, 1,
        reason: 'The independently observed Profiles revision 7 is not the Settings CAS base');
      expect(call.request.profile, AgentProfileEdit(profileId: original.profileId,
        displayName: original.displayName, description: 'edited description', whenToUse: original.whenToUse,
        systemInstructions: original.systemInstructions, accountId: original.accountId, modelId: original.modelId,
        effort: original.effort, enabled: original.enabled, workspaceMode: original.workspaceMode));
      call.reply.completeError(const CommandDispatchFailure.rejected(failure: _rejected));
      expect(await saving, isFalse);
      expect(editor.state.saveAction!.error, _rejected);
      expect(editor.state.dirty, isTrue);
      expect(editor.state.effort, original.effort);
      expect(editor.state.accountId, original.accountId);
      expect(editor.state.modelId, original.modelId);
      expect(port.firstCalls, isEmpty);
      expect(port.effortCalls, isEmpty, reason: 'Neither build nor save may repair raw input via suggestions');
      expect(editor.fixture.configurationPort.saves, hasLength(1), reason: 'Native rejection is not replayed');
    }
  });

  test('changing model sends candidate null and explicit null defeats a late native effort suggestion', () async {
    final editor = await _editor(profile: profileSnapshot());
    final firstChange = editor.vm.setRoute('account-1', 'text');
    final first = await editor.fixture.modelPort.effortCalled(0);
    expect(first.model, const AccountModelKey(accountId: 'account-1', modelId: 'text'));
    expect(first.candidate, isNull, reason: 'The previous model effort must not cross model identity');
    first.reply.complete('high');
    await firstChange;
    expect(editor.state.effort, 'high', reason: 'An eligible result comes from native, not the first declared candidate');
    final changing = editor.vm.setRoute('account-0', 'text');
    final call = await editor.fixture.modelPort.effortCalled(1);
    expect(call.model, const AccountModelKey(accountId: 'account-0', modelId: 'text'));
    expect(call.candidate, isNull, reason: 'The newly selected model must not inherit high either');
    expect(call.catalog, first.catalog);
    expect(editor.state.effort, isNull);
    expect(editor.state.routeSuggestion!.pending, isTrue);
    final revision = editor.state.revision;
    editor.vm.setEffort(null);
    expect(editor.state.routeSuggestion, isNull);
    expect(editor.state.revision, revision + 1, reason: 'Explicit null is a new intent even when pending raw was null');
    call.reply.complete('low');
    await changing;
    expect((editor.state.accountId, editor.state.modelId, editor.state.effort), ('account-0', 'text', null));
    expect(editor.state.dirty, isTrue);
    final saving = editor.vm.save();
    final save = await editor.fixture.configurationPort.saved(0);
    expect(save.request.profile.effort, isNull, reason: 'Saving must not fill the declined default');
    save.reply.completeError(const CommandDispatchFailure.rejected(failure: _rejected));
    expect(await saving, isFalse);
    expect(editor.state.effort, isNull);
    expect(editor.fixture.modelPort.effortCalls, hasLength(2));
    expect(editor.fixture.modelPort.firstCalls, isEmpty);
  });

  test('a newer catalog revokes pending UI eligibility but keeps the original native query owned', () async {
    final editor = await _editor();
    final port = editor.fixture.modelPort;
    final suggesting = editor.vm.suggestInitialRoute();
    final call = await port.firstCalled(0);
    editor.vm.setInstructions('raw text after request');
    await port.advanceCatalog();
    expect(editor.state.routeSuggestion!.pending, isFalse);
    expect(editor.state.routeSuggestion!.error!.code, StudioFailureCode.superseded);
    expect(call.pin.closed, isFalse, reason: 'UI invalidation is not cancellation or native join');
    call.reply.complete(const ModelSelection(model: AccountModelKey(accountId: 'account-0', modelId: 'text'), effort: 'high'));
    await suggesting;
    expect((editor.state.accountId, editor.state.modelId, editor.state.effort), ('', '', null));
    expect(editor.state.instructions, 'raw text after request');
    expect(editor.state.dirty, isTrue);
    expect(port.firstCalls, hasLength(1), reason: 'A source change is not permission to retry automatically');
    expect(port.lookupCalls, isEmpty, reason: 'The old result cannot launch a display read on the new catalog');
    expect(call.catalog.reference.revision, 1);
    expect(editor.state.modelSource.projection.header!.reference!.revision, 2);
  });

  test('rebuilding the same notifier binds a new lifetime and repositories before any late suggestion handoff', () async {
    final editor = await _editor();
    final originalVm = editor.vm;
    final originalLifetime = originalVm.lifetime;
    final suggesting = originalVm.suggestInitialRoute();
    final original = await editor.fixture.modelPort.firstCalled(0);
    final replacement = ProfileEditorFixture(ownerEpoch: 'replacement-profile-native');
    await replacement.establish();
    await editor.rebind(replacement);
    expect(editor.vm, same(originalVm), reason: 'Dependency rebuild is the real same-notifier ABA boundary');
    expect(editor.vm.lifetime, greaterThan(originalLifetime));
    expect(editor.vm.ownsEditor(originalLifetime, editor.key), isFalse);
    final nextSuggestion = editor.vm.suggestInitialRoute();
    final fresh = await replacement.modelPort.firstCalled(0);
    expect(fresh.catalog.origin, replacement.origin);
    fresh.reply.complete(const ModelSelection(model: AccountModelKey(accountId: 'account-1', modelId: 'text'), effort: 'low'));
    await nextSuggestion;
    final current = editor.state;
    original.reply.complete(const ModelSelection(model: AccountModelKey(accountId: 'account-0', modelId: 'text'), effort: 'high'));
    await suggesting;
    expect(editor.state, current, reason: 'An old owner/lifetime cannot overwrite the rebuilt editor');
    expect((editor.state.accountId, editor.state.modelId, editor.state.effort), ('account-1', 'text', 'low'));
    expect(original.catalog.origin, editor.fixture.origin);
    expect(editor.fixture.modelPort.lookupCalls, isEmpty);
  });

  test('disposing the editor cannot release the admitted native suggestion before Repository cleanup joins it', () async {
    final editor = await _editor();
    final suggesting = editor.vm.suggestInitialRoute();
    final call = await editor.fixture.modelPort.firstCalled(0);
    editor.disposeEditor();
    final publicationCount = editor.publications.length;
    expect(editor.fixture.modelPort.feed.requestCloseCalls, 0,
      reason: 'VM disposal only cancels its observations');
    final report = await editor.fixture.models.close(deadline: DateTime.utc(2000));
    expect(report.complete, isFalse);
    final query = report.unresolved.where((owner) => owner.owner == 'models:first-text-model').single;
    expect(query.issues.single.recovery, CleanupRecovery.awaitCompletion);
    expect(call.pin.closed, isFalse);
    call.reply.complete(const ModelSelection(model: AccountModelKey(accountId: 'account-0', modelId: 'text'), effort: 'high'));
    await suggesting;
    expect((await editor.fixture.models.retryCleanup()).complete, isTrue);
    expect(call.pin.closed, isTrue);
    expect(editor.publications, hasLength(publicationCount));
  });

  test('an admitted save stays with its original Configuration owner after the same editor rebuilds', () async {
    final editor = await _editor(profile: profileSnapshot());
    editor.vm.setDescription('original-owner draft');
    final originalVm = editor.vm;
    final lifetime = originalVm.lifetime;
    final saving = originalVm.save();
    final original = await editor.fixture.configurationPort.saved(0);
    final replacement = ProfileEditorFixture(ownerEpoch: 'replacement-save-native', profile: profileSnapshot(effort: 'high'));
    await replacement.establish();
    await editor.rebind(replacement);
    expect(editor.vm, same(originalVm));
    expect(editor.vm.lifetime, greaterThan(lifetime));
    editor.vm.setDescription('new-owner draft');
    final current = editor.state;
    final report = await editor.fixture.configuration.close(deadline: DateTime.utc(2000));
    expect(report.complete, isFalse, reason: 'The original save ticket remains Repository-owned');
    expect(original.request.profile.description, 'original-owner draft');
    original.reply.completeError(const CommandDispatchFailure.rejected(failure: _rejected));
    expect(await saving, isFalse);
    expect((await editor.fixture.configuration.retryCleanup()).complete, isTrue);
    expect(editor.state, current, reason: 'Late settlement may not replace the new raw draft or its action state');
    expect(replacement.configurationPort.saves, isEmpty);
    expect(editor.fixture.modelPort.firstCalls, isEmpty);
    expect(editor.fixture.modelPort.effortCalls, isEmpty);
  });
}
