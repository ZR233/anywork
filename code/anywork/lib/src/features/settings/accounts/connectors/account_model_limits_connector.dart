import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../connectors/settings_failure_text.dart';
import '../../state/settings_action.dart';
import '../view_models/account_model_limits_view_model.dart';
import '../views/account_details_view.dart';

class AccountModelLimitsConnector extends ConsumerWidget {
  const AccountModelLimitsConnector({required this.accountId, required this.onBack,
    required this.onEdit, required this.onRemoveModel, this.usage, this.modelErrors = const {}, super.key});
  final String accountId;
  final VoidCallback onBack;
  final VoidCallback onEdit;
  final ValueChanged<String> onRemoveModel;
  final Widget? usage;
  final Map<String, List<String>> modelErrors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = accountModelLimitsViewModelProvider(accountId);
    return ref.watch(provider).when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) {
        if (error is! StudioFailure) Error.throwWithStackTrace(error, stack);
        return Column(children: [SelectableText(settingsFailureText(error)),
          TextButton(onPressed: () => ref.invalidate(provider), child: Text(context.l10n.runtimeFatalRetry)),
          TextButton(onPressed: onBack, child: Text(context.l10n.settingsAccountsTitle))]);
      },
      data: (state) {
        final vm = ref.read(provider.notifier);
        return AccountDetailsView(state: state, usage: usage,
          onBack: onBack, onEdit: onEdit, onRemoveModel: onRemoveModel,
          onLimit: vm.edit, onComposing: vm.setComposing, onCommit: vm.commit,
          onRestore: vm.restoreDefault, onRetry: vm.retryRead,
          errors: [
            if (state.source.projection.sync.error case final error?) settingsFailureText(error),
            if (state.modelSource.projection.sync.error case final error?) settingsFailureText(error),
            for (final error in state.readIssues.values) settingsFailureText(error),
          ],
          modelErrors: {
            for (final model in state.catalog.effectiveModels) model.modelId: [
              ...?modelErrors[model.modelId], ..._errors(state.drafts[model.modelId]?.action),
            ],
          });
      },
    );
  }

  List<String> _errors(SettingsAction? action) => [
    if (action?.error case final error?) settingsFailureText(error),
    if (action?.observationError case final error?) settingsFailureText(error),
    if (action?.operation?.evidenceError case final error?) settingsFailureText(error),
  ];
}
