import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anywork/src/data/frb/studio_api.dart';
import 'package:anywork/src/data/repositories/studio_repository.dart';
import 'package:anywork/src/domain/models/studio_models.dart';

/// 回归证据：主界面的 session mode 与 reasoning effort 必须**不经过任何页面跳转**
/// 收敛到 canonical 事实。
///
/// 这两条用例覆盖的正是"改了不刷新、要往返设置页才生效"的两个结构性根因：
/// 1. 会话自身的状态流快照携带的 thread 身份（mode）曾被无条件丢弃，只能靠目录基线
///    页到达，而基线页是严格 `revision >` 门，因此不推进目录水位的 mode 变更永远
///    停在旧值；
/// 2. 阅读面可见性收敛曾是边沿触发：被取代的那一步在取消订阅之后、清账之前返回，
///    使客户端认为仍订阅着该会话而上游订阅已经取消，此后该会话的一切线程事实都不再
///    更新，直到下一次可见性调用恰好重置它。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const threadId = 'thread-main';
  const projectId = 'project-demo';

  group('thread 身份单调合并', () {
    test('会话快照能在目录水位不前进时修正 mode', () async {
      final api = DemoStudioBridgeDataSource(lspActivityLoop: false);
      final base = await api.readStudioState();
      final workspace = base.workspacesByThread[threadId];
      final directoryRow = base.threads
          .where((thread) => thread.id == threadId)
          .firstOrNull;
      expect(workspace, isNotNull, reason: 'demo fixture 应包含 $threadId');
      expect(directoryRow, isNotNull, reason: 'demo fixture 应包含目录行');
      expect(directoryRow!.mode, ThreadModeId.simple);

      // 目录窗口已经前进到某个水位：会话快照不携带目录水位，基线门会拒绝它。
      const directoryRevision = 7;
      final state = base.copyWith(
        selectedProjectId: projectId,
        selectedThreadId: threadId,
        threadDirectory: base.threadDirectory.copyWith(
          revision: directoryRevision,
        ),
      );
      final snapshot = workspace!.copyWith(
        thread: directoryRow.copyWith(mode: ThreadModeId.task),
        revision: workspace.revision + 1,
      );

      final next = applyThreadSnapshot(state, snapshot);

      expect(
        next.selectedThread?.mode,
        ThreadModeId.task,
        reason: '会话自身的 canonical 快照必须能修正 mode（selector 文案与选中态同源）',
      );
      expect(next.workspacesByThread[threadId]!.thread.mode, ThreadModeId.task);
      expect(
        next.threadDirectory.revision,
        directoryRevision,
        reason: '快照不是目录基线，不得推进目录水位',
      );
    });

    test('更旧的会话快照不得覆盖目录里更新的事实', () async {
      final api = DemoStudioBridgeDataSource(lspActivityLoop: false);
      final base = await api.readStudioState();
      final workspace = base.workspacesByThread[threadId]!;
      final directoryRow = base.threads
          .where((thread) => thread.id == threadId)
          .firstOrNull!;
      final newest = directoryRow.copyWith(
        mode: ThreadModeId.task,
        updatedAt: directoryRow.updatedAt.add(const Duration(minutes: 5)),
      );
      final state = base.copyWith(
        selectedProjectId: projectId,
        selectedThreadId: threadId,
        threadDirectory: base.threadDirectory.copyWith(
          threads: [
            for (final thread in base.threadDirectory.threads)
              if (thread.id == threadId) newest else thread,
          ],
        ),
      );

      final next = applyThreadSnapshot(
        state,
        workspace.copyWith(
          thread: directoryRow.copyWith(
            mode: ThreadModeId.simple,
            updatedAt: directoryRow.updatedAt,
          ),
          revision: workspace.revision + 1,
        ),
      );

      expect(next.selectedThread?.mode, ThreadModeId.task);
      expect(next.workspacesByThread[threadId]!.thread.mode, ThreadModeId.task);
    });
  });

  group('阅读面可见性收敛', () {
    test('取消订阅在途时恢复可见，线程状态流仍然存活（无需第二次往返）', () async {
      final api = _BlockingCancelBridge();
      final container = ProviderContainer(
        overrides: [studioBridgeDataSourceProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      final controller = container.read(studioControllerProvider.notifier);
      await container.read(studioControllerProvider.future);
      await controller.openSelectedThread();
      final opened = container.read(studioControllerProvider).value!;
      expect(opened.selectedThreadId, threadId);
      expect(opened.openedThreadIds, contains(threadId));

      // 离开设置页的取消订阅仍在途时用户就返回：这正是旧实现留下"账实不符"的窗口
      // （上游订阅已取消，`_subscribedThreadId` 仍声称已订阅），此后线程事实全部丢失，
      // 直到下一次可见性调用恰好重置它——用户侧的观感就是"要再往返一次"。
      api.blockCancel = true;
      final subscribesBefore = api.subscribeCalls;
      final leaving = controller.setConversationVisible(false);
      await api.cancelStarted.future;
      final returning = controller.setConversationVisible(true);
      api.cancelReleased.complete();
      await leaving;
      await returning;
      api.blockCancel = false;
      // 收敛后的重新订阅由协调器异步附加监听：等到订阅确实建立，才允许后续事件交付
      // （真实 bridge 上这个窗口同样存在，事实的最终收敛由 canonical 快照/响应保证）。
      await _awaitCondition(() => api.subscribeCalls > subscribesBefore);

      // 只有上游订阅仍然存活时，这个只经状态流交付的 route 变更才能到达客户端。
      final before = container
          .read(studioControllerProvider)
          .value!
          .workspacesByThread[threadId]!
          .runtime
          .modelRoute!;
      final snapshot = await api.readStudioState();
      final target = snapshot.settingsState.modeModelRoutes
          .where((route) => route.modeId == ThreadModeId.task)
          .firstOrNull;
      expect(target, isNotNull, reason: 'demo fixture 应有 task mode 默认路由');
      final model = snapshot.providers
          .where((provider) => provider.id == target!.providerId)
          .firstOrNull
          ?.allModels
          .where((candidate) => candidate.slug == target!.model)
          .firstOrNull;
      expect(model, isNotNull, reason: 'task 默认路由必须指向一个已知模型');
      final nextEffort = model!.reasoningEfforts
          .where((effort) => effort != before.effort)
          .firstOrNull;
      expect(nextEffort, isNotNull, reason: '模型需要至少两个思考强度候选，才能观察 route 变化');
      await api.setThreadModelRoute(
        threadId: threadId,
        expectedModelRouteRevision: before.revision,
        expectedSettingsRevision: snapshot.settingsState.revision,
        providerId: target!.providerId,
        model: target.model,
        effort: nextEffort,
      );

      final delivered = await _awaitRoute(
        container,
        threadId,
        (route) => route.effort == nextEffort,
      );
      expect(
        delivered?.effort,
        nextEffort,
        reason: '设置页往返后线程状态流必须仍然交付事实，不能依赖再往返一次',
      );
    });
  });
}

/// 让"取消订阅"可被测试挂起：只有测试显式放行，旧订阅的取消才完成。
///
/// 生产上的取消要跨越 bridge，用户快速进入并返回设置页时它会短暂在途；这里把同一
/// 窗口变成确定时序，使回归用例不依赖真实耗时。
final class _BlockingCancelBridge extends DemoStudioBridgeDataSource {
  _BlockingCancelBridge() : super(lspActivityLoop: false);

  final Completer<void> cancelStarted = Completer<void>();
  final Completer<void> cancelReleased = Completer<void>();
  bool blockCancel = false;

  /// 协调器实际附加监听的次数：用于等到重新订阅确实建立（事件不会发给尚未附加的订阅）。
  int subscribeCalls = 0;

  @override
  Stream<ThreadStreamFrame> subscribeThread(String threadId) {
    subscribeCalls += 1;
    final source = super.subscribeThread(threadId);
    late final StreamController<ThreadStreamFrame> controller;
    StreamSubscription<ThreadStreamFrame>? subscription;
    controller = StreamController<ThreadStreamFrame>(
      onListen: () {
        subscription = source.listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
      },
      onCancel: () async {
        if (blockCancel) {
          if (!cancelStarted.isCompleted) cancelStarted.complete();
          await cancelReleased.future;
        }
        await subscription?.cancel();
      },
    );
    return controller.stream;
  }
}

/// 有界等待一个条件成立，用于跨越"协调器已入队但尚未附加监听"的窗口。
Future<void> _awaitCondition(bool Function() ready) async {
  for (var attempt = 0; attempt < 40; attempt += 1) {
    if (ready()) return;
    await Future<void>.delayed(Duration.zero);
  }
}

Future<ThreadModelRouteView?> _awaitRoute(
  ProviderContainer container,
  String threadId,
  bool Function(ThreadModelRouteView route) matches,
) async {
  for (var attempt = 0; attempt < 40; attempt += 1) {
    final state = container.read(studioControllerProvider).value;
    final route = state?.workspacesByThread[threadId]?.runtime.modelRoute;
    if (route != null && matches(route)) return route;
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  return container
      .read(studioControllerProvider)
      .value
      ?.workspacesByThread[threadId]
      ?.runtime
      .modelRoute;
}
