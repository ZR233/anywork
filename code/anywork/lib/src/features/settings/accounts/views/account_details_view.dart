import 'package:anywork_client/models.dart';
import 'package:flutter/material.dart';

import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../widgets/settings_source_status_view.dart';
import '../state/model_limits_state.dart';
import '../widgets/account_model_card.dart';

class AccountDetailsView extends StatelessWidget {
  const AccountDetailsView({required this.state, required this.errors, required this.modelErrors,
    required this.onBack, required this.onEdit, required this.onRemoveModel,
    required this.onLimit, required this.onComposing, required this.onCommit,
    required this.onRestore, required this.onRetry, this.usage, super.key});
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
  final Widget? usage;

  @override
  Widget build(BuildContext context) => ListView(key: StudioDriverKeys.accountEditor, children: [
    SettingsSourceStatusView(title: context.l10n.settingsAccountTitle, brief: state.source.projection.header?.source.brief,
      read: state.source.sourceStatus, origin: state.source.projection.stamp?.origin,
      reference: state.source.projection.header?.source.status, onRetry: onRetry),
    SettingsSourceStatusView(title: context.l10n.settingsAccountModelsTitle, brief: state.modelSource.projection.header?.source.brief,
      read: state.modelSource.sourceStatus, origin: state.modelSource.projection.stamp?.origin,
      reference: state.modelSource.projection.header?.source.status, onRetry: onRetry),
    Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: onBack,
      icon: const Icon(Icons.arrow_back), label: Text(context.l10n.settingsAccountsTitle))),
    ListTile(contentPadding: EdgeInsets.zero, title: Text(state.canonical.name),
      subtitle: Text(state.canonical.baseUrl), trailing: FilledButton.tonalIcon(
        key: StudioDriverKeys.accountEdit, onPressed: onEdit,
        icon: const Icon(Icons.edit_outlined), label: Text(context.l10n.settingsEdit))),
    if (usage != null) usage!,
    SelectableText('${context.l10n.settingsAccountId}: ${state.accountId}\n'
      '${context.l10n.settingsAccountTemplate}: ${state.canonical.templateId ?? context.l10n.settingsCustomAccount}\n'
      '${context.l10n.settingsApiKey}: ${state.canonical.hasBearerToken ? context.l10n.settingsConfigured : context.l10n.settingsMissing}'),
    if (state.catalog.modelCatalog.supported) ...[
      Text(switch (state.catalog.modelCatalog.source) {
        ModelCatalogSource.defaultSource => context.l10n.settingsModelCatalogDefault,
        ModelCatalogSource.cached => context.l10n.settingsModelCatalogCached,
        ModelCatalogSource.online => context.l10n.settingsModelCatalogOnline,
      }),
      if (state.catalog.modelCatalog.checkedAt case final checked?)
        Text('${context.l10n.settingsModelCatalogChecked}: ${DateTime.fromMillisecondsSinceEpoch(checked * 1000)}'),
      if (state.catalog.modelCatalog.error != null) Text(context.l10n.settingsModelCatalogFailed),
      if (state.catalog.modelCatalog.cacheWarning != null) Text(context.l10n.settingsModelCatalogCacheWarning),
      Text(context.l10n.settingsModelCatalogRestartHint),
    ],
    for (final error in errors) SelectableText(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
    if (errors.isNotEmpty) TextButton(onPressed: onRetry, child: Text(context.l10n.runtimeFatalRetry)),
    for (final origin in [ModelOrigin.online, ModelOrigin.bundled, ModelOrigin.manual]) ...[
      Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(switch (origin) {
        ModelOrigin.online => context.l10n.settingsAccountOnlineModelsTitle,
        ModelOrigin.bundled => context.l10n.settingsAccountDefaultModelsTitle,
        ModelOrigin.manual => context.l10n.settingsAccountCustomModelsTitle,
      })),
      for (final model in state.catalog.effectiveModels.where((model) => model.origin == origin))
        AccountModelCard(key: ValueKey((state.accountId, model.modelId)), accountId: state.accountId, model: model,
          connectionMode: state.canonical.modelConnectionModes.where((item) => item.modelId == model.modelId)
            .firstOrNull?.connectionMode ?? model.transport.defaultConnectionMode,
          hasOverride: state.canonical.modelAutoCompactLimits.any((item) => item.modelId == model.modelId && item.overrideLimit != null),
          limit: state.drafts[model.modelId] ?? ModelLimitDraft(raw: state.canonical.modelAutoCompactLimits
            .where((item) => item.modelId == model.modelId).firstOrNull?.overrideLimit?.toString() ?? '', intent: 0),
          onLimit: (raw) => onLimit(model.modelId, raw),
          onComposing: (value) => onComposing(model.modelId, value),
          onCommit: () => onCommit(model.modelId), onRestore: () => onRestore(model.modelId),
          onDelete: origin == ModelOrigin.manual ? () => onRemoveModel(model.modelId) : null,
          errors: modelErrors[model.modelId] ?? []),
    ],
  ]);
}
