part of 'studio_shell.dart';

Future<void> _archiveThreadFromSidebar(
  BuildContext context,
  AnyworkClient client,
  String threadId,
) async {
  // 归档是破坏性动作：确认对话框是唯一入口，取消不产生任何副作用。
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.l10n.sidebarArchiveSessionConfirmTitle),
      content: Text(context.l10n.sidebarArchiveSessionConfirmBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.l10n.commonCancel),
        ),
        FilledButton(
          key: StudioDriverKeys.archiveThreadConfirm,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(context.l10n.sidebarArchiveSessionConfirmAction),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await client.threadCommands.archiveThread(threadId);
  } on Object catch (error) {
    if (!context.mounted) return;
    final message = switch (error) {
      StudioFailure(code: StudioFailureCode.busy) =>
        context.l10n.sidebarArchiveSessionBusy,
      StudioFailure(:final message, :final correlationId) =>
        context.l10n.sidebarArchiveSessionFailedReason(message, correlationId),
      _ => context.l10n.sidebarArchiveSessionFailed,
    };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

Future<void> _renameThreadFromSidebar(
  BuildContext context,
  AnyworkClient client,
  StudioThread thread,
) async {
  final title = await showDialog<String>(
    context: context,
    builder: (context) => _RenameThreadDialog(thread: thread),
  );
  if (title == null || !context.mounted) return;
  try {
    await client.threadCommands.renameThread(thread.id, title);
  } on Object {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.sidebarRenameSessionFailed)),
    );
  }
}

class _RenameThreadDialog extends StatefulWidget {
  const _RenameThreadDialog({required this.thread});

  final StudioThread thread;

  @override
  State<_RenameThreadDialog> createState() => _RenameThreadDialogState();
}

class _RenameThreadDialogState extends State<_RenameThreadDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.thread.title,
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _controller.text.trim();
    if (title.isEmpty) {
      setState(() => _error = context.l10n.sidebarRenameSessionEmpty);
      return;
    }
    if (title.runes.length > 80) {
      setState(() => _error = context.l10n.sidebarRenameSessionTooLong);
      return;
    }
    Navigator.of(context).pop(title);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: StudioDriverKeys.renameThreadDialog(widget.thread.id),
      title: Text(context.l10n.sidebarRenameSessionTitle),
      content: TextField(
        key: StudioDriverKeys.renameThreadInput(widget.thread.id),
        controller: _controller,
        autofocus: true,
        maxLength: 80,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: context.l10n.sidebarRenameSessionInput,
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.commonCancel),
        ),
        FilledButton(
          key: StudioDriverKeys.renameThreadSave(widget.thread.id),
          onPressed: _submit,
          child: Text(context.l10n.commonSave),
        ),
      ],
    );
  }
}
