import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anywork/src/data/bridge/studio_bridge.dart';
import 'package:anywork/src/data/commands/thread_commands.dart';
import 'package:anywork/src/data/frb/studio_api.dart';
import 'package:anywork/src/data/repositories/studio_api_provider.dart';
import 'package:anywork/src/data/stores/chat_view_metrics.dart';
import 'package:anywork/src/data/stores/thread_directory_store.dart';
import 'package:anywork/src/data/stores/thread_session_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const threadId = 'thread-main';

  late ProviderContainer container;
  late BridgeTopicLeaseBundle shell;
  late ProviderSubscription<Object?> sessionHold;

  setUp(() async {
    ChatViewMetrics.reset();
    final api = DemoStudioBridgeDataSource(lspActivityLoop: false);
    container = ProviderContainer(
      overrides: [studioBridgeDataSourceProvider.overrideWithValue(api)],
    );
    shell = container.read(studioBridgeProvider).acquireShellBundle();
    await _until(
      () => container.read(threadDirectoryStoreProvider).loaded,
      '目录基线',
    );
    sessionHold = container.listen(
      threadSessionStoreProvider(threadId),
      (_, _) {},
    );
    await _until(
      () => container.read(threadSessionStoreProvider(threadId)).hasSnapshot,
      'Thread 快照',
    );
  });

  tearDown(() async {
    sessionHold.close();
    await shell.release();
    container.dispose();
  });

  test('迟到的旧订阅清理不能清空已经恢复的窗口', () async {
    final store = container.read(threadSessionStoreProvider(threadId).notifier);
    await store.chatView();
    await _until(
      () =>
          container.read(threadSessionStoreProvider(threadId)).items.isNotEmpty,
      '首窗正文',
    );
    final before = container.read(threadSessionStoreProvider(threadId)).items;
    expect(before, isNotEmpty);

    store.holdNextSubscriptionRelease();
    sessionHold.close();
    await Future<void>.delayed(Duration.zero);

    sessionHold = container.listen(
      threadSessionStoreProvider(threadId),
      (_, _) {},
    );
    await store.chatView();
    await _until(
      () =>
          container.read(threadSessionStoreProvider(threadId)).items.isNotEmpty,
      '恢复后的正文',
    );
    final restored = container.read(threadSessionStoreProvider(threadId)).items;
    expect(restored, isNotEmpty);

    store.releaseHeldSubscription();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final after = container.read(threadSessionStoreProvider(threadId));
    expect(after.items.map((item) => item.id), restored.map((item) => item.id));
    expect(ChatViewMetrics.historyClears, 0);
  });

  test('extendLatest 在窗口不能扩充时结束 loading，不永久等待内容帧', () async {
    final store = container.read(threadSessionStoreProvider(threadId).notifier);
    await store.chatView();
    await _until(
      () => container.read(threadSessionStoreProvider(threadId)).hasChatWindow,
      '内容窗口',
    );
    expect(
      container
          .read(threadSessionStoreProvider(threadId))
          .history
          .canExtendLatest,
      isFalse,
    );

    await container
        .read(threadCommandsProvider.notifier)
        .extendLatestHistory(threadId);

    expect(ChatViewMetrics.extendLatestCalls, 0);
    expect(
      container.read(threadSessionStoreProvider(threadId)).history.isLoading,
      isFalse,
    );
  });
}

Future<void> _until(bool Function() condition, String what) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('$what 未在 5 秒内收敛');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
