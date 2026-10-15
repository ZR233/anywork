import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../presentation/providers/client_provider.dart';

import 'package:anywork_client/studio_client.dart';

import '../../l10n/studio_l10n.dart';
import '../../shared/model_route_selector.dart';
import '../../shared/studio_driver_keys.dart';
import 'settings_common.dart';
import 'settings_views.dart';

/// Observes Client facts and dispatches role intents for one stable role.
class AgentRouteConnector extends ConsumerWidget {
  const AgentRouteConnector({super.key, required this.role});

  final String role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsAgentsViewProvider);
    final providers = settings.providers;
    final route = ModelRouteQueries.roleRoute(
      providers: providers,
      roles: settings.roles,
      role: role,
    );
    final options = buildModelSelectionOptions(
      providers,
      modelsForProvider: (provider) =>
          provider.models.where((model) => model.slug.isNotEmpty).toList(),
    );
    final pending = ref.watch(
      settingsRoleCommandPendingProvider(role).select((state) => state.pending),
    );
    final unresolvedLabel = route.unavailable
        ? context.l10n.settingsAgentRouteUnavailable(
            [
              route.providerId,
              route.model,
            ].where((part) => part.isNotEmpty).join(' / '),
          )
        : route.descriptor == null
        ? context.l10n.settingsDefaultModel
        : null;
    final commands = ref.read(anyworkClientProvider).settingsCommands;

    Future<void> report(Future<void> Function() action) async {
      try {
        await action();
      } catch (error) {
        if (!context.mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }

    return AgentRouteView(
      role: role,
      selectedProviderId: route.providerId,
      selectedModel: route.model,
      selectedEffort: route.effort,
      options: options,
      efforts: route.descriptor?.reasoningEfforts ?? const [],
      unresolvedLabel: unresolvedLabel,
      showUnresolvedOption: route.unavailable,
      pending: pending,
      onModelChanged: (option) {
        if (option.providerId == route.providerId &&
            option.model == route.model) {
          return Future<void>.value();
        }
        return report(
          () => commands.setRoleModelField(
            roleKey: role,
            providerId: option.providerId,
            model: option.model,
          ),
        );
      },
      onEffortChanged: (effort) => report(
        () =>
            commands.setRoleReasoningEffortField(roleKey: role, effort: effort),
      ),
    );
  }
}

/// Renders the supplied role route; it neither observes nor resolves defaults.
class AgentRouteView extends StatelessWidget {
  const AgentRouteView({
    super.key,
    required this.role,
    required this.selectedProviderId,
    required this.selectedModel,
    required this.selectedEffort,
    required this.options,
    required this.efforts,
    required this.unresolvedLabel,
    required this.showUnresolvedOption,
    this.pending = false,
    required this.onModelChanged,
    required this.onEffortChanged,
  });

  final String role;
  final String selectedProviderId;
  final String selectedModel;
  final String? selectedEffort;
  final List<ModelSelectionOption> options;
  final List<String> efforts;
  final String? unresolvedLabel;
  final bool showUnresolvedOption;
  final bool pending;
  final FutureOr<void> Function(ModelSelectionOption option) onModelChanged;
  final FutureOr<void> Function(String effort) onEffortChanged;

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
            selectorKey: StudioDriverKeys.settingsRoleModel(role),
            fieldLabel: context.l10n.settingsModelField,
            options: options,
            providerId: selectedProviderId,
            model: selectedModel,
            unresolvedLabel: unresolvedLabel,
            showUnresolvedOption: showUnresolvedOption,
            enabled: options.isNotEmpty,
            onSelected: onModelChanged,
            optionKeyBuilder: (option) =>
                StudioDriverKeys.settingsRoleModelOption(
                  role,
                  option.providerId,
                  option.model,
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
    final effortUnresolvedLabel =
        selectedEffort != null && !efforts.contains(selectedEffort)
        ? context.l10n.settingsAgentRouteUnavailable(selectedEffort!)
        : selectedEffort == null && efforts.isNotEmpty
        ? context.l10n.statusModelRouteUnavailable
        : null;
    final effortSelector = DropdownMenu<String>(
      key: StudioDriverKeys.settingsRoleEffort(role),
      initialSelection: selectedEffort,
      label: Text(context.l10n.statusReasoningEffort),
      hintText: effortUnresolvedLabel,
      expandedInsets: EdgeInsets.zero,
      enabled: efforts.isNotEmpty,
      dropdownMenuEntries: [
        for (final effort in efforts)
          DropdownMenuEntry<String>(
            value: effort,
            label: effort,
            labelWidget: KeyedSubtree(
              key: StudioDriverKeys.settingsRoleEffortOption(role, effort),
              child: Text(effort, overflow: TextOverflow.ellipsis),
            ),
          ),
      ],
      onSelected: (effort) {
        if (effort != null) {
          final result = onEffortChanged(effort);
          if (result is Future<void>) unawaited(result);
        }
      },
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 760) {
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
              SizedBox(width: 140, child: effortSelector),
            ],
          );
        },
      ),
    );
  }
}
