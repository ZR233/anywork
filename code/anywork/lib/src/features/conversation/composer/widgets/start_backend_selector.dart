import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/routing/app_route.dart';
import '../../../../l10n/studio_l10n.dart';
import '../view_models/start_backend_view_model.dart';

class StartBackendSelector extends ConsumerWidget {
  const StartBackendSelector({required this.workspaceId, super.key});

  final String? workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final model = ref.watch(startBackendViewModelProvider(workspaceId));
    return MenuAnchor(
      builder: (context, controller, child) => TextButton.icon(
        onPressed: model.enabled
            ? () => controller.isOpen ? controller.close() : controller.open()
            : null,
        icon: const Icon(Icons.hub_outlined, size: 18),
        label: Text(
          model.accountId == null
              ? context.l10n.accountsTemplateNativeGroup
              : model.serviceName ?? model.accountId!,
        ),
      ),
      menuChildren: [
        MenuItemButton(
          onPressed: () => model.select(null),
          child: Text(context.l10n.accountsTemplateNativeGroup),
        ),
        const Divider(),
        if (model.loading)
          const Padding(
            padding: EdgeInsets.all(12),
            child: LinearProgressIndicator(),
          ),
        if (model.failure case final failure?)
          Padding(padding: const EdgeInsets.all(12), child: Text(failure)),
        for (final service in model.services)
          MenuItemButton(
            onPressed: service.enabled ? () => model.select(service.id) : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(service.name),
                Text(
                  service.enabled
                      ? service.id
                      : '${service.id} — ${context.l10n.acpConversationServiceDisabled}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        for (final diagnostic in model.diagnostics)
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: 320,
              child: Text('${diagnostic.fileName}: ${diagnostic.message}'),
            ),
          ),
        if (!model.loading && model.services.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(context.l10n.acpConversationNoServices),
          ),
        const Divider(),
        MenuItemButton(
          onPressed: () => const SettingsRoute().go(context),
          child: Text(context.l10n.acpConversationManageServices),
        ),
      ],
    );
  }
}
