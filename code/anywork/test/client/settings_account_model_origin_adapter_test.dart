import 'package:anywork/src/app/app_bindings.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/settings/accounts/state/model_limits_state.dart';
import 'package:anywork/src/features/settings/accounts/views/account_details_view.dart';
import 'package:anywork/src/features/settings/accounts/widgets/account_model_card.dart';
import 'package:anywork/src/features/settings/agents/connectors/agent_profile_editor_connector.dart';
import 'package:anywork/src/features/settings/agents/view_models/agent_profile_editor_view_model.dart';
import 'package:anywork/src/features/settings/agents/views/agent_profile_editor_view.dart';
import 'package:anywork/src/features/settings/state/editor_keys.dart';
import 'package:anywork/src/features/settings/view_models/collection_values.dart';
import 'package:anywork/src/features/status/projections/selector_values.dart';
import 'package:anywork/src/features/status/state/selector_catalog_state.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/ui/selectors/model_route_selector.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/modes.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pump_client_future.dart';
import 'support/settings_accounts_fixture.dart';

// 生产主题提供 StudioSemanticColors 扩展；测试必须用同一个主题，
// 否则共享的 tone 徽标只能靠生产代码里的兜底分支才能渲染。
Widget _app(Widget child) => MaterialApp(theme: pureStudioTheme(),
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales, home: Scaffold(body: child));

SelectorCatalogState _selector(SettingsAccountsFixture fixture) => SelectorCatalogState(
  configuration: fixture.configuration.state.value, models: fixture.models.state.value,
  modes: const ModesState(projection: ProductProjection(stamp: null, header: null,
    sync: ResourceSyncState(phase: ResourceSyncPhase.idle, error: null, retryExhausted: false)),
    modes: CollectionMirror.unavailable(lastKnown: null)));

ModelsState _models(ModelsState source, List<AccountCatalogEntry> accounts) {
  final origin = source.projection.stamp!.origin;
  final refs = [for (var index = 0; index < accounts.length; index++) ProductEntityRef(entry: 100 + index, revision: 1)];
  return source.copyWith(accounts: CollectionMirror.current(window: CollectionWindow(
    origin: origin, reference: ProductCollectionRef(entry: 2, revision: 1, total: accounts.length),
    entries: refs, rows: {for (var index = 0; index < refs.length; index++) refs[index].entry:
      ReadValue.ready(current: Materialized(origin: origin, reference: refs[index], value: accounts[index]))},
    continuation: const CollectionContinuation.end(), complete: true, loading: false, error: null)));
}

