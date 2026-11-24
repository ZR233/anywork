part of 'studio_shell.dart';

Future<bool?> _confirmThreadRemoval(
  BuildContext context,
  SessionDirectoryRow row, {
  required bool deleting,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => ThreadDestructiveActionDialog(
      key: deleting ? StudioDriverKeys.deleteThreadDialog(row.threadId) : null,
      title: deleting
          ? context.l10n.sidebarDeleteSessionConfirmTitle(row.title)
          : context.l10n.sidebarArchiveSessionConfirmTitle,
      body: deleting
          ? context.l10n.sidebarDeleteSessionConfirmBody
          : context.l10n.sidebarArchiveSessionConfirmBody,
      actionLabel: deleting
          ? context.l10n.sidebarDeleteSessionConfirmAction
          : context.l10n.sidebarArchiveSessionConfirmAction,
      confirmKey: deleting
          ? StudioDriverKeys.deleteThreadConfirm(row.threadId)
          : StudioDriverKeys.archiveThreadConfirm,
      danger: deleting,
    ),
  );
}

class ThreadDestructiveActionDialog extends StatelessWidget {
  const ThreadDestructiveActionDialog({
    super.key,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.confirmKey,
    this.danger = false,
  });

  final String title;
  final String body;
  final String actionLabel;
  final Key confirmKey;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    void finish(bool confirmed) {
      if (ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).pop(confirmed);
      }
    }

    return AlertDialog(
      scrollable: true,
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => finish(false),
          child: Text(context.l10n.commonCancel),
        ),
        FilledButton(
          key: confirmKey,
          style: danger
              ? FilledButton.styleFrom(
                  backgroundColor: colors.error,
                  foregroundColor: colors.onError,
                )
              : null,
          onPressed: () => finish(true),
          child: Text(actionLabel),
        ),
      ],
    );
  }
}

Future<void> _renameThreadFromSidebar(
  BuildContext context,
  AnyworkClient client,
  SessionDirectoryRow row,
) async {
  final title = await showDialog<String>(
    context: context,
    builder: (context) => _RenameThreadDialog(row: row),
  );
  if (title == null || !context.mounted) return;
  try {
    await client.threadCommands.renameThread(row.threadId, title);
  } on Object {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.sidebarRenameSessionFailed)),
    );
  }
}

class _RenameThreadDialog extends StatefulWidget {
  const _RenameThreadDialog({required this.row});

  final SessionDirectoryRow row;

  @override
  State<_RenameThreadDialog> createState() => _RenameThreadDialogState();
}

class _RenameThreadDialogState extends State<_RenameThreadDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.row.title,
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
      key: StudioDriverKeys.renameThreadDialog(widget.row.threadId),
      title: Text(context.l10n.sidebarRenameSessionTitle),
      content: TextField(
        key: StudioDriverKeys.renameThreadInput(widget.row.threadId),
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
          key: StudioDriverKeys.renameThreadSave(widget.row.threadId),
          onPressed: _submit,
          child: Text(context.l10n.commonSave),
        ),
      ],
    );
  }
}
