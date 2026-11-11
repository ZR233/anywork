import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/studio_models.dart' show PlanConfirmationView;
import '../views/plan_confirmation_view.dart' as plan_view;
import '../view_models/plan_confirmation_view_model.dart';

/// Plan confirmation connector: observes the feature projection and connects its actions.
class PlanConfirmationConnector extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final model = ref.watch(planConfirmationViewModelProvider(threadId));
    final state = model.stateFor(plan, enabled: enabled);
    return plan_view.PlanConfirmationView(
      interactionId: plan.interactionId,
      available: state.canDecide,
      submitting: state.submitting,
      enabled: state.canEdit,
      error: state.error,
      trailing: trailing,
      onSubmitRevision: (feedback) =>
          model.submitRevision(plan, feedback, enabled: enabled),
      onApprove: () => model.approve(plan, enabled: enabled),
    );
  }
}
