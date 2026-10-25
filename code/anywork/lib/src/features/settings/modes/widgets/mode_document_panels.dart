import 'package:anywork_client/modes.dart';
import 'package:anywork_client/resources.dart' show ValidationIssue;
import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../state/mode_editor_state.dart';

/// Raw JSON panel.
///
/// Restores the pre-refactor panel: a bounded action wrap with the validation
/// status text (including the initial "not validated" state), the expandable
/// monospace editor and the bounded issue list.
class ModeJsonPanel extends StatefulWidget {
  const ModeJsonPanel({
    required this.state,
    required this.onJson,
    required this.onApply,
    required this.onCopy,
    required this.onValidate,
    required this.onSchema,
    super.key,
  });

  final ModeEditorViewState state;
  final ValueChanged<String> onJson;
  final VoidCallback onApply;
  final VoidCallback onCopy;
  final VoidCallback onValidate;
  final VoidCallback onSchema;

  @override
  State<ModeJsonPanel> createState() => _ModeJsonPanelState();
}

class _ModeJsonPanelState extends State<ModeJsonPanel> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.state.jsonText,
  );

  @override
  void didUpdateWidget(covariant ModeJsonPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state.jsonText == _controller.text) return;
    _controller.value = TextEditingValue(
      text: widget.state.jsonText,
      selection: TextSelection.collapsed(offset: widget.state.jsonText.length),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = widget.state;
    final readOnly = !state.canEdit;
    final busy = state.busy;
    final validated = state.validationRequested;
    final issues = state.issues;
    final status = validated
        ? issues.isEmpty
              ? l10n.modeEditorValidationPassed
              : l10n.modeEditorValidationIssuesCount(issues.length)
        : l10n.modeEditorNotValidated;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                key: const ValueKey('mode-editor-apply-json'),
                onPressed: readOnly || busy ? null : widget.onApply,
                icon: const Icon(Icons.check, size: 17),
                label: Text(l10n.modeEditorApplyJson),
              ),
              OutlinedButton.icon(
                key: const ValueKey('mode-editor-validate'),
                onPressed: busy ? null : widget.onValidate,
                icon: const Icon(Icons.fact_check_outlined, size: 17),
                label: Text(l10n.modeEditorValidate),
              ),
              OutlinedButton.icon(
                key: const ValueKey('mode-editor-copy-json'),
                onPressed: widget.onCopy,
                icon: const Icon(Icons.copy_all_outlined, size: 17),
                label: Text(l10n.modeEditorCopyJson),
              ),
              OutlinedButton.icon(
                key: const ValueKey('mode-editor-schema'),
                onPressed: busy ? null : widget.onSchema,
                icon: const Icon(Icons.schema_outlined, size: 17),
                label: Text(l10n.modeEditorSchemaLabel),
              ),
              const SizedBox(width: 6),
              Text(
                readOnly ? l10n.modeEditorReadOnlyCopyHint : status,
                style: context.text.bodySmall?.copyWith(
                  color: validated && issues.isNotEmpty
                      ? context.colors.error
                      : context.colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TextField(
              key: const ValueKey('mode-editor-json-editor'),
              controller: _controller,
              readOnly: readOnly || busy,
              expands: true,
              maxLines: null,
              minLines: null,
              textAlignVertical: TextAlignVertical.top,
              onChanged: widget.onJson,
              style: const TextStyle(
                fontFamily: studioCodeFontFamily,
                fontSize: 12,
                height: 1.6,
              ),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: context.colors.surfaceContainerLowest,
                hintText: l10n.modeEditorJsonHint,
              ),
            ),
          ),
          if (issues.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(height: 150, child: _IssueList(issues: issues)),
          ],
        ],
      ),
    );
  }
}

/// Mode definition + workflow settings panel.
class ModeSettingsPanel extends StatelessWidget {
  const ModeSettingsPanel({
    required this.state,
    required this.onEdit,
    required this.onRemoveWorkflow,
    required this.onEnableWorkflow,
    super.key,
  });

