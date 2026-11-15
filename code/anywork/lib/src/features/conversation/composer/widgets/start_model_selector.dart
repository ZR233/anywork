import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/routing/app_route.dart';
import '../view_models/start_backend_view_model.dart';
import '../views/start_model_selector_view.dart';

class StartModelSelector extends ConsumerWidget {
  const StartModelSelector({required this.workspaceId, super.key});

  final String? workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = startBackendViewModelProvider(workspaceId);
    final state = ref.watch(provider);
    final actions = ref.read(provider.notifier);
    return StartModelSelectorView(
      state: state,
      onSelectModel: actions.selectModel,
      onSelectService: actions.select,
      onManageServices: () => const SettingsRoute().go(context),
    );
  }
}
