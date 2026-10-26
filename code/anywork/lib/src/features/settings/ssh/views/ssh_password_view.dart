import 'package:anywork_client/remote.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../widgets/settings_feedback.dart';
import '../../widgets/settings_form_dialog.dart';
import '../../widgets/settings_form_field.dart';
import '../state/ssh_editor_state.dart';

/// SSH password prompt.
///
/// Bounded form dialog with the pre-refactor content: 440 px column, a styled
/// target subtitle, an 8 px gap before the `CheckboxListTile` remember row and a
/// single inline failure.
class SshPasswordView extends StatelessWidget {
  const SshPasswordView({
    required this.state,
    required this.server,
    required this.errors,
    required this.onPassword,
    required this.onRemember,
    required this.onVisibility,
    required this.onSubmit,
    required this.onCancel,
    super.key,
  });
  final SshPasswordViewState state;
  final SshServerProfile server;
  final List<String> errors;
  final ValueChanged<String> onPassword;
  final ValueChanged<bool> onRemember;
  final VoidCallback onVisibility;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final busy = state.action?.preventsResubmission ?? false;
    final pending = state.action?.pending ?? false;
    return SettingsFormDialog(
      key: StudioDriverKeys.sshPasswordPromptDialog,
      title: Text(context.l10n.settingsSshAuthPromptTitle),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${server.username}@${server.hostName}:${server.port}',
                style: context.text.bodyMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              SettingsFormField(
                key: StudioDriverKeys.sshPasswordPromptInput,
                value: state.password,
                label: context.l10n.settingsSshAuthPasswordLabel,
                enabled: !busy,
                autofocus: true,
                obscureText: !state.passwordVisible,
                onChanged: onPassword,
                onSubmitted: (_) => onSubmit(),
                prefixIcon: Icons.password_outlined,
                error: state.requiredError
                    ? context.l10n.settingsSshAuthPasswordRequired
                    : null,
                suffix: IconButton(
                  onPressed: onVisibility,
                  icon: Icon(
                    state.passwordVisible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                key: StudioDriverKeys.sshPasswordPromptRemember,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                value: state.rememberPassword,
                onChanged: busy
                    ? null
                    : (value) {
                        if (value != null) onRemember(value);
                      },
                title: Text(context.l10n.settingsSshAuthRememberPassword),
              ),
              if (_failure() case final failure?) ...[
                const SizedBox(height: 8),
                SettingsInlineError(message: failure),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: pending ? null : onCancel,
          child: Text(context.l10n.settingsCancel),
        ),
        FilledButton.icon(
          key: StudioDriverKeys.sshPasswordPromptSubmit,
          onPressed: busy ? null : onSubmit,
          icon: pending
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.login_outlined, size: 17),
          label: Text(context.l10n.settingsSshAuthConnect),
        ),
      ],
    );
  }

  /// One failure line: transport failures first, then a failed connection.
  String? _failure() {
    if (errors.isNotEmpty) return errors.first;
    if (state.connection?.state case FailedSshConnectionState(
      :final code,
      :final message,
    )) {
      return '$message [$code]';
    }
    return null;
  }
}
