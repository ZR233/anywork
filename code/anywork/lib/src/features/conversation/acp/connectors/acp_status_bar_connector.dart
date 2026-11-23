import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../status/status_bar_item.dart';
import '../state/acp_view_state.dart';
import '../view_models/acp_external_history_view_model.dart';
import '../view_models/acp_status_bar_view_model.dart';
import '../views/acp_status_bar_view.dart';
import 'acp_external_history_connector.dart';

/// Stable identity and layout only; readouts own their subscriptions.
class AcpStatusBarConnector extends StatelessWidget {
  const AcpStatusBarConnector({super.key, required this.threadId});

  final String threadId;

  @override
  Widget build(BuildContext context) => AcpStatusBarView(
    status: AcpConnectionStatusConnector(threadId: threadId),
    contextUsage: AcpContextUsageConnector(threadId: threadId),
    cost: AcpCostConnector(threadId: threadId),
    throughput: _AcpThroughputConnector(threadId: threadId),
    externalHistory: AcpExternalHistoryButtonConnector(threadId: threadId),
  );
}

class _AcpThroughputConnector extends ConsumerWidget {
  const _AcpThroughputConnector({required this.threadId});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => TokenThroughputReadout(
    estimated: true,
    tokensPerSecond: ref.watch(acpThroughputViewModelProvider(threadId)),
  );
}

class AcpConnectionStatusConnector extends ConsumerWidget {
  const AcpConnectionStatusConnector({super.key, required this.threadId});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => AcpConnectionStatusView(
    state: ref.watch(acpStatusBarViewModelProvider(threadId)),
  );
}

class AcpContextUsageConnector extends ConsumerWidget {
  const AcpContextUsageConnector({super.key, required this.threadId});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => AcpContextUsageView(
    state: ref.watch(acpContextUsageViewModelProvider(threadId)),
    threadId: threadId,
    detailBuilder: (_) => _AcpContextDetailConnector(threadId: threadId),
  );
}

class _AcpContextDetailConnector extends ConsumerWidget {
  const _AcpContextDetailConnector({required this.threadId});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => AcpContextDetailView(
    state: ref.watch(acpContextDetailViewModelProvider(threadId)),
  );
}

class AcpCostConnector extends ConsumerWidget {
  const AcpCostConnector({super.key, required this.threadId});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      AcpCostReadoutView(state: ref.watch(acpCostViewModelProvider(threadId)));
}

class AcpExternalHistoryButtonConnector extends ConsumerWidget {
  const AcpExternalHistoryButtonConnector({super.key, required this.threadId});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(
      acpExternalHistoryButtonViewModelProvider(threadId),
    );
    return AcpExternalHistoryButtonView(
      threadId: threadId,
      state: state,
      onOpen: state.status == AcpExternalHistoryAvailability.available
          ? () => unawaited(showAcpExternalHistoryDialog(context, threadId))
          : null,
    );
  }
}
