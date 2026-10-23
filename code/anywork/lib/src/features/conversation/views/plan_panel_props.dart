import 'package:flutter/material.dart';

import '../state/plan_view_state.dart';

/// UI props for the one Plan reading panel. Expanded is solely state.expanded;
/// Timeline has no second toggle value and this panel has no response intent.
@immutable
final class PlanPanelProps {
  const PlanPanelProps({required this.state, required this.onRetry, required this.documentBuilder});
  final PlanViewState state;
  final VoidCallback onRetry;
  final Widget Function(BuildContext, String) documentBuilder;
}
