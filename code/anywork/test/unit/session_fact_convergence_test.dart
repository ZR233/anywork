import '../support/test_app_lifecycle.dart';
import '../support/chat_fixtures.dart';
import '../support/recording_demo_transport.dart';

import '../support/test_statistics_feed.dart';

import 'package:anywork/src/presentation/providers/client_provider.dart';
import 'package:anywork/src/features/conversation/composer/state/composer_view_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork_client/studio_client.dart';

import 'package:anywork/src/presentation/providers/account_domains.dart';
import 'package:anywork/src/presentation/providers/settings_store.dart';
import 'package:anywork/src/presentation/providers/thread_session_store.dart';
import 'package:anywork/src/features/conversation/composer/view_models/composer_view_model.dart';

/// AppGraph/Riverpod 适配契约：改动“任务模式 / 思考强度”后，主界面的显示值必须**只由
/// canonical 事实流收敛**——mode 走定向元数据观察，Thread route 走 Thread 有序流。
///
/// 这里用 AppGraph/Client owner 与只读 Riverpod adapter，只把
/// transport 换成 Demo；它不证明 native FRB，但 Demo
/// 少发任何一条真实侧会发的帧，本文件就会失败，而不会被“命令后重新读取”这类补偿
/// 路径掩盖（design/25 §25.5：命令成功以响应 canonical 应用回 store，不额外触发
/// 显式刷新）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const threadId = 'thread-main';

  late AppGraph graph;
  late RecordingDemoTransport transport;
  late ProviderContainer container;
  late ProviderSubscription<Object?> sessionHold;
  late ProviderSubscription<Object?> composerHold;

  setUp(() async {
    transport = RecordingDemoTransport();
    graph = testAppGraph(
      statisticsFeed: const TestStatisticsFeedPort(),
      transport: transport,
      clientId: 'canonical-convergence',
    );
    container = ProviderContainer(
      overrides: [appGraphProvider.overrideWithValue(graph)],
    );
    await graph.client.bootstrap();
    await (graph
          ..timeline.updateReadDemand(chatDemand)
          ..setConversationPageVisible(true))
        .client
        .directoryCommands
        .selectThread(threadId);
    sessionHold = container.listen(
      threadSessionStoreProvider(threadId),
      (_, _) {},
    );
    composerHold = container.listen(
      composerViewModelProvider(ComposerTarget.thread(threadId: threadId)),
      (_, _) {},
    );
    await graph.client.conversations
        .session(threadId)
        .source
        .waitFor((s) => s.hasSnapshot);
    const limit = Duration(seconds: 5);
    await graph.accounts.state.waitFor((state) => state.loaded).timeout(limit);
    await graph.models.state
        .waitFor(
          (state) => state.accounts.values.any(
            (resource) =>
                resource.loaded && resource.value?.models.isNotEmpty == true,
          ),
        )
        .timeout(limit);
  });

  tearDown(() async {
    sessionHold.close();
    composerHold.close();
    container.dispose();
    final report = await graph.close(
      budget: ClientCloseBudget(const Duration(seconds: 5)),
    );
    expect(
      report.complete,
      isTrue,
      reason: report.unresolved
          .map((value) => '${value.owner}: ${value.reason}')
          .join('; '),
    );
  });

  int routeRevision() => _routeRevision(container, threadId);

  AccountModelView? modelFor(String accountId, String model) =>
      _modelFor(container, accountId, model);

  test('任务模式由定向元数据交付，Thread route 由状态帧交付', () async {
    await transport.saveThreadModeDefinition(
      const ModeDocument(
        definition: ModeDefinition(
          id: 'mode.custom',
          displayName: '自定义',
          description: '自定义模式',
          order: 1,
          prompt: '',
        ),
      ),
      expectedRevision: 1,
      operationId: const OperationId('seed-custom-mode-convergence'),
    );
    final customMode = ThreadModeId.fromId('mode.custom');
    expect(
      container
          .read(
            composerViewModelProvider(
              ComposerTarget.thread(threadId: threadId),
            ),
          )
          .requireValue
          .thread!
          .row
          ?.mode,
      ThreadModeId.auto,
      reason: 'demo fixture 的根会话默认是自动模式',
    );
    final routeRevisionBefore = routeRevision();
    final directory = graph.client.threadDirectory.observeThread(threadId);
    try {
      final initial = await directory.state
          .waitFor((state) => state.frame != null)
          .timeout(const Duration(seconds: 5));
      final directoryRevisionBefore = initial.frame!.stamp.revision;

      await container
          .read(anyworkClientProvider)
          .threadCommands
          .setThreadMode(customMode, threadId: threadId);

      await graph.client.conversations
          .session(threadId)
          .source
          .waitFor((s) => s.modelRoute?.revision == routeRevisionBefore + 1);
      final updated = await directory.state.waitFor(
        (state) => state.frame?.row?.mode == customMode,
      );
      expect(
        updated.frame!.stamp.revision,
        greaterThan(directoryRevisionBefore),
        reason: 'mode 是目录事实：必须由受控窗口的新完整帧交付',
      );
      expect(
        routeRevision(),
        routeRevisionBefore + 1,
        reason:
            'mode 默认 route 是 Thread 状态事实，必须由有序流帧交付；'
            '命令后重新读取会掩盖这里缺帧',
      );
    } finally {
      await directory.release();
    }
  });

  test('思考强度由 Thread 有序流收敛，命令响应只合并 settings', () async {
    final route = container
        .read(
          composerViewModelProvider(ComposerTarget.thread(threadId: threadId)),
        )
        .requireValue
        .thread!
        .modelRoute;
    expect(route, isNotNull, reason: '已建会话必须有 canonical route');
    final canonicalRoute = route!;

    final model = modelFor(canonicalRoute.accountId, canonicalRoute.modelId);
    expect(model, isNotNull, reason: '当前 route 的模型必须在 account 目录中');
    final target = model!.reasoningEfforts
        .where((effort) => effort != canonicalRoute.effort)
        .firstOrNull;
    expect(target, isNotNull, reason: '模型需要至少两个思考强度候选');
    final routeRevisionBefore = routeRevision();

    await container
        .read(anyworkClientProvider)
        .threadCommands
        .setThreadModelRoute(
          threadId: threadId,
          accountId: canonicalRoute.accountId,
          modelId: canonicalRoute.modelId,
          effort: target,
        );

    await graph.client.conversations
        .session(threadId)
        .source
        .waitFor(
          (state) =>
              state.modelRoute?.revision == routeRevisionBefore + 1 &&
              state.modelRoute?.effort == target,
        );

    expect(
      container.read(threadSessionStoreProvider(threadId)).modelRoute?.effort,
      target,
      reason: 'canonical 事实必须经 Thread 帧收敛，不能停留在乐观目标值',
    );
    expect(
      routeRevision(),
      routeRevisionBefore + 1,
      reason: 'route 变更必须带新的模型路由 revision 到达 store',
    );
    final settled = container
        .read(
          composerViewModelProvider(ComposerTarget.thread(threadId: threadId)),
        )
        .requireValue
        .thread!;
    expect(settled.routePending, isFalse, reason: '命令完成后不得停在 pending 目标值');
    expect(
      settled.modelRoute?.effort,
      target,
      reason: '选择器显示值必须与收敛后的 canonical 一致（乐观值清除后不回落）',
    );
    expect(
      container
          .read(settingsStoreProvider)
          .canonical
          ?.modeModelRoutes
          .where((candidate) => candidate.modeId == settled.row?.mode)
          .firstOrNull
          ?.effort,
      target,
      reason: '命令响应的 settings canonical 是同一水位下的另一半事实',
    );
  });
}

int _routeRevision(ProviderContainer container, String threadId) =>
    container.read(threadSessionStoreProvider(threadId)).modelRoute?.revision ??
    -1;

AccountModelView? _modelFor(
  ProviderContainer container,
  String accountId,
  String model,
) => ModelRouteQueries.model(
  container.read(modelSelectionAccountsProvider),
  accountId,
  model,
);
