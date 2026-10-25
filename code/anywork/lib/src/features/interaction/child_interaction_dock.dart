import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/studio_l10n.dart';
import '../../presentation/providers/client_provider.dart';
import '../../shared/studio_driver_keys.dart';
import '../../shared/studio_panel.dart';
import '../../app/theme/studio_tokens.dart';
import 'hosted_child_interaction.dart';
import 'interaction_payload.dart';
import 'interaction_widgets.dart';
import 'tool_approval_dock.dart';
import 'user_input_dock.dart';

/// 主会话里的子任务待决交互卡片。
///
/// 事实仍由原子 child 会话持有：这里只展示 root 已装载成员发布的只读投影，并把用户的
/// 决定经主会话提交（design/18 §18.2、design/25 §25.7）。列举本身不激活任何 child，
/// 也不为它建立内容订阅或输入草稿。
class ChildInteractionDock extends ConsumerStatefulWidget {
  const ChildInteractionDock({
    required this.hostThreadId,
    required this.items,
    required this.sources,
    super.key,
  });

  /// 主会话（host）编号；决定与列举都用它作为宿主身份。
  final String hostThreadId;

  /// 主会话可见的直接 child 待决交互，来自 Client 的只读投影。
  final List<ChildInteractionSummary> items;

  /// child 会话编号 → 来源成员说明。
  final Map<String, String> sources;

  @override
  ConsumerState<ChildInteractionDock> createState() =>
      _ChildInteractionDockState();
}

class _ChildInteractionDockState extends ConsumerState<ChildInteractionDock> {
  /// 已受理、仍待 canonical 确认的决定：交互编号 → 提交时冻结的摘要。
  ///
  /// 命令受理不等于已决议：只有 root 投影里该交互消失或 revision 推进，才把它当作
  /// 已保存/已决议并显示成功说明。
  final Map<String, ChildInteractionSummary> _accepted = {};

  /// 未被接受的决定原因（typed 失败或未知结果）。
  final Map<String, Object> _failures = {};

  Object? _readFailure;

  /// 已排队的最新宿主列举请求；旧请求结束后必须执行仍然有效的最新请求。
  String? _pendingHost;
  Future<void>? _reading;

  @override
  void initState() {
    super.initState();
    _scheduleRead();
  }

  @override
  void didUpdateWidget(covariant ChildInteractionDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hostThreadId == widget.hostThreadId) return;
    _accepted.clear();
    _failures.clear();
    _readFailure = null;
    _scheduleRead();
  }

  /// 列举是一次显式只读命令；页面重建不重复发起，只有宿主变化、决定完成后才重读。
  ///
  /// 在构建/布局阶段（如 `initState`、`didUpdateWidget`）推迟到帧末，避免读取结果在
  /// 同一帧里再触发 `setState`；其余时机（按钮点击、决议回调）立即排空，不依赖
  /// 「还有一帧」才会发生的副作用。
  void _scheduleRead() {
    _pendingHost = widget.hostThreadId;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      unawaited(_drainReads());
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_drainReads());
    });
  }

  /// 串行排空最新宿主请求：在途读取不能被新宿主请求直接丢弃。
  Future<void> _drainReads() async {
    if (_reading != null) return;
    while (true) {
      final host = _pendingHost;
      if (host == null || !mounted) return;
      _pendingHost = null;
      final task = _readOnce(host);
      _reading = task;
      await task;
      _reading = null;
      if (!mounted) return;
    }
  }

  Future<void> _readOnce(String host) async {
    try {
      await ref
          .read(anyworkClientProvider)
          .threadCommands
          .readChildInteractions(host);
      // 旧宿主的迟到结果不得改写当前宿主的错误状态。
      if (!mounted || host != widget.hostThreadId) return;
      setState(() => _readFailure = null);
    } on Object catch (error) {
      if (!mounted || host != widget.hostThreadId) return;
      setState(() => _readFailure = error);
    }
  }

  /// 一次 child 决议完成。
  ///
  /// [hostThreadId] 是发起时的宿主：切到另一个主会话后，迟到结果不得写入当前界面的
  /// 已受理/失败状态，也不得据旧宿主的摘要替新宿主做「已确认」判定；此时只重列新宿主
  /// 自己的 canonical 投影。
  void _onDecision(
    String hostThreadId,
    ChildInteractionSummary summary,
    Object? error,
  ) {
    if (!mounted) return;
    if (hostThreadId != widget.hostThreadId) {
      _scheduleRead();
      return;
    }
    setState(() {
      if (error == null) {
        _accepted[summary.interactionId] = summary;
        _failures.remove(summary.interactionId);
      } else {
        _accepted.remove(summary.interactionId);
        _failures[summary.interactionId] = error;
      }
    });
    // 决定落在原子 child 会话上；重读让 root 投影显示真实状态（含过期与失败）。
    _scheduleRead();
  }

  @override
  Widget build(BuildContext context) {
    // 捕获本帧的宿主：卡片回调可能在切换宿主之后才完成，届时的 widget.hostThreadId
    // 已经属于新宿主，不能代表发起这次决议的宿主。
    final hostThreadId = widget.hostThreadId;
    // canonical 确认：该交互已从 root 投影消失，或 revision 已越过提交时的版本。
    final confirmed = <String, ChildInteractionSummary>{};
    final awaiting = <String, ChildInteractionSummary>{};
    for (final entry in _accepted.entries) {
      final current = widget.items
          .where(
            (item) =>
                item.interactionId == entry.key &&
                item.childThreadId == entry.value.childThreadId,
          )
          .firstOrNull;
      if (current == null || current.revision > entry.value.revision) {
        confirmed[entry.key] = entry.value;
      } else {
        awaiting[entry.key] = entry.value;
      }
    }
    final cards = [
      for (final item in widget.items)
        if (_isDecidable(item) && !confirmed.containsKey(item.interactionId))
          item,
    ];
    final notices = {
      for (final entry in confirmed.entries)
        if (_isDecidable(entry.value)) entry.key: entry.value.kind,
    };
    if (cards.isEmpty && notices.isEmpty && _readFailure == null) {
      return const SizedBox.shrink();
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in notices.entries)
          _ChildDecisionNotice(
            key: ValueKey('child-interaction-notice-${entry.key}'),
            kind: entry.value,
          ),
        if (_readFailure case final failure?)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    context.l10n.childInteractionLoadFailed(
                      _reasonText(context, failure),
                    ),
                    key: const ValueKey('child-interaction-load-failure'),
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.error),
                  ),
                ),
                // 读取失败必须能在页面内重试：保留当前宿主，失败可再次重试。
                TextButton(
                  key: const ValueKey('child-interaction-retry'),
                  onPressed: _scheduleRead,
                  child: Text(context.l10n.childInteractionRetry),
                ),
              ],
            ),
          ),
        for (final item in cards)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _ChildInteractionCard(
              hostThreadId: hostThreadId,
              summary: item,
              source: widget.sources[item.childThreadId] ?? item.childThreadId,
              failure: _failures[item.interactionId],
              awaitingConfirmation: awaiting.containsKey(item.interactionId),
              onResult: (error) => _onDecision(hostThreadId, item, error),
            ),
          ),
      ],
    );
  }
}

