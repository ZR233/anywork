import 'dart:async';

import 'package:anywork_client/acp_sessions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../interactions/state/interaction_payload.dart';
import '../../interactions/views/plan_confirmation_view.dart';
import '../../interactions/views/user_input_view.dart';
import '../view_models/acp_session_view_model.dart';

class AcpHostInteractionConnector extends ConsumerWidget {
  const AcpHostInteractionConnector({
    super.key,
    required this.threadId,
    required this.onReadPlan,
  });

  final String threadId;
  final VoidCallback onReadPlan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner = ref
        .watch(acpConversationOwnerProvider(threadId))
        .asData
        ?.value;
    final current = ref.watch(
      acpConversationStateProvider(threadId).select((value) {
        final session = value.asData?.value;
        return (
          target: session?.target,
          interaction: session?.pendingHostInteraction,
          hasPlan: session?.workflowState?.plan?.document != null,
          submitting: session?.hostInteractionAnswerPending ?? false,
        );
      }),
    );
    final target = current.target;
    final interaction = current.interaction;
    if (owner == null || target == null || interaction == null) {
      return const SizedBox.shrink();
    }
    return _AcpHostInteractionCard(
      key: ValueKey((owner, target, interaction.id)),
      threadId: threadId,
      owner: owner,
      target: target,
      interaction: interaction,
      submitting: current.submitting,
      onReadPlan: current.hasPlan ? onReadPlan : null,
    );
  }
}

class _AcpHostInteractionCard extends ConsumerStatefulWidget {
  const _AcpHostInteractionCard({
    required super.key,
    required this.threadId,
    required this.owner,
    required this.target,
    required this.interaction,
    required this.submitting,
    this.onReadPlan,
  });

  final String threadId;
  final AcpConversationSession owner;
  final AcpSessionTargetView target;
  final AcpPendingInteractionView interaction;
  final bool submitting;
  final VoidCallback? onReadPlan;

  @override
  ConsumerState<_AcpHostInteractionCard> createState() =>
      _AcpHostInteractionCardState();
}

class _AcpHostInteractionCardState
    extends ConsumerState<_AcpHostInteractionCard> {
  String? _error;

  bool get _isCurrent {
    if (!mounted) return false;
    final owner = ref
        .read(acpConversationOwnerProvider(widget.threadId))
        .asData
        ?.value;
    return identical(owner, widget.owner) &&
        widget.owner.state.target == widget.target &&
        widget.owner.state.pendingHostInteraction?.id == widget.interaction.id;
  }

  Future<void> _answer(AcpHostInteractionAnswerView answer) async {
    if (!_isCurrent || widget.owner.state.hostInteractionAnswerPending) return;
    if (_error != null) setState(() => _error = null);
    try {
      await widget.owner.answerHostInteraction(
        AcpHostInteractionAnswerRequestView(
          target: widget.target,
          interactionId: widget.interaction.id,
          answer: answer,
        ),
      );
    } catch (error) {
      if (_isCurrent && !widget.owner.state.hostInteractionAnswerPending) {
        setState(() => _error = formatAcpError(error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final enabled = !widget.submitting;
    final cancel = TextButton(
      onPressed: enabled
          ? () => unawaited(_answer(const AcpHostCancelInteractionView()))
          : null,
      child: Text(l10n.commonCancel),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: switch (widget.interaction) {
        AcpPendingQuestionView(:final questions) => UserInputView(
          payload: InteractionPayloadSnapshot.userInput(questions: questions),
          enabled: enabled,
          preserveQuestionIds: true,
          error: _error,
          trailing: widget.submitting
              ? SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    semanticsLabel: l10n.planDecisionSubmitting,
                  ),
                )
              : cancel,
          onSubmit: (resolution) => unawaited(
            _answer(
              AcpHostQuestionAnswerView({
                for (final answer in resolution.answers)
                  answer.questionId: answer.answers,
              }),
            ),
          ),
        ),
        AcpPendingPlanConfirmationView(:final id) => PlanConfirmationView(
          interactionId: id,
          available: widget.onReadPlan != null,
          enabled: enabled,
          submitting: widget.submitting,
          error: _error,
          trailing: Wrap(
            alignment: WrapAlignment.end,
            children: [
              TextButton.icon(
                onPressed: widget.onReadPlan,
                icon: const Icon(Icons.description_outlined),
                label: Text(l10n.interactionPlanViewDetails),
              ),
              cancel,
            ],
          ),
          onSubmitRevision: (feedback) =>
              unawaited(_answer(AcpHostRevisePlanView(feedback))),
          onApprove: () => unawaited(_answer(const AcpHostApprovePlanView())),
        ),
      },
    );
  }
}