Future<SettingsAccountsFixture> _fixture({WidgetTester? tester, bool duplicates = false}) async {
  Future<SettingsAccountsFixture> create() async {
  final fixture = SettingsAccountsFixture(accountCount: duplicates ? 2 : 1);
  fixture.modelPort.duplicateModels = duplicates;
    await fixture.establish();
    return fixture;
  }
  final fixture = tester == null ? await create() : (await tester.runAsync(create))!;
  addTearDown(() async {
    final report = tester == null ? await fixture.close()
      : await pumpClientFuture(tester, fixture.close(), 'account catalog environment cleanup');
    expect(report.unresolved, isEmpty);
    expect(fixture.budget.usage, isEmpty);
  });
  return fixture;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('an open Agent Profile dialog follows a newer catalog and keeps its draft route', (tester) async {
    final fixture = await _fixture(tester: tester);
    final container = ProviderContainer(overrides: [
      configurationRepositoryProvider.overrideWithValue(fixture.configuration),
      modelsRepositoryProvider.overrideWithValue(fixture.models),
    ]);
    addTearDown(container.dispose);
    const key = ProfileEditorKey(editorId: 1);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: _app(
      AgentProfileEditorConnector(target: key, onClose: (_) {}))));
    final first = await pumpClientFuture(tester, fixture.modelPort.base.firstCalled(0), 'explicit initial model suggestion');
    first.reply.complete(const ModelSelection(model: AccountModelKey(accountId: 'account-0', modelId: 'text'), effort: null));
    await pumpClientUntil(tester, () => container.read(agentProfileEditorViewModelProvider(key)).asData?.value.modelId == 'text', 'initial route');
    final dialogState = tester.state(find.byType(AgentProfileEditorConnector));
    expect(tester.widget<AgentProfileEditorView>(find.byType(AgentProfileEditorView)).options, hasLength(1));
    container.read(agentProfileEditorViewModelProvider(key).notifier).setDescription('keep the edited draft');
    await pumpClientFuture(tester, fixture.modelPort.invalidateTextModels(), 'newer catalog');
    await pumpClientFuture(tester, fixture.models.loadAccountsPage(), 'new catalog qualification');
    await tester.pump();
    final dialog = tester.widget<AgentProfileEditorView>(find.byType(AgentProfileEditorView));
    expect(dialog.options, isEmpty);
    expect(tester.state(find.byType(AgentProfileEditorConnector)), same(dialogState));
    final selector = tester.widget<ModelRouteSelector>(find.byType(ModelRouteSelector));
    expect(selector.modelId, 'text');
    expect(selector.options, isEmpty);
    expect(selector.unresolvedLabel?.toLowerCase(), contains('context'));
    expect(dialog.state.description, 'keep the edited draft');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('composer catalog projections observe canonical qualification without recomputing it', () async {
    final fixture = await _fixture();
    final before = _selector(fixture);
    expect(before.copyWith(models: before.models.copyWith()), before);
    final account = displayCollectionRows(before.models.accounts).single;
    final model = account.effectiveModels.single;
    // Large numeric limits deliberately remain unchanged: only Rust's typed
    // qualification changes, so a Dart-side recalculation would be detected.
    final excluded = model.copyWith(typeSupport: [ModelTypeSupport(modelType: ModelType.text,
      exclusions: const [ModelTypeExclusion.contextWindowUnknown])]);
    final after = before.copyWith(models: _models(before.models, [account.copyWith(effectiveModels: [excluded])]));
    expect(after, isNot(before));
    expect(selectorModels(after), isEmpty);
    expect(displayCollectionRows(after.models.accounts).single.effectiveModels.single.modelId, 'text');
    expect(selectorModels(before).single.modelId, 'text');
  });

  testWidgets('session and Agent adapters query canonical text types and deduplicate routes', (tester) async {
    final fixture = await _fixture(tester: tester, duplicates: true);
    final container = ProviderContainer(overrides: [
      configurationRepositoryProvider.overrideWithValue(fixture.configuration),
      modelsRepositoryProvider.overrideWithValue(fixture.models),
    ]);
    addTearDown(container.dispose);
    // The same controlled catalog goes through the real VM and Smart adapter.
    // Settle its explicit suggestion without manufacturing a selected route.
    const target = ProfileEditorKey(editorId: 2);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: _app(
      AgentProfileEditorConnector(target: target, onClose: (_) {}))));
    final first = await pumpClientFuture(tester, fixture.modelPort.base.firstCalled(0), 'initial suggestion');
    first.reply.complete(null);
    await pumpClientUntil(tester, () => container.read(agentProfileEditorViewModelProvider(target)).asData?.value.routeSuggestion?.pending == false, 'suggestion result');
    final options = selectorModels(_selector(fixture));
    final agentOptions = tester.widget<AgentProfileEditorView>(find.byType(AgentProfileEditorView)).options;
    expect(agentOptions, options);
    expect(options.map((option) => (option.accountId, option.modelId)).toList(),
      [('account-0', 'text'), ('account-1', 'text')]);
    expect(options.every((option) => option.descriptor.capabilities.input.isEmpty &&
      option.descriptor.capabilities.output.isEmpty), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('settings accounts view keeps canonical origins for grouping', (tester) async {
    final fixture = await _fixture(tester: tester);
    final configuration = displayCollectionRows(fixture.configuration.state.value.accounts).single;
    final catalog = displayCollectionRows(fixture.models.state.value.accounts).single;
    final model = catalog.effectiveModels.single;
    final grouped = catalog.copyWith(effectiveModels: [
      model.copyWith(modelId: 'gpt-manual', origin: ModelOrigin.manual),
      model.copyWith(modelId: 'gpt-online', origin: ModelOrigin.online),
      model.copyWith(modelId: 'gpt-bundled', origin: ModelOrigin.bundled),
    ]);
    await tester.pumpWidget(_app(AccountDetailsView(
      state: AccountModelLimitsViewState(accountId: configuration.accountId,
        source: fixture.configuration.state.value, modelSource: fixture.models.state.value,
        canonical: configuration, catalog: grouped), errors: const [], modelErrors: const {},
      enabledErrors: const {}, billingErrors: const [], onBack: () {}, onEdit: () {},
      onRemoveModel: (_) {}, onLimit: (_, _) {}, onComposing: (_, _) {}, onCommit: (_) {},
      onRestore: (_) {}, onRetry: () {}, onModelDetails: (_) {})));
    final list = tester.widget<ListView>(find.byType(ListView));
    final cards = (list.childrenDelegate as SliverChildListDelegate).children.whereType<AccountModelCard>().toList();
    expect(cards.where((card) => card.model.origin == ModelOrigin.online).map((card) => card.model.modelId), ['gpt-online']);
    expect(cards.where((card) => card.model.origin == ModelOrigin.bundled).map((card) => card.model.modelId), ['gpt-bundled']);
    expect(cards.where((card) => card.model.origin == ModelOrigin.manual).map((card) => card.model.modelId), ['gpt-manual']);
    expect(cards.map((card) => card.model.modelId), ['gpt-online', 'gpt-bundled', 'gpt-manual']);
    expect(cards.where((card) => card.onDelete != null).single.model.modelId, 'gpt-manual');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
