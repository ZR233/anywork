import 'package:material_ui/material_ui.dart';

import '../../../../../../l10n/app_localizations.dart';
import '../../../state/tool_presentation.dart';
import '../../support/execution_result_support.dart';
import '../../support/structured_tool_adapter.dart';
import '../../support/tool_detail_values.dart';
import '../../support/tool_status_labels.dart';
import '../../tool_item_adapter.dart';

/// Adapter for `builtin.write_stdin@1` interactive process standard input writes.
class WriteStdinToolItem extends StructuredTimelineToolAdapter {
  const WriteStdinToolItem();

  static const String contractId = 'builtin.write_stdin@1';

  @override
  String get id => contractId;

  @override
  TimelineToolMatcher get matcher =>
      const TimelineToolMatcher.contract(contractId);

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameWriteStdin;

  @override
  TimelineToolIcon buildIcon(TimelineToolItemContext context) =>
      const TimelineToolIcon.data(Icons.terminal);

  @override
  String? verb(AppLocalizations l10n, TimelineToolPresentation item) =>
      toolLifecycleVerb(
        item.statusString,
        running: l10n.timelineToolStdinRunning,
        failed: l10n.timelineToolStdinFailed,
        succeeded: l10n.timelineToolStdinSucceeded,
      );

  @override
  List<ToolDetailValue> input(AppLocalizations l10n, String text) => toolField(
    l10n,
    toolArguments(l10n, text),
    'chars',
    l10n.timelineToolDetailStdin,
    code: true,
  );

  @override
  List<ToolDetailValue> output(AppLocalizations l10n, Object? result) =>
      toolExecutionResult(l10n, result);
}
