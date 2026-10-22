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
  const _BotEditor({required this.bot, required this.projects});
  final BotSnapshot bot;
  final List<StudioProject> projects;

  @override
  State<_BotEditor> createState() => _BotEditorState();
}

class _BotEditorState extends State<_BotEditor> {
  late final _name = TextEditingController(text: widget.bot.name);
  late final _appId = TextEditingController(text: widget.bot.appId);
  final _secret = TextEditingController();
  late String _projectId = widget.bot.projectId;
  bool _clearSecret = false;

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
            TextField(
              controller: _name,
              decoration: InputDecoration(
                labelText: context.l10n.settingsBotsName,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _projectId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: context.l10n.settingsBotsProject,
              ),
              items: [
                if (!widget.projects.any(
                  (project) => project.id == widget.bot.projectId,
                ))
                  DropdownMenuItem(
                    value: widget.bot.projectId,
                    child: Text(
                      widget.bot.projectId,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                for (final project in widget.projects)
                  DropdownMenuItem(
                    value: project.id,
                    child: Text(project.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: widget.bot.canChangeProject
                  ? (value) {
                      if (value != null) _projectId = value;
                    }
                  : null,
            ),
            if (!widget.bot.canChangeProject)
              Text(context.l10n.settingsBotsProjectLocked),
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
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.settingsBotsDismiss),
      ),
      FilledButton(
        onPressed: () {
          final secret = _clearSecret
              ? const BotSecretClear()
              : _secret.text.isEmpty
              ? const BotSecretPreserve()
              : BotSecretReplace(_secret.text);
          _secret.clear();
          Navigator.pop(
            context,
            _BotEdits(
              name: _name.text,
              projectId: _projectId,
              appId: _appId.text,
              secret: secret,
            ),
          );
        },
        child: Text(context.l10n.settingsBotsSave),
      ),
    ],
  );
}
