import 'package:anywork_client/modes.dart';
import 'package:anywork_client/workspace.dart';
import 'package:flutter/material.dart';

import '../../../diagnostics/studio_driver_keys.dart';
import '../../../l10n/studio_l10n.dart';
import '../../../ui/selectors/effort_selector.dart';
import '../../../ui/selectors/mode_selector.dart';
import '../../../ui/selectors/model_route_selector.dart';
import '../../../ui/selectors/workspace_mode_selector.dart';

class InputModelControlsView extends StatelessWidget {
  InputModelControlsView({
    required List<ThreadModeDescriptor> modes,
    required List<ModelSelectionOption> models,
    required List<String> efforts,
    required this.mode,
    required this.workspaceMode,
    required this.accountId,
    required this.modelId,
    required this.effort,
    required this.enabled,
    this.onMode,
    this.onWorkspaceMode,
    this.onModel,
    this.onEffort,
    this.onExplain,
    this.onDismiss,
    this.modeEnabled = true,
    this.showWorkspace = true,
    this.blockedReason,
    this.unavailableReason,
    this.explanation,
    this.sessionOptions,
    super.key,
  }) : modes = List.unmodifiable(modes),
       models = List.unmodifiable(models),
       efforts = List.unmodifiable(efforts);

  final List<ThreadModeDescriptor> modes;
  final List<ModelSelectionOption> models;
  final List<String> efforts;
  final ThreadModeId mode;
  final ThreadWorkspaceMode workspaceMode;
  final String accountId;
  final String modelId;
  final String? effort;
  final bool enabled;
  final bool modeEnabled;
  final bool showWorkspace;
  final String? blockedReason;
  final String? unavailableReason;
  final String? explanation;
  final Widget? sessionOptions;
  final ValueChanged<ThreadModeId>? onMode;
  final ValueChanged<ThreadWorkspaceMode>? onWorkspaceMode;
  final ValueChanged<ModelSelectionOption>? onModel;
  final ValueChanged<String>? onEffort;
  final ValueChanged<String>? onExplain;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (explanation case final message?)
        Row(
          children: [
            Expanded(
              child: Text(
                message,
                key: const ValueKey('input-model-explanation'),
              ),
            ),
            IconButton(
              onPressed: onDismiss,
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              icon: const Icon(Icons.close, size: 16),
            ),
          ],
        ),
      Wrap(
        spacing: 12,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ModeSelector(
            modes: modes,
            selected: mode,
            enabled: enabled && modeEnabled && onMode != null,
            onSelected: (next) => onMode?.call(next),
          ),
          if (showWorkspace)
            WorkspaceModeSelector(
              mode: workspaceMode,
              enabled: enabled && onWorkspaceMode != null,
              onSelected: (next) => onWorkspaceMode?.call(next),
            ),
          ModelRouteSelector(
            options: models,
            accountId: accountId,
            modelId: modelId,
            enabled: enabled && onModel != null,
            selectorKey: StudioDriverKeys.model,
            optionKeyBuilder: (option) =>
                StudioDriverKeys.modelOption(option.accountId, option.modelId),
            fieldLabel: context.l10n.settingsModelField,
            tooltip: blockedReason ?? unavailableReason,
            onBlockedTap: blockedReason != null && onExplain != null
                ? () => onExplain!(blockedReason!)
                : null,
            unresolvedLabel: modelId.isEmpty
                ? context.l10n.settingsMissing
                : context.l10n.settingsAgentRouteUnavailable(modelId),
            onSelected: (next) => onModel?.call(next),
          ),
          EffortSelector(
            efforts: efforts,
            selected: effort,
            enabled: (enabled && onEffort != null) || blockedReason != null,
            blockedReason: blockedReason,
            onExplain: onExplain,
            onSelected: (next) {
              if (next != null) onEffort?.call(next);
            },
          ),
          if (unavailableReason case final reason?)
            IconButton(
              tooltip: context.l10n.statusModelRouteUnavailable,
              onPressed: onExplain == null ? null : () => onExplain!(reason),
              icon: const Icon(Icons.warning_amber_outlined, size: 18),
            ),
          ?sessionOptions,
        ],
      ),
    ],
  );
}
