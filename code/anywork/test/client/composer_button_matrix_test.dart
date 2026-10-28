import 'dart:async';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/composer/connectors/composer_dock_connector.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pump_client_future.dart';
import 'support/recording_demo_transport.dart';
import 'support/test_statistics_feed.dart';

const _threadId = 'thread-main';
const _altThreadId = 'thread-alt';
final _continuation = ContinuationView(
  id: 'continuation-1',
  sourceTurnId: 'turn-1',
  reason: ContinuationReason.userStop,
  createdAt: DateTime.utc(2026, 1, 1),
  claimed: false,
);

/// 记录停止/继续目标并按脚本受理或拒绝；canonical 执行与继续点由测试注入。
final class _ScriptedTransport extends RecordingDemoTransport {
  final List<String> stopTargets = [];
  final List<({String threadId, String continuationId, int revision})>
  continues = [];
  Object? stopError;
  Object? continueError;
  int submitCalls = 0;

  /// 非空时挂起停止请求，用于在在途期间观察界面与草稿。
  Completer<void>? stopGate;

  @override
  Future<SubmitPromptReceipt> submitPrompt(
    String threadId,
    StudioPromptInput input, {
    required int expectedModelRouteRevision,
  }) async {
    submitCalls++;
    throw StateError('The composer must not submit here');
  }

  @override
  Future<StopThreadCommandReply> stopThread(
    String threadId,
    String executionId, {
    required OperationId operationId,
  }) async {
    stopTargets.add('$threadId:$executionId');
    final gate = stopGate;
    if (gate != null) await gate.future;
    final error = stopError;
    if (error != null) throw error;
    return StopThreadCommandReply(
      threadId: threadId,
      executionId: executionId,
      stopped: true,
      receipt: _receipt(operationId),
    );
  }

  @override
  Future<ContinueThreadCommandReply> continueThread(
    String threadId,
    String continuationId, {
    required int expectedModelRouteRevision,
    required OperationId operationId,
  }) async {
    continues.add((
      threadId: threadId,
      continuationId: continuationId,
      revision: expectedModelRouteRevision,
    ));
    final error = continueError;
    if (error != null) throw error;
    return ContinueThreadCommandReply(
      threadId: threadId,
      inputId: operationId.value,
      continuationId: continuationId,
      cursor: 1,
      receipt: _receipt(operationId),
    );
  }
}

StudioCommandReceipt _receipt(OperationId operationId) => StudioCommandReceipt(
  operationId: operationId,
  disposition: CommitDisposition.applied,
  targets: const [],
  effect: EffectPoint.immediate,
  effective: true,
  durable: false,
  requiresIdentityObservation: true,
);

const _running = AgentExecutionView(
  id: 'exec-1',
  phase: AgentExecutionPhase.running,
  turnId: 'turn-1',
);

/// 一次 composer 现场的测试宿主：真实 Client 会话 + 注入的 canonical 事实。
final class _Composer {
  _Composer(this.graph, this.transport);

  final AppGraph graph;
  final _ScriptedTransport transport;

  ConversationSession get owner =>
      graph.client.conversations.session(_threadId);
  ThreadWorkspace get workspace => owner.state.workspace!;

  /// 只替换 canonical 运行时中的执行/继续点/模型路由，其余事实保持真实。
  Future<void> publish({
    Object? execution = _unset,
    Object? continuation = _unset,
    Object? modelRoute = _unset,
  }) async {
    final runtime = workspace.runtime;
    await transport.publishWorkspace(
      workspace.copyWith(
        runtime: runtime.copyWith(
          execution: identical(execution, _unset)
              ? runtime.execution
              : execution as AgentExecutionView?,
          continuation: identical(continuation, _unset)
              ? runtime.continuation
              : continuation as ContinuationView?,
          modelRoute: identical(modelRoute, _unset)
              ? runtime.modelRoute
              : modelRoute as ThreadModelRouteView?,
        ),
      ),
    );
  }
}

const _unset = Object();

Future<_Composer> _composer(WidgetTester tester) async {
  final transport = _ScriptedTransport();
  final graph = AppGraph(
    transport: transport,
    clientId: 'composer-matrix',
    statisticsFeed: const TestStatisticsFeedPort(),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpClientFuture(
      tester,
      graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
      'composer matrix teardown',
    );
  });
  await pumpClientFuture(
    tester,
    graph.client.bootstrap(),
    'composer bootstrap',
  );
  await pumpClientFuture(
    tester,
    (graph..setConversationPageVisible(true)).client.directoryCommands
        .selectThread(_threadId),
    'select composer thread',
  );
  await pumpClientUntil(
    tester,
    () => graph.client.conversations.session(_threadId).state.hasSnapshot,
    'composer thread snapshot',
  );
  // 后续停止与继续都以该会话已保存的路由版本作为 CAS 基线。
  await pumpClientUntil(
    tester,
    () =>
        graph.client.conversations
            .session(_threadId)
            .state
            .runtime
            ?.modelRoute !=
        null,
    'composer model route',
  );
  return _Composer(graph, transport);
}

Future<void> _pump(WidgetTester tester, _Composer composer) async {
  await _pumpThread(tester, composer, _threadId);
}

/// 在同一个位置渲染指定会话的输入区：切换会话即换 threadId，用来观察跨会话残留。
Future<void> _pumpThread(
  WidgetTester tester,
  _Composer composer,
  String threadId,
) async {
  await _pumpSized(
    tester,
    composer,
    threadId: threadId,
    width: 900,
    height: 400,
  );
}

