import '../../../../../l10n/app_localizations.dart';
import '../tool_display.dart';
import '../tool_presentation.dart';
import 'agent_result.dart';

final class SpawnAgentToolDisplay extends ToolDisplaySpec {
  const SpawnAgentToolDisplay()
    : super(
        'builtin.spawn_agent@1',
        ToolDisplayCategory.agent,
        targetFields: const ['taskSummary'],
        omitSuccessOutput: true,
      );

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameSpawnAgent;

  @override
  List<ToolDetailValue> input(AppLocalizations l10n, String text) {
    final data = toolArguments(l10n, text);
    return [
      ...toolField(
        l10n,
        data,
        'taskSummary',
        l10n.timelineToolDetailTask,
        required: true,
      ),
      ...toolField(
        l10n,
        data,
        'profileId',
        l10n.timelineToolDetailProfile,
        required: true,
      ),
      ...toolField(
        l10n,
        data,
        'message',
        l10n.timelineToolDetailTaskDescription,
        required: true,
      ),
    ];
  }

  @override
  List<ToolDetailValue> output(AppLocalizations l10n, Object? result) =>
      toolAgentResult(l10n, result);

  @override
  bool get requiresAcceptance => true;

  @override
  String rejectionLabel(AppLocalizations l10n) =>
      l10n.timelineToolSpawnRejected;

  @override
  ToolAcceptanceProjection acceptanceFromResult(Object? result) =>
      switch (result) {
        {'messageAccepted': true} => const ToolAcceptanceProjection(
          ToolAcceptance.accepted,
        ),
        {'messageAccepted': false} => const ToolAcceptanceProjection(
          ToolAcceptance.rejected,
        ),
        _ => const ToolAcceptanceProjection(ToolAcceptance.pending),
      };
}
