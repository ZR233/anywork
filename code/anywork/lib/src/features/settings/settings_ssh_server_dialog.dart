import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/models/studio_models.dart';
import '../../l10n/studio_l10n.dart';
import '../../shared/studio_driver_keys.dart';
import 'settings_common.dart';

class SshServerDialog extends StatefulWidget {
  const SshServerDialog({super.key, this.server, this.onSave, this.saveLabel});

  final SshServer? server;
  final Future<void> Function(SaveSshServerCommand)? onSave;
  final String? saveLabel;

  @override
  State<SshServerDialog> createState() => _SshServerDialogState();
}

class _SshServerDialogState extends State<SshServerDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _alias;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _identity;
  bool _obscurePassword = true;
  bool _clearSavedPassword = false;
  String? _submitError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final server = widget.server;
    _alias = TextEditingController(text: server?.alias ?? '');
    _host = TextEditingController(text: server?.hostName ?? '');
    _port = TextEditingController(text: '${server?.port ?? 22}');
    _username = TextEditingController(text: server?.username ?? '');
    _password = TextEditingController();
    _identity = TextEditingController(text: server?.identityFile ?? '');
  }

  @override
  void dispose() {
    _alias.dispose();
    _host.dispose();
    _port.dispose();
    _username.dispose();
    _password.dispose();
    _identity.dispose();
    super.dispose();
  }

  SshPasswordUpdate _buildPasswordUpdate() {
    if (_password.text.trim().isNotEmpty) {
      return SshPasswordUpdate.replace(_password.text);
    }
    if (_clearSavedPassword) {
      return const SshPasswordUpdate.clear();
    }
    return const SshPasswordUpdate.preserve();
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() => _submitError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final command = SaveSshServerCommand(
      alias: _alias.text.trim(),
      hostName: _host.text.trim(),
      port: int.parse(_port.text.trim()),
      username: _username.text.trim(),
      identityFile: _identity.text.trim().isEmpty
          ? null
          : _identity.text.trim(),
      password: _buildPasswordUpdate(),
    );
    if (widget.onSave == null) {
      Navigator.of(context).pop(command);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onSave!(command);
      if (mounted) Navigator.of(context).pop(command);
    } catch (error) {
      if (mounted) {
        setState(() => _submitError = error.toString());
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final server = widget.server;
    final editing = server != null;
    final hasSavedPassword = server?.hasPassword ?? false;
    final showKeepSavedHint =
        hasSavedPassword && !_clearSavedPassword && _password.text.isEmpty;

    return PopScope(
      canPop: !_saving,
      child: SettingsFormDialog(
        key: StudioDriverKeys.sshServerDialog,
        title: Text(
          editing
              ? context.l10n.settingsSshEditTitle
              : context.l10n.settingsSshAdd,
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: SettingsFieldStack(
                children: [
                  TextFormField(
                    key: StudioDriverKeys.sshServerAliasInput,
                    controller: _alias,
                    enabled: !editing && !_saving,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: context.l10n.settingsSshAlias,
                      helperText: context.l10n.settingsSshAliasHelper,
                      prefixIcon: const Icon(Icons.badge_outlined, size: 18),
                    ),
                    validator: (value) {
                      final alias = value?.trim() ?? '';
                      if (alias.isEmpty) {
                        return context.l10n.settingsSshAliasRequired;
                      }
                      if (alias.contains(RegExp("[\\s*?\\[\\]!#\"'\\\\]")) ||
                          alias.startsWith('-')) {
                        return context.l10n.settingsSshAliasInvalid;
                      }
                      return null;
                    },
                  ),
                  TextFormField(
                    key: StudioDriverKeys.sshServerHostInput,
                    controller: _host,
                    enabled: !_saving,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: context.l10n.settingsSshHost,
                      hintText: '192.168.1.10 / dev.example.com',
                      prefixIcon: const Icon(Icons.dns_outlined, size: 18),
                    ),
                    validator: (value) {
                      if ((value?.trim() ?? '').isEmpty) {
                        return context.l10n.settingsSshHostRequired;
                      }
                      return null;
                    },
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: StudioDriverKeys.sshServerUsernameInput,
                          controller: _username,
                          enabled: !_saving,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: context.l10n.settingsSshUsername,
                            prefixIcon: const Icon(
                              Icons.person_outline,
                              size: 18,
                            ),
                          ),
                          validator: (value) {
                            if ((value?.trim() ?? '').isEmpty) {
                              return context.l10n.settingsSshUsernameRequired;
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 120,
                        child: TextFormField(
                          key: StudioDriverKeys.sshServerPortInput,
                          controller: _port,
                          enabled: !_saving,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: context.l10n.settingsSshPort,
                          ),
                          validator: (value) {
                            final port = int.tryParse(value?.trim() ?? '');
                            if (port == null || port <= 0 || port > 65535) {
                              return context.l10n.settingsSshPortInvalid;
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  TextFormField(
                    key: StudioDriverKeys.sshServerPasswordInput,
                    controller: _password,
                    enabled: !_saving,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.next,
                    onChanged: (value) {
                      setState(() {
                        if (value.isNotEmpty) {
                          _clearSavedPassword = false;
                        }
                      });
                    },
                    decoration: InputDecoration(
                      labelText: context.l10n.settingsSshPassword,
                      hintText: showKeepSavedHint
                          ? context.l10n.settingsSshPasswordSavedHint
                          : null,
                      helperText: _clearSavedPassword
                          ? context.l10n.settingsSshPasswordClearedHint
                          : context.l10n.settingsSshPasswordHelper,
                      helperMaxLines: 2,
                      prefixIcon: const Icon(Icons.password_outlined, size: 18),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (showKeepSavedHint)
                            IconButton(
                              key: StudioDriverKeys.sshServerPasswordClear,
                              tooltip: context.l10n.settingsSshPasswordClear,
                              onPressed: _saving
                                  ? null
                                  : () => setState(
                                      () => _clearSavedPassword = true,
                                    ),
                              icon: const Icon(Icons.clear, size: 18),
                            ),
                          IconButton(
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  TextFormField(
                    key: StudioDriverKeys.sshServerIdentityInput,
                    controller: _identity,
                    enabled: !_saving,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => unawaited(_submit()),
                    decoration: InputDecoration(
                      labelText: context.l10n.settingsSshIdentityFile,
                      helperText: context.l10n.settingsSshIdentityHelper,
                      prefixIcon: const Icon(Icons.vpn_key_outlined, size: 18),
                    ),
                  ),
                  if (_submitError case final error?)
                    SettingsInlineError(
                      key: StudioDriverKeys.sshServerValidationError,
                      message: error,
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: Text(context.l10n.settingsCancel),
          ),
          FilledButton.icon(
            key: StudioDriverKeys.sshServerSave,
            onPressed: _saving ? null : () => unawaited(_submit()),
            icon: _saving
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check, size: 18),
            label: Text(
              _saving
                  ? context.l10n.sidebarLoadingMore
                  : (widget.saveLabel ?? context.l10n.settingsSshSave),
            ),
          ),
        ],
      ),
    );
  }
}
