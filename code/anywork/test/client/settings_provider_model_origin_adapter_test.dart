import 'package:anywork/src/features/settings/settings_views.dart';
import 'package:anywork/src/features/settings/settings_agents_tab.dart';
import 'package:anywork/src/features/settings/settings_agent_profile_dialog.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/domain/models/agent_workspace_view.dart';
import 'package:anywork/src/domain/models/studio_reactive_projections.dart';
import 'package:anywork/src/features/status/session_selectors.dart';
import 'package:anywork/src/presentation/providers/client_provider.dart';
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
      final client = (await tester.runAsync(
        () async => AnyworkClient(
          transport: _UnusedTransport(),
          clientId: 'profile-catalog',
        ),
      ))!;
      addTearDown(() async {
        final report = await tester.runAsync(
          () => client.close(
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
      const model = ProviderModelView(
        modelId: 'model',
        displayName: 'Model',
        reasoningEfforts: [],
        typeSupport: [ModelTypeSupportView(modelType: ModelType.text)],
      );
      const provider = ProviderSettingsView(
        id: 'p',
        name: 'P',
        baseUrl: '',
        defaultModel: 'model',
        status: '',
        usageLabel: '',
        models: [model],
      );
      client.settings.merge(
        SettingsStateSnapshot(
          revision: 1,
          modelCatalogRevision: 1,
          providers: [provider],
        ),
      );
      final container = ProviderContainer(
        overrides: [anyworkClientProvider.overrideWith((ref) => client)],
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
            .providers
            .single
            .modelsFor(type: ModelType.text),
        hasLength(1),
      );
      client.settings.merge(
        SettingsStateSnapshot(
          revision: 1,
          modelCatalogRevision: 2,
          providers: [
            provider.copyWith(
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
      expect(dialog.providers.single.modelsFor(type: ModelType.text), isEmpty);
      expect(tester.state(find.byType(AgentProfileDialog)), same(dialogState));
      final selector = tester.widget<ModelRouteSelector>(
        find.byType(ModelRouteSelector),
      );
      expect(selector.model, 'model');
      expect(selector.options, isEmpty);
      expect(selector.unresolvedLabel?.toLowerCase(), contains('context'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('composer projections observe canonical qualification without recomputing it', () {
    const model = ProviderModelView(
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
      updatedAt: DateTime.utc(2026),
      workspacePath: '/project',
    );
    StudioComposerProjection projection(ProviderModelView value) =>
        StudioComposerProjection(
          thread: thread,
          rootThread: thread,
          syncState: AgentWorkspaceSyncState.ready,
          loadError: null,
          composer: const ComposerThreadState.idle(),
          composerMode: AgentComposerMode.editable,
          providers: [
            ProviderSettingsView(
              id: 'p',
              name: 'P',
              baseUrl: '',
              defaultModel: 'model',
              status: '',
              usageLabel: '',
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
    expect(after.providers.single.modelsFor(type: ModelType.text), isEmpty);
    expect(after.providers.single.models.single.modelId, 'model');
  });

  test('session and Agent adapters query canonical text types and deduplicate routes', () {
    const text = ProviderModelView(
      modelId: 'shared',
      typeSupport: [ModelTypeSupportView(modelType: ModelType.text)],
      displayName: 'Shared',
      reasoningEfforts: [],
    );
    const media = ProviderModelView(
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
    ProviderSettingsView provider(String id) => ProviderSettingsView(
      id: id,
      name: id,
      baseUrl: '',
      defaultModel: 'shared',
      status: '',
      usageLabel: '',
      models: const [text, text, media],
    );
    final providers = [provider('a'), provider('b'), provider('a')];
    final options = modelOptions(providers);
    final agentOptions = buildModelSelectionOptions(
      providers,
      type: ModelType.text,
    );
    expect(agentOptions, options);
    expect(
      options.map((option) => (option.providerId, option.model)).toList(),
      [('a', 'shared'), ('b', 'shared')],
    );
    expect(
      options.every((option) => option.descriptor.capabilities.isEmpty),
      isTrue,
    );
  });

  test('settings providers view keeps snapshot origins for grouping', () {
    final client = AnyworkClient(
      transport: _UnusedTransport(),
      clientId: 'origin-adapter',
    );
    addTearDown(client.close);
    client.settings.merge(
      SettingsStateSnapshot(
        revision: 3,
        providers: [
          ProviderSettingsView(
            id: 'openai',
            name: 'OpenAI',
            baseUrl: 'https://api.openai.com',
            defaultModel: 'gpt-manual',
            status: 'ready',
            usageLabel: '',
            models: const [
              ProviderModelView(
                modelId: 'gpt-online',
                displayName: 'Online',
                reasoningEfforts: [],
                origin: ProviderModelOrigin.online,
              ),
              ProviderModelView(
                modelId: 'gpt-bundled',
                displayName: 'Bundled',
                reasoningEfforts: [],
                origin: ProviderModelOrigin.bundled,
              ),
              ProviderModelView(
                modelId: 'gpt-manual',
                displayName: 'Manual',
                reasoningEfforts: [],
                origin: ProviderModelOrigin.manual,
              ),
            ],
          ),
        ],
      ),
    );
    final container = ProviderContainer(
      overrides: [anyworkClientProvider.overrideWith((ref) => client)],
    );
    addTearDown(container.dispose);
    final view = container.read(settingsProvidersViewProvider);
    final provider = view.providers.single;
    expect(provider.onlineModels.map((model) => model.modelId), ['gpt-online']);
    expect(provider.bundledModels.map((model) => model.modelId), [
      'gpt-bundled',
    ]);
    expect(provider.customModels.map((model) => model.modelId), ['gpt-manual']);
  });
}

class _UnusedTransport implements StudioTransport {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unused transport: ${invocation.memberName}');
}
