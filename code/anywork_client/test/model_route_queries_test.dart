import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

void main() {
  test('pending model intent cannot fabricate an observed route revision', () {
    const canonical = ThreadModelRouteView(
      providerId: 'provider',
      model: 'observed-model',
      effort: 'medium',
      revision: 19,
      available: true,
    );
    const pending = CommandStatus(
      key: 'thread-route',
      phase: CommandPhase.pending,
      target: CommandTarget(
        providerId: 'provider',
        model: 'removed-model',
        effort: 'high',
      ),
    );

    final display = ModelRouteQueries.threadRoute(
      canonical: canonical,
      command: pending,
      providers: [_provider],
    )!;
    expect(display.model, 'removed-model');
    expect(display.effort, 'high');
    expect(display.pending, isTrue);
    expect(display.available, isFalse);
    expect(canonical.model, 'observed-model');
    expect(canonical.revision, 19);

    final observed = ModelRouteQueries.threadRoute(
      canonical: canonical,
      command: null,
      providers: const [],
    )!;
    expect(observed.model, 'observed-model');
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
      providerId: 'provider',
      model: 'observed-model',
      effort: 'medium',
    );
    final route = ModelRouteQueries.startRoute(
      routes: [simple],
      commands: const {},
      draft: const StartSessionDraft(),
      mode: ThreadModeId.task,
    );
    expect(route.canonical, same(simple));
    expect(route.display!.providerId, 'provider');
    expect(route.display!.model, 'observed-model');
    expect(route.pending, isFalse);

    final configured = ModelRouteQueries.roleRoute(
      providers: [_provider],
      roles: const [
        RoleSettingsView(
          key: 'reviewer',
          providerId: 'removed-provider',
          model: 'removed-model',
          effort: 'high',
        ),
      ],
      role: 'reviewer',
    );
    expect(configured.providerId, 'removed-provider');
    expect(configured.model, 'removed-model');
    expect(configured.unavailable, isTrue);
    expect(configured.hasConfiguredRoute, isTrue);
    final unconfigured = ModelRouteQueries.roleRoute(
      providers: [_provider],
      roles: const [],
      role: 'new-agent',
    );
    expect(unconfigured.model, 'observed-model');
    expect(unconfigured.effort, 'medium');
    expect(unconfigured.hasConfiguredRoute, isFalse);
  });

  test('throughput uses only a complete sample from the current Turn', () {
    const runtime = ThreadRuntimeView(
      model: 'observed-model',
      contextTokens: 0,
      contextWindow: 0,
      totalTokens: 0,
      costLabel: '',
      activeSkills: [],
      activeMcpServers: [],
      activeLspServers: [],
      turnCompletionTokens: 1000,
      turnDecodeMillis: 1000,
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
          decodeMillis: sample.millis,
          state: ThreadRuntimeUsageState.live,
          observationSequence: 1,
        ),
      );
      expect(
        ModelRouteQueries.throughput(partial),
        isNull,
        reason: 'incomplete live sample $sample must not borrow old counters',
      );
    }
    final complete = runtime.copyWith(
      liveUsage: const ThreadRuntimeLiveUsageView(
        turnId: 'next-turn',
        attemptId: 'next-attempt',
        completionTokens: 20,
        decodeMillis: 500,
        state: ThreadRuntimeUsageState.live,
        observationSequence: 2,
      ),
    );
    expect(ModelRouteQueries.throughput(complete), 40);
  });

  test('model selection keeps a supported effort then a declared candidate default', () {
    const model = ProviderModelView(
      slug: 'observed-model',
      displayName: 'Observed model',
      reasoningEfforts: ['low', 'medium', 'high'],
      defaultReasoningEffort: 'medium',
    );
    expect(ModelRouteQueries.effortAfterModelSelection(model, 'high'), 'high');
    expect(ModelRouteQueries.effortAfterModelSelection(model, null), 'medium');

    const emptyDefault = ProviderModelView(
      slug: 'observed-model',
      displayName: 'Observed model',
      reasoningEfforts: ['low', 'high'],
    );
    expect(
      ModelRouteQueries.effortAfterModelSelection(emptyDefault, null),
      'low',
    );

    const mismatchedDefault = ProviderModelView(
      slug: 'observed-model',
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

    const emptyCatalog = ProviderModelView(
      slug: 'observed-model',
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

const _provider = ProviderSettingsView(
  id: 'provider',
  name: 'Provider',
  baseUrl: '',
  defaultModel: 'observed-model',
  models: [
    ProviderModelView(
      slug: 'observed-model',
      displayName: 'Observed model',
      reasoningEfforts: ['medium', 'high'],
      defaultReasoningEffort: 'medium',
    ),
  ],
  status: '',
  usageLabel: '',
);
