import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/studio_tokens.dart';
import '../../domain/models/studio_models.dart';
import '../../l10n/studio_l10n.dart';
import '../../presentation/providers/client_provider.dart';
import '../../shared/studio_driver_keys.dart';
import 'settings_common.dart';

/// 連接未保存密码的远程主机或遇到 SSH 认证失败时的密码输入弹窗。
class SshPasswordPromptDialog extends ConsumerStatefulWidget {
  const SshPasswordPromptDialog({
    super.key,
    required this.server,
    this.initialError,
  });

  final SshServer server;
  final String? initialError;

  @override
  ConsumerState<SshPasswordPromptDialog> createState() =>
      _SshPasswordPromptDialogState();
}

class _SshPasswordPromptDialogState
    extends ConsumerState<SshPasswordPromptDialog> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _rememberPassword = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _error = widget.initialError;
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final snapshot = await ref
          .read(anyworkClientProvider)
          .remote
          .authenticateSshServer(
            AuthenticateSshServerCommand(
              alias: widget.server.alias,
              password: _password.text,
              rememberPassword: _rememberPassword,
            ),
          );
      if (!mounted) return;
      if (snapshot.state != 'ready') {
        setState(() {
          _submitting = false;
          _error = snapshot.errorMessage ?? snapshot.state;
        });
        return;
      }
      Navigator.of(context).pop(snapshot);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final target =
        '${widget.server.username}@${widget.server.hostName}:${widget.server.port}';
    return PopScope(
      canPop: !_submitting,
      child: SettingsFormDialog(
        key: StudioDriverKeys.sshPasswordPromptDialog,
        title: Text(context.l10n.settingsSshAuthPromptTitle),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.l10n.settingsSshAuthPromptSubtitle(target),
                    style: context.text.bodyMedium?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: StudioDriverKeys.sshPasswordPromptInput,
                    controller: _password,
                    autofocus: true,
                    obscureText: _obscure,
                    enabled: !_submitting,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => unawaited(_submit()),
                    decoration: InputDecoration(
                      labelText: context.l10n.settingsSshAuthPasswordLabel,
                      prefixIcon: const Icon(Icons.password_outlined, size: 18),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 18,
                        ),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return context.l10n.settingsSshAuthPasswordRequired;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    key: StudioDriverKeys.sshPasswordPromptRemember,
                    value: _rememberPassword,
                    onChanged: _submitting
                        ? null
                        : (value) =>
                              setState(() => _rememberPassword = value ?? true),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(context.l10n.settingsSshAuthRememberPassword),
                  ),
                  if (_error case final error?) ...[
                    const SizedBox(height: 8),
                    SettingsInlineError(message: error),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _submitting ? null : () => Navigator.of(context).pop(),
            child: Text(context.l10n.settingsCancel),
          ),
          FilledButton.icon(
            key: StudioDriverKeys.sshPasswordPromptSubmit,
            onPressed: _submitting ? null : () => unawaited(_submit()),
            icon: _submitting
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login_outlined, size: 17),
            label: Text(context.l10n.settingsSshAuthConnect),
          ),
        ],
      ),
    );
  }
}
