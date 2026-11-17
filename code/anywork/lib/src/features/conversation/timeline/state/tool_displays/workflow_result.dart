import '../../../../../l10n/app_localizations.dart';
import '../tool_display.dart';

List<ToolDetailValue> toolWorkflowResult(
  AppLocalizations l10n,
  Object? result,
) {
  if (result case {'currentRun': null}) {
    return [
      ToolDetailText(
        l10n.timelineToolDetailWorkflow,
        l10n.timelineToolWorkflowNotStarted,
      ),
    ];
  }
  return toolResultFields(l10n, _workflowEnums(l10n, result), {
    'title': l10n.timelineToolDetailWorkflow,
    'goal': l10n.timelineToolDetailGoal,
    'currentState': l10n.timelineToolDetailCurrentPhase,
    'instructions': l10n.timelineToolDetailStageInstructions,
    'completionCriteria': l10n.timelineToolDetailCompletionCriteria,
    'lifecycle': l10n.timelineToolDetailStatus,
    'transitions': l10n.timelineToolDetailAvailableTransitions,
    'guard': l10n.timelineToolDetailTransitionGuard,
    'history': l10n.timelineToolDetailHistory,
    'summary': l10n.timelineToolDetailStageResult,
    'evidence': l10n.timelineToolDetailEvidence,
    'definition': l10n.timelineToolDetailWorkflow,
    'states': l10n.timelineToolDetailStages,
    ...toolDiagnosticFields(l10n),
  });
}

Object? _workflowEnums(AppLocalizations l10n, Object? value) => switch (value) {
  final List entries => [
    for (final entry in entries) _workflowEnums(l10n, entry),
  ],
  final Map<String, dynamic> object => {
    for (final MapEntry(:key, :value) in object.entries)
      key: switch ((key, value)) {
        ('lifecycle', 'active') => l10n.timelineToolWorkflowActive,
        ('lifecycle', 'terminal') => l10n.timelineToolWorkflowTerminal,
        _ =>
          const {
                'currentState',
                'transitions',
                'history',
                'definition',
                'states',
              }.contains(key)
              ? _workflowEnums(l10n, value)
              : value,
      },
  },
  _ => value,
};

ToolAcceptanceProjection toolWorkflowAcceptance(Object? result) =>
    switch (result) {
      {'accepted': true} => const ToolAcceptanceProjection(
        ToolAcceptance.accepted,
      ),
      {'accepted': false} && final Map<String, dynamic> rejected =>
        ToolAcceptanceProjection(
          ToolAcceptance.rejected,
          code: rejected['code'] is String ? rejected['code'] as String : null,
          reason: rejected['recoveryAction'] is String
              ? rejected['recoveryAction'] as String
              : null,
        ),
      _ => const ToolAcceptanceProjection(ToolAcceptance.pending),
    };
