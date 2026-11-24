import '../../../../../l10n/app_localizations.dart';
import 'tool_detail_values.dart';

/// Projects structured plan tool outputs into localized detail fields.
List<ToolDetailValue> toolPlanResult(AppLocalizations l10n, Object? result) =>
    toolProject(l10n, _planEnums(l10n, result), {
      'state': l10n.timelineToolDetailPlanPhase,
      'forced': l10n.timelineToolDetailForceTransition,
      'document': l10n.timelineToolDetailPlan,
      'markdown': l10n.timelineToolDetailPlanContent,
      'lastRevisionFeedback': l10n.timelineToolDetailRevisionFeedback,
      'allowedTransitions': l10n.timelineToolDetailAvailableOperations,
      'transitions': l10n.timelineToolDetailAvailableOperations,
      'operation': l10n.timelineToolDetailOperation,
      'targetState': l10n.timelineToolDetailTargetPhase,
      'condition': l10n.timelineToolDetailCondition,
      'action': l10n.timelineToolDetailAction,
      'history': l10n.timelineToolDetailHistory,
      'snapshot': l10n.timelineToolDetailCurrentPlan,
    });

Object? _planEnums(AppLocalizations l10n, Object? value) => switch (value) {
  final List entries => [for (final entry in entries) _planEnums(l10n, entry)],
  final Map<String, dynamic> object => {
    for (final MapEntry(:key, :value) in object.entries)
      key: switch ((key, value)) {
        ('state' || 'targetState', final String state) => switch (state) {
          'drafting' => l10n.timelineToolPlanDrafting,
          'awaitingConfirmation' => l10n.timelineToolPlanAwaitingConfirmation,
          'revisionRequested' => l10n.timelineToolPlanRevisionRequested,
          'approved' => l10n.timelineToolPlanApproved,
          _ => state,
        },
        ('forced', final bool forced) => forced.toString(),
        ('operation', final String operation) => switch (operation) {
          'submit' => l10n.timelineToolPlanSubmit,
          'approve' => l10n.timelineToolPlanApprove,
          'requestRevision' => l10n.timelineToolPlanRequestRevision,
          'restart' => l10n.timelineToolPlanRestart,
          _ => operation,
        },
        _ =>
          const {
                'document',
                'allowedTransitions',
                'transitions',
                'history',
                'snapshot',
              }.contains(key)
              ? _planEnums(l10n, value)
              : value,
      },
  },
  _ => value,
};
