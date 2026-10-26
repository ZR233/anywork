import 'dart:async';

import 'package:anywork_client/remote.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../connectors/settings_failure_text.dart';
import '../../state/editor_keys.dart';
import '../view_models/ssh_editor_view_model.dart';
import '../views/ssh_editor_view.dart';
import 'ssh_action_errors.dart';

class SshEditorConnector extends ConsumerWidget {
  const SshEditorConnector({
    required this.target,
    required this.onClose,
    super.key,
  });
  final SshEditorKey target;
  final ValueChanged<SshServerRuntimeEntry?> onClose;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = sshEditorViewModelProvider(target);
    void cancel() {
      if (ref.read(provider).asData?.value.saving == true) return;
      onClose(null);
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) cancel();
      },
      child: ref
          .watch(provider)
          .when(
            loading: () => const AlertDialog(
              content: Center(
                heightFactor: 2,
                child: CircularProgressIndicator(),
              ),
            ),
            error: (error, stack) {
              if (error is! StudioFailure) {
                Error.throwWithStackTrace(error, stack);
              }
              return AlertDialog(
                content: SelectableText(settingsFailureText(error)),
                actions: [
                  TextButton(
                    onPressed: cancel,
                    child: Text(context.l10n.settingsCancel),
                  ),
                ],
              );
            },
            data: (state) {
              final vm = ref.read(provider.notifier);
              return SshEditorView(
                state: state,
                errors: sshActionErrors(state.saveAction),
                onField: vm.setField,
                onPassword: vm.setPassword,
                onClearPassword: vm.clearPassword,
                onVisibility: vm.togglePasswordVisibility,
                onCancel: cancel,
                onSave: () => unawaited(() async {
                  final saved = await vm.save();
                  if (saved != null && context.mounted) onClose(saved);
                }()),
              );
            },
          ),
    );
  }
}
