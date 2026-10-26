import 'package:anywork/src/features/settings/settings_agents_tab.dart';
import 'package:anywork/src/features/settings/settings_agent_profile_dialog.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/domain/models/agent_workspace_view.dart';
import 'package:anywork/src/domain/models/studio_reactive_projections.dart';
import 'package:anywork/src/features/status/session_selectors.dart';
import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/presentation/providers/account_domains.dart';
import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/accounts_ports.dart';
import 'package:anywork_client/model_directory.dart';

import 'support/test_statistics_feed.dart';
import 'support/unused_account_ports.dart';

import 'package:anywork/src/shared/model_route_selector.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'an open Agent Profile dialog follows a newer catalog and keeps its draft route',
    (tester) async {
      // App-owned asynchronous lanes must be created and joined in the same
      // real async zone, rather than trapping their initial futures in fake time.
      final graph = (await tester.runAsync(
        () async => AppGraph(
          transport: _UnusedTransport(),
          statisticsFeed: const TestStatisticsFeedPort(),
          clientId: 'profile-catalog',
        ),
      ))!;
      addTearDown(() async {
        final report = await tester.runAsync(
          () => graph.close(
            deadline: DateTime.now().add(const Duration(seconds: 3)),
          ),
        );
        expect(
          report?.unresolved.map(
            (resource) => '${resource.owner}: ${resource.reason}',
          ),
          isEmpty,
        );
      });
      const model = AccountModelView(
        modelId: 'model',
        displayName: 'Model',
        reasoningEfforts: [],
        typeSupport: [ModelTypeSupportView(modelType: ModelType.text)],
      );
      const account = AccountSettingsView(
        id: 'p',
        name: 'P',
        baseUrl: '',
        defaultModelId: 'model',
        status: '',
        usageLabel: '',
        models: [model],
      );
      _seed(
        graph,
        SettingsStateSnapshot(
          revision: 1,
          modelCatalogRevision: 1,
          accounts: [account],
        ),
      );
      final container = ProviderContainer(
        overrides: [appGraphProvider.overrideWithValue(graph)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: AgentsTab(tabIndex: 1)),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('agent-profile-add')));
      await tester.pump(const Duration(milliseconds: 300));
      final dialogState = tester.state(find.byType(AgentProfileDialog));
      expect(
        tester
            .widget<AgentProfileDialog>(find.byType(AgentProfileDialog))
            .accounts
            .single
            .modelsFor(type: ModelType.text),
        hasLength(1),
      );
      _seed(
        graph,
        SettingsStateSnapshot(
          revision: 1,
          modelCatalogRevision: 2,
          accounts: [
            account.copyWith(
              models: [
                model.copyWith(
                  typeSupport: const [
                    ModelTypeSupportView(
                      modelType: ModelType.text,
                      exclusions: [ModelTypeExclusion.contextWindowUnknown],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();
      final dialog = tester.widget<AgentProfileDialog>(
        find.byType(AgentProfileDialog),
      );
      expect(dialog.accounts.single.modelsFor(type: ModelType.text), isEmpty);
      expect(tester.state(find.byType(AgentProfileDialog)), same(dialogState));
      final selector = tester.widget<ModelRouteSelector>(
        find.byType(ModelRouteSelector),
      );
      expect(selector.modelId, 'model');
      expect(selector.options, isEmpty);
      expect(selector.unresolvedLabel?.toLowerCase(), contains('context'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      // The external container still owns model-selection demand after widget
      // unmount. Release it and really join the graph before the timer invariant.
      container.dispose();
      await tester.pump();
      final report = await tester.runAsync(
        () => graph.close(
          deadline: DateTime.now().add(const Duration(seconds: 3)),
        ),
      );
      expect(
        report!.unresolved.map(
          (resource) => '${resource.owner}: ${resource.reason}',
        ),
        isEmpty,
      );
    },
  );

  test('composer projections observe canonical qualification without recomputing it', () {
    const model = AccountModelView(
      modelId: 'model',
      displayName: 'Model',
      reasoningEfforts: [],
      typeSupport: [ModelTypeSupportView(modelType: ModelType.text)],
    );
    final thread = StudioThread(
      id: 'thread',
      projectId: 'project',
      title: 'Thread',
      mode: ThreadModeId.simple,
      delegationMode: DelegationMode.profile,
      delegationPreference: DelegationPreference.balanced,
      updatedAt: DateTime.utc(2026),
      workspacePath: '/project',
    );
    StudioComposerProjection projection(AccountModelView value) =>
        StudioComposerProjection(
          thread: thread,
          rootThread: thread,
          syncState: AgentWorkspaceSyncState.ready,
          loadError: null,
          composer: const ComposerThreadState.idle(),
          composerMode: AgentComposerMode.editable,
          accounts: [
            ModelSelectionAccount(
              id: 'p',
              name: 'P',
              billingKind: BillingKind.unknown,
              models: [value],
            ),
          ],
          modeModelRoutes: const [],
          roles: const [],
          activeInteraction: null,
          turn: null,
          modelRoute: null,
          workflow: null,
          targetDiagnostic: null,
        );
    final before = projection(model);
    expect(projection(model.copyWith()), before);
    final after = projection(
      model.copyWith(
        typeSupport: const [
          ModelTypeSupportView(
            modelType: ModelType.text,
            exclusions: [ModelTypeExclusion.contextWindowUnknown],
          ),
        ],
      ),
    );
    expect(after, isNot(before));
    expect(after.accounts.single.modelsFor(type: ModelType.text), isEmpty);
    expect(after.accounts.single.models.single.modelId, 'model');
  });

  test('session and Agent adapters query canonical text types and deduplicate routes', () {
    const text = AccountModelView(
      modelId: 'shared',
      typeSupport: [ModelTypeSupportView(modelType: ModelType.text)],
      displayName: 'Shared',
      reasoningEfforts: [],
    );
    const media = AccountModelView(
      modelId: 'image-generator',
      typeSupport: [
        ModelTypeSupportView(
          modelType: ModelType.text,
          exclusions: [ModelTypeExclusion.textOutputUnsupported],
        ),
      ],
      displayName: 'Image',
      reasoningEfforts: [],
    );
    ModelSelectionAccount account(String id) => ModelSelectionAccount(
      id: id,
      name: id,
      billingKind: BillingKind.unknown,
      models: const [text, text, media],
    );
    final accounts = [account('a'), account('b'), account('a')];
    final options = modelOptions(accounts);
    final agentOptions = buildModelSelectionOptions(
      accounts,
      type: ModelType.text,
    );
    expect(agentOptions, options);
    expect(
      options.map((option) => (option.accountId, option.modelId)).toList(),
      [('a', 'shared'), ('b', 'shared')],
    );
    expect(
      options.every((option) => option.descriptor.capabilities.isEmpty),
      isTrue,
    );
  });

  test('settings accounts view keeps snapshot origins for grouping', () {
    final graph = AppGraph(
      transport: _UnusedTransport(),
      statisticsFeed: const TestStatisticsFeedPort(),
      clientId: 'origin-adapter',
    );
    addTearDown(
      () =>
          graph.close(deadline: DateTime.now().add(const Duration(seconds: 3))),
    );
    _seed(
      graph,
      SettingsStateSnapshot(
        revision: 3,
        accounts: [
          AccountSettingsView(
            id: 'openai',
            name: 'OpenAI',
            baseUrl: 'https://api.openai.com',
            defaultModelId: 'gpt-manual',
            status: 'ready',
            usageLabel: '',
            models: const [
              AccountModelView(
                modelId: 'gpt-online',
                displayName: 'Online',
                reasoningEfforts: [],
                origin: ModelOrigin.online,
              ),
              AccountModelView(
                modelId: 'gpt-bundled',
                displayName: 'Bundled',
                reasoningEfforts: [],
                origin: ModelOrigin.bundled,
              ),
              AccountModelView(
                modelId: 'gpt-manual',
                displayName: 'Manual',
                reasoningEfforts: [],
                origin: ModelOrigin.manual,
              ),
            ],
          ),
        ],
      ),
    );
    final container = ProviderContainer(
      overrides: [appGraphProvider.overrideWithValue(graph)],
    );
    addTearDown(container.dispose);
    final view = container.read(modelDirectoryStateProvider);
    final models =
        view.accounts[const NativeAccountIdentity('openai')]!.value!.models;
    expect(
      models
          .where((model) => model.origin == ModelOrigin.online)
          .map((model) => model.modelId),
      ['gpt-online'],
    );
    expect(
      models
          .where((model) => model.origin == ModelOrigin.bundled)
          .map((model) => model.modelId),
      ['gpt-bundled'],
    );
    expect(
      models
          .where((model) => model.origin == ModelOrigin.manual)
          .map((model) => model.modelId),
      ['gpt-manual'],
    );
  });
}

class _UnusedTransport extends UnusedAccountPorts implements StudioTransport {
  @override
  Stream<ProductTopicFrame> subscribeProductTopic(ProductTopic topic) =>
      const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unused transport: ${invocation.memberName}');
}

// Complete scripted owner frames. Production providers reduce and project them.
void _seed(AppGraph graph, SettingsStateSnapshot snapshot) {
  graph.client.acceptSettingsSnapshot(snapshot);
  const epoch = 'origin-owner';
  graph.accountDomains.acceptFrame(
    AccountSummariesFrame(
      ResourceStamp(
        resourceKey: 'settings',
        ownerEpoch: epoch,
        revision: snapshot.revision,
      ),
      [
        for (final account in snapshot.accounts)
          AccountSummary(
            identity: NativeAccountIdentity(account.id),
            name: account.name,
            isDefault: false,
            credentialReady: true,
            capabilities: const AccountCapabilities(
              setDefault: true,
              edit: true,
              remove: true,
              queryUsage: false,
              syncModels: false,
              editModels: true,
              acpAuth: false,
            ),
          ),
      ],
    ),
  );
  for (final account in snapshot.accounts) {
    final identity = NativeAccountIdentity(account.id);
    graph.accountDomains.acceptFrame(
      AccountModelsFrame(
        ResourceStamp(
          resourceKey: 'model-catalog',
          ownerEpoch: epoch,
          revision: snapshot.modelCatalogRevision,
        ),
        identity,
        AccountModelCatalog(
          identity: identity,
          models: account.models,
          status: account.modelCatalog,
        ),
      ),
    );
  }
}
