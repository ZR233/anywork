import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../widgets/settings_form_field.dart';
import '../state/ssh_editor_state.dart';

class SshEditorView extends StatelessWidget {
  const SshEditorView({required this.state, required this.errors, required this.onField,
    required this.onPassword, required this.onClearPassword, required this.onVisibility,
    required this.onCancel, required this.onSave, super.key});
  final SshEditorViewState state;
  final List<String> errors;
  final void Function(SshEditorField field, String raw) onField;
  final ValueChanged<String> onPassword;
  final VoidCallback onClearPassword;
  final VoidCallback onVisibility;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final enabled = !state.readOnly && !(state.saveAction?.preventsResubmission ?? false);
    final keepPassword = state.hasPassword && state.passwordIntent == SshSecretIntent.preserve && state.password.isEmpty;
    return AlertDialog(key: StudioDriverKeys.sshServerDialog,
      title: Text(state.editing ? context.l10n.settingsSshEditTitle : context.l10n.settingsSshAdd),
      scrollable: true,
      content: SizedBox(width: 500, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _field(context, SshEditorField.alias, state.alias, context.l10n.settingsSshAlias,
          StudioDriverKeys.sshServerAliasInput, enabled && !state.editing, helper: context.l10n.settingsSshAliasHelper),
        _field(context, SshEditorField.host, state.host, context.l10n.settingsSshHost,
          StudioDriverKeys.sshServerHostInput, enabled),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _field(context, SshEditorField.username, state.username, context.l10n.settingsSshUsername,
            StudioDriverKeys.sshServerUsernameInput, enabled)),
          const SizedBox(width: 12),
          SizedBox(width: 120, child: _field(context, SshEditorField.port, state.port, context.l10n.settingsSshPort,
            StudioDriverKeys.sshServerPortInput, enabled, numeric: true)),
        ]),
        Padding(padding: const EdgeInsets.only(bottom: 14), child: SettingsFormField(
          key: StudioDriverKeys.sshServerPasswordInput, value: state.password, label: context.l10n.settingsSshPassword,
          enabled: enabled, obscureText: !state.passwordVisible, onChanged: onPassword,
          hint: keepPassword ? context.l10n.settingsSshPasswordSavedHint : null,
          helper: state.passwordIntent == SshSecretIntent.clear
            ? context.l10n.settingsSshPasswordClearedHint : context.l10n.settingsSshPasswordHelper,
          suffix: Row(mainAxisSize: MainAxisSize.min, children: [
            if (keepPassword) IconButton(key: StudioDriverKeys.sshServerPasswordClear,
              tooltip: context.l10n.settingsSshPasswordClear, onPressed: enabled ? onClearPassword : null,
              icon: const Icon(Icons.clear, size: 18)),
            IconButton(onPressed: onVisibility, icon: Icon(state.passwordVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18)),
          ]))),
        _field(context, SshEditorField.identityFile, state.identityFile, context.l10n.settingsSshIdentityFile,
          StudioDriverKeys.sshServerIdentityInput, enabled, helper: context.l10n.settingsSshIdentityHelper),
        if (state.readOnly) Text(context.l10n.settingsSshReadOnlyEntry),
        for (var i = 0; i < errors.length; i++) SelectableText(errors[i],
          key: i == 0 ? StudioDriverKeys.sshServerValidationError : null,
          style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ])),
      actions: [
        TextButton(onPressed: state.saving ? null : onCancel, child: Text(context.l10n.settingsCancel)),
        FilledButton.icon(key: StudioDriverKeys.sshServerSave, onPressed: enabled ? onSave : null,
          icon: state.saving ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check, size: 18),
          label: Text(context.l10n.settingsSshSave)),
      ]);
  }
  Widget _field(BuildContext context, SshEditorField field, String value, String label,
      Key key, bool enabled, {String? helper, bool numeric = false}) => Padding(padding: const EdgeInsets.only(bottom: 14),
    child: SettingsFormField(key: key, value: value, label: label, enabled: enabled, onChanged: (raw) => onField(field, raw),
      helper: helper, keyboardType: numeric ? TextInputType.number : null,
      inputFormatters: numeric ? [FilteringTextInputFormatter.digitsOnly] : null,
      error: switch (state.validation[field]) {
        SshValidation.aliasInvalid => context.l10n.settingsSshAliasInvalid,
        SshValidation.portInvalid => context.l10n.settingsSshPortInvalid,
        SshValidation.required => switch (field) {
          SshEditorField.alias => context.l10n.settingsSshAliasRequired,
          SshEditorField.host => context.l10n.settingsSshHostRequired,
          SshEditorField.username => context.l10n.settingsSshUsernameRequired,
          _ => null,
        },
        null => null,
      }));
}
