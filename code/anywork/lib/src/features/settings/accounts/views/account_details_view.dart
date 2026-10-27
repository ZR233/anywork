import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../state/account_presentations.dart';
import '../state/account_view_key_values.dart';
import '../widgets/account_details_header.dart';
import '../widgets/account_models_view.dart';
import '../widgets/account_sections.dart';
import '../widgets/account_usage_view.dart';
import '../widgets/acp_account_panel.dart';

/// Full main-area details at every width; navigation/scroll ownership is external.
class AccountDetailsView extends StatelessWidget {
  const AccountDetailsView({
    required this.value,
    required this.onBack,
    required this.onEdit,
    required this.onDelete,
    required this.onSetDefault,
    required this.onRefreshUsage,
    required this.onBillingChanged,
    required this.onResetBilling,
    required this.onSyncModels,
    required this.modelActions,
    required this.onAcpAction,
    required this.onLoginMethodChanged,
    required this.onRetry,
    this.scrollController,
    super.key,
  });
  final AccountDetailsPresentation value;
  final VoidCallback onBack;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onSetDefault;
  final VoidCallback onRefreshUsage;
  final ValueChanged<AccountBilling> onBillingChanged;
  final VoidCallback onResetBilling;
  final VoidCallback onSyncModels;
  final AccountModelActions modelActions;
  final ValueChanged<AcpAccountAction> onAcpAction;
  final ValueChanged<String> onLoginMethodChanged;
  final VoidCallback onRetry;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      key: PageStorageKey<String>(
        AccountViewKeyValues.detailsScroll(value.key.kind.name, value.key.id),
      ),
      controller: scrollController,
      padding: const EdgeInsets.all(24),
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const ValueKey<String>('account-back'),
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
            label: Text(l10n.accountsBack),
          ),
        ),
        const SizedBox(height: 16),
        AccountDetailsHeader(
          value: value,
          onEdit: onEdit,
          onDelete: onDelete,
          onSetDefault: onSetDefault,
        ),
        const SizedBox(height: 24),
        if (value.loading) const LinearProgressIndicator(minHeight: 2),
        if (value.error != null)
          AccountInlineError(message: value.error!, onRetry: onRetry),
        switch (value.content) {
          NativeAccountDetailsContent(:final value) => _NativeDetails(
            value: value,
            onRefreshUsage: onRefreshUsage,
            onBillingChanged: onBillingChanged,
            onResetBilling: onResetBilling,
            onSyncModels: onSyncModels,
            modelActions: modelActions,
          ),
          AcpAccountDetailsContent(:final value) => AccountSection(
            title: l10n.accountsSettingsSection,
            child: AcpAccountPanel(
              value: value,
              onAction: onAcpAction,
              onLoginMethodChanged: onLoginMethodChanged,
            ),
          ),
        },
      ],
    );
  }
}

class _NativeDetails extends StatelessWidget {
  const _NativeDetails({
    required this.value,
    required this.onRefreshUsage,
    required this.onBillingChanged,
    required this.onResetBilling,
    required this.onSyncModels,
    required this.modelActions,
  });
  final NativeAccountDetailsPresentation value;
  final VoidCallback onRefreshUsage;
  final ValueChanged<AccountBilling> onBillingChanged;
  final VoidCallback onResetBilling;
  final VoidCallback onSyncModels;
  final AccountModelActions modelActions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Card(
            color: accountGroupSurface(context),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            l10n.accountsBalanceColumn,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          AccountBillingBadge(
                            billing: value.billing.effective,
                            health: value.usage.balanceHealth,
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (value.usage.updatedLabel != null)
                            Text(
                              l10n.settingsUsageUpdated(
                                value.usage.updatedLabel!,
                              ),
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontSize: 14),
                            ),
                          IconButton(
                            key: const ValueKey<String>('account-usage-check'),
                            tooltip: l10n.settingsRefreshUsage,
                            onPressed: value.usage.canRefresh
                                ? onRefreshUsage
                                : null,
                            icon: const Icon(Icons.refresh),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: accountGroupSurface(context),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: AccountUsageView(
                      value: value.usage,
                      onRetry: onRefreshUsage,
                      showUpdated: false,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AccountSection(
          title: l10n.accountsSettingsSection,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AccountFacts(
                facts: [
                  AccountDisplayFact(
                    label: l10n.settingsApiKey,
                    value: value.credentialReady
                        ? l10n.settingsConfigured
                        : l10n.settingsMissing,
                  ),
                ],
              ),
              const Divider(),
              AccountBillingControl(
                value: value.billing,
                onChanged: onBillingChanged,
                onReset: onResetBilling,
              ),
              if (value.advanced.isNotEmpty) const Divider(),
              if (value.advanced.isNotEmpty)
                ExpansionTile(
                  // The typed details-page ancestor key scopes this per account.
                  key: const PageStorageKey<String>(
                    'account-advanced-expanded',
                  ),
                  title: Text(
                    l10n.accountsAdvancedSection,
                    style: Theme.of(context).textTheme.bodyLarge
                        ?.copyWith(fontSize: 16),
                  ),
                  tilePadding: EdgeInsets.zero,
                  children: [AccountFacts(facts: value.advanced)],
                ),
            ],
          ),
        ),
        AccountModelsView(
          value: value.catalog,
          actions: modelActions,
          onSync: onSyncModels,
        ),
      ],
    );
  }
}
