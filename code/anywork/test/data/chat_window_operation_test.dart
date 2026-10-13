import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anywork/src/data/bridge/studio_bridge.dart';
import 'package:anywork/src/data/frb/studio_api.dart';
import 'package:anywork/src/data/repositories/studio_api_provider.dart';
import 'package:anywork/src/data/stores/chat_view_events.dart';
import 'package:anywork/src/data/stores/thread_directory_store.dart';
import 'package:anywork/src/data/stores/thread_session_store.dart';
import 'package:anywork/src/domain/models/studio_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const threadId = 'thread-main';

  late ProviderContainer container;
  late BridgeTopicLeaseBundle shell;
  late ProviderSubscription<Object?> sessionHold;

  setUp(() async {
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

  test('同一窗口方向在途时拒绝第二个 load 占位', () async {
    final store = container.read(threadSessionStoreProvider(threadId).notifier);
    final first = store.beginHistoryOp(TimelineDirection.older);
    final second = store.beginHistoryOp(TimelineDirection.older);
    expect(first, isNotNull);
    expect(second, isNull);
    expect(
      container.read(threadSessionStoreProvider(threadId)).history.isLoading,
      isTrue,
    );
  });

  test('回执版本未超过已观察窗口时按 NoChange 结束，不等待内容帧', () async {
    final store = container.read(threadSessionStoreProvider(threadId).notifier);
    await store.chatView();
    await _until(
      () =>
          container.read(threadSessionStoreProvider(threadId)).chatVersion !=
          null,
      '窗口版本',
    );
    final version = container
        .read(threadSessionStoreProvider(threadId))
        .chatVersion!;
    final token = store.beginHistoryOp(TimelineDirection.older);
    expect(token, isNotNull);
    store.observeHistoryOp(
      token!,
      StudioChatReceipt(operationId: token, version: version, retained: true),
    );
    expect(
      container.read(threadSessionStoreProvider(threadId)).history.isLoading,
      isFalse,
    );
  });

  test('回执版本等于窗口交付版本时按 NoChange 结束并留下可核对的事实', () async {
    ChatViewEvents.reset();
    final store = container.read(threadSessionStoreProvider(threadId).notifier);
    await store.chatView();
    await _until(
      () =>
          container.read(threadSessionStoreProvider(threadId)).chatVersion !=
          null,
      '窗口版本',
    );
    final version = container
        .read(threadSessionStoreProvider(threadId))
        .chatVersion!;
    final token = store.beginHistoryOp(TimelineDirection.older)!;
    store.observeHistoryOp(
      token,
      StudioChatReceipt(operationId: token, version: version, retained: true),
    );

    expect(
      container.read(threadSessionStoreProvider(threadId)).history.isLoading,
      isFalse,
    );
    final settled = ChatViewEvents.ofKind(ChatViewEventKind.operationSettled);
    expect(settled, hasLength(1));
    expect(settled.single.details['result'], 'noChange');
    expect(settled.single.identity['operation'], '$token');
    expect(
      ChatViewEvents.ofKind(
        ChatViewEventKind.operationSettled,
      ).single.details['currentVersion'],
      version,
    );
  });

  test('内容帧先于回执到达时按 alreadyObserved 结束', () async {
    ChatViewEvents.reset();
    final store = container.read(threadSessionStoreProvider(threadId).notifier);
    await store.chatView();
    await _until(
      () =>
          container.read(threadSessionStoreProvider(threadId)).chatVersion !=
          null,
      '窗口版本',
    );
    final version = container
        .read(threadSessionStoreProvider(threadId))
        .chatVersion!;
    final token = store.beginHistoryOp(TimelineDirection.older)!;
    // 帧已经交付到更高版本：回执只是确认，不再等第二个帧。
    store.observeHistoryOp(
      token,
      StudioChatReceipt(
        operationId: token,
        version: version - 1,
        retained: true,
      ),
    );

    expect(
      container.read(threadSessionStoreProvider(threadId)).history.isLoading,
      isFalse,
    );
    expect(
      ChatViewEvents.ofKind(
        ChatViewEventKind.operationSettled,
      ).single.details['result'],
      'alreadyObserved',
    );
  });

  test('旧操作不能结束后提交的新占位', () async {
    final store = container.read(threadSessionStoreProvider(threadId).notifier);
    final oldToken = store.beginHistoryOp(TimelineDirection.older)!;
    store.finishHistoryLoad();
    final newToken = store.beginHistoryOp(TimelineDirection.newer)!;
    expect(newToken, isNot(oldToken));
    store.observeHistoryOp(
      oldToken,
      const StudioChatReceipt(operationId: 1, version: 1, retained: true),
    );
    expect(
      container.read(threadSessionStoreProvider(threadId)).history.isLoading,
      isTrue,
    );
    expect(
      container.read(threadSessionStoreProvider(threadId)).history.direction,
      TimelineDirection.newer,
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
