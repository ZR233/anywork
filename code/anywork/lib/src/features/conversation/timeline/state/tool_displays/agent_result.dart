import '../../../../../l10n/app_localizations.dart';
import '../tool_display.dart';
import 'task_state_values.dart';

List<ToolDetailValue> toolAgentResult(AppLocalizations l10n, Object? result) =>
    toolProject(l10n, toolTaskStateValues(l10n, result), {
      'messageAccepted': l10n.timelineToolDetailInputAccepted,
      'status': l10n.timelineToolDetailStatus,
      'state': l10n.timelineToolDetailStatus,
      'report': l10n.timelineToolDetailReport,
      'text': l10n.timelineToolDetailContent,
      'summary': l10n.timelineToolDetailSummary,
    });
