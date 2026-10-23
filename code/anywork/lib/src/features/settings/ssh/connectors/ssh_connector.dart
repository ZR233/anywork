import 'dart:async';

import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../ui/overlays/confirmation_view.dart';
import '../../connectors/settings_failure_text.dart';
import '../../presentation_api.dart';
import '../state/ssh_view_state.dart';
import '../view_models/ssh_view_model.dart';
import '../views/ssh_view.dart';
import 'ssh_action_errors.dart';

class SshConnector extends ConsumerStatefulWidget {
  const SshConnector({super.key});
  @override
  ConsumerState<SshConnector> createState() => _SshConnectorState();
}

class _SshConnectorState extends ConsumerState<SshConnector> {
  bool _confirmingDelete = false;
  SshViewModel get _vm => ref.read(sshViewModelProvider.notifier);
  @override
  void initState() { super.initState(); unawaited(_enter()); }
  Future<void> _enter() async {
    final vm = _vm;
    final lifetime = vm.lifetime;
    final ready = ref.read(sshViewModelProvider.future);
    try { await ready; }
    on StudioFailure { return; }
    if (mounted && vm.ownsLifetime(lifetime)) await vm.enter();
  }
  Future<void> _connect(String alias, {bool reconnect = false}) async {
    final vm = _vm;
    final challenge = await (reconnect ? vm.reconnect(alias) : vm.test(alias));
    if (mounted && challenge != null && vm.ownsChallenge(challenge)) await _password(alias, challenge: challenge);
  }
  Future<void> _password(String alias, {SshPasswordChallenge? challenge}) async {
    final server = _vm.server(alias)?.profile;
    if (server != null && mounted) await showSshPasswordDialog(context, ref, server: server, initialError: challenge?.error);
  }
  Future<void> _open(String alias) async {
    final server = _vm.server(alias)?.profile;
    if (server != null && mounted) await showRemoteDirectoryDialog(context, ref, server: server);
  }
  Future<void> _delete(String alias) async {
    final vm = _vm;
    if (_confirmingDelete || !vm.beginDeleteConfirmation(alias)) return;
    _confirmingDelete = true;
    try {
      final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) => ConfirmationView(
        title: context.l10n.settingsSshDeleteTitle, body: context.l10n.settingsSshDeleteBody(alias),
        confirmLabel: context.l10n.settingsSshDelete, cancelLabel: context.l10n.settingsCancel,
        destructive: true, confirmKey: StudioDriverKeys.sshDeleteConfirm,
        onConfirm: () => Navigator.pop(dialogContext, true), onCancel: () => Navigator.pop(dialogContext, false)));
      if (confirmed == true && mounted) await vm.delete(alias);
    } finally { _confirmingDelete = false; vm.cancelDeleteConfirmation(alias); }
  }
  @override
  Widget build(BuildContext context) => ref.watch(sshViewModelProvider).when(
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (error, stack) {
      if (error is! StudioFailure) Error.throwWithStackTrace(error, stack);
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        SelectableText(settingsFailureText(error)),
        TextButton(onPressed: () { ref.invalidate(sshViewModelProvider); unawaited(_enter()); }, child: Text(context.l10n.runtimeFatalRetry)),
      ]));
    },
    data: (value) => SshView(state: value, errors: sshActionErrors(value.reloadAction),
      rowErrors: {for (final entry in value.actions.entries) entry.key: sshActionErrors(entry.value.action)},
      busyAliases: {for (final entry in value.source.servers ?? []) if (_vm.busy(entry.profile.alias)) entry.profile.alias},
      onAdd: () => unawaited(showSshEditorDialog(context, ref)), onReload: () => unawaited(_vm.reload()),
      onTest: (alias) => unawaited(_connect(alias)), onReconnect: (alias) => unawaited(_connect(alias, reconnect: true)),
      onOpen: (alias) => unawaited(_open(alias)), onEdit: (alias) => unawaited(showSshEditorDialog(context, ref, alias: alias)),
      onDelete: (alias) => unawaited(_delete(alias)), onPassword: (alias) => unawaited(_password(alias))),
  );
}
