import 'package:anywork_client/remote.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ssh/connectors/remote_directory_connector.dart';
import 'ssh/connectors/ssh_editor_connector.dart';
import 'ssh/connectors/ssh_password_connector.dart';
import 'ssh/view_models/remote_directory_view_model.dart';
import 'ssh/view_models/ssh_editor_view_model.dart';
import 'ssh/view_models/ssh_password_view_model.dart';
import 'ssh/view_models/ssh_view_model.dart';

export 'connectors/settings_navigation_connector.dart' show confirmLeaveSettings;
export 'settings_screen.dart' show SettingsScreen;
export 'state/settings_navigation_state.dart' show SettingsTab;

/// Smart UI entrypoints, not a business facade or a second dialog owner.
Future<({SshViewModel owner, int lifetime})?> _sshOwner(BuildContext context, WidgetRef ref) async {
  final owner = ref.read(sshViewModelProvider.notifier);
  final lifetime = owner.lifetime;
  final ready = ref.read(sshViewModelProvider.future);
  await ready;
  if (!context.mounted || !owner.ownsLifetime(lifetime)) return null;
  await owner.enter();
  if (!context.mounted || !owner.ownsLifetime(lifetime)) return null;
  return (owner: owner, lifetime: lifetime);
}

Future<SshServerRuntimeEntry?> showSshEditorDialog(BuildContext context, WidgetRef ref, {String? alias}) async {
  final captured = await _sshOwner(context, ref);
  if (captured == null || !context.mounted) return null;
  final owner = captured.owner;
  final key = owner.beginEditor(alias);
  if (key == null) return null;
  final editor = ref.read(sshEditorViewModelProvider(key).notifier);
  SshServerRuntimeEntry? saved;
  try {
    if (!context.mounted || !owner.ownsLifetime(captured.lifetime)) return null;
    saved = await showDialog<SshServerRuntimeEntry>(context: context, barrierDismissible: false,
      builder: (dialogContext) => SshEditorConnector(target: key,
        onClose: (value) => Navigator.pop(dialogContext, value)));
  } finally {
    editor.endEditing(); owner.finishEditor(key);
  }
  if (saved != null && owner.ownsLifetime(captured.lifetime)) await owner.reload();
  return saved;
}

Future<bool?> showSshPasswordDialog(BuildContext context, WidgetRef ref, {
  required SshServerProfile server, StudioFailure? initialError,
}) async {
  // Automatic callers pass only the actual typed SSH challenge. Unknown
  // password support still permits a deliberate user attempt; false does not.
  if (initialError != null) {
    final details = initialError.details;
    if (details is! SshAuthenticationFailureDetails || details.passwordOffered == false) return null;
  }
  final alias = server.alias;
  final captured = await _sshOwner(context, ref);
  if (captured == null || !context.mounted) return null;
  final owner = captured.owner;
  final registration = owner.beginPassword(alias);
  if (registration == null) return null;
  final password = ref.read(sshPasswordViewModelProvider(alias, registration.scopeId, registration.promptId).notifier);
  bool? ready;
  try {
    if (!context.mounted || !owner.ownsLifetime(captured.lifetime)) return null;
    ready = await showDialog<bool>(context: context, barrierDismissible: false,
      builder: (dialogContext) => SshPasswordConnector(server: server,
        scopeId: registration.scopeId, promptId: registration.promptId, initialError: initialError,
        onClose: (value) => Navigator.pop(dialogContext, value)));
  } finally {
    password.endEditing(); owner.finishPassword(alias, registration.promptId);
  }
  if (ready == true && owner.ownsLifetime(captured.lifetime)) await owner.reload();
  return ready;
}

Future<String?> showRemoteDirectoryDialog(BuildContext context, WidgetRef ref, {
  required SshServerProfile server, bool showProjectNameField = false,
}) async {
  final alias = server.alias;
  final captured = await _sshOwner(context, ref);
  if (captured == null || !context.mounted) return null;
  final owner = captured.owner;
  final pickerId = owner.beginDirectory(alias);
  if (pickerId == null) return null;
  final directory = ref.read(remoteDirectoryViewModelProvider(alias, pickerId, showProjectNameField).notifier);
  String? result;
  String? openedPath;
  var complete = false;
  try {
    if (!context.mounted || !owner.ownsLifetime(captured.lifetime)) return null;
    result = await showDialog<String>(context: context, barrierDismissible: false,
      builder: (dialogContext) => RemoteDirectoryConnector(server: server, pickerId: pickerId,
        showProjectNameField: showProjectNameField, onClose: (path) => Navigator.pop(dialogContext, path)));
  } finally {
    try {
      // Explicit dialog end, not Widget.dispose. A late cursor remains with
      // the original D3 query; false is never presented as a Clean result.
      complete = await directory.close();
      openedPath = directory.openedPath;
    } finally {
      directory.endBrowsing(); owner.finishDirectory(alias, pickerId);
    }
  }
  return complete && result != null && result == openedPath ? result : null;
}
