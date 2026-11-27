import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../../../shared/typed_json.dart';
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

  /// Extracts compact display target and full hover tooltip from arguments.
  ToolRowTarget rowTarget(
    AppLocalizations l10n,
    TimelineToolPresentation item,
  ) {
    final arguments = decodeJsonObject(item.arguments);
    for (final key in targetFields) {
      final value = toolFirstLine(jsonStringValue(arguments[key]));
      if (value != null) {
        return (
          label: fileTarget ? toolPathBasename(value) : value,
          tooltip: value,
        );
      }
    }
    return (label: null, tooltip: null);
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
      return AcceptanceToolController(item, decoder: decodeAcceptance);
    }
    return super.createController(item);
  }

  @override
  ToolAcceptanceProjection decodeAcceptance(String text) {
    if (text.trim().isEmpty || !bodyPolicy.requiresAcceptance) {
      return const ToolAcceptanceProjection(ToolAcceptance.pending);
    }
    try {
      final result = jsonDecode(text);
      return result is Map<String, dynamic> || result is List
          ? acceptanceFromResult(result)
          : const ToolAcceptanceProjection(ToolAcceptance.pending);
    } on FormatException {
      return const ToolAcceptanceProjection(ToolAcceptance.pending);
    }
  }

  @override
  List<ToolDetailValue> decodeInput(AppLocalizations l10n, String text) =>
      decodeToolValues(l10n, () => input(l10n, text));

  @override
  List<ToolDetailValue> decodeOutput(AppLocalizations l10n, String text) {
    if (text.trim().isEmpty) return const [];
    return decodeToolValues(l10n, () {
      final Object result = bodyPolicy.readsStructuredOutput
          ? toolStructuredResult(l10n, text)
          : text;
      final projection = bodyPolicy.requiresAcceptance
          ? decodeAcceptance(text)
          : null;
      return projection != null && projection.state != ToolAcceptance.pending
          ? acceptanceDetails(l10n, projection)
          : output(l10n, result);
    });
  }

  @override
  List<ToolDetailValue> decodeArtifacts(AppLocalizations l10n, String text) =>
      decodeToolValues(l10n, () => artifacts(l10n, text));

  @override
  TimelineToolRowSummary buildRowSummary(TimelineToolItemContext context) {
    final l10n = context.l10n;
    final item = context.item;
    final acceptance = context.controller.acceptance;
    final targets = rowTarget(l10n, item);
    final elapsed = showsElapsedDuration ? toolElapsed(item) : null;
    final active = isTimelineToolActive(item.statusString);
    final label = item.frozenObservation
        ? l10n.timelineToolArchivedUnfinished
        : !item.executionPresent && active
        ? l10n.timelineToolNotResumed
        : rowLabel(l10n, item, targets.label, acceptance: acceptance);
    return TimelineToolRowSummary(
      icon: buildIcon(context),
      label: label,
      tooltip: targets.tooltip,
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
    final outputValues = readsOutput(item.statusString, output: item.output)
        ? acceptance != null && acceptance.state != ToolAcceptance.pending
              ? acceptanceDetails(l10n, acceptance)
              : decodeOutput(l10n, item.output)
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
  Widget buildWindowBody(
    TimelineToolItemContext context,
    String windowText, {
    required bool isInput,
    ToolAcceptanceProjection? acceptance,
  }) {
    final l10n = context.l10n;
    if (!isInput && bodyPolicy.requiresAcceptance) {
      return TimelineToolSemanticBody(
        values: acceptanceDetails(
          l10n,
          acceptance ?? const ToolAcceptanceProjection(ToolAcceptance.pending),
        ),
      );
    }
    if (!isInput &&
        bodyPolicy.readsStructuredOutput &&
        windowText.trim().isEmpty) {
      return TimelineToolSemanticBody(
        values: [ToolDetailUnavailable(l10n.timelineToolStructuredUnavailable)],
      );
    }
    return TimelineToolSemanticBody(
      values: isInput
          ? decodeInput(l10n, windowText)
          : decodeOutput(l10n, windowText),
    );
  }
}
