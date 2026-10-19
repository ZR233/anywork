import 'package:anywork_client/studio_client.dart'
    show
        ModeDocument,
        ModeDefinition,
        ModeValidationIssue,
        WorkflowDefinition,
        WorkflowPreviewSnapshot,
        WorkflowState,
        WorkflowStateKind,
        WorkflowTransition;
import 'package:flutter/material.dart';

import '../../../app/theme/studio_tokens.dart';
import '../../../l10n/app_localizations.dart';
import 'mode_editor_fields.dart';
import 'mode_editor_support.dart';

class ModeJsonPanel extends StatefulWidget {
  const ModeJsonPanel({
    super.key,
    required this.text,
    required this.issues,
    required this.error,
    required this.readOnly,
    required this.busy,
    required this.validated,
    required this.l10n,
    required this.onChanged,
    required this.onApply,
    required this.onCopy,
    required this.onValidate,
    required this.onSchema,
  });

  final String text;
  final List<ModeValidationIssue> issues;
  final String? error;
  final bool readOnly;
  final bool busy;
  final bool validated;
  final AppLocalizations l10n;
  final ValueChanged<String> onChanged;
  final VoidCallback onApply;
  final VoidCallback onCopy;
  final VoidCallback onValidate;
  final VoidCallback onSchema;

  @override
  State<ModeJsonPanel> createState() => _ModeJsonPanelState();
}

