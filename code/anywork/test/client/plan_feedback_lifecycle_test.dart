import 'dart:async';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/connectors/interaction_connector.dart';
import 'package:anywork/src/features/conversation/connectors/markdown_connector.dart';
import 'package:anywork/src/features/conversation/state/editor_keys.dart';
import 'package:anywork/src/features/conversation/state/plan_view_state.dart';
import 'package:anywork/src/features/conversation/views/conversation_view.dart';
import 'package:anywork/src/features/conversation/views/plan_view.dart';
import 'package:anywork/src/features/conversation/views/plan_panel_props.dart';
import 'package:anywork/src/features/conversation/widgets/conversation_markdown.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pump_client_future.dart';
import 'support/plan_feedback_environment.dart';

/// 计划详情头部右内边距（`PlanView` 头部的
/// `EdgeInsets.fromLTRB(16, 12, 8, 12)`）。
const _planHeaderContentInset = 8.0;

/// 根因回归：阅读布局（并排 / 全宽 / 窄窗 / 计划详情关开）只改变几何。
///
/// 变化的是 ConversationView.timeline；反馈栏始终是同一个子位置，因此真实
/// `InteractionConnector` 的草稿、错误与在途决定锁必须在切换后仍然存在。旧实现把整个
/// `conversation`（时间线 + 输入栏）交给两个不同父节点，切换时重建 State，这三项全部丢失。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const threadId = 'thread-main';
  const planMarkdown =
      '# Delivery Blueprint\n\n## Steps\n\n1. Keep the plan readable.';

  testWidgets('计划反馈草稿、错误与在途锁跨阅读布局与关开保持', (tester) async {
    // 桌面宽度需要真实画布：测试默认 800x600 会把 1100px 的 dock 压窄，
    // 让动作组按测试字体折行，从而掩盖右缘/基线回归。
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final env = PlanFeedbackEnvironment(threadId);
    final transport = env.commands;
    await pumpClientFuture(tester, env.establish(), 'plan native baseline');
    var interaction = planTestKey(threadId);
    Future<void> publishPlan(InteractionEditorKey next) async {
      interaction = next;
      await pumpClientFuture(
        tester,
        env.publish(next),
        'plan native replacement',
      );
    }

    var split = true;
    var planOpen = true;
    late StateSetter rebuild;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: env.container,
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
                  return ConversationView(
                    timeline: planOpen
                        ? _planReadingArea(split: split, markdown: planMarkdown)
                        : const SizedBox.shrink(),
                    interactions: InteractionConnector(
                      target: interaction,
                      enabled: true,
                    ),
                    status: const SizedBox.shrink(),
                    composerBuilder: (_) => const SizedBox.shrink(),
                    onToggleTodo: () {},
                    todoExpanded: false,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dock = tester.state<State>(find.byType(InteractionConnector));

    // 共享 footer 的动作组必须沿输入框右缘，且主/次操作同高同基线、组内间距 8px。
    final inputRect = tester.getRect(
      find.byKey(const ValueKey('plan-feedback-input')),
    );
    final reviseRect = tester.getRect(
      find.byKey(const ValueKey('plan-submit-revision')),
    );
    final approveRect = tester.getRect(
      find.byKey(const ValueKey('plan-approve')),
    );
    expect(
      approveRect.right,
      closeTo(inputRect.right, 1.0),
      reason: '动作组右缘必须与输入框右缘对齐',
    );
    expect(
      reviseRect.height,
      closeTo(approveRect.height, 1.0),
      reason: '主/次操作的布局盒同高（两侧都含标准 tap target，不断言视觉逐像素相等）',
    );
    expect(
      (reviseRect.center.dy - approveRect.center.dy).abs(),
      lessThanOrEqualTo(1.0),
      reason: '主/次操作必须同基线',
    );
    expect(
      approveRect.left - reviseRect.right,
      closeTo(8, 1.0),
      reason: '组内间距沿用 DockActions 的 8px',
    );
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
        tester.state<State>(find.byType(InteractionConnector)),
        same(dock),
        reason: '阅读布局变化不得重建反馈栏 State',
      );
      expect(
        tester.widget<TextField>(input).controller!.text,
        'keep this draft',
        reason: '草稿必须跨并排/全宽/窄窗与关开保持',
      );
      if (planOpen) {
        expectPlanHeaderAnchoredToContentEdge(
          tester,
          reason: 'en ${split ? '420 并排' : '1100 全宽'}计划头部',
        );
      }
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
    await publishPlan(planTestKey(threadId, suffix: '-next'));
    rebuild(() {});
    await tester.pumpAndSettle();
    await tester.enterText(input, 'next decision');
    await tester.tap(find.byKey(const ValueKey('plan-submit-revision')));
    await tester.pump();
    await publishPlan(planTestKey(threadId, suffix: '-later'));
    rebuild(() {});
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
      env.close(),
      'plan feedback lifecycle close',
    );
  });

  // 英文字号放大到 2x 时按钮文案明显变宽：受限折行必须真实生效，
  // 且无论是否折行，动作组右缘都要和输入框右缘一致。
  testWidgets('en 1x/1.5x/2x 下 560/640/窄布局的动作组不溢出且右缘对齐', (tester) async {
    // 大字号需要更高的画布，避免把画布不足误判成产品溢出。
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final env = PlanFeedbackEnvironment(threadId);
    await pumpClientFuture(tester, env.establish(), 'layout native baseline');
    final interaction = planTestKey(threadId);

    Widget harness({
      required double width,
      required double scale,
      Locale locale = const Locale('en'),
      Widget readingArea = const SizedBox.shrink(),
    }) {
      return UncontrolledProviderScope(
        container: env.container,
        child: MaterialApp(
          theme: pureStudioTheme(),
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                height: 900,
                child: ConversationView(
                  timeline: readingArea,
                  interactions: InteractionConnector(
                    target: interaction,
                    enabled: true,
                  ),
                  status: const SizedBox.shrink(),
                  composerBuilder: (_) => const SizedBox.shrink(),
                  onToggleTodo: () {},
                  todoExpanded: false,
                ),
              ),
            ),
          ),
        ),
      );
    }

    for (final width in const [640.0, 560.0, 360.0]) {
      for (final scale in const [1.0, 1.5, 2.0]) {
        await tester.pumpWidget(harness(width: width, scale: scale));
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'en ${scale}x / ${width}px 的动作组不允许横向溢出',
        );
        final input = tester.getRect(
          find.byKey(const ValueKey('plan-feedback-input')),
        );
        final revise = tester.getRect(
          find.byKey(const ValueKey('plan-submit-revision')),
        );
        final approve = tester.getRect(
          find.byKey(const ValueKey('plan-approve')),
        );
        expect(
          approve.right,
          closeTo(input.right, 1.0),
          reason: 'en ${scale}x / ${width}px 下动作组右缘仍与输入框对齐',
        );
        if ((approveRectCenter(approve) - approveRectCenter(revise)).abs() <=
            1.0) {
          expect(
            approve.left - revise.right,
            closeTo(8, 1.0),
            reason: 'en ${scale}x / ${width}px 同一行内保持 8px 组内间距',
          );
        }
      }
    }

    // 计划详情头部动作组：zh/en 正常字号下，420 并排、720 默认并排与 1100 全宽都必须
    // 靠右，不因语言或阅读布局把动作组留在中间并在右侧留空白。
    for (final locale in const [Locale('en'), Locale('zh')]) {
      for (final layout in const [
        (label: '360 最小并排', split: true, panelWidth: 360.0),
        (label: '420 并排', split: true, panelWidth: 420.0),
        (label: '720 默认并排', split: true, panelWidth: 720.0),
        (label: '1100 全宽', split: false, panelWidth: 0.0),
      ]) {
        await tester.pumpWidget(
          harness(
            width: 1100,
            scale: 1.0,
            locale: locale,
            readingArea: _planReadingArea(
              split: layout.split,
              panelWidth: layout.panelWidth,
              markdown: planMarkdown,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '${locale.languageCode} ${layout.label}计划头部不允许溢出',
        );
        expectPlanHeaderAnchoredToContentEdge(
          tester,
          reason: '${locale.languageCode} ${layout.label}计划头部',
        );
      }
    }

    // 桌面真实平台：`ThemeData` 对 linux/macOS/windows 默认
    // `MaterialTapTargetSize.shrinkWrap`，暹罗主题又显式 `VisualDensity.compact`，
    // 计划按钮因此在真实 Linux GUI 上只有 32px 高。`_InputPadding` 的 padded 尺寸是
    // `kMinInteractiveDimension + 密度调整`，所以 compact 下本机测试环境（缓存主题为
    // padded）也只有 40。计划动作组显式声明 `VisualDensity.standard` +
    // `MaterialTapTargetSize.padded` 后，四个动作必须统一 40 视觉 / 48 布局盒——
    // 未声明密度的旧 style 在这一步稳定变红（实测 40，关闭按钮在原生是 40）。
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    for (final locale in const [Locale('en'), Locale('zh')]) {
      await tester.pumpWidget(
        harness(
          width: 1100,
          scale: 1.0,
          locale: locale,
          readingArea: _planReadingArea(
            split: true,
            panelWidth: 720,
            markdown: planMarkdown,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: '${locale.languageCode} 桌面平台计划动作组不允许溢出',
      );
      final desktopActions = <String, Rect>{
        'revise': tester.getRect(
          find.byKey(const ValueKey('plan-submit-revision')),
        ),
        'approve': tester.getRect(find.byKey(const ValueKey('plan-approve'))),
        'readingMode': tester.getRect(
          find.byKey(const ValueKey('plan-details-reading-mode')),
        ),
        'close': tester.getRect(
          find.byKey(const ValueKey('plan-details-close')),
        ),
      };
      for (final action in desktopActions.entries) {
        expect(
          action.value.height,
          closeTo(kMinInteractiveDimension, 1.0),
          reason:
              '${locale.languageCode} 桌面平台 ${action.key} 必须保持标准密度（视觉 40）与'
              '标准命中区（布局盒 $kMinInteractiveDimension），不得退化成 compact 的 32',
        );
      }
      expect(
        approveRectCenter(desktopActions['approve']!),
        closeTo(approveRectCenter(desktopActions['revise']!), 1.0),
        reason: '${locale.languageCode} 桌面平台主/次操作仍同基线',
      );
      expect(
        desktopActions['approve']!.left - desktopActions['revise']!.right,
        closeTo(8, 1.0),
        reason: '${locale.languageCode} 桌面平台组内间距仍是 8px',
      );
      expectPlanHeaderAnchoredToContentEdge(
        tester,
        reason: '${locale.languageCode} 桌面平台计划头部',
      );
    }
    debugDefaultTargetPlatformOverride = null;

    await tester.pumpWidget(const SizedBox.shrink());
    await pumpClientFuture(tester, env.close(), 'plan actions layout close');
  });
}

double approveRectCenter(Rect rect) => rect.center.dy;

/// 计划详情头部动作组必须锚在面板内容右边界。
///
/// 头部 `Padding` 的右内边距是 8px，因此组内最后一个动作（关闭）的布局盒右缘必须正好
/// 落在面板右缘减 8px 处。旧实现把动作组放在宽松 `Flexible` 里，内部 `Row` 取自然宽度，
/// 剩余空间留在动作组右侧——关闭按钮因此离面板右缘很远（720px 下实测 186px），
/// 与“动作组靠右”的要求相反。
void expectPlanHeaderAnchoredToContentEdge(
  WidgetTester tester, {
  required String reason,
}) {
  final panel = tester.getRect(find.byType(PlanView));
  final close = tester.getRect(
    find.byKey(const ValueKey('plan-details-close')),
  );
  expect(
    close.right,
    closeTo(panel.right - _planHeaderContentInset, 1.0),
    reason: '$reason：头部动作组必须靠右，不在右侧留空白',
  );
  expect(
    close.height,
    greaterThanOrEqualTo(36),
    reason: '$reason：关闭动作保持标准命中尺寸',
  );
}

/// 阅读区域的两种结构：并排（窄侧栏）与全宽阅读；两者都使用真实的计划详情面板。
Widget _planReadingArea({
  required bool split,
  required String markdown,
  double panelWidth = 420,
}) {
  final panel = PlanView(
    props: PlanPanelProps(
      state: PlanViewState(
        threadId: 'thread-main',
        open: true,
        fullWidth: !split,
        plan: const PlanBrief(
          revision: 1,
          state: PlanPhase.awaitingConfirmation,
          document: PlanDocumentRef(version: 1, contentHash: 'plan-hash'),
          updatedAt: 1,
        ),
        document: PlanDocumentValue(
          scope: const ReadScopeIdentity(
            scopeId: 'plan-document',
            runtimeEpoch: planTestRuntime,
            incarnation: 1,
            sourceRevision: 1,
          ),
          version: 1,
          contentHash: 'plan-hash',
          markdown: markdown,
        ),
      ),
      sideBySideFeasible: true,
      onToggleReading: () {},
      onClose: () {},
      onRetry: () {},
      documentBuilder: (_, text) => MarkdownConnector(
        id: 'plan:thread-main:1:plan-hash',
        text: text,
        surface: MarkdownSurface.panel,
      ),
    ),
  );
  if (!split) return panel;
  return Row(
    children: [
      const Expanded(child: SizedBox.shrink()),
      SizedBox(width: panelWidth, child: panel),
    ],
  );
}
