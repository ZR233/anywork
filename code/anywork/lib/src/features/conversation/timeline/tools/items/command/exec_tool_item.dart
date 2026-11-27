import 'package:material_ui/material_ui.dart';

import '../../../../../../l10n/app_localizations.dart';
import '../../../../../../shared/typed_json.dart';
import '../../../state/tool_presentation.dart';
import '../../../widgets/timeline_activity_row.dart';
import '../../support/execution_result_support.dart';
import '../../support/structured_tool_adapter.dart';
import '../../support/tool_detail_values.dart';
import '../../support/tool_status_labels.dart';
import '../../tool_item_adapter.dart';

/// Adapter for `builtin.exec@2` shell command execution (and uncontracted live
/// `exec` / `exec_command` atoms).
class ExecToolItem extends StructuredTimelineToolAdapter {
  const ExecToolItem();

  static const String contractId = 'builtin.exec@2';

  @override
  String get id => contractId;

  @override
  TimelineToolMatcher get matcher => const TimelineToolMatcher.anyOf([
    TimelineToolMatcher.contract(contractId),
    TimelineToolMatcher.toolName('exec', requireEmptyContract: true),
    TimelineToolMatcher.toolName('exec_command', requireEmptyContract: true),
  ]);

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
  String? verb(AppLocalizations l10n, TimelineToolPresentation item) =>
      toolLifecycleVerb(
        item.statusString,
        running: l10n.timelineToolCommandRunning,
        failed: l10n.timelineToolCommandFailed,
        succeeded: l10n.timelineToolCommandSucceeded,
        backgroundStarted: l10n.timelineToolStateBackgroundStarted,
        backgrounded: l10n.timelineToolStateBackgrounded,
      );

  @override
  ToolRowTarget rowTarget(
    AppLocalizations l10n,
    TimelineToolPresentation item,
  ) {
    final direct = super.rowTarget(l10n, item);
    if (direct.label != null) return direct;
    final arguments = decodeJsonObject(item.arguments);
    final nested = jsonObject(arguments['args']);
    final fallback =
        toolFirstLine(jsonStringValue(nested['command'])) ??
        toolFirstLine(jsonStringValue(arguments['code']));
    return fallback == null ? direct : (label: fallback, tooltip: fallback);
  }

  @override
  TimelineToolRowSummary buildRowSummary(TimelineToolItemContext context) {
    final base = super.buildRowSummary(context);
    final item = context.item;
    final exitCode = item.exitCode ?? _outputExitCode(item.output);
    final showExitCode =
        exitCode != null &&
        (exitCode != 0 || isTimelineToolIssue(item.statusString));
    if (!showExitCode) return base;
    final exitLabel = context.l10n.timelineToolExitCode(exitCode);
    final meta = base.meta == null ? exitLabel : '$exitLabel · ${base.meta}';
    return TimelineToolRowSummary(
      icon: base.icon,
      label: base.label,
      tooltip: base.tooltip,
      meta: meta,
      active: base.active,
      isIssue: base.isIssue,
      isStopped: base.isStopped,
      cardKey: base.cardKey,
      disclosureKey: base.disclosureKey,
      semanticsLabel: base.semanticsLabel,
    );
  }

  static int? _outputExitCode(String output) {
    final value = decodeJsonObject(output)['exitCode'];
    return value is int ? value : null;
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