class _ModeJsonPanelState extends State<ModeJsonPanel> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.text,
  );

  @override
  void didUpdateWidget(covariant ModeJsonPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.text,
        selection: TextSelection.collapsed(offset: widget.text.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final status = widget.validated
        ? widget.issues.isEmpty
              ? l10n.modeEditorValidationPassed
              : l10n.modeEditorValidationIssuesCount(widget.issues.length)
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
                key: ModeEditorKeys.applyJson,
                onPressed: widget.readOnly || widget.busy
                    ? null
                    : widget.onApply,
                icon: const Icon(Icons.check, size: 17),
                label: Text(l10n.modeEditorApplyJson),
              ),
              OutlinedButton.icon(
                key: ModeEditorKeys.validate,
                onPressed: widget.busy ? null : widget.onValidate,
                icon: const Icon(Icons.fact_check_outlined, size: 17),
                label: Text(l10n.modeEditorValidate),
              ),
              OutlinedButton.icon(
                key: ModeEditorKeys.copyJson,
                onPressed: widget.onCopy,
                icon: const Icon(Icons.copy_all_outlined, size: 17),
                label: Text(l10n.modeEditorCopyJson),
              ),
              OutlinedButton.icon(
                key: ModeEditorKeys.schema,
                onPressed: widget.busy ? null : widget.onSchema,
                icon: const Icon(Icons.schema_outlined, size: 17),
                label: Text(l10n.modeEditorSchemaLabel),
              ),
              const SizedBox(width: 6),
              Text(
                widget.readOnly ? l10n.modeEditorReadOnlyCopyHint : status,
                style: context.text.bodySmall?.copyWith(
                  color: widget.validated && widget.issues.isNotEmpty
                      ? context.colors.error
                      : context.colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (widget.error != null) ...[
            const SizedBox(height: 10),
            _Banner(
              message: widget.error!,
              color: context.colors.errorContainer,
              foreground: context.colors.onErrorContainer,
            ),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: TextField(
              key: ModeEditorKeys.jsonEditor,
              controller: _controller,
              readOnly: widget.readOnly || widget.busy,
              expands: true,
              maxLines: null,
              minLines: null,
              textAlignVertical: TextAlignVertical.top,
              onChanged: widget.onChanged,
              style: const TextStyle(
                fontFamily: 'monospace',
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
          if (widget.issues.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(height: 150, child: _IssueList(issues: widget.issues)),
          ],
        ],
      ),
    );
  }
}

class ModeSettingsPanel extends StatelessWidget {
  const ModeSettingsPanel({
    super.key,
    required this.document,
    required this.readOnly,
    required this.l10n,
    required this.onDocumentChanged,
    required this.onEnableWorkflow,
    required this.onRemoveWorkflow,
  });

  final ModeDocument document;
  final bool readOnly;
  final AppLocalizations l10n;
  final ValueChanged<ModeDocument> onDocumentChanged;
  final VoidCallback onEnableWorkflow;
  final VoidCallback onRemoveWorkflow;

  void _updateDefinition(_ModeDefinitionUpdater update) {
    onDocumentChanged(
      documentWithDefinition(document, update(document.definition)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final definition = document.definition;
    final workflow = definition.workflow;
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
                ModeEditorTextField(
                  key: ModeEditorKeys.settingsField('display-name'),
                  label: l10n.modeEditorDisplayName,
                  value: definition.displayName,
                  enabled: !readOnly,
                  onChanged: (value) => _updateDefinition(
                    (definition) =>
                        definitionWith(definition, displayName: value),
                  ),
                ),
                const SizedBox(height: 12),
                ModeEditorTextField(
                  key: ModeEditorKeys.settingsField('description'),
                  label: l10n.modeEditorDescription,
                  value: definition.description,
                  enabled: !readOnly,
                  minLines: 2,
                  maxLines: 4,
                  onChanged: (value) => _updateDefinition(
                    (definition) =>
                        definitionWith(definition, description: value),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ModeEditorTextField(
                        key: ModeEditorKeys.settingsField('order'),
                        label: l10n.modeEditorOrder,
                        value: '${definition.order}',
                        enabled: !readOnly,
                        keyboardType: TextInputType.number,
                        onChanged: (value) {
                          final order = int.tryParse(value.trim());
                          if (order == null || order < 0) return;
                          _updateDefinition(
                            (definition) =>
                                definitionWith(definition, order: order),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: l10n.modeEditorModeId,
                        ),
                        child: SelectableText(definition.id),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                ModeEditorTextField(
                  key: ModeEditorKeys.settingsField('prompt'),
                  label: l10n.modeEditorRawPrompt,
                  value: definition.prompt,
                  enabled: !readOnly,
                  minLines: 12,
                  maxLines: 24,
                  monospace: true,
                  helperText: l10n.modeEditorRawPromptHelper,
                  onChanged: (value) => _updateDefinition(
                    (definition) => definitionWith(definition, prompt: value),
                  ),
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
                        key: ModeEditorKeys.removeWorkflow,
                        onPressed: onRemoveWorkflow,
                        icon: const Icon(Icons.link_off, size: 16),
                        label: Text(l10n.modeEditorRemoveWorkflow),
                      ),
                  ],
                ),
                if (workflow == null)
                  _WorkflowMissing(
                    readOnly: readOnly,
                    l10n: l10n,
                    onEnable: onEnableWorkflow,
                  )
                else ...[
                  const SizedBox(height: 8),
                  ModeEditorTextField(
                    key: ModeEditorKeys.settingsField('workflow-title'),
                    label: l10n.modeEditorWorkflowTitle,
                    value: workflow.title,
                    enabled: !readOnly,
                    onChanged: (value) => onDocumentChanged(
                      documentWithWorkflow(
                        document,
                        workflowWith(workflow, title: value),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ModeEditorTextField(
                    key: ModeEditorKeys.settingsField('workflow-goal'),
                    label: l10n.modeEditorWorkflowGoal,
                    value: workflow.goal,
                    enabled: !readOnly,
                    minLines: 2,
                    maxLines: 5,
                    onChanged: (value) => onDocumentChanged(
                      documentWithWorkflow(
                        document,
                        workflowWith(workflow, goal: value),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey<String>(
                      'mode-editor-settings-initial-${workflow.initialStateId}',
                    ),
                    initialValue:
                        workflow.states.any(
                          (state) =>
                              state.id == workflow.initialStateId &&
                              state.kind == WorkflowStateKind.atomic,
                        )
                        ? workflow.initialStateId
                        : null,
                    decoration: InputDecoration(
                      labelText: l10n.modeEditorInitialStateLabel,
                    ),
                    items: [
                      for (final state in workflow.states)
                        if (state.kind == WorkflowStateKind.atomic)
                          DropdownMenuItem(
                            value: state.id,
                            child: Text(state.title),
                          ),
                    ],
                    onChanged: readOnly
                        ? null
                        : (value) {
                            if (value == null) return;
                            onDocumentChanged(
                              documentWithWorkflow(
                                document,
                                workflowWith(workflow, initialStateId: value),
                              ),
                            );
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
}

typedef _ModeDefinitionUpdater = ModeDefinition Function(
  ModeDefinition definition,
);

class _WorkflowMissing extends StatelessWidget {
  const _WorkflowMissing({
    required this.readOnly,
    required this.l10n,
    required this.onEnable,
  });

  final bool readOnly;
  final AppLocalizations l10n;
  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) {
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
              key: ModeEditorKeys.enableWorkflow,
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

class ModePreviewPanel extends StatelessWidget {
  const ModePreviewPanel({
    super.key,
    required this.document,
    required this.preview,
    required this.reason,
    required this.busy,
    required this.l10n,
    required this.onReasonChanged,
    required this.onStart,
    required this.onReset,
    required this.onAdvance,
  });

  final ModeDocument document;
  final WorkflowPreviewSnapshot? preview;
  final String reason;
  final bool busy;
  final AppLocalizations l10n;
  final ValueChanged<String> onReasonChanged;
  final VoidCallback onStart;
  final VoidCallback onReset;
  final ValueChanged<String> onAdvance;

  @override
  Widget build(BuildContext context) {
    final workflow = document.definition.workflow;
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
    final snapshot = preview;
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
                        key: ModeEditorKeys.previewStart,
                        onPressed: busy ? null : onStart,
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: Text(l10n.modeEditorStartPreview),
                      )
                    else
                      OutlinedButton.icon(
                        key: ModeEditorKeys.previewReset,
                        onPressed: busy ? null : onReset,
                        icon: const Icon(Icons.restart_alt, size: 18),
                        label: Text(l10n.modeEditorRestart),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                ModeEditorTextField(
                  key: ModeEditorKeys.previewReason,
                  label: l10n.modeEditorTransitionReason,
                  value: reason,
                  minLines: 1,
                  maxLines: 3,
                  hintText: l10n.modeEditorTransitionReasonHint,
                  helperText: l10n.modeEditorTransitionReasonHelper,
                  onChanged: onReasonChanged,
                ),
                const SizedBox(height: 16),
                if (snapshot == null)
                  _PreviewIntro(l10n: l10n)
                else ...[
                  _PreviewStatus(snapshot: snapshot, l10n: l10n),
                  const SizedBox(height: 14),
                  if (snapshot.currentState != null)
                    _CurrentStateCard(
                      state: snapshot.currentState!,
                      terminal: snapshot.terminal,
                      l10n: l10n,
                    ),
                  if (snapshot.path.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _PathTrail(
                      workflow: workflow,
                      path: snapshot.path,
                      l10n: l10n,
                    ),
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
                        l10n: l10n,
                        onPressed: () => onAdvance(transition.targetStateId),
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
                  _PreviewHistory(
                    workflow: workflow,
                    snapshot: snapshot,
                    l10n: l10n,
                  ),
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
  const _PreviewIntro({required this.l10n});

  final AppLocalizations l10n;

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
        l10n.modeEditorPreviewIntroText,
        style: context.text.bodySmall?.copyWith(
          color: context.colors.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _PreviewStatus extends StatelessWidget {
  const _PreviewStatus({required this.snapshot, required this.l10n});

  final WorkflowPreviewSnapshot snapshot;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
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
  const _CurrentStateCard({
    required this.state,
    required this.terminal,
    required this.l10n,
  });

  final WorkflowState state;
  final bool terminal;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
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
  const _PathTrail({
    required this.workflow,
    required this.path,
    required this.l10n,
  });

  final WorkflowDefinition workflow;
  final List<String> path;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.modeEditorPath,
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
                  stateTitle(workflow, path[index]),
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
    required this.l10n,
    required this.onPressed,
  });

  final WorkflowDefinition workflow;
  final WorkflowTransition transition;
  final bool busy;
  final AppLocalizations l10n;
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
          key: ModeEditorKeys.previewTarget(transition.targetStateId),
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
                        stateTitle(workflow, transition.targetStateId),
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
                  l10n.modeEditorAdvance,
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
  const _PreviewHistory({
    required this.workflow,
    required this.snapshot,
    required this.l10n,
  });

  final WorkflowDefinition workflow;
  final WorkflowPreviewSnapshot snapshot;
  final AppLocalizations l10n;

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
          l10n.modeEditorPreviewHistory,
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
                        '${stateTitle(workflow, rows[index].$1)} → '
                        '${stateTitle(workflow, rows[index].$2)}',
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

class _IssueList extends StatelessWidget {
  const _IssueList({required this.issues});

  final List<ModeValidationIssue> issues;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.errorContainer,
        borderRadius: BorderRadius.circular(StudioRadii.sm),
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          for (var index = 0; index < issues.length; index++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 1),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: context.colors.onErrorContainer.withValues(
                        alpha: 0.1,
                      ),
                      borderRadius: BorderRadius.circular(StudioRadii.xs),
                    ),
                    child: Text(
                      issues[index].code,
                      style: context.text.labelSmall?.copyWith(
                        color: context.colors.onErrorContainer,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${issues[index].path}: ${issues[index].message}',
                      style: context.text.bodySmall?.copyWith(
                        color: context.colors.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
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
        style: context.text.bodySmall?.copyWith(color: foreground),
      ),
    );
  }
}
