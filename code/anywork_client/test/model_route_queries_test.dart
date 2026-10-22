import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

void main() {
  test(
    'typed model queries preserve full catalogs and configured excluded routes',
    () {
      final eligible = _account.models.single;
      final unknown = eligible.copyWith(
        modelId: 'unknown-budget',
        typeSupport: const [
          ModelTypeSupportView(
            modelType: ModelType.text,
            exclusions: [ModelTypeExclusion.contextWindowUnknown],
          ),
        ],
      );
      final mixed = _account.copyWith(models: [unknown, eligible]);
      expect(mixed.modelsFor().map((model) => model.modelId), [
        'unknown-budget',
        'observed-model',
      ]);
      expect(
        mixed.modelsFor(type: ModelType.text).map((model) => model.modelId),
        ['observed-model'],
      );
      final role = ModelRouteQueries.roleRoute(
        accounts: [mixed],
        roles: const [
          RoleSettingsView(
            key: 'worker',
            accountId: 'account',
            modelId: 'unknown-budget',
            effort: 'high',
          ),
        ],
        role: 'worker',
      );
      expect(role.modelId, 'unknown-budget');
      expect(role.descriptor, same(unknown));
      expect(
        role.unavailable,
        isFalse,
        reason: 'list qualification is independent of execution availability',
      );
      expect(
        ModelRouteQueries.newAgentProfileRoute([mixed]).modelId,
        'observed-model',
      );
      expect(
        ModelRouteQueries.newAgentProfileRoute([
          mixed.copyWith(models: [unknown]),
        ]).modelId,
        isEmpty,
      );
    },
  );
  test('pending model intent cannot fabricate an observed route revision', () {
    const canonical = ThreadModelRouteView(
      accountId: 'account',
      modelId: 'observed-model',
      effort: 'medium',
      revision: 19,
      available: true,
    );
    const pending = CommandStatus(
      key: 'thread-route',
      phase: CommandPhase.pending,
      target: CommandTarget(
        accountId: 'account',
        modelId: 'removed-model',
        effort: 'high',
      ),
    );

    final display = ModelRouteQueries.threadRoute(
      canonical: canonical,
      command: pending,
      accounts: [_account],
    )!;
    expect(display.modelId, 'removed-model');
    expect(display.effort, 'high');
    expect(display.pending, isTrue);
    expect(display.available, isFalse);
    expect(canonical.modelId, 'observed-model');
    expect(canonical.revision, 19);

    final observed = ModelRouteQueries.threadRoute(
      canonical: canonical,
      command: null,
      accounts: const [],
    )!;
    expect(observed.modelId, 'observed-model');
    expect(observed.pending, isFalse);
    expect(
      observed.available,
      isTrue,
      reason: 'canonical availability comes from its owner frame',
    );
  });

  test('mode inheritance preserves configured unavailable Agent routes', () {
    const simple = ModeModelRouteView(
      modeId: ThreadModeId.simple,
      accountId: 'account',
      modelId: 'observed-model',
      effort: 'medium',
    );
    final route = ModelRouteQueries.startRoute(
      routes: [simple],
      commands: const {},
      draft: const StartSessionDraft(),
      mode: ThreadModeId.task,
    );
    expect(route.canonical, same(simple));
    expect(route.display!.accountId, 'account');
    expect(route.display!.modelId, 'observed-model');
    expect(route.pending, isFalse);

    final configured = ModelRouteQueries.roleRoute(
      accounts: [_account],
      roles: const [
        RoleSettingsView(
          key: 'reviewer',
          accountId: 'removed-account',
          modelId: 'removed-model',
          effort: 'high',
        ),
      ],
      role: 'reviewer',
    );
    expect(configured.accountId, 'removed-account');
    expect(configured.modelId, 'removed-model');
    expect(configured.unavailable, isTrue);
    expect(configured.hasConfiguredRoute, isTrue);
    final unconfigured = ModelRouteQueries.roleRoute(
      accounts: [_account],
      roles: const [],
      role: 'new-agent',
    );
    expect(unconfigured.modelId, 'observed-model');
    expect(unconfigured.effort, 'medium');
    expect(unconfigured.hasConfiguredRoute, isFalse);
    final configuredDefault = ModelRouteQueries.roleRoute(
      accounts: [_account],
      roles: const [
        RoleSettingsView(
          key: 'worker',
          accountId: 'account',
          modelId: 'observed-model',
          effort: '',
        ),
      ],
      role: 'worker',
    );
    expect(configuredDefault.effort, 'medium');
    expect(configuredDefault.hasConfiguredRoute, isTrue);
  });

  test('throughput uses only a complete sample from the current Turn', () {
    const runtime = ThreadRuntimeView(
      modelId: 'observed-model',
      contextTokens: 0,
      contextWindow: 0,
      totalTokens: 0,
      costLabel: '',
      activeSkills: [],
      activeMcpServers: [],
      activeLspServers: [],
      turnCompletionTokens: 1000,
      turnResponseMillis: 1000,
    );
    expect(ModelRouteQueries.throughput(runtime), 1000);
    expect(
      ModelRouteQueries.throughput(runtime.copyWith(turnCompletionTokens: 0)),
      isNull,
    );
    for (final sample in [
      (tokens: 20, millis: null),
      (tokens: null, millis: 500),
      (tokens: 0, millis: 500),
      (tokens: 20, millis: 0),
    ]) {
      final partial = runtime.copyWith(
        liveUsage: ThreadRuntimeLiveUsageView(
          turnId: 'next-turn',
          attemptId: 'next-attempt',
          completionTokens: sample.tokens,
          responseMillis: sample.millis,
          state: ThreadRuntimeUsageState.live,
          observationSequence: 1,
        ),
      );
      expect(
        ModelRouteQueries.throughput(partial),
        1000,
        reason:
            'incomplete live sample $sample must keep the confirmed Turn pair',
      );
    }
    final complete = runtime.copyWith(
      liveUsage: const ThreadRuntimeLiveUsageView(
        turnId: 'next-turn',
        attemptId: 'next-attempt',
        completionTokens: 20,
        responseMillis: 500,
        state: ThreadRuntimeUsageState.live,
        observationSequence: 2,
      ),
    );
    expect(ModelRouteQueries.throughput(complete), 40);
    expect(ModelRouteQueries.throughputSource(complete)?.outputTokens, 20);
    expect(ModelRouteQueries.throughputSource(complete)?.responseMillis, 500);
    expect(
      ModelRouteQueries.throughputSource(
        runtime.copyWith(
          liveUsage: const ThreadRuntimeLiveUsageView(
            turnId: 'next-turn',
            attemptId: 'next-attempt',
            completionTokens: 20,
            state: ThreadRuntimeUsageState.live,
            observationSequence: 1,
          ),
        ),
      )?.outputTokens,
      1000,
    );
    expect(
      ModelRouteQueries.throughput(
        runtime.copyWith(turnCompletionTokens: 0, turnResponseMillis: 0),
      ),
      isNull,
    );
    expect(
      ModelRouteQueries.throughput(runtime.copyWith(turnResponseMillis: 0)),
      isNull,
      reason: 'positive tokens without decode duration stay unknown',
    );
  });

  test('model selection keeps a supported effort then a declared candidate default', () {
    const model = AccountModelView(
      modelId: 'observed-model',
      typeSupport: [ModelTypeSupportView(modelType: ModelType.text)],
      displayName: 'Observed model',
      reasoningEfforts: ['low', 'medium', 'high'],
      defaultReasoningEffort: 'medium',
    );
    expect(ModelRouteQueries.effortAfterModelSelection(model, 'high'), 'high');
    expect(ModelRouteQueries.effortAfterModelSelection(model, null), 'medium');

    const emptyDefault = AccountModelView(
      modelId: 'observed-model',
      displayName: 'Observed model',
      reasoningEfforts: ['low', 'high'],
    );
    expect(
      ModelRouteQueries.effortAfterModelSelection(emptyDefault, null),
      'low',
    );

    const mismatchedDefault = AccountModelView(
      modelId: 'observed-model',
      displayName: 'Observed model',
      reasoningEfforts: ['low', 'high'],
      defaultReasoningEffort: 'medium',
    );
    expect(
      ModelRouteQueries.effortAfterModelSelection(mismatchedDefault, null),
      'low',
    );
    expect(
      ModelRouteQueries.effortAfterModelSelection(mismatchedDefault, 'medium'),
      'low',
      reason: 'undeclared candidate values must not be admitted',
    );

    const emptyCatalog = AccountModelView(
      modelId: 'observed-model',
      displayName: 'Observed model',
      reasoningEfforts: [],
      defaultReasoningEffort: 'medium',
    );
    expect(
      ModelRouteQueries.effortAfterModelSelection(emptyCatalog, 'medium'),
      isNull,
    );
    expect(
      ModelRouteQueries.effortAfterModelSelection(emptyCatalog, null),
      isNull,
    );
    expect(ModelRouteQueries.effortAfterModelSelection(null, 'high'), isNull);
  });
}

const _account = AccountSettingsView(
  id: 'account',
  name: 'Provider',
  baseUrl: '',
  defaultModelId: 'observed-model',
  models: [
    AccountModelView(
      modelId: 'observed-model',
      displayName: 'Observed model',
      reasoningEfforts: ['medium', 'high'],
      typeSupport: [ModelTypeSupportView(modelType: ModelType.text)],
      defaultReasoningEffort: 'medium',
    ),
  ],
  status: '',
  usageLabel: '',
);
