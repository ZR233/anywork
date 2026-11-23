import 'package:material_ui/material_ui.dart';

import '../../../../../../l10n/app_localizations.dart';
import '../../../state/chat_item_presentation.dart';
import '../../../state/chat_payload_reading.dart';
import '../../../state/tool_presentation.dart';
import '../../support/structured_tool_adapter.dart';
import '../../support/task_state_values_support.dart';
import '../../support/tool_detail_values.dart';
import '../../tool_item_adapter.dart';

/// Adapter for `builtin.show_files@1`, also controlling standalone file-card
/// presentation routing in timeline and live member streams.
class ShowFilesToolItem extends StructuredTimelineToolAdapter {
  const ShowFilesToolItem();

  static const String contractId = 'builtin.show_files@1';

  @override
  String get id => contractId;

  @override
  TimelineToolMatcher get matcher =>
      const TimelineToolMatcher.contract(contractId);

  @override
  bool get usesFileArtifactsMedia => true;

  @override
  bool presentsStandaloneMedia(ChatItemPresentation item) {
    if (item.type != 'tool') return false;
    final state = chatObject(item.data['state'], 'state');
    return state['kind'] == 'succeeded' ||
        (state['kind'] == 'failed' &&
            item.body('tool.output-artifacts') != null);
  }

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      l10n.timelineToolNameShowFiles;

  @override
  TimelineToolIcon buildIcon(TimelineToolItemContext context) =>
      const TimelineToolIcon.data(Icons.image_outlined);

  @override
  List<ToolDetailValue> input(AppLocalizations l10n, String text) => toolField(
    l10n,
    toolArguments(l10n, text),
    'caption',
    l10n.timelineToolDetailDescription,
  );

  @override
  List<ToolDetailValue> output(AppLocalizations l10n, Object? result) =>
      toolProject(l10n, toolTaskStateValues(l10n, result), {
        'caption': l10n.timelineToolDetailDescription,
        'files': l10n.timelineToolDetailFile,
        'filename': l10n.timelineToolDetailFile,
        'outcome': l10n.timelineToolDetailResult,
        'status': l10n.timelineToolDetailStatus,
      });
}
