import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/account_brand.dart';
import '../../../../shared/studio_driver_keys.dart';
import '../../../../shared/studio_menu_label.dart';
import '../../../status/session_selectors.dart' show modelOptions;
import '../state/start_backend_view_state.dart';

class StartModelSelectorView extends StatefulWidget {
  const StartModelSelectorView({
    required this.state,
    required this.onSelectModel,
    required this.onSelectService,
    required this.onManageServices,
    super.key,
  });

  final StartBackendViewState state;
  final void Function(String accountId, String modelId) onSelectModel;
  final ValueChanged<String?> onSelectService;
  final VoidCallback onManageServices;

  @override
  State<StartModelSelectorView> createState() => _StartModelSelectorViewState();
}

class _StartModelSelectorViewState extends State<StartModelSelectorView> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(Iterable<String> values) {
    final query = _search.text.trim().toLowerCase();
    return query.isEmpty ||
        values.any((value) => value.toLowerCase().contains(query));
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final l10n = context.l10n;
    final options = modelOptions(state.modelAccounts);
    final current = options
        .where(
          (option) =>
              option.accountId == state.modelAccountId &&
              option.modelId == state.modelId,
        )
        .firstOrNull;
    final service = state.selectedService;
    final isAcp = state.accountId != null;
    final available = isAcp ? service?.enabled == true : current != null;
    final label = isAcp
        ? service?.name ?? state.accountId!
        : current?.displayName ?? state.modelId ?? l10n.statusPlannerModel;
    final width = (MediaQuery.sizeOf(context).width - 32).clamp(200.0, 380.0);
    final filtered = options
        .where(
          (option) => _matches([
            option.displayName,
            option.modelId,
            option.accountName,
          ]),
        )
        .toList();
    final services = state.services
        .where((item) => _matches([item.name, item.id]))
        .toList();

    return MenuAnchor(
      key: StudioDriverKeys.model,
      crossAxisUnconstrained: false,
      onOpen: () {
        _search.clear();
        setState(() {});
      },
      style: MenuStyle(
        maximumSize: WidgetStatePropertyAll(
          Size(
            width,
            (MediaQuery.sizeOf(context).height - 64).clamp(160.0, 520.0),
          ),
        ),
      ),
      builder: (context, controller, _) => Tooltip(
        message: !available
            ? isAcp
                  ? l10n.acpConversationServiceDisabled
                  : l10n.statusModelRouteUnavailable
            : l10n.statusPlannerModel,
        child: TextButton(
          onPressed: state.enabled
              ? () => controller.isOpen ? controller.close() : controller.open()
              : null,
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: StudioMenuLabel(
            leading: isAcp
                ? AccountBrandMark(
                    fallbackName: label,
                    iconKey: service?.brandKey,
                    size: 18,
                    active: available,
                  )
                : !available
                ? Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: context.colors.error,
                  )
                : null,
            label: label,
            maxWidth: 160,
            enabled: state.enabled,
          ),
        ),
      ),
      menuChildren: [
        SizedBox(
          width: width,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              key: const ValueKey('start-model-search'),
              controller: _search,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: l10n.composerModelSearch,
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
              ),
            ),
          ),
        ),
        if (state.loading) const LinearProgressIndicator(),
        for (final account in state.modelAccounts)
          if (filtered.any((option) => option.accountId == account.id)) ...[
            _heading(context, account.name),
            for (final option in filtered.where(
              (option) => option.accountId == account.id,
            ))
              MenuItemButton(
                key: StudioDriverKeys.modelOption(
                  option.accountId,
                  option.modelId,
                ),
                onPressed: state.enabled && state.nativeEnabled
                    ? () =>
                          widget.onSelectModel(option.accountId, option.modelId)
                    : null,
                leadingIcon: AccountBrandMark(
                  fallbackName: option.accountName,
                  iconKey: option.accountIconKey,
                  size: 18,
                ),
                trailingIcon: _selected(!isAcp && option == current),
                child: _label(option.displayName, width),
              ),
          ],
        if (services.isNotEmpty) ...[
          const Divider(height: 8),
          _heading(context, l10n.acpBackendServicesHeader),
          for (final item in services)
            MenuItemButton(
              key: ValueKey(('start-acp-service', item.id)),
              onPressed: state.enabled && item.enabled
                  ? () => widget.onSelectService(item.id)
                  : null,
              leadingIcon: AccountBrandMark(
                fallbackName: item.name,
                iconKey: item.brandKey,
                size: 18,
                active: item.enabled,
              ),
              trailingIcon: item.enabled
                  ? _selected(state.accountId == item.id)
                  : Tooltip(
                      message: l10n.acpConversationServiceDisabled,
                      child: const Icon(Icons.block_rounded, size: 16),
                    ),
              child: _label(item.name, width),
            ),
        ],
        if (filtered.isEmpty && services.isEmpty && !state.loading)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(l10n.composerModelSearchEmpty),
          ),
        if (state.failure case final failure?)
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: width - 24,
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
          onPressed: widget.onManageServices,
          child: Text(l10n.composerManageModels),
        ),
      ],
    );
  }

  Widget _label(String text, double width) => SizedBox(
    width: (width - 104).clamp(96.0, 280.0),
    child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
  );

  Widget _selected(bool selected) => SizedBox.square(
    dimension: 18,
    child: selected ? const Icon(Icons.check_rounded, size: 18) : null,
  );

  Widget _heading(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
    child: Text(
      text,
      style: context.text.labelSmall?.copyWith(
        color: context.colors.onSurfaceVariant,
      ),
    ),
  );
}
