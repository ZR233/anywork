part of 'studio_shell.dart';

Future<void> _archiveThreadFromSidebar(
  BuildContext context,
  AnyworkClient client,
  String threadId,
) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => ThreadDestructiveActionDialog(
      title: context.l10n.sidebarArchiveSessionConfirmTitle,
      body: context.l10n.sidebarArchiveSessionConfirmBody,
      actionLabel: context.l10n.sidebarArchiveSessionConfirmAction,
      confirmKey: StudioDriverKeys.archiveThreadConfirm,
      onConfirm: () => client.threadCommands.archiveThread(threadId),
    ),
  );
}

Future<void> _deleteThreadFromSidebar(
  BuildContext context,
  AnyworkClient client,
  SessionDirectoryRow row,
) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => ThreadDestructiveActionDialog(
      key: StudioDriverKeys.deleteThreadDialog(row.threadId),
      title: context.l10n.sidebarDeleteSessionConfirmTitle(row.title),
      body: context.l10n.sidebarDeleteSessionConfirmBody,
      actionLabel: context.l10n.sidebarDeleteSessionConfirmAction,
      confirmKey: StudioDriverKeys.deleteThreadConfirm(row.threadId),
      danger: true,
      onConfirm: () => client.threadCommands.deleteThread(row.threadId),
    ),
  );
}

class ThreadDestructiveActionDialog extends StatefulWidget {
  const ThreadDestructiveActionDialog({
    super.key,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.confirmKey,
    required this.onConfirm,
    this.danger = false,
  });

  final String title;
  final String body;
  final String actionLabel;
  final Key confirmKey;
  final Future<void> Function() onConfirm;
  final bool danger;

  @override
  State<ThreadDestructiveActionDialog> createState() =>
      _ThreadDestructiveActionDialogState();
}

class _ThreadDestructiveActionDialogState
    extends State<ThreadDestructiveActionDialog> {
  bool _pending = false;
  String? _error;

  Future<void> _confirm() async {
    if (_pending) return;
    setState(() {
      _pending = true;
      _error = null;
    });
    try {
      await widget.onConfirm();
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_pending,
      child: AlertDialog(
        title: Text(widget.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.body),
            if (_error case final error?) ...[
              const SizedBox(height: 12),
              Text(error, style: TextStyle(color: colors.error)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: _pending ? null : () => Navigator.of(context).pop(),
            child: Text(context.l10n.commonCancel),
          ),
          FilledButton(
            key: widget.confirmKey,
            style: widget.danger
                ? FilledButton.styleFrom(
                    backgroundColor: colors.error,
                    foregroundColor: colors.onError,
                  )
                : null,
            onPressed: _pending ? null : _confirm,
            child: _pending
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Text(widget.actionLabel),
                    ],
                  )
                : Text(widget.actionLabel),
          ),
        ],
      ),
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
