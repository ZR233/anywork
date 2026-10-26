import 'dart:async';

import 'package:anywork_client/remote.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../connectors/settings_failure_text.dart';
import '../view_models/ssh_password_view_model.dart';
import '../views/ssh_password_view.dart';
import 'ssh_action_errors.dart';

class SshPasswordConnector extends ConsumerWidget {
  const SshPasswordConnector({
    required this.server,
    required this.promptId,
    required this.onClose,
    this.scopeId = 0,
    this.initialError,
    super.key,
  });
  final SshServerProfile server;
  final int promptId;
  final int scopeId;
  final ValueChanged<bool> onClose;
  final StudioFailure? initialError;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = sshPasswordViewModelProvider(
      server.alias,
      scopeId,
      promptId,
    );
    void cancel() {
      if (ref.read(provider).asData?.value.action?.pending == true) return;
      onClose(false);
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
              return SshPasswordView(
                state: state,
                server: server,
                errors: [
                  if (state.action == null && initialError != null)
                    settingsFailureText(initialError!),
                  ...sshActionErrors(state.action),
                ],
                onPassword: vm.setPassword,
                onRemember: vm.setRemember,
                onVisibility: vm.toggleVisibility,
                onCancel: cancel,
                onSubmit: () => unawaited(() async {
                  if (await vm.submit() && context.mounted) onClose(true);
                }()),
              );
            },
          ),
    );
  }
}
