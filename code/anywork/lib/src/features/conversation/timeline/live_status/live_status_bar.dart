import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'live_status_surface_view.dart';
import 'live_status_view_model.dart';

/// 底部实时状态栏薄连接层：直接将 [LiveStatusViewModel] 投影出的状态传入纯视图组件。
class LiveStatusBar extends ConsumerWidget {
  const LiveStatusBar({required this.threadId, super.key});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(liveStatusViewModelProvider(threadId));
    if (view == null) return const SizedBox.shrink();
    return LiveStatusSurfaceView(
      viewportKey: ValueKey(threadId),
      state: view.state,
    );
  }
}
