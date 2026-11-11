import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../view_models/acp_permission_view_model.dart';
import '../widgets/acp_permission_dock.dart';

/// Thin Riverpod connector binding [AcpPermissionViewModel] to the docked
/// [AcpPermissionDock] anchored directly above the composer.
class AcpPermissionConnector extends ConsumerWidget {
  const AcpPermissionConnector({super.key, required this.threadId});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = acpPermissionViewModelProvider(threadId);
    final state = ref.watch(provider);
    if (state.activeRequest == null) return const SizedBox.shrink();
    return AcpPermissionDock(
      state: state,
      onSelectOption: (permissionId, optionId) =>
          unawaited(ref.read(provider.notifier).answer(permissionId, optionId)),
      onCancel: (permissionId) =>
          unawaited(ref.read(provider.notifier).cancel(permissionId)),
    );
  }
}
