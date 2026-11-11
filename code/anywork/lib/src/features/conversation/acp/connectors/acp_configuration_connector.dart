import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../view_models/acp_configuration_view_model.dart';
import '../widgets/acp_configuration_bar.dart';

/// Thin Riverpod connector binding [AcpConfigurationViewModel] to the inline
/// composer [AcpConfigurationBar].
class AcpConfigurationConnector extends ConsumerWidget {
  const AcpConfigurationConnector({super.key, required this.threadId});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = acpConfigurationViewModelProvider(threadId);
    final state = ref.watch(provider);
    return AcpConfigurationBar(
      state: state,
      onSelectValue: (configId, valueId) =>
          unawaited(ref.read(provider.notifier).selectValue(configId, valueId)),
      onBooleanChanged: (configId, value) =>
          unawaited(ref.read(provider.notifier).setBoolean(configId, value)),
      onSelectLegacyMode: (modeId) =>
          unawaited(ref.read(provider.notifier).selectLegacyMode(modeId)),
    );
  }
}
