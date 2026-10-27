import 'package:flutter/material.dart';

import '../../../../app/theme/studio_semantic_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../state/account_presentations.dart';
import '../state/account_view_key_values.dart';
import 'account_compact_view.dart';
import 'account_sections.dart';

export 'account_compact_view.dart';

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
            Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  l10n.settingsAccountModelsTitle,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (value.canSync || value.canRetry)
                  OutlinedButton.icon(
                    style: accountActionButtonStyle(context),
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
            if (value.sourceLabel != null || value.checkedLabel != null)
              Wrap(
                spacing: 16,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (value.sourceLabel != null)
                    Text(
                      '${l10n.accountsSource} · ${value.sourceLabel}',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(fontSize: 14),
                    ),
                  if (value.checkedLabel != null)
                    Text(
                      '${l10n.settingsModelCatalogChecked} ${value.checkedLabel}',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(fontSize: 14),
                    ),
                ],
              ),
          ],
        ),
        if (!value.canSync && !value.canRetry && !value.syncing)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              l10n.accountsSyncUnsupported,
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(fontSize: 16),
            ),
          ),
        if (value.syncing) const LinearProgressIndicator(minHeight: 2),
        if (value.error != null)
          AccountInlineError(
            message: value.error!,
            onRetry: value.canRetry && !value.syncing ? onSync : null,
          ),
        if (value.models.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              l10n.settingsModelCatalogEmpty,
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(fontSize: 16),
            ),
          ),
        for (final origin in AccountModelOrigin.values)
          if (value.models.any((model) => model.origin == origin)) ...[
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 8),
              child: Text(
                switch (origin) {
                  AccountModelOrigin.online =>
                    l10n.settingsAccountOnlineModelsTitle,
                  AccountModelOrigin.bundled =>
                    l10n.settingsModelCatalogDefault,
                  AccountModelOrigin.manual =>
                    l10n.settingsAccountCustomModelsTitle,
                },
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(fontSize: 16),
              ),
            ),
            Card(
              color: accountGroupSurface(context),
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
      title: Wrap(
        spacing: 12,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            value.name,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: value.origin == AccountModelOrigin.online
                  ? Theme.of(context)
                        .extension<StudioSemanticColors>()!
                        .successContainer
                  : Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              switch (value.origin) {
                AccountModelOrigin.online => l10n.settingsModelOriginOnline,
                AccountModelOrigin.bundled => l10n.settingsModelOriginBundled,
                AccountModelOrigin.manual => l10n.settingsModelOriginManual,
              },
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontSize: 16,
                color: value.origin == AccountModelOrigin.online
                    ? Theme.of(context)
                          .extension<StudioSemanticColors>()!
                          .success
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
      // Exactly one fixed trailing slot on every model, with no extra chevron.
      trailing: SizedBox(
        width: 60,
        height: 48,
        child: Center(
          child: Tooltip(
            message: l10n.settingsModelEnabledHint,
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
      ),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Divider(),
            Text(l10n.settingsModelEnabledHint),
            if (value.saving) const LinearProgressIndicator(minHeight: 2),
            if (value.error != null) AccountInlineError(message: value.error!),
            if (value.summary != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  value.summary!,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(fontSize: 14),
                ),
              ),
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
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(fontSize: 14),
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
