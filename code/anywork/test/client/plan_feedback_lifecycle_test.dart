import 'dart:async';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/domain/models/studio_models.dart';
import 'package:anywork/src/features/interaction/plan_confirmation_dock.dart';
import 'package:anywork/src/features/shell/studio_shell.dart';
import 'package:anywork/src/features/timeline/timeline_view.dart';
import 'package:anywork/src/infrastructure/frb/studio_api.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pump_client_future.dart';

/// 根因回归：阅读布局（并排 / 全宽 / 窄窗 / 计划详情关开）只改变几何。
///
/// 变化的是 [StudioWorkspaceBody.readingArea]；反馈栏始终是同一个子位置，因此真实
/// `PlanConfirmationDock` 的草稿、错误与在途决定锁必须在切换后仍然存在。旧实现把整个
/// `conversation`（时间线 + 输入栏）交给两个不同父节点，切换时重建 State，这三项全部丢失。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const threadId = 'thread-main';
  const planMarkdown =
      '# Delivery Blueprint\n\n## Steps\n\n1. Keep the plan readable.';

  testWidgets('计划反馈草稿、错误与在途锁跨阅读布局与关开保持', (tester) async {
    final transport = _PlanFeedbackTransport();
    final graph = AppGraph(transport: transport, clientId: 'plan-feedback');
    await graph.client.bootstrap();
    await graph.client.directoryCommands.selectThread(threadId);
    await graph.client.session(threadId).source.waitFor((s) => s.hasSnapshot);

    /// 用 Client 自己的 canonical 状态入口投递一份待确认计划：这是运行时帧走的同一
    /// reducer，测试不去伪造第二个会话事实源。
    var interaction = _planInteraction(threadId);
    void publishPlan(PendingInteraction next) {
      interaction = next;
      transport.echo = next;
      final session = graph.client.session(threadId);
      session.applySnapshot(
        session.state.workspace!.copyWith(interactions: [next]),
      );
    }

    publishPlan(interaction);

    var plan = interaction.planConfirmation!;
    var split = true;
    var planOpen = true;
    late StateSetter rebuild;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appGraphProvider.overrideWithValue(graph)],
        child: MaterialApp(
          theme: pureStudioTheme(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 1100,
              height: 620,
              child: StatefulBuilder(
                builder: (context, setState) {
                  rebuild = setState;
                  return StudioWorkspaceBody(
                    readingArea: planOpen
                        ? _planReadingArea(split: split, markdown: planMarkdown)
                        : const SizedBox.shrink(),
                    footer: PlanConfirmationDock(
                      threadId: threadId,
                      plan: plan,
                      enabled: true,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dock = tester.state<State>(find.byType(PlanConfirmationDock));
    final input = find.byKey(const ValueKey('plan-feedback-input'));
    await tester.enterText(input, 'keep this draft');
    await tester.pump();

    /// 一次几何切换：只换阅读区域结构，反馈栏必须在原 State 上继续。
    Future<void> switchLayout({bool? nextSplit, bool? nextPlanOpen}) async {
      rebuild(() {
        if (nextSplit case final value?) split = value;
        if (nextPlanOpen case final value?) planOpen = value;
      });
      await tester.pumpAndSettle();
      expect(
        tester.state<State>(find.byType(PlanConfirmationDock)),
        same(dock),
        reason: '阅读布局变化不得重建反馈栏 State',
      );
      expect(
        tester.widget<TextField>(input).controller!.text,
        'keep this draft',
        reason: '草稿必须跨并排/全宽/窄窗与关开保持',
      );
    }

    await switchLayout(nextSplit: false);
    await switchLayout(nextPlanOpen: false);
    await switchLayout(nextPlanOpen: true, nextSplit: true);

    FilledButton approveButton() =>
        tester.widget<FilledButton>(find.byKey(const ValueKey('plan-approve')));

    // 真实命令错误：显示 Client 类型化失败的文案，并保留原输入。
    transport.failure = const StudioFailure(
      code: StudioFailureCode.busy,
      message: 'Interaction is busy',
      retryable: true,
      correlationId: 'plan-feedback-test',
    );
    await tester.tap(find.byKey(const ValueKey('plan-submit-revision')));
    await tester.pumpAndSettle();
    expect(find.text('Interaction is busy'), findsOneWidget);
    expect(transport.respondCalls, 1);
    await switchLayout(nextSplit: false);
    expect(
      find.text('Interaction is busy'),
      findsOneWidget,
      reason: '错误必须在布局切换后仍然可见',
    );
    expect(approveButton().onPressed, isNotNull, reason: '真实失败必须释放在途锁，允许改写后重试');

    // 已受理不等于 canonical 已移除：成功后保持禁用，重复决定不再发命令。
    transport.failure = null;
    await tester.tap(find.byKey(const ValueKey('plan-submit-revision')));
    await tester.pumpAndSettle();
    expect(transport.respondCalls, 2);
    expect(tester.widget<TextField>(input).enabled, isFalse);
    expect(
      approveButton().onPressed,
      isNull,
      reason: '受理后到 canonical 移除之前必须继续禁止重复决定',
    );
    await tester.tap(
      find.byKey(const ValueKey('plan-submit-revision')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(transport.respondCalls, 2);

    // 旧交互的迟到回包不能污染新交互：新身份下错误与锁都不继承。
    transport.failure = const StudioFailure(
      code: StudioFailureCode.conflict,
      message: 'Stale interaction',
      retryable: false,
      correlationId: 'plan-feedback-stale',
    );
    transport.gate = Completer<void>();
    publishPlan(_planInteraction(threadId, suffix: '-next'));
    rebuild(() => plan = interaction.planConfirmation!);
    await tester.pumpAndSettle();
    await tester.enterText(input, 'next decision');
    await tester.tap(find.byKey(const ValueKey('plan-submit-revision')));
    await tester.pump();
    publishPlan(_planInteraction(threadId, suffix: '-later'));
    rebuild(() => plan = interaction.planConfirmation!);
    await tester.pumpAndSettle();
    transport.gate!.complete();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('plan-feedback-error')),
      findsNothing,
      reason: '旧交互的失败不得写进新交互的错误',
    );
    expect(approveButton().onPressed, isNotNull, reason: '旧交互的在途锁不得扣住新交互');

    // testWidgets 在测试体结束前检查未完成定时器：成功路径在这里关闭 owner。
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpClientFuture(
      tester,
      graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
      'plan feedback lifecycle close',
    );
  });
}

/// 阅读区域的两种结构：并排（窄侧栏）与全宽阅读；两者都使用真实的计划详情面板。
Widget _planReadingArea({required bool split, required String markdown}) {
  final panel = PlanDetailPanel(
    identity: 'interaction:1',
    markdown: markdown,
    awaitingConfirmation: true,
    onToggleReadingMode: () {},
    onClose: () {},
  );
  if (!split) return panel;
  return Row(
    children: [
      const Expanded(child: SizedBox.shrink()),
      SizedBox(width: 420, child: panel),
    ],
  );
}

PendingInteraction _planInteraction(String threadId, {String suffix = ''}) {
  return PendingInteraction(
    id: 'interaction-plan$suffix',
    threadId: threadId,
    turnId: 'turn-plan$suffix',
    kind: InteractionKind.userInput,
    title: 'Plan',
    body: '# Delivery Blueprint',
    payload: const UserInputInteractionPayload(
      questions: [
        UserQuestionView(
          id: agentSessionPlanConfirmationQuestionId,
          header: 'Implementation plan',
          question: '# Delivery Blueprint\n\n## Steps\n\n1. Keep it readable.',
          isOther: false,
          isSecret: false,
          options: [],
        ),
      ],
    ),
  );
}

/// Demo transport 只替换 interaction 命令的结果与时机：其余会话/目录帧保持真实 Demo 行为。
///
/// 成功分支返回「已受理、canonical 尚未移除」的回执：这正是 UI 必须在成功后继续禁锁、
/// 等待交互流收敛的真实语义（thread_commands 的 future 只表示 accepted）。
class _PlanFeedbackTransport extends DemoStudioTransport {
  _PlanFeedbackTransport() : super(lspActivityLoop: false);

  int respondCalls = 0;
  Object? failure;

  /// 设置后命令在完成后等待该闸门，用于观察迟到的失败回包。
  Completer<void>? gate;

  /// 成功回执要回显的交互身份。
  PendingInteraction? echo;

  @override
  Future<InteractionCommandReply> respondInteraction(
    String interactionId,
    InteractionResolutionCommand resolution, {
    required OperationId operationId,
  }) async {
    respondCalls++;
    final pending = gate;
    if (pending != null) await pending.future;
    if (failure case final error?) throw error;
    return InteractionCommandReply(
      interaction: echo!,
      receipt: StudioCommandReceipt(
        operationId: operationId,
        disposition: CommitDisposition.applied,
        targets: const [],
        effect: EffectPoint.immediate,
        effective: false,
        durable: false,
        requiresIdentityObservation: true,
      ),
    );
  }
}
