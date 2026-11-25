import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../shell/sidebar/sidebar_views.dart';
import '../view_models/studio_update_view_model.dart';
import 'update_action_feedback.dart';

/// Binds the shared update ViewModel to the sidebar footer without shell logic.
class SidebarFooterConnector extends ConsumerWidget {
  const SidebarFooterConnector({
    super.key,
    required this.archived,
    required this.onToggleArchived,
    this.onSettings,
  });

  final bool archived;
  final VoidCallback onToggleArchived;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(studioUpdateViewModelProvider);
    return SidebarFooter(
      archived: archived,
      onToggleArchived: onToggleArchived,
      onSettings: onSettings,
      hasUpdate: state.hasUpdate,
      updateBusy: state.updateBusy,
      onUpdateNow: () => runStudioUpdateAction(
        context,
        ref.read(studioUpdateViewModelProvider.notifier).install,
      ),
    );
  }
}
