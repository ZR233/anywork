import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../state/acp_view_state.dart';
import '../view_models/acp_external_history_view_model.dart';
import '../view_models/acp_status_bar_view_model.dart';
import '../views/acp_status_bar_view.dart';
import 'acp_external_history_connector.dart';

/// Thin Riverpod connector binding [acpStatusBarViewModelProvider] and
/// [acpExternalHistoryButtonViewModelProvider] to [AcpStatusBarView].
class AcpStatusBarConnector extends ConsumerWidget {
  const AcpStatusBarConnector({super.key, required this.threadId});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(acpStatusBarViewModelProvider(threadId));
    final historyButton = ref.watch(
      acpExternalHistoryButtonViewModelProvider(threadId),
    );
    return AcpStatusBarView(
      threadId: threadId,
      state: state,
      externalHistoryButton: historyButton,
      onOpenExternalHistory:
          historyButton.status == AcpExternalHistoryAvailability.available
          ? () => unawaited(showAcpExternalHistoryDialog(context, threadId))
          : null,
    );
  }
}
