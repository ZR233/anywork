import 'package:anywork_client/configuration.dart';
import 'package:flutter/material.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../../../ui/selectors/model_route_selector.dart';
import '../../widgets/settings_feedback.dart';
import '../../accounts/widgets/auto_page_loader.dart';
import '../../widgets/settings_field_label.dart';
import '../../widgets/settings_form_dialog.dart';
import '../../widgets/settings_form_field.dart';
import '../../widgets/settings_form_layout.dart';
import '../state/profile_editor_state.dart';
import '../widgets/agent_workspace_label.dart';

/// Agent profile editor.
///
/// Layout follows the pre-refactor dialog: bounded 560 content inside the
/// shared form dialog, identity fields first, then the model route, reasoning
/// effort, workspace mode with its hint and the enabled switch. Read failures
/// surface as an inline notice instead of permanent status rows.
class AgentProfileEditorView extends StatelessWidget {
  const AgentProfileEditorView({
    required this.state,
    required this.options,
    required this.efforts,
    required this.unresolvedLabel,
    required this.hasMoreModels,
    required this.errors,
    required this.onId,
    required this.onDisplayName,
    required this.onDescription,
    required this.onWhenToUse,
    required this.onInstructions,
    required this.onRoute,
    required this.onEffort,
    required this.onWorkspaceMode,
    required this.onEnabled,
    required this.onMoreModels,
    required this.onRetrySuggestion,
    required this.onSave,
    required this.onCancel,
    super.key,
  });
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
    final text = Theme.of(context).textTheme;
    final enabled = !(state.saveAction?.preventsResubmission ?? false);
    final suggesting = state.routeSuggestion?.pending == true;
    String? error(ProfileField field) => state.validation.containsKey(field)
        ? context.l10n.settingsAgentProfileRequired
        : null;
    Widget field(
      String value,
      String label,
      ValueChanged<String> changed,
      ProfileField key, {
      bool editable = true,
      int lines = 1,
    }) => SettingsFormField(
      value: value,
      label: label,
      onChanged: changed,
      enabled: enabled && editable,
      maxLines: lines,
      error: error(key),
    );
    final routeError = error(ProfileField.route);
    return SettingsFormDialog(
      title: Text(
        state.key.profileId == null
            ? context.l10n.settingsAgentProfileAddTitle
            : context.l10n.settingsAgentProfileEditTitle,
      ),
      content: AutoPageLoader(
        hasMore: hasMoreModels,
        loading: state.loadingModels,
        blocked: false,
        requestedCount: options.length,
        onLoadMore: onMoreModels,
        child: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (errors.isNotEmpty) ...[
                  SettingsInlineError(message: errors.join('\n')),
                  const SizedBox(height: 12),
                ],
                SettingsFieldStack(
                  children: [
                    field(
                      state.profileId,
                      context.l10n.settingsAgentProfileIdField,
                      onId,
                      ProfileField.id,
                      editable: state.key.profileId == null,
                    ),
                    field(
                      state.displayName,
                      context.l10n.settingsAgentProfileDisplayNameField,
                      onDisplayName,
                      ProfileField.displayName,
                    ),
                    field(
                      state.description,
                      context.l10n.settingsAgentProfileDescriptionField,
                      onDescription,
                      ProfileField.description,
                    ),
                    field(
                      state.whenToUse,
                      context.l10n.settingsAgentProfileWhenToUseField,
                      onWhenToUse,
                      ProfileField.whenToUse,
                    ),
                    field(
                      state.instructions,
                      context.l10n.settingsAgentProfileInstructionsField,
                      onInstructions,
                      ProfileField.instructions,
                      lines: 6,
                    ),
                  ],
                ),
                Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: SettingsFieldLabel(
                        label: context.l10n.settingsModelField,
                      ),
                    ),
                    Flexible(
                      child: ModelRouteSelector(
                        selectorKey: const ValueKey('agent-profile-model'),
                        fieldLabel: context.l10n.settingsModelField,
                        options: options,
                        accountId: state.accountId,
                        modelId: state.modelId,
                        unresolvedLabel: unresolvedLabel,
                        enabled: options.isNotEmpty && enabled && !suggesting,
                        onSelected: onRoute,
                      ),
                    ),
                  ],
                ),
                if (routeError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 8),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        routeError,
                        style: text.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                if (state.routeSuggestion?.error != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: enabled ? onRetrySuggestion : null,
                      child: Text(context.l10n.runtimeFatalRetry),
                    ),
                  ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownMenu<String?>(
                        key: const ValueKey('agent-profile-effort'),
                        initialSelection: state.effort,
                        label: Text(context.l10n.statusReasoningEffort),
                        hintText:
                            context.l10n.settingsAgentProfileEffortDefault,
                        enabled: enabled && !suggesting,
                        expandedInsets: EdgeInsets.zero,
                        dropdownMenuEntries: [
                          DropdownMenuEntry<String?>(
                            value: null,
                            label:
                                context.l10n.settingsAgentProfileEffortDefault,
                          ),
                          if (state.effort case final selection?
                              when !efforts.contains(selection))
                            DropdownMenuEntry<String?>(
                              value: selection,
                              label: selection,
                            ),
                          for (final effort in efforts)
                            DropdownMenuEntry<String?>(
                              value: effort,
                              label: effort,
                            ),
                        ],
                        onSelected: onEffort,
                      ),
                    ),
                    if (suggesting)
                      const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: SizedBox.square(
                          dimension: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownMenu<AgentWorkspaceMode>(
                  key: const ValueKey('agent-profile-workspace-mode'),
                  initialSelection: state.workspaceMode,
                  label: Text(
                    context.l10n.settingsAgentProfileWorkspaceModeField,
                  ),
                  enabled: enabled,
                  expandedInsets: EdgeInsets.zero,
                  dropdownMenuEntries: [
                    for (final value in AgentWorkspaceMode.values)
                      DropdownMenuEntry(
                        value: value,
                        label: agentWorkspaceLabel(context, value),
                      ),
                  ],
                  onSelected: (value) {
                    if (value != null) onWorkspaceMode(value);
                  },
                ),
                if (state.workspaceMode == AgentWorkspaceMode.directory)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 10),
                    child: Text(
                      context.l10n.settingsAgentProfileWorkspaceDirectoryHint,
                    ),
                  ),
                if (state.workspaceMode == AgentWorkspaceMode.review)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 10),
                    child: Text(
                      context.l10n.settingsAgentProfileWorkspaceReviewHint,
                    ),
                  ),
                SwitchListTile(
                  key: const ValueKey('agent-profile-enabled'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.l10n.settingsAgentProfileEnabledTitle),
                  subtitle: Text(
                    context.l10n.settingsAgentProfileEnabledSubtitle,
                  ),
                  value: state.enabled,
                  onChanged: enabled ? onEnabled : null,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: state.saveAction?.pending == true ? null : onCancel,
          child: Text(context.l10n.commonCancel),
        ),
        FilledButton(
          key: const ValueKey('agent-profile-save'),
          onPressed: enabled && !suggesting ? onSave : null,
          child: Text(context.l10n.settingsAgentProfileSave),
        ),
      ],
    );
  }
}