  final ModeEditorViewState state;
  final ValueChanged<ModeEdit> onEdit;
  final VoidCallback onRemoveWorkflow;
  final VoidCallback onEnableWorkflow;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final definition = state.document!.definition;
    final workflow = definition.workflow;
    final readOnly = !state.canEdit || !state.jsonApplied;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
      children: [
        Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 940),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.modeEditorModeSettingsTitle,
                  style: context.text.titleMedium?.copyWith(
                    color: context.colors.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.modeEditorModeSettingsSubtitle,
                  style: context.text.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                _textField(
                  context,
                  key: 'display-name',
                  label: l10n.modeEditorDisplayName,
                  value: definition.displayName,
                  enabled: !readOnly,
                  onChanged: (value) => onEdit(ModeEdit.displayName(value)),
                ),
                const SizedBox(height: 12),
                _textField(
                  context,
                  key: 'description',
                  label: l10n.modeEditorDescription,
                  value: definition.description,
                  enabled: !readOnly,
                  minLines: 2,
                  maxLines: 4,
                  onChanged: (value) => onEdit(ModeEdit.description(value)),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _textField(
                        context,
                        key: 'order',
                        label: l10n.modeEditorOrder,
                        value: state.orderText,
                        enabled: !readOnly,
                        keyboardType: TextInputType.number,
                        onChanged: (value) => onEdit(ModeEdit.orderRaw(value)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: l10n.modeEditorModeId,
                        ),
                        child: SelectableText(definition.id.id),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _textField(
                  context,
                  key: 'prompt',
                  label: l10n.modeEditorRawPrompt,
                  value: definition.prompt,
                  enabled: !readOnly,
                  minLines: 12,
                  maxLines: 24,
                  monospace: true,
                  helperText: l10n.modeEditorRawPromptHelper,
                  onChanged: (value) => onEdit(ModeEdit.prompt(value)),
                ),
                const SizedBox(height: 26),
                Divider(color: context.colors.outlineVariant),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.modeEditorWorkflow,
                        style: context.text.titleSmall?.copyWith(
                          color: context.colors.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (workflow != null && !readOnly)
                      TextButton.icon(
                        key: const ValueKey('mode-editor-remove-workflow'),
                        onPressed: onRemoveWorkflow,
                        icon: const Icon(Icons.link_off, size: 16),
                        label: Text(l10n.modeEditorRemoveWorkflow),
                      ),
                  ],
                ),
                if (workflow == null)
                  _WorkflowMissing(
                    readOnly: readOnly,
                    onEnable: onEnableWorkflow,
                  )
                else ...[
                  const SizedBox(height: 8),
                  _textField(
                    context,
                    key: 'workflow-title',
                    label: l10n.modeEditorWorkflowTitle,
                    value: workflow.title,
                    enabled: !readOnly,
                    onChanged: (value) => onEdit(ModeEdit.workflowTitle(value)),
                  ),
                  const SizedBox(height: 12),
                  _textField(
                    context,
                    key: 'workflow-goal',
                    label: l10n.modeEditorWorkflowGoal,
                    value: workflow.goal,
                    enabled: !readOnly,
                    minLines: 2,
                    maxLines: 5,
                    onChanged: (value) => onEdit(ModeEdit.workflowGoal(value)),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey<String>(
                      'mode-editor-settings-initial-${workflow.initialStateId}',
                    ),
                    initialValue:
                        workflow.states.any(
                          (workflowState) =>
                              workflowState.id == workflow.initialStateId &&
                              workflowState.kind == WorkflowStateKind.atomic,
                        )
                        ? workflow.initialStateId
                        : null,
                    decoration: InputDecoration(
                      labelText: l10n.modeEditorInitialStateLabel,
                    ),
                    items: [
                      for (final workflowState in workflow.states)
                        if (workflowState.kind == WorkflowStateKind.atomic)
                          DropdownMenuItem(
                            value: workflowState.id,
                            child: Text(workflowState.title),
                          ),
                    ],
                    onChanged: readOnly
                        ? null
                        : (value) {
                            if (value == null) return;
                            onEdit(ModeEdit.initialState(value));
                          },
                  ),
                  const SizedBox(height: 10),
                  Text(
                    l10n.modeEditorWorkflowSummary(
                      workflow.states.length,
                      workflow.transitions.length,
                    ),
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _textField(
    BuildContext context, {
    required String key,
    required String label,
    required String value,
    required bool enabled,
    int minLines = 1,
    int maxLines = 1,
    bool monospace = false,
    String? helperText,
    String? error,
    TextInputType? keyboardType,
    required ValueChanged<String> onChanged,
  }) => _ModeEditorTextField(
    fieldKey: ValueKey('mode-editor-settings-$key'),
    label: label,
    value: value,
    enabled: enabled,
    minLines: minLines,
    maxLines: maxLines,
    monospace: monospace,
    helperText: helperText,
    error: error,
    keyboardType: keyboardType,
    onChanged: onChanged,
  );
}

class _WorkflowMissing extends StatelessWidget {
  const _WorkflowMissing({required this.readOnly, required this.onEnable});

  final bool readOnly;
  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(StudioRadii.sm),
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.modeEditorNoWorkflow,
            style: context.text.titleSmall?.copyWith(
              color: context.colors.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.modeEditorNoWorkflowToolHint,
            style: context.text.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          if (!readOnly) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('mode-editor-enable-workflow'),
              onPressed: onEnable,
              icon: const Icon(Icons.playlist_add, size: 17),
              label: Text(l10n.modeEditorEnableWorkflow),
            ),
          ],
        ],
      ),
    );
  }
}

