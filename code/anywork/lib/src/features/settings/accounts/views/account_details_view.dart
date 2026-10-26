import 'package:anywork_client/models.dart';
import 'package:flutter/material.dart';

import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../ui/badges/studio_badges.dart';
import '../../../../ui/branding/account_brand.dart';
import '../../../../app/theme/studio_tokens.dart';
import '../../widgets/settings_feedback.dart';
import '../../widgets/settings_layout.dart';
import '../../widgets/settings_readouts.dart';
import '../state/model_limits_state.dart';
import '../widgets/account_billing_control.dart';
import '../widgets/account_model_card.dart';
import '../widgets/account_model_selection_control.dart';

/// Account details column.
///
/// Mirrors the pre-refactor detail pane: back affordance, header with the brand
/// mark and edit action, the usage panel, identity pills, then the account and
/// model sections. Read failures surface as an inline notice instead of a
/// permanent status area.
class AccountDetailsView extends StatelessWidget {
  const AccountDetailsView({
    required this.state,
    required this.errors,
    required this.modelErrors,
    required this.onBack,
    required this.onEdit,
    required this.onRemoveModel,
    required this.onLimit,
    required this.onComposing,
    required this.onCommit,
    required this.onRestore,
    required this.onRetry,
    required this.onModelDetails,
    required this.enabledErrors,
    required this.billingErrors,
    this.iconKey,
    this.onModelEnabled,
    this.onBillingKind,
    this.usage,
    super.key,
  });
  final AccountModelLimitsViewState state;
  final List<String> errors;
  final Map<String, List<String>> modelErrors;
  final VoidCallback onBack;
  final VoidCallback onEdit;
  final ValueChanged<String> onRemoveModel;
  final void Function(String modelId, String raw) onLimit;
  final void Function(String modelId, bool value) onComposing;
  final ValueChanged<String> onCommit;
  final ValueChanged<String> onRestore;
  final VoidCallback onRetry;
  final ValueChanged<String> onModelDetails;
  final String? iconKey;
  final void Function(String modelId, bool enabled)? onModelEnabled;
  final ValueChanged<BillingKind?>? onBillingKind;
  final Map<String, List<String>> enabledErrors;
  final List<String> billingErrors;
  final Widget? usage;

