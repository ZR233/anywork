import 'package:anywork/src/presentation/providers/client_provider.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/studio_tokens.dart';
import '../../presentation/providers/thread_session_store.dart';
import '../../domain/models/studio_models.dart';
import 'interaction_payload.dart';
import '../../l10n/studio_l10n.dart';
import '../../shared/studio_driver_keys.dart';
import 'interaction_widgets.dart';
import 'multiline_enter_shortcuts.dart';

/// 计划决定动作的统一视觉高度与水平内边距：主/次操作大小一致，
/// 组内间距沿用 [DockActions] 的 8px，右缘由共享 footer 对齐输入框。
const _planActionMinHeight = 40.0;
const _planActionPadding = EdgeInsets.symmetric(horizontal: 14);

/// 桌面平台必须显式声明标准密度与标准命中区。
///
/// `ThemeData` 对 linux/macOS/windows 默认 `MaterialTapTargetSize.shrinkWrap`，而暹罗
/// 主题显式 [VisualDensity.compact] 会把 [_planActionMinHeight] 再缩 8px（真实 Linux
/// GUI 上计划按钮只有 32px 高）。计划动作显式要求 [VisualDensity.standard] +
/// [MaterialTapTargetSize.padded]：视觉 40、布局盒 48，主/次操作仍同高同基线，
/// 鼠标与键盘命中区都达到 Material 标准尺寸。
const _planActionVisualDensity = VisualDensity.standard;
const _planActionTapTargetSize = MaterialTapTargetSize.padded;

/// 计划确认反馈栏：阅读在右侧详情面板，决定只在这里发生一次。
///
/// Enter 提交修改、Shift+Enter 换行由标准 `TextField` 文本输入动作完成；按钮与键盘
/// 共用 [_submitRevision] 这一入口，非空、当前交互仍有效与在途状态都在该入口判定，
/// 因此在途或重复决定不会产生第二次命令（design/13-plan.md §13.5）。
class PlanConfirmationDock extends ConsumerStatefulWidget {
  const PlanConfirmationDock({
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
  ConsumerState<PlanConfirmationDock> createState() =>
      _PlanConfirmationDockState();
}

class _PlanConfirmationDockState extends ConsumerState<PlanConfirmationDock> {
  late final TextEditingController _feedbackController;
  bool _resolving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _feedbackController = TextEditingController()
      ..addListener(_handleFeedbackChanged);
  }

  @override
  void didUpdateWidget(covariant PlanConfirmationDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.plan.interactionId != widget.plan.interactionId) {
      _feedbackController.clear();
      _error = null;
      _resolving = false;
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
    // build 里唯一观察：pending 队列与事件路径共享同一事实，回调侧用 ref.read。
    final pending = ref
        .watch(threadSessionStoreProvider(widget.threadId))
        .interactions;
    final available =
        widget.enabled &&
        !_resolving &&
        pendingInteractionIsActive(pending, widget.plan.interactionId);
    final feedback = _feedbackController.text.trim();
    return InteractionDockShell(
      kind: InteractionDockKind.plan,
      trailing: widget.trailing,
      title: context.l10n.interactionPlanConfirmTitle,
      subtitle: context.l10n.interactionPlanConfirmSubtitle,
      footerHint: context.l10n.interactionPlanFeedbackHint,
      footer: DockActions(
        children: [
          // 次操作（请求修改）保持清晰的次要层级；与主操作共用同一视觉高度与
          // 水平内边距。动作组由共享 footer 给一份有界宽度，超出时在自身范围内
          // 折行（含英文与大字号），因此这里不固定死宽也不写无界自然宽注释。
          OutlinedButton.icon(
            key: StudioDriverKeys.planSubmitRevision,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, _planActionMinHeight),
              padding: _planActionPadding,
              visualDensity: _planActionVisualDensity,
              tapTargetSize: _planActionTapTargetSize,
            ),
            icon: const Icon(Icons.send_outlined, size: 18),
            label: Text(context.l10n.interactionPlanAdjustSubmit),
            onPressed: available && feedback.isNotEmpty
                ? _submitRevision
                : null,
          ),
          FilledButton.icon(
            key: StudioDriverKeys.planApprove,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, _planActionMinHeight),
              padding: _planActionPadding,
              visualDensity: _planActionVisualDensity,
              tapTargetSize: _planActionTapTargetSize,
            ),
            icon: const Icon(Icons.check, size: 18),
            label: Text(context.l10n.interactionPlanConfirmAction),
            onPressed: available ? _approve : null,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          MultilineEnterShortcuts(
            controller: _feedbackController,
            child: TextField(
              key: StudioDriverKeys.planFeedbackInput,
              controller: _feedbackController,
              enabled: widget.enabled && !_resolving,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              // 提交后保留焦点：失败时可以直接改写重试，成功与否由交互状态决定。
              onEditingComplete: () {},
              onSubmitted: (_) => _submitRevision(),
              decoration: InputDecoration(
                labelText: context.l10n.interactionPlanAdjust,
                hintText: context.l10n.interactionPlanAdjustHint,
              ),
            ),
          ),
          if (_error case final error?) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 15,
                  color: context.colors.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    error,
                    key: StudioDriverKeys.planFeedbackError,
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.error,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
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
  Future<void> _resolve(List<String> answers) async {
    if (_resolving || !widget.enabled) return;
    final threadId = widget.threadId;
    final interactionId = widget.plan.interactionId;
    final questionId = widget.plan.questionId;
    if (!_interactionIsCurrent(threadId, interactionId)) return;
    setState(() {
      _resolving = true;
      _error = null;
    });
    try {
      await ref
          .read(anyworkClientProvider)
          .threadCommands
          .resolveActiveInteraction(
            threadId,
            interactionId,
            UserInputResolutionCommand(
              answers: [
                UserInputAnswerCommand(
                  questionId: questionId,
                  answers: answers,
                ),
              ],
            ),
          );
      // 已受理不等于 canonical 已移除：保持禁用直到交互消失或真实失败。
    } catch (error) {
      if (!mounted || widget.plan.interactionId != interactionId) return;
      setState(() {
        _error = _commandFailure(error);
        _resolving = false;
      });
    }
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
