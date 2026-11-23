import 'package:material_ui/material_ui.dart';

import '../../../../../../l10n/app_localizations.dart';
import '../../../state/tool_presentation.dart';
import '../../../widgets/timeline_activity_row.dart';
import '../../support/execution_result_support.dart';
import '../../support/structured_tool_adapter.dart';
import '../../support/tool_detail_values.dart';
import '../../support/tool_status_labels.dart';
import '../../tool_item_adapter.dart';

/// Adapter for `builtin.exec@2` shell command execution.
class ExecToolItem extends StructuredTimelineToolAdapter {
  const ExecToolItem();

  static const String contractId = 'builtin.exec@2';

  @override
  String get id => contractId;

  @override
  TimelineToolMatcher get matcher =>
      const TimelineToolMatcher.contract(contractId);

  @override
  List<String> get targetFields => const ['command'];

  @override
  bool get showsElapsedDuration => true;

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameExec;

  @override
  TimelineToolIcon buildIcon(TimelineToolItemContext context) =>
      const TimelineToolIcon.data(
        Icons.terminal,
        activeIndicatorStyle: TimelineActivityIndicatorStyle.circularProgress,
      );

  @override
  String? verb(AppLocalizations l10n, TimelineToolPresentation item) {
    final running = timelineToolRunningStatuses.contains(item.statusString);
    final failed = item.statusString == 'failed';
    if (!running && !failed && item.statusString != 'succeeded') return null;
    return running
        ? l10n.timelineToolCommandRunning
        : failed
        ? l10n.timelineToolCommandFailed
        : l10n.timelineToolCommandSucceeded;
  }

  @override
  List<ToolDetailValue> input(AppLocalizations l10n, String text) => toolField(
    l10n,
    toolArguments(l10n, text),
    'command',
    l10n.timelineToolDetailProgram,
    code: true,
    required: true,
  );

  @override
  List<ToolDetailValue> output(AppLocalizations l10n, Object? result) =>
      toolExecutionResult(l10n, result);
}
