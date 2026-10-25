import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../view_models/statistics_view_model.dart';
import '../views/statistics_view.dart';

/// Connects shell-provided visibility to the SDK-only repository demand lease.
class StatisticsConnector extends ConsumerStatefulWidget {
  const StatisticsConnector({required this.visible, super.key});

  final bool visible;

  @override
  ConsumerState<StatisticsConnector> createState() =>
      _StatisticsConnectorState();
}

class _StatisticsConnectorState extends ConsumerState<StatisticsConnector> {
  @override
  void initState() {
    super.initState();
    _applyVisibility();
  }

  @override
  void didUpdateWidget(covariant StatisticsConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible) _applyVisibility();
  }

  void _applyVisibility() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(statisticsViewModelProvider.notifier).setVisible(widget.visible);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(statisticsViewModelProvider);
    final viewModel = ref.read(statisticsViewModelProvider.notifier);
    return StatisticsView(
      state: state,
      visible: widget.visible,
      onModelChanged: viewModel.selectModel,
      onEffortChanged: viewModel.selectEffort,
      onMismatchesOnlyChanged: viewModel.setMismatchesOnly,
      onRetry: viewModel.retry,
    );
  }
}
