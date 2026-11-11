import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/studio_models.dart';
import '../../../../presentation/providers/thread_session_store.dart';
import '../state/interaction_payload.dart';
import 'interaction_command_view_model.dart';

enum PlanConfirmationFeedbackPhase {
  resolvable,
  submitting,
  acceptedAwaitingRemoval,
  failedRetryable,
  invalid,
}

final class PlanConfirmationFeedbackState {
  const PlanConfirmationFeedbackState({required this.phase, this.error});

  final PlanConfirmationFeedbackPhase phase;
  final String? error;

  bool get canDecide =>
      phase == PlanConfirmationFeedbackPhase.resolvable ||
      phase == PlanConfirmationFeedbackPhase.failedRetryable;

  bool get canEdit => canDecide;

  bool get submitting =>
      phase == PlanConfirmationFeedbackPhase.submitting ||
      phase == PlanConfirmationFeedbackPhase.acceptedAwaitingRemoval;
}

/// Observes canonical interaction and existing command projection, and delegates decisions
/// to the shared command owner. It holds no independent command or plan lifecycle state.
final class PlanConfirmationViewModel {
  const PlanConfirmationViewModel(
    this._ref, {
    required this.threadId,
    required this.interactions,
    required this.commands,
  });

  final Ref _ref;
  final String threadId;
  final List<PendingInteraction> interactions;
  final InteractionCommandViewState? commands;

  PlanConfirmationFeedbackState stateFor(
    PlanConfirmationView plan, {
    required bool enabled,
  }) {
    final current = activePendingInteraction(interactions);
    if (!enabled ||
        current?.id != plan.interactionId ||
        current?.threadId != threadId ||
        current?.revision != plan.interaction.revision ||
        current?.planConfirmation?.questionId != plan.questionId) {
      return const PlanConfirmationFeedbackState(
        phase: PlanConfirmationFeedbackPhase.invalid,
      );
    }
    final action = commands?.status(plan.interactionId);
    if (action?.pending == true) {
      return const PlanConfirmationFeedbackState(
        phase: PlanConfirmationFeedbackPhase.submitting,
      );
    }
    if (action?.accepted == true) {
      return const PlanConfirmationFeedbackState(
        phase: PlanConfirmationFeedbackPhase.acceptedAwaitingRemoval,
      );
    }
    if (action?.error case final error?) {
      return PlanConfirmationFeedbackState(
        phase: PlanConfirmationFeedbackPhase.failedRetryable,
        error: _commandFailure(error),
      );
    }
    if (action?.blocked == true) {
      return const PlanConfirmationFeedbackState(
        phase: PlanConfirmationFeedbackPhase.invalid,
      );
    }
    return const PlanConfirmationFeedbackState(
      phase: PlanConfirmationFeedbackPhase.resolvable,
    );
  }

  Future<void> submitRevision(
    PlanConfirmationView plan,
    String feedback, {
    required bool enabled,
  }) {
    final trimmed = feedback.trim();
    if (trimmed.isEmpty) return Future<void>.value();
    return _resolve(plan, [
      agentSessionPlanReviseAnswer,
      trimmed,
    ], enabled: enabled);
  }

  Future<void> approve(PlanConfirmationView plan, {required bool enabled}) =>
      _resolve(plan, const [agentSessionPlanApproveAnswer], enabled: enabled);

  Future<void> _resolve(
    PlanConfirmationView plan,
    List<String> answers, {
    required bool enabled,
  }) async {
    if (!enabled || !_ref.mounted) return;
    final threadId = this.threadId;
    final interactionId = plan.interactionId;
    final questionId = plan.questionId;
    final session = _ref.read(threadSessionStoreProvider(threadId));
    final current = activePendingInteraction(session.interactions);
    if (current == null ||
        current.id != interactionId ||
        current.threadId != threadId ||
        current.revision != plan.interaction.revision ||
        current.planConfirmation?.questionId != questionId) {
      return;
    }
    final action = _ref
        .read(interactionCommandViewModelProvider(threadId))
        .value
        ?.status(interactionId);
    if (action?.blocked == true ||
        action?.pending == true ||
        action?.accepted == true) {
      return;
    }
    try {
      await _ref
          .read(interactionCommandViewModelProvider(threadId).notifier)
          .resolveActive(
            threadId,
            interactionId,
            plan.interaction.revision,
            UserInputResolutionCommand(
              answers: [
                UserInputAnswerCommand(
                  questionId: questionId,
                  answers: answers,
                ),
              ],
            ),
          );
    } on Object {
      // The shared command observation exposes the actual typed failure to the view.
    }
  }
}

final planConfirmationViewModelProvider = Provider.autoDispose
    .family<PlanConfirmationViewModel, String>((ref, threadId) {
      final session = ref.watch(threadSessionStoreProvider(threadId));
      final commands = ref
          .watch(interactionCommandViewModelProvider(threadId))
          .value;
      return PlanConfirmationViewModel(
        ref,
        threadId: threadId,
        interactions: session.interactions,
        commands: commands,
      );
    });

String _commandFailure(Object error) {
  if (error case final StudioFailure failure) {
    final message = failure.message.trim();
    if (message.isNotEmpty) return message;
    return failure.code.name;
  }
  return '$error';
}
