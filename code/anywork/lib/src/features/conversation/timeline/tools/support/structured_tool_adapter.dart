import 'package:material_ui/material_ui.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../../../shared/typed_json.dart';
import '../../state/tool_data_artifact.dart';
import '../../state/tool_presentation.dart';
import '../../widgets/timeline_activity_clock.dart';
import '../tool_item_adapter.dart';
import 'tool_acceptance_controller.dart';
import 'tool_detail_panel.dart';
import 'tool_detail_values.dart';
import 'tool_status_labels.dart';

/// Convenience base adapter preserving strict semantic projection, privacy
/// boundaries (no raw argument or unmapped task ID leaks), and acceptance gating.
abstract class StructuredTimelineToolAdapter extends TimelineToolItemAdapter {
  const StructuredTimelineToolAdapter();

  /// Builds the icon for the collapsed single-line row.
  TimelineToolIcon buildIcon(TimelineToolItemContext context);

  /// JSON keys inspected in order to extract condensed collapsed row targets.
  List<String> get targetFields => const [];

  /// Whether [targetFields] represent file paths shortened via basename.
  bool get fileTarget => false;

  /// Whether completed items show `elapsed` metadata (reserved for `exec`).
  @override
  bool get showsElapsedDuration => false;

  /// Optional driver/test card wrapper key.
  Key? buildCardKey(TimelineToolItemContext context) => null;

  /// Localized action verb for active/failed/succeeded states, or `null` to
  /// use [statusTitle] directly.
  String? verb(AppLocalizations l10n, TimelineToolPresentation item) => null;

  /// Decodes raw argument JSON string into validated semantic values.
  List<ToolDetailValue> input(AppLocalizations l10n, String text) => const [];

  /// Projects decoded output (`Map`/`List` when structured, `String` when text)
  /// into semantic detail values.
  List<ToolDetailValue> output(AppLocalizations l10n, Object? result) =>
      toolProject(l10n, result, const {});

  /// Extracts semantic values from `outputArtifacts`.
  List<ToolDetailValue> artifacts(AppLocalizations l10n, String text) =>
      const [];

  /// Evaluates acceptance state from a decoded JSON output object/list.
  ToolAcceptanceProjection acceptanceFromResult(Object? result) =>
      const ToolAcceptanceProjection(ToolAcceptance.pending);

  /// Extracts the compact display target from arguments.
  String? rowTarget(AppLocalizations l10n, TimelineToolPresentation item) {
    final arguments = decodeJsonObject(item.arguments);
    for (final key in targetFields) {
      final value = toolFirstLine(jsonStringValue(arguments[key]));
      if (value != null) {
        return fileTarget ? toolPathBasename(value) : value;
      }
    }
    return null;
  }

  /// Composes the single-line row headline from acceptance, lifecycle status,
  /// verb, and condensed target.
  String rowLabel(
    AppLocalizations l10n,
    TimelineToolPresentation item,
    String? target, {
    ToolAcceptanceProjection? acceptance,
  }) {
    final label = acceptanceLabel(l10n, item, acceptance);
    if (label != null) return [label, ?target].join(' ');
    final action = verb(l10n, item);
    if (action == null) {
      return [
        statusTitle(l10n, item),
        if (target != null && target.isNotEmpty) target,
      ].join(' · ');
    }
    return target == null || target.isEmpty ? action : '$action $target';
  }

  @override
  TimelineToolItemController createController(TimelineToolPresentation item) {
    if (bodyPolicy.requiresAcceptance) {
      return AcceptanceToolController(item, decoder: decodeAcceptanceData);
    }
    return super.createController(item);
  }

  @override
  ToolAcceptanceProjection decodeAcceptanceData(ToolDataArtifact data) =>
      !bodyPolicy.requiresAcceptance || data is! ToolDataArtifactPresent
      ? const ToolAcceptanceProjection(ToolAcceptance.pending)
      : acceptanceFromResult(data.value);

  @override
  List<ToolDetailValue> decodeInput(AppLocalizations l10n, String text) =>
      decodeToolValues(l10n, () => input(l10n, text));

  @override
  List<ToolDetailValue> decodeOutput(AppLocalizations l10n, String text) {
    return text.isEmpty ? const [] : toolTextResult(l10n, text);
  }

