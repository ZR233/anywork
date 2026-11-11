import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../view_models/acp_start_composer_view_model.dart';
import '../views/acp_start_composer_view.dart';

/// Thin Riverpod connector binding [AcpStartComposerViewModel] to the pure
/// [AcpStartComposerView] start-page creation card.
class AcpStartComposerConnector extends ConsumerWidget {
  const AcpStartComposerConnector({super.key, required this.workspaceId});

  final String workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = acpStartComposerViewModelProvider(workspaceId);
    final state = ref.watch(provider);
    return AcpStartComposerView(
      state: state,
      onDraftChanged: ref.read(provider.notifier).updateDraft,
      onSubmit: () => unawaited(ref.read(provider.notifier).submit()),
    );
  }
}
