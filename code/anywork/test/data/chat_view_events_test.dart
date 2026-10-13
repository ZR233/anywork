import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anywork/src/data/bridge/studio_bridge.dart';
import 'package:anywork/src/data/commands/thread_commands.dart';
import 'package:anywork/src/data/frb/studio_api.dart';
import 'package:anywork/src/data/repositories/studio_api_provider.dart';
import 'package:anywork/src/data/stores/chat_view_events.dart';
import 'package:anywork/src/data/stores/thread_directory_store.dart';
import 'package:anywork/src/data/stores/thread_session_store.dart';
import 'package:anywork/src/domain/models/studio_models.dart';

/// 真实内容泵路径上的逐事件记录：每个决定都要带身份与原因，才能把一次视觉闪动
/// 对应到具体的 binding、帧与校验，而不是只有全局累计计数。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const threadId = 'thread-main';

  late ProviderContainer container;
  late BridgeTopicLeaseBundle shell;
  late ProviderSubscription<Object?> sessionHold;

  setUp(() async {
    ChatViewEvents.reset();
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

  test('绑定建立按 opening -> opened 成对记录，并带首窗版本与容量事实', () async {
    final store = container.read(threadSessionStoreProvider(threadId).notifier);
    await store.chatView();
    await _until(
      () => container.read(threadSessionStoreProvider(threadId)).hasChatWindow,
      '内容窗口',
    );

    final opening = ChatViewEvents.ofKind(ChatViewEventKind.bindingOpening);
    final opened = ChatViewEvents.ofKind(ChatViewEventKind.bindingOpened);
    expect(opening, hasLength(1));
    expect(opened, hasLength(1));
    expect(opening.single.identity['thread'], threadId);
    expect(
      opened.single.identity['binding'],
      opening.single.identity['binding'],
    );
    expect(opening.single.sequence, lessThan(opened.single.sequence));
    expect(opened.single.details['version'], isNotNull);
    expect(opened.single.details['hasOlder'], isA<bool>());
    expect(opened.single.details['canExtendLatest'], isA<bool>());
  });

  test('首帧是 reset，流式增量是 patch，两者都带 binding 身份与版本区间', () async {
    final store = container.read(threadSessionStoreProvider(threadId).notifier);
    await store.chatView();
    await _until(
      () => container.read(threadSessionStoreProvider(threadId)).hasChatWindow,
      '内容窗口',
    );

    final resets = ChatViewEvents.ofKind(ChatViewEventKind.frameReset);
    expect(resets, isNotEmpty);
    expect(resets.first.identity['binding'], isNotNull);
    expect(resets.first.details['to'], isNotNull);

    final before = container.read(threadSessionStoreProvider(threadId));
    await container
        .read(threadCommandsProvider.notifier)
        .submitComposer(
          threadId,
          StudioPromptInput(
            inputId: 'input-event-1',
            text: '观测用例',
            attachmentDraftIds: const [],
          ),
        );
    await _until(
      () =>
          (container.read(threadSessionStoreProvider(threadId)).chatVersion ??
              0) >
          (before.chatVersion ?? 0),
      '流式增量',
    );

    final patches = ChatViewEvents.ofKind(ChatViewEventKind.framePatch);
    expect(patches, isNotEmpty);
    expect(
      patches.every((event) => event.identity['thread'] == threadId),
      isTrue,
      reason: '每条帧事件都必须能定位到会话',
    );
    expect(
      patches.any((event) => event.identity['binding'] != null),
      isTrue,
      reason: '帧事件必须带 binding 身份，才能区分换代前后的交付',
    );
    expect(
      patches.map((event) => event.details['to']),
      contains(
        container.read(threadSessionStoreProvider(threadId)).chatVersion,
      ),
    );
  });
}

Future<void> _until(bool Function() condition, String what) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('$what 未在 10 秒内收敛');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
