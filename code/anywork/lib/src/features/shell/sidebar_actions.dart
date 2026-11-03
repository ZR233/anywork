part of 'studio_shell.dart';

class _DriverProjectPathDialog extends StatefulWidget {
  const _DriverProjectPathDialog();

  @override
  State<_DriverProjectPathDialog> createState() =>
      _DriverProjectPathDialogState();
}

class _DriverProjectPathDialogState extends State<_DriverProjectPathDialog> {
  final _controller = TextEditingController();

  String get _path => _controller.text.trim();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: StudioDriverKeys.projectPathDialog,
      title: Text(context.l10n.sidebarOpenProject),
      content: TextField(
        key: StudioDriverKeys.projectPathInput,
        controller: _controller,
        autofocus: true,
        style: const TextStyle(fontFamily: studioCodeFontFamily),
        decoration: InputDecoration(
          labelText: context.l10n.agentDetailPathLabel,
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.settingsCancel),
        ),
        FilledButton(
          key: _path.isEmpty
              ? const ValueKey('project-path-submit-disabled')
              : StudioDriverKeys.projectPathSubmit,
          onPressed: _path.isEmpty ? null : _submit,
          child: Text(context.l10n.sidebarOpen),
        ),
      ],
    );
  }

  void _submit() {
    final path = _path;
    if (path.isNotEmpty) {
      Navigator.of(context).pop(path);
    }
  }
}
