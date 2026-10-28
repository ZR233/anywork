import 'package:anywork_client/studio_client.dart'
    show
        WorkflowDefinition,
        WorkflowState,
        WorkflowStateKind,
        WorkflowTransition;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/studio_tokens.dart';
import '../../../l10n/studio_l10n.dart';
import '../../../presentation/providers/client_provider.dart';
import 'mode_editor_support.dart';

enum _UnsavedChoice { save, discard, cancel }

/// Returns true when the current draft may be left.
///
/// A failed save keeps the caller on the page and exposes the owner error.
Future<bool> confirmLeaveModeEditor(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final owner = container.read(anyworkClientProvider).modeEditor;
  if (owner.state.busy) return false;
  if (!owner.state.dirty) return true;
  final l10n = context.l10n;
  final choice = await showDialog<_UnsavedChoice>(
    context: context,
    builder: (context) => AlertDialog(
      key: const ValueKey<String>('mode-editor-unsaved-dialog'),
      title: Text(l10n.modeEditorUnsavedTitle),
      content: Text(l10n.modeEditorUnsavedBody),
      actions: [
        TextButton(
          key: const ValueKey<String>('mode-editor-unsaved-cancel'),
          onPressed: () => Navigator.of(context).pop(_UnsavedChoice.cancel),
          child: Text(l10n.modeEditorCancel),
        ),
        TextButton(
          key: const ValueKey<String>('mode-editor-unsaved-discard'),
          onPressed: () => Navigator.of(context).pop(_UnsavedChoice.discard),
          child: Text(l10n.modeEditorDiscard),
        ),
        FilledButton(
          key: const ValueKey<String>('mode-editor-unsaved-save'),
          onPressed: () => Navigator.of(context).pop(_UnsavedChoice.save),
          child: Text(l10n.modeEditorSaveAndContinue),
        ),
      ],
    ),
  );
  switch (choice) {
    case _UnsavedChoice.save:
      try {
        return await owner.save();
      } catch (_) {
        return false;
      }
    case _UnsavedChoice.discard:
      owner.discard();
      return !owner.state.dirty;
    case _UnsavedChoice.cancel:
    case null:
      return false;
  }
}

final class CreateModeResult {
  const CreateModeResult({
    required this.id,
    required this.displayName,
    required this.template,
  });

  final String id;
  final String displayName;
  final ModeTemplateKind template;
}

Future<CreateModeResult?> showCreateModeDialog(
  BuildContext context, {
  required Set<String> existingIds,
}) => showDialog<CreateModeResult>(
  context: context,
  builder: (context) => _CreateModeDialog(existingIds: existingIds),
);

class _CreateModeDialog extends StatefulWidget {
  const _CreateModeDialog({required this.existingIds});

  final Set<String> existingIds;

  @override
  State<_CreateModeDialog> createState() => _CreateModeDialogState();
}

class _CreateModeDialogState extends State<_CreateModeDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController();
  late final TextEditingController _id = TextEditingController(
    text: suggestedModeId(widget.existingIds),
  );
  ModeTemplateKind _template = ModeTemplateKind.minimal;

  @override
  void dispose() {
    _name.dispose();
    _id.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      CreateModeResult(
        id: _id.text.trim(),
        displayName: _name.text.trim(),
        template: _template,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      key: const ValueKey<String>('mode-editor-create-dialog'),
      title: Text(l10n.modeEditorNewWorkMode),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const ValueKey<String>('mode-editor-create-name'),
                  controller: _name,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: l10n.modeEditorModeName,
                    hintText: l10n.modeEditorModeNameHint,
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? l10n.modeEditorModeNameRequired
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey<String>('mode-editor-create-id'),
                  controller: _id,
                  decoration: InputDecoration(
                    labelText: l10n.modeEditorModeId,
                    hintText: 'mode.custom-research',
                  ),
                  validator: (value) {
                    final id = (value ?? '').trim();
                    if (!isValidModeId(id)) {
                      return l10n.modeEditorModeIdFormat;
                    }
                    if (widget.existingIds.contains(id)) {
                      return l10n.modeEditorModeIdExists;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.modeEditorStartingPoint,
                  style: context.text.labelMedium?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<ModeTemplateKind>(
                  key: const ValueKey<String>('mode-editor-create-template'),
                  segments: [
                    ButtonSegment(
                      value: ModeTemplateKind.minimal,
                      icon: const Icon(Icons.account_tree_outlined, size: 16),
                      label: Text(l10n.modeEditorMinimalWorkflow),
                    ),
                    ButtonSegment(
                      value: ModeTemplateKind.none,
                      icon: const Icon(Icons.notes_outlined, size: 16),
                      label: Text(l10n.modeEditorNoWorkflowTemplate),
                    ),
                  ],
                  selected: {_template},
                  onSelectionChanged: (value) =>
                      setState(() => _template = value.first),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey<String>('mode-editor-create-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.modeEditorCancel),
        ),
        FilledButton(
          key: const ValueKey<String>('mode-editor-create-confirm'),
          onPressed: _submit,
          child: Text(l10n.modeEditorCreateMode),
        ),
      ],
    );
  }
}

Future<String?> showImportModeDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (context) => const _ImportModeDialog(),
  );
}

