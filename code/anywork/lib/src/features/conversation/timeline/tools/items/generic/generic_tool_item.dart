import 'package:material_ui/material_ui.dart';

import '../../../../../../l10n/app_localizations.dart';
import '../../../state/tool_presentation.dart';
import '../../support/structured_tool_adapter.dart';
import '../../support/tool_detail_values.dart';
import '../../tool_item_adapter.dart';

/// Fallback adapter for unknown or custom `presentationContract` tools (`generic@1`).
class GenericToolItem extends StructuredTimelineToolAdapter {
  const GenericToolItem();

  static const String contractId = 'generic@1';

  @override
  String get id => contractId;

  @override
  TimelineToolMatcher get matcher =>
      const TimelineToolMatcher.contract(contractId);

  @override
  TimelineToolBodyPolicy get bodyPolicy => const TimelineToolBodyPolicy(
    requiresJsonObjectArguments: false,
    readsStructuredOutput: false,
  );

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) =>
      item.name.trim().isEmpty || item.name == 'Tool'
      ? l10n.timelineToolFallback
      : item.name;

  @override
  TimelineToolIcon buildIcon(TimelineToolItemContext context) =>
      const TimelineToolIcon.data(Icons.build_outlined);

  @override
  List<ToolDetailValue> output(AppLocalizations l10n, Object? result) =>
      toolTextResult(l10n, result);
}
