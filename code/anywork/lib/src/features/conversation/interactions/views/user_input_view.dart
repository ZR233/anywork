import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_driver_keys.dart';
import '../state/interaction_payload.dart';
import '../widgets/interaction_widgets.dart';
import '../widgets/question_progress.dart';
import '../widgets/question_step.dart';
import '../views/fallback_question_dock.dart';

class UserInputView extends StatefulWidget {
  const UserInputView({
    required this.payload,
    required this.enabled,
    this.error,
    required this.onSubmit,
    this.trailing,
    super.key,
  });

  final InteractionPayloadSnapshot payload;
  final bool enabled;
  final Object? error;
  final ValueChanged<UserInputResolutionCommand> onSubmit;
  final Widget? trailing;

  @override
  State<UserInputView> createState() => _UserInputViewState();
}

class _UserInputViewState extends State<UserInputView> {
  late final TextEditingController _fallbackController;
  final Map<String, TextEditingController> _textControllers = {};
  final Map<String, Set<String>> _selectedOptions = {};
  final _firstOptionKey = GlobalKey();
  final _submitKey = GlobalKey();
  String? _ensuredQuestionKey;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _fallbackController = TextEditingController();
    _resetQuestionDraft(widget.payload.questions);
  }

  @override
  void didUpdateWidget(covariant UserInputView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed =
        !_sameQuestionSemantics(
          oldWidget.payload.questions,
          widget.payload.questions,
        ) ||
        (oldWidget.payload.questions.isEmpty &&
            widget.payload.questions.isEmpty &&
            oldWidget.payload.rawBody != widget.payload.rawBody);
    if (changed) {
      _fallbackController.clear();
      _resetQuestionDraft(widget.payload.questions);
    }
  }

  @override
  void dispose() {
    _fallbackController.dispose();
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    final questions = widget.payload.questions;
    if (questions.isEmpty) {
      return FallbackQuestionDock(
        body: widget.payload.rawBody,
        controller: _fallbackController,
        trailing: widget.trailing,
        onChanged: () => setState(() {}),
        error: widget.error?.toString(),
        onSubmit: !enabled || _fallbackController.text.trim().isEmpty
            ? null
            : _submitFallbackAnswer,
      );
    }

    final index = _index.clamp(0, questions.length - 1).toInt();
    if (index != _index) {
      _index = index;
    }
    final question = questions[index];
    final key = _questionKey(question, index);
    if (index == 0 && question.options.isNotEmpty) {
      _ensureFirstOptionVisible(key);
    }
    final total = questions.length;
    final answeredCount = questions.where(_answered).length;
    final isLast = index >= total - 1;
    return InteractionDockShell(
      kind: InteractionDockKind.question,
      trailing: widget.trailing,
      title: context.l10n.interactionQuestionsTitle,
      subtitle: isLast
          ? context.l10n.interactionLastQuestion
          : context.l10n.interactionContinueAfterAnswer,
      footerHint: isLast
          ? context.l10n.interactionSubmitEmptyAnswersHint
          : context.l10n.interactionAnsweredPendingHint(
              answeredCount,
              total - answeredCount,
            ),
      footer: DockActions(
        children: [
          if (index > 0)
            TextButton.icon(
              icon: const Icon(Icons.chevron_left),
              label: Text(context.l10n.interactionPreviousQuestion),
              onPressed: () => setState(() => _index -= 1),
            ),
          KeyedSubtree(
            key: _submitKey,
            child: FilledButton.icon(
              key: StudioDriverKeys.userInputSubmit,
              icon: Icon(isLast ? Icons.check : Icons.chevron_right),
              label: Text(
                isLast
                    ? context.l10n.interactionSubmitAnswers
                    : context.l10n.interactionNextQuestion,
              ),
              onPressed: enabled
                  ? () {
                      if (isLast) {
                        _submitAnswers();
                      } else {
                        setState(() => _index += 1);
                      }
                    }
                  : null,
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          QuestionProgress(
            total: total,
            currentIndex: index,
            answeredCount: answeredCount,
            questions: questions,
            answered: _answered,
            onSelected: (value) => setState(() => _index = value),
          ),
          const SizedBox(height: 12),
          QuestionStep(
            enabled: enabled,
            isFirstQuestion: index == 0,
            firstOptionKey: _firstOptionKey,
            question: question,
            questionKey: key,
            controller: _textControllers[key]!,
            selected: _selectedOptions[key] ?? <String>{},
            onOptionChanged: (label, selected) {
              setState(() {
                final values = _selectedOptions[key] ?? <String>{};
                if (selected) {
                  values.add(label);
                } else {
                  values.remove(label);
                }
                _selectedOptions[key] = values;
              });
              _ensureSubmitVisible();
            },
            onTextChanged: (_) {
              setState(() {});
              _ensureSubmitVisible();
            },
          ),
          if (widget.error case final error?) ...[
            const SizedBox(height: 8),
            Text(
              '$error',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }

  void _resetQuestionDraft(List<UserQuestionView> questions) {
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    _textControllers
      ..clear()
      ..addEntries(
        questions.indexed.map(
          (entry) => MapEntry(
            _questionKey(entry.$2, entry.$1),
            TextEditingController(),
          ),
        ),
      );
    _selectedOptions
      ..clear()
      ..addEntries(
        questions.indexed.map(
          (entry) => MapEntry(_questionKey(entry.$2, entry.$1), <String>{}),
        ),
      );
    _index = 0;
    _ensuredQuestionKey = null;
  }

  bool _sameQuestionSemantics(
    List<UserQuestionView> previous,
    List<UserQuestionView> next,
  ) {
    if (previous.length != next.length) return false;
    for (var index = 0; index < previous.length; index++) {
      final left = previous[index];
      final right = next[index];
      if (left.id != right.id ||
          left.header != right.header ||
          left.question != right.question ||
          left.isOther != right.isOther ||
          left.isSecret != right.isSecret ||
          left.options.length != right.options.length) {
        return false;
      }
      for (
        var optionIndex = 0;
        optionIndex < left.options.length;
        optionIndex++
      ) {
        final leftOption = left.options[optionIndex];
        final rightOption = right.options[optionIndex];
        if (leftOption.label != rightOption.label ||
            leftOption.description != rightOption.description) {
          return false;
        }
      }
    }
    return true;
  }

  void _ensureFirstOptionVisible(String questionKey) {
    if (_ensuredQuestionKey == questionKey) {
      return;
    }
    _ensuredQuestionKey = questionKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final context = _firstOptionKey.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          alignment: 0.8,
          duration: Duration.zero,
        );
      }
    });
  }

  void _ensureSubmitVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final context = _submitKey.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          alignment: 0.8,
          duration: Duration.zero,
        );
      }
    });
  }

  bool _answered(UserQuestionView question) {
    final index = widget.payload.questions.indexOf(question);
    final key = _questionKey(question, index);
    final selected = _selectedOptions[key] ?? const <String>{};
    final text = _textControllers[key]?.text.trim() ?? '';
    return selected.isNotEmpty || text.isNotEmpty;
  }

  List<UserInputAnswerCommand> _answers() {
    final answers = <UserInputAnswerCommand>[];
    for (final entry in widget.payload.questions.indexed) {
      final index = entry.$1;
      final question = entry.$2;
      final key = _questionKey(question, index);
      final values = <String>[...(_selectedOptions[key] ?? const <String>{})];
      final text = _textControllers[key]?.text.trim() ?? '';
      if ((question.isOther || question.options.isEmpty) && text.isNotEmpty) {
        values.add(text);
      }
      answers.add(UserInputAnswerCommand(questionId: key, answers: values));
    }
    return answers;
  }

  void _submitFallbackAnswer() {
    final text = _fallbackController.text.trim();
    if (text.isEmpty) {
      return;
    }
    _submit(
      UserInputResolutionCommand(
        answers: [
          UserInputAnswerCommand(questionId: 'answer', answers: [text]),
        ],
      ),
    );
  }

  void _submitAnswers() {
    _submit(UserInputResolutionCommand(answers: _answers()));
  }

  /// root 自身交互走本会话目标，转交的 child 交互经主会话提交。
  void _submit(UserInputResolutionCommand resolution) =>
      widget.onSubmit(resolution);
}

String _questionKey(UserQuestionView question, int index) {
  final id = question.id.trim();
  return id.isEmpty ? 'answer_$index' : id;
}
