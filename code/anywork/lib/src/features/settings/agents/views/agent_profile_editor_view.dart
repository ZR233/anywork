import 'package:anywork_client/configuration.dart';
import 'package:flutter/material.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../../../ui/selectors/effort_selector.dart';
import '../../../../ui/selectors/model_route_selector.dart';
import '../../widgets/settings_form_field.dart';
import '../../widgets/settings_source_status_view.dart';
import '../state/profile_editor_state.dart';
import '../widgets/agent_workspace_label.dart';

class AgentProfileEditorView extends StatelessWidget {
  const AgentProfileEditorView({required this.state, required this.options, required this.efforts,
    required this.unresolvedLabel, required this.hasMoreModels, required this.errors,
    required this.onId, required this.onDisplayName, required this.onDescription, required this.onWhenToUse,
    required this.onInstructions, required this.onRoute, required this.onEffort, required this.onWorkspaceMode,
    required this.onEnabled, required this.onMoreModels, required this.onRetrySuggestion,
    required this.onSave, required this.onCancel, super.key});
  final ProfileEditorViewState state;
  final List<ModelSelectionOption> options;
  final List<String> efforts;
  final String? unresolvedLabel;
  final bool hasMoreModels;
  final List<String> errors;
  final ValueChanged<String> onId;
  final ValueChanged<String> onDisplayName;
  final ValueChanged<String> onDescription;
  final ValueChanged<String> onWhenToUse;
  final ValueChanged<String> onInstructions;
  final Future<void> Function(ModelSelectionOption) onRoute;
  final ValueChanged<String?> onEffort;
  final ValueChanged<AgentWorkspaceMode> onWorkspaceMode;
  final ValueChanged<bool> onEnabled;
  final VoidCallback onMoreModels;
  final VoidCallback onRetrySuggestion;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final enabled = !(state.saveAction?.preventsResubmission ?? false);
    String? error(ProfileField field) => state.validation.containsKey(field) ? context.l10n.settingsAgentProfileRequired : null;
    Widget field(String value, String label, ValueChanged<String> changed, ProfileField key, {bool editable = true, int lines = 1}) =>
      Padding(padding: const EdgeInsets.only(bottom: 10), child: SettingsFormField(
        value: value, label: label, onChanged: changed, enabled: enabled && editable,
        maxLines: lines, error: error(key)));
    return AlertDialog(
      title: Text(state.key.profileId == null ? context.l10n.settingsAgentProfileAddTitle : context.l10n.settingsAgentProfileEditTitle),
      content: SizedBox(width: 560, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SettingsSourceStatusView(title: context.l10n.settingsAgentsTitle, brief: state.source.projection.header?.source.brief,
            read: state.source.sourceStatus, origin: state.source.projection.stamp?.origin,
            reference: state.source.projection.header?.source.status),
          for (final message in errors) SelectableText(message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          field(state.profileId, context.l10n.settingsAgentProfileIdField, onId, ProfileField.id, editable: state.key.profileId == null),
          field(state.displayName, context.l10n.settingsAgentProfileDisplayNameField, onDisplayName, ProfileField.displayName),
          field(state.description, context.l10n.settingsAgentProfileDescriptionField, onDescription, ProfileField.description),
          field(state.whenToUse, context.l10n.settingsAgentProfileWhenToUseField, onWhenToUse, ProfileField.whenToUse),
          field(state.instructions, context.l10n.settingsAgentProfileInstructionsField, onInstructions, ProfileField.instructions, lines: 6),
          Row(children: [Text(context.l10n.settingsModelField), const SizedBox(width: 10),
            Flexible(child: ModelRouteSelector(selectorKey: const ValueKey('agent-profile-model'),
              fieldLabel: context.l10n.settingsModelField, options: options, accountId: state.accountId,
              modelId: state.modelId, unresolvedLabel: unresolvedLabel, enabled: enabled,
              onSelected: onRoute)),
          ]),
          if (error(ProfileField.route) case final message?) Text(message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (hasMoreModels) Align(alignment: Alignment.centerLeft, child: TextButton.icon(
            onPressed: state.loadingModels ? null : onMoreModels, icon: const Icon(Icons.expand_more),
            label: Text(context.l10n.settingsSshNextPage))),
          const SizedBox(height: 10),
          Align(alignment: Alignment.centerLeft, child: EffortSelector(key: const ValueKey('agent-profile-effort'),
            efforts: efforts, selected: state.effort, allowDefault: true, enabled: enabled,
            pending: state.routeSuggestion?.pending == true, onSelected: onEffort)),
          if (state.routeSuggestion?.error != null) Align(alignment: Alignment.centerLeft,
            child: TextButton(onPressed: enabled ? onRetrySuggestion : null, child: Text(context.l10n.runtimeFatalRetry))),
          const SizedBox(height: 12),
          DropdownMenu<AgentWorkspaceMode>(key: const ValueKey('agent-profile-workspace-mode'),
            initialSelection: state.workspaceMode, label: Text(context.l10n.settingsAgentProfileWorkspaceModeField),
            enabled: enabled, expandedInsets: EdgeInsets.zero,
            dropdownMenuEntries: [for (final value in AgentWorkspaceMode.values)
              DropdownMenuEntry(value: value, label: agentWorkspaceLabel(context, value))],
            onSelected: (value) { if (value != null) onWorkspaceMode(value); }),
          if (state.workspaceMode == AgentWorkspaceMode.directory)
            Text(context.l10n.settingsAgentProfileWorkspaceDirectoryHint),
          if (state.workspaceMode == AgentWorkspaceMode.review)
            Text(context.l10n.settingsAgentProfileWorkspaceReviewHint),
          SwitchListTile(key: const ValueKey('agent-profile-enabled'), contentPadding: EdgeInsets.zero,
            title: Text(context.l10n.settingsAgentProfileEnabledTitle), subtitle: Text(context.l10n.settingsAgentProfileEnabledSubtitle),
            value: state.enabled, onChanged: enabled ? onEnabled : null),
        ]))),
      actions: [
        TextButton(onPressed: state.saveAction?.pending == true ? null : onCancel, child: Text(context.l10n.commonCancel)),
        FilledButton(key: const ValueKey('agent-profile-save'), onPressed: enabled && state.routeSuggestion?.pending != true ? onSave : null,
          child: Text(context.l10n.settingsAgentProfileSave)),
      ],
    );
  }
}