class _ImportModeDialog extends StatefulWidget {
  const _ImportModeDialog();

  @override
  State<_ImportModeDialog> createState() => _ImportModeDialogState();
}

class _ImportModeDialogState extends State<_ImportModeDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      key: const ValueKey<String>('mode-editor-import-dialog'),
      title: Text(l10n.modeEditorImportDialogTitle),
      content: SizedBox(
        width: 680,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.modeEditorImportDialogBody,
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 360,
              child: TextField(
                key: const ValueKey<String>('mode-editor-import-json'),
                controller: _controller,
                autofocus: true,
                expands: true,
                maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(
                  fontFamily: studioCodeFontFamily,
                  fontSize: 12,
                  height: 1.5,
                ),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '{"id": "mode.custom", ...}',
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey<String>('mode-editor-import-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.modeEditorCancel),
        ),
        FilledButton(
          key: const ValueKey<String>('mode-editor-import-confirm'),
          onPressed: () {
            final raw = _controller.text.trim();
            if (raw.isEmpty) return;
            Navigator.of(context).pop(raw);
          },
          child: Text(l10n.modeEditorLoadAsDraft),
        ),
      ],
    );
  }
}

Future<void> showSchemaDialog(BuildContext context, String schema) {
  final l10n = context.l10n;
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      key: const ValueKey<String>('mode-editor-schema-dialog'),
      title: Text(l10n.modeEditorSchemaDialogTitle),
      content: SizedBox(
        width: 720,
        height: 480,
        child: SingleChildScrollView(
          child: SelectableText(
            schema,
            style: const TextStyle(
              fontFamily: studioCodeFontFamily,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.modeEditorClose),
        ),
      ],
    ),
  );
}

Future<bool> confirmDeleteMode(
  BuildContext context, {
  required String displayName,
}) async {
  final l10n = context.l10n;
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          key: const ValueKey<String>('mode-editor-delete-dialog'),
          title: Text(l10n.modeEditorDeleteDialogTitle),
          content: Text(l10n.modeEditorDeleteDialogBody(displayName)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.modeEditorCancel),
            ),
            FilledButton(
              key: const ValueKey<String>('mode-editor-delete-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.modeEditorConfirmDelete),
            ),
          ],
        ),
      ) ??
      false;
}

Future<bool> confirmRemoveState(
  BuildContext context, {
  required String title,
  required int transitionCount,
}) async {
  final l10n = context.l10n;
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          key: const ValueKey<String>('mode-editor-remove-state-dialog'),
          title: Text(l10n.modeEditorRemoveStateTitle),
          content: Text(l10n.modeEditorRemoveStateBody(title, transitionCount)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.modeEditorCancel),
            ),
            FilledButton(
              key: const ValueKey<String>('mode-editor-remove-state-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.modeEditorDeleteState),
            ),
          ],
        ),
      ) ??
      false;
}

Future<bool> confirmRemoveWorkflow(BuildContext context) async {
  final l10n = context.l10n;
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.modeEditorRemoveWorkflowTitle),
          content: Text(l10n.modeEditorRemoveWorkflowBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.modeEditorCancel),
            ),
            FilledButton(
              key: const ValueKey<String>(
                'mode-editor-remove-workflow-confirm',
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.modeEditorRemoveWorkflow),
            ),
          ],
        ),
      ) ??
      false;
}

Future<String?> showRenameStateDialog(
  BuildContext context, {
  required WorkflowState state,
  required WorkflowDefinition workflow,
}) => showDialog<String>(
  context: context,
  builder: (context) => _RenameStateDialog(state: state, workflow: workflow),
);

class _RenameStateDialog extends StatefulWidget {
  const _RenameStateDialog({required this.state, required this.workflow});

  final WorkflowState state;
  final WorkflowDefinition workflow;

  @override
  State<_RenameStateDialog> createState() => _RenameStateDialogState();
}

