part of 'timeline_view.dart';

/// 普通问答的只读回执：默认折叠，展开后按原问题顺序给出题目、完整问题与用户答案。
///
/// 它是历史回执而不是表单：不重建可提交控件，不缓存回答，也不解析工具载荷。折叠状态是
/// 局部展示意图，由 Timeline 的展开作用域按行身份持有；行内容更新（待回答 → 已回答）
/// 只替换载荷，不改变身份，也不重置用户主动展开。
class _UserInputReceipt extends StatelessWidget {
  const _UserInputReceipt({required this.itemId, required this.history});

  /// 承载这条问答历史的 canonical 工具条目身份。
  final String itemId;
  final ThreadToolUserInputView history;

  @override
  Widget build(BuildContext context) {
    final status = switch (history.state) {
      ResolvedThreadToolUserInputView() => (
        icon: Icons.check_rounded,
        label: context.l10n.timelineUserInputAnswered,
        tone: StudioTone.success,
      ),
      CancelledThreadToolUserInputView() => (
        icon: Icons.remove_rounded,
        label: context.l10n.timelineUserInputCancelled,
        tone: StudioTone.neutral,
      ),
      PendingThreadToolUserInputView() => (
        icon: Icons.schedule_rounded,
        label: context.l10n.timelineUserInputAwaiting,
        tone: StudioTone.warning,
      ),
    };
    final summary = _userInputSummary(context, history);
    return StudioPanel(
      backgroundColor: context.colors.surfaceContainerLowest,
      radius: StudioRadii.md,
      child: ExpansionTile(
        maintainState: false,
        dense: true,
        minTileHeight: 44,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        shape: const Border(),
        collapsedShape: const Border(),
        title: KeyedSubtree(
          key: StudioDriverKeys.timelineUserInput(itemId),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _UserInputStatusMark(icon: status.icon, tone: status.tone),
              const SizedBox(width: 9),
              Flexible(
                child: Text(
                  status.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelLarge?.copyWith(
                    color: context.colors.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (history.questions.isNotEmpty) ...[
                const SizedBox(width: 7),
                Text(
                  context.l10n.timelineUserInputQuestionCount(
                    history.questions.length,
                  ),
                  maxLines: 1,
                  style: context.text.labelSmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        subtitle: summary.isEmpty
            ? null
            : Text(
                summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
        children: [
          Column(
            key: StudioDriverKeys.timelineUserInputDetails(itemId),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, question) in history.questions.indexed) ...[
                if (index > 0) const _UserInputQuestionRule(),
                _UserInputQuestionBlock(
                  itemId: itemId,
                  index: index,
                  question: question,
                  answer: _userInputAnswer(history, question.id),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _UserInputStatusMark extends StatelessWidget {
  const _UserInputStatusMark({required this.icon, required this.tone});

  final IconData icon;
  final StudioTone tone;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tone.background(context),
        borderRadius: BorderRadius.circular(StudioRadii.xs),
      ),
      child: SizedBox.square(
        dimension: 20,
        child: Icon(icon, size: 13, color: tone.indicator(context)),
      ),
    );
  }
}

class _UserInputQuestionRule extends StatelessWidget {
  const _UserInputQuestionRule();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 17,
      thickness: 1,
      color: context.colors.outlineVariant.withValues(alpha: 0.66),
    );
  }
}

/// 一题的层级：序号与题目标题 → 完整问题 → 「你的回答」 → 答案正文。
class _UserInputQuestionBlock extends StatelessWidget {
  const _UserInputQuestionBlock({
    required this.itemId,
    required this.index,
    required this.question,
    required this.answer,
  });

  final String itemId;
  final int index;
  final UserQuestionView question;
  final ThreadUserInputAnswerView? answer;

  @override
  Widget build(BuildContext context) {
    final body = question.question.trim();
    return Column(
      key: StudioDriverKeys.timelineUserInputQuestion(itemId, index),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _UserInputIndexMark(index: index + 1),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _userInputQuestionLabel(context, question),
                style: context.text.labelLarge?.copyWith(
                  color: context.colors.onSurface,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
        if (body.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 26, top: 5),
            child: Text(
              question.question,
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurface,
                height: 1.45,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(left: 26, top: 10),
          child: Text(
            context.l10n.timelineUserInputYourAnswer,
            style: context.text.labelSmall?.copyWith(
              color: context.colors.onSurfaceVariant,
              letterSpacing: 0.2,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 26, top: 5),
          child: KeyedSubtree(
            key: StudioDriverKeys.timelineUserInputAnswer(itemId, index),
            child: _UserInputAnswerBody(question: question, answer: answer),
          ),
        ),
      ],
    );
  }
}

class _UserInputIndexMark extends StatelessWidget {
  const _UserInputIndexMark({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surfaceContainer.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(StudioRadii.xs),
      ),
      child: SizedBox.square(
        dimension: 18,
        child: Center(
          child: Text(
            '$index',
            style: context.text.labelSmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// 答案正文：精确匹配已有选项的回答作为克制标签，自由文本保留换行并可选择复制。
///
/// 敏感问题只表达「已回答且原值隐藏」：选项、自由文本与辅助语义都不出现原值。
class _UserInputAnswerBody extends StatelessWidget {
  const _UserInputAnswerBody({required this.question, required this.answer});

  final UserQuestionView question;
  final ThreadUserInputAnswerView? answer;

  @override
  Widget build(BuildContext context) {
    final answer = this.answer;
    final redacted = answer?.redacted ?? false;
    final values = (answer?.answers ?? const <String>[])
        .where((value) => value.trim().isNotEmpty)
        .toList(growable: false);
    // 先判定用户到底有没有提供答案：待回答、已取消和缺失答案都只是「没有答案」，
    // 与问题是否敏感无关。权威脱敏即使没有可见值，也证明用户确实提供过答案。
    if (answer == null || (!redacted && values.isEmpty)) {
      return Text(
        context.l10n.timelineUserInputNoAnswer,
        style: context.text.bodySmall?.copyWith(
          color: context.colors.onSurfaceVariant,
          height: 1.45,
        ),
      );
    }
    // 再对真实提供的答案做脱敏：敏感问题（含 caller 误带明文）只表达已隐藏。
    if (question.isSecret || redacted) {
      return const _UserInputHiddenAnswer();
    }
    final labels = {for (final option in question.options) option.label};
    final choices = [
      for (final value in values)
        if (labels.contains(value)) value,
    ];
    final freeText = [
      for (final value in values)
        if (!labels.contains(value)) value,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (choices.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final choice in choices) _UserInputChoiceTag(label: choice),
            ],
          ),
        for (final (index, text) in freeText.indexed) ...[
          if (choices.isNotEmpty || index > 0) const SizedBox(height: 6),
          _UserInputFreeText(text: text),
        ],
      ],
    );
  }
}

class _UserInputHiddenAnswer extends StatelessWidget {
  const _UserInputHiddenAnswer();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.lock_outline_rounded,
          size: 14,
          color: context.colors.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            context.l10n.timelineUserInputSecretHidden,
            style: context.text.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

class _UserInputChoiceTag extends StatelessWidget {
  const _UserInputChoiceTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surfaceContainer.withValues(alpha: 0.55),
        border: Border.all(
          color: context.colors.outlineVariant.withValues(alpha: 0.9),
        ),
        borderRadius: BorderRadius.circular(StudioRadii.xs),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: context.text.bodySmall?.copyWith(
            color: context.colors.onSurface,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _UserInputFreeText extends StatelessWidget {
  const _UserInputFreeText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(StudioRadii.xs),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        child: SelectableText(
          text,
          style: context.text.bodySmall?.copyWith(
            color: context.colors.onSurface,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}

/// 折叠时的次行摘要：多题只给题目串，单题给出可读答案；敏感回答永不进入摘要。
String _userInputSummary(
  BuildContext context,
  ThreadToolUserInputView history,
) {
  final questions = history.questions;
  if (questions.isEmpty) return '';
  if (questions.length == 1) {
    final question = questions.single;
    final answer = _userInputAnswer(history, question.id);
    if (!question.isSecret && !(answer?.redacted ?? false)) {
      final joined = (answer?.answers ?? const <String>[])
          .where((value) => value.trim().isNotEmpty)
          .map((value) => value.replaceAll(RegExp(r'\s+'), ' ').trim())
          .join(' · ');
      if (joined.isNotEmpty) return joined;
    }
    return _userInputSummaryTitle(context, question);
  }
  return [
    for (final question in questions) _userInputSummaryTitle(context, question),
  ].join(' · ');
}

String _userInputSummaryTitle(BuildContext context, UserQuestionView question) {
  final header = question.header.trim();
  if (header.isNotEmpty) return header;
  final body = question.question.trim();
  return body.isEmpty ? context.l10n.interactionQuestionFallback : body;
}

String _userInputQuestionLabel(
  BuildContext context,
  UserQuestionView question,
) {
  final header = question.header.trim();
  return header.isEmpty ? context.l10n.interactionQuestionFallback : header;
}

ThreadUserInputAnswerView? _userInputAnswer(
  ThreadToolUserInputView history,
  String questionId,
) {
  for (final answer in history.answers) {
    if (answer.questionId == questionId) return answer;
  }
  return null;
}
