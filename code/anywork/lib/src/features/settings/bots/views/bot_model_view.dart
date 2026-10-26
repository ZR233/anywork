import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../ui/selectors/effort_selector.dart';
import '../../../../ui/selectors/model_route_selector.dart';
import '../../widgets/settings_field_label.dart';
import '../../widgets/settings_layout.dart';

/// Model route and reasoning effort of one bot.
///
/// The route belongs to the bot and applies to all of its chats; the selector
/// only renders the supplied options and reports the chosen identity. A model
/// change carries the effort the new model still supports, never a silently
/// substituted one.
class BotModelView extends StatelessWidget {
  const BotModelView({
    required this.role,
    required this.accountId,
    required this.modelId,
    required this.effort,
    required this.options,
    required this.efforts,
    required this.unresolvedLabel,
    required this.pending,
    required this.onModel,
    required this.onEffort,
    super.key,
  });

  /// Stable driver identity of this bot's route controls.
  final String role;
  final String accountId;
  final String modelId;
  final String? effort;
  final List<ModelSelectionOption> options;
  final List<String> efforts;
  final String? unresolvedLabel;
  final bool pending;
  final FutureOr<void> Function(ModelSelectionOption option) onModel;
  final ValueChanged<String?> onEffort;

  @override
  Widget build(BuildContext context) {
    final modelSelector = Row(
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: SettingsFieldLabel(label: context.l10n.settingsModelField),
        ),
        Flexible(
          child: ModelRouteSelector(
            // DropdownMenu owns transient selection text. Recreate it after a
            // save settles so failed writes also display the canonical route.
            key: ValueKey(('bot-model', role, accountId, modelId, pending)),
            selectorKey: StudioDriverKeys.settingsRoleModel(role),
            fieldLabel: context.l10n.settingsModelField,
            options: options,
            accountId: accountId,
            modelId: modelId,
            unresolvedLabel: unresolvedLabel,
            enabled: options.isNotEmpty && !pending,
            onSelected: onModel,
            optionKeyBuilder: (option) =>
                StudioDriverKeys.settingsRoleModelOption(
                  role,
                  option.accountId,
                  option.modelId,
                ),
          ),
        ),
        if (pending)
          const Padding(
            padding: EdgeInsets.only(left: 8),
            child: SizedBox.square(
              dimension: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
          ),
      ],
    );
    final effortSelector = EffortSelector(
      key: StudioDriverKeys.settingsRoleEffort(role),
      efforts: efforts,
      selected: effort,
      allowDefault: true,
      enabled: !pending,
      pending: pending,
      onSelected: onEffort,
    );
    return SettingsSectionPanel(
      title: context.l10n.botsModelTitle,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final textScaler = MediaQuery.textScalerOf(context);
              if (constraints.maxWidth < textScaler.scale(760)) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    modelSelector,
                    const SizedBox(height: 10),
                    effortSelector,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: modelSelector),
                  const SizedBox(width: 12),
                  SizedBox(width: textScaler.scale(140), child: effortSelector),
                ],
              );
            },
          ),
        ),
        Text(
          context.l10n.botsModelHint,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
