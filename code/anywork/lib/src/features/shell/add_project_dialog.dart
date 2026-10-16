part of 'studio_shell.dart';

Future<void> showAddProjectDialog(BuildContext context) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => const _AddProjectDialog(),
);

enum _AddProjectStep { location, connections, directory }

class _AddProjectDialog extends ConsumerStatefulWidget {
  const _AddProjectDialog();

  @override
  ConsumerState<_AddProjectDialog> createState() => _AddProjectDialogState();
}

class _AddProjectDialogState extends ConsumerState<_AddProjectDialog> {
  _AddProjectStep _step = _AddProjectStep.location;
  bool? _remote;
  bool _busy = false;
  bool _picking = false;
  String? _error;
  List<SshServer>? _servers;
  SshServer? _selected;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (_busy || _remote == null) return;
    if (_remote!) {
      setState(() {
        _step = _AddProjectStep.connections;
        _error = null;
      });
      await _loadServers();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      setState(() => _picking = true);
      final path = await ref.read(projectDirectoryPickerProvider)(context);
      if (mounted) setState(() => _picking = false);
      if (!mounted || path == null || path.isEmpty) return;
      await ref.read(anyworkClientProvider).directoryCommands.openProject(path);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadServers() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final servers = await ref
          .read(anyworkClientProvider)
          .remote
          .listSshServers();
      if (!mounted) return;
      setState(() {
        _servers = servers;
        if (_selected != null) {
          _selected = servers
              .where((item) => item.alias == _selected!.alias)
              .firstOrNull;
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openServerEditor([SshServer? server]) async {
    if (_busy) return;
    SshServer? savedServer;
    final command = await showDialog<SaveSshServerCommand>(
      context: context,
      builder: (context) => SshServerDialog(
        server: server,
        onSave: (cmd) async {
          savedServer = await ref
              .read(anyworkClientProvider)
              .remote
              .saveSshServer(cmd);
        },
      ),
    );
    if (command == null || savedServer == null || !mounted) return;
    await _loadServers();
    if (!mounted) return;
    setState(() {
      _selected =
          _servers
              ?.where((item) => item.alias == savedServer!.alias)
              .firstOrNull ??
          savedServer;
    });
  }

  Future<void> _deleteServer(SshServer server) async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.settingsSshDeleteTitle),
        content: Text(context.l10n.settingsSshDeleteBody(server.alias)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.settingsCancel),
          ),
          FilledButton(
            key: StudioDriverKeys.sshDeleteConfirm,
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.settingsSshDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(anyworkClientProvider)
          .remote
          .deleteSshServer(server.alias);
      if (!mounted) return;
      if (_selected?.alias == server.alias) {
        _selected = null;
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) {
      await _loadServers();
    }
  }

  Future<void> _connectSelected() async {
    final selected = _selected;
    if (_busy || selected == null) return;

    final hasIdentity =
        selected.identityFile != null &&
        selected.identityFile!.trim().isNotEmpty;
    var ready = false;

    if (!selected.hasPassword && !hasIdentity) {
      final snapshot = await showDialog<SshConnectionView>(
        context: context,
        builder: (context) => SshPasswordPromptDialog(server: selected),
      );
      if (snapshot == null || !mounted) return;
      ready = snapshot.state == 'ready';
      await _loadServers();
      if (!mounted) return;
    }

    if (!ready) {
      setState(() {
        _busy = true;
        _error = null;
      });
      try {
        final connection = await ref
            .read(anyworkClientProvider)
            .remote
            .testSshConnection(selected.alias);
        if (connection.state != 'ready') {
          throw StateError(connection.errorMessage ?? connection.state);
        }
        ready = true;
      } catch (error) {
        if (!mounted) return;
        setState(() => _busy = false);
        if (isSshAuthenticationError(error)) {
          final snapshot = await showDialog<SshConnectionView>(
            context: context,
            builder: (context) => SshPasswordPromptDialog(
              server: selected,
              initialError: error.toString(),
            ),
          );
          if (snapshot == null || !mounted) return;
          ready = snapshot.state == 'ready';
          await _loadServers();
          if (!mounted) return;
        } else {
          setState(() => _error = error.toString());
          return;
        }
      } finally {
        if (mounted && _busy) setState(() => _busy = false);
      }
    }

    if (!ready || !mounted) return;
    final currentServer =
        _servers?.where((item) => item.alias == selected.alias).firstOrNull ??
        selected;
    setState(() {
      _selected = currentServer;
      _step = _AddProjectStep.directory;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_step == _AddProjectStep.directory && _selected != null) {
      return RemoteDirectoryDialog(
        key: ValueKey('remote-directory-${_selected!.alias}'),
        server: _selected!,
        showProjectNameField: true,
        onBack: () => setState(() {
          _step = _AddProjectStep.connections;
          _error = null;
        }),
      );
    }
    final location = _step == _AddProjectStep.location;
    final servers = _servers;
    final filteredServers = servers
        ?.where(
          (server) =>
              '${server.alias} ${server.username}@${server.hostName}:${server.port}'
                  .toLowerCase()
                  .contains(_search.text.trim().toLowerCase()),
        )
        .toList(growable: false);

    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        key: const ValueKey('add-project-dialog'),
        scrollable: true,
        title: Row(
          children: [
            Expanded(
              child: Text(
                location
                    ? context.l10n.sidebarAddProject
                    : context.l10n.sidebarRemoteProject,
              ),
            ),
            IconButton(
              tooltip: context.l10n.settingsCancel,
              onPressed: _busy ? null : () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        content: SizedBox(
          width: 540,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (location) ...[
                _locationCard(
                  false,
                  Icons.computer_outlined,
                  context.l10n.sidebarLocalProject,
                  context.l10n.sidebarLocalHint,
                ),
                const SizedBox(height: 12),
                _locationCard(
                  true,
                  Icons.dns_outlined,
                  context.l10n.sidebarRemoteProject,
                  context.l10n.sidebarRemoteHint,
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('add-project-connection-search'),
                        controller: _search,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search, size: 18),
                          hintText: context.l10n.sidebarSearchConnections,
                          isDense: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.tonalIcon(
                      key: StudioDriverKeys.addProjectNewConnection,
                      onPressed: _busy ? null : () => _openServerEditor(),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(context.l10n.sidebarNewConnection),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (filteredServers != null && filteredServers.isEmpty)
                  SettingsEmptyMessage(
                    icon: Icons.dns_outlined,
                    title: context.l10n.sidebarNoConnections,
                    body: context.l10n.settingsSshManagedByCore,
                  )
                else if (filteredServers != null)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final server in filteredServers) ...[
                            _buildServerTile(context, server),
                            const SizedBox(height: 8),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
              if (_busy && !_picking)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                SettingsInlineError(message: _error!),
              ],
              if (!location && _servers == null && !_busy)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _loadServers,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(context.l10n.sidebarRetry),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy
                ? null
                : () {
                    if (location) {
                      Navigator.pop(context);
                    } else {
                      setState(() {
                        _step = _AddProjectStep.location;
                        _error = null;
                      });
                    }
                  },
            child: Text(
              location ? context.l10n.settingsCancel : context.l10n.sidebarBack,
            ),
          ),
          FilledButton.icon(
            key: !_busy && (location ? _remote != null : _selected != null)
                ? const ValueKey('add-project-continue-ready')
                : const ValueKey('add-project-continue'),
            onPressed: _busy || (location ? _remote == null : _selected == null)
                ? null
                : location
                ? _continue
                : _connectSelected,
            icon: Icon(
              location ? Icons.arrow_forward : Icons.cable_outlined,
              size: 18,
            ),
            label: Text(
              location
                  ? context.l10n.sidebarContinue
                  : context.l10n.sidebarConnect,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServerTile(BuildContext context, SshServer server) {
    final selected = _selected?.alias == server.alias;
    final hasIdentity =
        server.identityFile != null && server.identityFile!.trim().isNotEmpty;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: selected
              ? context.colors.primary
              : context.colors.outlineVariant,
        ),
      ),
      child: ListTile(
        key: StudioDriverKeys.addProjectConnectionRow(server.alias),
        selected: selected,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        ),
        title: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              server.alias,
              style: context.text.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (server.hasPassword)
              SettingsMiniMeta(
                icon: Icons.password_outlined,
                label: context.l10n.settingsSshPasswordBadge,
              ),
            if (hasIdentity)
              SettingsMiniMeta(
                icon: Icons.vpn_key_outlined,
                label: context.l10n.settingsSshKeyBadge(server.identityFile!),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${server.username}@${server.hostName}:${server.port}',
            style: context.text.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
              fontFamily: 'monospace',
            ),
          ),
        ),
        trailing: server.managed
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: StudioDriverKeys.addProjectConnectionEdit(
                      server.alias,
                    ),
                    tooltip: context.l10n.settingsSshEdit,
                    onPressed: _busy ? null : () => _openServerEditor(server),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    key: StudioDriverKeys.addProjectConnectionDelete(
                      server.alias,
                    ),
                    tooltip: context.l10n.settingsSshDelete,
                    onPressed: _busy ? null : () => _deleteServer(server),
                    icon: Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: _busy ? null : context.colors.error,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              )
            : null,
        onTap: _busy ? null : () => setState(() => _selected = server),
      ),
    );
  }

  Widget _locationCard(
    bool remote,
    IconData icon,
    String title,
    String subtitle,
  ) => Card(
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(
        color: _remote == remote
            ? context.colors.primary
            : context.colors.outlineVariant,
      ),
    ),
    child: ListTile(
      key: ValueKey(remote ? 'add-project-remote' : 'add-project-local'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      leading: Icon(
        _remote == remote
            ? Icons.radio_button_checked
            : Icons.radio_button_unchecked,
      ),
      title: Row(
        children: [
          Icon(icon, size: 18, color: context.colors.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            title,
            style: context.text.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(subtitle),
      ),
      selected: _remote == remote,
      onTap: _busy ? null : () => setState(() => _remote = remote),
    ),
  );
}
