import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../view_models/studio_update_view_model.dart';
import '../views/studio_update_settings_view.dart';
import 'update_action_feedback.dart';

class StudioUpdateSettingsConnector extends ConsumerWidget {
  const StudioUpdateSettingsConnector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(studioUpdateViewModelProvider);
    final viewModel = ref.read(studioUpdateViewModelProvider.notifier);
    return StudioUpdateSettingsView(
      state: state,
      onCheck: () => runStudioUpdateAction(context, viewModel.check),
      onInstall: () => runStudioUpdateAction(context, viewModel.install),
      onCancel: () => runStudioUpdateAction(context, viewModel.cancelInstall),
      onOpenReleaseNotes: () =>
          runStudioUpdateAction(context, viewModel.openReleaseNotes),
    );
  }
}
