import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../state/account_presentations.dart';
import '../state/account_view_key_values.dart';
import 'account_sections.dart';

/// Narrow model intents shared by detail and editor views. Never a reducer.
@immutable
class AccountModelActions {
  const AccountModelActions({
    required this.onEnabledChanged,
    required this.onConnectionChanged,
    required this.onCompactChanged,
    required this.onAction,
  });
  final void Function(AccountModelKey key, bool enabled) onEnabledChanged;
  final void Function(AccountModelKey key, AccountConnection connection)
  onConnectionChanged;
  final void Function(AccountModelKey key, String raw) onCompactChanged;
  final void Function(AccountModelKey key, AccountModelAction action) onAction;
}

class AccountModelsView extends StatelessWidget {
  const AccountModelsView({
    required this.value,
    required this.actions,
    required this.onSync,
    super.key,
  });
  final AccountCatalogPresentation value;
  final AccountModelActions actions;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              l10n.settingsAccountModelsTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (value.canSync || value.canRetry)
              OutlinedButton.icon(
                key: const ValueKey<String>('account-model-sync'),
                onPressed: value.syncing ? null : onSync,
                icon: const Icon(Icons.sync),
                label: Text(
                  value.syncing
                      ? l10n.accountsSyncingModels
                      : value.error != null
                      ? l10n.accountsRetry
                      : l10n.accountsSyncModels,
                ),
              ),
          ],
        ),
        if (!value.canSync && !value.canRetry && !value.syncing)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(l10n.accountsSyncUnsupported),
          ),
        if (value.syncing) const LinearProgressIndicator(minHeight: 2),
        if (value.sourceLabel != null || value.checkedLabel != null)
          AccountFacts(
            facts: [
              if (value.sourceLabel != null)
                AccountDisplayFact(
                  label: l10n.accountsSource,
                  value: value.sourceLabel!,
                ),
              if (value.checkedLabel != null)
                AccountDisplayFact(
                  label: l10n.settingsModelCatalogChecked,
                  value: value.checkedLabel!,
                ),
            ],
          ),
        if (value.error != null)
          AccountInlineError(
            message: value.error!,
            onRetry: value.canRetry && !value.syncing ? onSync : null,
          ),
        if (value.models.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(l10n.settingsModelCatalogEmpty),
          ),
        for (final origin in AccountModelOrigin.values)
          if (value.models.any((model) => model.origin == origin)) ...[
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 8),
              child: Text(switch (origin) {
                AccountModelOrigin.online =>
                  l10n.settingsAccountOnlineModelsTitle,
                AccountModelOrigin.bundled => l10n.settingsModelCatalogDefault,
                AccountModelOrigin.manual =>
                  l10n.settingsAccountCustomModelsTitle,
              }, style: Theme.of(context).textTheme.labelLarge),
            ),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final model in value.models.where(
                    (model) => model.origin == origin,
                  ))
                    AccountModelTile(
                      key: ValueKey<String>(
                        AccountViewKeyValues.modelItem(
                          model.key.account.kind.name,
                          model.key.account.id,
                          model.key.modelId,
                        ),
                      ),
                      value: model,
                      actions: actions,
                    ),
                ],
              ),
            ),
          ],
      ],
    );
  }
}

