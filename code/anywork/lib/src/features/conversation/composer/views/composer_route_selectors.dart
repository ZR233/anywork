import 'package:anywork_client/model_directory.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../shared/studio_menu_label.dart';
import '../../../../shared/composer_configuration_bar.dart';
import '../../../status/session_selectors.dart';

List<ComposerConfigurationEntry> modelRouteConfigurationEntries({
  required List<ModelSelectionAccount> accounts,
  required bool pending,
  required String unavailableReason,
  bool enabled = true,
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
      accountId.isNotEmpty &&
      modelId != null &&
      modelId.isNotEmpty;
  ModelRoleSelector model(bool inMenu) => ModelRoleSelector(
    accounts: accounts,
    accountId: accountId ?? '',
    modelId: modelId ?? '',
    effort: effort,
    enabled: enabled,
    inMenu: inMenu,
    pending: pending,
    available: hasRoute && available,
    unavailableReason: routeUnavailableReason ?? unavailableReason,
    blockedReason: blockedReason,
    onExplain: onExplain,
    onModelSelected: onModelSelected,
  );
  ReasoningEffortSelector reasoning(bool inMenu) => ReasoningEffortSelector(
    accounts: accounts,
    accountId: accountId ?? '',
    modelId: modelId ?? '',
    effort: effort,
    enabled: enabled,
    inMenu: inMenu,
    pending: pending,
    blockedReason: blockedReason,
    onExplain: onExplain,
    onEffortSelected: onEffortSelected,
  );
  final inlineModel = model(false);
  final ComposerConfigurationEntry effortEntry;
  if (hasRoute) {
    final inlineEffort = reasoning(false);
    effortEntry = ComposerConfigurationEntry(
      id: 'native-effort',
      inline: inlineEffort,
      measureInlineWidth: inlineEffort.measureInlineWidth,
      menuItem: reasoning(true),
    );
  } else {
    final inlineEffort = UnavailableEffortSelector(reason: unavailableReason);
    effortEntry = ComposerConfigurationEntry(
      id: 'native-effort',
      inline: inlineEffort,
      measureInlineWidth: inlineEffort.measureInlineWidth,
      menuItem: Tooltip(
        message: unavailableReason,
        child: MenuItemButton(
          key: const ValueKey('effort-route-unavailable'),
          child: Text(unavailableReason),
        ),
      ),
    );
  }
  return [
    ComposerConfigurationEntry(
      id: 'native-model',
      inline: inlineModel,
      measureInlineWidth: inlineModel.measureInlineWidth,
      menuItem: model(true),
    ),
    effortEntry,
  ];
}

class UnavailableEffortSelector extends StatelessWidget {
  const UnavailableEffortSelector({required this.reason, super.key});

  final String reason;

  StudioMenuLabel _inlineLabel() => StudioMenuLabel(
    key: const ValueKey('effort-route-unavailable'),
    label: reason,
    enabled: false,
    maxWidth: 160,
  );

  double measureInlineWidth(BuildContext context) =>
      _inlineLabel().measureWidth(context);

  @override
  Widget build(BuildContext context) {
    return Tooltip(message: reason, child: _inlineLabel());
  }
}
