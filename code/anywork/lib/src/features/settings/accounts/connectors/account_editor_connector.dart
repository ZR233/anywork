import 'dart:async';

import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../connectors/settings_failure_text.dart';
import '../../state/editor_keys.dart';
import '../view_models/account_editor_view_model.dart';
import '../views/account_editor_view.dart';

class AccountEditorConnector extends ConsumerWidget {
  const AccountEditorConnector({
    required this.target,
    required this.onCancel,
    required this.onSaved,
    super.key,
  });
  final AccountEditorKey target;
  final VoidCallback onCancel;
  final VoidCallback onSaved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = accountEditorViewModelProvider(target);
    return ref
        .watch(provider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) {
            if (error is! StudioFailure) {
              Error.throwWithStackTrace(error, stack);
            }
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SelectableText(settingsFailureText(error)),
                  TextButton(
                    onPressed: () => ref.invalidate(provider),
                    child: Text(context.l10n.runtimeFatalRetry),
                  ),
                  TextButton(
                    onPressed: onCancel,
                    child: Text(context.l10n.settingsCancel),
                  ),
                ],
              ),
            );
          },
          data: (state) {
            final vm = ref.read(provider.notifier);
            return AccountEditorView(
              key: ValueKey((target, state.formGeneration)),
              state: state,
              onCancel: onCancel,
              onSave: () => unawaited(_save(context, vm)),
              onTemplate: vm.setTemplate,
              onName: vm.setName,
              onBaseUrl: vm.setBaseUrl,
              onPricing: vm.setPricing,
              onSecret: vm.setSecret,
              onSecretIntent: vm.setSecretIntent,
              onAddModel: vm.addCustomModel,
              onModel: vm.setCustomModel,
              onRemoveModel: vm.removeCustomModel,
              onConnection: vm.setConnection,
              errors: [
                if (state.sourceError case final error?)
                  settingsFailureText(error),
                for (final action in [
                  state.saveAction,
                  state.defaultAction,
                ]) ...[
                  if (action?.error case final error?)
                    settingsFailureText(error),
                  if (action?.observationError case final error?)
                    settingsFailureText(error),
                  if (action?.operation?.evidenceError case final error?)
                    settingsFailureText(error),
                ],
              ],
            );
          },
        );
  }

  Future<void> _save(BuildContext context, AccountEditorViewModel vm) async {
    if (await vm.save() && context.mounted) onSaved();
  }
}
