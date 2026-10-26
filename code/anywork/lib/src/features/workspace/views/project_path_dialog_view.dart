import 'package:flutter/material.dart';

import '../../../app/theme/studio_tokens.dart';
import '../../../diagnostics/studio_driver_keys.dart';
import '../../../l10n/studio_l10n.dart';

class ProjectPathDialogView extends StatefulWidget {
  const ProjectPathDialogView({
    required this.raw,
    required this.enabled,
    required this.canSubmit,
    required this.onChanged,
    required this.onSubmit,
    required this.onCancel,
    super.key,
  });
  final String raw;
  final bool enabled;
  final bool canSubmit;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  @override
  State<ProjectPathDialogView> createState() => _ProjectPathDialogViewState();
}

class _ProjectPathDialogViewState extends State<ProjectPathDialogView> {
  late final _controller = TextEditingController(text: widget.raw);

  @override
  void didUpdateWidget(ProjectPathDialogView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text != widget.raw) {
      _controller.value = TextEditingValue(
        text: widget.raw,
        selection: TextSelection.collapsed(offset: widget.raw.length),
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
    final canSubmit = widget.enabled && widget.canSubmit;
    return AlertDialog(
      key: StudioDriverKeys.projectPathDialog,
      title: Text(context.l10n.sidebarOpenProject),
      content: TextField(
        key: StudioDriverKeys.projectPathInput,
        controller: _controller,
        autofocus: true,
        enabled: widget.enabled,
        style: const TextStyle(fontFamily: studioCodeFontFamily),
        decoration: InputDecoration(
          labelText: context.l10n.agentDetailPathLabel,
        ),
        onChanged: widget.onChanged,
        onSubmitted: (_) {
          if (canSubmit) widget.onSubmit();
        },
      ),
      actions: [
        TextButton(
          onPressed: widget.onCancel,
          child: Text(context.l10n.settingsCancel),
        ),
        FilledButton(
          key: canSubmit
              ? StudioDriverKeys.projectPathSubmit
              : const ValueKey('project-path-submit-disabled'),
          onPressed: canSubmit ? widget.onSubmit : null,
          child: Text(context.l10n.sidebarOpen),
        ),
      ],
    );
  }
}