  @override
  List<ToolDetailValue> decodeOutputData(
    AppLocalizations l10n,
    String text,
    ToolDataArtifact data,
  ) {
    switch (data) {
      case ToolDataArtifactPresent(:final value):
        final emptyValue = _emptyJsonValue(value);
        if (emptyValue != null) {
          return [
            ToolDetailText(
              l10n.timelineToolDetailResult,
              emptyValue,
              code: true,
            ),
          ];
        }
        final projected = decodeToolValues(l10n, () => output(l10n, value));
        if (projected.isNotEmpty) return projected;
        return projected;
      case ToolDataArtifactInvalid(:final message):
        return [
          ToolDetailUnavailable(l10n.timelineToolContentMalformed(message)),
        ];
      case ToolDataArtifactAbsent() || ToolDataArtifactPending():
        return const [];
    }
  }

  String? _emptyJsonValue(Object? value) {
    if (value == null) return 'null';
    if (value is String && value.isEmpty) return '""';
    if (value is List && value.isEmpty) return '[]';
    if (value is Map && value.isEmpty) return '{}';
    return null;
  }

  @override
  List<ToolDetailValue> decodeArtifacts(AppLocalizations l10n, String text) =>
      decodeToolValues(l10n, () => artifacts(l10n, text));

  @override
  TimelineToolRowSummary buildRowSummary(TimelineToolItemContext context) {
    final l10n = context.l10n;
    final item = context.item;
    final acceptance = context.controller.acceptance;
    final target = rowTarget(l10n, item);
    final elapsed = showsElapsedDuration ? toolElapsed(item) : null;
    final active = isTimelineToolActive(item.statusString);
    final label = item.frozenObservation
        ? l10n.timelineToolArchivedUnfinished
        : !item.executionPresent && active
        ? l10n.timelineToolNotResumed
        : rowLabel(l10n, item, target, acceptance: acceptance);
    return TimelineToolRowSummary(
      icon: buildIcon(context),
      label: label,
      meta: elapsed == null
          ? null
          : activityDurationLabel(context.buildContext, elapsed.inSeconds),
      active: item.executionPresent && active,
      isIssue:
          isTimelineToolIssue(item.statusString) ||
          acceptance?.state == ToolAcceptance.rejected,
      isStopped: isTimelineToolStopped(item.statusString),
      cardKey: buildCardKey(context),
      disclosureKey: ValueKey('timeline-tool-details:${item.id}'),
    );
  }

  @override
  List<Widget> buildExpandedChildren(
    TimelineToolItemContext context,
    TimelineToolExpandedSlots slots,
  ) => slots.standardPanel == null ? const [] : [slots.standardPanel!];

  @override
  Widget? buildInlineBody(
    TimelineToolItemContext context, {
    ToolAcceptanceProjection? acceptance,
  }) {
    final item = context.item;
    final l10n = context.l10n;
    final inputValues = decodeInput(l10n, item.arguments);
    final outputValues =
        readsOutput(
          item.statusString,
          output: item.output,
          toolData: context.controller.toolData,
        )
        ? decodeOutput(l10n, item.output)
        : const <ToolDetailValue>[];
    if (inputValues.isEmpty && outputValues.isEmpty) {
      return null;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (inputValues.isNotEmpty)
          TimelineToolSemanticBody(values: inputValues),
        if (outputValues.isNotEmpty)
          TimelineToolSemanticBody(values: outputValues),
      ],
    );
  }

  @override
  Widget? buildToolDataBody(
    TimelineToolItemContext context, {
    ToolAcceptanceProjection? acceptance,
  }) {
    final data = context.controller.toolData;
    if (data is! ToolDataArtifactPresent && data is! ToolDataArtifactInvalid) {
      return null;
    }
    final values =
        data is ToolDataArtifactPresent &&
            bodyPolicy.requiresAcceptance &&
            acceptance != null &&
            acceptance.state != ToolAcceptance.accepted
        ? acceptanceDetails(context.l10n, acceptance)
        : decodeOutputData(context.l10n, context.item.output, data);
    return values.isEmpty ? null : TimelineToolSemanticBody(values: values);
  }

  @override
  Widget buildWindowBody(
    TimelineToolItemContext context,
    String windowText, {
    required bool isInput,
    ToolAcceptanceProjection? acceptance,
  }) {
    final l10n = context.l10n;
    return TimelineToolSemanticBody(
      values: isInput
          ? decodeInput(l10n, windowText)
          : decodeOutput(l10n, windowText),
    );
  }
}
