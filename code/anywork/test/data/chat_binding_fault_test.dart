import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anywork/src/data/bridge/studio_bridge.dart';
import 'package:anywork/src/data/frb/studio_api.dart';
import 'package:anywork/src/data/repositories/studio_api_provider.dart';
import 'package:anywork/src/data/stores/chat_view_events.dart';
import 'package:anywork/src/data/stores/chat_view_metrics.dart';
import 'package:anywork/src/data/stores/thread_directory_store.dart';
import 'package:anywork/src/data/stores/thread_session_store.dart';
import 'package:anywork/src/domain/models/studio_models.dart';

/// 候选安装：首帧验证成功之前，任何并发调用都不得把「有句柄、没有泵」的实例当 ready 复用。
///
/// 故障只加在首帧延迟上：状态流、目录与正文事实仍走 demo 的真实实现。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const threadId = 'thread-main';

  late ProviderContainer container;
  late BridgeTopicLeaseBundle shell;
  late ProviderSubscription<Object?> sessionHold;
  late _SlowInitial inner;
  late Completer<void> gate;

  setUp(() async {
    ChatViewEvents.reset();
    ChatViewMetrics.reset();
    gate = Completer<void>();
    inner = _SlowInitial(gate);
    container = ProviderContainer(
      overrides: [studioBridgeDataSourceProvider.overrideWithValue(inner)],
    );
    shell = container.read(studioBridgeProvider).acquireShellBundle();
    await _until(
      () => container.read(threadDirectoryStoreProvider).loaded,
      '目录基线',
    );
    sessionHold = container.listen(threadSessionStoreProvider(threadId), (
      _,
      _,
    ) {});
    await _until(
      () => container.read(threadSessionStoreProvider(threadId)).hasSnapshot,
      'Thread 快照',
    );
  });

  tearDown(() async {
    if (!gate.isCompleted) gate.complete();
    sessionHold.close();
    await shell.release();
    container.dispose();
  });

  test('首帧仍在途时的并发 chatView 不会交出没有泵的候选绑定', () async {
    final store = container.read(threadSessionStoreProvider(threadId).notifier);
    final first = store.chatView();
    // 让第一条打开进入 initial 等待，再发起第二次内容需求。
    await _until(() => inner.initialCalls >= 1, '首帧请求');
    final second = store.chatView();

    gate.complete();
    final a = await first;
    final b = await second;
    expect(a, isNotNull);
    expect(b, isNotNull);
    expect(
      identical(a, b),
      isTrue,
      reason: '并发内容需求必须复用同一条验证过的绑定',
    );
    expect(
      inner.openedWindowCount,
      1,
      reason: '首帧在途时不得重复开窗',
    );

    // 只有真正建立泵的绑定才能交付正文。
    await _until(
      () =>
          container.read(threadSessionStoreProvider(threadId)).items.isNotEmpty,
      '首窗正文',
    );
    expect(
      ChatViewEvents.ofKind(ChatViewEventKind.bindingOpened),
      hasLength(1),
    );
  });
}

/// 只延迟首帧的 demo 包装；其余能力全部转发，业务事实仍是 demo 的真实实现。
class _SlowInitial extends DemoStudioBridgeDataSource {
  _SlowInitial(this._gate) : super(lspActivityLoop: false) {
    chatWindowFactory = _wrap;
  }

  final Completer<void> _gate;
  int openedWindowCount = 0;
  int initialCalls = 0;

  Future<StudioChatWindow> _wrap(
    String threadId,
    StudioChatWindow window,
  ) async {
    openedWindowCount += 1;
    return _SlowWindow(this, window);
  }
}

class _SlowWindow implements StudioChatWindow {
  _SlowWindow(this._owner, this._inner);

  final _SlowInitial _owner;
  final StudioChatWindow _inner;

  @override
  Future<StudioChatSnapshot> initial() async {
    _owner.initialCalls += 1;
    await _owner._gate.future;
    return _inner.initial();
  }

  @override
  Future<StudioChatFrame?> next() => _inner.next();

  @override
  Future<void> close() => _inner.close();

  @override
  Future<StudioChatReceipt> load(TimelineDirection direction) =>
      _inner.load(direction);

  @override
  Future<StudioChatReceipt> extendLatest() => _inner.extendLatest();

  @override
  Future<StudioChatReceipt> focus(String? itemId) => _inner.focus(itemId);

  @override
  Future<StudioChatReceipt> expandItem(String itemId) =>
      _inner.expandItem(itemId);
}

Future<void> _until(
  bool Function() condition,
  String what, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('$what 未在 ${timeout.inSeconds} 秒内收敛');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