/// 只有问题与权限请求可以在主会话决议。
///
/// child 的计划确认沿用通用 `UserInput` 载荷，但它是子会话自身的诊断事实：生产侧的目录与决议
/// 入口都按计划确认问题身份把它排除，界面据同一判据不渲染可决议卡片，避免把诊断事实转成决议。
bool _isDecidable(ChildInteractionSummary item) =>
    (item.kind == InteractionKind.userInput ||
        item.kind == InteractionKind.toolApproval) &&
    !item.interaction.isPlanConfirmation;

/// 一张来源明确的 child 交互卡片：复用既有问题/审批面板，只换宿主与提交链。
class _ChildInteractionCard extends StatelessWidget {
  const _ChildInteractionCard({
    required this.hostThreadId,
    required this.summary,
    required this.source,
    required this.failure,
    required this.awaitingConfirmation,
    required this.onResult,
  });

  final String hostThreadId;
  final ChildInteractionSummary summary;
  final String source;
  final Object? failure;

  /// 决定已被受理，但 canonical 尚未确认：控件停用、保留卡片、不宣告成功。
  final bool awaitingConfirmation;

  final ValueChanged<Object?> onResult;

  @override
  Widget build(BuildContext context) {
    final hosted = HostedChildInteraction(summary: summary, onResult: onResult);
    final payload = InteractionPayloadSnapshot.from(summary.interaction);
    final secondaryStyle = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return KeyedSubtree(
      key: StudioDriverKeys.childInteractionCard(summary.interactionId),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              InfoChip(
                icon: Icons.account_tree_outlined,
                label: context.l10n.childInteractionFrom(source),
              ),
              Text(
                context.l10n.childInteractionRevision(summary.revision),
                key: ValueKey(
                  'child-interaction-revision-${summary.interactionId}',
                ),
                style: secondaryStyle,
              ),
              if (awaitingConfirmation)
                SizedBox.square(
                  key: ValueKey(
                    'child-interaction-awaiting-${summary.interactionId}',
                  ),
                  dimension: 14,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          // 受理与确认是两件事：确认之前只表达「等待会话确认」，不宣告已保存/已决议。
          if (awaitingConfirmation)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                context.l10n.childInteractionDecisionAccepted,
                key: ValueKey(
                  'child-interaction-accepted-${summary.interactionId}',
                ),
                style: secondaryStyle,
              ),
            ),
          const SizedBox(height: 6),
          switch (summary.kind) {
            InteractionKind.toolApproval => ToolApprovalDock(
              threadId: hostThreadId,
              interactionId: summary.interactionId,
              payload: payload,
              enabled: !awaitingConfirmation,
              hostedChild: hosted,
            ),
            _ => UserInputDock(
              threadId: hostThreadId,
              interactionId: summary.interactionId,
              payload: payload,
              enabled: !awaitingConfirmation,
              hostedChild: hosted,
            ),
          },
          if (failure case final error?)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                context.l10n.childInteractionDecideFailed(
                  _reasonText(context, error),
                ),
                key: ValueKey(
                  'child-interaction-failure-${summary.interactionId}',
                ),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}

/// 已受理决定的状态说明：审批与普通问题表达不同事实，两种文案不得混用。
class _ChildDecisionNotice extends StatelessWidget {
  const _ChildDecisionNotice({required this.kind, super.key});

  final InteractionKind kind;

  @override
  Widget build(BuildContext context) {
    final approval = kind == InteractionKind.toolApproval;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: StudioPanel(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        borderColor: Theme.of(context).colorScheme.outlineVariant,
        radius: StudioRadii.lg,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(
                approval ? Icons.verified_outlined : Icons.task_alt_outlined,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  approval
                      ? context.l10n.childInteractionApprovalResolved
                      : context.l10n.childInteractionAnswerSaved,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 决定失败的原因：typed 失败用其文案，未知结果不伪装成成功。
String _reasonText(BuildContext context, Object error) {
  final reason = studioFailureReason(error);
  if (reason != null) return context.composerFailureReasonLabel(reason);
  final failure = error is StudioFailure ? error : null;
  return failure?.message ?? error.toString();
}
