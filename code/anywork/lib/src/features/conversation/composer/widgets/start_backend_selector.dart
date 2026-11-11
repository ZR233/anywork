import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/routing/app_route.dart';
import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/account_brand.dart';
import '../../../../shared/studio_chrome.dart';
import '../../../../shared/studio_menu_label.dart';
import '../state/start_backend_view_state.dart';
import '../view_models/start_backend_view_model.dart';

/// Start-page runtime/backend selector positioned consistently in the top-right
/// environment bar across both Native and ACP modes.
class StartBackendSelector extends ConsumerWidget {
  const StartBackendSelector({required this.workspaceId, super.key});

  final String? workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = startBackendViewModelProvider(workspaceId);
    final state = ref.watch(provider);
    final notifier = ref.read(provider.notifier);
    return StartBackendSelectorView(
      state: state,
      onSelect: notifier.select,
      onManageServices: () => const SettingsRoute().go(context),
    );
  }
}

class StartBackendSelectorView extends StatelessWidget {
  const StartBackendSelectorView({
    super.key,
    required this.state,
    required this.onSelect,
    required this.onManageServices,
  });

  final StartBackendViewState state;
  final ValueChanged<String?> onSelect;
  final VoidCallback onManageServices;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;
    final selectedService = state.selectedService;
    final isNative = state.accountId == null;
    final label = isNative
        ? l10n.acpBackendNativeLabel
        : selectedService?.name ?? state.accountId!;
    final menuWidth = (MediaQuery.sizeOf(context).width - 40)
        .clamp(220.0, 340.0)
        .toDouble();

    return MenuAnchor(
      crossAxisUnconstrained: false,
      style: MenuStyle(
        maximumSize: WidgetStatePropertyAll(
          Size(
            menuWidth,
            (MediaQuery.sizeOf(context).height - 64).clamp(200.0, 520.0),
          ),
        ),
      ),
      builder: (context, controller, child) => Tooltip(
        message: label,
        child: TextButton(
          onPressed: state.enabled
              ? () => controller.isOpen ? controller.close() : controller.open()
              : null,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(StudioRadii.sm),
            ),
          ),
          child: StudioMenuLabel(
            leading: isNative
                ? Icon(
                    Icons.auto_awesome_outlined,
                    size: 16,
                    color: state.enabled ? colors.primary : colors.outline,
                  )
                : AccountBrandMark(
                    fallbackName: label,
                    iconKey: selectedService?.brandKey,
                    size: 18,
                    active: state.enabled,
                  ),
            label: label,
            enabled: state.enabled,
            maxWidth: 180,
          ),
        ),
      ),
      menuChildren: [
        MenuItemButton(
          leadingIcon: Icon(
            isNative ? Icons.check_rounded : Icons.auto_awesome_outlined,
            size: 18,
          ),
          onPressed: () => onSelect(null),
          child: SizedBox(
            width: menuWidth - 68,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.acpBackendNativeLabel,
                  style: context.text.bodyMedium?.copyWith(
                    fontWeight: isNative ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
                Text(
                  l10n.acpBackendNativeHint,
                  style: context.text.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 8),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: Text(
            l10n.acpBackendServicesHeader,
            style: context.text.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (state.loading)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: LinearProgressIndicator(),
          ),
        if (state.failure case final failure?)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: SizedBox(
              width: menuWidth - 24,
              child: StudioNotice(
                icon: Icons.error_outline_rounded,
                message: failure,
                tone: StudioNoticeTone.danger,
              ),
            ),
          ),
        for (final service in state.services)
          MenuItemButton(
            leadingIcon: AccountBrandMark(
              fallbackName: service.name,
              iconKey: service.brandKey,
              size: 20,
              active: service.enabled,
            ),
            trailingIcon: state.accountId == service.id
                ? Icon(Icons.check_rounded, size: 18, color: colors.primary)
                : StudioPill(
                    label: service.enabled
                        ? l10n.acpBackendReadyBadge
                        : l10n.acpConversationServiceDisabled,
                    tone: service.enabled
                        ? StudioTone.success
                        : StudioTone.neutral,
                  ),
            onPressed: service.enabled ? () => onSelect(service.id) : null,
            child: SizedBox(
              width: menuWidth - 136,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    service.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodyMedium?.copyWith(
                      fontWeight: state.accountId == service.id
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                  ),
                  Text(
                    service.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontFamily: studioCodeFontFamily,
                    ),
                  ),
                ],
              ),
            ),
          ),
        for (final diagnostic in state.diagnostics)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: SizedBox(
              width: menuWidth - 24,
              child: StudioNotice(
                icon: Icons.warning_amber_rounded,
                title: diagnostic.fileName,
                message: diagnostic.message,
                tone: StudioNoticeTone.warning,
              ),
            ),
          ),
        if (!state.loading && state.services.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              l10n.acpConversationNoServices,
              style: context.text.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        const Divider(height: 8),
        MenuItemButton(
          leadingIcon: const Icon(Icons.settings_outlined, size: 18),
          onPressed: onManageServices,
          child: Text(l10n.acpConversationManageServices),
        ),
      ],
    );
  }
}
