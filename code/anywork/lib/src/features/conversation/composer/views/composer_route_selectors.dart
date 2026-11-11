import 'package:anywork_client/model_directory.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../shared/studio_menu_label.dart';
import '../../../status/session_selectors.dart';

List<Widget> modelRouteSelectorChildren({
  required List<ModelSelectionAccount> accounts,
  required bool pending,
  bool enabled = true,
  required String unavailableReason,
  String? accountId,
  String? modelId,
  String? effort,
  bool available = true,
  String? routeUnavailableReason,
  String? blockedReason,
  ValueChanged<String>? onExplain,
  ModelSelectionChanged? onModelSelected,
  EffortSelectionChanged? onEffortSelected,
}) {
  final hasRoute =
      accountId != null &&
      modelId != null &&
      accountId.isNotEmpty &&
      modelId.isNotEmpty;
  if (!hasRoute) {
    return [
      RouteUnavailableNotice(reason: unavailableReason),
      ModelRoleSelector(
        accounts: accounts,
        accountId: accountId ?? '',
        modelId: modelId ?? '',
        effort: effort,
        enabled: enabled,
        pending: pending,
        available: false,
        unavailableReason: unavailableReason,
        blockedReason: blockedReason,
        onExplain: onExplain,
        onModelSelected: onModelSelected,
      ),
      UnavailableEffortSelector(reason: unavailableReason),
    ];
  }
  return [
    ModelRoleSelector(
      accounts: accounts,
      accountId: accountId,
      modelId: modelId,
      effort: effort,
      enabled: enabled,
      pending: pending,
      available: available,
      unavailableReason: routeUnavailableReason,
      blockedReason: blockedReason,
      onExplain: onExplain,
      onModelSelected: onModelSelected,
    ),
    ReasoningEffortSelector(
      accounts: accounts,
      accountId: accountId,
      modelId: modelId,
      effort: effort,
      enabled: enabled,
      pending: pending,
      blockedReason: blockedReason,
      onExplain: onExplain,
      onEffortSelected: onEffortSelected,
    ),
  ];
}

class RouteUnavailableNotice extends StatelessWidget {
  const RouteUnavailableNotice({required this.reason, super.key});

  final String reason;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.warning_amber_outlined, size: 15, color: colors.error),
        const SizedBox(width: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Text(
            reason,
            key: const ValueKey('model-route-unavailable'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: colors.error),
          ),
        ),
      ],
    );
  }
}

class UnavailableEffortSelector extends StatelessWidget {
  const UnavailableEffortSelector({required this.reason, super.key});

  final String reason;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: reason,
      child: StudioMenuLabel(
        key: const ValueKey('effort-route-unavailable'),
        label: reason,
        enabled: false,
        maxWidth: 160,
      ),
    );
  }
}