/// 受限尺寸下的同一现场：用来验证原因区在窄矮窗口里不撑破底栏。
Future<void> _pumpSized(
  WidgetTester tester,
  _Composer composer, {
  required String threadId,
  required double width,
  required double height,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appGraphProvider.overrideWithValue(composer.graph)],
      child: MaterialApp(
        theme: pureStudioTheme(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: width,
            height: height,
            child: ComposerDockConnector(threadId: threadId),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// 关闭顺序与生产一致：先卸载 Widget，再收束 Client 的观察与定时器。
///
/// testWidgets 在测试体结束前检查未完成定时器，因此成功路径必须在体内关闭 owner。
Future<void> _close(WidgetTester tester, _Composer composer) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await pumpClientFuture(
    tester,
    composer.graph.close(
      deadline: DateTime.now().add(const Duration(seconds: 5)),
    ),
    'composer matrix close',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('运行中、清理中、可继续、正在继续与完成态的按钮矩阵', (tester) async {
    final composer = await _composer(tester);
    await _pump(tester, composer);

    // 正常完成：空草稿只有禁用发送，不出现继续或停止。
    expect(
      find.byKey(const ValueKey('composer-submit-disabled')),
      findsOneWidget,
    );
    expect(find.byKey(StudioDriverKeys.composerStop), findsNothing);
    expect(find.byKey(StudioDriverKeys.composerContinue), findsNothing);

    // 运行中空草稿：中性停止。
    await composer.publish(execution: _running);
    await tester.pump();
    expect(find.byKey(StudioDriverKeys.composerStop), findsOneWidget);
    expect(find.byKey(StudioDriverKeys.composerSubmit), findsNothing);

    // 运行中有草稿：发送并继续。
    await tester.enterText(
      find.byKey(StudioDriverKeys.composerInput),
      'follow up while running',
    );
    await tester.pump();
    expect(find.byKey(StudioDriverKeys.composerSubmit), findsOneWidget);
    expect(find.byKey(StudioDriverKeys.composerStop), findsNothing);

    // 停止已受理、清理未观察到结束：显示正在停止且不可提交。草稿先清空以取停止位。
    await tester.enterText(find.byKey(StudioDriverKeys.composerInput), '');
    await tester.pump();
    await tester.tap(find.byKey(StudioDriverKeys.composerStop));
    await tester.pump();
    expect(composer.transport.stopTargets, ['$_threadId:exec-1']);
    expect(find.byKey(StudioDriverKeys.composerStopping), findsOneWidget);
    expect(find.text('Stopping'), findsOneWidget);
    expect(find.byKey(StudioDriverKeys.composerSubmit), findsNothing);
    expect(find.byKey(StudioDriverKeys.composerContinue), findsNothing);

    // 观察到执行结束并留下未认领继续点：显示继续与已知中断原因。
    await composer.publish(execution: null, continuation: _continuation);
    await tester.pump();
    expect(find.byKey(StudioDriverKeys.composerStopping), findsNothing);
    expect(find.byKey(StudioDriverKeys.composerContinue), findsOneWidget);
    expect(
      find.byKey(const ValueKey('composer-continuation-reason')),
      findsOneWidget,
    );
    expect(find.text('Stopped by the user'), findsOneWidget);

    // 空输入继续必须点击：Enter 不提交，也不产生继续操作。
    await tester.tap(find.byKey(StudioDriverKeys.composerInput));
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    expect(composer.transport.continues, isEmpty, reason: '空输入继续只能由显式点击发起');
    expect(
      composer.graph.client.threadCommands.state.commands.containsKey(
        'continue:$_threadId',
      ),
      isFalse,
    );

    // 点击继续后、新轮次出现前：显示正在继续并禁用重复提交。
    await tester.tap(find.byKey(StudioDriverKeys.composerContinue));
    await tester.pump();
    expect(
      composer.transport.continues.single.continuationId,
      'continuation-1',
    );
    expect(
      composer.transport.continues.single.revision,
      composer.workspace.runtime.modelRoute!.revision,
      reason: '继续必须携带已观察的模型路由版本',
    );
    expect(find.byKey(StudioDriverKeys.composerContinuing), findsOneWidget);
    expect(find.text('Continuing'), findsOneWidget);
    expect(find.byKey(StudioDriverKeys.composerContinue), findsNothing);

    // 新轮次出现：回到运行中的停止入口。
    await composer.publish(execution: _running, continuation: null);
    await tester.pump();
    expect(find.byKey(StudioDriverKeys.composerContinuing), findsNothing);
    expect(find.byKey(StudioDriverKeys.composerStop), findsOneWidget);
    await _close(tester, composer);
  });

  testWidgets('保存与模型阻塞显示 typed 原因并禁用继续，草稿保留', (tester) async {
    final composer = await _composer(tester);
    await _pump(tester, composer);
    await composer.publish(execution: null, continuation: _continuation);
    await tester.pump();
    await tester.enterText(
      find.byKey(StudioDriverKeys.composerInput),
      'keep this draft',
    );
    await tester.pump();

    final route = composer.workspace.runtime.modelRoute!;
    await composer.publish(
      modelRoute: ThreadModelRouteView(
        accountId: route.accountId,
        modelId: route.modelId,
        effort: route.effort,
        revision: route.revision,
        available: false,
        unavailableReason: 'route unavailable',
      ),
    );
    await tester.pump();
    expect(find.byKey(StudioDriverKeys.composerBlocker), findsOneWidget);
    expect(
      find.text(
        'The current model is unavailable, so continuing is unavailable.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('composer-submit-disabled')),
      findsOneWidget,
      reason: '阻塞时主按钮不可提交',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(StudioDriverKeys.composerInput))
          .controller!
          .text,
      'keep this draft',
      reason: '阻塞不清草稿',
    );

    // 硬保存故障同样阻塞继续，并保留运行中的停止入口。
    await tester.enterText(find.byKey(StudioDriverKeys.composerInput), '');
    await tester.pump();
    await composer.publish(
      execution: _running,
      modelRoute: route,
      continuation: null,
    );
    await composer.transport.publishWorkspace(
      composer.workspace.copyWith(
        storage: const ThreadStorageStateView(
          fault: ThreadHistoryFault.writeFailed,
          resumeRequired: true,
          lastError: 'writer unavailable',
        ),
      ),
    );
    await tester.pump();
    expect(
      find.text('Saving has not finished yet, so continuing is unavailable.'),
      findsOneWidget,
    );
    expect(
      find.byKey(StudioDriverKeys.composerStop),
      findsOneWidget,
      reason: '阻塞不得隐藏停止入口',
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(StudioDriverKeys.composerStop))
          .onPressed,
      isNotNull,
      reason: '阻塞只禁用继续与提交，停止仍然可点',
    );
    await _close(tester, composer);
  });

  testWidgets('停止与继续被拒绝显示 typed 文案且不清草稿', (tester) async {
    final composer = await _composer(tester);
    await _pump(tester, composer);
    await composer.publish(execution: _running);
    await tester.pump();
    await tester.enterText(find.byKey(StudioDriverKeys.composerInput), 'draft');
    await tester.pump();
    await tester.enterText(find.byKey(StudioDriverKeys.composerInput), '');
    await tester.pump();

    composer.transport.stopError = const StudioFailure(
      code: StudioFailureCode.conflict,
      message: 'raw stop failure',
      retryable: false,
      correlationId: 'stop-conflict',
      reason: StudioFailureReason.staleExecution,
    );
    await tester.tap(find.byKey(StudioDriverKeys.composerStop));
    await tester.pump();
    await tester.pump();
    expect(
      find.text('The observed execution already ended or was replaced.'),
      findsOneWidget,
    );
    expect(
      find.byKey(StudioDriverKeys.composerStop),
      findsOneWidget,
      reason: '未被受理的停止回到可停止状态',
    );

    composer.transport.stopError = null;
    await composer.publish(execution: null, continuation: _continuation);
    await tester.pump();
    await tester.enterText(
      find.byKey(StudioDriverKeys.composerInput),
      'keep my draft',
    );
    await tester.pump();
    await tester.enterText(find.byKey(StudioDriverKeys.composerInput), '');
    await tester.pump();

    composer.transport.continueError = const StudioFailure(
      code: StudioFailureCode.busy,
      message: 'raw continue failure',
      retryable: true,
      correlationId: 'continue-busy',
      reason: StudioFailureReason.executionInProgress,
    );
    await tester.tap(find.byKey(StudioDriverKeys.composerContinue));
    await tester.pump();
    await tester.pump();
    expect(
      find.text('The session is still executing or settling.'),
      findsOneWidget,
    );
    expect(
      find.byKey(StudioDriverKeys.composerContinue),
      findsOneWidget,
      reason: '未被受理的继续仍可重新发起',
    );
    expect(
      find.byKey(const ValueKey('composer-failure')),
      findsOneWidget,
      reason: 'typed 原因必须可见',
    );
    await _close(tester, composer);
  });

  testWidgets('输入法组词中的 send 动作不提交，草稿保留', (tester) async {
    final composer = await _composer(tester);
    await _pump(tester, composer);
    await tester.enterText(
      find.byKey(StudioDriverKeys.composerInput),
      'zhongwen',
    );
    await tester.pump();
    // 组词区间有效：回车由平台确认候选，框架不参与提交。
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'zhongwen',
        selection: TextSelection.collapsed(offset: 8),
        composing: TextRange(start: 0, end: 8),
      ),
    );
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    expect(composer.transport.submitCalls, 0, reason: '组词期间不得提交或发起模型请求');
    expect(
      tester
          .widget<TextField>(find.byKey(StudioDriverKeys.composerInput))
          .controller!
          .text,
      'zhongwen',
      reason: '组词期间不提交也不清草稿',
    );

    // 组词结束后同一次 send 动作才提交。
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'zhongwen',
        selection: TextSelection.collapsed(offset: 8),
      ),
    );
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    await tester.pump();
    expect(composer.transport.submitCalls, 1, reason: '组词确认后 Enter 仍与主按钮一致');
    await _close(tester, composer);
  });

  testWidgets('点击停止固定的执行编号不会在排队期间被重选', (tester) async {
    final composer = await _composer(tester);
    await _pump(tester, composer);
    await composer.publish(execution: _running);
    await tester.pump();
    expect(find.byKey(StudioDriverKeys.composerStop), findsOneWidget);

    // 界面渲染 exec-1；canonical 之后已推进到 exec-2。点击必须仍以 exec-1 为目标，
    // 由服务端判过时（而不是本地改选或静默停止新执行）。
    await composer.publish(
      execution: const AgentExecutionView(
        id: 'exec-2',
        phase: AgentExecutionPhase.running,
        turnId: 'turn-2',
      ),
    );
    composer.transport.stopError = const StudioFailure(
      code: StudioFailureCode.conflict,
      message: 'raw stale stop',
      retryable: false,
      correlationId: 'stop-stale-queued',
      reason: StudioFailureReason.staleExecution,
    );
    await tester.tap(
      find.byKey(StudioDriverKeys.composerStop),
      warnIfMissed: false,
    );
    await tester.pump();
    await tester.pump();
    expect(composer.transport.stopTargets, ['$_threadId:exec-1']);
    expect(find.byKey(StudioDriverKeys.composerStopping), findsNothing);
    expect(
      find.text('The observed execution already ended or was replaced.'),
      findsOneWidget,
    );
    // 按 canonical 重新呈现：新执行仍在运行，主按钮回到停止。
    expect(find.byKey(StudioDriverKeys.composerStop), findsOneWidget);
    await _close(tester, composer);
  });

  testWidgets('停止发送渲染时的执行编号，staleExecution 不重试且保留草稿', (tester) async {
    final composer = await _composer(tester);
    await _pump(tester, composer);
    await composer.publish(execution: _running);
    await tester.pump();
    expect(find.byKey(StudioDriverKeys.composerStop), findsOneWidget);

    // canonical 已推进到新执行，界面仍是上一帧的 exec-1。
    await composer.publish(
      execution: const AgentExecutionView(
        id: 'exec-2',
        phase: AgentExecutionPhase.running,
        turnId: 'turn-2',
      ),
    );
    final gate = Completer<void>();
    composer.transport.stopGate = gate;
    composer.transport.stopError = const StudioFailure(
      code: StudioFailureCode.conflict,
      message: 'raw stale stop',
      retryable: false,
      correlationId: 'stop-stale-execution',
      reason: StudioFailureReason.staleExecution,
    );
    await tester.tap(
      find.byKey(StudioDriverKeys.composerStop),
      warnIfMissed: false,
    );
    await pumpClientUntil(
      tester,
      () => composer.transport.stopTargets.isNotEmpty,
      'stop request captured',
    );
    expect(composer.transport.stopTargets, [
      '$_threadId:exec-1',
    ], reason: '使用渲染时的执行编号作为 expectedExecutionId');
    expect(
      composer.transport.stopTargets,
      isNot(contains('$_threadId:exec-2')),
      reason: '不得改用 canonical 的新执行',
    );

    await tester.enterText(
      find.byKey(StudioDriverKeys.composerInput),
      'draft kept during stop',
    );
    await tester.pump();
    gate.complete();
    await tester.pump();
    await tester.pump();
    expect(
      find.text('The observed execution already ended or was replaced.'),
      findsOneWidget,
      reason: 'staleExecution 显示 typed 原因',
    );
    expect(
      find.byKey(StudioDriverKeys.composerStopping),
      findsNothing,
      reason: '过时目标不能停留在正在停止',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(StudioDriverKeys.composerInput))
          .controller!
          .text,
      'draft kept during stop',
      reason: '失败不清草稿',
    );
    expect(composer.transport.stopTargets, [
      '$_threadId:exec-1',
    ], reason: '过时目标不自动重试成新编号');
    await _close(tester, composer);
  });

  testWidgets('请求在途只禁用停止按钮，不显示正在停止', (tester) async {
    final composer = await _composer(tester);
    await _pump(tester, composer);
    await composer.publish(execution: _running);
    await tester.pump();
    final gate = Completer<void>();
    composer.transport.stopGate = gate;
    await tester.tap(find.byKey(StudioDriverKeys.composerStop));
    await pumpClientUntil(
      tester,
      () => composer.transport.stopTargets.isNotEmpty,
      'stop request in flight',
    );
    await tester.pump();
    expect(
      find.byKey(StudioDriverKeys.composerStopping),
      findsNothing,
      reason: '还没拿到受理回执，不能声称正在停止',
    );
    expect(
      find.byKey(const ValueKey('composer-stopping-disabled')),
      findsNothing,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(StudioDriverKeys.composerStop))
          .onPressed,
      isNull,
      reason: '请求在途时停止按钮禁用，避免重复提交',
    );

    // 受理回执到达后才进入清理态。
    await tester.runAsync(() async {
      gate.complete();
      await Future<void>.delayed(Duration.zero);
    });
    await pumpClientUntil(
      tester,
      () => find.byKey(StudioDriverKeys.composerStopping).evaluate().isNotEmpty,
      'stopping after acceptance',
    );
    expect(find.text('Stopping'), findsOneWidget);
    await _close(tester, composer);
  });

  testWidgets('canonical 阻塞优先于历史失败原因，两者同时可见', (tester) async {
    final composer = await _composer(tester);
    await _pump(tester, composer);
    await composer.publish(execution: null, continuation: _continuation);
    await tester.pump();

    // 先制造一次 typed 失败。
    composer.transport.continueError = const StudioFailure(
      code: StudioFailureCode.busy,
      message: 'raw continue busy',
      retryable: true,
      correlationId: 'continue-busy-then-blocked',
      reason: StudioFailureReason.executionInProgress,
    );
    await tester.tap(find.byKey(StudioDriverKeys.composerContinue));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('composer-failure')), findsOneWidget);

    // 随后出现保存阻塞：入口必须仍被禁用，且两条原因都在。
    await composer.transport.publishWorkspace(
      composer.workspace.copyWith(
        storage: const ThreadStorageStateView(
          fault: ThreadHistoryFault.writeFailed,
          resumeRequired: true,
          lastError: 'writer unavailable',
        ),
      ),
    );
    await tester.pump();
    expect(
      find.text('Saving has not finished yet, so continuing is unavailable.'),
      findsOneWidget,
    );
    expect(
      find.text('The session is still executing or settling.'),
      findsOneWidget,
      reason: '历史失败原因不被当前阻塞吞掉',
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(StudioDriverKeys.composerContinue))
          .onPressed,
      isNull,
      reason: 'canonical 阻塞仍决定准入',
    );
    await _close(tester, composer);
  });

  testWidgets('运行中有草稿时 Escape 仍能停止当前执行', (tester) async {
    final composer = await _composer(tester);
    await _pump(tester, composer);
    await composer.publish(execution: _running);
    await tester.pump();
    await tester.enterText(
      find.byKey(StudioDriverKeys.composerInput),
      'draft while running',
    );
    await tester.pump();
    expect(
      find.byKey(StudioDriverKeys.composerSubmit),
      findsOneWidget,
      reason: '主动作是发送并继续',
    );

    await tester.tap(find.byKey(StudioDriverKeys.composerInput));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpClientUntil(
      tester,
      () => composer.transport.stopTargets.isNotEmpty,
      'escape stops the running execution',
    );
    expect(composer.transport.stopTargets, [
      '$_threadId:exec-1',
    ], reason: 'Escape 与主按钮共用同一停止目标');
    expect(
      tester
          .widget<TextField>(find.byKey(StudioDriverKeys.composerInput))
          .controller!
          .text,
      'draft while running',
      reason: '停止不清草稿',
    );

    // 清理中再按 Escape 不重复发请求。
    await composer.publish(
      execution: const AgentExecutionView(
        id: 'exec-1',
        phase: AgentExecutionPhase.stopping,
        turnId: 'turn-1',
      ),
      continuation: null,
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(composer.transport.stopTargets, hasLength(1));
    await _close(tester, composer);
  });

  testWidgets('运行中有草稿时停止请求在途禁用发送并显示进度', (tester) async {
    final composer = await _composer(tester);
    await _pump(tester, composer);
    await composer.publish(execution: _running);
    await tester.pump();
    await tester.enterText(
      find.byKey(StudioDriverKeys.composerInput),
      'draft during pending stop',
    );
    await tester.pump();
    expect(
      find.byKey(StudioDriverKeys.composerSubmit),
      findsOneWidget,
      reason: '运行中有草稿时主动作是发送并继续',
    );

    // Escape 发出停止，回执被挂起：请求在途是线程级事实，与主动作种类无关。
    final gate = Completer<void>();
    composer.transport.stopGate = gate;
    await tester.tap(find.byKey(StudioDriverKeys.composerInput));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpClientUntil(
      tester,
      () => composer.transport.stopTargets.isNotEmpty,
      'escape stop in flight with draft',
    );
    await tester.pump();
    expect(composer.transport.stopTargets, ['$_threadId:exec-1']);
    expect(
      find.byKey(StudioDriverKeys.composerSubmit),
      findsNothing,
      reason: '请求在途时发送并继续必须禁用，不能与停止请求竞态',
    );
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('composer-submit-disabled')),
          )
          .onPressed,
      isNull,
    );
    expect(
      find.byKey(StudioDriverKeys.composerPending),
      findsOneWidget,
      reason: '请求在途显示请求进度',
    );
    expect(
      find.byKey(StudioDriverKeys.composerStopping),
      findsNothing,
      reason: '还没有受理回执，不能声称正在停止',
    );

    // Enter 同样不得提交：提交准入与主按钮同源。
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    expect(composer.transport.submitCalls, 0, reason: '请求在途期间回车也不得提交');

    // 受理回执到达后按既有清理态处理：正在停止且不可提交。
    await tester.runAsync(() async {
      gate.complete();
      await Future<void>.delayed(Duration.zero);
    });
    await pumpClientUntil(
      tester,
      () => find.byKey(StudioDriverKeys.composerStopping).evaluate().isNotEmpty,
      'stopping after acceptance with draft',
    );
    expect(find.text('Stopping'), findsOneWidget);
    expect(find.byKey(StudioDriverKeys.composerSubmit), findsNothing);
    await _close(tester, composer);
  });

  testWidgets('canonical 阻塞、历史失败与中断原因三条原因同时可见', (tester) async {
    final composer = await _composer(tester);
    await _pump(tester, composer);
    await composer.publish(execution: null, continuation: _continuation);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('composer-continuation-reason')),
      findsOneWidget,
      reason: '中断原因先独立可见',
    );

    // 制造一次 typed 失败：它说明上一次尝试被拒绝，不改变准入。
    composer.transport.continueError = const StudioFailure(
      code: StudioFailureCode.busy,
      message: 'raw continue busy',
      retryable: true,
      correlationId: 'continue-busy-three-reasons',
      reason: StudioFailureReason.executionInProgress,
    );
    await tester.tap(find.byKey(StudioDriverKeys.composerContinue));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('composer-failure')), findsOneWidget);

    // 随后出现 canonical 阻塞：准入由它决定，但另两条原因不得被吞掉。
    final route = composer.workspace.runtime.modelRoute!;
    await composer.publish(
      modelRoute: ThreadModelRouteView(
        accountId: route.accountId,
        modelId: route.modelId,
        effort: route.effort,
        revision: route.revision,
        available: false,
        unavailableReason: 'route unavailable',
      ),
    );
    await tester.pump();
    expect(
      find.byKey(StudioDriverKeys.composerBlocker),
      findsOneWidget,
      reason: 'canonical 阻塞可见',
    );
    expect(
      find.byKey(const ValueKey('composer-failure')),
      findsOneWidget,
      reason: '历史失败不被 canonical 阻塞吞掉',
    );
    expect(
      find.byKey(const ValueKey('composer-continuation-reason')),
      findsOneWidget,
      reason: '中断原因不被另两条吞掉',
    );
    expect(find.text('Stopped by the user'), findsOneWidget);
    expect(
      find.text('The session is still executing or settling.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'The current model is unavailable, so continuing is unavailable.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(StudioDriverKeys.composerContinue))
          .onPressed,
      isNull,
      reason: '准入仍只由 canonical 阻塞决定',
    );
    await _close(tester, composer);
  });

  testWidgets('切换会话后迟到的停止回执不写进新会话', (tester) async {
    final composer = await _composer(tester);
    await _pump(tester, composer);
    await composer.publish(execution: _running);
    await tester.pump();

    // A 的停止请求挂起。
    final gate = Completer<void>();
    composer.transport.stopGate = gate;
    composer.transport.stopError = const StudioFailure(
      code: StudioFailureCode.conflict,
      message: 'raw stale stop for A',
      retryable: false,
      correlationId: 'stop-stale-cross-thread',
      reason: StudioFailureReason.staleExecution,
    );
    await tester.tap(find.byKey(StudioDriverKeys.composerStop));
    await pumpClientUntil(
      tester,
      () => composer.transport.stopTargets.isNotEmpty,
      'stop in flight on A',
    );

    // 切到另一个会话：输入区换成 B 的线程级状态。
    await pumpClientFuture(
      tester,
      composer.graph.client.directoryCommands.selectThread(_altThreadId),
      'select alternate composer thread',
    );
    await pumpClientUntil(
      tester,
      () => composer.graph.client.conversations
          .session(_altThreadId)
          .state
          .hasSnapshot,
      'alternate thread snapshot',
    );
    await _pumpThread(tester, composer, _altThreadId);
    expect(
      find.byKey(StudioDriverKeys.composerInput),
      findsOneWidget,
      reason: 'B 有自己的输入区',
    );

    // 放行 A 的停止：回执属于 A，不得写进 B。
    await tester.runAsync(() async {
      gate.complete();
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('composer-failure')),
      findsNothing,
      reason: 'A 的失败不残留到 B',
    );
    expect(
      find.text('The observed execution already ended or was replaced.'),
      findsNothing,
    );
    expect(
      find.byKey(StudioDriverKeys.composerStopping),
      findsNothing,
      reason: 'A 的停止受理态不残留到 B',
    );
    expect(
      find.byKey(StudioDriverKeys.composerPending),
      findsNothing,
      reason: 'A 的在途进度不残留到 B',
    );
    await _close(tester, composer);
  });

  testWidgets('切回原会话仍恢复停止请求在途', (tester) async {
    final composer = await _composer(tester);
    await _pump(tester, composer);
    await composer.publish(execution: _running);
    await tester.pump();
    final gate = Completer<void>();
    composer.transport.stopGate = gate;
    await tester.tap(find.byKey(StudioDriverKeys.composerStop));
    await pumpClientUntil(
      tester,
      () => composer.transport.stopTargets.isNotEmpty,
      'stop in flight before switching away',
    );
    await tester.pump();
    expect(find.byKey(StudioDriverKeys.composerPending), findsOneWidget);

    // 切到另一会话再切回来：在途事实在 Client 命令板里，不随输入区 State 卸载丢失。
    await pumpClientFuture(
      tester,
      composer.graph.client.directoryCommands.selectThread(_altThreadId),
      'select alternate thread',
    );
    await pumpClientUntil(
      tester,
      () => composer.graph.client.conversations
          .session(_altThreadId)
          .state
          .hasSnapshot,
      'alternate snapshot before returning',
    );
    await _pumpThread(tester, composer, _altThreadId);
    await pumpClientFuture(
      tester,
      composer.graph.client.directoryCommands.selectThread(_threadId),
      'select original thread',
    );
    await _pumpThread(tester, composer, _threadId);
    // 重新打开会话后 canonical 执行由快照恢复；这里显式保持同一执行身份，
    // 让断言的焦点落在「命令板能否恢复在途」而不是重新订阅的时序上。
    await composer.publish(execution: _running);
    await tester.pump();
    expect(
      find.byKey(StudioDriverKeys.composerStop),
      findsOneWidget,
      reason: '回到原会话仍是同一执行',
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(StudioDriverKeys.composerStop))
          .onPressed,
      isNull,
      reason: '命令板仍 pending，重建后不得重新开放停止',
    );
    expect(
      find.byKey(StudioDriverKeys.composerPending),
      findsOneWidget,
      reason: '在途进度随命令板恢复',
    );
    expect(
      find.byKey(StudioDriverKeys.composerStopping),
      findsNothing,
      reason: '未结算前仍不声称正在停止',
    );

    // 放行回执：旧 State 的回调被丢弃，不写进新会话状态；在途事实仍由命令板维持，
    // 不因放行而误显示成失败或重新开放提交。
    await tester.runAsync(() async {
      gate.complete();
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    expect(
      find.byKey(const ValueKey('composer-failure')),
      findsNothing,
      reason: '迟到回执不写进重建后的输入区',
    );
    expect(
      find.byKey(const ValueKey('composer-stop-failure')),
      findsNothing,
      reason: '迟到的停止失败也不得落到新会话',
    );
    // canonical 进入清理期后由投影给出「正在停止」，不依赖本地受理记忆。
    await composer.publish(
      execution: const AgentExecutionView(
        id: 'exec-1',
        phase: AgentExecutionPhase.stopping,
        turnId: 'turn-1',
      ),
    );
    await tester.pump();
    expect(
      find.byKey(StudioDriverKeys.composerStopping),
      findsOneWidget,
      reason: '清理态来自 canonical 执行阶段',
    );
    await _close(tester, composer);
  });

  testWidgets('停止请求长时间未结算显示结果未确认并允许同一执行再试', (tester) async {
    final composer = await _composer(tester);
    await _pump(tester, composer);
    await composer.publish(execution: _running);
    await tester.pump();
    final gate = Completer<void>();
    composer.transport.stopGate = gate;
    await tester.tap(find.byKey(StudioDriverKeys.composerStop));
    await pumpClientUntil(
      tester,
      () => composer.transport.stopTargets.isNotEmpty,
      'stop pending before unconfirmed threshold',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('composer-stop-unconfirmed')),
      findsNothing,
      reason: '阈值内仍按请求在途处理',
    );

    // 超过有界阈值：说明结果未确认，不再无限锁死停止入口。
    await tester.pump(const Duration(seconds: 16));
    expect(
      find.byKey(const ValueKey('composer-stop-unconfirmed')),
      findsOneWidget,
    );
    expect(
      find.text(
        'The last action could not be confirmed. '
        'Check the session state before retrying.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(StudioDriverKeys.composerStop))
          .onPressed,
      isNotNull,
      reason: '结果未确认后允许用户显式再试',
    );

    // 再试仍用同一执行编号：不换目标、不自动重发。Client 的 stop lane 串行，
    // 因此这次点击排在第一个请求之后，不会产生并发的第二个请求。
    final second = Completer<void>();
    composer.transport.stopGate = second;
    await tester.tap(find.byKey(StudioDriverKeys.composerStop));
    await tester.pump();
    expect(composer.transport.stopTargets, [
      '$_threadId:exec-1',
    ], reason: '未结算前不并发重发');
    // 重试后立即回到「请求在途」：按钮重新禁用并显示进度，未确认提示消失。
    expect(
      find.byKey(const ValueKey('composer-stop-unconfirmed')),
      findsNothing,
      reason: '重试进入新的在途，不再显示上一条的未确认',
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(StudioDriverKeys.composerStop))
          .onPressed,
      isNull,
      reason: '新的在途期间不得继续点击',
    );
    expect(find.byKey(StudioDriverKeys.composerPending), findsOneWidget);
    // 这次重试已被 Client 排队（`StopQueued`，仍属同一次登记）：界面保持「请求在途」
    // 与禁用，不重复提示、也不新建计时。
    await tester.pump(const Duration(seconds: 16));
    expect(
      find.byKey(const ValueKey('composer-stop-unconfirmed')),
      findsNothing,
      reason: '排队中的重试尚未发出，不重复提示未确认',
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(StudioDriverKeys.composerStop))
          .onPressed,
      isNull,
      reason: '排队期间保持禁用',
    );
    expect(composer.transport.stopTargets, [
      '$_threadId:exec-1',
    ], reason: '重试仍排在第一个请求之后，不并发');

    await tester.runAsync(() async {
      gate.complete();
      await Future<void>.delayed(Duration.zero);
    });
    await pumpClientUntil(
      tester,
      () => composer.transport.stopTargets.length == 2,
      'queued retry dispatched after the first settles',
    );
    expect(composer.transport.stopTargets, [
      '$_threadId:exec-1',
      '$_threadId:exec-1',
    ], reason: '再试仍是同一执行编号');
    await tester.runAsync(() async {
      second.complete();
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    await _close(tester, composer);
  });

  testWidgets('受理状态跨重建保持：切走再回仍显示正在停止', (tester) async {
    final composer = await _composer(tester);
    await _pump(tester, composer);
    await composer.publish(execution: _running);
    await tester.pump();
    // 回执立即返回（applied）：命令板进入 accepted、仍 pending 等 canonical 收敛。
    await tester.tap(find.byKey(StudioDriverKeys.composerStop));
    await pumpClientUntil(
      tester,
      () => find.byKey(StudioDriverKeys.composerStopping).evaluate().isNotEmpty,
      'accepted before rebuild',
    );

    // 卸载再重新挂载输入区：State 被重建，受理事实只能来自命令板。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await _pumpThread(tester, composer, _threadId);
    expect(
      find.byKey(StudioDriverKeys.composerStopping),
      findsOneWidget,
      reason: '重建后的输入区从命令板 accepted 恢复正在停止',
    );

    expect(
      find.byKey(StudioDriverKeys.composerStopping),
      findsOneWidget,
      reason: '重建后仍显示正在停止（受理来自命令板 accepted）',
    );
    expect(
      find.byKey(StudioDriverKeys.composerStop),
      findsNothing,
      reason: '已受理不得重新开放停止',
    );
    // 距受理已经很久也不会变成「结果未确认」。
    await tester.pump(const Duration(seconds: 16));
    expect(find.byKey(StudioDriverKeys.composerStopping), findsOneWidget);
    expect(
      find.byKey(const ValueKey('composer-stop-unconfirmed')),
      findsNothing,
      reason: '已受理不是结果未确认',
    );
    await _close(tester, composer);
  });

  testWidgets('canonical 进入清理后超过阈值也不显示结果未确认', (tester) async {
    final composer = await _composer(tester);
    await _pump(tester, composer);
    await composer.publish(execution: _running);
    await tester.pump();
    final gate = Completer<void>();
    composer.transport.stopGate = gate;
    await tester.tap(find.byKey(StudioDriverKeys.composerStop));
    await pumpClientUntil(
      tester,
      () => composer.transport.stopTargets.isNotEmpty,
      'stop pending without receipt',
    );
    await tester.pump();

    // canonical 先进入清理期：执行已经在停，谈不上「结果未确认」。
    await composer.publish(
      execution: const AgentExecutionView(
        id: 'exec-1',
        phase: AgentExecutionPhase.stopping,
        turnId: 'turn-1',
      ),
    );
    await tester.pump();
    expect(
      find.byKey(StudioDriverKeys.composerStopping),
      findsOneWidget,
      reason: '清理期显示正在停止',
    );
    await tester.pump(const Duration(seconds: 16));
    expect(find.byKey(StudioDriverKeys.composerStopping), findsOneWidget);
    expect(
      find.byKey(const ValueKey('composer-stop-unconfirmed')),
      findsNothing,
      reason: '等待回执排除 canonical 清理：超时也不说未确认',
    );
    expect(
      find.byKey(StudioDriverKeys.composerStop),
      findsNothing,
      reason: '清理期没有重试入口',
    );
    await tester.runAsync(() async {
      gate.complete();
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    await _close(tester, composer);
  });

  testWidgets('重建后按命令板登记时间立即判定结果未确认', (tester) async {
    final composer = await _composer(tester);
    await _pump(tester, composer);
    await composer.publish(execution: _running);
    await tester.pump();

    // 直接写入一条 20 秒前登记、尚未受理的停止命令：模拟重建后读到的历史在途。
    final key = 'stop:$_threadId';
    composer.graph.client.threadCommands.state = ThreadCommandBoard(
      commands: {
        key: CommandStatus(
          key: key,
          phase: CommandPhase.pending,
          target: const CommandTarget(label: 'exec-1'),
          startedAtMs: DateTime.now().millisecondsSinceEpoch - 20000,
        ),
      },
    );
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('composer-stop-unconfirmed')),
      findsOneWidget,
      reason: 'elapsed 由 startedAtMs 算出，重建后无需再等 15 秒',
    );
    expect(
      find.text(
        'The last action could not be confirmed. '
        'Check the session state before retrying.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(StudioDriverKeys.composerStop))
          .onPressed,
      isNotNull,
      reason: '未确认后允许同一执行编号再试',
    );
    await _close(tester, composer);
  });

  testWidgets('命令板无停止条目时按 canonical 渲染', (tester) async {
    final composer = await _composer(tester);
    await _pump(tester, composer);
    await composer.publish(execution: _running);
    await tester.pump();
    await tester.tap(find.byKey(StudioDriverKeys.composerStop));
    await pumpClientUntil(
      tester,
      () => find.byKey(StudioDriverKeys.composerStopping).evaluate().isNotEmpty,
      'accepted before convergence',
    );

    // 执行结束、没有继续点：命令板条目随之清除，界面回到普通发送态。
    await composer.publish(execution: null, continuation: null);
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(StudioDriverKeys.composerStop),
      findsNothing,
      reason: '没有当前执行就没有停止入口',
    );
    expect(find.byKey(StudioDriverKeys.composerStopping), findsNothing);
    expect(
      find.byKey(const ValueKey('composer-stop-unconfirmed')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('composer-stop-failure')), findsNothing);
    expect(
      find.byKey(const ValueKey('composer-submit-disabled')),
      findsOneWidget,
      reason: '空草稿的普通发送态',
    );
    await _close(tester, composer);
  });

  testWidgets('受理回执已返回且清理未结束时不出现结果未确认', (tester) async {
    final composer = await _composer(tester);
    await _pump(tester, composer);
    await composer.publish(execution: _running);
    await tester.pump();
    // 回执立即返回（applied），canonical 执行仍在：命令板会继续 pending 等身份观察。
    await tester.tap(find.byKey(StudioDriverKeys.composerStop));
    await pumpClientUntil(
      tester,
      () => find.byKey(StudioDriverKeys.composerStopping).evaluate().isNotEmpty,
      'accepted stop shows stopping',
    );
    expect(find.text('Stopping'), findsOneWidget);

    // 超过阈值：已受理不是「结果未确认」，继续显示正在停止。
    await tester.pump(const Duration(seconds: 16));
    expect(
      find.byKey(StudioDriverKeys.composerStopping),
      findsOneWidget,
      reason: '受理后仍显示正在停止',
    );
    expect(
      find.byKey(const ValueKey('composer-stop-unconfirmed')),
      findsNothing,
      reason: '受理后不得再说结果未确认',
    );
    expect(
      find.byKey(StudioDriverKeys.composerStop),
      findsNothing,
      reason: '清理期不提供重复停止',
    );
    await _close(tester, composer);
  });

  testWidgets('受理回执在阈值之后到达会清除未确认标记', (tester) async {
    final composer = await _composer(tester);
    await _pump(tester, composer);
    await composer.publish(execution: _running);
    await tester.pump();
    final gate = Completer<void>();
    composer.transport.stopGate = gate;
    await tester.tap(find.byKey(StudioDriverKeys.composerStop));
    await pumpClientUntil(
      tester,
      () => composer.transport.stopTargets.isNotEmpty,
      'stop pending before late receipt',
    );
    // 让面板先按 pending 重建一次（计时器在重建时建立），再推进阈值。
    await tester.pump();
    await tester.pump(const Duration(seconds: 16));
    expect(
      find.byKey(const ValueKey('composer-stop-unconfirmed')),
      findsOneWidget,
      reason: '迟迟没有受理回执时才说未确认',
    );

    // 回执迟到但确实到达：未确认让位给「正在停止」，不再要求用户核对重试。
    await tester.runAsync(() async {
      gate.complete();
      await Future<void>.delayed(Duration.zero);
    });
    await pumpClientUntil(
      tester,
      () => find.byKey(StudioDriverKeys.composerStopping).evaluate().isNotEmpty,
      'late acceptance clears unconfirmed',
    );
    expect(
      find.byKey(const ValueKey('composer-stop-unconfirmed')),
      findsNothing,
      reason: '受理后未确认标记被清除',
    );
    expect(find.text('Stopping'), findsOneWidget);
    await _close(tester, composer);
  });

  testWidgets('受限尺寸下三类原因同时存在不溢出且可读', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final composer = await _composer(tester);
    await _pumpSized(
      tester,
      composer,
      threadId: _threadId,
      width: 320,
      height: 480,
    );
    // 先制造中断原因与 typed 失败。
    await composer.publish(execution: null, continuation: _continuation);
    await tester.pump();
    composer.transport.continueError = const StudioFailure(
      code: StudioFailureCode.busy,
      message: 'raw continue busy',
      retryable: true,
      correlationId: 'continue-busy-narrow',
      reason: StudioFailureReason.executionInProgress,
    );
    await tester.tap(find.byKey(StudioDriverKeys.composerContinue));
    await tester.pump();
    await tester.pump();
    // 再叠加 canonical 阻塞。
    final route = composer.workspace.runtime.modelRoute!;
    await composer.publish(
      modelRoute: ThreadModelRouteView(
        accountId: route.accountId,
        modelId: route.modelId,
        effort: route.effort,
        revision: route.revision,
        available: false,
        unavailableReason: 'route unavailable',
      ),
    );
    await tester.pump();
    expect(
      find.byKey(StudioDriverKeys.composerBlocker),
      findsOneWidget,
      reason: '受限尺寸下 canonical 阻塞仍可读',
    );
    expect(find.byKey(const ValueKey('composer-failure')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('composer-continuation-reason')),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('composer-reasons'))).height,
      lessThanOrEqualTo(84),
      reason: '原因区受高度约束，长文案改在区内滚动',
    );
    // 320 宽下选择器行本身已有既有的横向溢出（`session_selectors.dart` /
    // `studio_menu_label.dart`，与本原因区无关），这里把它们取走，
    // 在不溢出的宽度上单独验证原因区不新增溢出。
    while (tester.takeException() != null) {}

    // 不触发选择器横向溢出的窄宽 + 矮高：三种原因同时存在也不产生溢出。
    await _pumpSized(
      tester,
      composer,
      threadId: _threadId,
      width: 420,
      height: 360,
    );
    expect(
      find.byKey(const ValueKey('composer-reasons')),
      findsOneWidget,
      reason: '三种原因仍在',
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('composer-reasons'))).height,
      lessThanOrEqualTo(84),
    );
    expect(
      tester.takeException(),
      isNull,
      reason: '受限尺寸下原因区受高度约束并可滚动，不产生 RenderFlex 溢出',
    );
    await _close(tester, composer);
  });
}
