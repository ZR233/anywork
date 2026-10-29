import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../presentation/providers/thread_session_store.dart';
import '../../../../domain/models/studio_models.dart';
import '../state/interaction_payload.dart';
import '../views/plan_confirmation_view.dart' as plan_view;
import '../view_models/interaction_command_view_model.dart';

/// 计划确认反馈栏：阅读在右侧详情面板，决定只在这里发生一次。
///
/// Enter 提交修改、Shift+Enter 换行由标准 `TextField` 文本输入动作完成；按钮与键盘
/// 共用 [_submitRevision] 这一入口，非空、当前交互仍有效与在途状态都在该入口判定，
/// 因此在途或重复决定不会产生第二次命令（design/13-plan.md §13.5）。
class PlanConfirmationConnector extends ConsumerStatefulWidget {
  const PlanConfirmationConnector({
    required this.threadId,
    required this.plan,
    required this.enabled,
    this.trailing,
    super.key,
  });

  final String threadId;
  final PlanConfirmationView plan;
  final bool enabled;
  final Widget? trailing;

  @override
  ConsumerState<PlanConfirmationConnector> createState() =>
      _PlanConfirmationConnectorState();
}

class _PlanConfirmationConnectorState
    extends ConsumerState<PlanConfirmationConnector> {
  late final TextEditingController _feedbackController;

  @override
  void initState() {
    super.initState();
    _feedbackController = TextEditingController()
      ..addListener(_handleFeedbackChanged);
  }

  @override
  void didUpdateWidget(covariant PlanConfirmationConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.plan.interactionId != widget.plan.interactionId) {
      _feedbackController.clear();
    }
  }

  @override
  void dispose() {
    _feedbackController
      ..removeListener(_handleFeedbackChanged)
      ..dispose();
    super.dispose();
  }

  /// 正文变化（含 Shift+Enter 插入的换行）决定「提交修改」是否可用。
  void _handleFeedbackChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final pending = ref
        .watch(threadSessionStoreProvider(widget.threadId))
        .interactions;
    final command = ref
        .watch(interactionCommandViewModelProvider(widget.threadId))
        .value
        ?.status(widget.plan.interactionId);
    final available =
        widget.enabled &&
        !(command?.blocked ?? false) &&
        !(command?.pending ?? false) &&
        !(command?.accepted ?? false) &&
        pendingInteractionIsActive(pending, widget.plan.interactionId);
    return plan_view.PlanConfirmationView(
      controller: _feedbackController,
      available: available,
      enabled:
          widget.enabled &&
          !(command?.blocked ?? false) &&
          !(command?.pending ?? false) &&
          !(command?.accepted ?? false),
      error: command?.error == null ? null : _commandFailure(command!.error!),
      trailing: widget.trailing,
      onFeedbackChanged: (_) => _handleFeedbackChanged(),
      onSubmitRevision: _submitRevision,
      onApprove: _approve,
    );
  }

  /// 交互仍待回答才算可提交：resolved/cancelled 或被其它交互取代时不发命令。
  ///
  /// 事件与异步路径只能读当前事实，不能在这里 watch；观察点只有 build 一处。
  bool _interactionIsCurrent(String threadId, String interactionId) {
    return pendingInteractionIsActive(
      ref.read(threadSessionStoreProvider(threadId)).interactions,
      interactionId,
    );
  }

  /// 提交修改的唯一入口：按钮与 Enter 提交共用。
  void _submitRevision() {
    final feedback = _feedbackController.text.trim();
    if (feedback.isEmpty) return;
    _resolve([agentSessionPlanReviseAnswer, feedback]);
  }

  void _approve() {
    _resolve(const [agentSessionPlanApproveAnswer]);
  }

  /// 在途、失效交互与关闭状态都不发命令；失败保留原输入并显示真实命令错误。
  ///
  /// 本次决定的 thread/交互/问题身份在第一个 await 之前冻结：回包或失败只允许影响
  /// 同一目标，绝不能清掉新交互的在途锁或写入它的错误。命令 future 只表示已受理，
  /// canonical 移除由交互流交付，因此成功后继续禁止重复决定，只有真实失败才释放锁。
  void _resolve(List<String> answers) {
    if (!widget.enabled) return;
    final threadId = widget.threadId;
    final interactionId = widget.plan.interactionId;
    final questionId = widget.plan.questionId;
    if (!_interactionIsCurrent(threadId, interactionId)) return;
    unawaited(
      ref
          .read(interactionCommandViewModelProvider(threadId).notifier)
          .resolveActive(
            threadId,
            interactionId,
            widget.plan.interaction.revision,
            UserInputResolutionCommand(
              answers: [
                UserInputAnswerCommand(
                  questionId: questionId,
                  answers: answers,
                ),
              ],
            ),
          )
          .then<void>((_) {}, onError: (Object _) {}),
    );
  }
}

/// 命令失败的实际原因：Client 的类型化失败带可用文案，其余原样传递。
String _commandFailure(Object error) {
  if (error case final StudioFailure failure) {
    final message = failure.message.trim();
    if (message.isNotEmpty) return message;
    return failure.code.name;
  }
  return '$error';
}
