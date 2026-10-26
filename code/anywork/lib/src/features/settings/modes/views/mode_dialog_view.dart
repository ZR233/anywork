import 'package:anywork_client/modes.dart';
import 'package:flutter/material.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../../../ui/feedback/studio_messages.dart';
import '../../widgets/settings_form_field.dart';
import '../state/mode_editor_state.dart';
import '../state/mode_dialog_state.dart';

class ModeDialogView extends StatelessWidget {
  const ModeDialogView({
    required this.state,
    required this.errors,
    required this.onId,
    required this.onName,
    required this.onTemplate,
    required this.onGuard,
    required this.onSource,
    required this.onTarget,
    required this.onJson,
    required this.onCancel,
    required this.onSubmit,
    super.key,
  });
  final ModeEditorViewState state;
  final List<String> errors;
  final ValueChanged<String> onId;
  final ValueChanged<String> onName;
  final ValueChanged<ModeTemplateKind> onTemplate;
  final ValueChanged<String> onGuard;
  final ValueChanged<String?> onSource;
  final ValueChanged<String?> onTarget;
  final ValueChanged<String> onJson;
  final VoidCallback onCancel;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final draft = state.dialog!;
    final l10n = context.l10n;
    final workflow = state.document?.definition.workflow;
    final prefix = switch (draft.kind) {
      ModeDialogKind.create => 'create',
      ModeDialogKind.importJson => 'import',
      ModeDialogKind.renameState => 'rename-state',
      ModeDialogKind.transition => 'transition',
    };
    return PopScope(
      canPop: !state.busy,
      child: AlertDialog(
        key: ValueKey('mode-editor-$prefix-dialog'),
        scrollable: true,
        title: Text(switch (draft.kind) {
          ModeDialogKind.create => l10n.modeEditorNewWorkMode,
          ModeDialogKind.importJson => l10n.modeEditorImportDialogTitle,
          ModeDialogKind.renameState => l10n.modeEditorRenameStateTitle,
          ModeDialogKind.transition => l10n.modeEditorAddTransition,
        }),
        content: SizedBox(
          width: draft.kind == ModeDialogKind.importJson ? 680 : 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (draft.kind == ModeDialogKind.create) ...[
                SettingsFormField(
                  key: const ValueKey('mode-editor-create-name'),
                  value: draft.name,
                  label: l10n.modeEditorModeName,
                  enabled: !state.busy,
                  onChanged: onName,
                ),
                const SizedBox(height: 12),
                SettingsFormField(
                  key: const ValueKey('mode-editor-create-id'),
                  value: draft.id,
                  label: l10n.modeEditorModeId,
                  enabled: !state.busy,
                  onChanged: onId,
                ),
                const SizedBox(height: 16),
                Text(l10n.modeEditorStartingPoint),
                SegmentedButton<ModeTemplateKind>(
                  key: const ValueKey('mode-editor-create-template'),
                  segments: [
                    ButtonSegment(
                      value: ModeTemplateKind.minimal,
                      label: Text(l10n.modeEditorMinimalWorkflow),
                    ),
                    ButtonSegment(
                      value: ModeTemplateKind.none,
                      label: Text(l10n.modeEditorNoWorkflowTemplate),
                    ),
                  ],
                  selected: {draft.template},
                  onSelectionChanged: state.busy
                      ? null
                      : (values) => onTemplate(values.first),
                ),
              ],
              if (draft.kind == ModeDialogKind.importJson) ...[
                Text(l10n.modeEditorImportDialogBody),
                SettingsFormField(
                  key: const ValueKey('mode-editor-import-json'),
                  value: state.jsonText,
                  label: l10n.modeEditorTabJson,
                  enabled: !state.busy,
                  minLines: 14,
                  maxLines: 20,
                  code: true,
                  onChanged: onJson,
                ),
                for (final issue in state.issues)
                  SelectableText(
                    '${issue.path}: ${issue.message} [${issue.code}]',
                  ),
              ],
              if (draft.kind == ModeDialogKind.renameState)
                SettingsFormField(
                  key: const ValueKey('mode-editor-inspector-state-id'),
                  value: draft.id,
                  label: l10n.modeEditorStateId,
                  enabled: !state.busy,
                  onChanged: onId,
                ),
              if (draft.kind == ModeDialogKind.transition) ...[
                DropdownMenu<String>(
                  key: const ValueKey('mode-editor-inspector-new-source'),
                  initialSelection: draft.sourceId,
                  enabled: !state.busy,
                  label: Text(l10n.modeEditorSourceState),
                  dropdownMenuEntries: [
                    for (final node
                        in workflow?.states ?? const <WorkflowState>[])
                      if (node.kind == WorkflowStateKind.atomic)
                        DropdownMenuEntry(value: node.id, label: node.title),
                  ],
                  onSelected: onSource,
                ),
                const SizedBox(height: 12),
                DropdownMenu<String>(
                  key: const ValueKey('mode-editor-inspector-new-target'),
                  initialSelection: draft.targetId,
                  enabled: !state.busy,
                  label: Text(l10n.modeEditorTargetState),
                  dropdownMenuEntries: [
                    for (final node
                        in workflow?.states ?? const <WorkflowState>[])
                      DropdownMenuEntry(value: node.id, label: node.title),
                  ],
                  onSelected: onTarget,
                ),
                const SizedBox(height: 12),
                SettingsFormField(
                  key: const ValueKey('mode-editor-inspector-new-guard'),
                  value: draft.guard,
                  label: l10n.modeEditorTransitionGuard,
                  enabled: !state.busy,
                  minLines: 3,
                  maxLines: 5,
                  onChanged: onGuard,
                ),
              ],
              if (draft.validation case final issue?)
                Text(switch (issue) {
                  ModeDialogValidation.nameRequired =>
                    l10n.modeEditorModeNameRequired,
                  ModeDialogValidation.invalidModeId =>
                    l10n.modeEditorModeIdFormat,
                  ModeDialogValidation.modeExists =>
                    l10n.modeEditorModeIdExists,
                  ModeDialogValidation.invalidStateId =>
                    l10n.modeEditorStateIdInvalid,
                  ModeDialogValidation.stateExists =>
                    l10n.modeEditorStateIdExists,
                  ModeDialogValidation.sourceRequired =>
                    l10n.modeEditorChooseSource,
                  ModeDialogValidation.targetRequired =>
                    l10n.modeEditorChooseTarget,
                  ModeDialogValidation.guardRequired =>
                    l10n.modeEditorGuardRequiredField,
                  ModeDialogValidation.duplicateTransition =>
                    l10n.modeEditorDuplicateTransition,
                }),
              for (final error in errors)
                StudioInlineMessage(
                  icon: Icons.error_outline,
                  message: error,
                  color: Theme.of(context).colorScheme.error,
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            key: ValueKey('mode-editor-$prefix-cancel'),
            onPressed: state.busy ? null : onCancel,
            child: Text(l10n.modeEditorCancel),
          ),
          FilledButton(
            key: ValueKey('mode-editor-$prefix-confirm'),
            onPressed: state.busy ? null : onSubmit,
            child: state.busy
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(switch (draft.kind) {
                    ModeDialogKind.create => l10n.modeEditorCreateMode,
                    ModeDialogKind.importJson => l10n.modeEditorLoadAsDraft,
                    ModeDialogKind.renameState => l10n.modeEditorApply,
                    ModeDialogKind.transition => l10n.modeEditorAddTransition,
                  }),
          ),
        ],
      ),
    );
  }
}
