import 'package:flutter_test/flutter_test.dart';

import 'package:anywork/src/domain/models/studio_models.dart';

void main() {
  test(
    'partial live throughput stays unknown instead of using the old turn',
    () {
      final state = _stateWithRuntime(_runtimeWithLive(decodeMillis: 100));

      final projection = StudioThroughputProjection.fromState(state);

      expect(projection.completionTokens, 0);
      expect(projection.decodeMillis, 0);
      expect(statusBarThroughput(projection, state.runtime), isNull);
    },
  );

  test('complete live throughput owns the status value', () {
    final state = _stateWithRuntime(
      _runtimeWithLive(completionTokens: 25, decodeMillis: 1000),
    );

    final projection = StudioThroughputProjection.fromState(state);

    expect(projection.completionTokens, 25);
    expect(projection.decodeMillis, 1000);
    expect(projection.tokensPerSecond, 25);
    expect(statusBarThroughput(projection, state.runtime), 25);
  });

  test(
    'authoritative runtime is used only when no live observation exists',
    () {
      final state = _stateWithRuntime(
        const ThreadRuntimeView(
          model: 'fixture-model',
          contextTokens: 0,
          contextWindow: 128000,
          totalTokens: 100,
          costLabel: '-',
          activeSkills: <String>[],
          activeMcpServers: <String>[],
          activeLspServers: <String>[],
          turnCompletionTokens: 500,
          turnDecodeMillis: 100,
        ),
      );

      final projection = StudioThroughputProjection.fromState(state);

      expect(projection.completionTokens, 500);
      expect(projection.decodeMillis, 100);
      expect(statusBarThroughput(projection, state.runtime), 5000);
    },
  );

  test('zero live output with positive decode stays unknown', () {
    final state = _stateWithRuntime(
      _runtimeWithLive(completionTokens: 0, decodeMillis: 1000),
    );

    final projection = StudioThroughputProjection.fromState(state);

    expect(projection.tokensPerSecond, isNull);
    expect(statusBarThroughput(projection, state.runtime), isNull);
  });

  test('zero live decode with positive output stays unknown', () {
    final state = _stateWithRuntime(
      _runtimeWithLive(completionTokens: 25, decodeMillis: 0),
    );

    final projection = StudioThroughputProjection.fromState(state);

    expect(projection.tokensPerSecond, isNull);
    expect(statusBarThroughput(projection, state.runtime), isNull);
  });

  test('runtime fallback does not turn zero output into a speed', () {
    final state = _stateWithRuntime(
      const ThreadRuntimeView(
        model: 'fixture-model',
        contextTokens: 0,
        contextWindow: 128000,
        totalTokens: 100,
        costLabel: '-',
        activeSkills: <String>[],
        activeMcpServers: <String>[],
        activeLspServers: <String>[],
        turnCompletionTokens: 0,
        turnDecodeMillis: 1000,
      ),
    );

    expect(statusBarThroughput(null, state.runtime), isNull);
  });
}

ThreadRuntimeView _runtimeWithLive({int? completionTokens, int? decodeMillis}) {
  return ThreadRuntimeView(
    model: 'fixture-model',
    contextTokens: 0,
    contextWindow: 128000,
    totalTokens: 100,
    costLabel: '-',
    activeSkills: const <String>[],
    activeMcpServers: const <String>[],
    activeLspServers: const <String>[],
    turnCompletionTokens: 500,
    turnDecodeMillis: 100,
    liveUsage: ThreadRuntimeLiveUsageView(
      turnId: 'turn-1',
      attemptId: 'attempt-1',
      completionTokens: completionTokens,
      decodeMillis: decodeMillis,
      state: ThreadRuntimeUsageState.live,
      observationSequence: 1,
    ),
  );
}

StudioState _stateWithRuntime(ThreadRuntimeView runtime) {
  final thread = StudioThread(
    id: 'thread-1',
    projectId: 'project-1',
    title: 'Fixture thread',
    mode: ThreadModeId.simple,
    updatedAt: DateTime(2024, 1, 1),
    workspacePath: '/tmp/fixture-thread',
  );

  return StudioState(
    projectDirectory: ProjectDirectoryState(),
    threadDirectory: ThreadDirectoryWindow(threads: [thread]),
    agentDirectory: AgentDirectoryState(),
    settingsState: SettingsStateSnapshot(),
    recoveryState: RecoveryStateSnapshot(),
    mcpState: McpStateSnapshot(),
    lspState: LspStateSnapshot(),
    skillsByProject: const {},
    providerUsageState: ProviderUsageStateSnapshot(),
    updaterState: UpdaterStateSnapshot.idle(
      revision: 0,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
    ),
    selectedProjectId: 'project-1',
    selectedThreadId: 'thread-1',
    workspacesByThread: {
      'thread-1': ThreadWorkspace(
        thread: thread,
        revision: 1,
        items: const [],
        interactions: const [],
        runtime: runtime,
      ),
    },
  );
}
