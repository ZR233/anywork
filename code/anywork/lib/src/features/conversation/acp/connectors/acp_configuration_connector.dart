import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../view_models/acp_conversation_view_model.dart';
import '../widgets/acp_configuration_panel.dart';

class AcpConfigurationConnector extends ConsumerWidget {
  const AcpConfigurationConnector({super.key, required this.threadId});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(acpConfigurationViewModelProvider(threadId));
    final actions = ref.watch(acpConversationActionsProvider(threadId));
    if (state.options?.isEmpty != false &&
        (state.options != null || state.modes == null)) {
      return const SizedBox.shrink();
    }
    final panel = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (state.error != null) Text('配置失败：${state.error}。请重新选择配置后再发送。'),
        AcpConfigurationPanel(
          options: state.options,
          modes: state.modes,
          pending: state.pending,
          enabled: state.enabled,
          onConfigure: (id, value) => unawaited(actions.configure(id, value)),
          onMode: (id) => unawaited(actions.setMode(id)),
        ),
      ],
    );
    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (context, constraints) => ExpansionTile(
          key: PageStorageKey(('acp-settings', threadId)),
          tilePadding: EdgeInsets.zero,
          initiallyExpanded: constraints.maxWidth >= 640,
          title: Text(constraints.maxWidth < 640 ? '更多设置' : '会话配置'),
          children: [panel],
        ),
      ),
    );
  }
}
