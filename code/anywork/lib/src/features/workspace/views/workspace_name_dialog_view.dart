import 'package:flutter/material.dart';

import '../../../l10n/studio_l10n.dart';
import '../state/workspace_view_state.dart';

class WorkspaceNameDialogView extends StatefulWidget {
  const WorkspaceNameDialogView({
    required this.state, required this.onChanged, required this.onCancel,
    required this.onSave, super.key,
  });
  final WorkspaceNameEditor state;
  final ValueChanged<String> onChanged;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  @override
  State<WorkspaceNameDialogView> createState() => _WorkspaceNameDialogViewState();
}

class _WorkspaceNameDialogViewState extends State<WorkspaceNameDialogView> {
  late final _controller = TextEditingController(text: widget.state.raw);
  @override
  void didUpdateWidget(WorkspaceNameDialogView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text != widget.state.raw) {
      _controller.value = TextEditingValue(text: widget.state.raw,
        selection: TextSelection.collapsed(offset: widget.state.raw.length));
    }
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.sidebarRenameSessionTitle),
      content: SizedBox(width: 400, child: TextField(
        key: const ValueKey('thread-rename-input'), controller: _controller,
        autofocus: true, maxLength: widget.state.target == WorkspaceNameTarget.thread ? 80 : null,
        onChanged: widget.onChanged,
        onSubmitted: (_) { if (!widget.state.saving) widget.onSave(); },
        decoration: InputDecoration(labelText: l10n.sidebarRenameSessionInput,
          errorText: switch (widget.state.problem) {
            WorkspaceNameProblem.empty => l10n.sidebarRenameSessionEmpty,
            WorkspaceNameProblem.tooLong => l10n.sidebarRenameSessionTooLong,
            null => widget.state.error?.message,
          },
        ),
      )),
      actions: [
        TextButton(onPressed: widget.onCancel, child: Text(l10n.settingsCancel)),
        FilledButton(key: const ValueKey('thread-rename-save'),
          onPressed: widget.state.saving || widget.state.problem != null ? null : widget.onSave,
          child: Text(l10n.settingsSave)),
      ],
    );
  }
}
