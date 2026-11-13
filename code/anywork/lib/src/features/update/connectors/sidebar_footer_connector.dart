import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../l10n/studio_l10n.dart';
import '../../shell/sidebar/sidebar_views.dart';
import '../view_models/studio_update_view_model.dart';

/// Binds the shared update ViewModel to the sidebar footer without shell logic.
class SidebarFooterConnector extends ConsumerWidget {
  const SidebarFooterConnector({
    super.key,
    required this.archived,
    required this.onToggleArchived,
    this.onSettings,
    this.touchMode = false,
  });

  final bool archived;
  final VoidCallback onToggleArchived;
  final VoidCallback? onSettings;
  final bool touchMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(studioUpdateViewModelProvider);
    return SidebarFooter(
      archived: archived,
      onToggleArchived: onToggleArchived,
      onSettings: onSettings,
      hasUpdate: state.hasUpdate,
      updateBusy: state.updateBusy,
      touchMode: touchMode,
      onUpdateNow: () => _runInstall(context, ref),
    );
  }

  Future<void> _runInstall(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(studioUpdateViewModelProvider.notifier).install();
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
