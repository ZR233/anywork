import 'package:anywork_client/models.dart';
import 'package:flutter/material.dart';

import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../ui/formatters/token_format.dart';
import '../../../../ui/selectors/model_capability_card.dart';
import '../../state/settings_action.dart';
import '../../widgets/settings_form_field.dart';
import '../state/model_limits_state.dart';

/// A projection of Rust's descriptor. Eligibility and effective context values
/// are never recomputed here from capabilities, pricing or the raw override.
class AccountModelCard extends StatelessWidget {
  const AccountModelCard({required this.accountId, required this.model,
    required this.connectionMode, this.onConnection, this.limit,
    this.hasOverride = false, this.onLimit, this.onComposing,
    this.onCommit, this.onRestore, this.onDelete, this.errors = const [], super.key});

  final String accountId;
  final ModelDescriptor model;
  final String connectionMode;
  final ValueChanged<String>? onConnection;
  final ModelLimitDraft? limit;
  final bool hasOverride;
  final ValueChanged<String>? onLimit;
  final ValueChanged<bool>? onComposing;
  final VoidCallback? onCommit;
  final VoidCallback? onRestore;
  final VoidCallback? onDelete;
  final List<String> errors;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final pricing = model.pricing;
    final firstPrice = pricing?.tiers.firstOrNull;
    final draft = limit;
    return Card.outlined(margin: const EdgeInsets.only(bottom: 10), child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(model.displayName, style: Theme.of(context).textTheme.titleSmall),
              Chip(visualDensity: VisualDensity.compact, label: Text(switch (model.origin) {
                ModelOrigin.online => context.l10n.settingsModelOriginOnline,
                ModelOrigin.bundled => context.l10n.settingsModelOriginBundled,
                ModelOrigin.manual => context.l10n.settingsModelOriginManual,
              })),
            ]),
            SelectableText(model.modelId),
            Text('${context.modelWireApiLabel(model.transport.protocol)} · ${context.modelConnectionLabel(connectionMode)}'),
            Text('${context.l10n.settingsContextBudget}: ${formatTokenCount(model.contextWindow ?? model.maxContextWindow)}'),
            if (model.contextWindow == null && model.maxContextWindow == null)
              Text(context.l10n.settingsModelParametersUnknown),
            Wrap(key: StudioDriverKeys.modelCapabilityTags(accountId, model.modelId), spacing: 6, runSpacing: 4,
              children: [for (final item in model.capabilities.input) ModelCapabilityCard(modality: item.modality)]),
            if (model.capabilities.output.isNotEmpty)
              Text(context.l10n.settingsModelOutputCapabilities(model.capabilities.output.map(context.modalityLabel).join(' · '))),
            Text([
              if (model.capabilities.streaming) 'Streaming',
              if (model.capabilities.reasoning) 'Reasoning',
              if (model.capabilities.webSearch) 'Web search',
              if (model.capabilities.functionCalling) 'Tools',
              if (model.capabilities.parallelToolCalls) 'Parallel tools',
              if (model.capabilities.temperature) 'Temperature',
              if (model.capabilities.customTools) 'Custom tools',
              if (model.capabilities.freeformTools) 'Freeform tools',
              if (model.capabilities.instructionSnapshotOverrides) 'Instruction snapshot',
            ].join(' · ')),
          ])),
          if (onDelete != null) IconButton(
            key: StudioDriverKeys.accountManualModelDelete(accountId, model.modelId),
            tooltip: context.l10n.settingsRemoveManualModelConfirmTitle,
            onPressed: onDelete, icon: const Icon(Icons.delete_outline)),
          if (pricing != null && firstPrice != null)
            Tooltip(message: '${pricing.source}\n${pricing.tiers.map((tier) =>
              '${tier.label}\n${context.l10n.settingsPriceTierUnit(pricing.currency)} · '
              '${context.l10n.settingsPriceInput}: ${tier.inputPerMtok} · '
              '${context.l10n.settingsPriceOutput}: ${tier.outputPerMtok} · '
              '${context.l10n.settingsPriceCacheRead}: ${tier.cacheReadPerMtok ?? "—"} · '
              '${context.l10n.settingsPriceCacheWrite}: ${tier.cacheWritePerMtok ?? "—"}').join('\n\n')}',
              child: Text('${pricing.currency} ${_price(firstPrice.inputPerMtok)}/${_price(firstPrice.outputPerMtok)}${pricing.tiers.length > 1 ? ' · …' : ''}'))
          else Text(context.l10n.settingsModelPriceUnknown),
        ]),
        if (model.transport.connectionModes.length > 1) ...[
          const Divider(),
          Align(alignment: Alignment.centerLeft, child: SegmentedButton<String>(
            key: StudioDriverKeys.accountModelConnectionMode(accountId, model.modelId),
            segments: [for (final mode in model.transport.connectionModes)
              ButtonSegment(value: mode.id, label: KeyedSubtree(
                key: StudioDriverKeys.accountModelConnectionModeOption(accountId, model.modelId, mode.id),
                child: Text(context.modelConnectionLabel(mode.id))))],
            selected: {connectionMode}, showSelectedIcon: false,
            onSelectionChanged: onConnection == null ? null : (values) => onConnection!(values.single),
          )),
        ],
        if (draft != null) ...[
          const Divider(),
          Row(children: [
            Expanded(child: Text(context.l10n.settingsModelAutoCompactTitle)),
            TextButton.icon(key: StudioDriverKeys.accountModelAutoCompactReset(accountId, model.modelId),
              icon: const Icon(Icons.restart_alt), onPressed: onRestore,
              label: Text(context.l10n.settingsModelAutoCompactRestore)),
          ]),
          Text('${context.l10n.settingsModelAutoCompactOverrideLabel}: ${hasOverride
            ? context.l10n.settingsModelAutoCompactCustom : context.l10n.settingsModelAutoCompactUsingDefault} · '
            '${context.l10n.settingsModelAutoCompactEffectiveLabel}: ${formatTokenCount(model.context.autoCompactLimit)}'),
          const SizedBox(height: 10),
          SettingsFormField(key: StudioDriverKeys.accountModelAutoCompactInput(accountId, model.modelId),
            value: draft.raw, label: context.l10n.settingsModelAutoCompactInputLabel,
            hint: context.l10n.settingsModelAutoCompactUsingDefault,
            error: draft.validation == null ? null : context.l10n.settingsModelAutoCompactInvalid,
            enabled: onLimit != null, onChanged: (raw) => onLimit?.call(raw),
            onComposing: onComposing, onCommit: onCommit),
          const SizedBox(height: 6),
          Text(switch (model.context.unavailable) {
            ModelContextUnavailable.windowUnknown => context.l10n.settingsModelAutoCompactUnknownCapacity,
            ModelContextUnavailable.invalidParameters => context.l10n.modelContextParametersInvalid,
            ModelContextUnavailable.inputBudgetExhausted => context.l10n.modelInputBudgetExhausted,
            null => model.context.adjustment == null ? context.l10n.settingsModelAutoCompactHelp
              : context.l10n.settingsModelAutoCompactAdjusted,
          }, style: Theme.of(context).textTheme.bodySmall),
          if (draft.action?.pending ?? false) Text(context.l10n.settingsModelAutoCompactSaving),
          if (draft.action?.outcome == SettingsActionOutcome.rejected)
            Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: onCommit,
              icon: const Icon(Icons.refresh), label: Text(context.l10n.settingsModelAutoCompactRetry))),
        ],
        for (final error in errors) SelectableText(error, style: TextStyle(color: colors.error)),
      ]),
    ));
  }
}

String _price(double value) => value.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
