import 'package:anywork_client/remote.dart';
import 'package:flutter/material.dart';

import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../widgets/settings_form_field.dart';
import '../state/ssh_editor_state.dart';
import 'ssh_view.dart';

class SshPasswordView extends StatelessWidget {
  const SshPasswordView({required this.state, required this.server, required this.errors,
    required this.onPassword, required this.onRemember, required this.onVisibility,
    required this.onSubmit, required this.onCancel, super.key});
  final SshPasswordViewState state;
  final SshServerProfile server;
  final List<String> errors;
  final ValueChanged<String> onPassword;
  final ValueChanged<bool> onRemember;
  final VoidCallback onVisibility;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;
  @override
  Widget build(BuildContext context) => AlertDialog(key: StudioDriverKeys.sshPasswordPromptDialog,
    scrollable: true, title: Text(context.l10n.settingsSshAuthPromptTitle),
    content: SizedBox(width: 440, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(context.l10n.settingsSshAuthPromptSubtitle('${server.username}@${server.hostName}:${server.port}')),
      const SizedBox(height: 16),
      SettingsFormField(key: StudioDriverKeys.sshPasswordPromptInput, value: state.password,
        label: context.l10n.settingsSshAuthPasswordLabel, enabled: !(state.action?.preventsResubmission ?? false),
        autofocus: true, obscureText: !state.passwordVisible, onChanged: onPassword,
        onSubmitted: (_) => onSubmit(), error: state.requiredError ? context.l10n.settingsSshAuthPasswordRequired : null,
        suffix: IconButton(onPressed: onVisibility,
          icon: Icon(state.passwordVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18))),
      CheckboxListTile(key: StudioDriverKeys.sshPasswordPromptRemember, contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading, dense: true, value: state.rememberPassword,
        onChanged: state.action?.preventsResubmission == true ? null : (value) { if (value != null) onRemember(value); },
        title: Text(context.l10n.settingsSshAuthRememberPassword)),
      if (state.connection case final connection?) Text(sshPhaseLabel(context, connection.state)),
      if (state.connection?.state case FailedSshConnectionState(:final code, :final message))
        SelectableText('$message [$code]', style: TextStyle(color: Theme.of(context).colorScheme.error)),
      for (final error in errors) SelectableText(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
    ])),
    actions: [
      TextButton(onPressed: state.action?.pending == true ? null : onCancel, child: Text(context.l10n.settingsCancel)),
      FilledButton.icon(key: StudioDriverKeys.sshPasswordPromptSubmit,
        onPressed: state.action?.preventsResubmission == true ? null : onSubmit,
        icon: state.action?.pending == true ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.login_outlined, size: 17),
        label: Text(context.l10n.settingsSshAuthConnect)),
    ]);
}
