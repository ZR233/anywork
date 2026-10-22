part of 'settings_bots_tab.dart';

class _BotEdits {
  const _BotEdits({
    required this.name,
    required this.projectId,
    required this.appId,
    required this.secret,
  });
  final String name;
  final String projectId;
  final String appId;
  final BotSecretUpdate secret;
}

/// A secret lives only in this open editor and the submitted command. Closing
/// the dialog never writes it to a normal Client draft or driver projection.
class _BotEditor extends StatefulWidget {
  const _BotEditor({required this.bot, required this.onSave});
  final BotSnapshot bot;
  final Future<void> Function(_BotEdits) onSave;

  @override
  State<_BotEditor> createState() => _BotEditorState();
}

class _BotEditorState extends State<_BotEditor> {
  late final _name = TextEditingController(text: widget.bot.name);
  late final _appId = TextEditingController(text: widget.bot.appId);
  final _secret = TextEditingController();
  late final String _projectId = widget.bot.projectId;
  bool _clearSecret = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _secret.clear();
    _secret.dispose();
    _name.dispose();
    _appId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.l10n.settingsBotsEdit),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 500),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error case final error?) ...[
              SettingsInlineError(message: error),
              const SizedBox(height: 12),
            ],
            TextField(
              key: StudioDriverKeys.botsName,
              controller: _name,
              decoration: InputDecoration(
                labelText: context.l10n.settingsBotsName,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _appId,
              readOnly: !widget.bot.canChangeAppId,
              decoration: InputDecoration(
                labelText: context.l10n.settingsBotsAppId,
              ),
            ),
            if (!widget.bot.canChangeAppId)
              Text(context.l10n.settingsBotsAppIdLocked),
            const SizedBox(height: 12),
            TextField(
              controller: _secret,
              obscureText: true,
              enabled: !_clearSecret,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: context.l10n.settingsBotsSecret,
                helperText: context.l10n.settingsBotsPreserveSecret,
              ),
            ),
            CheckboxListTile(
              value: _clearSecret,
              title: Text(context.l10n.settingsBotsClearSecret),
              onChanged: (value) => setState(() {
                _clearSecret = value ?? false;
                if (_clearSecret) _secret.clear();
              }),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: Text(context.l10n.settingsBotsDismiss),
      ),
      FilledButton(
        key: StudioDriverKeys.botsSave,
        onPressed: _busy
            ? null
            : () async {
                setState(() {
                  _busy = true;
                  _error = null;
                });
                final secret = _clearSecret
                    ? const BotSecretClear()
                    : _secret.text.isEmpty
                    ? const BotSecretPreserve()
                    : BotSecretReplace(_secret.text);
                try {
                  await widget.onSave(
                    _BotEdits(
                      name: _name.text,
                      projectId: _projectId,
                      appId: _appId.text,
                      secret: secret,
                    ),
                  );
                  _secret.clear();
                  if (context.mounted) Navigator.pop(context);
                } catch (error) {
                  if (mounted) {
                    setState(() {
                      _error = error is StudioFailure
                          ? error.message
                          : context.l10n.settingsBotsOperationFailed;
                    });
                  }
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
              },
        child: Text(context.l10n.settingsBotsSave),
      ),
    ],
  );
}
