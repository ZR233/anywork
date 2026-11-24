import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/account_brand.dart';
import '../../../../shared/model_route_selector.dart';
import '../../../../shared/studio_driver_keys.dart';
import '../../../status/session_selectors.dart' show modelOptions;
import '../state/start_backend_view_state.dart';

class StartModelSelectorView extends StatelessWidget {
  const StartModelSelectorView({
    required this.state,
    required this.onSelectModel,
    required this.onSelectService,
    required this.onManageServices,
    this.inMenu = false,
    super.key,
  });

  final StartBackendViewState state;
  final void Function(String accountId, String modelId) onSelectModel;
  final ValueChanged<String?> onSelectService;
  final VoidCallback onManageServices;
  final bool inMenu;

  double measureInlineWidth(BuildContext context) =>
      _selector(context).measureInlineWidth(context);

  @override
  Widget build(BuildContext context) => _selector(context);

  ModelRouteSelector _selector(BuildContext context) {
    final l10n = context.l10n;
    final service = state.selectedService;
    final isAcp = state.accountId != null;
    final options = modelOptions(state.modelAccounts);
    final accountId = isAcp ? '' : state.modelAccountId ?? '';
    final modelId = isAcp ? '' : state.modelId ?? '';
    final available = isAcp
        ? service?.enabled == true
        : options.any(
            (option) =>
                option.accountId == accountId && option.modelId == modelId,
          );
    final fallbackLabel = isAcp
        ? service?.name ?? state.accountId!
        : state.modelId ?? l10n.statusPlannerModel;
    return ModelRouteSelector(
      options: options,
      accountId: accountId,
      modelId: modelId,
      enabled: state.enabled,
      onSelected: state.nativeEnabled
          ? (option) => onSelectModel(option.accountId, option.modelId)
          : null,
      fieldLabel: l10n.statusPlannerModel,
      selectorKey: StudioDriverKeys.model,
      showSelectedBrand: true,
      unresolvedLabel: fallbackLabel,
      unresolvedLeading: isAcp
          ? AccountBrandMark(
              fallbackName: fallbackLabel,
              iconKey: service?.brandKey,
              size: ModelRouteSelector.triggerIconSize,
              active: available,
            )
          : Icon(
              Icons.warning_amber_rounded,
              size: ModelRouteSelector.triggerIconSize,
              color: context.colors.error,
            ),
      tooltip: available
          ? l10n.statusPlannerModel
          : isAcp
          ? l10n.acpConversationServiceDisabled
          : l10n.statusModelRouteUnavailable,
      labelMaxWidth: isAcp ? 160 : 140,
      inMenu: inMenu,
      searchKey: const ValueKey('start-model-search'),
      menuFooter: _menuFooter,
    );
  }

  List<Widget> _menuFooter(
    BuildContext context,
    double width,
    String query,
    bool hasMatchingModels,
  ) {
    final l10n = context.l10n;
    final services = state.services
        .where(
          (service) =>
              service.name.toLowerCase().contains(query) ||
              service.id.toLowerCase().contains(query),
        )
        .toList();
    return [
      if (state.loading) const LinearProgressIndicator(),
      if (services.isNotEmpty) ...[
        if (hasMatchingModels) const Divider(height: 8),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Text(
            l10n.acpBackendServicesHeader,
            style: context.text.labelSmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ),
        for (final service in services)
          MenuItemButton(
            key: ValueKey(('start-acp-service', service.id)),
            overflowAxis: Axis.vertical,
            onPressed: state.enabled && service.enabled
                ? () => onSelectService(service.id)
                : null,
            leadingIcon: AccountBrandMark(
              fallbackName: service.name,
              iconKey: service.brandKey,
              size: 18,
              active: service.enabled,
            ),
            trailingIcon: service.enabled
                ? SizedBox.square(
                    dimension: 18,
                    child: state.accountId == service.id
                        ? const Icon(Icons.check_rounded, size: 18)
                        : null,
                  )
                : Tooltip(
                    message: l10n.acpConversationServiceDisabled,
                    child: const Icon(Icons.block_rounded, size: 16),
                  ),
            child: Text(
              service.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      if (!hasMatchingModels && services.isEmpty && !state.loading)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(l10n.composerModelSearchEmpty),
        ),
      if (state.failure case final failure?)
        SizedBox(
          width: width,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              failure,
              style: context.text.bodySmall?.copyWith(
                color: context.colors.error,
              ),
            ),
          ),
        ),
      for (final diagnostic in state.diagnostics)
        Tooltip(
          message: diagnostic.message,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(diagnostic.fileName),
          ),
        ),
      const Divider(height: 8),
      MenuItemButton(
        leadingIcon: const Icon(Icons.settings_outlined, size: 18),
        onPressed: onManageServices,
        child: Text(l10n.composerManageModels),
      ),
    ];
  }
}
