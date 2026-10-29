import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/studio_l10n.dart';
import 'hosted_child_interaction_connector.dart';
import '../state/interaction_payload.dart';
import '../view_models/interaction_command_view_model.dart';
import '../views/child_interaction_view.dart';
import '../../interactions/connectors/tool_approval_connector.dart';
import '../../interactions/connectors/user_input_connector.dart';

/// 主会话里的子任务待决交互卡片。
///
/// 事实仍由原子 child 会话持有：这里只展示 root 已装载成员发布的只读投影，并把用户的
/// 决定经主会话提交（design/18 §18.2、design/25 §25.7）。列举本身不激活任何 child，
/// 也不为它建立内容订阅或输入草稿。
class ChildInteractionConnector extends ConsumerStatefulWidget {
  const ChildInteractionConnector({
    required this.hostThreadId,
    required this.displayGeneration,
    required this.items,
    required this.sources,
    super.key,
  });

  /// 主会话（host）编号；决定与列举都用它作为宿主身份。
  final String hostThreadId;

  /// SDK display identity, not the canonical query sequence or command outcome.
  final int displayGeneration;

  /// 主会话可见的直接 child 待决交互，来自 Client 的只读投影。
  final List<ChildInteractionSummary> items;

  /// child 会话编号 → 来源成员说明。
  final Map<String, String> sources;

  @override
  ConsumerState<ChildInteractionConnector> createState() =>
      _ChildInteractionConnectorState();
}

class _ChildInteractionConnectorState
    extends ConsumerState<ChildInteractionConnector> {
  /// 已排队的最新宿主列举请求；旧请求结束后必须执行仍然有效的最新请求。
  ({String hostThreadId, int displayGeneration, int generation})? _pendingRead;
  Future<void>? _reading;
  Object? _readFailure;
  int _readGeneration = 0;

  @override
  void initState() {
    super.initState();
    _scheduleRead();
  }

  @override
  void didUpdateWidget(covariant ChildInteractionConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hostThreadId == widget.hostThreadId &&
        oldWidget.displayGeneration == widget.displayGeneration) {
      return;
    }
    _readGeneration++;
    _readFailure = null;
    _scheduleRead();
  }

  @override
  void dispose() {
    _readGeneration++;
    _pendingRead = null;
    super.dispose();
  }

  /// 列举是一次显式只读命令；页面重建不重复发起，只有宿主变化、决定完成后才重读。
  ///
  /// 在构建/布局阶段（如 `initState`、`didUpdateWidget`）推迟到帧末，避免读取结果在
  /// 同一帧里再触发 `setState`；其余时机（按钮点击、决议回调）立即排空，不依赖
  /// 「还有一帧」才会发生的副作用。
  void _scheduleRead() {
    if (!mounted) return;
    _pendingRead = (
      hostThreadId: widget.hostThreadId,
      displayGeneration: widget.displayGeneration,
      generation: _readGeneration,
    );
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
      final request = _pendingRead;
      if (request == null || !mounted) return;
      _pendingRead = null;
      final task = _readOnce(
        request.hostThreadId,
        request.displayGeneration,
        request.generation,
      );
      _reading = task;
      await task;
      if (!mounted) return;
      _reading = null;
    }
  }

  Future<void> _readOnce(
    String host,
    int displayGeneration,
    int generation,
  ) async {
    if (!_ownsReadResult(host, displayGeneration, generation)) return;
    try {
      await ref
          .read(interactionCommandViewModelProvider(host).notifier)
          .readChildInteractions(host, displayGeneration: displayGeneration);
      if (_ownsReadResult(host, displayGeneration, generation)) {
        setState(() => _readFailure = null);
      }
    } on Object catch (error) {
      if (_ownsReadResult(host, displayGeneration, generation)) {
        setState(() => _readFailure = error);
      }
    }
  }

  bool _ownsReadResult(String host, int displayGeneration, int generation) =>
      mounted &&
      host == widget.hostThreadId &&
      displayGeneration == widget.displayGeneration &&
      generation == _readGeneration;

  /// 一次 child 决议完成。
  ///
  /// 宿主和展示代次都取自派发时；旧决定继续由 SDK 收束，但不能触发新展示的重读。
  void _onDecision(
    String hostThreadId,
    int displayGeneration,
    ChildInteractionSummary summary,
    Object? error,
  ) {
    if (!mounted) return;
    if (hostThreadId != widget.hostThreadId ||
        displayGeneration != widget.displayGeneration) {
      return;
    }
    // SDK command state and the canonical child projection are the only outcome facts.
    // 决定落在原子 child 会话上；重读让 root 投影显示真实状态（含过期与失败）。
    _scheduleRead();
  }

  @override
  Widget build(BuildContext context) {
    final hostThreadId = widget.hostThreadId;
    final commands =
        ref.watch(interactionCommandViewModelProvider(hostThreadId)).value ??
        InteractionCommandViewState();
    final notice = commands.childNotice;
    final cards = [
      for (final item in widget.items)
        if (_isDecidable(item))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildCard(
              context,
              hostThreadId,
              item,
              commands.status(item.interactionId),
            ),
          ),
    ];
    if (cards.isEmpty && _readFailure == null && notice == null) {
      return const SizedBox.shrink();
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                TextButton(
                  key: const ValueKey('child-interaction-retry'),
                  onPressed: _scheduleRead,
                  child: Text(context.l10n.childInteractionRetry),
                ),
              ],
            ),
          ),
        ...cards,
        if (notice != null) ChildInteractionNoticeView(notice: notice),
      ],
    );
  }

  Widget _buildCard(
    BuildContext context,
    String hostThreadId,
    ChildInteractionSummary item,
    InteractionActionStatus? action,
  ) {
    final displayGeneration = widget.displayGeneration;
    final pending = action?.pending == true;
    final accepted = action?.accepted == true;
    final blocked = action?.blocked == true;
    final enabled = !pending && !accepted && !blocked;
    final hosted = HostedChildInteraction(
      summary: item,
      onResult: (error) =>
          _onDecision(hostThreadId, displayGeneration, item, error),
    );
    final payload = InteractionPayloadSnapshot.from(item.interaction);
    final child = switch (item.kind) {
      InteractionKind.toolApproval => ToolApprovalConnector(
        threadId: hostThreadId,
        interactionId: item.interactionId,
        expectedRevision: item.revision,
        payload: payload,
        enabled: enabled,
        hostedChild: hosted,
      ),
      InteractionKind.userInput => UserInputConnector(
        threadId: hostThreadId,
        interactionId: item.interactionId,
        expectedRevision: item.revision,
        payload: payload,
        enabled: enabled,
        hostedChild: hosted,
      ),
    };
    final failure = action?.error;
    return ChildInteractionCardView(
      interactionId: item.interactionId,
      revision: item.revision,
      source: widget.sources[item.childThreadId] ?? item.childThreadId,
      pending: pending,
      accepted: accepted,
      blocked: blocked,
      failure: failure == null ? null : _reasonText(context, failure),
      child: child,
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

/// 决定失败的原因：typed 失败用其文案，未知结果不伪装成成功。
String _reasonText(BuildContext context, Object error) {
  final reason = studioFailureReason(error);
  if (reason != null) return context.composerFailureReasonLabel(reason);
  final failure = error is StudioFailure ? error : null;
  return failure?.message ?? error.toString();
}
