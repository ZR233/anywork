import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../state/acp_view_state.dart';
import '../view_models/acp_external_history_view_model.dart';
import '../views/acp_external_history_dialog.dart';

Future<void> showAcpExternalHistoryDialog(
  BuildContext context,
  String threadId,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => AcpExternalHistoryDialogConnector(threadId: threadId),
  );
}

/// Thin Riverpod connector binding [AcpExternalHistoryViewModel] (keyed strictly
/// by `String threadId`) to the pure [AcpExternalHistoryDialog].
class AcpExternalHistoryDialogConnector extends ConsumerStatefulWidget {
  const AcpExternalHistoryDialogConnector({super.key, required this.threadId});

  final String threadId;

  @override
  ConsumerState<AcpExternalHistoryDialogConnector> createState() =>
      _AcpExternalHistoryDialogConnectorState();
}

class _AcpExternalHistoryDialogConnectorState
    extends ConsumerState<AcpExternalHistoryDialogConnector> {
  bool _initialRefreshScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialRefreshScheduled) {
      _initialRefreshScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final state = ref.read(
          acpExternalHistoryViewModelProvider(widget.threadId),
        );
        if (state.availability == AcpExternalHistoryAvailability.available &&
            state.sessions.isEmpty &&
            !state.loading) {
          unawaited(
            ref
                .read(
                  acpExternalHistoryViewModelProvider(widget.threadId).notifier,
                )
                .refresh(),
          );
        }
      });
    }
  }

  Future<void> _openSession(String sessionId, {required bool resume}) async {
    final opened = await ref
        .read(acpExternalHistoryViewModelProvider(widget.threadId).notifier)
        .openSession(sessionId, resume: resume);
    if (opened && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = acpExternalHistoryViewModelProvider(widget.threadId);
    final state = ref.watch(provider);
    return AcpExternalHistoryDialog(
      state: state,
      onRefresh: () => unawaited(ref.read(provider.notifier).refresh()),
      onLoadMore: () => unawaited(ref.read(provider.notifier).loadMore()),
      onLoadSession: (sessionId) =>
          unawaited(_openSession(sessionId, resume: false)),
      onResumeSession: (sessionId) =>
          unawaited(_openSession(sessionId, resume: true)),
      onClose: () => Navigator.of(context).pop(),
    );
  }
}
