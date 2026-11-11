import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../state/acp_view_state.dart';
import '../view_models/acp_plan_card_view_model.dart';
import '../widgets/acp_plan_card.dart';

/// Thin Riverpod connector binding [acpPlanCardViewModelProvider] to the pure
/// collapsible [AcpPlanCard].
class AcpPlanCardConnector extends ConsumerWidget {
  const AcpPlanCardConnector({super.key, required this.threadId});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(acpPlanCardViewModelProvider(threadId));
    if (state == null) return const SizedBox.shrink();
    return AcpPlanCard(
      key: ValueKey(AcpViewKeyValues.planCard(threadId)),
      state: state,
    );
  }
}