/// Workflow preview panel.
class ModePreviewPanel extends StatelessWidget {
  const ModePreviewPanel({
    required this.state,
    required this.onReason,
    required this.onPreview,
    super.key,
  });

  final ModeEditorViewState state;
  final ValueChanged<String> onReason;
  final void Function(String? target, bool reset) onPreview;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final workflow = state.document!.definition.workflow;
    if (workflow == null) {
      return Center(
        child: Text(
          l10n.modeEditorPreviewUnavailable,
          style: context.text.bodyMedium?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      );
    }
    final snapshot = state.preview;
    final busy = state.busy;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
      children: [
        Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.modeEditorRunPreview,
                            style: context.text.titleMedium?.copyWith(
                              color: context.colors.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.modeEditorPreviewSubtitle,
                            style: context.text.bodySmall?.copyWith(
                              color: context.colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (snapshot == null)
                      FilledButton.icon(
                        key: const ValueKey('mode-editor-preview-start'),
                        onPressed: busy ? null : () => onPreview(null, true),
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: Text(l10n.modeEditorStartPreview),
                      )
                    else
                      OutlinedButton.icon(
                        key: const ValueKey('mode-editor-preview-reset'),
                        onPressed: busy ? null : () => onPreview(null, true),
                        icon: const Icon(Icons.restart_alt, size: 18),
                        label: Text(l10n.modeEditorRestart),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                _ModeEditorTextField(
                  fieldKey: const ValueKey('mode-editor-preview-reason'),
                  label: l10n.modeEditorTransitionReason,
                  value: state.previewReason,
                  enabled: true,
                  minLines: 1,
                  maxLines: 3,
                  hintText: l10n.modeEditorTransitionReasonHint,
                  helperText: l10n.modeEditorTransitionReasonHelper,
                  onChanged: onReason,
                ),
                const SizedBox(height: 16),
                if (snapshot == null)
                  const _PreviewIntro()
                else ...[
                  _PreviewStatus(snapshot: snapshot),
                  const SizedBox(height: 14),
                  if (snapshot.currentState case final currentState?)
                    _CurrentStateCard(
                      state: currentState,
                      terminal: snapshot.terminal,
                    ),
                  if (snapshot.path.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _PathTrail(workflow: workflow, path: snapshot.path),
                  ],
                  if (!snapshot.terminal &&
                      snapshot.transitions.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text(
                      l10n.modeEditorAllowedNextStates(
                        snapshot.transitions.length,
                      ),
                      style: context.text.labelMedium?.copyWith(
                        color: context.colors.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...snapshot.transitions.map(
                      (transition) => _NextTransitionTile(
                        workflow: workflow,
                        transition: transition,
                        busy: busy,
                        onPressed: () =>
                            onPreview(transition.targetStateId, false),
                      ),
                    ),
                  ],
                  if (snapshot.terminal)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: _Banner(
                        message: l10n.modeEditorTerminalReached,
                        color: context.colors.surfaceContainerHigh,
                        foreground: context.colors.onSurfaceVariant,
                      ),
                    ),
                  _PreviewHistory(workflow: workflow, snapshot: snapshot),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PreviewIntro extends StatelessWidget {
  const _PreviewIntro();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(StudioRadii.sm),
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: Text(
        context.l10n.modeEditorPreviewIntroText,
        style: context.text.bodySmall?.copyWith(
          color: context.colors.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _PreviewStatus extends StatelessWidget {
  const _PreviewStatus({required this.snapshot});

  final WorkflowPreviewSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _Banner(
      message: snapshot.message.isEmpty
          ? snapshot.accepted
                ? l10n.modeEditorPreviewAccepted
                : l10n.modeEditorPreviewRejected
          : snapshot.message,
      color: snapshot.accepted
          ? context.colors.primaryContainer
          : context.colors.errorContainer,
      foreground: snapshot.accepted
          ? context.colors.onPrimaryContainer
          : context.colors.onErrorContainer,
    );
  }
}

class _CurrentStateCard extends StatelessWidget {
  const _CurrentStateCard({required this.state, required this.terminal});

  final WorkflowState state;
  final bool terminal;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(StudioRadii.sm),
        border: Border(
          left: BorderSide(color: context.colors.primary, width: 3),
          top: BorderSide(color: context.colors.primary),
          right: BorderSide(color: context.colors.primary),
          bottom: BorderSide(color: context.colors.primary),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  state.title.isEmpty ? state.id : state.title,
                  style: context.text.titleMedium?.copyWith(
                    color: context.colors.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                terminal
                    ? l10n.modeEditorFinalLabel
                    : l10n.modeEditorCurrentStage,
                style: context.text.labelSmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            state.id,
            style: context.text.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          if (state.instructions.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            SelectableText(
              state.instructions,
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurface,
                height: 1.55,
              ),
            ),
          ],
          if (state.completionCriteria.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final criterion in state.completionCriteria)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Icon(Icons.circle, size: 5),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        criterion,
                        style: context.text.bodySmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _PathTrail extends StatelessWidget {
  const _PathTrail({required this.workflow, required this.path});

  final WorkflowDefinition workflow;
  final List<String> path;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.modeEditorPath,
          style: context.text.labelMedium?.copyWith(
            color: context.colors.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 7),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var index = 0; index < path.length; index++) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: context.colors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(StudioRadii.pill),
                ),
                child: Text(
                  _stateTitle(workflow, path[index]),
                  style: context.text.labelSmall?.copyWith(
                    color: context.colors.onSurface,
                  ),
                ),
              ),
              if (index < path.length - 1)
                Icon(
                  Icons.arrow_forward,
                  size: 13,
                  color: context.colors.onSurfaceVariant,
                ),
            ],
          ],
        ),
      ],
    );
  }
}

class _NextTransitionTile extends StatelessWidget {
  const _NextTransitionTile({
    required this.workflow,
    required this.transition,
    required this.busy,
    required this.onPressed,
  });

  final WorkflowDefinition workflow;
  final WorkflowTransition transition;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: context.colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(StudioRadii.sm),
          side: BorderSide(color: context.colors.outlineVariant),
        ),
        child: InkWell(
          key: ValueKey(
            'mode-editor-preview-target-${transition.targetStateId}',
          ),
          borderRadius: BorderRadius.circular(StudioRadii.sm),
          onTap: busy ? null : onPressed,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.arrow_forward, size: 17),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _stateTitle(workflow, transition.targetStateId),
                        style: context.text.titleSmall?.copyWith(
                          color: context.colors.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (transition.guard.trim().isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          transition.guard,
                          style: context.text.bodySmall?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  context.l10n.modeEditorAdvance,
                  style: context.text.labelSmall?.copyWith(
                    color: context.colors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewHistory extends StatelessWidget {
  const _PreviewHistory({required this.workflow, required this.snapshot});

  final WorkflowDefinition workflow;
  final WorkflowPreviewSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    if (snapshot.path.length < 2) return const SizedBox.shrink();
    final rows = <(String, String, WorkflowTransition?)>[];
    for (var index = 0; index < snapshot.path.length - 1; index++) {
      final source = snapshot.path[index];
      final target = snapshot.path[index + 1];
      WorkflowTransition? found;
      for (final transition in workflow.transitions) {
        if (transition.sourceStateId == source &&
            transition.targetStateId == target) {
          found = transition;
          break;
        }
      }
      rows.add((source, target, found));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Text(
          context.l10n.modeEditorPreviewHistory,
          style: context.text.labelMedium?.copyWith(
            color: context.colors.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        for (var index = 0; index < rows.length; index++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: context.colors.outlineVariant),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 26,
                  child: Text(
                    '${index + 1}'.padLeft(2, '0'),
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_stateTitle(workflow, rows[index].$1)} → '
                        '${_stateTitle(workflow, rows[index].$2)}',
                        style: context.text.bodySmall?.copyWith(
                          color: context.colors.onSurface,
                        ),
                      ),
                      if (rows[index].$3 != null &&
                          rows[index].$3!.guard.trim().isNotEmpty)
                        Text(
                          rows[index].$3!.guard,
                          style: context.text.bodySmall?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.message,
    required this.color,
    required this.foreground,
  });

  final String message;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(StudioRadii.sm),
      ),
      child: Text(
        message,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: context.text.bodySmall?.copyWith(color: foreground),
      ),
    );
  }
}

class _IssueList extends StatelessWidget {
  const _IssueList({required this.issues});

  final List<ValidationIssue> issues;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (final issue in issues)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              '${issue.code} · ${issue.path} · ${issue.message}',
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _ModeEditorTextField extends StatefulWidget {
  const _ModeEditorTextField({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.minLines = 1,
    this.maxLines = 1,
    this.monospace = false,
    this.hintText,
    this.helperText,
    this.error,
    this.keyboardType,
  });

  final Key fieldKey;
  final String label;
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final int minLines;
  final int maxLines;
  final bool monospace;
  final String? hintText;
  final String? helperText;
  final String? error;
  final TextInputType? keyboardType;

  @override
  State<_ModeEditorTextField> createState() => _ModeEditorTextFieldState();
}

class _ModeEditorTextFieldState extends State<_ModeEditorTextField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(covariant _ModeEditorTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == _controller.text) return;
    _controller.value = TextEditingValue(
      text: widget.value,
      selection: TextSelection.collapsed(offset: widget.value.length),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: widget.fieldKey,
      controller: _controller,
      enabled: widget.enabled,
      minLines: widget.minLines,
      maxLines: widget.maxLines,
      keyboardType: widget.keyboardType,
      onChanged: widget.onChanged,
      style: widget.monospace
          ? const TextStyle(
              fontFamily: studioCodeFontFamily,
              fontSize: 12,
              height: 1.55,
            )
          : null,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hintText,
        helperText: widget.helperText,
        errorText: widget.error,
        alignLabelWithHint: widget.maxLines != 1,
      ),
    );
  }
}

/// Human-readable state label used by the path trail and transition tiles.
String _stateTitle(WorkflowDefinition workflow, String id) {
  for (final state in workflow.states) {
    if (state.id == id) return state.title.isEmpty ? id : state.title;
  }
  return id;
}
