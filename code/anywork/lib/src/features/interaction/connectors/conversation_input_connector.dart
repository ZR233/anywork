import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/studio_l10n.dart';
import '../../conversation/conversation.dart';
import '../../conversation/state/conversation_view_state.dart';
import '../../conversation/view_models/conversation_view_model.dart';
import '../../conversation/widgets/conversation_stop_control.dart';
import '../../status/status.dart';
import '../view_models/session_options_view_model.dart';
import '../views/conversation_input_view.dart';
import '../views/input_model_controls_view.dart';
import '../views/session_route_operation_view.dart';

/// The Smart ConversationScreen remains the sole Stop page-lifetime owner.
/// It supplies captureStop(page) and stopStateFor(page), retiring/deferStopPage
/// on cover/unmount. This connector never obtains a ticket or sends Stop via D1.
class ConversationInputConnector extends ConsumerWidget {
  const ConversationInputConnector({
    required this.threadId,
    required this.onStop,
    required this.stopState,
    this.compact = false,
    super.key,
  });
  final String threadId;
  final VoidCallback? onStop;
  final ConversationStopState? stopState;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = conversationViewModelProvider(threadId);
    final value = ref.watch(provider);
    final vm = ref.read(provider.notifier);
    return value.when(
      loading: () => const LinearProgressIndicator(),
      error: (error, stack) => Text(error.toString()),
      data: (state) => ConversationInputView(
        retired: state.retiredPlanner,
        runtimeDriven: state.runtimeDriven,
        interactionVisible: state.visibleEditors.isNotEmpty,
        interactionReopenable: state.currentEditors.isNotEmpty,
        interactionPending: (state.pendingInteractionCount ?? 0) > 0,
        onReopen: vm.reopenCurrentEditors,
        stopControl: ConversationStopControl(
          state: stopState,
          onStop: state.retiredPlanner ? null : onStop,
          primaryAction: vm.primaryAction(
            hasContent: false,
            submissionPending: false,
          ),
        ),
        composer: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ComposerConnector(
              target: vm.composerTarget,
              compact: compact,
              onStop: state.retiredPlanner ? null : onStop,
              stopState: stopState,
            ),
            ConversationModelRouteConnector(
              threadId: threadId,
              builder: (props, write, retryRead) =>
                  _ConversationRouteControlsConnector(
                    threadId: threadId,
                    props: props,
                    write: write,
                    retryRead: retryRead,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationRouteControlsConnector extends ConsumerWidget {
  const _ConversationRouteControlsConnector({
    required this.threadId,
    required this.props,
    required this.write,
    required this.retryRead,
  });
  final String threadId;
  final ConversationModelRouteProps props;
  final ThreadModelRouteWriter? write;
  final Future<void> Function() retryRead;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogValue = ref.watch(selectorCatalogViewModelProvider);
    final catalog = catalogValue.value;
    // Live route operations cannot share a presentation lane with Start's
    // project defaults, even when a caller supplies equal opaque ID strings.
    final provider = sessionOptionsViewModelProvider(
      'thread:${jsonEncode([threadId, props.source.runtimeEpoch, props.source.incarnation, props.source.generation])}',
    );
    final options = ref.watch(provider).value;
    final vm = ref.read(provider.notifier);
    final thread = props.thread;
    final route = props.route;
    final descriptor = catalog == null || route == null
        ? null
        : selectedDescriptor(catalog.models, route.accountId, route.modelId);
    final writer = write;
    final enabled = writer != null && options != null && !options.pending;
    final blockedReason = switch (props.blocked) {
      ModelRouteEditBlock.running => context.l10n.statusModelSwitchWhileRunning,
      ModelRouteEditBlock.inactive =>
        context.l10n.statusModelSwitchWhileInactive,
      ModelRouteEditBlock.frozen ||
      ModelRouteEditBlock.botManaged => context.l10n.delegationFrozen,
      ModelRouteEditBlock.unavailable =>
        props.error?.message ?? context.l10n.workspaceLoading,
      null => null,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (thread != null)
          InputModelControlsView(
            modes: catalog == null ? const [] : selectorModes(catalog),
            models: catalog == null ? const [] : selectorModels(catalog),
            efforts: descriptor?.reasoning?.candidates ?? const [],
            mode: thread.mode,
            modeEnabled: false,
            workspaceMode: thread.workspaceMode,
            showWorkspace: false,
            accountId: route?.accountId ?? '',
            modelId: route?.modelId ?? '',
            effort: route?.effort,
            enabled: enabled,
            blockedReason: blockedReason,
            unavailableReason: route?.available == false
                ? route?.unavailableReason ??
                      context.l10n.statusModelRouteUnavailableFallback
                : null,
            explanation: options?.explanation,
            onExplain: vm.explain,
            onDismiss: () => vm.explain(null),
            onModel: writer == null || route == null
                ? null
                : (model) {
                    vm.explain(null);
                    unawaited(
                      vm.chooseThreadModel(
                        accountId: model.accountId,
                        modelId: model.modelId,
                        current: route,
                        write: writer,
                      ),
                    );
                  },
            onEffort: writer == null || route == null
                ? null
                : (effort) => unawaited(
                    vm.chooseThreadEffort(
                      effort: effort,
                      current: route,
                      write: writer,
                    ),
                  ),
          ),
        SessionRouteOperationView(
          state: options,
          attempted: vm.attemptedThreadRoute,
          reading: props.reading,
          readError: props.error,
          onRetryRead: () => unawaited(retryRead()),
          onRetry: writer != null && vm.canRetryThreadRoute
              ? () => unawaited(vm.retryThreadRoute(writer))
              : null,
        ),
        if (catalogValue.isLoading || catalog?.reading.isNotEmpty == true)
          const LinearProgressIndicator(),
        if (catalogValue.hasError) Text(catalogValue.error.toString()),
        if (catalog != null) ...[
          for (final error in catalog.errors.values) Text(error.message),
          if (catalog.configuration.projection.sync.error case final error?)
            Text(error.message),
          if (catalog.models.projection.sync.error case final error?)
            Text(error.message),
          if (catalog.modes.projection.sync.error case final error?)
            Text(error.message),
        ],
        TextButton(
          onPressed: catalog == null || catalog.reading.isNotEmpty
              ? null
              : () => unawaited(
                  ref
                      .read(selectorCatalogViewModelProvider.notifier)
                      .loadMore(),
                ),
          child: Text(MaterialLocalizations.of(context).moreButtonTooltip),
        ),
      ],
    );
  }
}