  @override
  Widget build(BuildContext context) {
    final account = state.canonical;
    final models = state.catalog.effectiveModels;
    return ListView(
      key: StudioDriverKeys.accountEditor,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
            label: Text(context.l10n.settingsAccountsTitle),
          ),
        ),
        const SizedBox(height: 4),
        SettingsHeader(
          title: account.name,
          subtitle: account.baseUrl,
          leading: AccountBrandMark(
            iconKey: iconKey,
            fallbackName: account.name,
          ),
          trailing: FilledButton.tonalIcon(
            key: StudioDriverKeys.accountEdit,
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
            label: Text(context.l10n.settingsEdit),
          ),
        ),
        if (errors.isNotEmpty) ...[
          const SizedBox(height: 12),
          SettingsInlineError(message: errors.join('\n')),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onRetry,
              child: Text(context.l10n.runtimeFatalRetry),
            ),
          ),
        ],
        const SizedBox(height: 12),
        ?usage,
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            StudioPill(
              icon: account.hasBearerToken
                  ? Icons.key_outlined
                  : Icons.error_outline,
              label: account.hasBearerToken
                  ? context.l10n.settingsConfigured
                  : context.l10n.settingsMissing,
              tone: account.hasBearerToken
                  ? StudioTone.neutral
                  : StudioTone.warning,
            ),
            StudioCompactChip(
              icon: Icons.hub_outlined,
              maxWidth: 220,
              label: context.protocolKindLabel(account.protocol),
            ),
            StudioCompactChip(
              icon: Icons.memory_outlined,
              maxWidth: 220,
              label:
                  '${context.l10n.settingsAccountModelsTitle}: ${models.length}',
            ),
          ],
        ),
        const SizedBox(height: 16),
        SettingsSectionPanel(
          title: context.l10n.settingsAccountTitle,
          children: [
            SettingsReadout(
              label: context.l10n.settingsAccountId,
              value: account.accountId,
            ),
            SettingsReadout(
              label: context.l10n.settingsAccountTemplate,
              value: account.templateId == null || account.templateId!.isEmpty
                  ? context.l10n.settingsCustomAccount
                  : account.templateId!,
            ),
            SettingsReadout(
              label: context.l10n.settingsApiKey,
              value: account.hasBearerToken
                  ? context.l10n.settingsConfigured
                  : context.l10n.settingsMissing,
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Models section. The heading/12 gap and the 16 vertical rhythm are the
        // section-panel geometry, inlined here because the model cards must stay
        // direct rows of the page list: their established identity and ordering
        // are addressed by key. Every origin group therefore lives inside this
        // one section, exactly as before the refactor.
        const SizedBox(height: 16),
        Text(
          context.l10n.settingsAccountModelsTitle,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        AccountBillingControl(
          account: account,
          onChanged: onBillingKind,
          action: state.billingAction?.binding == state.binding
              ? state.billingAction
              : null,
          errors: billingErrors,
        ),
        if (state.catalog.modelCatalog.supported)
          _CatalogReadout(status: state.catalog.modelCatalog),
        if (models.isEmpty) Text(context.l10n.settingsModelCatalogEmpty),
        for (final origin in const [
          ModelOrigin.online,
          ModelOrigin.bundled,
          ModelOrigin.manual,
        ])
          ..._originRows(context, origin, models),
        const SizedBox(height: 16),
      ],
    );
  }

  List<Widget> _originRows(
    BuildContext context,
    ModelOrigin origin,
    List<ModelDescriptor> models,
  ) {
    if (models.isEmpty) return const [];
    final rows = models.where((model) => model.origin == origin).toList();
    final title = switch (origin) {
      ModelOrigin.online => context.l10n.settingsAccountOnlineModelsTitle,
      ModelOrigin.bundled => context.l10n.settingsAccountDefaultModelsTitle,
      ModelOrigin.manual => context.l10n.settingsAccountCustomModelsTitle,
    };
    final emptyLabel = switch (origin) {
      ModelOrigin.online => context.l10n.settingsNoOnlineModels,
      ModelOrigin.bundled => context.l10n.settingsNoBundledModels,
      ModelOrigin.manual => context.l10n.settingsNoCustomModels,
    };
    return [
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(title, style: Theme.of(context).textTheme.titleSmall),
      ),
      const SizedBox(height: 8),
      if (rows.isEmpty)
        Text(emptyLabel)
      else
        for (final model in rows)
          AccountModelCard(
            key: ValueKey((state.accountId, model.modelId)),
            accountId: state.accountId,
            model: model,
            selectionControl: AccountModelSelectionControl(
              accountId: state.accountId,
              model: model,
              action:
                  state.enabledActions[model.modelId]?.binding == state.binding
                  ? state.enabledActions[model.modelId]
                  : null,
              onEnabled: onModelEnabled == null
                  ? null
                  : (enabled) => onModelEnabled!(model.modelId, enabled),
              onDetails: () => onModelDetails(model.modelId),
              errors: enabledErrors[model.modelId] ?? [],
            ),
            connectionMode:
                state.canonical.modelConnectionModes
                    .where((item) => item.modelId == model.modelId)
                    .firstOrNull
                    ?.connectionMode ??
                model.transport.defaultConnectionMode,
            hasOverride: state.canonical.modelAutoCompactLimits.any(
              (item) =>
                  item.modelId == model.modelId && item.overrideLimit != null,
            ),
            limit:
                state.drafts[model.modelId] ??
                ModelLimitDraft(
                  raw:
                      state.canonical.modelAutoCompactLimits
                          .where((item) => item.modelId == model.modelId)
                          .firstOrNull
                          ?.overrideLimit
                          ?.toString() ??
                      '',
                  intent: 0,
                ),
            onLimit: (raw) => onLimit(model.modelId, raw),
            onComposing: (value) => onComposing(model.modelId, value),
            onCommit: () => onCommit(model.modelId),
            onRestore: () => onRestore(model.modelId),
            onDelete: origin == ModelOrigin.manual
                ? () => onRemoveModel(model.modelId)
                : null,
            errors: modelErrors[model.modelId] ?? [],
          ),
    ];
  }
}

/// Catalog status readouts in the pre-refactor order: active source first, then
/// the restart hint and the observation timestamps.
class _CatalogReadout extends StatelessWidget {
  const _CatalogReadout({required this.status});
  final ModelCatalogStatus status;

  @override
  Widget build(BuildContext context) {
    final checkedAt = status.checkedAt;
    final lastSuccessAt = status.lastSuccessAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(switch (status.source) {
          ModelCatalogSource.defaultSource =>
            context.l10n.settingsModelCatalogDefault,
          ModelCatalogSource.cached => context.l10n.settingsModelCatalogCached,
          ModelCatalogSource.online => context.l10n.settingsModelCatalogOnline,
        }),
        Text(context.l10n.settingsModelCatalogRestartHint),
        if (lastSuccessAt != null && lastSuccessAt != checkedAt)
          Text(_formatCatalogTime(lastSuccessAt)),
        if (checkedAt != null)
          Text(
            '${context.l10n.settingsModelCatalogChecked}: ${_formatCatalogTime(checkedAt)}',
          ),
        if (status.error != null)
          Text(
            context.l10n.settingsModelCatalogFailed,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (status.cacheWarning != null)
          Text(context.l10n.settingsModelCatalogCacheWarning),
      ],
    );
  }
}

String _formatCatalogTime(int unixSeconds) =>
    DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000)
        .toLocal()
        .toString();
