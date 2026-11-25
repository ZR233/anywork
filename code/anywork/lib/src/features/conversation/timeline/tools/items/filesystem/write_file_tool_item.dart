import 'package:material_ui/material_ui.dart';

import '../../../../../../l10n/app_localizations.dart';
import '../../../state/tool_presentation.dart';
import '../../support/structured_tool_adapter.dart';
import '../../support/tool_detail_values.dart';
import '../../support/tool_status_labels.dart';
import '../../tool_item_adapter.dart';

/// Adapter for `builtin.write_file@1`.
class WriteFileToolItem extends StructuredTimelineToolAdapter {
  const WriteFileToolItem();

  static const String contractId = 'builtin.write_file@1';

  @override
  String get id => contractId;

  @override
  TimelineToolMatcher get matcher =>
      const TimelineToolMatcher.contract(contractId);

  @override
  TimelineToolBodyPolicy get bodyPolicy => const TimelineToolBodyPolicy(
    readsArgumentsWindow: true,
    omitSuccessOutput: true,
  );

  @override
  List<String> get targetFields => const ['path'];

  @override
  bool get fileTarget => true;

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameWriteFile;

  @override
  TimelineToolIcon buildIcon(TimelineToolItemContext context) =>
      const TimelineToolIcon.data(Icons.edit_outlined);

  @override
  String? verb(AppLocalizations l10n, TimelineToolPresentation item) =>
      toolLifecycleVerb(
        item.statusString,
        running: l10n.timelineToolEditRunning,
        failed: l10n.timelineToolEditFailed,
        succeeded: l10n.timelineToolEditSucceeded,
      );

  @override
  List<ToolDetailValue> input(AppLocalizations l10n, String text) {
    final data = toolArguments(l10n, text);
    return [
      ...toolField(
        l10n,
        data,
        'path',
        l10n.timelineToolDetailFile,
        required: true,
      ),
      ToolDetailText(l10n.timelineToolDetailWriteMode, switch (data['mode']) {
        'create' => l10n.timelineToolWriteCreate,
        'overwrite' => l10n.timelineToolWriteOverwrite,
        'append' => l10n.timelineToolWriteAppend,
        _ => throw FormatException(l10n.timelineToolInvalidWriteMode),
      }),
      ...toolField(
        l10n,
        data,
        'content',
        l10n.timelineToolDetailContent,
        code: true,
        required: true,
      ),
    ];
  }
}
