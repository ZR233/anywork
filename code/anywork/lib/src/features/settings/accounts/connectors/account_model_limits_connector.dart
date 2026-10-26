import 'dart:async';

import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../connectors/settings_failure_text.dart';
import '../../state/settings_action.dart';
import '../view_models/account_model_limits_view_model.dart';
import '../views/account_details_view.dart';
import 'account_model_details_connector.dart';

class AccountModelLimitsConnector extends ConsumerWidget {
  const AccountModelLimitsConnector({
    required this.accountId,
    required this.onBack,
    required this.onEdit,
    required this.onRemoveModel,
    this.iconKey,
    this.usage,
    this.modelErrors = const {},
    super.key,
  });
  final String accountId;
  final VoidCallback onBack;
  final VoidCallback onEdit;
  final ValueChanged<String> onRemoveModel;
  final String? iconKey;
  final Widget? usage;
  final Map<String, List<String>> modelErrors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = accountModelLimitsViewModelProvider(accountId);
    return ref
        .watch(provider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) {
            if (error is! StudioFailure) {
              Error.throwWithStackTrace(error, stack);
            }
            return Column(
              children: [
                SelectableText(settingsFailureText(error)),
                TextButton(
                  onPressed: () => ref.invalidate(provider),
                  child: Text(context.l10n.runtimeFatalRetry),
                ),
                TextButton(
                  onPressed: onBack,
                  child: Text(context.l10n.settingsAccountsTitle),
                ),
              ],
            );
          },
          data: (state) {
            final vm = ref.read(provider.notifier);
            return AccountDetailsView(
              state: state,
              usage: usage,
              iconKey: iconKey,
              onBack: onBack,
              onEdit: onEdit,
              onRemoveModel: onRemoveModel,
              onLimit: vm.edit,
              onComposing: vm.setComposing,
              onCommit: vm.commit,
              onRestore: vm.restoreDefault,
              onRetry: vm.retryRead,
              onModelEnabled: state.binding == null
                  ? null
                  : (modelId, enabled) => unawaited(
                      vm.setModelEnabled(modelId, enabled, state.binding!),
                    ),
              onBillingKind: state.binding == null
                  ? null
                  : (kind) =>
                        unawaited(vm.setBillingKind(kind, state.binding!)),
              onModelDetails: (modelId) {
                final entry = vm.openModelDetails(modelId, state.binding);
                if (entry != null) {
                  unawaited(
                    showDialog<void>(
                      context: context,
                      builder: (_) =>
                          AccountModelDetailsConnector(entry: entry),
                    ),
                  );
                }
              },
              enabledErrors: {
                for (final entry in state.enabledActions.entries)
                  if (entry.value.binding == state.binding)
                    entry.key: _errors(entry.value.action),
              },
              billingErrors: state.billingAction?.binding == state.binding
                  ? _errors(state.billingAction?.action)
                  : [],
              errors: [
                if (state.source.projection.sync.error case final error?)
                  settingsFailureText(error),
                if (state.modelSource.projection.sync.error case final error?)
                  settingsFailureText(error),
                for (final error in state.readIssues.values)
                  settingsFailureText(error),
              ],
              modelErrors: {
                for (final model in state.catalog.effectiveModels)
                  model.modelId: [
                    ...?modelErrors[model.modelId],
                    ..._errors(state.drafts[model.modelId]?.action),
                  ],
              },
            );
          },
        );
  }

  List<String> _errors(SettingsAction? action) => {
    if (action?.error case final error?) settingsFailureText(error),
    if (action?.operation?.error case final error?) settingsFailureText(error),
    if (action?.observationError case final error?) settingsFailureText(error),
    if (action?.operation?.evidenceError case final error?)
      settingsFailureText(error),
  }.toList();
}