class _RenameStateDialogState extends State<_RenameStateDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.state.id,
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final l10n = context.l10n;
    final id = _controller.text.trim();
    if (!isValidStateId(id)) {
      setState(() => _error = l10n.modeEditorStateIdInvalid);
      return;
    }
    if (id != widget.state.id &&
        widget.workflow.states.any((state) => state.id == id)) {
      setState(() => _error = l10n.modeEditorStateIdExists);
      return;
    }
    Navigator.of(context).pop(id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      key: const ValueKey<String>('mode-editor-rename-state-dialog'),
      title: Text(l10n.modeEditorRenameStateTitle),
      content: TextField(
        key: ModeEditorKeys.inspectorField('state-id'),
        controller: _controller,
        autofocus: true,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: l10n.modeEditorStateId,
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.modeEditorCancel),
        ),
        FilledButton(
          key: const ValueKey<String>('mode-editor-rename-state-confirm'),
          onPressed: _submit,
          child: Text(l10n.modeEditorApply),
        ),
      ],
    );
  }
}

Future<WorkflowTransition?> showTransitionDialog(
  BuildContext context, {
  required WorkflowDefinition workflow,
  String? initialSourceId,
  String? initialTargetId,
}) => showDialog<WorkflowTransition>(
  context: context,
  builder: (context) => _TransitionDialog(
    workflow: workflow,
    initialSourceId: initialSourceId,
    initialTargetId: initialTargetId,
  ),
);

class _TransitionDialog extends StatefulWidget {
  const _TransitionDialog({
    required this.workflow,
    this.initialSourceId,
    this.initialTargetId,
  });

  final WorkflowDefinition workflow;
  final String? initialSourceId;
  final String? initialTargetId;

  @override
  State<_TransitionDialog> createState() => _TransitionDialogState();
}

class _TransitionDialogState extends State<_TransitionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _guard = TextEditingController();
  late String? _source = widget.initialSourceId;
  late String? _target = widget.initialTargetId;

  @override
  void initState() {
    super.initState();
    final atomic = widget.workflow.states
        .where((state) => state.kind == WorkflowStateKind.atomic)
        .toList(growable: false);
    if (_source == null && atomic.isNotEmpty) {
      _source = atomic.first.id;
    }
    if (_target == null && widget.workflow.states.isNotEmpty) {
      _target = widget.workflow.states.first.id;
    }
  }

  @override
  void dispose() {
    _guard.dispose();
    super.dispose();
  }

  void _submit() {
    final l10n = context.l10n;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final source = _source;
    final target = _target;
    if (source == null || target == null) return;
    final duplicate = widget.workflow.transitions.any(
      (transition) =>
          transition.sourceStateId == source &&
          transition.targetStateId == target,
    );
    if (duplicate) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.modeEditorDuplicateTransition)),
      );
      return;
    }
    Navigator.of(context).pop(
      WorkflowTransition(
        sourceStateId: source,
        targetStateId: target,
        guard: _guard.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final atomic = widget.workflow.states
        .where((state) => state.kind == WorkflowStateKind.atomic)
        .toList(growable: false);
    return AlertDialog(
      key: const ValueKey<String>('mode-editor-transition-dialog'),
      title: Text(l10n.modeEditorAddTransition),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                key: ModeEditorKeys.inspectorField('new-source'),
                initialValue: _source,
                decoration: InputDecoration(
                  labelText: l10n.modeEditorSourceState,
                ),
                items: [
                  for (final state in atomic)
                    DropdownMenuItem(value: state.id, child: Text(state.title)),
                ],
                onChanged: (value) => setState(() => _source = value),
                validator: (value) =>
                    value == null ? l10n.modeEditorChooseSource : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ModeEditorKeys.inspectorField('new-target'),
                initialValue: _target,
                decoration: InputDecoration(
                  labelText: l10n.modeEditorTargetState,
                ),
                items: [
                  for (final state in widget.workflow.states)
                    DropdownMenuItem(value: state.id, child: Text(state.title)),
                ],
                onChanged: (value) => setState(() => _target = value),
                validator: (value) =>
                    value == null ? l10n.modeEditorChooseTarget : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: ModeEditorKeys.inspectorField('new-guard'),
                controller: _guard,
                minLines: 3,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: l10n.modeEditorTransitionGuard,
                  alignLabelWithHint: true,
                  hintText: l10n.modeEditorTransitionGuardHint,
                ),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? l10n.modeEditorGuardRequiredField
                    : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.modeEditorCancel),
        ),
        FilledButton(
          key: const ValueKey<String>('mode-editor-transition-confirm'),
          onPressed: _submit,
          child: Text(l10n.modeEditorAddTransition),
        ),
      ],
    );
  }
}
