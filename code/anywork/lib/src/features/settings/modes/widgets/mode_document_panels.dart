import 'package:flutter/material.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../widgets/settings_form_field.dart';
import '../state/mode_editor_state.dart';

class ModeSettingsPanel extends StatelessWidget {
  const ModeSettingsPanel({required this.state, required this.onEdit, required this.onRemoveWorkflow, super.key});
  final ModeEditorViewState state;
  final ValueChanged<ModeEdit> onEdit;
  final VoidCallback onRemoveWorkflow;
  @override
  Widget build(BuildContext context) {
    final definition = state.document!.definition;
    final l10n = context.l10n;
    final enabled = state.canEdit && state.jsonApplied;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(l10n.modeEditorModeSettingsSubtitle), SelectableText(definition.id.id),
      const SizedBox(height: 12),
      SettingsFormField(key: const ValueKey('mode-editor-settings-display-name'), value: definition.displayName,
        label: l10n.modeEditorDisplayName, enabled: enabled, onChanged: (raw) => onEdit(ModeEdit.displayName(raw))),
      const SizedBox(height: 12),
      SettingsFormField(key: const ValueKey('mode-editor-settings-description'), value: definition.description,
        label: l10n.modeEditorDescription, enabled: enabled, maxLines: 3, onChanged: (raw) => onEdit(ModeEdit.description(raw))),
      const SizedBox(height: 12),
      SettingsFormField(key: const ValueKey('mode-editor-settings-order'), value: state.orderText,
        label: l10n.modeEditorOrder, error: state.orderError?.message, enabled: enabled, onChanged: (raw) => onEdit(ModeEdit.orderRaw(raw))),
      const SizedBox(height: 12),
      SettingsFormField(key: const ValueKey('mode-editor-settings-prompt'), value: definition.prompt,
        label: l10n.modeEditorRawPrompt, enabled: enabled, minLines: 12, maxLines: null, code: true,
        onChanged: (raw) => onEdit(ModeEdit.prompt(raw))),
      Text(l10n.modeEditorRawPromptHelper),
      if (definition.workflow != null) TextButton(key: const ValueKey('mode-editor-remove-workflow'),
        onPressed: enabled ? onRemoveWorkflow : null, child: Text(l10n.modeEditorRemoveWorkflow)),
    ]);
  }
}

class ModePreviewPanel extends StatelessWidget {
  const ModePreviewPanel({required this.state, required this.onReason,
    required this.onPreview, super.key});
  final ModeEditorViewState state;
  final ValueChanged<String> onReason;
  final void Function(String? target, bool reset) onPreview;
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (state.document?.definition.workflow == null) return Center(child: Text(l10n.modeEditorPreviewUnavailable));
    final preview = state.preview;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(l10n.modeEditorPreviewSubtitle),
      Wrap(spacing: 8, children: [
        FilledButton(key: const ValueKey('mode-editor-preview-start'),
          onPressed: state.busy ? null : () => onPreview(null, true), child: Text(l10n.modeEditorStartPreview)),
        OutlinedButton(key: const ValueKey('mode-editor-preview-reset'),
          onPressed: state.busy ? null : () => onPreview(null, true), child: Text(l10n.modeEditorRestart)),
      ]),
      const SizedBox(height: 12),
      SettingsFormField(key: const ValueKey('mode-editor-preview-reason'), value: state.previewReason,
        label: l10n.modeEditorTransitionReason, hint: l10n.modeEditorTransitionReasonHint, onChanged: onReason),
      if (preview != null) ...[
        Text(preview.accepted ? l10n.modeEditorPreviewAccepted : l10n.modeEditorPreviewRejected),
        Text(preview.message),
        if (preview.terminal) Text(l10n.modeEditorTerminalReached),
        if (preview.currentState case final current?) ...[
          Text(current.title), SelectableText(current.instructions),
          for (final criterion in current.completionCriteria) Text(criterion),
        ],
        for (final transition in preview.transitions) ListTile(
          title: Text(transition.targetStateId), subtitle: Text(transition.guard),
          trailing: FilledButton(key: ValueKey('mode-editor-preview-target-${transition.targetStateId}'),
            onPressed: state.busy ? null : () => onPreview(transition.targetStateId, false), child: Text(l10n.modeEditorAdvance))),
        Text(l10n.modeEditorPreviewHistory),
        for (final stateId in preview.path) SelectableText(stateId),
      ],
    ]);
  }
}