class AccountModelTile extends StatelessWidget {
  const AccountModelTile({
    required this.value,
    required this.actions,
    this.initiallyExpanded = false,
    super.key,
  });
  final AccountModelPresentation value;
  final AccountModelActions actions;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ExpansionTile(
      key: PageStorageKey<String>(
        AccountViewKeyValues.modelDetails(
          value.key.account.kind.name,
          value.key.account.id,
          value.key.modelId,
        ),
      ),
      initiallyExpanded: initiallyExpanded,
      maintainState: true,
      controlAffinity: ListTileControlAffinity.leading,
      tilePadding: const EdgeInsetsDirectional.only(start: 12, end: 16),
      childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      title: Text(value.name, style: Theme.of(context).textTheme.titleSmall),
      subtitle: value.summary == null ? null : Text(value.summary!),
      // Exactly one fixed trailing slot on every model, with no extra chevron.
      trailing: SizedBox(
        width: 60,
        height: 48,
        child: Center(
          child: Switch(
            key: ValueKey<String>(
              AccountViewKeyValues.modelEnabled(
                value.key.account.kind.name,
                value.key.account.id,
                value.key.modelId,
              ),
            ),
            value: value.enabled,
            onChanged: value.canToggle && !value.saving
                ? (enabled) => actions.onEnabledChanged(value.key, enabled)
                : null,
          ),
        ),
      ),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Divider(),
            if (value.saving) const LinearProgressIndicator(minHeight: 2),
            if (value.error != null) AccountInlineError(message: value.error!),
            AccountFacts(facts: value.capabilities),
            AccountFacts(
              facts: [
                AccountDisplayFact(
                  label: l10n.accountsSource,
                  value: switch (value.origin) {
                    AccountModelOrigin.online => l10n.settingsModelOriginOnline,
                    AccountModelOrigin.bundled =>
                      l10n.settingsModelOriginBundled,
                    AccountModelOrigin.manual => l10n.settingsModelOriginManual,
                  },
                ),
              ],
            ),
            if (value.priceTiers.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                l10n.accountsPriceTiers,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              AccountFacts(facts: value.priceTiers),
            ],
            if (value.connection != null) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(l10n.accountsConnection),
                  if (value.allowedConnections.isEmpty)
                    Text(accountConnectionLabel(l10n, value.connection!)),
                  for (final connection in value.allowedConnections)
                    ChoiceChip(
                      label: Text(accountConnectionLabel(l10n, connection)),
                      selected: value.connection == connection,
                      onSelected: value.saving
                          ? null
                          : (_) => actions.onConnectionChanged(
                              value.key,
                              connection,
                            ),
                    ),
                ],
              ),
            ],
            if (value.compact != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: AccountCompactView(
                  value: value.compact!,
                  onChanged: (raw) => actions.onCompactChanged(value.key, raw),
                  onReset: () => actions.onAction(
                    value.key,
                    AccountModelAction.resetCompact,
                  ),
                  onRetry: () => actions.onAction(
                    value.key,
                    AccountModelAction.retryCompact,
                  ),
                ),
              ),
            if (value.canLoadReadout)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: value.readoutLoading
                      ? null
                      : () => actions.onAction(
                          value.key,
                          AccountModelAction.loadReadout,
                        ),
                  icon: const Icon(Icons.analytics_outlined),
                  label: Text(l10n.accountsReadout),
                ),
              ),
            if (value.readoutLoading)
              const LinearProgressIndicator(minHeight: 2),
            if (value.readoutError != null)
              AccountInlineError(
                message: value.readoutError!,
                onRetry: value.canLoadReadout
                    ? () => actions.onAction(
                        value.key,
                        AccountModelAction.retryReadout,
                      )
                    : null,
              ),
            if (value.performance.isNotEmpty) ...[
              Text(
                l10n.accountsPerformance,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              AccountFacts(facts: value.performance),
            ],
            if (value.evaluations.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                l10n.accountsEvaluations,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              for (final evaluation in value.evaluations.take(10))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${evaluation.title} · ${evaluation.outcome}',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      Text(
                        evaluation.updatedLabel,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      AccountFacts(facts: evaluation.scores),
                      AccountSelectableText(evaluation.comment),
                    ],
                  ),
                ),
            ],
            Wrap(
              spacing: 8,
              children: [
                if (value.canEdit)
                  TextButton.icon(
                    onPressed: () =>
                        actions.onAction(value.key, AccountModelAction.edit),
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(l10n.settingsEdit),
                  ),
                if (value.origin == AccountModelOrigin.manual &&
                    value.canDelete)
                  TextButton.icon(
                    onPressed: () =>
                        actions.onAction(value.key, AccountModelAction.delete),
                    icon: const Icon(Icons.delete_outline),
                    label: Text(l10n.settingsRemoveModel),
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class AccountCompactView extends StatelessWidget {
  const AccountCompactView({
    required this.value,
    required this.onChanged,
    required this.onReset,
    required this.onRetry,
    super.key,
  });
  final AccountCompactPresentation value;
  final ValueChanged<String> onChanged;
  final VoidCallback onReset;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              l10n.settingsModelAutoCompactTitle,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (value.canReset)
              TextButton.icon(
                onPressed: value.saving ? null : onReset,
                icon: const Icon(Icons.restart_alt),
                label: Text(l10n.settingsModelAutoCompactRestore),
              ),
          ],
        ),
        Text(
          value.overridden ? l10n.accountsOverride : l10n.accountsAutomatic,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        AccountRawTextField(
          value: AccountTextPresentation(raw: value.raw, error: value.error),
          label: l10n.settingsModelAutoCompactInputLabel,
          onChanged: onChanged,
          enabled: value.canEdit,
          keyboardType: TextInputType.number,
        ),
        // No parsing, rounding or filtering: exact raw intent goes to the VM.
        AccountFacts(
          facts: [
            if (value.effective != null && value.effective != value.raw)
              AccountDisplayFact(
                label: l10n.settingsModelAutoCompactEffectiveLabel,
                value: value.effective!,
              ),
            if (value.automatic != null &&
                value.automatic != value.effective &&
                value.automatic != value.raw)
              AccountDisplayFact(
                label: l10n.accountsAutomatic,
                value: value.automatic!,
              ),
          ],
        ),
        Text(
          l10n.settingsModelAutoCompactHelp,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (value.saving) Text(l10n.settingsModelAutoCompactSaving),
        if (value.canRetry)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: onRetry,
              child: Text(l10n.settingsModelAutoCompactRetry),
            ),
          ),
      ],
    );
  }
}
