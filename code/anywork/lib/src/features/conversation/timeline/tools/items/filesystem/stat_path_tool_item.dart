import 'package:material_ui/material_ui.dart';

import '../../../../../../l10n/app_localizations.dart';
import '../../../state/tool_presentation.dart';
import '../../support/structured_tool_adapter.dart';
import '../../support/tool_detail_values.dart';
import '../../support/tool_status_labels.dart';
import '../../tool_item_adapter.dart';

/// Adapter for `builtin.stat_path@1`.
class StatPathToolItem extends StructuredTimelineToolAdapter {
  const StatPathToolItem();

  static const String contractId = 'builtin.stat_path@1';

  @override
  String get id => contractId;

  @override
  TimelineToolMatcher get matcher =>
      const TimelineToolMatcher.contract(contractId);

  @override
  List<String> get targetFields => const ['path'];

  @override
  bool get fileTarget => true;

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameStatPath;

  @override
  TimelineToolIcon buildIcon(TimelineToolItemContext context) =>
      const TimelineToolIcon.data(Icons.menu_book_outlined);

  @override
  String? verb(AppLocalizations l10n, TimelineToolPresentation item) {
    final running = timelineToolRunningStatuses.contains(item.statusString);
    final failed = item.statusString == 'failed';
    if (!running && !failed && item.statusString != 'succeeded') return null;
    return running
        ? l10n.timelineToolReadReading
        : failed
        ? l10n.timelineToolReadFailed
        : l10n.timelineToolReadCompleted;
  }

  @override
  List<ToolDetailValue> input(AppLocalizations l10n, String text) => toolField(
    l10n,
    toolArguments(l10n, text),
    'path',
    l10n.timelineToolDetailFile,
    required: true,
  );

  @override
  List<ToolDetailValue> output(AppLocalizations l10n, Object? result) {
    return switch (result) {
      {'exists': final bool exists} && final Map<String, dynamic> stat => [
        ToolDetailText(
          l10n.timelineToolDetailExists,
          exists ? l10n.timelineToolDetailYes : l10n.timelineToolDetailNo,
        ),
        if (stat['type'] case final String type)
          ToolDetailText(l10n.timelineToolDetailType, switch (type) {
            'file' => l10n.timelineToolFileTypeFile,
            'directory' => l10n.timelineToolFileTypeDirectory,
            'other' => l10n.timelineToolFileTypeOther,
            _ => type,
          }),
        if (stat['len'] case final int len)
          ToolDetailText(l10n.timelineToolDetailBytes, '$len'),
        if (stat['readonly'] case final bool readonly)
          ToolDetailText(
            l10n.timelineToolDetailReadOnly,
            readonly ? l10n.timelineToolDetailYes : l10n.timelineToolDetailNo,
          ),
        if (stat['modifiedAt'] case final int modifiedAt)
          ToolDetailText(
            l10n.timelineToolDetailModifiedAt,
            DateTime.fromMillisecondsSinceEpoch(modifiedAt)
                .toLocal()
                .toString(),
          ),
      ],
      final Map<String, dynamic> diagnostic => toolResultFields(
        l10n,
        diagnostic,
        toolDiagnosticFields(l10n),
      ),
      _ => [ToolDetailUnavailable(l10n.timelineToolStatMalformed)],
    };
  }
}
