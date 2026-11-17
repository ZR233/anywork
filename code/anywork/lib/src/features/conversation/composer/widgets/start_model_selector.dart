import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/routing/app_route.dart';
import '../../../../shared/composer_configuration_bar.dart';
import '../view_models/start_backend_view_model.dart';
import '../views/start_model_selector_view.dart';

ComposerConfigurationEntry startModelConfigurationEntry({
  required Object id,
  required BuildContext context,
  required WidgetRef ref,
  required String? workspaceId,
}) {
  final provider = startBackendViewModelProvider(workspaceId);
  final state = ref.watch(provider);
  final actions = ref.read(provider.notifier);
  StartModelSelectorView selector(bool inMenu) => StartModelSelectorView(
    inMenu: inMenu,
    state: state,
    onSelectModel: actions.selectModel,
    onSelectService: actions.select,
    onManageServices: () => const SettingsRoute().go(context),
  );
  final inline = selector(false);
  return ComposerConfigurationEntry(
    id: id,
    inline: inline,
    measureInlineWidth: inline.measureInlineWidth,
    menuItem: selector(true),
  );
}
