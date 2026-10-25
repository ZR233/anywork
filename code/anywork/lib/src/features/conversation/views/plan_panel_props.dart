import 'package:flutter/material.dart';

import '../state/plan_view_state.dart';

/// UI props for the one Plan reading panel.
///
/// [sideBySideFeasible] is a measured layout fact from the caller: when the
/// real available width cannot hold both minimums, the reading-mode action is
/// not offered and the panel reads full width.
@immutable
final class PlanPanelProps {
  const PlanPanelProps({
    required this.state,
    required this.sideBySideFeasible,
    required this.onToggleReading,
    required this.onClose,
    required this.onRetry,
    required this.documentBuilder,
  });
  final PlanViewState state;
  final bool sideBySideFeasible;

  /// GUI-only reading mode: side-by-side <-> full width.
  final VoidCallback onToggleReading;

  /// Closes the reading panel; the conversation entry stays as the reopen path
  /// and no Session, draft or accepted command is affected.
  final VoidCallback onClose;
  final VoidCallback onRetry;
  final Widget Function(BuildContext, String) documentBuilder;
}
