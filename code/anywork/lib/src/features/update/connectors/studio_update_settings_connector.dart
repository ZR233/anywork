import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../l10n/studio_l10n.dart';
import '../view_models/studio_update_view_model.dart';
import '../views/studio_update_settings_view.dart';

class StudioUpdateSettingsConnector extends ConsumerWidget {
  const StudioUpdateSettingsConnector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(studioUpdateViewModelProvider);
    final viewModel = ref.read(studioUpdateViewModelProvider.notifier);
    return StudioUpdateSettingsView(
      state: state,
      onCheck: () => _runAction(context, viewModel.check),
      onInstall: () => _runAction(context, viewModel.install),
      onCancel: () => _runAction(context, viewModel.cancelInstall),
      onOpenReleaseNotes: viewModel.openReleaseNotes,
    );
  }

  Future<void> _runAction(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.settingsStudioUpdateFailed(error.toString()),
          ),
        ),
      );
    }
  }
}
