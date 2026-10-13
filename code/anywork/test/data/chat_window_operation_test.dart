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
    final settled = _settledFor(token);
    expect(settled, hasLength(1));
    expect(settled.single.details['result'], 'noChange');
    expect(settled.single.identity['operation'], '$token');
    expect(
      settled.single.details['targetVersion'],
      isNull,
      reason: 'NoChange 不产生等待目标：它是在回执处直接收束的',
    );
    expect(settled.single.details['currentVersion'], version);
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
    expect(_settledFor(token).single.details['result'], 'alreadyObserved');
  });

  test('等待内容帧期间绑定被废弃时操作确定收束，不停在 loading', () async {
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
    // 回执指向一个比已交付更高的窗口版本：按设计要等内容帧。
    store.observeHistoryOp(
      token,
      StudioChatReceipt(operationId: token, version: version + 5, retained: true),
    );
    expect(
      container.read(threadSessionStoreProvider(threadId)).history.isLoading,
      isTrue,
      reason: 'Applied 操作要等匹配的窗口变化进入 read model',
    );

    // 绑定被重同步/关闭：目标版本不会再作为这一代绑定的帧到达。
    sessionHold.close();
    await _until(
      () =>
          !container.read(threadSessionStoreProvider(threadId)).history.isLoading,
      '绑定废弃后的收束',
    );

    expect(_settledFor(token).single.details['result'], 'bindingRetired');
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

/// 本操作自己的收束事件；同一会话的其它操作（含离开页面时的收束）不参与断言。
List<ChatViewEvent> _settledFor(int token) {
  return [
    for (final event in ChatViewEvents.ofKind(ChatViewEventKind.operationSettled))
      if (event.identity['operation'] == '$token') event,
  ];
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
